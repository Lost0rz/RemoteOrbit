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
    static let knownApps: [PresetApplication] = [
        PresetApplication(
            bundleIdentifier: "com.openai.codex",
            displayName: "ChatGPT / Codex"
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
    /// Codex 与 ChatGPT 当前共用 com.openai.codex，因此 Codex 模板保留为手动导入。
    static let defaultPresetIDs = [
        "chatgpt.default",
        "floatTabs.default",
        "ghostty.default",
        "netease.default",
        "obsidian.default",
    ]

    static let all: [AppTemplatePreset] = [
        AppTemplatePreset(
            id: "chatgpt.default",
            appBundleIdentifier: "com.openai.codex",
            appName: "ChatGPT",
            templateName: "ChatGPT 默认",
            summary: "内置官方 ChatGPT / Codex 全量快捷动作分类；侧边栏、底部面板、需要注意的对话、滚屏和编辑动作。菜单键留空。",
            bindings: chatGPTBindings
        ),
        AppTemplatePreset(
            id: "codex.default",
            appBundleIdentifier: "com.openai.codex",
            appName: "Codex",
            templateName: "Codex 默认",
            summary: "内置官方 ChatGPT / Codex 全量快捷动作分类；默认含 Terminal、需要注意的对话和上一个对话。",
            bindings: codexBindings
        ),
        AppTemplatePreset(
            id: "floatTabs.default",
            appBundleIdentifier: "com.lost0rz.FloatTabs",
            appName: "FloatTabs",
            templateName: "FloatTabs 默认",
            summary: "标签切换、对话框/网页焦点切换、滚屏和设置。音量键切换标签。",
            bindings: floatTabsBindings
        ),
        AppTemplatePreset(
            id: "ghostty.default",
            appBundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty",
            templateName: "Ghostty 默认",
            summary: "新标签、新窗口、标签切换、分屏、搜索、命令面板和关闭当前 surface。",
            bindings: ghosttyBindings
        ),
        AppTemplatePreset(
            id: "netease.default",
            appBundleIdentifier: "com.netease.163music",
            appName: "网易云音乐",
            templateName: "网易云音乐 默认",
            summary: "上一首、下一首、播放暂停和系统音量。",
            bindings: neteaseBindings
        ),
        AppTemplatePreset(
            id: "obsidian.default",
            appBundleIdentifier: "md.obsidian",
            appName: "Obsidian",
            templateName: "Obsidian 默认",
            summary: "标签切换、快速切换文件、命令面板、新建笔记和全库搜索。",
            bindings: obsidianBindings
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
            allowed.formUnion(ButtonActionCategory.chatGPTCategories)
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

    private static let chatGPTBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.chatGPTToggleSidebar),
        .right: .preset(.chatGPTToggleBottomPanel),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .home: .preset(.chatGPTNextAttention),
        .menu: .preset(.disabled),
        .tv: .preset(.appSwitcher),
    ])

    private static let codexBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.chatGPTToggleSidebar),
        .right: .preset(.chatGPTToggleBottomPanel),
        .ok: .preset(.returnKey),
        .back: .preset(.deleteBackward),
        .home: .preset(.chatGPTNextAttention),
        .menu: .preset(.chatGPTPreviousChat),
        .tv: .preset(.appSwitcher),
    ])

    private static let floatTabsBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.floatTabsPreviousTab),
        .right: .preset(.floatTabsNextTab),
        .ok: .preset(.returnKey),
        .back: .preset(.escape),
        .home: .preset(.floatTabsToggleVisibility),
        .menu: .preset(.floatTabsSettings),
        .tv: .preset(.appSwitcher),
        .volumeUp: .preset(.floatTabsNextTab),
        .volumeDown: .preset(.floatTabsPreviousTab),
    ])

    private static let ghosttyBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
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
    ])

    private static let obsidianBindings = overlay([
        .power: .preset(.disabled),
        .up: .preset(.pageUp),
        .down: .preset(.pageDown),
        .left: .preset(.obsidianPreviousTab),
        .right: .preset(.obsidianNextTab),
        .ok: .preset(.returnKey),
        .back: .preset(.obsidianCloseTab),
        .home: .preset(.obsidianQuickSwitcher),
        .menu: .preset(.obsidianCommandPalette),
        .tv: .preset(.obsidianNewNote),
        .volumeUp: .preset(.obsidianNextTab),
        .volumeDown: .preset(.obsidianPreviousTab),
    ])
}
