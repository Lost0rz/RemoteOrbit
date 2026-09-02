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

struct MappingBackup: Identifiable, Equatable {
    let url: URL
    let modifiedAt: Date

    var id: String { url.path }
    var fileName: String { url.lastPathComponent }
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

enum MappingStoreError: LocalizedError {
    case backupFailed

    var errorDescription: String? {
        switch self {
        case .backupFailed:
            return "无法创建当前配置备份，已取消本次导入或恢复。"
        }
    }
}

private struct PersistedMappingConfiguration: Codable {
    var globalBindings: [RemoteButton: ButtonBinding]
    // Optional so configurations created before per-button global pinning was
    // added can still be decoded.
    var globallyPinnedButtons: Set<RemoteButton>?
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
    private static let previousBackupFileName = "mapping-v3.previous.json"
    /// Codex 的 Bundle ID。保留旧常量名只用于读取旧版配置代码，设置界面
    /// 和新模板统一使用 Codex 命名。
    static let codexBundleIdentifier = "com.openai.codex"
    static let chatGPTBundleIdentifier = codexBundleIdentifier
    static let floatTabsBundleIdentifier = "com.lost0rz.FloatTabs"
    static let defaultScrollLinesPerStep = 6
    static let scrollLinesPerStepRange = 1...40
    static let defaultGloballyPinnedButtons: Set<RemoteButton> = [.home]
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

    /// These buttons always use the corresponding global binding, even when
    /// the foreground App has an active template.
    @Published private(set) var globallyPinnedButtons: Set<RemoteButton> = [.home]

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

    init() {
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
        if globallyPinnedButtons.contains(button) {
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
        globalGestureProfiles[button] ?? .disabled
    }

    /// Get the gesture profile in a specific template. A configured App
    /// template is its own mapping scope, so an absent profile means the
    /// feature is disabled there rather than inheriting a global gesture.
    func gestureProfile(for button: RemoteButton, templateID: UUID) -> ButtonGestureProfile {
        guard let template = template(withID: templateID) else {
            return gestureProfile(for: button)
        }
        return template.gestureProfiles?[button] ?? .disabled
    }

    /// Resolve the active profile using the same App-template precedence as
    /// ordinary bindings. Global pinning applies to gestures as well.
    func gestureProfile(
        for button: RemoteButton,
        appBundleIdentifier: String?
    ) -> ButtonGestureProfile {
        if globallyPinnedButtons.contains(button) {
            return gestureProfile(for: button)
        }
        guard let template = activeTemplate(for: appBundleIdentifier) else {
            return gestureProfile(for: button)
        }
        return template.gestureProfiles?[button] ?? .disabled
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

    func isActiveTemplate(_ templateID: UUID) -> Bool {
        guard let template = template(withID: templateID) else { return false }
        return activeTemplateIDs[template.appBundleIdentifier] == templateID
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
        bindings = DefaultBindings.all
        globalGestureProfiles.removeAll()
        globallyPinnedButtons.removeAll()
        save()
    }

    /// 设置某个按钮是否由通用映射接管所有 App 场景。
    func setGlobalPinning(_ isPinned: Bool, for button: RemoteButton) {
        var updated = globallyPinnedButtons
        if isPinned {
            updated.insert(button)
        } else {
            updated.remove(button)
        }
        guard updated != globallyPinnedButtons else { return }
        globallyPinnedButtons = updated
        save()
    }

    func isGloballyPinned(_ button: RemoteButton) -> Bool {
        globallyPinnedButtons.contains(button)
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
        var updatedTemplates = appTemplates
        updatedTemplates.append(template)
        appTemplates = updatedTemplates
        if activeTemplateIDs[appBundleIdentifier] == nil {
            var updatedActiveIDs = activeTemplateIDs
            updatedActiveIDs[appBundleIdentifier] = template.id
            activeTemplateIDs = updatedActiveIDs
        }
        save()
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
        var updatedTemplates = appTemplates
        updatedTemplates.append(template)
        appTemplates = updatedTemplates

        var updatedActiveIDs = activeTemplateIDs
        updatedActiveIDs[appBundleIdentifier] = template.id
        activeTemplateIDs = updatedActiveIDs
        save()
        print("[MappingStore] imported preset template: \(template.displayName)")
        return template.id
    }

    /// 设置某个 App 的激活模板。
    func setActiveTemplate(_ templateID: UUID) {
        guard let template = template(withID: templateID) else { return }
        guard template.appBundleIdentifier.isEmpty == false else { return }
        var updatedActiveIDs = activeTemplateIDs
        updatedActiveIDs[template.appBundleIdentifier] = templateID
        activeTemplateIDs = updatedActiveIDs
        save()
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
        let builtInBindings = AppTemplatePresetLibrary.all.first(where: {
            $0.appBundleIdentifier == template.appBundleIdentifier &&
            $0.templateName == template.templateName
        })?.bindings
        updatedTemplates[index].bindings = builtInBindings ?? DefaultBindings.all
        updatedTemplates[index].gestureProfiles = AppTemplatePresetLibrary.all.first(where: {
            $0.appBundleIdentifier == template.appBundleIdentifier &&
            $0.templateName == template.templateName
        })?.gestureProfiles
        appTemplates = updatedTemplates
    }

    /// 删除模板。若删除的是激活模板，会自动激活同一 App 的另一个模板；
    /// 如果没有剩余模板，该 App 自动回退到通用映射。
    func deleteTemplate(_ templateID: UUID) {
        guard let index = appTemplates.firstIndex(where: { $0.id == templateID }) else { return }
        let bundleID = appTemplates[index].appBundleIdentifier
        let wasActive = activeTemplateIDs[bundleID] == templateID
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
        save()
    }

    // MARK: - 配置备份与迁移

    func mappingBackups() -> [MappingBackup] {
        AppStorage.ensureDirectory(AppStorage.mappingBackupsDirectory)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: AppStorage.mappingBackupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json",
                  url.lastPathComponent.hasPrefix("mapping-v3-") else {
                return nil
            }
            let modifiedAt = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return MappingBackup(url: url, modifiedAt: modifiedAt)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

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

    func restoreMappingBackup(_ backup: MappingBackup) throws {
        let knownBackup = mappingBackups().contains {
            $0.url.standardizedFileURL == backup.url.standardizedFileURL
        }
        guard knownBackup else {
            throw CocoaError(.fileNoSuchFile)
        }
        try importConfiguration(from: backup.url)
    }

    // MARK: - 持久化

    private func load() {
        guard !hasLoaded else { return }

        isLoading = true
        var shouldPersistAfterLoad = false

        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            do {
                let decoded = try JSONDecoder().decode(PersistedMappingConfiguration.self, from: data)
                apply(decoded)
                hasLoaded = true
                ensureBuiltInTemplates()
                isLoading = false
                save()
                print("[MappingStore] loaded v3: global=\(bindings.count), templates=\(appTemplates.count), scroll=\(scrollLinesPerStep) lines")
                return
            } catch {
                print("[MappingStore] v3 load failed: \(error)")
                backupInvalidConfiguration(data)
                configurationWarning = "当前按键配置无法读取，已保留原始备份；本次仅使用内存中的默认配置。"
            }
        }

        // 兼容之前只保存全局映射的 v2 数据。
        if let data = UserDefaults.standard.data(forKey: Self.legacyStorageKey) {
            do {
                let decoded = try JSONDecoder().decode([RemoteButton: ButtonBinding].self, from: data)
                bindings = Self.mergedBindings(decoded)
                shouldPersistAfterLoad = true
                print("[MappingStore] migrated v2 global bindings: \(decoded.count)")
            } catch {
                print("[MappingStore] v2 load failed: \(error)")
            }
        }

        hasLoaded = true
        ensureBuiltInTemplates()
        isLoading = false
        if shouldPersistAfterLoad {
            save()
        } else {
            print("[MappingStore] using in-memory defaults; existing v3 data was preserved in a backup")
        }
    }

    private func apply(_ decoded: PersistedMappingConfiguration) {
        bindings = Self.mergedBindings(decoded.globalBindings)
        globalGestureProfiles = decoded.globalGestureProfiles ?? [:]
        globallyPinnedButtons = decoded.globallyPinnedButtons
            ?? Self.defaultGloballyPinnedButtons
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
        let current = try encodedCurrentConfiguration()
        guard backupMappingData(
            current,
            fileName: "mapping-v3-before-restore-\(timestamp()).json"
        ) else {
            throw MappingStoreError.backupFailed
        }

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
    /// 已有任意模板的 App 完全保留用户配置，不会被自动覆盖。
    private func ensureBuiltInTemplates() {
        consolidateLegacyChatGPTTemplates()
        ensureBuiltInCodexTemplate()
        migrateBuiltInTemplateMappings()

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

    /// 将旧版“ChatGPT”命名收敛到唯一的 Codex 模板入口。
    ///
    /// ChatGPT 与 Codex 历史上共用同一个 Bundle ID，旧版本因此可能在本机
    /// 保存两个模板。新版本只暴露 Codex；如果只有旧默认模板则改名并保留
    /// 用户的映射，如果两个默认模板同时存在则保留 Codex 默认并移除旧重复项。
    private func consolidateLegacyChatGPTTemplates() {
        let bundleID = Self.chatGPTBundleIdentifier
        var updatedTemplates = appTemplates
        var didChange = false

        if !updatedTemplates.contains(where: {
            $0.appBundleIdentifier == bundleID && $0.templateName == "Codex 默认"
        }),
           let legacyIndex = updatedTemplates.firstIndex(where: {
               $0.appBundleIdentifier == bundleID && $0.templateName == "ChatGPT 默认"
           }) {
            updatedTemplates[legacyIndex].appName = "Codex"
            updatedTemplates[legacyIndex].templateName = "Codex 默认"
            didChange = true
            print("[MappingStore] renamed legacy ChatGPT default template to Codex default")
        }

        // Custom templates are kept, but their old application label must not
        // leak back into the Codex-only settings UI.
        for index in updatedTemplates.indices where
            updatedTemplates[index].appBundleIdentifier == bundleID &&
            updatedTemplates[index].appName == "ChatGPT" {
            updatedTemplates[index].appName = "Codex"
            didChange = true
        }

        let codexDefaultID = updatedTemplates.first(where: {
            $0.appBundleIdentifier == bundleID && $0.templateName == "Codex 默认"
        })?.id
        let legacyDefaultIDs = Set(updatedTemplates.compactMap { template -> UUID? in
            guard template.appBundleIdentifier == bundleID,
                  template.templateName == "ChatGPT 默认"
            else { return nil }
            return template.id
        })
        if !legacyDefaultIDs.isEmpty, let codexDefaultID {
            updatedTemplates.removeAll { legacyDefaultIDs.contains($0.id) }
            didChange = true

            if legacyDefaultIDs.contains(activeTemplateIDs[bundleID] ?? UUID()) {
                var updatedActiveIDs = activeTemplateIDs
                updatedActiveIDs[bundleID] = codexDefaultID
                activeTemplateIDs = updatedActiveIDs
            }
            print("[MappingStore] removed duplicate ChatGPT default template")
        }

        guard didChange else { return }
        appTemplates = updatedTemplates
        save()
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
            bindings: preset.bindings
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

    /// 将本次内置模板调整应用到“仍保持旧内置内容”的模板。
    ///
    /// 只比较完整的旧模板快照：只要用户改过任意一个按钮，就保留用户配置，
    /// 避免升级时覆盖自定义快捷键。新安装则直接使用 AppTemplatePresetLibrary
    /// 的最新模板内容。
    private func migrateBuiltInTemplateMappings() {
        let migrations: [(String, String, String, [RemoteButton: ButtonBinding])] = [
            (
                Self.chatGPTBundleIdentifier,
                "Codex 默认",
                "codex.default",
                Self.legacyCodexBindings(menu: .preset(.chatGPTPreviousChat))
            ),
            (
                Self.chatGPTBundleIdentifier,
                "Codex 默认",
                "codex.default",
                Self.legacyCodexBindings(menu: .preset(.disabled))
            ),
            (
                Self.chatGPTBundleIdentifier,
                "Codex 默认",
                "codex.default",
                Self.legacyCodexPresetBindings()
            ),
            (
                Self.chatGPTBundleIdentifier,
                "Codex 默认",
                "codex.default",
                Self.legacyCodexTerminalPresetBindings()
            ),
            (
                "com.lost0rz.FloatTabs",
                "FloatTabs 默认",
                "floatTabs.default",
                Self.legacyFloatTabsBindings()
            ),
            (
                Self.chatGPTBundleIdentifier,
                "Codex 默认",
                "codex.default",
                Self.legacyCodexCurrentBindings()
            ),
            (
                "com.lost0rz.FloatTabs",
                "FloatTabs 默认",
                "floatTabs.default",
                Self.legacyFloatTabsCurrentBindings()
            ),
            (
                "com.lost0rz.FloatTabs",
                "FloatTabs 浏览增强",
                "floatTabs.browse",
                Self.legacyFloatTabsBrowseBindings()
            ),
        ]

        var updatedTemplates = appTemplates
        var didMigrate = false

        for (bundleID, templateName, presetID, legacyBindings) in migrations {
            guard let index = updatedTemplates.firstIndex(where: {
                $0.appBundleIdentifier == bundleID &&
                $0.templateName == templateName
            }) else { continue }

            guard let preset = AppTemplatePresetLibrary.preset(id: presetID),
                  updatedTemplates[index].bindings == legacyBindings else {
                continue
            }

            updatedTemplates[index].bindings = preset.bindings
            didMigrate = true
            print("[MappingStore] migrated built-in template: \(updatedTemplates[index].displayName)")
        }

        // The vertical direction is a semantic correction that also applies
        // to a built-in template after the user customized other buttons.
        // Change only the two affected bindings so those custom mappings are
        // preserved. New templates already contain the desired pair and do
        // not enter this migration.
        let verticalDirectionScopes: Set<String> = [
            "\(Self.chatGPTBundleIdentifier)\u{0}Codex 默认",
            "com.lost0rz.FloatTabs\u{0}FloatTabs 默认",
            "com.lost0rz.FloatTabs\u{0}FloatTabs 浏览增强",
        ]
        for index in updatedTemplates.indices {
            let template = updatedTemplates[index]
            let scopeKey = "\(template.appBundleIdentifier)\u{0}\(template.templateName)"
            guard verticalDirectionScopes.contains(scopeKey),
                  template.bindings[.up] == .preset(.pageDown),
                  template.bindings[.down] == .preset(.pageUp) else {
                continue
            }

            updatedTemplates[index].bindings[.up] = .preset(.pageUp)
            updatedTemplates[index].bindings[.down] = .preset(.pageDown)
            didMigrate = true
            print(
                "[MappingStore] corrected vertical direction: "
                    + "\(updatedTemplates[index].displayName)"
            )
        }

        guard didMigrate else { return }
        appTemplates = updatedTemplates
        save()
    }

    private static func legacyCodexBaseBindings() -> [RemoteButton: ButtonBinding] {
        var bindings = DefaultBindings.all
        bindings[.power] = .preset(.disabled)
        bindings[.up] = .preset(.pageUp)
        bindings[.down] = .preset(.pageDown)
        bindings[.left] = .preset(.chatGPTToggleSidebar)
        bindings[.right] = .preset(.chatGPTToggleBottomPanel)
        bindings[.ok] = .preset(.returnKey)
        bindings[.back] = .preset(.deleteBackward)
        bindings[.home] = .preset(.chatGPTNextAttention)
        bindings[.menu] = .preset(.disabled)
        bindings[.tv] = .preset(.appSwitcher)
        return bindings
    }

    private static func legacyCodexBindings(
        menu: ButtonBinding
    ) -> [RemoteButton: ButtonBinding] {
        var bindings = legacyCodexBaseBindings()
        bindings[.right] = .preset(.chatGPTToggleBottomPanel)
        bindings[.menu] = menu
        return bindings
    }

    /// Codex 预设曾经已经使用右键粘贴，但菜单键仍是禁用；只迁移完整的
    /// 未自定义模板，避免覆盖用户已经改过的单个按键。
    private static func legacyCodexPresetBindings() -> [RemoteButton: ButtonBinding] {
        var bindings = legacyCodexBaseBindings()
        bindings[.right] = .preset(.paste)
        bindings[.menu] = .preset(.disabled)
        return bindings
    }

    /// 最近一版本地测试预设已经使用右键粘贴和菜单键 Terminal；新默认改为
    /// 左右方向键与菜单键侧边栏，只迁移未自定义的完整模板。
    private static func legacyCodexTerminalPresetBindings() -> [RemoteButton: ButtonBinding] {
        var bindings = legacyCodexPresetBindings()
        bindings[.menu] = .preset(.chatGPTOpenTerminal)
        return bindings
    }

    private static func legacyFloatTabsBindings() -> [RemoteButton: ButtonBinding] {
        var bindings = DefaultBindings.all
        bindings[.power] = .preset(.disabled)
        bindings[.up] = .preset(.pageUp)
        bindings[.down] = .preset(.pageDown)
        bindings[.left] = .preset(.floatTabsPreviousTab)
        bindings[.right] = .preset(.floatTabsNextTab)
        bindings[.ok] = .preset(.returnKey)
        bindings[.back] = .preset(.escape)
        bindings[.home] = .preset(.floatTabsToggleVisibility)
        bindings[.menu] = .preset(.floatTabsSettings)
        bindings[.tv] = .preset(.appSwitcher)
        bindings[.volumeUp] = .preset(.floatTabsNextTab)
        bindings[.volumeDown] = .preset(.floatTabsPreviousTab)
        return bindings
    }

    /// Snapshot of the immediately preceding Codex built-in template. This
    /// pair used the opposite physical direction and is migrated only when
    /// the complete template is still untouched.
    private static func legacyCodexCurrentBindings() -> [RemoteButton: ButtonBinding] {
        var bindings = DefaultBindings.all
        bindings[.power] = .preset(.disabled)
        bindings[.up] = .preset(.pageDown)
        bindings[.down] = .preset(.pageUp)
        bindings[.left] = .preset(.arrowLeft)
        bindings[.right] = .preset(.arrowRight)
        bindings[.ok] = .preset(.returnKey)
        bindings[.back] = .preset(.deleteBackward)
        bindings[.volumeUp] = .preset(.chatGPTPreviousChat)
        bindings[.home] = .preset(.chatGPTNextAttention)
        bindings[.volumeDown] = .preset(.chatGPTNextChat)
        bindings[.menu] = .preset(.chatGPTToggleSidebar)
        bindings[.tv] = .preset(.appSwitcher)
        return bindings
    }

    /// Snapshot of the immediately preceding FloatTabs built-in template.
    private static func legacyFloatTabsCurrentBindings() -> [RemoteButton: ButtonBinding] {
        var bindings = DefaultBindings.all
        bindings[.power] = .preset(.disabled)
        bindings[.up] = .preset(.pageDown)
        bindings[.down] = .preset(.pageUp)
        bindings[.left] = .preset(.floatTabsToggleFocus)
        bindings[.right] = .preset(.paste)
        bindings[.ok] = .preset(.returnKey)
        bindings[.back] = .preset(.escape)
        bindings[.home] = .preset(.floatTabsToggleVisibility)
        bindings[.menu] = .preset(.floatTabsToggleAlwaysOnTop)
        bindings[.tv] = .preset(.appSwitcher)
        bindings[.volumeUp] = .preset(.floatTabsPreviousTab)
        bindings[.volumeDown] = .preset(.floatTabsNextTab)
        return bindings
    }

    /// Snapshot of the immediately preceding FloatTabs browse template.
    private static func legacyFloatTabsBrowseBindings() -> [RemoteButton: ButtonBinding] {
        var bindings = legacyFloatTabsCurrentBindings()
        bindings[.menu] = .preset(.reloadPage)
        return bindings
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

    private func save() {
        guard hasLoaded, !isLoading else { return }
        do {
            let data = try encodedCurrentConfiguration()
            if let previous = UserDefaults.standard.data(forKey: Self.storageKey),
               previous != data {
                _ = backupMappingData(
                    previous,
                    fileName: Self.previousBackupFileName
                )
            }
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            print("[MappingStore] save failed: \(error)")
        }
    }

    private func encodedCurrentConfiguration() throws -> Data {
        let configuration = PersistedMappingConfiguration(
            globalBindings: bindings,
            globallyPinnedButtons: globallyPinnedButtons,
            appTemplates: appTemplates,
            activeTemplateIDs: activeTemplateIDs,
            scrollLinesPerStep: scrollLinesPerStep,
            globalGestureProfiles: globalGestureProfiles.isEmpty
                ? nil
                : globalGestureProfiles
        )
        return try JSONEncoder().encode(configuration)
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
        ]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }

    private func backupInvalidConfiguration(_ data: Data) {
        _ = backupMappingData(
            data,
            fileName: "mapping-v3-invalid-\(timestamp()).json"
        )
    }

    @discardableResult
    private func backupMappingData(_ data: Data, fileName: String) -> Bool {
        let url = AppStorage.mappingBackupsDirectory.appendingPathComponent(fileName)
        do {
            AppStorage.ensureDirectory(AppStorage.mappingBackupsDirectory)
            try data.write(to: url, options: .atomic)
            print("[MappingStore] configuration backup: \(url.path)")
            return true
        } catch {
            print("[MappingStore] configuration backup failed: \(error)")
            return false
        }
    }
}
