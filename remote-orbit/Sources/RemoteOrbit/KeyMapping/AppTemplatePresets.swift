import Foundation

/// 可导入的 App 按键模板。
///
/// 模板只描述“语义动作”，具体快捷键统一由 ButtonAction/KeyInjector 发送，
/// 因此用户可以先导入一套可读的默认布局，再逐个按钮改成录制快捷键。
struct AppTemplatePreset: Identifiable {
    let id: String
    let appBundleIdentifier: String
    let appName: String
    let templateName: String
    let summary: String
    let bindings: [RemoteButton: ButtonBinding]
    let gestureProfiles: [RemoteButton: ButtonGestureProfile]?

    init(
        id: String,
        appBundleIdentifier: String,
        appName: String,
        templateName: String,
        summary: String,
        bindings: [RemoteButton: ButtonBinding],
        gestureProfiles: [RemoteButton: ButtonGestureProfile]? = nil
    ) {
        self.id = id
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.templateName = templateName
        self.summary = summary
        self.bindings = bindings
        self.gestureProfiles = gestureProfiles
    }

    var displayName: String {
        "\(appName) · \(templateName)"
    }
}

struct PresetApplication: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }
}

/// 内置模板库。
enum AppTemplatePresetLibrary {
    /// Every built-in app template exposes the same Orbit-owned contextual
    /// map on TV long press. The action resolves the foreground app at the
    /// moment it is shown, so the display remains app-specific.
    static let defaultKeymapInspectionProfile = ButtonGestureProfile(
        isEnabled: true,
        longPress: .preset(.inspectCurrentKeymap),
        longPressBehavior: .triggerOnce
    )

    static let knownApps: [PresetApplication] = [
        PresetApplication(
            bundleIdentifier: "com.openai.codex",
            displayName: "Codex"
        ),
        PresetApplication(
            bundleIdentifier: "com.lost0rz.FloatTabs",
            displayName: "FloatTabs"
        ),
        PresetApplication(
            bundleIdentifier: "com.mitchellh.ghostty",
            displayName: "Ghostty"
        ),
        PresetApplication(
            bundleIdentifier: "com.netease.163music",
            displayName: "网易云音乐"
        ),
        PresetApplication(
            bundleIdentifier: "md.obsidian",
            displayName: "Obsidian"
        ),
        PresetApplication(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome"
        ),
        PresetApplication(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari"
        ),
        PresetApplication(
            bundleIdentifier: "com.colliderli.iina",
            displayName: "IINA"
        ),
        PresetApplication(
            bundleIdentifier: "com.t3tools.t3code",
            displayName: "T3 Code"
        ),
        PresetApplication(
            bundleIdentifier: "com.google.antigravity",
            displayName: "Antigravity"
        ),
        PresetApplication(
            bundleIdentifier: "com.apple.dt.Xcode",
            displayName: "Xcode"
        ),
        PresetApplication(
            bundleIdentifier: "com.tencent.xinWeChat",
            displayName: "微信"
        ),
        PresetApplication(
            bundleIdentifier: "com.google.GeminiMacOS",
            displayName: "Gemini"
        ),
    ]

    /// 首次启动时，为本机已安装且尚未配置模板的常用 App 自动添加默认模板。
    static let defaultPresetIDs = [
        "codex.default",
        "t3code.default",
        "antigravity.default",
        "gemini.default",
        "ghostty.default",
        "obsidian.default",
        "chrome.default",
        "safari.default",
        "wechat.default",
        "floatTabs.default",
        "iina.default",
        "netease.default",
        "xcode.default",
    ]

    static let all: [AppTemplatePreset] = [
        AppTemplatePreset(
            id: "codex.default",
            appBundleIdentifier: "com.openai.codex",
            appName: "Codex",
            templateName: "Codex 默认",
            summary: "侧边栏显示/隐藏、输入栏左右移动、上/下一个对话和需要注意的对话。",
            bindings: codexBindings,
            gestureProfiles: codexGestureProfiles
        ),
        AppTemplatePreset(
            id: "floatTabs.default",
            appBundleIdentifier: "com.lost0rz.FloatTabs",
            appName: "FloatTabs",
            templateName: "FloatTabs 默认",
            summary: "标签切换、对话框/网页焦点切换、滚屏和设置。音量键切换标签。",
            bindings: floatTabsBindings,
            gestureProfiles: floatTabsGestureProfiles
        ),
        AppTemplatePreset(
            id: "floatTabs.browse",
            appBundleIdentifier: "com.lost0rz.FloatTabs",
            appName: "FloatTabs",
            templateName: "FloatTabs 浏览增强",
            summary: "滚屏、刷新、焦点切换、显示/隐藏和标签切换；菜单键直接刷新当前页面。",
            bindings: floatTabsBrowseBindings,
            gestureProfiles: floatTabsBrowseGestureProfiles
        ),
        AppTemplatePreset(
            id: "ghostty.default",
            appBundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty",
            templateName: "Ghostty 默认",
            summary: "上下滚屏、标签切换、分屏切换、命令面板、关闭 surface 与新建标签/窗口。",
            bindings: ghosttyBindings,
            gestureProfiles: ghosttyGestureProfiles
        ),
        AppTemplatePreset(
            id: "netease.default",
            appBundleIdentifier: "com.netease.163music",
            appName: "网易云音乐",
            templateName: "网易云音乐 默认",
            summary: "上一首、下一首、播放暂停和系统音量。",
            bindings: neteaseBindings,
            gestureProfiles: defaultKeymapGestureProfiles
        ),
        AppTemplatePreset(
            id: "obsidian.default",
            appBundleIdentifier: "md.obsidian",
            appName: "Obsidian",
            templateName: "Obsidian 默认",
            summary: "CLI 文档分栏聚焦、滚屏、标签与窗口、笔记编辑、快速切换、命令面板、搜索、侧边栏、图谱和属性。",
            bindings: obsidianBindings,
            gestureProfiles: defaultKeymapGestureProfiles
        ),
        AppTemplatePreset(
            id: "chrome.default",
            appBundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            templateName: "Chrome 默认",
            summary: "网页滚屏、前进/后退、标签切换、关闭/恢复标签、刷新页面与地址栏定位。",
            bindings: browserBindings,
            gestureProfiles: browserGestureProfiles
        ),
        AppTemplatePreset(
            id: "safari.default",
            appBundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            templateName: "Safari 默认",
            summary: "网页滚屏、前进/后退、标签切换、关闭/恢复标签、刷新页面与地址栏定位。",
            bindings: browserBindings,
            gestureProfiles: browserGestureProfiles
        ),
        AppTemplatePreset(
            id: "iina.default",
            appBundleIdentifier: "com.colliderli.iina",
            appName: "IINA",
            templateName: "IINA 默认",
            summary: "空格播放/暂停、左右快进快退 5 秒、上下/音量调节、倍速切换与全屏。",
            bindings: iinaBindings,
            gestureProfiles: iinaGestureProfiles
        ),
        AppTemplatePreset(
            id: "t3code.default",
            appBundleIdentifier: "com.t3tools.t3code",
            appName: "T3 Code",
            templateName: "T3 Code 默认",
            summary: "对话与代码滚屏、Cmd-Shift-O 新建线程、Cmd-Shift-[/] 切换线程、Cmd-K 命令面板与 Diff / 侧栏 / 终端切换。",
            bindings: t3CodeBindings,
            gestureProfiles: t3CodeGestureProfiles
        ),
        AppTemplatePreset(
            id: "antigravity.default",
            appBundleIdentifier: "com.google.antigravity",
            appName: "Antigravity",
            templateName: "Antigravity 默认",
            summary: "代码滚屏、文件导航、侧边栏/终端切换、命令面板与标签切换。",
            bindings: codeWorkspaceBindings,
            gestureProfiles: codeWorkspaceGestureProfiles
        ),
        AppTemplatePreset(
            id: "gemini.default",
            appBundleIdentifier: "com.google.GeminiMacOS",
            appName: "Gemini",
            templateName: "Gemini 默认",
            summary: "对话滚屏、Cmd-N 发起新对话、Cmd-Shift-N 临时对话与 Antigravity 模式切换。",
            bindings: geminiBindings,
            gestureProfiles: geminiGestureProfiles
        ),
        AppTemplatePreset(
            id: "xcode.default",
            appBundleIdentifier: "com.apple.dt.Xcode",
            appName: "Xcode",
            templateName: "Xcode 默认",
            summary: "代码滚屏、文件历史前进/后退、运行与停止、快速打开、导航栏与调试区开关。",
            bindings: xcodeBindings,
            gestureProfiles: xcodeGestureProfiles
        ),
        AppTemplatePreset(
            id: "wechat.default",
            appBundleIdentifier: "com.tencent.xinWeChat",
            appName: "微信",
            templateName: "微信 默认",
            summary: "聊天记录滚屏、搜索联系人/消息、截屏、锁定微信、确定发送与长按换行。",
            bindings: wechatBindings,
            gestureProfiles: wechatGestureProfiles
        ),
    ]

    static func presets(for bundleIdentifier: String) -> [AppTemplatePreset] {
        all.filter { $0.appBundleIdentifier == bundleIdentifier }
    }

    static func preset(id: String) -> AppTemplatePreset? {
        all.first { $0.id == id }
    }

    /// Strictly exclusive categories owned by `bundleIdentifier` alone.
    /// Never mixes another app's exclusive shortcuts into the selected app.
    static func exclusiveCategories(for bundleIdentifier: String) -> [ButtonActionCategory] {
        switch bundleIdentifier {
        case "com.openai.codex":
            return [
                .chatGPTGeneral,
                .chatGPTChats,
                .chatGPTInputModes,
                .chatGPTWorkspaceBrowser,
            ]
        case "com.lost0rz.FloatTabs":
            return [.floatTabs]
        case "com.mitchellh.ghostty":
            return [.ghostty]
        case "md.obsidian":
            return [.obsidian]
        case "com.netease.163music":
            return [.netease]
        case "com.google.Chrome",
             "com.apple.Safari",
             "company.thebrowser.Browser",
             "com.microsoft.edgemac",
             "org.mozilla.firefox":
            return [.browser]
        case "com.colliderli.iina":
            return [.iina]
        case "com.t3tools.t3code":
            return [.t3Code]
        case "com.google.antigravity",
             "com.microsoft.VSCode",
             "com.todesktop.230313mzl4w4u92":
            return [.codeWorkspace]
        case "com.google.GeminiMacOS":
            return [.gemini]
        case "com.apple.dt.Xcode":
            return [.xcode]
        case "com.tencent.xinWeChat":
            return [.wechat]
        default:
            return []
        }
    }

    /// 通用动作始终可用；只有当前 App 对应的专属分类才会出现在设置选择器中。
    static func categories(for bundleIdentifier: String) -> [ButtonActionCategory] {
        var allowed: Set<ButtonActionCategory> = [
            .navigation,
            .editing,
            .selection,
            .media,
            .system,
        ]
        allowed.formUnion(exclusiveCategories(for: bundleIdentifier))
        return ButtonActionCategory.allCases.filter { allowed.contains($0) }
    }

    private static func overlay(
        _ overrides: [RemoteButton: ButtonBinding]
    ) -> [RemoteButton: ButtonBinding] {
        var bindings = DefaultBindings.all
        for (button, binding) in overrides {
            bindings[button] = binding
        }
        return bindings
    }

    private static let codexBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.arrowLeft),
        .right: .preset(.arrowRight),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .volumeUp: .preset(.chatGPTPreviousChat),
        .home: .preset(.chatGPTNextAttention),
        .volumeDown: .preset(.chatGPTNextChat),
        .menu: .preset(.chatGPTToggleSidebar),
        .tv: .preset(.appSwitcher),
    ])

    private static let floatTabsBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.arrowLeft),
        .right: .preset(.arrowRight),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .home: .preset(.floatTabsToggleVisibility),
        .menu: .preset(.floatTabsToggleAlwaysOnTop),
        .tv: .preset(.appSwitcher),
        .volumeUp: .preset(.floatTabsPreviousTab),
        .volumeDown: .preset(.floatTabsNextTab),
    ])

    /// Alternative layout for page navigation. The existing default keeps
    /// Pin / Auto-hide on Menu; this opt-in preset gives the same button a
    /// semantic refresh action without relying on FloatTabs' configurable
    /// Command-R shortcut.
    private static let floatTabsBrowseBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.arrowLeft),
        .right: .preset(.arrowRight),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .home: .preset(.floatTabsToggleVisibility),
        .menu: .preset(.reloadPage),
        .tv: .preset(.appSwitcher),
        .volumeUp: .preset(.floatTabsPreviousTab),
        .volumeDown: .preset(.floatTabsNextTab),
    ])

    private static let codexGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.paste),
            longPressBehavior: .triggerOnce
        ),
        .back: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld
        ),
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let floatTabsGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .back: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld
        ),
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.paste),
            longPressBehavior: .triggerOnce
        ),
        .menu: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.reloadPage),
            longPressBehavior: .triggerOnce
        ),
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let floatTabsBrowseGestureProfiles = floatTabsGestureProfiles
    private static let defaultKeymapGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let ghosttyBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.ghosttyPreviousSplit),
        .right: .preset(.ghosttyNextSplit),
        .ok: .preset(.returnKey),
        .back: .preset(.ghosttyCloseSurface),
        .home: .preset(.ghosttyNewTab),
        .menu: .preset(.ghosttyCommandPalette),
        .tv: .preset(.ghosttyNewWindow),
        .volumeUp: .preset(.ghosttyPreviousTab),
        .volumeDown: .preset(.ghosttyNextTab),
    ])

    private static let ghosttyGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.paste),
            longPressBehavior: .triggerOnce
        ),
        .back: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.ghosttyInterrupt),
            longPressBehavior: .triggerOnce
        ),
        .menu: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.ghosttyClearScreen),
            longPressBehavior: .triggerOnce
        ),
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let neteaseBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.volumeUp),
        .down: .preset(.volumeDown),
        .left: .preset(.neteasePreviousTrack),
        .right: .preset(.neteaseNextTrack),
        .ok: .preset(.playPause),
        .back: .preset(.escape),
        .home: .preset(.appSwitcher),
        .menu: .preset(.disabled),
        .tv: .preset(.appSwitcher),
        // Keep the remote's dedicated volume buttons as system volume too.
        // Otherwise overlay() inherits Codex chat navigation from
        // DefaultBindings and the HUD reports the wrong action.
        .volumeUp: .preset(.volumeUp),
        .volumeDown: .preset(.volumeDown),
    ])

    private static let obsidianBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.obsidianFocusTabGroupLeft),
        .right: .preset(.obsidianFocusTabGroupRight),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .home: .preset(.obsidianQuickSwitcher),
        .menu: .preset(.obsidianCommandPalette),
        .tv: .preset(.obsidianNewNote),
        .volumeUp: .preset(.obsidianPreviousTab),
        .volumeDown: .preset(.obsidianNextTab),
    ])

    private static let browserBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.browserBack),
        .right: .preset(.browserForward),
        .ok: .preset(.returnKey),
        .back: .preset(.browserCloseTab),
        .home: .preset(.browserAddressBar),
        .menu: .preset(.browserReload),
        .tv: .preset(.appSwitcher),
        .volumeUp: .preset(.browserPreviousTab),
        .volumeDown: .preset(.browserNextTab),
    ])

    private static let browserGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .back: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.browserReopenClosedTab),
            longPressBehavior: .triggerOnce
        ),
        .menu: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.browserReloadNoCache),
            longPressBehavior: .triggerOnce
        ),
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let iinaBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.iinaVolumeUp),
        .down: .preset(.iinaVolumeDown),
        .left: .preset(.iinaSeekBackward),
        .right: .preset(.iinaSeekForward),
        .ok: .preset(.iinaPlayPause),
        .back: .preset(.escape),
        .home: .preset(.iinaShowPlaylist),
        .menu: .preset(.iinaCycleSubtitles),
        .tv: .preset(.iinaToggleFullScreen),
        .volumeUp: .preset(.iinaVolumeUp),
        .volumeDown: .preset(.iinaVolumeDown),
    ])

    private static let iinaGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .left: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.iinaSpeedDown),
            longPressBehavior: .triggerOnce
        ),
        .right: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.iinaSpeedUp),
            longPressBehavior: .triggerOnce
        ),
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.iinaResetSpeed),
            longPressBehavior: .triggerOnce
        ),
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let codeWorkspaceBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.workspaceNavigateBack),
        .right: .preset(.workspaceNavigateForward),
        .ok: .preset(.returnKey),
        .back: .preset(.workspaceCloseTab),
        .home: .preset(.workspaceQuickOpen),
        .menu: .preset(.workspaceCommandPalette),
        .tv: .preset(.appSwitcher),
        .volumeUp: .preset(.workspacePreviousTab),
        .volumeDown: .preset(.workspaceNextTab),
    ])

    private static let codeWorkspaceGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .menu: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.workspaceToggleSidebar),
            longPressBehavior: .triggerOnce
        ),
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.paste),
            longPressBehavior: .triggerOnce
        ),
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let xcodeBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.xcodePreviousHistory),
        .right: .preset(.xcodeNextHistory),
        .ok: .preset(.xcodeRun),
        .back: .preset(.xcodeStop),
        .home: .preset(.xcodeOpenQuickly),
        .menu: .preset(.xcodeToggleNavigator),
        .tv: .preset(.appSwitcher),
        .volumeUp: .preset(.volumeUp),
        .volumeDown: .preset(.volumeDown),
    ])

    private static let xcodeGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.xcodeBuild),
            longPressBehavior: .triggerOnce
        ),
        .menu: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.xcodeToggleDebugArea),
            longPressBehavior: .triggerOnce
        ),
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let t3CodeBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.arrowLeft),
        .right: .preset(.arrowRight),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .volumeUp: .preset(.t3PreviousThread),
        .volumeDown: .preset(.t3NextThread),
        .home: .preset(.t3NewChat),
        .menu: .preset(.t3CommandPalette),
        .tv: .preset(.t3ToggleDiff),
    ])

    private static let t3CodeGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.paste),
            longPressBehavior: .triggerOnce
        ),
        .back: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld
        ),
        .menu: ButtonGestureProfile(
            isEnabled: true,
            doubleTap: .preset(.t3SwitchMode),
            longPress: .preset(.t3ToggleSidebar),
            longPressBehavior: .triggerOnce
        ),
        .tv: ButtonGestureProfile(
            isEnabled: true,
            doubleTap: .preset(.t3ToggleTerminal),
            longPress: .preset(.inspectCurrentKeymap),
            longPressBehavior: .triggerOnce
        ),
    ]

    private static let geminiBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.arrowLeft),
        .right: .preset(.arrowRight),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .home: .preset(.geminiNewChat),
        .menu: .preset(.geminiSwitchAntigravity),
        .tv: .preset(.appSwitcher),
        .volumeUp: .preset(.volumeUp),
        .volumeDown: .preset(.volumeDown),
    ])

    private static let geminiGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.paste),
            longPressBehavior: .triggerOnce
        ),
        .back: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld
        ),
        .menu: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.geminiNewTemporaryChat),
            longPressBehavior: .triggerOnce
        ),
        .tv: defaultKeymapInspectionProfile,
    ]

    private static let wechatBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.arrowLeft),
        .right: .preset(.arrowRight),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .home: .preset(.wechatSearch),
        .menu: .preset(.wechatScreenshot),
        .tv: .preset(.appSwitcher),
        .volumeUp: .preset(.volumeUp),
        .volumeDown: .preset(.volumeDown),
    ])

    private static let wechatGestureProfiles: [RemoteButton: ButtonGestureProfile] = [
        .ok: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.wechatLineBreak),
            longPressBehavior: .triggerOnce
        ),
        .back: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld
        ),
        .menu: ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.wechatLock),
            longPressBehavior: .triggerOnce
        ),
        .tv: defaultKeymapInspectionProfile,
    ]
}
