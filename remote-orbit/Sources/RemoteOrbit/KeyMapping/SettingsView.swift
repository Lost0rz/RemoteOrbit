// SettingsView.swift — RemoteOrbit Control Center
//
// 产品级设置工作区：通用设置、按键映射与关于。
// Shortcut recording remains in this file so the recorder shares the mapping
// model and uses the same product-specific window flow.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: MappingStore
    @ObservedObject var voiceShortcutPresentation: VoiceShortcutPresentation
    @ObservedObject var navigation: SettingsNavigationModel
    var onRecordingChanged: (Bool) -> Void = { _ in }

    @State private var selectedSection: WorkspaceSection = .general
    @State private var selectedButton: RemoteButton = .microphone
    @State private var mappingScope: MappingScope = .global
    @State private var selectedTemplateTarget: TemplateTarget = .none
    @State private var recorderButton: RemoteButton?
    @State private var gestureRecorderTarget: GestureRecorderTarget?
    @State private var voiceShortcutEditorRequest: VoiceShortcutEditorRequest?
    @State private var voiceShortcutStatus: String?
    @State private var showResetConfirm = false
    @State private var templateCreatorRequest: TemplateCreatorRequest?
    @State private var showTemplatePresetImporter = false
    @State private var showDeleteTemplateConfirm = false
    @State private var templateToDelete: UUID?

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var loggingEnabled = Log.isEnabled
    @State private var recordingEnabled = AppStorage.recordingEnabled
    @State private var isRepairingInstallation = false
    @State private var isInstallingVirtualHID = false
    @State private var installationMessage: String?
    @State private var installationRefreshID = UUID()
    @State private var storageRefreshID = UUID()
    @State private var configurationMessage: String?
    @State private var isExportingDiagnostics = false
    @State private var diagnosticExportMessage: String?
    @State private var exportedArchiveURL: URL?

    init(
        store: MappingStore,
        voiceShortcutPresentation: VoiceShortcutPresentation = .shared,
        navigation: SettingsNavigationModel = SettingsNavigationModel(),
        onRecordingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.voiceShortcutPresentation = voiceShortcutPresentation
        self.navigation = navigation
        self.onRecordingChanged = onRecordingChanged
    }

    enum MappingScope: Hashable {
        case global
        case app(String)
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

    enum TemplateCreatorRequest: Identifiable {
        case addApplication
        case newTemplateForApp(bundleIdentifier: String, appName: String)

        var id: String {
            switch self {
            case .addApplication:
                return "add-application"
            case let .newTemplateForApp(bundleID, _):
                return "new-template-\(bundleID)"
            }
        }
    }

    private enum WorkspaceSection: String, CaseIterable, Identifiable {
        case general
        case mappings
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "通用设置"
            case .mappings: return "按键映射"
            case .about: return "关于"
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "运行状态、启动、组件与日志"
            case .mappings: return "通用与程序专属快捷键"
            case .about: return "版本与产品信息"
            }
        }

        var symbolName: String {
            switch self {
            case .general: return "gearshape.2"
            case .mappings: return "slider.horizontal.3"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        workspace
            .frame(minWidth: 1_020, minHeight: 660)
            .onAppear {
                applyNavigationRoute(navigation.routeRequest.route)
            }
            .onChange(of: navigation.routeRequest) { request in
                applyNavigationRoute(request.route)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )
            ) { _ in
                refreshLiveState()
            }
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
                        let effectiveTrigger: ShortcutTriggerMode =
                            currentGestureProfile(for: button).usesAdvancedGestures
                            ? .single
                            : trigger
                        setCurrentBinding(
                            .shortcut(chord, trigger: effectiveTrigger),
                            for: button
                        )
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
            .sheet(item: $voiceShortcutEditorRequest) { request in
                VoiceShortcutEditorSheet(
                    request: request,
                    onCancel: { voiceShortcutEditorRequest = nil },
                    onSave: { entry, completion in
                        saveVoiceShortcutEntry(entry, completion: completion)
                    }
                )
            }
            .sheet(item: $templateCreatorRequest) { request in
                AppTemplateCreatorSheet(
                    request: request,
                    installedApps: Self.installedApplicationsChoices(),
                    configuredBundleIDs: Set(configuredAppChoices.map(\.bundleIdentifier)),
                    onCancel: { templateCreatorRequest = nil },
                    onCreateBlank: { app, templateName in
                        let id = store.addTemplate(
                            appBundleIdentifier: app.bundleIdentifier,
                            appName: app.displayName,
                            templateName: templateName
                        )
                        mappingScope = .app(app.bundleIdentifier)
                        selectedTemplateTarget = .template(id)
                        templateCreatorRequest = nil
                    },
                    onImportPreset: { app, preset in
                        if let id = store.applyTemplatePreset(
                            preset.id,
                            for: app.bundleIdentifier,
                            appName: app.displayName
                        ) {
                            mappingScope = .app(app.bundleIdentifier)
                            selectedTemplateTarget = .template(id)
                        }
                        templateCreatorRequest = nil
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
                            if let id = store.applyTemplatePreset(
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
            Text("功能导航")
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
        case .general:
            generalPage
        case .mappings:
            mappingsPage
        case .about:
            aboutPage
        }
    }

    // MARK: - 通用设置

    private var generalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                runtimeStatusCard
                preferencesCard
                installationCard
                mappingConfigurationCard
                logsAndDiagnosticsSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var runtimeStatusCard: some View {
        let health = DiagnosticRuntimeHealthRegistry.shared.snapshot()
        let hidActive = health["hid_device_active"] == .bool(true)
        let bleConnected = health["ble_connected"] == .bool(true)
        let streaming = health["atvv_streaming"] == .bool(true)
        let audioOutputReady = AudioPipe.shared.isOutputReady
        let activeEntry = voiceShortcutPresentation.snapshot.activeEntry

        let hidDisplay: (String, Color) = {
            guard hidActive else { return ("未连接（请按任意按键唤醒或检查蓝牙配对）", .red) }
            if SecureEventInputDiagnostics.isSecureEventInputEnabled {
                return ("已连接（系统安全输入激活，语音旁路可用）", .orange)
            }
            return ("已连接", .green)
        }()

        let voiceLinkDisplay: (String, Color) = {
            if streaming {
                return ("正在采集遥控器语音", .green)
            }
            if bleConnected {
                return ("BLE 已连接 · 待命", .green)
            }
            if hidActive {
                return ("待命（按住语音键约 300ms 启动）", .green)
            }
            return ("等待遥控器连接", .secondary)
        }()

        let audioOutputDisplay: (String, Color) = audioOutputReady
            ? ("RemoteOrbit Mic 2ch · 已就绪", .green)
            : ("未就绪", .orange)

        return workspaceCard(title: "运行与连接状态", symbolName: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 11) {
                installationStatusRow(label: "遥控器 HID", value: hidDisplay.0, color: hidDisplay.1)
                installationStatusRow(label: "蓝牙语音链路", value: voiceLinkDisplay.0, color: voiceLinkDisplay.1)
                installationStatusRow(label: "虚拟音频输出", value: audioOutputDisplay.0, color: audioOutputDisplay.1)

                Divider()

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前语音快捷键")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(
                            activeEntry.map { "\($0.displayName)（\($0.binding.sideDescription)）" }
                                ?? "未配置"
                        )
                        .font(.callout.weight(.medium))
                    }
                    Spacer()
                    Button("管理语音快捷键…") {
                        navigation.navigate(to: .voiceShortcuts)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .id(installationRefreshID)
    }

    private var preferencesCard: some View {
        workspaceCard(title: "通用偏好", symbolName: "gearshape") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    Toggle("登录时自动启动", isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { value in
                            do {
                                try LaunchAtLogin.setEnabled(value)
                                launchAtLoginEnabled = LaunchAtLogin.isEnabled
                                launchAtLoginError = nil
                            } catch {
                                launchAtLoginEnabled = LaunchAtLogin.isEnabled
                                launchAtLoginError = error.localizedDescription
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
                            storageRefreshID = UUID()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle("保存调试录音", isOn: Binding(
                        get: { recordingEnabled },
                        set: { value in
                            AppStorage.recordingEnabled = value
                            recordingEnabled = AppStorage.recordingEnabled
                            onRecordingChanged(recordingEnabled)
                            storageRefreshID = UUID()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.checkbox)

                if LaunchAtLogin.needsPathUpdate {
                    Label(
                        "当前登录启动项指向的旧路径与本次运行位置不同，建议取消勾选后重新开启以更新启动路径。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if let launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if DiagnosticsRuntimeGate.shared.isEnvironmentOverrideEnabled {
                    Label(
                        "当前检测到环境变量 REMOTE_ORBIT_DIAGNOSTICS=1，结构化诊断收集正由环境变量强制开启。",
                        systemImage: "info.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Text("日志与调试录音只在此处管理，不占用菜单栏。调试录音会保存遥控器语音的 WAV 与原始数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                scrollSpeedControl
            }
        }
    }

    private var logsAndDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                diagnosticCard(
                    title: "运行日志与诊断记录",
                    detail: AppStorage.formattedSize(AppStorage.logsTotalByteSize()),
                    symbolName: "doc.text.magnifyingglass",
                    openAction: {
                        AppStorage.ensureDirectory(AppStorage.logsDirectory)
                        NSWorkspace.shared.open(AppStorage.logsDirectory)
                    },
                    clearAction: {
                        AppStorage.clearAllLogs()
                        storageRefreshID = UUID()
                    }
                )
                diagnosticCard(
                    title: "调试录音",
                    detail: AppStorage.formattedSize(
                        AppStorage.byteSize(of: AppStorage.recordingsDirectory)
                    ),
                    symbolName: "waveform",
                    openAction: {
                        AppStorage.ensureDirectory(AppStorage.recordingsDirectory)
                        NSWorkspace.shared.open(AppStorage.recordingsDirectory)
                    },
                    clearAction: {
                        AppStorage.clearFiles(in: AppStorage.recordingsDirectory)
                        storageRefreshID = UUID()
                    }
                )
            }
            .id(storageRefreshID)

            workspaceCard(title: "诊断包导出", symbolName: "shippingbox.and.arrow.backward") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("打包当前运行健康快照、结构化 JSONL 诊断日志与文本日志（含校验和），用于问题排查。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            exportDiagnosticBundle()
                        } label: {
                            if isExportingDiagnostics {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在导出…")
                            } else {
                                Label("导出诊断包…", systemImage: "square.and.arrow.up")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isExportingDiagnostics)

                        if let exportedArchiveURL {
                            Button("在访达中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([exportedArchiveURL])
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    if let diagnosticExportMessage {
                        Text(diagnosticExportMessage)
                            .font(.caption)
                            .foregroundStyle(
                                diagnosticExportMessage.contains("失败") ? .red : .green
                            )
                    }
                }
            }
        }
    }

    private func exportDiagnosticBundle() {
        guard !isExportingDiagnostics else { return }
        let panel = NSOpenPanel()
        panel.title = "选择诊断包导出目录"
        panel.prompt = "导出到此目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let outputDirectory = panel.url else { return }

        isExportingDiagnostics = true
        diagnosticExportMessage = nil
        exportedArchiveURL = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let archiveURL = try DiagnosticExporter().export(
                    options: DiagnosticExportOptions(outputDirectory: outputDirectory)
                )
                DispatchQueue.main.async {
                    isExportingDiagnostics = false
                    exportedArchiveURL = archiveURL
                    diagnosticExportMessage = "诊断包已导出：\(archiveURL.lastPathComponent)"
                }
            } catch {
                DispatchQueue.main.async {
                    isExportingDiagnostics = false
                    diagnosticExportMessage = "导出诊断包失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 按键映射

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
                templateCreatorRequest = .addApplication
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
        .help("切换通用映射或已配置的程序模板；也可以在菜单底部添加 /Applications 中的应用程序")
    }

    private var visualMappingEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                visualMappingScopeBar

                if case .app = mappingScope, !hasEditableScope {
                    workspaceCard(title: "先创建一个程序模板", symbolName: "square.stack.3d.up.badge.plus") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("这个程序还没有可编辑的模板。可以直接套用内置预设，或者新建一个模板。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Button("套用预设模板") {
                                    showTemplatePresetImporter = true
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(templatePresetChoicesForCurrentScope.isEmpty)
                                Button("新建模板…") {
                                    if case let .app(bundleID) = mappingScope {
                                        templateCreatorRequest = .newTemplateForApp(
                                            bundleIdentifier: bundleID,
                                            appName: mappingScopeDisplayName
                                        )
                                    }
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
                            isGloballyOverridden: { button in
                                mappingScope != .global && isButtonGloballyOverridden(button)
                            },
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

    private func isButtonGloballyOverridden(_ button: RemoteButton) -> Bool {
        button != .microphone
            && GlobalMappingSlot.allCases.contains { store.isGloballyPinned(button, slot: $0) }
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
                    .frame(maxWidth: 190)
                }

                if !store.templatePresets(for: bundleID).isEmpty {
                    Button("套用预设…") {
                        showTemplatePresetImporter = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("新建模板…") {
                    templateCreatorRequest = .newTemplateForApp(
                        bundleIdentifier: bundleID,
                        appName: mappingScopeDisplayName
                    )
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
            } else {
                Text("通用映射会作为未配置程序的基础行为；如需为具体软件单独配键，请在左侧菜单添加程序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                if selectedButton != .microphone {
                    Button("恢复默认") {
                        resetSelectedButtonToDefault()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if selectedButton == .microphone {
                microphoneVoiceControlCard
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
                     ? "这将恢复通用映射中的所有按钮并重置默认全局锁定。"
                     : "这将恢复当前程序模板中的所有按钮与默认手势。")
            }
        }
    }

    private var visualSingleBehaviorCard: some View {
        let binding = currentBinding(for: selectedButton)
        let isEnabled = !binding.isDisabled
        let isGloballyPinned = mappingScope != .global &&
            store.isGloballyPinned(selectedButton, slot: .single)
        let advancedActive = currentGestureProfile(for: selectedButton).usesAdvancedGestures

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

                actionPicker(
                    title: "单击功能",
                    selection: Binding(
                        get: {
                            if case let .preset(action) = currentBinding(for: selectedButton) {
                                return action
                            }
                            return ButtonAction.disabled
                        },
                        set: { setCurrentBinding(.preset($0), for: selectedButton) }
                    )
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!isEnabled || isGloballyPinned)

                if case let .shortcut(chord, trigger) = binding {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 9) {
                            Label("自定义快捷键", systemImage: "command")
                                .font(.caption.weight(.medium))
                            Text(chord.displayName)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            Picker("触发方式", selection: Binding(
                                get: { advancedActive ? .single : trigger },
                                set: { setCurrentBinding(.shortcut(chord, trigger: $0), for: selectedButton) }
                            )) {
                                ForEach(ShortcutTriggerMode.allCases) { mode in
                                    Text(mode.shortLabel).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 125)
                            .disabled(advancedActive)

                            Button("重新录制") { recorderButton = selectedButton }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .disabled(isGloballyPinned)

                        if advancedActive {
                            Text("启用双击或长按后，单击固定按单次执行；长按连发请在下方“长按重复”中配置。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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

    private var microphoneVoiceControlCard: some View {
        workspaceCard(title: "语音键 · 直接传输控制", symbolName: "mic.circle.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("按住达到约 300ms 开始直接远程语音；松开后等待输出收尾，再释放语音快捷键")
                    .font(.callout)

                if let reason = voiceShortcutPresentation.readOnlyReason {
                    Label(reason.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(voiceShortcutPresentation.snapshot.entries) { entry in
                    HStack(spacing: 8) {
                        Button {
                            activateVoiceShortcut(entry.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: entry.id == voiceShortcutPresentation.snapshot.activeEntryID
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(entry.id == voiceShortcutPresentation.snapshot.activeEntryID
                                                     ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.displayName)
                                        .font(.callout.weight(.medium))
                                    Text(entry.binding.sideDescription)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                if entry.id == voiceShortcutPresentation.snapshot.activeEntryID {
                                    Text("Active")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(voiceShortcutPresentation.readOnlyReason != nil)

                        Spacer(minLength: 8)
                        Button("编辑") {
                            voiceShortcutEditorRequest = VoiceShortcutEditorRequest(entry: entry, isNew: false)
                        }
                        .controlSize(.small)
                        .disabled(voiceShortcutPresentation.readOnlyReason != nil)
                        Button(role: .destructive) {
                            deleteVoiceShortcut(entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(voiceShortcutPresentation.readOnlyReason != nil
                                  || voiceShortcutPresentation.snapshot.entries.count <= 1)
                    }
                    .padding(.vertical, 3)
                }

                HStack {
                    Button("添加语音快捷键…") {
                        voiceShortcutEditorRequest = VoiceShortcutEditorRequest(
                            entry: VoiceShortcutEntry(
                                displayName: "自定义语音快捷键",
                                binding: .pureModifier(.leftOption)
                            ),
                            isNew: true
                        )
                    }
                    .disabled(voiceShortcutPresentation.readOnlyReason != nil)
                    Spacer()
                }

                if let voiceShortcutStatus {
                    Text(voiceShortcutStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("菜单栏“语音输入”也可切换 Active。快捷键变化只影响之后开始的长按会话。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func activateVoiceShortcut(_ id: String) {
        var proposed = voiceShortcutPresentation.snapshot
        proposed.activeEntryID = id
        updateVoiceShortcutSnapshot(proposed)
    }

    private func deleteVoiceShortcut(_ id: String) {
        let snapshot = voiceShortcutPresentation.snapshot
        let replacement = snapshot.activeEntryID == id
            ? snapshot.entries.first(where: { $0.id != id })?.id
            : nil
        do {
            let proposed = try VoiceShortcutStore.deletingEntry(
                id: id,
                from: snapshot,
                replacementActiveID: replacement
            )
            updateVoiceShortcutSnapshot(proposed)
        } catch {
            voiceShortcutStatus = error.localizedDescription
        }
    }

    private func saveVoiceShortcutEntry(
        _ entry: VoiceShortcutEntry,
        completion: @escaping (String?) -> Void
    ) {
        do {
            let proposed = try VoiceShortcutStore.replacingEntry(
                entry,
                in: voiceShortcutPresentation.snapshot
            )
            voiceShortcutPresentation.updateSnapshot(proposed) { result in
                DispatchQueue.main.async {
                    if result == .applied || result == .unchanged {
                        voiceShortcutStatus = nil
                        voiceShortcutEditorRequest = nil
                        completion(nil)
                    } else {
                        let message = voiceShortcutFailureMessage(result)
                        voiceShortcutStatus = message
                        completion(message)
                    }
                }
            }
        } catch {
            voiceShortcutStatus = error.localizedDescription
            completion(error.localizedDescription)
        }
    }

    private func updateVoiceShortcutSnapshot(_ proposed: VoiceShortcutSnapshot) {
        voiceShortcutPresentation.updateSnapshot(proposed) { result in
            DispatchQueue.main.async {
                if result == .applied || result == .unchanged {
                    voiceShortcutStatus = nil
                } else {
                    voiceShortcutStatus = voiceShortcutFailureMessage(result)
                }
            }
        }
    }

    private func voiceShortcutFailureMessage(_ result: VoiceTriggerApplyResult) -> String {
        switch result {
        case .busy, .busyActiveHold:
            return "语音键仍处于按住状态。请松开后重试；当前 Active 保持不变。"
        case .busyReleaseDrain:
            return "语音输出仍在收尾。等待收尾完成后重试；当前 Active 保持不变。"
        case .locked:
            return "语音快捷键运行时已锁定。请重启 RemoteOrbit 后重试；当前 Active 保持不变。"
        case .failed:
            return "运行时应用或快照回读失败。当前 Active 保持不变，请重试。"
        case .applied, .unchanged:
            return ""
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
        let currentActionBinding = profile.binding(for: slot)
        let isEffective = slot == .doubleTap
            ? (enabled && currentActionBinding?.isUsableGestureAction == true)
            : (enabled && currentActionBinding?.isUsableGestureAction == true && profile.longPressBehavior != .none)

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
                        selection: Binding<ButtonLongPressBehavior>(
                            get: {
                                let behavior = currentGestureProfile(for: selectedButton).longPressBehavior
                                return behavior == .repeatWhileHeld ? .repeatWhileHeld : .triggerOnce
                            },
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

            actionPicker(
                title: "\(slot.displayName)功能",
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
            )
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!enabled || isGloballyPinned)

            HStack(spacing: 9) {
                if let binding = currentActionBinding, !binding.isDisabled {
                    Label(
                        isEffective
                            ? "当前：\(binding.displayName)"
                            : "已配置（未启用）：\(binding.displayName)",
                        systemImage: isEffective ? "checkmark.circle" : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(isEffective ? .primary : .secondary)
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
        .help("勾选后全局统一使用通用映射，覆盖具体程序的模板差异")
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

    // MARK: - 配置与安装检查卡片

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
            if case let .app(bundleID) = mappingScope {
                if let active = store.activeTemplate(for: bundleID) {
                    selectedTemplateTarget = .template(active.id)
                } else if let first = store.templates(for: bundleID).first {
                    selectedTemplateTarget = .template(first.id)
                    store.setActiveTemplate(first.id)
                } else {
                    mappingScope = .global
                    selectedTemplateTarget = .none
                }
            }
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
        let appDisplay: (String, Color) = {
            switch InstallationDiagnostics.appInstallLocationStatus {
            case .installedInApplications:
                return ("已安装（/Applications）", .green)
            case let .runningOutsideApplications(path):
                return ("从外部位置运行：\(path)（建议移入 /Applications）", .orange)
            case .developmentBinary:
                return ("未检测到 .app 安装", .red)
            }
        }()
        let driverStatus: (String, Color) = {
            if let deviceName = InstallationDiagnostics.audioDeviceName {
                return ("已安装 · \(deviceName)", .green)
            }
            if InstallationDiagnostics.audioDriverInstalled {
                return ("驱动已安装，设备未加载", .orange)
            }
            return ("未检测到", .red)
        }()
        let virtualHIDState = InstallationDiagnostics.virtualHIDStatus
        let virtualHIDDisplay: (String, Color) = {
            switch virtualHIDState {
            case .ready:
                return ("已就绪 · 支持任意真实组合键", .green)
            case .helperUpdateRequired:
                return ("已就绪 · 守护服务有可用更新", .orange)
            case .awaitingDriverApproval:
                return ("等待系统扩展批准（请在登录项与扩展中允许）", .orange)
            case .daemonDisconnected:
                return ("守护服务未连接", .orange)
            case .notInstalled:
                return ("未安装", .red)
            }
        }()

        return workspaceCard(title: "安装与权限检查", symbolName: "shippingbox") {
            VStack(alignment: .leading, spacing: 12) {
                installationStatusRow(
                    label: "应用本体",
                    value: appDisplay.0,
                    color: appDisplay.1
                )
                installationStatusRow(
                    label: "虚拟音频组件",
                    value: driverStatus.0,
                    color: driverStatus.1
                )
                installationStatusRow(
                    label: "虚拟键盘驱动",
                    value: virtualHIDDisplay.0,
                    color: virtualHIDDisplay.1
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
                if SecureEventInputDiagnostics.isSecureEventInputEnabled {
                    installationStatusRow(
                        label: "系统安全输入",
                        value: "\(SecureEventInputDiagnostics.secureInputOwnerSummary ?? "已开启") · 已切换 BLE 语音旁路，普通遥控器改键暂时受系统限制",
                        color: .orange
                    )
                }

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

                    if virtualHIDState == .helperUpdateRequired,
                       InstallationDiagnostics.bundledHIDHelperDaemonURL != nil {
                        Button {
                            beginVirtualHIDHelperUpdate()
                        } label: {
                            if isInstallingVirtualHID {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在更新守护服务…")
                            } else {
                                Label("更新虚拟键盘守护服务", systemImage: "arrow.triangle.2.circlepath.circle")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isInstallingVirtualHID || isRepairingInstallation)
                    } else if virtualHIDState != .ready, InstallationDiagnostics.bundledVirtualHIDAvailable {
                        Button {
                            beginVirtualHIDInstallation()
                        } label: {
                            if isInstallingVirtualHID {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在安装虚拟键盘…")
                            } else {
                                Label(
                                    virtualHIDState == .notInstalled ? "安装并启用虚拟键盘驱动" : "修复虚拟键盘服务",
                                    systemImage: "keyboard.badge.ellipsis"
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isInstallingVirtualHID || isRepairingInstallation)
                    }

                    if virtualHIDState == .awaitingDriverApproval, InstallationDiagnostics.karabinerManagerInstalled {
                        Button("激活虚拟键盘扩展") {
                            InstallationRepair.activateVirtualHIDDriverExtension { result in
                                switch result {
                                case let .success(msg):
                                    installationMessage = msg
                                case let .failure(err):
                                    installationMessage = err.localizedDescription
                                }
                                installationRefreshID = UUID()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("重新检测") {
                        installationMessage = nil
                        if !RuntimeEnvironment.isRunningTests {
                            VoiceShortcutHIDUnixSocketProvider.shared.refreshStatusNow()
                        }
                        refreshLiveState()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            installationRefreshID = UUID()
                        }
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
                .multilineTextAlignment(.trailing)
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

    private func beginVirtualHIDInstallation() {
        guard !isInstallingVirtualHID else { return }
        isInstallingVirtualHID = true
        installationMessage = nil

        InstallationRepair.reinstallBundledVirtualHIDStack { result in
            finishVirtualHIDRepair(result)
        }
    }

    private func beginVirtualHIDHelperUpdate() {
        guard !isInstallingVirtualHID else { return }
        isInstallingVirtualHID = true
        installationMessage = nil

        InstallationRepair.updateBundledHIDHelperDaemon { result in
            finishVirtualHIDRepair(result)
        }
    }

    private func finishVirtualHIDRepair(_ result: Result<String, Error>) {
        isInstallingVirtualHID = false
        switch result {
        case let .success(msg):
            installationMessage = msg
        case let .failure(error):
            installationMessage = error.localizedDescription
        }
        installationRefreshID = UUID()
        for delay in [0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !RuntimeEnvironment.isRunningTests {
                    VoiceShortcutHIDUnixSocketProvider.shared.refreshStatusNow()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    installationRefreshID = UUID()
                }
            }
        }
    }

    // MARK: - 关于

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

                workspaceCard(title: "本地隐私与作用域", symbolName: "checkmark.shield") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RemoteOrbit 所有快捷键模板、语音快捷键、运行日志与调试录音均只保存在本机目录中。")
                        Text("程序专属映射仅在对应应用程序位于前台（或存在对应焦点）时生效，并在按下遥控器按键的瞬间锁定目标，避免切窗误触发。")
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

    // MARK: - Shared UI components

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
           let template = selectedEditorTemplate,
           !store.isGloballyPinned(selectedButton, slot: .single) {
            let matchingPreset = AppTemplatePresetLibrary.all.first(where: {
                $0.appBundleIdentifier == template.appBundleIdentifier &&
                $0.templateName == template.templateName
            })
            let defaultBinding = matchingPreset?.bindings[selectedButton]
                ?? DefaultBindings.all[selectedButton]
                ?? .preset(.disabled)
            let defaultProfile = matchingPreset?.gestureProfiles?[selectedButton] ?? .disabled
            store.setBinding(defaultBinding, for: selectedButton, templateID: id)
            store.setGestureProfile(defaultProfile, for: selectedButton, templateID: id)
        } else {
            let defaultBinding = DefaultBindings.all[selectedButton] ?? .preset(.disabled)
            store.setBinding(defaultBinding, for: selectedButton)
            store.setGestureProfile(.disabled, for: selectedButton)
        }
    }

    // MARK: - Footer & scroll speed

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

    // MARK: - Action picker structure (generic + strictly app-exclusive)

    static func orderedActionCategories(for scope: MappingScope) -> [ButtonActionCategory] {
        let generic: [ButtonActionCategory] = [
            .navigation,
            .editing,
            .selection,
            .media,
            .system,
        ]
        switch scope {
        case .global:
            return generic + [.applications]
        case let .app(bundleID):
            return AppTemplatePresetLibrary.exclusiveCategories(for: bundleID) + generic
        }
    }

    private func actionPicker(
        title: String,
        selection: Binding<ButtonAction>
    ) -> some View {
        let categories = Self.orderedActionCategories(for: mappingScope)
        let allowedActions = Set(
            ButtonAction.allCases.filter { action in
                action != .disabled && categories.contains(action.category)
            }
        )
        let currentSelection = selection.wrappedValue

        return Picker(title, selection: selection) {
            Text(ButtonAction.disabled.displayName).tag(ButtonAction.disabled)

            ForEach(categories) { category in
                actionPickerSections(for: category)
            }

            if currentSelection != .disabled && !allowedActions.contains(currentSelection) {
                Section("已保存动作") {
                    Text(currentSelection.displayName).tag(currentSelection)
                }
            }
        }
    }

    private func actions(in category: ButtonActionCategory) -> [ButtonAction] {
        ButtonAction.allCases.filter { action in
            action.category == category && action != .disabled
        }
    }

    @ViewBuilder
    private func actionPickerSections(for category: ButtonActionCategory) -> some View {
        switch category {
        case .navigation:
            ForEach(NavigationActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.navigationGroup == group }) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        case .selection:
            ForEach(SelectionActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.selectionGroup == group }) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        case .ghostty:
            ForEach(GhosttyActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.ghosttyGroup == group }) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        case .browser:
            ForEach(BrowserActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.browserGroup == group }) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        case .iina:
            ForEach(IINAActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.iinaGroup == group }) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        case .codeWorkspace:
            ForEach(CodeWorkspaceActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.codeWorkspaceGroup == group }) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        case .t3Code:
            ForEach(T3CodeActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.t3CodeGroup == group }) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        case .obsidian:
            ForEach(ObsidianActionGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(actions(in: category).filter { $0.obsidianGroup == group }) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        default:
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
        case "com.t3tools.t3code":
            return "sparkles.square.filled.on.square"
        case "com.google.GeminiMacOS":
            return "sparkles"
        case "com.google.antigravity":
            return "chevron.left.forwardslash.chevron.right"
        case "md.obsidian":
            return "note.text"
        case MappingStore.floatTabsBundleIdentifier:
            return "rectangle.on.rectangle.angled"
        case "com.mitchellh.ghostty":
            return "terminal"
        case "com.colliderli.iina":
            return "play.rectangle"
        case "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser":
            return "safari"
        case "com.tencent.xinWeChat":
            return "message"
        case "com.netease.163music":
            return "music.note"
        case "com.apple.dt.Xcode":
            return "hammer"
        default:
            return "app"
        }
    }

    private var configuredAppChoices: [AppTemplateChoice] {
        // 已经建过模板的 App 固定显示在主菜单顶部，方便随时切换编辑。
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

    private var mappingScopeDisplayName: String {
        switch mappingScope {
        case .global:
            return "通用映射"
        case let .app(bundleID):
            if let app = configuredAppChoices.first(where: { $0.bundleIdentifier == bundleID }) {
                return app.displayName
            }
            if let app = Self.installedApplicationsChoices().first(where: {
                $0.bundleIdentifier == bundleID
            }) {
                return app.displayName
            }
            return bundleID
        }
    }

    // MARK: - /Applications-only app discovery

    static func installedApplicationsChoices(
        applicationsDirectoryURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> [AppTemplateChoice] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: applicationsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var byBundleID: [String: AppTemplateChoice] = [:]
        for url in entries {
            guard url.pathExtension.lowercased() == "app" else { continue }
            guard let info = infoDictionary(forAppAt: url),
                  let rawBundleID = info["CFBundleIdentifier"] as? String else {
                continue
            }
            let bundleID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty else { continue }
            guard bundleID != ProductIdentity.canonicalBundleIdentifier,
                  !bundleID.hasPrefix(ProductIdentity.canonicalBundleIdentifier + ".") else {
                continue
            }
            if isBackgroundOnlyApp(info: info) || isUninstallerApp(url: url, bundleID: bundleID) {
                continue
            }

            let displayName = resolvedApplicationDisplayName(
                bundleID: bundleID,
                info: info,
                appURL: url
            )
            byBundleID[bundleID] = AppTemplateChoice(
                bundleIdentifier: bundleID,
                displayName: displayName
            )
        }

        return byBundleID.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func infoDictionary(forAppAt appURL: URL) -> [String: Any]? {
        if let bundle = Bundle(url: appURL), let info = bundle.infoDictionary {
            return info
        }
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        return NSDictionary(contentsOf: plistURL) as? [String: Any]
    }

    private static func isBackgroundOnlyApp(info: [String: Any]) -> Bool {
        if let flag = info["LSBackgroundOnly"] as? Bool, flag {
            return true
        }
        if let str = info["LSBackgroundOnly"] as? String,
           str == "1" || str.lowercased() == "true" {
            return true
        }
        return false
    }

    private static func isUninstallerApp(url: URL, bundleID: String) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        return bundleID.localizedCaseInsensitiveContains("uninstaller")
            || name.localizedCaseInsensitiveContains("uninstaller")
    }

    private static func resolvedApplicationDisplayName(
        bundleID: String,
        info: [String: Any],
        appURL: URL
    ) -> String {
        if let known = AppTemplatePresetLibrary.knownApps.first(where: {
            $0.bundleIdentifier == bundleID
        }) {
            return known.displayName
        }
        if let localized = Bundle(url: appURL)?.localizedInfoDictionary,
           let display = localized["CFBundleDisplayName"] as? String ?? localized["CFBundleName"] as? String,
           !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return display
        }
        if let display = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String,
           !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return display
        }
        return appURL.deletingPathExtension().lastPathComponent
    }

    // MARK: - Navigation & scope state helpers

    private func applyNavigationRoute(_ route: SettingsEntryRoute) {
        switch route {
        case .general:
            selectedSection = .general
        case .voiceShortcuts:
            Self.resetMappingEditorEntry(
                scope: &mappingScope,
                selectedButton: &selectedButton,
                selectedTemplateTarget: &selectedTemplateTarget
            )
            selectedSection = .mappings
        }
        refreshLiveState()
    }

    private func refreshLiveState() {
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
        loggingEnabled = Log.isEnabled
        recordingEnabled = AppStorage.recordingEnabled
        installationRefreshID = UUID()
        storageRefreshID = UUID()
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
        if let templateID {
            store.setBinding(binding, for: button, templateID: templateID)
        } else {
            store.setBinding(binding, for: button)
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
        if enabled,
           let chordBinding = currentBinding(for: selectedButton) as ButtonBinding?,
           case let .shortcut(chord, trigger) = chordBinding,
           trigger == .repeatWhileHeld,
           profile.usesAdvancedGestures {
            setCurrentBinding(.shortcut(chord, trigger: .single), for: selectedButton)
        }
        setCurrentGestureProfile(profile, for: selectedButton)
    }

    static func updatedGestureProfile(
        _ profile: ButtonGestureProfile,
        setting binding: ButtonBinding?,
        for slot: ButtonGestureSlot
    ) -> ButtonGestureProfile {
        var updated = profile
        updated.setBinding(binding, for: slot)
        if slot == .longPress {
            if binding == nil {
                updated.longPressBehavior = .none
            } else if updated.longPressBehavior == .none {
                updated.longPressBehavior = .triggerOnce
            }
        }
        return updated
    }

    private func setCurrentGestureBinding(
        _ binding: ButtonBinding?,
        for button: RemoteButton,
        slot: ButtonGestureSlot
    ) {
        let profile = Self.updatedGestureProfile(
            currentGestureProfile(for: button),
            setting: binding,
            for: slot
        )
        if profile.usesAdvancedGestures,
           case let .shortcut(chord, trigger) = currentBinding(for: button),
           trigger == .repeatWhileHeld {
            setCurrentBinding(.shortcut(chord, trigger: .single), for: button)
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
}

private struct SettingsRemotePreview: View {
    let selectedButton: RemoteButton
    let bindingFor: (RemoteButton) -> ButtonBinding
    let profileFor: (RemoteButton) -> ButtonGestureProfile
    var isGloballyOverridden: (RemoteButton) -> Bool = { _ in false }
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
            .overlay {
                if isGloballyOverridden(button) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .offset(x: size * 0.34, y: -size * 0.34)
                }
            }
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

struct AppTemplateChoice: Identifiable, Hashable {
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
            Text("模板只会应用到当前程序（\(bundleID)），更新为最新推荐按键与手势并立即设为 Active。")
                .font(.caption)
                .foregroundColor(.secondary)

            if presets.isEmpty {
                Text("当前程序暂无内置预设，请使用“新建模板”或录制快捷键。")
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
    enum CreationMode: Hashable {
        case recommendedPreset
        case blankFromGlobal
    }

    enum SheetTarget {
        case pickApp([AppTemplateChoice], Set<String>)
        case fixedApp(AppTemplateChoice)
    }

    let target: SheetTarget
    let onCancel: () -> Void
    let onCreateBlank: (AppTemplateChoice, String) -> Void
    let onImportPreset: (AppTemplateChoice, AppTemplatePreset) -> Void

    @State private var searchText = ""
    @State private var selectedBundleIdentifier = ""
    @State private var templateName = "默认模板"
    @State private var creationMode: CreationMode = .recommendedPreset
    @State private var selectedPresetID = ""

    init(
        request: SettingsView.TemplateCreatorRequest,
        installedApps: [AppTemplateChoice],
        configuredBundleIDs: Set<String>,
        onCancel: @escaping () -> Void,
        onCreateBlank: @escaping (AppTemplateChoice, String) -> Void,
        onImportPreset: @escaping (AppTemplateChoice, AppTemplatePreset) -> Void
    ) {
        switch request {
        case .addApplication:
            self.target = .pickApp(installedApps, configuredBundleIDs)
        case let .newTemplateForApp(bundleIdentifier, appName):
            self.target = .fixedApp(
                AppTemplateChoice(bundleIdentifier: bundleIdentifier, displayName: appName)
            )
        }
        self.onCancel = onCancel
        self.onCreateBlank = onCreateBlank
        self.onImportPreset = onImportPreset
    }

    private var availableApps: [AppTemplateChoice] {
        switch target {
        case let .pickApp(apps, _):
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return apps }
            return apps.filter {
                $0.displayName.localizedCaseInsensitiveContains(trimmed)
                    || $0.bundleIdentifier.localizedCaseInsensitiveContains(trimmed)
            }
        case let .fixedApp(app):
            return [app]
        }
    }

    private var configuredBundleIDs: Set<String> {
        switch target {
        case let .pickApp(_, ids): return ids
        case .fixedApp: return []
        }
    }

    private var selectedApp: AppTemplateChoice? {
        switch target {
        case let .fixedApp(app):
            return app
        case let .pickApp(apps, _):
            return apps.first { $0.bundleIdentifier == selectedBundleIdentifier }
                ?? availableApps.first
        }
    }

    private var availablePresets: [AppTemplatePreset] {
        guard let selectedApp else { return [] }
        return AppTemplatePresetLibrary.presets(for: selectedApp.bundleIdentifier)
    }

    private var selectedPreset: AppTemplatePreset? {
        availablePresets.first { $0.id == selectedPresetID } ?? availablePresets.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isFixedApp ? "为 \(selectedApp?.displayName ?? "程序") 新建模板" : "添加 /Applications 中的应用程序")
                .font(.title3.weight(.semibold))
            Text(
                isFixedApp
                    ? "新建该程序的专属按键模板；之后只有该程序位于前台时才会自动生效。"
                    : "仅列出 /Applications 中已安装的核心应用。添加后会自动拥有该程序的专属快捷选项。"
            )
            .font(.caption)
            .foregroundColor(.secondary)

            if !isFixedApp {
                TextField("搜索应用程序名称或 Bundle ID…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            if availableApps.isEmpty {
                Text("未找到符合条件的 /Applications 应用程序。")
                    .foregroundColor(.orange)
            } else {
                if !isFixedApp {
                    Picker("目标程序", selection: $selectedBundleIdentifier) {
                        ForEach(availableApps) { app in
                            let suffix = configuredBundleIDs.contains(app.bundleIdentifier) ? " · 已配置" : ""
                            Text("\(app.displayName)\(suffix)（\(app.bundleIdentifier)）")
                                .tag(app.bundleIdentifier)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if !availablePresets.isEmpty {
                    Picker("创建方式", selection: $creationMode) {
                        Text("使用推荐预设").tag(CreationMode.recommendedPreset)
                        Text("从通用映射新建").tag(CreationMode.blankFromGlobal)
                    }
                    .pickerStyle(.segmented)

                    if creationMode == .recommendedPreset {
                        if availablePresets.count > 1 {
                            Picker("推荐预设", selection: $selectedPresetID) {
                                ForEach(availablePresets) { preset in
                                    Text(preset.templateName).tag(preset.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        if let preset = selectedPreset {
                            Text(preset.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if availablePresets.isEmpty || creationMode == .blankFromGlobal {
                    TextField("模板名称，例如：浏览 / 编辑 / 调试", text: $templateName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button(canImportSelectedPreset ? "导入并设为 Active" : "创建") {
                    guard let app = selectedApp else { return }
                    if canImportSelectedPreset, let preset = selectedPreset {
                        onImportPreset(app, preset)
                    } else {
                        onCreateBlank(app, templateName)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedApp == nil)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            syncInitialSelection()
        }
        .onChange(of: selectedBundleIdentifier) { _ in
            syncPresetSelectionForCurrentApp()
        }
    }

    private var isFixedApp: Bool {
        if case .fixedApp = target { return true }
        return false
    }

    private var canImportSelectedPreset: Bool {
        !availablePresets.isEmpty && creationMode == .recommendedPreset
    }

    private func syncInitialSelection() {
        switch target {
        case let .fixedApp(app):
            selectedBundleIdentifier = app.bundleIdentifier
        case let .pickApp(apps, configured):
            if selectedBundleIdentifier.isEmpty {
                let firstUnconfigured = apps.first { !configured.contains($0.bundleIdentifier) }
                selectedBundleIdentifier = (firstUnconfigured ?? apps.first)?.bundleIdentifier ?? ""
            }
        }
        syncPresetSelectionForCurrentApp()
    }

    private func syncPresetSelectionForCurrentApp() {
        let presets = availablePresets
        if presets.isEmpty {
            creationMode = .blankFromGlobal
            selectedPresetID = ""
        } else {
            creationMode = .recommendedPreset
            selectedPresetID = presets.first?.id ?? ""
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

private struct VoiceShortcutEditorRequest: Identifiable {
    let entry: VoiceShortcutEntry
    let isNew: Bool
    var id: String { entry.id }
}

private struct VoiceShortcutEditorSheet: View {
    let request: VoiceShortcutEditorRequest
    let onCancel: () -> Void
    let onSave: (VoiceShortcutEntry, @escaping (String?) -> Void) -> Void

    @State private var displayName: String
    @State private var binding: VoiceShortcutBinding
    @State private var showRecorder = false
    @State private var errorText = ""

    init(
        request: VoiceShortcutEditorRequest,
        onCancel: @escaping () -> Void,
        onSave: @escaping (VoiceShortcutEntry, @escaping (String?) -> Void) -> Void
    ) {
        self.request = request
        self.onCancel = onCancel
        self.onSave = onSave
        _displayName = State(initialValue: request.entry.displayName)
        _binding = State(initialValue: request.entry.binding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.isNew ? "新增语音快捷键" : "编辑语音快捷键")
                .font(.title3.weight(.semibold))

            TextField("名称", text: $displayName)
                .textFieldStyle(.roundedBorder)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前快捷键")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(binding.sideDescription)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                }
                Spacer()
                Button("录制快捷键…") { showRecorder = true }
                    .buttonStyle(.bordered)
            }

            Text("录制支持左右 Option、Control、Command 纯修饰键、两个或更多不同类型的修饰键，以及修饰键加普通按键。Fn/Globe 尚未验证，按 Fn 会取消录制。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("保存") {
                    onSave(VoiceShortcutEntry(
                        id: request.entry.id,
                        displayName: displayName,
                        binding: binding
                    )) { error in
                        errorText = error ?? ""
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 480)
        .sheet(isPresented: $showRecorder) {
            VoiceShortcutRecorderSheet(
                onCancel: { showRecorder = false },
                onRecord: { recorded in
                    binding = recorded
                    showRecorder = false
                }
            )
        }
    }
}

private struct VoiceShortcutRecorderSheet: View {
    let onCancel: () -> Void
    let onRecord: (VoiceShortcutBinding) -> Void

    @State private var captureMonitor: ShortcutCaptureMonitor?
    @State private var preview = "请按下语音快捷键"
    @State private var errorText = ""
    @State private var pendingCancel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("录制语音快捷键")
                .font(.title3.weight(.semibold))
            Text("按住一个可用的纯修饰键、两个或更多不同类型的修饰键，或修饰键和普通按键；等全部相关按键释放后完成录制。")
                .foregroundStyle(.secondary)

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

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("录制会独占并抑制本次按键边沿。Fn/Globe 尚未验证，当前不可作为快捷键；按 Fn、Escape 或点击取消均可结束录制。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("取消录制") { requestCancel() }
                Spacer()
                Button("重新开始") { startMonitoring() }
                    .disabled(captureMonitor?.isRunning == true)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear { startMonitoring() }
        .onDisappear { stopMonitoring() }
    }

    private func startMonitoring() {
        stopMonitoring()
        pendingCancel = false
        preview = "请按下语音快捷键"
        errorText = ""
        let monitor = ShortcutCaptureMonitor(
            initiallyHeldFlags: CGEventSource.flagsState(.combinedSessionState),
            triggerModeProvider: { .single },
            voiceCaptureEnabled: true
        )
        monitor.onPreview = { preview = $0 }
        monitor.onError = { errorText = $0 }
        monitor.onVoiceRecord = { binding in
            do {
                try VoiceShortcutStore.validate(binding: binding)
                preview = binding.displayName
                onRecord(binding)
            } catch {
                errorText = error.localizedDescription
            }
        }
        monitor.onVoiceCancel = onCancel
        monitor.onStopped = {
            if pendingCancel { onCancel() }
        }
        captureMonitor = monitor
        if !monitor.start() { captureMonitor = nil }
    }

    private func requestCancel() {
        pendingCancel = true
        if captureMonitor == nil || captureMonitor?.requestCancel() == true {
            pendingCancel = false
            onCancel()
        }
    }

    private func stopMonitoring() {
        if captureMonitor?.stop() == true { captureMonitor = nil }
    }
}
