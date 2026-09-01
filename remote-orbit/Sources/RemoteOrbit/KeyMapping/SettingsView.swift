// SettingsView.swift — RemoteOrbit Control Center
//
// 产品级设置工作区：概览、按键映射、设置与诊断和关于。
// Shortcut recording remains in this file so the recorder shares the mapping
// model and uses the same product-specific window flow.

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MappingStore
    var onRecordingChanged: (Bool) -> Void = { _ in }
    @State private var selectedSection: WorkspaceSection = .overview
    @State private var selectedButton: RemoteButton = .back
    @State private var mappingScope: MappingScope = .global
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

    private enum MappingScope: Hashable {
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

    private enum TemplateTarget: Hashable {
        case none
        case template(UUID)
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
        .frame(minWidth: 980, minHeight: 660)
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
                    gestureRecorderTarget = nil
                },
                onRecord: { chord, _ in
                    setCurrentGestureBinding(
                        .shortcut(chord, trigger: .single),
                        for: target.button,
                        slot: target.slot
                    )
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
                    selectedSection = section
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
                pageHeader(
                    title: "概览",
                    description: "RemoteOrbit 正在后台监听遥控器，并把按钮动作交给当前 App。",
                    symbolName: "rectangle.grid.2x2"
                )

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
                        Text("先在“按键映射”顶部选择通用或程序范围；程序专属模板统一在右下角创建和套用。")
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
        VStack(spacing: 0) {
            mappingToolbar
            Divider()

            HStack(spacing: 0) {
                mappingButtonRail
                Divider()
                mappingEditor
            }
        }
    }

    private var mappingToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                pageHeader(
                    title: "按键映射",
                    description: "先确定映射范围，再为每个按键定义动作。模板只在下方管理。",
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
                    Label("当前程序", systemImage: "app.badge")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    programScopeMenu(bundleID: bundleID)
                    Spacer(minLength: 0)
                    Text("模板在右下角选择和管理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("通用映射 · 对所有没有独立程序模板的场景生效", systemImage: "globe")
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

                bindingSummaryCard(currentBinding(for: selectedButton))

                if case .global = mappingScope {
                    globalBehaviorCard
                } else if isSelectedButtonGloballyPinned {
                    pinnedBehaviorCard
                }

                if hasEditableScope {
                    VStack(alignment: .leading, spacing: 14) {
                        if selectedButton != .microphone {
                            presetActionCard
                        }
                        customShortcutCard
                        if selectedButton != .microphone {
                            advancedGestureCard
                        }
                    }
                    .disabled(isAppMappingLocked)
                    .opacity(isAppMappingLocked ? 0.55 : 1)
                } else {
                    workspaceCard(title: "等待选择模板", symbolName: "square.stack.3d.up") {
                        Text("这是程序范围。请在右下角的“模板”模块中新建、导入或选择一个模板后，再编辑按键。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if selectedButton == .microphone {
                    microphoneBehaviorCard(currentBinding(for: selectedButton))
                }

                if isScrollAction(currentBinding(for: selectedButton)) {
                    workspaceCard(title: "滚动速度", symbolName: "arrow.up.and.down") {
                        scrollSpeedControl
                    }
                }

                if case .app = mappingScope {
                    templateControlPanel
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

    private var presetActionCard: some View {
        workspaceCard(title: "预设动作", symbolName: "bolt.circle") {
            VStack(alignment: .leading, spacing: 10) {
                Text("使用有语义的动作，RemoteOrbit 会负责向当前 App 发送对应事件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("预设动作", selection: Binding(
                    get: {
                        if case let .preset(action) = currentBinding(for: selectedButton) { return action }
                        return ButtonAction.disabled
                    },
                    set: { setCurrentBinding(.preset($0), for: selectedButton) }
                )) {
                    ForEach(availableActionCategories) { category in
                        Section(category.displayName) {
                            ForEach(actions(in: category)) { action in
                                Text(action.displayName).tag(action)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 480)
            }
        }
    }

    private var customShortcutCard: some View {
        workspaceCard(title: "自定义快捷键", symbolName: "command") {
            VStack(alignment: .leading, spacing: 12) {
                if case let .shortcut(chord, trigger) = currentBinding(for: selectedButton) {
                    HStack(spacing: 10) {
                        Text(chord.displayName)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                        .frame(width: 180)
                        Spacer()
                        Button("重新录制") { recorderButton = selectedButton }
                            .buttonStyle(.bordered)
                    }
                    Text(trigger.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("还没有自定义快捷键。录制后会覆盖当前按钮的预设动作。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("录制快捷键…") { recorderButton = selectedButton }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var advancedGestureCard: some View {
        let profile = currentGestureProfile(for: selectedButton)
        return workspaceCard(title: "额外按键手势", symbolName: "hand.tap") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "启用额外按键手势",
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
                Text("未启用时完全沿用上面的单击映射。启用后，单击仍执行基础动作；双击和长按使用下面的额外动作。")
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
                    Section(category.displayName) {
                        ForEach(actions(in: category)) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
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
                workspaceCard(title: "模板", symbolName: "square.stack.3d.up") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("当前程序")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(mappingScopeDisplayName)
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                            if let selected = selectedEditorTemplate {
                                Label(
                                    store.isActiveTemplate(selected.id) ? "Active" : "未激活",
                                    systemImage: store.isActiveTemplate(selected.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .font(.caption.weight(.medium))
                                .foregroundStyle(
                                    store.isActiveTemplate(selected.id) ? .green : .orange
                                )
                            }
                        }

                        if templates.isEmpty {
                            Text("当前程序还没有模板。可以新建空白模板，或从下方导入一个预设模板。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("编辑模板", selection: Binding(
                                get: { selectedTemplateTarget },
                                set: { selectTemplate($0, for: bundleID) }
                            )) {
                                ForEach(templates) { template in
                                    Text(template.templateName + (store.isActiveTemplate(template.id) ? " · Active" : ""))
                                        .tag(TemplateTarget.template(template.id))
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 420)

                            HStack(spacing: 10) {
                                if let selected = selectedEditorTemplate,
                                   !store.isActiveTemplate(selected.id) {
                                    Button("设为 Active") {
                                        store.setActiveTemplate(selected.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }

                                if selectedEditorTemplate != nil {
                                    Button("删除模板", role: .destructive) {
                                        templateToDelete = selectedEditorTemplate?.id
                                        showDeleteTemplateConfirm = true
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                }
                            }
                        }

                        Divider()

                        HStack(spacing: 10) {
                            Button("套用预设模板") {
                                showTemplatePresetImporter = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(store.templatePresets(for: bundleID).isEmpty)

                            Button("新建空白模板") {
                                showTemplateCreator = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text("选择模板后在上方编辑按键；Active 模板才会在该程序运行时生效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private func bindingSummaryCard(_ binding: ButtonBinding) -> some View {
        HStack(spacing: 12) {
            Image(systemName: binding.isDisabled ? "minus.circle" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(binding.isDisabled ? .secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("当前生效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentBindingLabel(for: binding))
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
            }
            Spacer()
            Text(mappingScope == .global ? "通用" : "程序模板")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func microphoneBehaviorCard(_ binding: ButtonBinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text("语音键的独立逻辑")
                    .font(.subheadline.weight(.semibold))
                if case .voiceKeyDefault = binding {
                    Text("短按使用本机物理麦克风，长按切换到遥控器麦克风，并由 RemoteOrbit 统一处理。")
                } else {
                    Text("当前已改为自定义动作，短按/长按语音桥接行为不会执行。")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var diagnosticsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "设置与诊断",
                    description: "管理启动、日志、调试录音和系统权限。",
                    symbolName: "gearshape.2"
                )

                installationCard

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
                pageHeader(
                    title: "关于 RemoteOrbit",
                    description: "独立的遥控器、语音和快捷键控制中心。",
                    symbolName: "info.circle"
                )

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
        let defaultBinding = DefaultBindings.all[selectedButton] ?? .preset(.disabled)
        if case let .template(id) = selectedTemplateTarget,
           selectedEditorTemplate != nil,
           !store.isGloballyPinned(selectedButton) {
            store.setBinding(defaultBinding, for: selectedButton, templateID: id)
            store.setGestureProfile(.disabled, for: selectedButton, templateID: id)
        } else {
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

    private func currentGestureProfile(for button: RemoteButton) -> ButtonGestureProfile {
        if store.isGloballyPinned(button) {
            return store.gestureProfile(for: button)
        }
        guard case let .template(id) = selectedTemplateTarget,
              selectedEditorTemplate != nil
        else {
            return store.gestureProfile(for: button)
        }
        return store.gestureProfile(for: button, templateID: id)
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

    private func setCurrentGestureProfile(
        _ profile: ButtonGestureProfile,
        for button: RemoteButton
    ) {
        guard hasEditableScope else { return }
        if case .app = mappingScope, store.isGloballyPinned(button) {
            return
        }
        guard case let .template(id) = selectedTemplateTarget,
              selectedEditorTemplate != nil
        else {
            store.setGestureProfile(profile, for: button)
            return
        }
        store.setGestureProfile(profile, for: button, templateID: id)
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

    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var heldModifiers: KeyChord.Modifiers = []
    @State private var heldModifierKeyCodes = Set<UInt16>()
    @State private var didCapture = false
    @State private var preview = "请按下快捷键"
    @State private var errorText = ""

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
                Button(clearButtonTitle, action: onClear)
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
