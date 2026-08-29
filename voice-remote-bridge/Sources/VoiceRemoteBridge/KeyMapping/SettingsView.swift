// SettingsView.swift — 按键映射设置界面
//
// 布局：左列按钮列表（Capsule 样式）+ 右侧动作选择器（Menu + 快捷键录制）。
// Settings UI and shortcut recorder for this app.

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MappingStore
    @State private var selectedButton: RemoteButton = .back
    @State private var mappingScope: MappingScope = .global
    @State private var selectedTemplateTarget: TemplateTarget = .none
    @State private var recorderButton: RemoteButton?
    @State private var showResetConfirm = false
    @State private var showTemplateCreator = false
    @State private var showTemplatePresetImporter = false
    @State private var showDeleteTemplateConfirm = false
    @State private var templateToDelete: UUID?

    private enum MappingScope: Hashable {
        case global
        case app(String)
    }

    private enum TemplateTarget: Hashable {
        case none
        case template(UUID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                buttonListPanel
                Divider()
                actionPanel
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 580)
        // 用 sheet(item:) 直接以按钮作为展示状态，避免第一次点击时
        // showRecorder 已变成 true、recorderButton 仍是 nil，导致空 sheet。
        .sheet(item: $recorderButton) { button in
            ShortcutRecorderSheet(
                button: button,
                initialTriggerMode: currentBinding(for: button).shortcutTriggerMode ?? .single,
                onCancel: { recorderButton = nil },
                onClear: {
                    setCurrentBinding(.preset(.disabled), for: button)
                    recorderButton = nil
                },
                onRecord: { chord, trigger in
                    setCurrentBinding(.shortcut(chord, trigger: trigger), for: button)
                    recorderButton = nil
                }
            )
        }
        .sheet(isPresented: $showTemplateCreator) {
            AppTemplateCreatorSheet(
                apps: templateCreatorApps,
                onCancel: { showTemplateCreator = false },
                onCreate: { app, templateName in
                    let id = store.addTemplate(
                        appBundleIdentifier: app.bundleIdentifier,
                        appName: app.displayName,
                        templateName: templateName
                    )
                    mappingScope = .app(app.bundleIdentifier)
                    selectedTemplateTarget = .template(id)
                    showTemplateCreator = false
                }
            )
        }
        .sheet(isPresented: $showTemplatePresetImporter) {
            if case let .app(bundleID) = mappingScope {
                AppTemplatePresetSheet(
                    appName: mappingScopeDisplayName,
                    bundleID: bundleID,
                    presets: store.templatePresets(for: bundleID),
                    onCancel: { showTemplatePresetImporter = false },
                    onImport: { preset in
                        if let id = store.importTemplatePreset(
                            preset.id,
                            for: bundleID,
                            appName: mappingScopeDisplayName
                        ) {
                            selectedTemplateTarget = .template(id)
                        }
                        showTemplatePresetImporter = false
                    }
                )
            } else {
                EmptyView()
            }
        }
        .alert("确认删除 App 模板", isPresented: $showDeleteTemplateConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let templateToDelete {
                    let bundleID = store.template(withID: templateToDelete)?.appBundleIdentifier
                    store.deleteTemplate(templateToDelete)
                    if let bundleID, let active = store.activeTemplate(for: bundleID) {
                        mappingScope = .app(bundleID)
                        selectedTemplateTarget = .template(active.id)
                    } else {
                        mappingScope = .global
                        selectedTemplateTarget = .none
                    }
                }
                self.templateToDelete = nil
            }
        } message: {
            Text("删除后该 App 将使用通用映射，其他模板不受影响。")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("按键映射设置")
                .font(.title2)
                .fontWeight(.medium)
            Text("选择左侧按钮，在右侧设置映射目标。支持预设动作和自定义快捷键。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text("程序")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Menu {
                    Button("通用映射") {
                        selectMappingScope(.global)
                    }

                    if !configuredAppChoices.isEmpty {
                        Divider()
                        Section("已配置模板") {
                            ForEach(configuredAppChoices) { app in
                                Button(app.displayName) {
                                    selectMappingScope(.app(app.bundleIdentifier))
                                }
                            }
                        }
                    }

                    if !moreAppChoices.isEmpty {
                        Divider()
                        Menu("更多应用") {
                            ForEach(moreAppChoices) { app in
                                Button("\(app.displayName)（未配置模板）") {
                                    selectMappingScope(.app(app.bundleIdentifier))
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(mappingScopeDisplayName)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 190)

                if case let .app(bundleID) = mappingScope {
                    Text("模板")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    let templates = store.templates(for: bundleID)
                    Picker("模板", selection: Binding(
                        get: { selectedTemplateTarget },
                        set: { selectTemplate($0, for: bundleID) }
                    )) {
                        if templates.isEmpty {
                            Text("暂无模板").tag(TemplateTarget.none)
                        } else {
                            ForEach(templates) { template in
                                Text(template.templateName + (store.isActiveTemplate(template.id) ? " · Active" : ""))
                                    .tag(TemplateTarget.template(template.id))
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)

                    Button("导入预设") {
                        showTemplatePresetImporter = true
                    }
                    .controlSize(.small)
                    .disabled(store.templatePresets(for: bundleID).isEmpty)

                    Button("新增模板") {
                        showTemplateCreator = true
                    }
                    .controlSize(.small)
                } else {
                    Button("新增 App 模板") {
                        showTemplateCreator = true
                    }
                    .controlSize(.small)
                }
            }

            if let template = selectedEditorTemplate {
                HStack(spacing: 8) {
                    Text("Active：\(template.templateName)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.green)
                    Text("\(template.appName)（\(template.appBundleIdentifier)）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("删除模板", role: .destructive) {
                        templateToDelete = template.id
                        showDeleteTemplateConfirm = true
                    }
                    .controlSize(.small)
                }
            } else if case .global = mappingScope {
                Text("通用映射：没有对应 App 的 Active 模板时使用。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("这个 App 还没有模板，请点击“导入预设”或“新增模板”。")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Left: Button list

    private var buttonListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("遥控器按钮")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(RemoteButton.allCases) { button in
                        Button(action: { selectedButton = button }) {
                            HStack {
                                Text(button.displayName)
                                    .fontWeight(selectedButton == button ? .semibold : .regular)
                                    .foregroundColor(
                                        store.isGloballyPinned(button) && mappingScope != .global
                                            ? .secondary
                                            : .primary
                                    )
                                Spacer()
                                Text(bindingSummary(for: button))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                if store.isGloballyPinned(button) {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .help("应用全局")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedButton == button
                                          ? Color.accentColor.opacity(0.15)
                                          : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(width: 220)
    }

    private func bindingSummary(for button: RemoteButton) -> String {
        let binding = currentBinding(for: button)
        switch binding {
        case .preset(.disabled):
            if button == .menu,
               selectedEditorTemplate?.appBundleIdentifier == MappingStore.chatGPTBundleIdentifier {
                return "自定义（留空）"
            }
            return "禁用"
        case .preset: return binding.displayName
        case let .shortcut(chord, trigger): return "\(chord.displayName) · \(trigger.shortLabel)"
        case .voiceKeyDefault: return "默认"
        }
    }

    // MARK: - Right: Action panel

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(selectedButton.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("HID: 0x\(String(selectedButton.hidUsage, radix: 16, uppercase: true))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
            }

            // 当前绑定显示
            let currentBinding = currentBinding(for: selectedButton)
            HStack {
                Text("当前映射:")
                    .foregroundColor(.secondary)
                Text(currentBindingLabel(for: currentBinding))
                    .fontWeight(.medium)
                if let trigger = currentBinding.shortcutTriggerMode {
                    Text("· \(trigger.displayName)")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if case .global = mappingScope {
                globalPinningControl
            } else if isSelectedButtonGloballyPinned {
                globalPinningStatus
            }

            if hasEditableScope {
                Group {
                    // 预设动作选择
                if selectedButton != .microphone {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("预设动作（按分类）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("预设动作", selection: Binding(
                            get: {
                                if case .preset(let action) = currentBinding {
                                    return action
                                }
                                return ButtonAction.disabled
                            },
                            set: { newAction in
                                setCurrentBinding(.preset(newAction), for: selectedButton)
                            }
                        )) {
                            ForEach(availableActionCategories) { category in
                                Section(category.displayName) {
                                    ForEach(actions(in: category)) { action in
                                        Text(action.displayName).tag(action)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 300)
                    }
                }

                if isScrollAction(currentBinding) {
                    scrollSpeedControl
                }

                // 自定义快捷键
                VStack(alignment: .leading, spacing: 8) {
                    Text("自定义快捷键")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        if case let .shortcut(chord, trigger) = currentBinding {
                            Text(chord.displayName)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Picker("触发方式", selection: Binding(
                                get: { trigger },
                                set: { newMode in
                                    setCurrentBinding(
                                        .shortcut(chord, trigger: newMode),
                                        for: selectedButton
                                    )
                                }
                            )) {
                                ForEach(ShortcutTriggerMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }

                        Button("录制快捷键...") {
                            recorderButton = selectedButton
                        }
                        .controlSize(.regular)
                    }
                    }
                }
                .disabled(isAppMappingLocked)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("请先为当前程序导入或新增一个模板")
                        .font(.headline)
                    Text("当前程序还没有模板。先在上方选择“导入预设”或“新增模板”，避免把程序专属设置误改到通用映射。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Spacer()

            // 语音键特殊说明
            if selectedButton == .microphone {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    if case .voiceKeyDefault = currentBinding {
                        Text("语音键当前为默认行为（短按自动选择物理麦克风，长按遥控器麦克风）。设置其他快捷键后将覆盖此行为。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("语音键已设为自定义快捷键，原短按/长按语音行为已覆盖。若要恢复，请点「录制快捷键…」后取消并选回预设动作。")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Footer

    private var scrollSpeedControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("滚屏速度")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(store.scrollLinesPerStep) 行/次")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Text("慢")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(store.scrollLinesPerStep) },
                        set: { store.scrollLinesPerStep = Int($0.rounded()) }
                    ),
                    in: Double(MappingStore.scrollLinesPerStepRange.lowerBound)...Double(MappingStore.scrollLinesPerStepRange.upperBound),
                    step: 1
                )
                Text("快")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("默认") {
                    store.scrollLinesPerStep = MappingStore.defaultScrollLinesPerStep
                }
                .controlSize(.small)
            }

            Text("影响“向上滚屏”和“向下滚屏”预设动作；长按时也会同步加快。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("当前范围重置") {
                showResetConfirm = true
            }
            .controlSize(.small)
            .foregroundColor(.red)
            .alert("确认重置", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive) {
                    resetCurrentMapping()
                }
            } message: {
                Text(mappingScope == .global
                     ? "这将恢复通用映射中的所有按钮。"
                     : "这将恢复当前 App 模板中的所有按钮。")
            }

            Spacer()

            Text("需要输入监控 + 辅助功能权限")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selectedEditorTemplate: AppMappingTemplate? {
        guard case let .app(bundleID) = mappingScope,
              case let .template(id) = selectedTemplateTarget,
              let template = store.template(withID: id),
              template.appBundleIdentifier == bundleID
        else { return nil }
        return template
    }

    private var hasEditableScope: Bool {
        switch mappingScope {
        case .global:
            return true
        case .app:
            return selectedEditorTemplate != nil
        }
    }

    private var isSelectedButtonGloballyPinned: Bool {
        store.isGloballyPinned(selectedButton)
    }

    private var isAppMappingLocked: Bool {
        if case .app = mappingScope {
            return isSelectedButtonGloballyPinned
        }
        return false
    }

    private var globalPinningControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "应用全局",
                isOn: Binding(
                    get: { store.isGloballyPinned(selectedButton) },
                    set: { store.setGlobalPinning($0, for: selectedButton) }
                )
            )
            Text("开启后，这个按键始终使用通用映射；FloatTabs、Ghostty 等 App 模板不能替代它。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var globalPinningStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("此按键已应用全局")
                    .font(.caption.weight(.medium))
                Text("当前 App 模板不会替代它；请切回“通用映射”修改这个按键。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var availableActionCategories: [ButtonActionCategory] {
        var allowed: Set<ButtonActionCategory> = [
            .system,
            .navigation,
            .editing,
            .media,
        ]
        if case .global = mappingScope {
            allowed.insert(.applications)
        }
        if case let .app(bundleID) = mappingScope {
            allowed.formUnion(AppTemplatePresetLibrary.categories(for: bundleID))
        }
        if case let .preset(action) = currentBinding(for: selectedButton) {
            allowed.insert(action.category)
        }
        return ButtonActionCategory.allCases.filter { allowed.contains($0) }
    }

    private func actions(in category: ButtonActionCategory) -> [ButtonAction] {
        ButtonAction.allCases.filter { $0.category == category }
    }

    private var configuredAppChoices: [AppTemplateChoice] {
        // 已经建过模板的 App 固定显示在主菜单顶部；即使当前没有运行，
        // 也保留在这里，方便继续编辑已有模板。
        var choices: [String: AppTemplateChoice] = [:]
        for template in store.appTemplates {
            let displayName = AppTemplatePresetLibrary.knownApps.first {
                $0.bundleIdentifier == template.appBundleIdentifier
            }?.displayName ?? template.appName
            choices[template.appBundleIdentifier] = AppTemplateChoice(
                bundleIdentifier: template.appBundleIdentifier,
                displayName: displayName
            )
        }
        return choices.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var moreAppChoices: [AppTemplateChoice] {
        let configuredBundleIDs = Set(configuredAppChoices.map(\.bundleIdentifier))
        var choices: [String: AppTemplateChoice] = [:]
        for app in Self.runningAppChoices() {
            choices[app.bundleIdentifier] = app
        }
        for app in installedPresetAppChoices where choices[app.bundleIdentifier] == nil {
            choices[app.bundleIdentifier] = app
        }
        return choices.values
            .filter { !configuredBundleIDs.contains($0.bundleIdentifier) }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var installedPresetAppChoices: [AppTemplateChoice] {
        AppTemplatePresetLibrary.knownApps.compactMap { app in
            guard NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: app.bundleIdentifier
            ) != nil else { return nil }
            return AppTemplateChoice(
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.displayName
            )
        }
    }

    private var mappingScopeDisplayName: String {
        switch mappingScope {
        case .global:
            return "通用映射"
        case let .app(bundleID):
            if let app = configuredAppChoices.first(where: { $0.bundleIdentifier == bundleID }) {
                return app.displayName
            }
            if let app = moreAppChoices.first(where: { $0.bundleIdentifier == bundleID }) {
                return app.displayName
            }
            return bundleID
        }
    }

    private var templateCreatorApps: [AppTemplateChoice] {
        if case let .app(bundleID) = mappingScope,
           let app = (configuredAppChoices + moreAppChoices)
                .first(where: { $0.bundleIdentifier == bundleID }) {
            return [app]
        }
        return mergedAppChoices(Self.runningAppChoices() + installedPresetAppChoices)
    }

    private func selectMappingScope(_ scope: MappingScope) {
        mappingScope = scope
        switch scope {
        case .global:
            selectedTemplateTarget = .none
        case let .app(bundleID):
            if let active = store.activeTemplate(for: bundleID) {
                selectedTemplateTarget = .template(active.id)
            } else if let first = store.templates(for: bundleID).first {
                selectedTemplateTarget = .template(first.id)
                store.setActiveTemplate(first.id)
            } else {
                selectedTemplateTarget = .none
            }
        }
    }

    private func selectTemplate(_ target: TemplateTarget, for bundleID: String) {
        selectedTemplateTarget = target
        if case let .template(id) = target {
            // 下拉框选中的模板就是该 App 当前生效的 Active 模板。
            guard let template = store.template(withID: id),
                  template.appBundleIdentifier == bundleID
            else { return }
            store.setActiveTemplate(id)
        }
    }

    private func currentBinding(for button: RemoteButton) -> ButtonBinding {
        if store.isGloballyPinned(button) {
            return store.binding(for: button)
        }
        guard case let .template(id) = selectedTemplateTarget,
              selectedEditorTemplate != nil
        else {
            return store.binding(for: button)
        }
        return store.binding(for: button, templateID: id)
    }

    private func isScrollAction(_ binding: ButtonBinding) -> Bool {
        guard case let .preset(action) = binding else { return false }
        return action == .pageUp || action == .pageDown
    }

    private func currentBindingLabel(for binding: ButtonBinding) -> String {
        if selectedButton == .menu,
           selectedEditorTemplate?.appBundleIdentifier == MappingStore.chatGPTBundleIdentifier,
           binding.isDisabled {
            return "自定义（留空）"
        }
        return binding.displayName
    }

    private func setCurrentBinding(_ binding: ButtonBinding, for button: RemoteButton) {
        guard hasEditableScope else { return }
        if case .app = mappingScope, store.isGloballyPinned(button) {
            return
        }
        guard case let .template(id) = selectedTemplateTarget,
              selectedEditorTemplate != nil
        else {
            store.setBinding(binding, for: button)
            return
        }
        store.setBinding(binding, for: button, templateID: id)
    }

    private func resetCurrentMapping() {
        guard case let .template(id) = selectedTemplateTarget,
              selectedEditorTemplate != nil
        else {
            store.resetAll()
            return
        }
        store.resetTemplate(id)
    }

    private static func runningAppChoices() -> [AppTemplateChoice] {
        let ownBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> AppTemplateChoice? in
                guard app.activationPolicy == .regular ||
                      app.activationPolicy == .accessory,
                      let bundleID = app.bundleIdentifier,
                      bundleID != ownBundleID
                else { return nil }
                return AppTemplateChoice(
                    bundleIdentifier: bundleID,
                    displayName: app.localizedName ?? bundleID
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func mergedAppChoices(_ choices: [AppTemplateChoice]) -> [AppTemplateChoice] {
        var byBundleID: [String: AppTemplateChoice] = [:]
        for choice in choices {
            byBundleID[choice.bundleIdentifier] = choice
        }
        return byBundleID.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}

private struct AppTemplateChoice: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }
}

private struct AppTemplatePresetSheet: View {
    let appName: String
    let bundleID: String
    let presets: [AppTemplatePreset]
    let onCancel: () -> Void
    let onImport: (AppTemplatePreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入 \(appName) 预设模板")
                .font(.title3.weight(.semibold))
            Text("模板只会添加到当前程序（\(bundleID)），并立即设为 Active。已经导入过的同名模板会保留你的修改。")
                .font(.caption)
                .foregroundColor(.secondary)

            if presets.isEmpty {
                Text("当前程序暂无内置预设，请使用“新增模板”或录制快捷键。")
                    .foregroundColor(.orange)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(presets) { preset in
                            Button {
                                onImport(preset)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "square.and.arrow.down")
                                        .foregroundColor(.accentColor)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.templateName)
                                            .font(.body.weight(.medium))
                                        Text(preset.summary)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private struct AppTemplateCreatorSheet: View {
    let apps: [AppTemplateChoice]
    let onCancel: () -> Void
    let onCreate: (AppTemplateChoice, String) -> Void

    @State private var selectedBundleIdentifier = ""
    @State private var templateName = "默认模板"

    private var selectedApp: AppTemplateChoice? {
        apps.first { $0.bundleIdentifier == selectedBundleIdentifier }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增 App 按键模板")
                .font(.title3.weight(.semibold))
            Text("选择一个当前正在运行的 App。之后只有该 App 位于前台时，这个模板才会参与映射选择。")
                .foregroundColor(.secondary)

            if apps.isEmpty {
                Text("当前没有可选择的普通 App，请先打开目标 App 后再试。")
                    .foregroundColor(.orange)
            } else {
                Picker("目标 App", selection: $selectedBundleIdentifier) {
                    ForEach(apps) { app in
                        Text("\(app.displayName)（\(app.bundleIdentifier)）")
                            .tag(app.bundleIdentifier)
                    }
                }
                .pickerStyle(.menu)

                TextField("模板名称，例如：浏览 / 编辑 / 交易", text: $templateName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("创建") {
                    if let selectedApp {
                        onCreate(selectedApp, templateName)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedApp == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            if selectedBundleIdentifier.isEmpty {
                selectedBundleIdentifier = apps.first?.bundleIdentifier ?? ""
            }
        }
    }
}

// MARK: - Shortcut Recorder Sheet

struct ShortcutRecorderSheet: View {
    let button: RemoteButton
    let onCancel: () -> Void
    let onClear: () -> Void
    let onRecord: (KeyChord, ShortcutTriggerMode) -> Void

    @State private var triggerMode: ShortcutTriggerMode

    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var heldModifiers: KeyChord.Modifiers = []
    @State private var heldModifierKeyCodes = Set<UInt16>()
    @State private var didCapture = false
    @State private var preview = "请按下快捷键"
    @State private var errorText = ""

    init(
        button: RemoteButton,
        initialTriggerMode: ShortcutTriggerMode,
        onCancel: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onRecord: @escaping (KeyChord, ShortcutTriggerMode) -> Void
    ) {
        self.button = button
        self.onCancel = onCancel
        self.onClear = onClear
        self.onRecord = onRecord
        _triggerMode = State(initialValue: initialTriggerMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置 \(button.displayName) 的快捷键")
                .font(.title3.weight(.semibold))
            Text("按下一个键（可带修饰键），或直接按下修饰键（如 Control、Option、Shift、Command、Fn）。")
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Text(preview)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.accentColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("触发方式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("触发方式", selection: $triggerMode) {
                    ForEach(ShortcutTriggerMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(triggerMode.helpText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Text("录制只在此窗口打开期间生效。")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack {
                Button("禁用这个按键", action: onClear)
                Spacer()
                Button("取消", action: onCancel)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { startMonitoring() }
        .onDisappear { stopMonitoring() }
    }

    private static let modifierKeyCodeMap: [UInt16: (String, KeyChord.Modifiers, NSEvent.ModifierFlags)] = [
        54: ("⌘", .command, .command), 55: ("⌘", .command, .command),
        59: ("⌃", .control, .control), 62: ("⌃", .control, .control),
        58: ("⌥", .option, .option),   61: ("⌥", .option, .option),
        56: ("⇧", .shift, .shift),     60: ("⇧", .shift, .shift),
        63: ("Fn",  [], .function),
    ]

    private func startMonitoring() {
        stopMonitoring()
        heldModifiers = []
        heldModifierKeyCodes.removeAll()
        didCapture = false

        // 监听普通按键（过滤自动重复）
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat else { return nil }
            if let cgEvent = event.cgEvent,
               cgEvent.getIntegerValueField(.eventSourceUserData) == KeyInjector.syntheticMarker {
                return event
            }
            guard let chord = KeyChord.from(event: event, extraModifiers: heldModifiers) else {
                errorText = "这个键暂时无法安全注入，请换一个普通键或功能键。"
                return nil
            }
            preview = chord.displayName
            errorText = ""
            didCapture = true
            DispatchQueue.main.async { onRecord(chord, triggerMode) }
            return nil
        }

        // 监听修饰键按下/松开（flagsChanged）
        // 按下时只追踪状态，松开时才捕获（这样可以按 Option+A 等组合键）
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if let cgEvent = event.cgEvent,
               cgEvent.getIntegerValueField(.eventSourceUserData) == KeyInjector.syntheticMarker {
                return event
            }
            let keyCode = event.keyCode
            guard let (_, mod, nsFlag) = Self.modifierKeyCodeMap[keyCode] else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isDown = flags.contains(nsFlag)

            if isDown {
                // 修饰键按下 → 只追踪，不捕获
                heldModifierKeyCodes.insert(keyCode)
                heldModifiers.insert(mod)
                if let chord = KeyChord.fromModifierKeyCode(keyCode, extraModifiers: heldModifiers) {
                    preview = chord.displayName
                }
                errorText = ""
                return nil
            } else {
                // 修饰键松开
                heldModifierKeyCodes.remove(keyCode)
                heldModifiers.remove(mod)
                // 如果没有捕获过组合键，且没有其他修饰键按住 → 捕获为纯修饰键
                if !didCapture && heldModifierKeyCodes.isEmpty {
                    if let chord = KeyChord.fromModifierKeyCode(keyCode) {
                        preview = chord.displayName
                        didCapture = true
                        DispatchQueue.main.async { onRecord(chord, triggerMode) }
                    }
                }
                return nil
            }
        }
    }

    private func stopMonitoring() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        flagsMonitor = nil
        heldModifiers = []
        heldModifierKeyCodes.removeAll()
        didCapture = false
    }
}

// MARK: - KeyChord from NSEvent

extension KeyChord {
    static func from(event: NSEvent, extraModifiers: KeyChord.Modifiers = []) -> KeyChord? {
        guard event.type == .keyDown,
              let label = Self.keyLabel(for: event)
        else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = extraModifiers
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option)  { modifiers.insert(.option) }
        if flags.contains(.shift)   { modifiers.insert(.shift) }
        return KeyChord(keyCode: event.keyCode, keyLabel: label, modifiers: modifiers)
    }

    /// 从修饰键 keyCode 构建 KeyChord（纯修饰键松开时调用）。
    static func fromModifierKeyCode(_ keyCode: UInt16, extraModifiers: KeyChord.Modifiers = []) -> KeyChord? {
        let modifierKeyCodeMap: [UInt16: (String, Modifiers)] = [
            54: ("⌘", .command), 55: ("⌘", .command),
            59: ("⌃", .control), 62: ("⌃", .control),
            58: ("⌥", .option),  61: ("⌥", .option),
            56: ("⇧", .shift),   60: ("⇧", .shift),
            63: ("Fn",  []),
        ]
        guard let (label, mod) = modifierKeyCodeMap[keyCode] else { return nil }
        var combined = mod.union(extraModifiers)
        // 移除自身（避免重复）
        combined.remove(mod)
        return KeyChord(keyCode: keyCode, keyLabel: label, modifiers: combined)
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        let fixed: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete",
            119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20", 63: "Fn",
            54: "⌘", 55: "⌘", 59: "⌃", 62: "⌃",
            58: "⌥", 61: "⌥", 56: "⇧", 60: "⇧",
        ]
        if let label = fixed[event.keyCode] { return label }
        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar)
        else { return nil }
        return characters.uppercased()
    }
}
