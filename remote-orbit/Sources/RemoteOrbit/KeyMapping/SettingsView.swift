// SettingsView.swift — RemoteOrbit Control Center
//
// 产品级设置工作区：概览、按键映射、设置与诊断和关于。
// Shortcut recording remains in this file so the recorder shares the mapping
// model and uses the same product-specific window flow.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

typealias VoiceTriggerChangeHandler = (
    VoiceTriggerKey,
    @escaping (VoiceTriggerApplyResult) -> Void
) -> Void
typealias PersistentSessionTriggerKeyChangeHandler = VoiceTriggerChangeHandler
typealias SecondaryVoiceTriggerKeyChangeHandler = (
    VoiceTriggerKey?,
    ButtonBinding,
    @escaping (VoiceTriggerApplyResult) -> Void
) -> Void
typealias MicrophoneShortBindingChangeHandler = (
    ButtonBinding,
    @escaping (VoiceTriggerApplyResult) -> Void
) -> Void

enum VoiceSettingsRuntimeBridge {
    static var readSecondaryVoiceTriggerKey: () -> VoiceTriggerKey? = {
        AppStorage.secondaryMomentaryVoiceTriggerKey
    }
    static var changeSecondaryVoiceTriggerKey: SecondaryVoiceTriggerKeyChangeHandler = {
        key, _, completion in
        AppStorage.secondaryMomentaryVoiceTriggerKey = key
        completion(.applied)
    }
    static var changeMicrophoneShortBinding: MicrophoneShortBindingChangeHandler = { _, completion in
        completion(.applied)
    }
}

struct SettingsView: View {
    @ObservedObject var store: MappingStore
    var onRecordingChanged: (Bool) -> Void = { _ in }
    private var onVoiceTriggerChanged: VoiceTriggerChangeHandler
    private var onPersistentSessionTriggerKeyChanged: PersistentSessionTriggerKeyChangeHandler
    private var onSecondaryVoiceTriggerKeyChanged: SecondaryVoiceTriggerKeyChangeHandler
    private var onMicrophoneShortBindingChanged: MicrophoneShortBindingChangeHandler
    @State private var selectedSection: WorkspaceSection = .overview
    @State private var selectedButton: RemoteButton = .microphone
    @State private var mappingScope: MappingScope = .global
    @State private var selectedMomentaryVoiceTriggerKey: VoiceTriggerKey
    @State private var isApplyingMomentaryVoiceTriggerKey = false
    @State private var momentaryVoiceTriggerMessage: String?
    @State private var selectedPersistentSessionTriggerKey: VoiceTriggerKey
    @State private var isApplyingPersistentSessionTriggerKey = false
    @State private var persistentSessionTriggerMessage: String?
    @State private var selectedSecondaryVoiceTriggerKey: VoiceTriggerKey?
    @State private var isApplyingSecondaryVoiceTriggerKey = false
    @State private var secondaryVoiceTriggerMessage: String?
    @State private var microphoneShortBindingMessage: String?
    @State private var selectedTemplateTarget: TemplateTarget = .none
    @State private var recorderButton: RemoteButton?
    @State private var gestureRecorderTarget: GestureRecorderTarget?
    @State private var showResetConfirm = false
    @State private var showTemplateCreator = false
    @State private var showTemplatePresetImporter = false
    @State private var showDeleteTemplateConfirm = false
    @State private var templateToDelete: UUID?
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var loggingEnabled = Log.isEnabled
    @State private var recordingEnabled = AppStorage.recordingEnabled
    @State private var isRepairingInstallation = false
    @State private var installationMessage: String?
    @State private var installationRefreshID = UUID()
    @State private var configurationMessage: String?

    init(
        store: MappingStore,
        initialMomentaryVoiceTriggerKey: VoiceTriggerKey,
        initialPersistentSessionTriggerKey: VoiceTriggerKey,
        initialSecondaryVoiceTriggerKey: VoiceTriggerKey? = nil,
        onRecordingChanged: @escaping (Bool) -> Void = { _ in },
        onVoiceTriggerChanged: @escaping VoiceTriggerChangeHandler,
        onPersistentSessionTriggerKeyChanged: @escaping PersistentSessionTriggerKeyChangeHandler,
        onSecondaryVoiceTriggerKeyChanged: SecondaryVoiceTriggerKeyChangeHandler? = nil,
        onMicrophoneShortBindingChanged: MicrophoneShortBindingChangeHandler? = nil
    ) {
        self.store = store
        self.onRecordingChanged = onRecordingChanged
        self.onVoiceTriggerChanged = onVoiceTriggerChanged
        self.onPersistentSessionTriggerKeyChanged = onPersistentSessionTriggerKeyChanged
        self.onSecondaryVoiceTriggerKeyChanged = onSecondaryVoiceTriggerKeyChanged
            ?? VoiceSettingsRuntimeBridge.changeSecondaryVoiceTriggerKey
        self.onMicrophoneShortBindingChanged = onMicrophoneShortBindingChanged
            ?? VoiceSettingsRuntimeBridge.changeMicrophoneShortBinding
        _selectedMomentaryVoiceTriggerKey = State(initialValue: initialMomentaryVoiceTriggerKey)
        _selectedPersistentSessionTriggerKey = State(initialValue: initialPersistentSessionTriggerKey)
        _selectedSecondaryVoiceTriggerKey = State(
            initialValue: initialSecondaryVoiceTriggerKey
                ?? VoiceSettingsRuntimeBridge.readSecondaryVoiceTriggerKey()
        )
    }

    enum MappingScope: Hashable {
        case global
        case app(String)
    }

    private enum MappingScopeKind: Hashable {
        case global
        case app
    }

    private struct ButtonGroup: Identifiable {
        let title: String
        let buttons: [RemoteButton]

        var id: String { title }
    }

    private struct GestureRecorderTarget: Identifiable {
        let button: RemoteButton
        let slot: ButtonGestureSlot

        var id: String { "\(button.rawValue)-\(slot.rawValue)" }
    }

    enum TemplateTarget: Hashable {
        case none
        case template(UUID)
    }

    /// The microphone key is a semantic two-mode control, not a generic
    /// shortcut slot. Keep the small UI choice separate from ButtonAction so
    /// the long-press remote microphone remains independent.
    private enum MicrophoneShortInputMode: String, CaseIterable, Identifiable {
        case persistentIME
        case codexVoiceChat

        var id: String { rawValue }
    }

    private enum WorkspaceSection: String, CaseIterable, Identifiable {
        case overview
        case mappings
        case diagnostics
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "概览"
            case .mappings: return "按键映射"
            case .diagnostics: return "设置与诊断"
            case .about: return "关于"
            }
        }

        var subtitle: String {
            switch self {
            case .overview: return "连接与运行状态"
            case .mappings: return "定义每个按钮的行为"
            case .diagnostics: return "启动、日志、录音与权限"
            case .about: return "版本与产品信息"
            }
        }

        var symbolName: String {
            switch self {
            case .overview: return "rectangle.grid.2x2"
            case .mappings: return "slider.horizontal.3"
            case .diagnostics: return "stethoscope"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        workspace
        .frame(minWidth: 1_020, minHeight: 660)
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
        .sheet(item: $gestureRecorderTarget) { target in
            ShortcutRecorderSheet(
                button: target.button,
                title: "设置 \(target.button.displayName) 的 \(target.slot.displayName) 快捷键",
                showsTriggerMode: false,
                clearButtonTitle: "清除这个手势",
                initialTriggerMode: .single,
                onCancel: { gestureRecorderTarget = nil },
                onClear: {
                    setCurrentGestureBinding(nil, for: target.button, slot: target.slot)
                    setCurrentGestureEnabled(false, for: target.slot)
                    gestureRecorderTarget = nil
                },
                onRecord: { chord, _ in
                    setCurrentGestureBinding(
                        .shortcut(chord, trigger: .single),
                        for: target.button,
                        slot: target.slot
                    )
                    setCurrentGestureEnabled(true, for: target.slot)
                    gestureRecorderTarget = nil
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

    // MARK: - Product workspace

    private var workspace: some View {
        VStack(spacing: 0) {
            ProductTitleBar()
            Divider()

            HStack(spacing: 0) {
                navigationRail
                Divider()
                pageContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var navigationRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKSPACE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ForEach(WorkspaceSection.allCases) { section in
                Button {
                    selectSection(section)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbolName)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.title)
                                .font(.body.weight(.medium))
                            Text(section.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                selectedSection == section
                                    ? Color.accentColor.opacity(0.14)
                                    : Color.clear
                            )
                    )
                    .foregroundStyle(selectedSection == section ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 7) {
                Label("配置只保存在本机", systemImage: "lock.shield")
                    .font(.caption.weight(.medium))
                Text("RemoteOrbit 使用独立的本地配置，不连接其他项目的设置或服务。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(12)
        .frame(width: 224, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedSection {
        case .overview:
            overviewPage
        case .mappings:
            mappingsPage
        case .diagnostics:
            diagnosticsPage
        case .about:
            aboutPage
        }
    }

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    metricCard(
                        title: "遥控器按钮",
                        value: "\(RemoteButton.allCases.count)",
                        detail: "可配置按键",
                        symbolName: "remote"
                    )
                    metricCard(
                        title: "程序模板",
                        value: "\(store.appTemplates.count)",
                        detail: "独立程序模板",
                        symbolName: "square.stack.3d.up"
                    )
                    metricCard(
                        title: "滚动速度",
                        value: "\(store.scrollLinesPerStep)",
                        detail: "行 / 次",
                        symbolName: "arrow.up.and.down"
                    )
                }

                workspaceCard(title: "生效逻辑", symbolName: "arrow.triangle.branch") {
                    VStack(alignment: .leading, spacing: 14) {
                        logicRow(
                            index: "01",
                            title: "默认映射",
                            description: "所有程序都有一套基础行为，没有独立模板时直接使用。"
                        )
                        logicRow(
                            index: "02",
                            title: "程序模板",
                            description: "当前程序有 Active 模板时，只对该程序使用专属按钮方案。"
                        )
                        logicRow(
                            index: "03",
                            title: "始终使用默认",
                            description: "单个按钮开启后会跳过程序模板，适合音量、Home 等固定操作。"
                        )
                    }
                }

                workspaceCard(title: "首次使用建议", symbolName: "sparkles") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("先在“按键映射”顶部选择通用或程序范围；选择程序后，在顶部直接选择 Active 模板并管理模板。")
                        Text("修改会立即保存到本机；按键按下后会锁定当时的目标 App，避免切换窗口时误发到别的程序。")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
    }

    private var mappingsPage: some View {
        visualMappingEditor
    }

    private var visualMappingScopeMenu: some View {
        Menu {
            Button {
                selectMappingScope(.global)
            } label: {
                Label("通用映射", systemImage: "globe")
            }

            if !configuredAppChoices.isEmpty {
                Divider()
                Section("已配置程序") {
                    ForEach(configuredAppChoices) { app in
                        Button {
                            selectMappingScope(.app(app.bundleIdentifier))
                        } label: {
                            Label(app.displayName, systemImage: appSymbolName(for: app.bundleIdentifier))
                        }
                    }
                }
            }

            Divider()
            Button {
                showTemplateCreator = true
            } label: {
                Label("添加程序…", systemImage: "plus.circle")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mappingScope == .global ? "globe" : "app.badge")
                    .foregroundStyle(Color.accentColor)
                Text(mappingScopeDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .help("切换通用映射或已配置的程序模板；也可以在菜单底部添加程序")
    }

    private var visualMappingEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                visualMappingScopeBar

                if case .app = mappingScope, !hasEditableScope {
                    workspaceCard(title: "先创建一个程序模板", symbolName: "square.stack.3d.up.badge.plus") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("这个程序还没有可编辑的模板。可以直接套用内置预设，或者新建一个空模板。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Button("套用预设模板") {
                                    showTemplatePresetImporter = true
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(templatePresetChoicesForCurrentScope.isEmpty)
                                Button("新建空模板") {
                                    showTemplateCreator = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        SettingsRemotePreview(
                            selectedButton: selectedButton,
                            bindingFor: { currentBinding(for: $0) },
                            profileFor: { currentGestureProfile(for: $0) },
                            onSelect: { selectedButton = $0 }
                        )
                        .frame(width: 270)

                        visualButtonInspector
                            .frame(minWidth: 430, maxWidth: 560, alignment: .topLeading)
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var visualMappingScopeBar: some View {
        HStack(spacing: 10) {
            Label("映射范围", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            visualMappingScopeMenu

            Spacer(minLength: 12)

            if case let .app(bundleID) = mappingScope {
                let templates = store.templates(for: bundleID)
                Text("模板")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if templates.isEmpty {
                    Text("暂无模板")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Picker("Active 模板", selection: Binding(
                        get: { selectedTemplateTarget },
                        set: { selectTemplate($0, for: bundleID) }
                    )) {
                        ForEach(templates) { template in
                            Text(template.templateName)
                                .tag(TemplateTarget.template(template.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 210)
                }

                if selectedEditorTemplate != nil {
                    Button("删除", role: .destructive) {
                        templateToDelete = selectedEditorTemplate?.id
                        showDeleteTemplateConfirm = true
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else {
                Text("通用映射会作为未配置程序的基础行为")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var visualButtonInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: buttonSymbol(for: selectedButton))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedButton.displayName)
                        .font(.title2.weight(.semibold))
                    Text("点击左侧遥控器的其他按键即可切换编辑目标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("恢复默认") {
                    resetSelectedButtonToDefault()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if selectedButton == .microphone {
                microphoneSingleBehaviorCard
                microphoneMomentaryTriggerCard(currentBinding(for: selectedButton))
                microphoneSecondaryTriggerCard(currentBinding(for: selectedButton))
            } else if hasEditableScope {
                visualSingleBehaviorCard
                visualAdditionalBehaviorCard
            }

            if isScrollAction(currentBinding(for: selectedButton)) {
                workspaceCard(title: "滚动速度", symbolName: "arrow.up.and.down") {
                    scrollSpeedControl
                }
            }

            HStack {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("重置当前范围", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .tint(.red)
                Spacer()
                Label("修改会自动保存", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .alert("确认重置当前范围", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive) {
                    resetCurrentMapping()
                }
            } message: {
                Text(mappingScope == .global
                     ? "这将恢复通用映射中的所有按钮。"
                     : "这将恢复当前程序模板中的所有按钮。")
            }
        }
    }

    private var visualSingleBehaviorCard: some View {
        let binding = currentBinding(for: selectedButton)
        let isEnabled = !binding.isDisabled
        let isGloballyPinned = mappingScope != .global &&
            store.isGloballyPinned(selectedButton, slot: .single)

        return workspaceCard(title: "单击", symbolName: "1.circle.fill") {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Toggle(
                        "启用单击",
                        isOn: Binding(
                            get: { !currentBinding(for: selectedButton).isDisabled },
                            set: { setCurrentSingleEnabled($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .disabled(isGloballyPinned)

                    Spacer(minLength: 12)
                    visualGlobalScopeControl(for: .single)
                }
                Picker(
                    "单击功能",
                    selection: Binding(
                        get: {
                            if case let .preset(action) = currentBinding(for: selectedButton) {
                                return action
                            }
                            return ButtonAction.disabled
                        },
                        set: { setCurrentBinding(.preset($0), for: selectedButton) }
                    )
                ) {
                    ForEach(availableActionCategories) { category in
                        actionPickerSections(for: category)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!isEnabled || isGloballyPinned)

                if case let .shortcut(chord, trigger) = binding {
                    HStack(spacing: 9) {
                        Label("自定义快捷键", systemImage: "command")
                            .font(.caption.weight(.medium))
                        Text(chord.displayName)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                        Picker("触发方式", selection: Binding(
                            get: { trigger },
                            set: { setCurrentBinding(.shortcut(chord, trigger: $0), for: selectedButton) }
                        )) {
                            ForEach(ShortcutTriggerMode.allCases) { mode in
                                Text(mode.shortLabel).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 125)
                        Button("重新录制") { recorderButton = selectedButton }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .disabled(isGloballyPinned)
                } else {
                    Button("录制自定义快捷键…") { recorderButton = selectedButton }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!isEnabled || isGloballyPinned)
                }

                mappingBehaviorStatus(
                    slot: .single,
                    enabled: isEnabled,
                    binding: binding
                )
            }
        }
    }

    private var visualAdditionalBehaviorCard: some View {
        let profile = currentGestureProfile(for: selectedButton)
        return workspaceCard(title: "双击与长按", symbolName: "hand.tap") {
            VStack(alignment: .leading, spacing: 12) {
                Text("每种行为独立启用；长按一次和长按重复二选一。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                visualGestureBehaviorRow(
                    slot: .doubleTap,
                    profile: profile
                )

                Divider()

                visualGestureBehaviorRow(
                    slot: .longPress,
                    profile: profile
                )
            }
        }
    }

    private var microphoneSingleBehaviorCard: some View {
        let binding = currentBinding(for: selectedButton)
        let isEnabled = !binding.isDisabled
        let isPersistentIME = binding == .voiceKeyDefault
        let isGloballyPinned = mappingScope != .global &&
            store.isGloballyPinned(selectedButton, slot: .single)
        return workspaceCard(title: "单击 · 外部语音输入", symbolName: "mic.circle.fill") {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Toggle(
                        "启用单击（无需一直按住）",
                        isOn: Binding(
                            get: { !currentBinding(for: selectedButton).isDisabled },
                            set: { setCurrentSingleEnabled($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .disabled(isGloballyPinned)

                    Spacer(minLength: 12)
                    visualGlobalScopeControl(for: .single)
                }
                if let microphoneShortBindingMessage {
                    Text(microphoneShortBindingMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker(
                    "单击语音方式",
                    selection: Binding<MicrophoneShortInputMode>(
                        get: {
                            switch currentBinding(for: selectedButton) {
                            case .preset(.chatGPTStartVoiceChat):
                                return MicrophoneShortInputMode.codexVoiceChat
                            default:
                                return MicrophoneShortInputMode.persistentIME
                            }
                        },
                        set: { mode in
                            setCurrentBinding(
                                mode == .codexVoiceChat
                                    ? .preset(.chatGPTStartVoiceChat)
                                    : .voiceKeyDefault,
                                for: selectedButton
                            )
                        }
                    )
                ) {
                    Text("输入法 · 持续会话")
                        .tag(MicrophoneShortInputMode.persistentIME)
                    Text("Codex · 语音对话")
                        .tag(MicrophoneShortInputMode.codexVoiceChat)
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!isEnabled || isGloballyPinned)

                HStack(spacing: 10) {
                    Text("持续会话激活键")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                    Picker("持续会话激活键", selection: Binding(
                        get: { selectedPersistentSessionTriggerKey },
                        set: { requestPersistentSessionTriggerKeyChange($0) }
                    )) {
                        ForEach(VoiceTriggerKey.allCases, id: \.self) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("持续会话激活键")
                    .disabled(isApplyingPersistentSessionTriggerKey)
                }
                if let persistentSessionTriggerMessage {
                    Text(persistentSessionTriggerMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text(
                    isPersistentIME
                        ? "请将输入法的语音输入快捷键设为 \(selectedPersistentSessionTriggerKey.displayName)。短按开启或结束持续会话；会话中按住和释放会录制遥控器麦克风片段。"
                        : binding.isDisabled
                            ? "单击已关闭；持续会话激活键仍保留独立配置。"
                            : "短按调用 Codex 语音对话；持续会话激活键仍保留独立配置。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                mappingBehaviorStatus(
                    slot: .single,
                    enabled: isEnabled,
                    binding: binding
                )
            }
        }
    }

    private func visualGestureBehaviorRow(
        slot: ButtonGestureSlot,
        profile: ButtonGestureProfile
    ) -> some View {
        let enabled = profile.isEnabled(for: slot)
        let globalSlot: GlobalMappingSlot = slot == .doubleTap ? .doubleTap : .longPress
        let isGloballyPinned = mappingScope != .global &&
            store.isGloballyPinned(selectedButton, slot: globalSlot)

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Toggle(
                    slot.displayName,
                    isOn: Binding(
                        get: { currentGestureProfile(for: selectedButton).isEnabled(for: slot) },
                        set: { setCurrentGestureEnabled($0, for: slot) }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(isGloballyPinned)

                Spacer(minLength: 12)
                visualGlobalScopeControl(for: globalSlot)
            }

            if slot == .longPress {
                HStack(spacing: 10) {
                    Text("执行方式")
                        .font(.caption.weight(.medium))
                    Picker(
                        "长按执行方式",
                        selection: Binding(
                            get: { currentGestureProfile(for: selectedButton).longPressBehavior },
                            set: { behavior in
                                var updated = currentGestureProfile(for: selectedButton)
                                updated.longPressBehavior = behavior
                                setCurrentGestureProfile(updated, for: selectedButton)
                            }
                        )
                    ) {
                        Text("长按一次").tag(ButtonLongPressBehavior.triggerOnce)
                        Text("长按重复").tag(ButtonLongPressBehavior.repeatWhileHeld)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                .disabled(!enabled || isGloballyPinned)
            }

            Picker(
                "\(slot.displayName)功能",
                selection: Binding(
                    get: {
                        guard case let .preset(action) = currentGestureProfile(
                            for: selectedButton
                        ).binding(for: slot) else { return ButtonAction.disabled }
                        return action
                    },
                    set: { action in
                        setCurrentGestureBinding(
                            action == .disabled ? nil : .preset(action),
                            for: selectedButton,
                            slot: slot
                        )
                    }
                )
            ) {
                ForEach(availableGestureActionCategories) { category in
                    actionPickerSections(for: category)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!enabled || isGloballyPinned)

            HStack(spacing: 9) {
                if let binding = profile.binding(for: slot) {
                    Label(
                        enabled && !binding.isDisabled
                            ? "当前：\(binding.displayName)"
                            : "未启用",
                        systemImage: enabled && !binding.isDisabled
                            ? "checkmark.circle"
                            : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(enabled && !binding.isDisabled ? .primary : .secondary)
                } else {
                    Text("未设置功能")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                if !isGloballyPinned {
                    Button("录制快捷键…") {
                        gestureRecorderTarget = GestureRecorderTarget(
                            button: selectedButton,
                            slot: slot
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func visualGlobalScopeControl(for slot: GlobalMappingSlot) -> some View {
        Toggle(
            "应用全局",
            isOn: Binding(
                get: { store.isGloballyPinned(selectedButton, slot: slot) },
                set: {
                    store.setGlobalPinning($0, for: selectedButton, slot: slot)
                }
            )
        )
        .toggleStyle(.checkbox)
        .font(.caption.weight(.medium))
        .tint(.orange)
        .help("勾选后，这个行为使用通用映射，不被当前程序模板覆盖")
    }

    private func mappingBehaviorStatus(
        slot: GlobalMappingSlot,
        enabled: Bool,
        binding: ButtonBinding
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(enabled ? Color.green : Color.secondary)
            Text(enabled ? "当前：\(currentBindingLabel(for: binding))" : "未启用")
                .font(.caption)
                .foregroundStyle(enabled ? .primary : .secondary)
            Spacer()
            if store.isGloballyPinned(selectedButton, slot: slot) {
                Label("全局", systemImage: "globe")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var mappingToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                pageHeader(
                    title: "按键映射",
                    description: "选择范围与模板",
                    symbolName: "slider.horizontal.3"
                )

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 7) {
                    Text("映射范围")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("映射范围", selection: Binding(
                        get: { mappingScopeKind },
                        set: { selectMappingScopeKind($0) }
                    )) {
                        Text("通用").tag(MappingScopeKind.global)
                        Text("程序").tag(MappingScopeKind.app)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }

            if case let .app(bundleID) = mappingScope {
                HStack(spacing: 10) {
                    Label("程序", systemImage: "app.badge")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    programScopeMenu(bundleID: bundleID)
                    Divider()
                        .frame(height: 20)
                    templateControlPanel
                    Spacer(minLength: 0)
                }
            } else {
                Label("通用映射", systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var mappingScopeKind: MappingScopeKind {
        if case .app = mappingScope {
            return .app
        }
        return .global
    }

    private func selectMappingScopeKind(_ kind: MappingScopeKind) {
        switch kind {
        case .global:
            selectMappingScope(.global)
        case .app:
            guard case .global = mappingScope else { return }
            if let app = configuredAppChoices.first ?? moreAppChoices.first {
                selectMappingScope(.app(app.bundleIdentifier))
            } else {
                showTemplateCreator = true
            }
        }
    }

    private func programScopeMenu(bundleID: String) -> some View {
        Menu {
            Button("通用映射") {
                selectMappingScope(.global)
            }

            if !configuredAppChoices.isEmpty {
                Divider()
                Section("已配置程序") {
                    ForEach(configuredAppChoices) { app in
                        Button(app.displayName) {
                            selectMappingScope(.app(app.bundleIdentifier))
                        }
                    }
                }
            }

            if !moreAppChoices.isEmpty {
                Menu("更多程序") {
                    ForEach(moreAppChoices) { app in
                        Button(app.displayName) {
                            selectMappingScope(.app(app.bundleIdentifier))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Text(mappingScopeDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .help("切换当前程序映射范围")
    }

    private var mappingButtonRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REMOTE BUTTONS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(RemoteButton.allCases.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(buttonGroups) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.title)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                            ForEach(group.buttons) { button in
                                buttonRow(button)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(14)
        .frame(width: 270, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
    }

    private func buttonRow(_ button: RemoteButton) -> some View {
        Button { selectedButton = button } label: {
            HStack(spacing: 10) {
                Image(systemName: buttonSymbol(for: button))
                    .frame(width: 20)
                    .foregroundStyle(selectedButton == button ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(button.displayName)
                        .font(.subheadline.weight(selectedButton == button ? .semibold : .regular))
                    Text(bindingSummary(for: button))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if store.isGloballyPinned(button) && mappingScope != .global {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selectedButton == button ? Color.accentColor.opacity(0.13) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var mappingEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedButton.displayName)
                            .font(.title2.weight(.semibold))
                        Text("HID 0x\(String(selectedButton.hidUsage, radix: 16, uppercase: true)) · \(selectedButton == .microphone ? "语音键特殊逻辑" : "遥控器按钮")")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("恢复此按钮默认") { resetSelectedButtonToDefault() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if selectedButton == .microphone {
                    microphoneSingleBehaviorCard
                    microphoneMomentaryTriggerCard(currentBinding(for: selectedButton))
                    microphoneSecondaryTriggerCard(currentBinding(for: selectedButton))
                } else {
                    bindingActionCard(currentBinding(for: selectedButton))
                }

                if case .global = mappingScope {
                    globalBehaviorCard
                } else if isSelectedButtonGloballyPinned {
                    pinnedBehaviorCard
                }

                if hasEditableScope {
                    VStack(alignment: .leading, spacing: 14) {
                        if selectedButton != .microphone {
                            advancedGestureCard
                        }
                    }
                    .disabled(isAppMappingLocked)
                    .opacity(isAppMappingLocked ? 0.55 : 1)
                } else {
                    workspaceCard(title: "等待选择模板", symbolName: "square.stack.3d.up") {
                        Text("这是程序范围。请先在顶部的“当前模板”中选择、导入或新建模板后，再编辑按键。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if isScrollAction(currentBinding(for: selectedButton)) {
                    workspaceCard(title: "滚动速度", symbolName: "arrow.up.and.down") {
                        scrollSpeedControl
                    }
                }

                Spacer(minLength: 20)
                HStack {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("重置当前范围", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .alert("确认重置当前范围", isPresented: $showResetConfirm) {
                        Button("取消", role: .cancel) {}
                        Button("重置", role: .destructive) {
                            resetCurrentMapping()
                        }
                    } message: {
                        Text(mappingScope == .global
                             ? "这将恢复通用映射中的所有按钮。"
                             : "这将恢复当前程序模板中的所有按钮。")
                    }
                    Spacer()
                    Label("修改会自动保存", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func bindingActionCard(_ binding: ButtonBinding) -> some View {
        workspaceCard(title: "当前生效", symbolName: "checkmark.circle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: binding.isDisabled ? "minus.circle" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(binding.isDisabled ? Color.secondary : Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentBindingLabel(for: binding))
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Picker("切换为预设动作", selection: Binding(
                        get: {
                            if case let .preset(action) = currentBinding(for: selectedButton) {
                                return action
                            }
                            return ButtonAction.disabled
                        },
                        set: { setCurrentBinding(.preset($0), for: selectedButton) }
                    )) {
                        ForEach(availableActionCategories) { category in
                            actionPickerSections(for: category)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                }

                Divider()

                if case let .shortcut(chord, trigger) = binding {
                    HStack(spacing: 10) {
                        Label("自定义快捷键", systemImage: "command")
                            .font(.subheadline.weight(.medium))
                        Text(chord.displayName)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Picker("触发方式", selection: Binding(
                            get: { trigger },
                            set: { setCurrentBinding(.shortcut(chord, trigger: $0), for: selectedButton) }
                        )) {
                            ForEach(ShortcutTriggerMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        Spacer(minLength: 0)
                        Button("重新录制") { recorderButton = selectedButton }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Text(trigger.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        Label("自定义快捷键", systemImage: "command")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button("录制快捷键…") { recorderButton = selectedButton }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Text("录制后会替换当前预设动作；如需恢复预设，直接从上方选择即可。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var advancedGestureCard: some View {
        let profile = currentGestureProfile(for: selectedButton)
        return workspaceCard(title: "复杂操作", symbolName: "hand.tap") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "使用复杂操作（双击 / 长按）",
                    isOn: Binding(
                        get: { currentGestureProfile(for: selectedButton).isEnabled },
                        set: {
                            var updated = currentGestureProfile(for: selectedButton)
                            updated.isEnabled = $0
                            setCurrentGestureProfile(updated, for: selectedButton)
                            if $0,
                               case let .shortcut(chord, trigger) = currentBinding(
                                   for: selectedButton
                               ),
                               trigger == .repeatWhileHeld {
                                // Once the advanced profile is enabled,
                                // repetition is controlled by the long-press
                                // selector below. Keep the base action atomic.
                                setCurrentBinding(
                                    .shortcut(chord, trigger: .single),
                                    for: selectedButton
                                )
                            }
                        }
                    )
                )
                Text("关闭时只使用单击映射；打开后，单击保留基础动作，并可分别设置双击与长按动作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if profile.isEnabled {
                    Divider()
                    gestureBindingRow(
                        slot: .doubleTap,
                        profile: profile
                    )

                    HStack {
                        Text("长按行为")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Picker(
                            "长按行为",
                            selection: Binding(
                                get: { currentGestureProfile(for: selectedButton).longPressBehavior },
                                set: {
                                    var updated = currentGestureProfile(for: selectedButton)
                                    updated.longPressBehavior = $0
                                    setCurrentGestureProfile(updated, for: selectedButton)
                                }
                            )
                        ) {
                            ForEach(ButtonLongPressBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    if profile.longPressBehavior != .none {
                        gestureBindingRow(
                            slot: .longPress,
                            profile: profile
                        )
                    }

                    Text(
                        profile.longPressBehavior == .repeatWhileHeld
                            ? "达到长按阈值后每约 100 ms 发送一次；适合滚动、方向移动、删除等可重复动作。"
                            : "短按会执行基础动作；超过长按阈值后只执行一次长按动作。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func gestureBindingRow(
        slot: ButtonGestureSlot,
        profile: ButtonGestureProfile
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slot.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("录制快捷键…") {
                    gestureRecorderTarget = GestureRecorderTarget(
                        button: selectedButton,
                        slot: slot
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if profile.binding(for: slot) != nil {
                    Button("清除") {
                        setCurrentGestureBinding(
                            nil,
                            for: selectedButton,
                            slot: slot
                        )
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            Picker(
                "\(slot.displayName)预设动作",
                selection: Binding(
                    get: {
                        guard case let .preset(action) = currentGestureProfile(
                            for: selectedButton
                        ).binding(for: slot)
                        else { return ButtonAction.disabled }
                        return action
                    },
                    set: { action in
                        setCurrentGestureBinding(
                            action == .disabled ? nil : .preset(action),
                            for: selectedButton,
                            slot: slot
                        )
                    }
                )
            ) {
                ForEach(availableGestureActionCategories) { category in
                    actionPickerSections(for: category)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 520)

            if let binding = profile.binding(for: slot) {
                Label(
                    "当前：\(binding.displayName)",
                    systemImage: binding.isDisabled ? "circle" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(binding.isDisabled ? .secondary : .primary)
            } else {
                Text("未设置额外动作")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var templateControlPanel: some View {
        if case let .app(bundleID) = mappingScope {
            let templates = store.templates(for: bundleID)
            return AnyView(
                HStack(spacing: 8) {
                    Text("模板")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: selectedEditorTemplate == nil
                          ? "circle.dashed"
                          : "checkmark.circle.fill")
                        .foregroundStyle(selectedEditorTemplate == nil ? Color.secondary : Color.green)
                        .help("绿色对勾表示 Active 模板")

                    if templates.isEmpty {
                        Text("无")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Active 模板", selection: Binding(
                            get: { selectedTemplateTarget },
                            set: { selectTemplate($0, for: bundleID) }
                        )) {
                            ForEach(templates) { template in
                                Text(template.templateName)
                                    .tag(TemplateTarget.template(template.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }

                    Button("套用") {
                        showTemplatePresetImporter = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.templatePresets(for: bundleID).isEmpty)

                    Button("新建") {
                        showTemplateCreator = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if selectedEditorTemplate != nil {
                        Button("删除", role: .destructive) {
                            templateToDelete = selectedEditorTemplate?.id
                            showDeleteTemplateConfirm = true
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            )
        }
        return AnyView(EmptyView())
    }

    private var globalBehaviorCard: some View {
        workspaceCard(title: "默认行为", symbolName: "globe") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "始终使用默认映射",
                    isOn: Binding(
                        get: { store.isGloballyPinned(selectedButton) },
                        set: { store.setGlobalPinning($0, for: selectedButton) }
                    )
                )
                Text("开启后，这个按钮不会被任何程序模板覆盖，适合系统音量、Home 或你希望保持一致的操作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pinnedBehaviorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("此按钮被默认映射锁定")
                    .font(.subheadline.weight(.semibold))
                Text("当前程序模板不会覆盖它；切回“通用”范围即可修改实际行为。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func microphoneMomentaryTriggerCard(_ binding: ButtonBinding) -> some View {
        workspaceCard(title: "直接长按 · 遥控器麦克风", symbolName: "mic.circle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("直接长按激活键")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                    Picker("直接长按激活键", selection: Binding(
                        get: { selectedMomentaryVoiceTriggerKey },
                        set: { requestVoiceTriggerKeyChange($0) }
                    )) {
                        ForEach(VoiceTriggerKey.allCases, id: \.self) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("直接长按激活键")
                    .disabled(isApplyingMomentaryVoiceTriggerKey)
                }
                if let momentaryVoiceTriggerMessage {
                    Text(momentaryVoiceTriggerMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(
                    binding.isDisabled
                        ? "单击已关闭；长按立即进入遥控器麦克风。"
                        : "长按经判定后进入遥控器麦克风，并使用此键激活语音输入。持续会话已打开时，长按只录制麦克风片段。"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func microphoneSecondaryTriggerCard(_ binding: ButtonBinding) -> some View {
        workspaceCard(title: "快速单击后长按 · Receiver B", symbolName: "mic.badge.plus") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("第二接收器激活键")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                    Picker("第二接收器激活键", selection: Binding(
                        get: { selectedSecondaryVoiceTriggerKey },
                        set: { requestSecondaryVoiceTriggerKeyChange($0, shortBinding: binding) }
                    )) {
                        Text("关闭").tag(nil as VoiceTriggerKey?)
                        ForEach(VoiceTriggerKey.allCases, id: \.self) { key in
                            Text(key.displayName).tag(Optional(key))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("第二接收器激活键")
                    .disabled(isApplyingSecondaryVoiceTriggerKey)
                }
                if let secondaryVoiceTriggerMessage {
                    Text(secondaryVoiceTriggerMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("直接长按进入 Receiver A；快速单击后在窗口内再次长按进入 Receiver B；单次快速点击不触发。仅当单击动作已禁用且两个激活键不同时启用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                installationCard

                mappingConfigurationCard

                workspaceCard(title: "应用设置", symbolName: "gearshape") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 18) {
                            Toggle("登录时自动启动", isOn: Binding(
                                get: { launchAtLoginEnabled },
                                set: { value in
                                    do {
                                        try LaunchAtLogin.setEnabled(value)
                                        launchAtLoginEnabled = LaunchAtLogin.isEnabled
                                    } catch {
                                        launchAtLoginEnabled = LaunchAtLogin.isEnabled
                                        print("[SETTINGS] 登录启动设置失败: \(error.localizedDescription)")
                                    }
                                }
                            ))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Toggle("记录运行日志", isOn: Binding(
                                get: { loggingEnabled },
                                set: { value in
                                    Log.setEnabled(value)
                                    loggingEnabled = Log.isEnabled
                                    if loggingEnabled {
                                        print("[APP] 日志已由用户开启")
                                    }
                                }
                            ))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Toggle("保存调试录音", isOn: Binding(
                                get: { recordingEnabled },
                                set: { value in
                                    AppStorage.recordingEnabled = value
                                    recordingEnabled = AppStorage.recordingEnabled
                                    onRecordingChanged(recordingEnabled)
                                }
                            ))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.checkbox)

                        Text("日志和调试录音只在这里管理，不再出现在菜单栏。调试录音会保存遥控器语音的 WAV 与原始数据。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    diagnosticCard(
                        title: "运行日志",
                        detail: AppStorage.formattedSize(Log.byteSize),
                        symbolName: "doc.text.magnifyingglass",
                        openAction: {
                            AppStorage.ensureDirectory(AppStorage.logsDirectory)
                            NSWorkspace.shared.open(AppStorage.logsDirectory)
                        },
                        clearAction: {
                            Log.clear()
                        }
                    )
                    diagnosticCard(
                        title: "调试录音",
                        detail: AppStorage.formattedSize(AppStorage.byteSize(of: AppStorage.recordingsDirectory)),
                        symbolName: "waveform",
                        openAction: {
                            AppStorage.ensureDirectory(AppStorage.recordingsDirectory)
                            NSWorkspace.shared.open(AppStorage.recordingsDirectory)
                        },
                        clearAction: {
                            AppStorage.clearFiles(in: AppStorage.recordingsDirectory)
                        }
                    )
                }

            }
            .padding(28)
        }
    }

    private func requestVoiceTriggerKeyChange(_ requestedKey: VoiceTriggerKey) {
        guard !isApplyingMomentaryVoiceTriggerKey else { return }
        let oldKey = selectedMomentaryVoiceTriggerKey
        isApplyingMomentaryVoiceTriggerKey = true
        momentaryVoiceTriggerMessage = nil

        onVoiceTriggerChanged(requestedKey) { result in
            switch result {
            case .applied:
                selectedMomentaryVoiceTriggerKey = requestedKey
                isApplyingMomentaryVoiceTriggerKey = false
                momentaryVoiceTriggerMessage = nil
            case .unchanged:
                selectedMomentaryVoiceTriggerKey = requestedKey
                isApplyingMomentaryVoiceTriggerKey = false
                momentaryVoiceTriggerMessage = nil
            case .busy:
                selectedMomentaryVoiceTriggerKey = oldKey
                isApplyingMomentaryVoiceTriggerKey = false
                momentaryVoiceTriggerMessage = "当前正在进行语音输入，请结束后再切换快捷键。"
            case .busyActiveHold:
                selectedMomentaryVoiceTriggerKey = oldKey
                isApplyingMomentaryVoiceTriggerKey = false
                momentaryVoiceTriggerMessage = "语音键仍按住，请先松开再切换激活键。"
            case .busyReleaseDrain:
                selectedMomentaryVoiceTriggerKey = oldKey
                isApplyingMomentaryVoiceTriggerKey = false
                momentaryVoiceTriggerMessage = "语音键已松开，等待按键释放或音频收尾完成后再切换。"
            case .failed:
                selectedMomentaryVoiceTriggerKey = oldKey
                isApplyingMomentaryVoiceTriggerKey = false
                momentaryVoiceTriggerMessage = "快捷键切换失败，已恢复原设置。"
            case .locked:
                selectedMomentaryVoiceTriggerKey = oldKey
                isApplyingMomentaryVoiceTriggerKey = false
                momentaryVoiceTriggerMessage = "语音快捷键运行时已锁定，请重新启动 RemoteOrbit 后重试。"
            }
        }
    }

    private func requestPersistentSessionTriggerKeyChange(_ requestedKey: VoiceTriggerKey) {
        guard !isApplyingPersistentSessionTriggerKey else { return }
        let oldKey = selectedPersistentSessionTriggerKey
        isApplyingPersistentSessionTriggerKey = true
        persistentSessionTriggerMessage = nil

        onPersistentSessionTriggerKeyChanged(requestedKey) { result in
            switch result {
            case .applied, .unchanged:
                selectedPersistentSessionTriggerKey = requestedKey
                isApplyingPersistentSessionTriggerKey = false
                persistentSessionTriggerMessage = nil
            case .busy:
                selectedPersistentSessionTriggerKey = oldKey
                isApplyingPersistentSessionTriggerKey = false
                persistentSessionTriggerMessage = "当前语音按键仍有活动所有权，完成后再切换。"
            case .busyActiveHold:
                selectedPersistentSessionTriggerKey = oldKey
                isApplyingPersistentSessionTriggerKey = false
                persistentSessionTriggerMessage = "语音键仍按住，请先松开再切换激活键。"
            case .busyReleaseDrain:
                selectedPersistentSessionTriggerKey = oldKey
                isApplyingPersistentSessionTriggerKey = false
                persistentSessionTriggerMessage = "语音键已松开，等待按键释放或音频收尾完成后再切换。"
            case .failed:
                selectedPersistentSessionTriggerKey = oldKey
                isApplyingPersistentSessionTriggerKey = false
                persistentSessionTriggerMessage = "快捷键切换失败，已恢复原设置。"
            case .locked:
                selectedPersistentSessionTriggerKey = oldKey
                isApplyingPersistentSessionTriggerKey = false
                persistentSessionTriggerMessage = "语音快捷键运行时已锁定，请重新启动 RemoteOrbit 后重试。"
            }
        }
    }

    private func requestSecondaryVoiceTriggerKeyChange(
        _ requestedKey: VoiceTriggerKey?,
        shortBinding: ButtonBinding
    ) {
        guard !isApplyingSecondaryVoiceTriggerKey else { return }
        let oldKey = selectedSecondaryVoiceTriggerKey
        isApplyingSecondaryVoiceTriggerKey = true
        secondaryVoiceTriggerMessage = nil

        onSecondaryVoiceTriggerKeyChanged(requestedKey, shortBinding) { result in
            switch result {
            case .applied, .unchanged:
                selectedSecondaryVoiceTriggerKey = requestedKey
                isApplyingSecondaryVoiceTriggerKey = false
                secondaryVoiceTriggerMessage = nil
            case .busy:
                selectedSecondaryVoiceTriggerKey = oldKey
                isApplyingSecondaryVoiceTriggerKey = false
                secondaryVoiceTriggerMessage = "当前语音手势仍在等待，请结束后再更改 Receiver B。"
            case .busyActiveHold:
                selectedSecondaryVoiceTriggerKey = oldKey
                isApplyingSecondaryVoiceTriggerKey = false
                secondaryVoiceTriggerMessage = "遥控器语音键仍按住，请松开后再更改 Receiver B。"
            case .busyReleaseDrain:
                selectedSecondaryVoiceTriggerKey = oldKey
                isApplyingSecondaryVoiceTriggerKey = false
                secondaryVoiceTriggerMessage = "语音输入正在收尾，请等待释放和音频收尾完成。"
            case .failed:
                selectedSecondaryVoiceTriggerKey = oldKey
                isApplyingSecondaryVoiceTriggerKey = false
                secondaryVoiceTriggerMessage = "Receiver B 无法启用，已恢复原设置。"
            case .locked:
                selectedSecondaryVoiceTriggerKey = oldKey
                isApplyingSecondaryVoiceTriggerKey = false
                secondaryVoiceTriggerMessage = "语音快捷键运行时已锁定，请重新启动 RemoteOrbit 后重试。"
            }
        }
    }

    private var mappingConfigurationCard: some View {
        workspaceCard(title: "配置导入与导出", symbolName: "arrow.up.arrow.down") {
            VStack(alignment: .leading, spacing: 12) {
                Text("配置保存在本机。需要复制按键映射时请手动导出；导入会替换当前映射、模板和 Active 选择，不会创建自动备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = store.configurationWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    Button("导出当前配置…", action: exportMappingConfiguration)
                        .buttonStyle(.bordered)
                    Button("导入配置…", action: importMappingConfiguration)
                        .buttonStyle(.bordered)
                }

                if let configurationMessage {
                    Text(configurationMessage)
                        .font(.caption)
                        .foregroundStyle(
                            configurationMessage.contains("失败") ? .red : .green
                        )
                }

            }
        }
    }

    private func exportMappingConfiguration() {
        let panel = NSSavePanel()
        panel.title = "导出 Remote Orbit 按键配置"
        panel.nameFieldStringValue = "RemoteOrbit-mapping.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.exportCurrentConfiguration(to: url)
            configurationMessage = "配置已导出：\(url.lastPathComponent)"
        } catch {
            configurationMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importMappingConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "导入 Remote Orbit 按键配置"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.importConfiguration(from: url)
            configurationMessage = "配置已导入：\(url.lastPathComponent)"
        } catch {
            configurationMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func diagnosticCard(
        title: String,
        detail: String,
        symbolName: String,
        openAction: @escaping () -> Void,
        clearAction: @escaping () -> Void
    ) -> some View {
        workspaceCard(title: title, symbolName: symbolName) {
            VStack(alignment: .leading, spacing: 12) {
                Text(detail)
                    .font(.title3.monospacedDigit().weight(.semibold))
                HStack {
                    Button("打开文件夹", action: openAction)
                        .buttonStyle(.bordered)
                    Button("清空", role: .destructive, action: clearAction)
                        .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var installationCard: some View {
        let driverStatus: (String, Color) = {
            if let deviceName = InstallationDiagnostics.audioDeviceName {
                return ("已安装 · \(deviceName)", .green)
            }
            if InstallationDiagnostics.audioDriverInstalled {
                return ("驱动已安装，设备未加载", .orange)
            }
            return ("未检测到", .red)
        }()

        return workspaceCard(title: "安装与设备检查", symbolName: "shippingbox") {
            VStack(alignment: .leading, spacing: 12) {
                installationStatusRow(
                    label: "应用本体",
                    value: InstallationDiagnostics.appInstalled ? "已安装" : "未检测到",
                    color: InstallationDiagnostics.appInstalled ? .green : .red
                )
                installationStatusRow(
                    label: "虚拟音频组件",
                    value: driverStatus.0,
                    color: driverStatus.1
                )
                installationStatusRow(
                    label: "输入监控",
                    value: HIDMonitor.isInputMonitoringGranted ? "已授权" : "需要授权",
                    color: HIDMonitor.isInputMonitoringGranted ? .green : .orange
                )
                installationStatusRow(
                    label: "辅助功能",
                    value: KeyInjector.isAccessibilityTrusted ? "已授权" : "需要授权",
                    color: KeyInjector.isAccessibilityTrusted ? .green : .orange
                )

                Divider()

                HStack(spacing: 10) {
                    Button {
                        beginInstallationRepair()
                    } label: {
                        if isRepairingInstallation {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在补装…")
                        } else {
                            Label("重新安装音频组件", systemImage: "arrow.clockwise.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        isRepairingInstallation ||
                            !InstallationDiagnostics.bundledAudioDriverAvailable
                    )

                    Button("重新检测") {
                        installationMessage = nil
                        installationRefreshID = UUID()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("打开输入监控") {
                        openSystemPrivacySettings(anchor: "Privacy_ListenEvent")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("打开辅助功能") {
                        openSystemPrivacySettings(anchor: "Privacy_Accessibility")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !InstallationDiagnostics.bundledAudioDriverAvailable {
                        Text("当前安装包未附带可补装的音频组件")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let installationMessage {
                    Text(installationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("首次安装或音频设备没有出现在系统中时，可在这里重新安装组件。macOS 会弹出管理员授权对话框，现有驱动会先保留为带时间戳的备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .id(installationRefreshID)
    }

    private func installationStatusRow(
        label: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
    }

    private func beginInstallationRepair() {
        guard !isRepairingInstallation else { return }
        isRepairingInstallation = true
        installationMessage = nil
        AudioPipe.shared.stop()

        InstallationRepair.reinstallBundledAudioDriver { result in
            let message: String
            switch result {
            case .success:
                message = "音频组件补装完成；正在重新加载设备。"
            case let .failure(error):
                message = error.localizedDescription
            }
            isRepairingInstallation = false
            installationMessage = message

            // coreaudiod is restarted by the privileged installer. Give it a
            // moment to publish the device before probing and reopening HAL.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AudioPipe.shared.restartOutputDevice()
                installationRefreshID = UUID()
            }
        }
    }

    private var aboutPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                workspaceCard(title: "产品信息", symbolName: "waveform.circle") {
                    VStack(alignment: .leading, spacing: 10) {
                        aboutLine(label: "产品", value: ProductIdentity.name)
                        aboutLine(label: "版本", value: ProductIdentity.versionLabel)
                        aboutLine(label: "Bundle ID", value: ProductIdentity.bundleIdentifier)
                        aboutLine(label: "音频设备", value: "RemoteOrbit Mic 2ch")
                    }
                }

                workspaceCard(title: "独立项目边界", symbolName: "checkmark.shield") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("这是 RemoteOrbit 自己的产品界面、配置空间和安装身份。按键模板、日志和录音都使用独立的本地路径。")
                        Text("当前版本不需要连接其他项目的运行时或配置；适配器只在你主动启用对应程序模板时参与。")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Text("© 2026 Lost0rz · RemoteOrbit")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
        }
    }

    private func pageHeader(title: String, description: String, symbolName: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metricCard(title: String, value: String, detail: String, symbolName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbolName)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func workspaceCard<Content: View>(
        title: String,
        symbolName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func logicRow(index: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func diagnosticLine(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.medium))
        }
    }

    private func aboutLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.body.monospaced())
            Spacer()
        }
    }

    private var buttonGroups: [ButtonGroup] {
        [
            ButtonGroup(
                title: "语音与系统",
                buttons: [.microphone, .power, .home, .menu, .tv]
            ),
            ButtonGroup(
                title: "方向与确认",
                buttons: [.up, .left, .ok, .right, .down, .back]
            ),
            ButtonGroup(
                title: "音量",
                buttons: [.volumeUp, .volumeDown]
            ),
        ]
    }

    private func openSystemPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func buttonSymbol(for button: RemoteButton) -> String {
        switch button {
        case .microphone: return "mic"
        case .power: return "power"
        case .up: return "arrow.up"
        case .left: return "arrow.left"
        case .ok: return "checkmark"
        case .right: return "arrow.right"
        case .down: return "arrow.down"
        case .back: return "arrow.uturn.backward"
        case .volumeUp: return "speaker.plus"
        case .home: return "house"
        case .volumeDown: return "speaker.minus"
        case .menu: return "line.3.horizontal"
        case .tv: return "rectangle.on.rectangle"
        }
    }

    private func resetSelectedButtonToDefault() {
        if case let .template(id) = selectedTemplateTarget,
           selectedEditorTemplate != nil,
           !store.isGloballyPinned(selectedButton, slot: .single) {
            let template = selectedEditorTemplate
            let defaultBinding = AppTemplatePresetLibrary.all.first(where: {
                $0.appBundleIdentifier == template?.appBundleIdentifier &&
                $0.templateName == template?.templateName
            })?.bindings[selectedButton]
                ?? DefaultBindings.all[selectedButton]
                ?? .preset(.disabled)
            store.setBinding(defaultBinding, for: selectedButton, templateID: id)
            store.setGestureProfile(.disabled, for: selectedButton, templateID: id)
        } else {
            let defaultBinding = DefaultBindings.all[selectedButton] ?? .preset(.disabled)
            store.setBinding(defaultBinding, for: selectedButton)
            store.setGestureProfile(.disabled, for: selectedButton)
        }
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

    private var availableActionCategories: [ButtonActionCategory] {
        var allowed: Set<ButtonActionCategory> = [
            .system,
            .navigation,
            .editing,
            .selection,
            .media,
        ]
        if case .global = mappingScope {
            allowed.insert(.applications)
        }
        if case let .app(bundleID) = mappingScope {
            allowed.formUnion(AppTemplatePresetLibrary.categories(for: bundleID))
        }
        return ButtonActionCategory.allCases.filter { allowed.contains($0) }
    }

    private var availableGestureActionCategories: [ButtonActionCategory] {
        var allowed: Set<ButtonActionCategory> = [
            .system,
            .navigation,
            .editing,
            .selection,
            .media,
        ]
        switch mappingScope {
        case .global:
            // Application launchers are global-only actions. An app-specific
            // action must never leak into the global gesture picker.
            allowed.insert(.applications)
        case let .app(bundleID):
            // The selected app contributes only its own preset categories.
            // Do not add categories from the current gesture profile: an old
            // or migrated binding can otherwise make FloatTabs/Codex actions
            // appear while editing another app.
            allowed.formUnion(AppTemplatePresetLibrary.categories(for: bundleID))
        }
        return ButtonActionCategory.allCases.filter { allowed.contains($0) }
    }

    private func actions(in category: ButtonActionCategory) -> [ButtonAction] {
        ButtonAction.allCases.filter { $0.category == category }
    }

    /// Obsidian 的动作数量较多：保留一个 App 作用域，并在选择器里按
    /// 工作区、标签、笔记、命令和视图继续分组，避免和其他程序的动作混在一起。
    @ViewBuilder
    private func actionPickerSections(for category: ButtonActionCategory) -> some View {
        if category == .obsidian {
            ForEach(ObsidianActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.obsidianGroup == group }) {
                        action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        } else {
            Section(category.displayName) {
                ForEach(actions(in: category)) { action in
                    Text(action.displayName).tag(action)
                }
            }
        }
    }

    private var templatePresetChoicesForCurrentScope: [AppTemplatePreset] {
        guard case let .app(bundleID) = mappingScope else { return [] }
        return store.templatePresets(for: bundleID)
    }

    private func appSymbolName(for bundleIdentifier: String) -> String {
        switch bundleIdentifier {
        case MappingStore.codexBundleIdentifier:
            return "sparkles.rectangle.stack"
        case "md.obsidian":
            return "note.text"
        case MappingStore.floatTabsBundleIdentifier:
            return "rectangle.on.rectangle.angled"
        default:
            return "app"
        }
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

    private func selectSection(_ section: WorkspaceSection) {
        if section == .mappings {
            Self.resetMappingEditorEntry(
                scope: &mappingScope,
                selectedButton: &selectedButton,
                selectedTemplateTarget: &selectedTemplateTarget
            )
        }
        selectedSection = section
    }

    static func resetMappingEditorEntry(
        scope: inout MappingScope,
        selectedButton: inout RemoteButton,
        selectedTemplateTarget: inout TemplateTarget
    ) {
        scope = .global
        selectedButton = .microphone
        selectedTemplateTarget = .none
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
        if store.isGloballyPinned(button, slot: .single) {
            return store.binding(for: button)
        }
        guard case let .template(id) = selectedTemplateTarget,
              selectedEditorTemplate != nil
        else {
            return store.binding(for: button)
        }
        return store.binding(for: button, templateID: id)
    }

    private func currentGestureProfile(for button: RemoteButton) -> ButtonGestureProfile {
        guard case let .template(id) = selectedTemplateTarget,
              selectedEditorTemplate != nil
        else {
            return store.gestureProfile(for: button)
        }
        let templateProfile = store.gestureProfile(for: button, templateID: id)
        var merged = templateProfile
        let globalProfile = store.gestureProfile(for: button)
        if store.isGloballyPinned(button, slot: .doubleTap) {
            merged.doubleTapEnabled = globalProfile.doubleTapEnabled
            merged.doubleTap = globalProfile.doubleTap
        }
        if store.isGloballyPinned(button, slot: .longPress) {
            merged.longPressEnabled = globalProfile.longPressEnabled
            merged.longPress = globalProfile.longPress
            merged.longPressBehavior = globalProfile.longPressBehavior
        }
        return merged
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
        if case .app = mappingScope, store.isGloballyPinned(button, slot: .single) {
            return
        }
        let templateID: UUID?
        if case let .template(id) = selectedTemplateTarget,
           selectedEditorTemplate != nil {
            templateID = id
        } else {
            templateID = nil
        }
        let persistBinding = {
            if let templateID {
                store.setBinding(binding, for: button, templateID: templateID)
            } else {
                store.setBinding(binding, for: button)
            }
        }
        guard button == .microphone else {
            persistBinding()
            return
        }

        onMicrophoneShortBindingChanged(binding) { result in
            switch result {
            case .applied, .unchanged:
                persistBinding()
                microphoneShortBindingMessage = nil
            case .busy:
                microphoneShortBindingMessage = "语音手势仍在等待，请结束后再更改单击动作。"
            case .busyActiveHold:
                microphoneShortBindingMessage = "语音键仍按住，请松开后再更改单击动作。"
            case .busyReleaseDrain:
                microphoneShortBindingMessage = "语音输入正在收尾，请等待音频释放完成后再更改。"
            case .failed:
                microphoneShortBindingMessage = "语音路由尚未就绪，单击动作未更改。"
            case .locked:
                microphoneShortBindingMessage = "语音运行时已锁定，单击动作未更改。"
            }
        }
    }

    private func setCurrentGestureProfile(
        _ profile: ButtonGestureProfile,
        for button: RemoteButton
    ) {
        guard hasEditableScope else { return }
        guard case let .template(id) = selectedTemplateTarget,
              selectedEditorTemplate != nil
        else {
            store.setGestureProfile(profile, for: button)
            return
        }
        var editableProfile = profile
        let globalProfile = store.gestureProfile(for: button)
        if store.isGloballyPinned(button, slot: .doubleTap) {
            editableProfile.doubleTapEnabled = globalProfile.doubleTapEnabled
            editableProfile.doubleTap = globalProfile.doubleTap
        }
        if store.isGloballyPinned(button, slot: .longPress) {
            editableProfile.longPressEnabled = globalProfile.longPressEnabled
            editableProfile.longPress = globalProfile.longPress
            editableProfile.longPressBehavior = globalProfile.longPressBehavior
        }
        store.setGestureProfile(editableProfile, for: button, templateID: id)
    }

    private func setCurrentSingleEnabled(_ enabled: Bool) {
        guard hasEditableScope else { return }
        if case .app = mappingScope,
           store.isGloballyPinned(selectedButton, slot: .single) {
            return
        }
        let binding = currentBinding(for: selectedButton)
        if enabled {
            guard binding.isDisabled else { return }
            setCurrentBinding(
                DefaultBindings.all[selectedButton] ?? .preset(.disabled),
                for: selectedButton
            )
        } else {
            setCurrentBinding(.preset(.disabled), for: selectedButton)
        }
    }

    private func setCurrentGestureEnabled(
        _ enabled: Bool,
        for slot: ButtonGestureSlot
    ) {
        guard hasEditableScope else { return }
        let globalSlot: GlobalMappingSlot = slot == .doubleTap ? .doubleTap : .longPress
        if case .app = mappingScope,
           store.isGloballyPinned(selectedButton, slot: globalSlot) {
            return
        }
        var profile = currentGestureProfile(for: selectedButton)
        profile.setEnabled(enabled, for: slot)
        if enabled,
           slot == .longPress,
           profile.longPressBehavior == .none {
            profile.longPressBehavior = .triggerOnce
        }
        setCurrentGestureProfile(profile, for: selectedButton)
    }

    private func setCurrentGestureBinding(
        _ binding: ButtonBinding?,
        for button: RemoteButton,
        slot: ButtonGestureSlot
    ) {
        var profile = currentGestureProfile(for: button)
        profile.setBinding(binding, for: slot)
        if slot == .longPress, binding == nil {
            profile.longPressBehavior = .none
        }
        setCurrentGestureProfile(profile, for: button)
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

private struct SettingsRemotePreview: View {
    let selectedButton: RemoteButton
    let bindingFor: (RemoteButton) -> ButtonBinding
    let profileFor: (RemoteButton) -> ButtonGestureProfile
    let onSelect: (RemoteButton) -> Void

    private let canvasSize = CGSize(width: 228, height: 555)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("遥控器布局", systemImage: "rectangle.portrait.and.arrow.forward")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("13 键")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("点击任意实体按键，右侧编辑它的单击、双击和长按。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                remoteShell

                remoteButton(.power, size: 31)
                    .position(x: 86, y: 48)
                remoteButton(.microphone, size: 31)
                    .position(x: 142, y: 48)

                dPad
                    .position(x: 114, y: 153)

                remoteButton(.back, size: 34)
                    .position(x: 86, y: 256)
                volumeButtons
                    .position(x: 144, y: 303)
                remoteButton(.home, size: 34)
                    .position(x: 86, y: 326)
                remoteButton(.menu, size: 34)
                    .position(x: 86, y: 397)
                remoteButton(.tv, size: 34)
                    .position(x: 142, y: 397)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)

            selectedMappingSummary
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var remoteShell: some View {
        RoundedRectangle(cornerRadius: 42, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        Color.white.opacity(0.72),
                        Color.gray.opacity(0.35),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 150, height: 530)
            .overlay(
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .stroke(Color.white.opacity(0.95), lineWidth: 1.2)
            )
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.32), .clear, Color.blue.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
            )
            .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }

    private var dPad: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.72))
                .frame(width: 116, height: 116)
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .frame(width: 76, height: 76)

            remoteButton(.up, size: 32).position(x: 58, y: 17)
            remoteButton(.left, size: 32).position(x: 17, y: 58)
            remoteButton(.ok, size: 42).position(x: 58, y: 58)
            remoteButton(.right, size: 32).position(x: 99, y: 58)
            remoteButton(.down, size: 32).position(x: 58, y: 99)
        }
        .frame(width: 116, height: 116)
    }

    private var volumeButtons: some View {
        VStack(spacing: 1) {
            remoteButton(.volumeUp, size: 34)
            Divider()
                .overlay(Color.white.opacity(0.34))
                .frame(width: 21)
            remoteButton(.volumeDown, size: 34)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.70))
                .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 1))
        )
    }

    private func remoteButton(_ button: RemoteButton, size: CGFloat) -> some View {
        Button {
            onSelect(button)
        } label: {
            ZStack {
                Circle()
                    .fill(
                        selectedButton == button
                            ? Color.accentColor.opacity(0.90)
                            : Color.black.opacity(0.72)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                selectedButton == button
                                    ? Color.white
                                    : Color.white.opacity(0.25),
                                lineWidth: selectedButton == button ? 2 : 1
                            )
                    )

                if button == .tv {
                    Text("TV")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                } else if button == .ok {
                    Text("OK")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                } else if button == .volumeUp {
                    Text("+")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                } else if button == .volumeDown {
                    Text("−")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                } else {
                    Image(systemName: symbolName(for: button))
                        .font(.system(size: max(11, size * 0.34), weight: .semibold))
                }
            }
            .frame(width: size, height: size)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.52), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .help(actionSummary(for: button))
        .accessibilityLabel("\(button.displayName)：\(actionSummary(for: button))")
    }

    private var selectedMappingSummary: some View {
        let lines = KeymapPresentation.actionLines(
            for: selectedButton,
            binding: bindingFor(selectedButton),
            profile: profileFor(selectedButton)
        )

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("当前按键")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedButton.displayName)
                    .font(.caption.weight(.bold))
            }

            ForEach(lines) { line in
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(gestureColor(for: line.gesture))
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                    Text(line.gesture)
                        .font(.caption2.weight(.semibold))
                        .frame(width: 52, alignment: .leading)
                    Text(line.action)
                        .font(.caption2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func actionSummary(for button: RemoteButton) -> String {
        let lines = KeymapPresentation.actionLines(
            for: button,
            binding: bindingFor(button),
            profile: profileFor(button)
        )
        return lines.map { "\($0.gesture)：\($0.action)" }.joined(separator: "；")
    }

    private func gestureColor(for gesture: String) -> Color {
        if gesture.contains("双击") { return .mint }
        if gesture.contains("长按") { return .orange }
        return .cyan
    }

    private func symbolName(for button: RemoteButton) -> String {
        switch button {
        case .microphone: return "mic.fill"
        case .power: return "power"
        case .up: return "chevron.up"
        case .left: return "chevron.left"
        case .ok: return "checkmark"
        case .right: return "chevron.right"
        case .down: return "chevron.down"
        case .back: return "arrow.uturn.backward"
        case .volumeUp: return "speaker.plus"
        case .home: return "house.fill"
        case .volumeDown: return "speaker.minus"
        case .menu: return "line.3.horizontal"
        case .tv: return "rectangle.on.rectangle"
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
    let title: String?
    let showsTriggerMode: Bool
    let clearButtonTitle: String
    let onCancel: () -> Void
    let onClear: () -> Void
    let onRecord: (KeyChord, ShortcutTriggerMode) -> Void

    @State private var triggerMode: ShortcutTriggerMode

    @State private var captureMonitor: ShortcutCaptureMonitor?
    @State private var pendingTermination: RecorderTermination?
    @State private var preview = "请按下快捷键"
    @State private var errorText = ""

    private enum RecorderTermination {
        case cancel
        case clear
    }

    init(
        button: RemoteButton,
        title: String? = nil,
        showsTriggerMode: Bool = true,
        clearButtonTitle: String = "禁用这个按键",
        initialTriggerMode: ShortcutTriggerMode,
        onCancel: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onRecord: @escaping (KeyChord, ShortcutTriggerMode) -> Void
    ) {
        self.button = button
        self.title = title
        self.showsTriggerMode = showsTriggerMode
        self.clearButtonTitle = clearButtonTitle
        self.onCancel = onCancel
        self.onClear = onClear
        self.onRecord = onRecord
        _triggerMode = State(initialValue: initialTriggerMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title ?? "设置 \(button.displayName) 的快捷键")
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

            if showsTriggerMode {
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
                Button(clearButtonTitle) { requestTermination(.clear) }
                Spacer()
                Button("取消") { requestTermination(.cancel) }
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { startMonitoring() }
        .onDisappear { stopMonitoring() }
    }

    private func startMonitoring() {
        stopMonitoring()
        preview = "请按下快捷键"
        errorText = ""

        let initialFlags = CGEventSource.flagsState(.combinedSessionState)
        let monitor = ShortcutCaptureMonitor(
            initiallyHeldFlags: initialFlags,
            triggerModeProvider: { triggerMode }
        )
        monitor.onPreview = { value in
            preview = value
            errorText = ""
        }
        monitor.onError = { value in
            errorText = value
        }
        monitor.onRecord = { chord, trigger in
            preview = chord.displayName
            onRecord(chord, trigger)
        }
        monitor.onStopped = {
            finishPendingTermination()
        }
        captureMonitor = monitor
        if !monitor.start() {
            captureMonitor = nil
        }
    }

    private func stopMonitoring() {
        if captureMonitor?.stop() == true {
            captureMonitor = nil
            pendingTermination = nil
        }
    }

    private func requestTermination(_ termination: RecorderTermination) {
        pendingTermination = termination
        if captureMonitor == nil || captureMonitor?.requestCancel() == true {
            finishPendingTermination()
        }
    }

    private func finishPendingTermination() {
        guard let termination = pendingTermination else { return }
        pendingTermination = nil
        captureMonitor = nil
        switch termination {
        case .cancel:
            onCancel()
        case .clear:
            onClear()
        }
    }
}
