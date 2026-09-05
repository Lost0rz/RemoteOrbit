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
    ]

    /// 首次启动时，只对本机已安装且尚未配置模板的 App 自动添加这些默认模板。
    static let defaultPresetIDs = [
        "codex.default",
        "floatTabs.default",
        "ghostty.default",
        "netease.default",
        "obsidian.default",
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
            summary: "新标签、新窗口、标签切换、分屏、搜索、命令面板和关闭当前 surface。",
            bindings: ghosttyBindings,
            gestureProfiles: defaultKeymapGestureProfiles
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
    ]

    static func presets(for bundleIdentifier: String) -> [AppTemplatePreset] {
        all.filter { $0.appBundleIdentifier == bundleIdentifier }
    }

    static func preset(id: String) -> AppTemplatePreset? {
        all.first { $0.id == id }
    }

    /// 通用动作始终可用；只有当前 App 对应的专属分类才会出现在设置选择器中。
    static func categories(for bundleIdentifier: String) -> [ButtonActionCategory] {
        var allowed: Set<ButtonActionCategory> = [
            .system,
            .navigation,
            .editing,
            .selection,
            .media,
        ]
        for preset in presets(for: bundleIdentifier) {
            for action in preset.bindings.values {
                if case let .preset(action) = action {
                    allowed.insert(action.category)
                }
            }
        }
        if bundleIdentifier == "com.openai.codex" {
            // The official command catalog is larger than the actions assigned
            // to the 13 physical buttons in a default template. Keep all four
            // app categories available so every command can be selected from
            // the per-button preset picker.
            allowed.formUnion(ButtonActionCategory.codexCategories)
        }
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
        .up: .preset(.pageDown),
        .down: .preset(.pageUp),
        .left: .preset(.ghosttyPreviousTab),
        .right: .preset(.ghosttyNextTab),
        .ok: .preset(.returnKey),
        .back: .preset(.ghosttyCloseSurface),
        .home: .preset(.ghosttyNewTab),
        .menu: .preset(.ghosttyCommandPalette),
        .tv: .preset(.ghosttyNewWindow),
        .volumeUp: .preset(.ghosttyNextTab),
        .volumeDown: .preset(.ghosttyPreviousTab),
    ])

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
}
