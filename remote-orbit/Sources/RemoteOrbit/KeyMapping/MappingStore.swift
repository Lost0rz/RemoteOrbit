// MappingStore.swift — 通用映射与 App 模板映射
//
// 通用映射适用于所有 App。每个 App 可以拥有多个模板，但同一个 App
// 同时只有一个激活模板；如果没有激活模板，就回退到通用映射。

import AppKit
import Combine
import Foundation
import ApplicationServices

/// 一个 App 的完整按键映射模板。
struct AppMappingTemplate: Codable, Equatable, Identifiable {
    let id: UUID
    var appBundleIdentifier: String
    var appName: String
    var templateName: String
    var bindings: [RemoteButton: ButtonBinding]
    /// Optional for backward-compatible decoding of templates saved before
    /// advanced button gestures existed.
    var gestureProfiles: [RemoteButton: ButtonGestureProfile]?

    init(
        id: UUID = UUID(),
        appBundleIdentifier: String,
        appName: String,
        templateName: String,
        bindings: [RemoteButton: ButtonBinding] = DefaultBindings.all,
        gestureProfiles: [RemoteButton: ButtonGestureProfile]? = nil
    ) {
        self.id = id
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.templateName = templateName
        self.bindings = bindings
        self.gestureProfiles = gestureProfiles
    }

    var displayName: String {
        "\(appName) · \(templateName)"
    }
}

/// The application-routing decision captured for one physical button press.
/// Diagnostic fields explain a global fallback without resolving focus again
/// during the same press.
struct ApplicationRouteSnapshot: Equatable {
    let bundleIdentifier: String?
    let source: String
    let focusedBundleIdentifier: String?
    let frontmostBundleIdentifier: String?
    let cachedBundleIdentifier: String?
}

private struct PersistedMappingConfiguration: Codable {
    /// Added for the file-backed configuration. Missing in older v3
    /// UserDefaults payloads, which decode as version 0 and are migrated
    /// without changing their user-owned values.
    var schemaVersion: Int?
    var globalBindings: [RemoteButton: ButtonBinding]
    // Optional so configurations created before per-button global pinning was
    // added can still be decoded.
    var globallyPinnedButtons: [RemoteButton]?
    // Optional so v3 configurations written before per-gesture global
    // inheritance was introduced can still be decoded.
    var globallyPinnedSlots: [GlobalMappingKey]?
    var appTemplates: [AppMappingTemplate]
    var activeTemplateIDs: [String: UUID]
    // Optional so configurations created before the scroll setting was added
    // can still be decoded.
    var scrollLinesPerStep: Int?
    // Optional so v3 configurations created before advanced button gestures
    // existed can still be decoded without changing any existing bindings.
    var globalGestureProfiles: [RemoteButton: ButtonGestureProfile]?
}

final class MappingStore: ObservableObject {
    private static let storageKey = "RemoteOrbit.mappingConfiguration.v3"
    private static let legacyStorageKey = "RemoteOrbit.buttonBindings.v2"
    private static let currentConfigurationSchemaVersion = 1
    /// Codex 的 Bundle ID。保留旧常量名只用于读取旧版配置代码，设置界面
    /// 和新模板统一使用 Codex 命名。
    static let codexBundleIdentifier = "com.openai.codex"
    static let chatGPTBundleIdentifier = codexBundleIdentifier
    static let floatTabsBundleIdentifier = "com.lost0rz.FloatTabs"
    static let defaultScrollLinesPerStep = 6
    static let scrollLinesPerStepRange = 1...40
    static let defaultGloballyPinnedButtons: Set<RemoteButton> = []
    static let defaultGloballyPinnedSlots: Set<GlobalMappingKey> = Set(
        defaultGloballyPinnedButtons.flatMap { button in
            GlobalMappingSlot.allCases.map { GlobalMappingKey(button: button, slot: $0) }
        }
    )
    /// The remote microphone is a dedicated long-press behavior. Keep this
    /// fallback available for old templates that have no gesture profile yet.
    static let defaultMicrophoneGestureProfile = ButtonGestureProfile(
        longPress: .voiceKeyDefault,
        longPressBehavior: .triggerOnce,
        longPressEnabled: true
    )
    private static let routingLock = NSLock()
    private static var lastExternalApplicationBundleIdentifier: String?

    /// 通用映射：没有匹配的 App 激活模板时使用。
    @Published var bindings: [RemoteButton: ButtonBinding] = DefaultBindings.all {
        didSet { save() }
    }

    /// Extra gesture profiles for the global scope. An absent entry is the
    /// exact legacy behavior; the settings UI creates an entry only when the
    /// user enables or edits advanced gestures.
    @Published private(set) var globalGestureProfiles: [RemoteButton: ButtonGestureProfile] = [:] {
        didSet { save() }
    }

    /// Individual behaviors can inherit the corresponding global mapping even
    /// when the foreground App has an active template. This is intentionally
    /// finer grained than the old whole-button pinning set.
    @Published private(set) var globallyPinnedSlots: Set<GlobalMappingKey> =
        MappingStore.defaultGloballyPinnedSlots

    /// 所有 App 模板。一个 App 可以有多个模板。
    @Published private(set) var appTemplates: [AppMappingTemplate] = [] {
        didSet { save() }
    }

    /// Bundle ID → 激活模板 ID。每个 App 最多一个激活模板。
    @Published private(set) var activeTemplateIDs: [String: UUID] = [:] {
        didSet { save() }
    }

    /// A non-nil value means the last configuration load was recovered in
    /// memory instead of overwriting the stored bytes.
    @Published private(set) var configurationWarning: String?

    /// 每次向上/向下滚屏事件发送的滚轮行数。数值越大，单次和长按滚动都越快。
    @Published var scrollLinesPerStep: Int = MappingStore.defaultScrollLinesPerStep {
        didSet {
            let clamped = Self.clampedScrollLinesPerStep(scrollLinesPerStep)
            if scrollLinesPerStep != clamped {
                scrollLinesPerStep = clamped
                return
            }
            save()
        }
    }

    /// 按下时锁定的映射快照。这样即使快捷键切换/退出前台 App，松开和重复
    /// 事件仍然使用同一套映射，不会发送错模板或留下修饰键状态。
    private var pressedBindings: [RemoteButton: ButtonBinding] = [:]

    /// Gesture profile captured alongside the base binding at button-down.
    /// This prevents a template/focus change during a hold from changing the
    /// meaning of the pending long-press or repeat gesture.
    private var pressedGestureProfiles: [RemoteButton: ButtonGestureProfile] = [:]

    /// 与映射快照配套锁定目标 App。FloatTabs 是浮动窗口，不能在按键的
    /// down/up 或 repeat 边沿重新读取 frontmostApplication，否则窗口短暂
    /// 激活时会把同一个物理按键路由到另一个模板。
    private var pressedApplicationBundleIDs: [RemoteButton: String] = [:]

    private var hasLoaded = false
    /// Prevent didSet observers from persisting a fallback while load() is
    /// still deciding whether the existing configuration is recoverable.
    private var isLoading = false
    private let configurationFileURL: URL
    private let userDefaults: UserDefaults

    init(
        configurationFileURL: URL = AppStorage.mappingConfigurationFile,
        userDefaults: UserDefaults = .standard
    ) {
        self.configurationFileURL = configurationFileURL
        self.userDefaults = userDefaults
        load()
    }

    // MARK: - 通用与模板查询

    /// 获取通用映射。
    func binding(for button: RemoteButton) -> ButtonBinding {
        bindings[button] ?? DefaultBindings.all[button] ?? .preset(.disabled)
    }

    /// 获取指定模板中的映射。
    func binding(for button: RemoteButton, templateID: UUID) -> ButtonBinding {
        guard let template = template(withID: templateID) else {
            return binding(for: button)
        }
        return template.bindings[button]
            ?? DefaultBindings.all[button]
            ?? .preset(.disabled)
    }

    /// 根据前台 App 选择实际生效的映射；没有激活模板时回退到通用映射。
    func binding(for button: RemoteButton, appBundleIdentifier: String?) -> ButtonBinding {
        if isGloballyPinned(button, slot: .single) {
            return binding(for: button)
        }
        guard let template = activeTemplate(for: appBundleIdentifier) else {
            return binding(for: button)
        }
        return template.bindings[button]
            ?? DefaultBindings.all[button]
            ?? .preset(.disabled)
    }

    /// Get the global-scope gesture profile for a button.
    func gestureProfile(for button: RemoteButton) -> ButtonGestureProfile {
        if let profile = globalGestureProfiles[button] {
            return profile
        }
        return button == .microphone
            ? Self.defaultMicrophoneGestureProfile
            : .disabled
    }

    /// Get the gesture profile in a specific template. A configured App
    /// template is its own mapping scope, so an absent profile means the
    /// feature is disabled there rather than inheriting a global gesture.
    func gestureProfile(for button: RemoteButton, templateID: UUID) -> ButtonGestureProfile {
        guard let template = template(withID: templateID) else {
            return gestureProfile(for: button)
        }
        return template.gestureProfiles?[button]
            ?? (button == .microphone
                ? Self.defaultMicrophoneGestureProfile
                : .disabled)
    }

    /// Resolve the active profile using the same App-template precedence as
    /// ordinary bindings. Global pinning applies to gestures as well.
    func gestureProfile(
        for button: RemoteButton,
        appBundleIdentifier: String?
    ) -> ButtonGestureProfile {
        guard let template = activeTemplate(for: appBundleIdentifier) else {
            return gestureProfile(for: button)
        }
        let templateProfile = template.gestureProfiles?[button]
            ?? (button == .microphone
                ? Self.defaultMicrophoneGestureProfile
                : .disabled)
        return mergedGestureProfile(
            global: gestureProfile(for: button),
            template: templateProfile,
            button: button
        )
    }

    private func mergedGestureProfile(
        global: ButtonGestureProfile,
        template: ButtonGestureProfile,
        button: RemoteButton
    ) -> ButtonGestureProfile {
        Self.mergedGestureProfile(
            global: global,
            template: template,
            button: button,
            globallyPinnedSlots: globallyPinnedSlots
        )
    }

    static func mergedGestureProfile(
        global: ButtonGestureProfile,
        template: ButtonGestureProfile,
        button: RemoteButton,
        globallyPinnedSlots: Set<GlobalMappingKey>
    ) -> ButtonGestureProfile {
        var merged = template
        if globallyPinnedSlots.contains(
            GlobalMappingKey(button: button, slot: .doubleTap)
        ) {
            merged.doubleTapEnabled = global.doubleTapEnabled
            merged.doubleTap = global.doubleTap
        }
        if globallyPinnedSlots.contains(
            GlobalMappingKey(button: button, slot: .longPress)
        ) {
            merged.longPressEnabled = global.longPressEnabled
            merged.longPress = global.longPress
            merged.longPressBehavior = global.longPressBehavior
        }
        return merged
    }

    func template(withID id: UUID) -> AppMappingTemplate? {
        appTemplates.first { $0.id == id }
    }

    func templates(for appBundleIdentifier: String) -> [AppMappingTemplate] {
        appTemplates.filter { $0.appBundleIdentifier == appBundleIdentifier }
    }

    /// 获取当前 App 可导入的内置模板。
    func templatePresets(for appBundleIdentifier: String) -> [AppTemplatePreset] {
        AppTemplatePresetLibrary.presets(for: appBundleIdentifier)
    }

    func activeTemplate(for appBundleIdentifier: String?) -> AppMappingTemplate? {
        guard let appBundleIdentifier,
              let activeID = activeTemplateIDs[appBundleIdentifier]
        else { return nil }
        return appTemplates.first {
            $0.id == activeID && $0.appBundleIdentifier == appBundleIdentifier
        }
    }

    // MARK: - 运行时按键快照

    /// Resolve the current target once. For a normal external foreground app,
    /// NSWorkspace is the stable and cheap answer. Accessibility focus is only
    /// consulted when RemoteOrbit itself (or no app) is frontmost, which is the
    /// case where a floating panel/menu would otherwise hide the real target.
    static func preferredApplicationBundleIdentifier() -> String? {
        preferredApplicationRoute().bundleIdentifier
    }

    static func preferredApplicationRoute() -> ApplicationRouteSnapshot {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let focused: String?
        if frontmost == ownBundleIdentifier || frontmost == nil {
            focused = focusedApplicationBundleIdentifier()
        } else {
            focused = nil
        }

        routingLock.lock()
        let cachedExternal = lastExternalApplicationBundleIdentifier
        routingLock.unlock()

        let resolved = resolvedApplicationBundleIdentifier(
            focused: focused,
            frontmost: frontmost,
            cachedExternal: cachedExternal,
            ownBundleIdentifier: ownBundleIdentifier
        )

        let source: String
        if resolved == nil {
            source = "global"
        } else if resolved == frontmost,
                  frontmost != nil,
                  frontmost != ownBundleIdentifier {
            source = "frontmost"
        } else if resolved == focused,
                  focused != nil,
                  focused != ownBundleIdentifier {
            source = "accessibility-focus"
        } else if resolved == cachedExternal,
                  cachedExternal != nil,
                  cachedExternal != ownBundleIdentifier {
            source = "cached"
        } else {
            source = "resolved"
        }

        if let resolved,
           resolved != ownBundleIdentifier {
            routingLock.lock()
            lastExternalApplicationBundleIdentifier = resolved
            routingLock.unlock()
        }

        if focused == ownBundleIdentifier || frontmost == ownBundleIdentifier {
            print(
                "[MappingRoute] ignoredSelf=true focused=\(focused ?? "nil") "
                    + "frontmost=\(frontmost ?? "nil") "
                    + "cached=\(cachedExternal ?? "nil") "
                    + "resolved=\(resolved ?? "global") source=\(source)"
            )
        }
        return ApplicationRouteSnapshot(
            bundleIdentifier: resolved,
            source: source,
            focusedBundleIdentifier: focused,
            frontmostBundleIdentifier: frontmost,
            cachedBundleIdentifier: cachedExternal
        )
    }

    /// Resolves a target without ever returning the bridge itself. Keeping this
    /// decision pure makes the self-focus fallback testable and prevents a
    /// transient menu/settings activation from routing an App template to the
    /// global system-volume action.
    static func resolvedApplicationBundleIdentifier(
        focused: String?,
        frontmost: String?,
        cachedExternal: String?,
        ownBundleIdentifier: String?
    ) -> String? {
        // The actual external foreground app is the least ambiguous target.
        // In particular, stale Accessibility focus from a previous window must
        // not override the app the user has just selected. FloatTabs is also
        // covered here because its own app remains frontmost while its panel is
        // visible.
        if let frontmost,
           frontmost != ownBundleIdentifier {
            return frontmost
        }
        if let focused,
           focused != ownBundleIdentifier {
            return focused
        }
        if let cachedExternal,
           cachedExternal != ownBundleIdentifier {
            return cachedExternal
        }
        return nil
    }

    /// Returns whether this process actually owns the current foreground or
    /// Accessibility focus. Unlike `preferredApplicationBundleIdentifier`, it
    /// intentionally does not use the cached external target.
    static func isApplicationActuallyFocused(_ bundleIdentifier: String) -> Bool {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
            return true
        }
        return focusedApplicationBundleIdentifier() == bundleIdentifier
    }

    private static func focusedApplicationBundleIdentifier() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &processIdentifier) == .success,
              processIdentifier > 0,
              let application = NSRunningApplication(processIdentifier: processIdentifier)
        else { return nil }
        return application.bundleIdentifier
    }

    /// Prepare a complete press snapshot before HID debouncing.
    @discardableResult
    func preparePress(for button: RemoteButton) -> ButtonBinding {
        cancelPress(for: button)
        return beginPress(for: button)
    }

    /// 在按下边沿解析一次前台 App，并锁定该按键的映射。
    @discardableResult
    func beginPress(for button: RemoteButton) -> ButtonBinding {
        if let existing = pressedBindings[button] {
            return existing
        }

        let route = Self.preferredApplicationRoute()
        let bundleID = route.bundleIdentifier
        let binding = binding(for: button, appBundleIdentifier: bundleID)
        let gestureProfile = gestureProfile(
            for: button,
            appBundleIdentifier: bundleID
        )
        pressedBindings[button] = binding
        pressedGestureProfiles[button] = gestureProfile
        if let bundleID {
            pressedApplicationBundleIDs[button] = bundleID
        } else {
            pressedApplicationBundleIDs.removeValue(forKey: button)
        }

        if let bundleID, let template = activeTemplate(for: bundleID) {
            print(
                "[MappingStore] \(button.displayName) → \(template.displayName) "
                    + "[target=\(bundleID) source=\(route.source)]"
            )
        } else {
            print(
                "[MappingStore] \(button.displayName) → 通用映射 "
                    + "[target=\(bundleID ?? "unknown") source=\(route.source)]"
            )
        }
        return binding
    }

    /// Discard a prepared snapshot when HID rejects the corresponding down
    /// edge as bounce. The next real down edge will resolve a fresh target.
    func cancelPress(for button: RemoteButton) {
        pressedBindings.removeValue(forKey: button)
        pressedApplicationBundleIDs.removeValue(forKey: button)
        pressedGestureProfiles.removeValue(forKey: button)
    }

    /// 获取当前按住事件锁定的映射；没有快照时才重新读取前台 App。
    func activePressBinding(for button: RemoteButton) -> ButtonBinding {
        pressedBindings[button] ?? binding(
            for: button,
            appBundleIdentifier: Self.preferredApplicationBundleIdentifier()
        )
    }

    /// Get the advanced gesture profile captured on button-down.
    func activePressGestureProfile(for button: RemoteButton) -> ButtonGestureProfile {
        pressedGestureProfiles[button] ?? gestureProfile(
            for: button,
            appBundleIdentifier: Self.preferredApplicationBundleIdentifier()
        )
    }

    /// 获取当前按键按下时锁定的目标 App。用于诊断和需要区分 App 的动作。
    func activePressApplicationBundleIdentifier(for button: RemoteButton) -> String? {
        pressedApplicationBundleIDs[button]
            ?? Self.preferredApplicationBundleIdentifier()
    }

    /// 结束按键并返回按下时锁定的映射。
    @discardableResult
    func endPress(for button: RemoteButton) -> ButtonBinding {
        let binding = pressedBindings.removeValue(forKey: button)
            ?? activePressBinding(for: button)
        pressedApplicationBundleIDs.removeValue(forKey: button)
        pressedGestureProfiles.removeValue(forKey: button)
        return binding
    }

    func clearPressedBindings() {
        pressedBindings.removeAll()
        pressedApplicationBundleIDs.removeAll()
        pressedGestureProfiles.removeAll()
    }

    // MARK: - 通用映射修改

    /// 设置通用映射。
    func setBinding(_ binding: ButtonBinding, for button: RemoteButton) {
        bindings[button] = binding
    }

    /// Set or clear a global advanced gesture profile. Keeping disabled
    /// profiles in storage preserves the user's configured slots when they
    /// temporarily turn the feature off.
    func setGestureProfile(_ profile: ButtonGestureProfile, for button: RemoteButton) {
        var updated = globalGestureProfiles
        if profile == .disabled {
            updated.removeValue(forKey: button)
        } else {
            updated[button] = profile
        }
        guard updated != globalGestureProfiles else { return }
        globalGestureProfiles = updated
    }

    /// 重置通用映射。
    func resetAll() {
        performSaveBatch {
            bindings = DefaultBindings.all
            globalGestureProfiles.removeAll()
            globallyPinnedSlots = Self.defaultGloballyPinnedSlots
        }
    }

    /// Set whether every behavior of a button inherits the global mapping.
    func setGlobalPinning(_ isPinned: Bool, for button: RemoteButton) {
        var updated = globallyPinnedSlots
        for slot in GlobalMappingSlot.allCases {
            let key = GlobalMappingKey(button: button, slot: slot)
            if isPinned {
                updated.insert(key)
            } else {
                updated.remove(key)
            }
        }
        guard updated != globallyPinnedSlots else { return }
        globallyPinnedSlots = updated
        save()
    }

    /// Set whether one behavior of a button inherits the global mapping.
    func setGlobalPinning(
        _ isPinned: Bool,
        for button: RemoteButton,
        slot: GlobalMappingSlot
    ) {
        var updated = globallyPinnedSlots
        let key = GlobalMappingKey(button: button, slot: slot)
        if isPinned {
            updated.insert(key)
        } else {
            updated.remove(key)
        }
        guard updated != globallyPinnedSlots else { return }
        globallyPinnedSlots = updated
        save()
    }

    func isGloballyPinned(_ button: RemoteButton) -> Bool {
        GlobalMappingSlot.allCases.allSatisfy {
            isGloballyPinned(button, slot: $0)
        }
    }

    func isGloballyPinned(_ button: RemoteButton, slot: GlobalMappingSlot) -> Bool {
        globallyPinnedSlots.contains(GlobalMappingKey(button: button, slot: slot))
    }

    // MARK: - App 模板修改

    /// 新建模板。第一个模板自动成为该 App 的激活模板，后续模板需要手动激活。
    @discardableResult
    func addTemplate(
        appBundleIdentifier: String,
        appName: String,
        templateName: String
    ) -> UUID {
        let cleanName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = AppMappingTemplate(
            appBundleIdentifier: appBundleIdentifier,
            appName: appName,
            templateName: cleanName.isEmpty ? "默认模板" : cleanName,
            // 新模板从当前通用映射开始，之后可独立修改全部按钮。
            bindings: bindings
        )
        performSaveBatch {
            var updatedTemplates = appTemplates
            updatedTemplates.append(template)
            appTemplates = updatedTemplates
            if activeTemplateIDs[appBundleIdentifier] == nil {
                var updatedActiveIDs = activeTemplateIDs
                updatedActiveIDs[appBundleIdentifier] = template.id
                activeTemplateIDs = updatedActiveIDs
            }
        }
        print("[MappingStore] added template: \(template.displayName) [\(appBundleIdentifier)]")
        return template.id
    }

    /// 导入一个内置模板并立即设为该 App 的 Active 模板。
    /// 同名模板已经存在时保留用户现有修改，只切换 Active，不覆盖内容。
    @discardableResult
    func importTemplatePreset(
        _ presetID: String,
        for appBundleIdentifier: String,
        appName: String
    ) -> UUID? {
        guard let preset = AppTemplatePresetLibrary.preset(id: presetID),
              preset.appBundleIdentifier == appBundleIdentifier
        else { return nil }

        if let existing = appTemplates.first(where: {
            $0.appBundleIdentifier == appBundleIdentifier &&
            $0.templateName == preset.templateName
        }) {
            setActiveTemplate(existing.id)
            print("[MappingStore] activated existing preset template: \(existing.displayName)")
            return existing.id
        }

        let template = AppMappingTemplate(
            appBundleIdentifier: appBundleIdentifier,
            appName: appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? preset.appName
                : appName,
            templateName: preset.templateName,
            bindings: preset.bindings,
            gestureProfiles: preset.gestureProfiles
        )
        performSaveBatch {
            var updatedTemplates = appTemplates
            updatedTemplates.append(template)
            appTemplates = updatedTemplates

            var updatedActiveIDs = activeTemplateIDs
            updatedActiveIDs[appBundleIdentifier] = template.id
            activeTemplateIDs = updatedActiveIDs
        }
        print("[MappingStore] imported preset template: \(template.displayName)")
        return template.id
    }

    /// Explicit user action from Settings ("套用预设…" / preset importer):
    /// applies the preset's latest bindings & gestures even if a same-named
    /// template already exists, and sets it Active.
    @discardableResult
    func applyTemplatePreset(
        _ presetID: String,
        for appBundleIdentifier: String,
        appName: String
    ) -> UUID? {
        guard let preset = AppTemplatePresetLibrary.preset(id: presetID),
              preset.appBundleIdentifier == appBundleIdentifier
        else { return nil }

        let resolvedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preset.appName
            : appName

        if let existingIndex = appTemplates.firstIndex(where: {
            $0.appBundleIdentifier == appBundleIdentifier &&
            $0.templateName == preset.templateName
        }) {
            let existingID = appTemplates[existingIndex].id
            performSaveBatch {
                var updatedTemplates = appTemplates
                updatedTemplates[existingIndex].appName = resolvedAppName
                updatedTemplates[existingIndex].bindings = preset.bindings
                updatedTemplates[existingIndex].gestureProfiles = preset.gestureProfiles
                appTemplates = updatedTemplates

                var updatedActiveIDs = activeTemplateIDs
                updatedActiveIDs[appBundleIdentifier] = existingID
                activeTemplateIDs = updatedActiveIDs
            }
            print("[MappingStore] applied preset to existing template: \(preset.displayName)")
            return existingID
        }

        let template = AppMappingTemplate(
            appBundleIdentifier: appBundleIdentifier,
            appName: resolvedAppName,
            templateName: preset.templateName,
            bindings: preset.bindings,
            gestureProfiles: preset.gestureProfiles
        )
        performSaveBatch {
            var updatedTemplates = appTemplates
            updatedTemplates.append(template)
            appTemplates = updatedTemplates

            var updatedActiveIDs = activeTemplateIDs
            updatedActiveIDs[appBundleIdentifier] = template.id
            activeTemplateIDs = updatedActiveIDs
        }
        print("[MappingStore] applied new preset template: \(template.displayName)")
        return template.id
    }

    /// 设置某个 App 的激活模板。
    func setActiveTemplate(_ templateID: UUID) {
        guard let template = template(withID: templateID) else { return }
        guard template.appBundleIdentifier.isEmpty == false else { return }
        var updatedActiveIDs = activeTemplateIDs
        updatedActiveIDs[template.appBundleIdentifier] = templateID
        activeTemplateIDs = updatedActiveIDs
        print("[MappingStore] active template: \(template.displayName)")
    }

    /// 设置模板内某个按钮的映射。
    func setBinding(_ binding: ButtonBinding, for button: RemoteButton, templateID: UUID) {
        guard let index = appTemplates.firstIndex(where: { $0.id == templateID }) else { return }
        var updatedTemplates = appTemplates
        updatedTemplates[index].bindings[button] = binding
        appTemplates = updatedTemplates
    }

    /// Set or clear one template's advanced gesture profile.
    func setGestureProfile(
        _ profile: ButtonGestureProfile,
        for button: RemoteButton,
        templateID: UUID
    ) {
        guard let index = appTemplates.firstIndex(where: { $0.id == templateID }) else { return }
        var updatedTemplates = appTemplates
        var profiles = updatedTemplates[index].gestureProfiles ?? [:]
        if profile == .disabled {
            profiles.removeValue(forKey: button)
        } else {
            profiles[button] = profile
        }
        updatedTemplates[index].gestureProfiles = profiles.isEmpty ? nil : profiles
        appTemplates = updatedTemplates
    }

    /// 将当前模板恢复为系统默认映射。
    func resetTemplate(_ templateID: UUID) {
        guard let index = appTemplates.firstIndex(where: { $0.id == templateID }) else { return }
        var updatedTemplates = appTemplates
        let template = updatedTemplates[index]
        let matchingPreset = AppTemplatePresetLibrary.all.first(where: {
            $0.appBundleIdentifier == template.appBundleIdentifier &&
            $0.templateName == template.templateName
        })
        updatedTemplates[index].bindings = matchingPreset?.bindings ?? DefaultBindings.all
        updatedTemplates[index].gestureProfiles = matchingPreset?.gestureProfiles
        appTemplates = updatedTemplates
    }

    /// 删除模板。若删除的是激活模板，会自动激活同一 App 的另一个模板；
    /// 如果没有剩余模板，该 App 自动回退到通用映射。
    func deleteTemplate(_ templateID: UUID) {
        guard let index = appTemplates.firstIndex(where: { $0.id == templateID }) else { return }
        let bundleID = appTemplates[index].appBundleIdentifier
        let wasActive = activeTemplateIDs[bundleID] == templateID
        performSaveBatch {
            var updatedTemplates = appTemplates
            updatedTemplates.remove(at: index)
            appTemplates = updatedTemplates

            if wasActive {
                var updatedActiveIDs = activeTemplateIDs
                if let replacement = updatedTemplates.first(where: { $0.appBundleIdentifier == bundleID }) {
                    updatedActiveIDs[bundleID] = replacement.id
                } else {
                    updatedActiveIDs.removeValue(forKey: bundleID)
                }
                activeTemplateIDs = updatedActiveIDs
            }
        }
    }

    // MARK: - 配置导入与导出

    func exportCurrentConfiguration(to url: URL) throws {
        let data = try encodedCurrentConfiguration()
        try data.write(to: url, options: .atomic)
        print("[MappingStore] exported configuration: \(url.path)")
    }

    func importConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(PersistedMappingConfiguration.self, from: data)
        try replaceConfiguration(with: decoded, source: url.lastPathComponent)
    }

    // MARK: - 持久化

    private func load() {
        guard !hasLoaded else { return }

        isLoading = true
        configurationWarning = nil

        // The file is canonical. UserDefaults is consulted only as a one-time
        // compatibility source for installations created before the file-backed
        // store existed. Replacing the app bundle therefore cannot reset the
        // active configuration.
        if let data = try? Data(contentsOf: configurationFileURL) {
            if let decoded = decodeConfiguration(data, source: "file") {
                finishLoad(decoded, source: "file-backed configuration")
                return
            }
            configurationWarning = "配置文件无法读取，正在尝试兼容配置或恢复默认配置。"
        }

        if let data = userDefaults.data(forKey: Self.storageKey) {
            if let decoded = decodeConfiguration(data, source: "UserDefaults") {
                print("[MappingStore] migrating v3 UserDefaults payload to file-backed configuration")
                finishLoad(decoded, source: "migrated UserDefaults configuration")
                return
            }
            configurationWarning = "旧版配置也无法读取，正在恢复默认配置。"
        }

        // 兼容之前只保存全局映射的 v2 数据。
        if let data = userDefaults.data(forKey: Self.legacyStorageKey),
           let decoded = try? JSONDecoder().decode(
               [RemoteButton: ButtonBinding].self,
               from: data
           ) {
            print("[MappingStore] migrating v2 global bindings: \(decoded.count)")
            let migrated = PersistedMappingConfiguration(
                schemaVersion: Self.currentConfigurationSchemaVersion,
                globalBindings: Self.mergedBindings(decoded),
                globallyPinnedButtons: nil,
                globallyPinnedSlots: nil,
                appTemplates: [],
                activeTemplateIDs: [:],
                scrollLinesPerStep: Self.defaultScrollLinesPerStep,
                globalGestureProfiles: nil
            )
            finishLoad(migrated, source: "migrated v2 configuration")
            return
        }

        let initial = PersistedMappingConfiguration(
            schemaVersion: Self.currentConfigurationSchemaVersion,
            globalBindings: DefaultBindings.all,
            globallyPinnedButtons: nil,
            globallyPinnedSlots: nil,
            appTemplates: [],
            activeTemplateIDs: [:],
            scrollLinesPerStep: Self.defaultScrollLinesPerStep,
            globalGestureProfiles: nil
        )
        finishLoad(initial, source: "new user configuration")
    }

    private func decodeConfiguration(
        _ data: Data,
        source: String
    ) -> PersistedMappingConfiguration? {
        do {
            let configuration = try JSONDecoder().decode(
                PersistedMappingConfiguration.self,
                from: data
            )
            if let version = configuration.schemaVersion,
               version > Self.currentConfigurationSchemaVersion {
                print(
                    "[MappingStore] \(source) uses newer schema v\(version); "
                        + "current=\(Self.currentConfigurationSchemaVersion)"
                )
                return nil
            }
            return configuration
        } catch {
            print("[MappingStore] \(source) configuration decode failed: \(error)")
            return nil
        }
    }

    private func finishLoad(
        _ decoded: PersistedMappingConfiguration,
        source: String
    ) {
        apply(decoded)
        hasLoaded = true
        // This routine is additive only. Existing templates and profiles are
        // never rewritten as part of app launch or app-bundle replacement.
        ensureBuiltInTemplates()
        isLoading = false
        save()
        print(
            "[MappingStore] loaded \(source): global=\(bindings.count), "
                + "templates=\(appTemplates.count), scroll=\(scrollLinesPerStep) lines"
        )
    }

    private func apply(_ decoded: PersistedMappingConfiguration) {
        bindings = Self.mergedBindings(decoded.globalBindings)
        globalGestureProfiles = decoded.globalGestureProfiles ?? [:]
        if let slots = decoded.globallyPinnedSlots {
            globallyPinnedSlots = Set(slots)
        } else if let buttons = decoded.globallyPinnedButtons {
            globallyPinnedSlots = Set(
                buttons.flatMap { button in
                    GlobalMappingSlot.allCases.map {
                        GlobalMappingKey(button: button, slot: $0)
                    }
                }
            )
        } else {
            globallyPinnedSlots = Self.defaultGloballyPinnedSlots
        }
        appTemplates = decoded.appTemplates.map { template in
            var merged = template
            merged.bindings = Self.mergedBindings(template.bindings)
            return merged
        }
        activeTemplateIDs = decoded.activeTemplateIDs
        scrollLinesPerStep = Self.clampedScrollLinesPerStep(
            decoded.scrollLinesPerStep ?? Self.defaultScrollLinesPerStep
        )
    }

    private func replaceConfiguration(
        with decoded: PersistedMappingConfiguration,
        source: String
    ) throws {
        isLoading = true
        apply(decoded)
        hasLoaded = true
        ensureBuiltInTemplates()
        isLoading = false
        configurationWarning = nil
        save()
        print("[MappingStore] imported configuration: \(source)")
    }

    /// 首次升级到模板库版本时，为当前机器已安装的常用 App 提供默认模板。
    /// Existing templates are never migrated or rewritten automatically.
    /// This method is intentionally additive: it may provision a missing
    /// built-in template, but it never changes a user's existing template.
    private func ensureBuiltInTemplates() {
        ensureBuiltInCodexTemplate()

        for presetID in AppTemplatePresetLibrary.defaultPresetIDs {
            guard let preset = AppTemplatePresetLibrary.preset(id: presetID),
                  NSWorkspace.shared.urlForApplication(
                      withBundleIdentifier: preset.appBundleIdentifier
                  ) != nil,
                  !appTemplates.contains(where: {
                      $0.appBundleIdentifier == preset.appBundleIdentifier
                  })
            else { continue }

            _ = importTemplatePreset(
                presetID,
                for: preset.appBundleIdentifier,
                appName: preset.appName
            )
        }

        repairActiveTemplateIDs()
    }

    /// ChatGPT and Codex share the same bundle identifier, so Codex needs its
    /// own selectable template. Keep the existing active template untouched so
    /// an upgrade never overwrites a user's customized ChatGPT mapping.
    private func ensureBuiltInCodexTemplate() {
        guard let preset = AppTemplatePresetLibrary.preset(id: "codex.default") else {
            return
        }

        let alreadyExists = appTemplates.contains {
            $0.appBundleIdentifier == preset.appBundleIdentifier &&
            $0.templateName == preset.templateName
        }
        guard !alreadyExists else { return }

        let template = AppMappingTemplate(
            appBundleIdentifier: preset.appBundleIdentifier,
            appName: preset.appName,
            templateName: preset.templateName,
            bindings: preset.bindings,
            gestureProfiles: preset.gestureProfiles
        )
        appTemplates.append(template)
        print("[MappingStore] added built-in template: \(template.displayName)")
    }

    /// A template can survive a partial/older configuration migration while
    /// its active ID is missing or points to a deleted template. Repair that
    /// index deterministically, preserving an existing valid choice and using
    /// the first stored template only when no valid choice remains.
    private func repairActiveTemplateIDs() {
        let repaired = Self.repairedActiveTemplateIDs(
            activeTemplateIDs,
            templates: appTemplates
        )
        guard repaired != activeTemplateIDs else { return }
        activeTemplateIDs = repaired
        print("[MappingStore] repaired active template index")
    }

    static func repairedActiveTemplateIDs(
        _ activeTemplateIDs: [String: UUID],
        templates: [AppMappingTemplate]
    ) -> [String: UUID] {
        var repaired = activeTemplateIDs
        let bundleIDs = Set(templates.map(\.appBundleIdentifier))

        for bundleID in bundleIDs {
            let activeID = repaired[bundleID]
            let activeIsValid = activeID.flatMap { id in
                templates.first {
                    $0.id == id && $0.appBundleIdentifier == bundleID
                }
            } != nil

            guard !activeIsValid,
                  let replacement = templates.first(where: {
                      $0.appBundleIdentifier == bundleID
                  }) else { continue }
            repaired[bundleID] = replacement.id
        }

        for bundleID in Array(repaired.keys) where !bundleIDs.contains(bundleID) {
            repaired.removeValue(forKey: bundleID)
        }
        return repaired
    }

    private static func mergedBindings(_ decoded: [RemoteButton: ButtonBinding]) -> [RemoteButton: ButtonBinding] {
        var merged = DefaultBindings.all
        for (button, binding) in decoded {
            merged[button] = binding
        }
        return merged
    }

    private static func clampedScrollLinesPerStep(_ value: Int) -> Int {
        min(max(value, scrollLinesPerStepRange.lowerBound), scrollLinesPerStepRange.upperBound)
    }

    private var isBatchingMutations = false

    private func performSaveBatch<T>(_ body: () -> T) -> T {
        let wasBatching = isBatchingMutations
        isBatchingMutations = true
        defer {
            isBatchingMutations = wasBatching
            if !wasBatching {
                save()
            }
        }
        return body()
    }

    private func save() {
        guard hasLoaded, !isLoading, !isBatchingMutations else { return }
        do {
            let data = try encodedCurrentConfiguration()
            let canonicalURL = configurationFileURL
            AppStorage.ensureDirectory(canonicalURL.deletingLastPathComponent())
            try data.write(to: canonicalURL, options: .atomic)
            // Keep a compatibility mirror so an older signed build can still
            // start with the latest user configuration. The file above remains
            // the source of truth for current builds.
            userDefaults.set(data, forKey: Self.storageKey)
            print("[MappingStore] saved canonical configuration: \(canonicalURL.path)")
        } catch {
            print("[MappingStore] save failed: \(error)")
        }
    }

    private func encodedCurrentConfiguration() throws -> Data {
        let configuration = PersistedMappingConfiguration(
            schemaVersion: Self.currentConfigurationSchemaVersion,
            globalBindings: bindings,
            globallyPinnedButtons: legacyGloballyPinnedButtons.sorted {
                $0.rawValue < $1.rawValue
            },
            globallyPinnedSlots: globallyPinnedSlots.sorted {
                if $0.button.rawValue != $1.button.rawValue {
                    return $0.button.rawValue < $1.button.rawValue
                }
                return $0.slot.rawValue < $1.slot.rawValue
            },
            appTemplates: appTemplates,
            activeTemplateIDs: activeTemplateIDs,
            scrollLinesPerStep: scrollLinesPerStep,
            globalGestureProfiles: globalGestureProfiles.isEmpty
                ? nil
                : globalGestureProfiles
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(configuration)
    }

    private var legacyGloballyPinnedButtons: Set<RemoteButton> {
        Set(RemoteButton.allCases.filter { isGloballyPinned($0) })
    }

}
