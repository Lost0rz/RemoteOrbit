// ButtonDefinitions.swift — 遥控器按钮定义、KeyChord、ButtonAction、ButtonBinding
//
// Button definitions and default actions for the supported voice remote.
// 支持 13 个遥控器按钮（含电源/菜单/TV/音量/返回），完整 HID usage 映射。

import Foundation

// MARK: - 遥控器按钮

/// 小米蓝牙语音遥控器 2 Pro (RC003) 的所有物理按钮。
enum RemoteButton: String, CaseIterable, Codable, Identifiable {
    case microphone
    case power
    case up
    case left
    case ok
    case right
    case down
    case back
    case volumeUp = "volume_up"
    case home
    case volumeDown = "volume_down"
    case menu
    case tv

    var id: String { rawValue }

    /// HID usage code（来自遥控器 HID 报告）。
    var hidUsage: UInt16 {
        switch self {
        case .microphone:  return 0x3E
        case .power:       return 0x66
        case .up:          return 0x52
        case .left:        return 0x50
        case .ok:          return 0x28
        case .right:       return 0x4F
        case .down:        return 0x51
        case .back:        return 0xF1
        case .volumeUp:    return 0x80
        case .home:        return 0x4A
        case .volumeDown:  return 0x81
        case .menu:        return 0x65
        case .tv:          return 0x35
        }
    }

    /// 中文显示名称。
    var displayName: String {
        switch self {
        case .microphone:  return "语音键"
        case .power:       return "电源键"
        case .up:          return "上键"
        case .left:        return "左键"
        case .ok:          return "确定键"
        case .right:       return "右键"
        case .down:        return "下键"
        case .back:        return "返回键"
        case .volumeUp:    return "音量 +"
        case .home:        return "主页键"
        case .volumeDown:  return "音量 -"
        case .menu:        return "菜单键"
        case .tv:          return "TV 键"
        }
    }

    /// 短标签（用于紧凑 UI）。
    var shortLabel: String {
        switch self {
        case .microphone:  return "语音"
        case .power:       return "电源"
        case .up:          return "上"
        case .left:        return "左"
        case .ok:          return "OK"
        case .right:       return "右"
        case .down:        return "下"
        case .back:        return "返回"
        case .volumeUp:    return "+"
        case .home:        return "主页"
        case .volumeDown:  return "−"
        case .menu:        return "菜单"
        case .tv:          return "TV"
        }
    }

    /// macOS 为该按钮生成的原生事件（nil = 无原生事件，如 back）。
    var nativeEvent: RemoteNativeEvent? {
        switch self {
        case .microphone:  return .keyboard(keyCode: 96)   // F5
        case .ok:          return .keyboard(keyCode: 36)   // Return
        case .tv:          return .keyboard(keyCode: 50)   // `
        case .home:        return .keyboard(keyCode: 115)  // Home
        case .right:       return .keyboard(keyCode: 124)  // →
        case .left:        return .keyboard(keyCode: 123)  // ←
        case .down:        return .keyboard(keyCode: 125)  // ↓
        case .up:          return .keyboard(keyCode: 126)  // ↑
        case .menu:        return .keyboard(keyCode: 110)  // Forward Delete (macOS 映射)
        case .power:       return .systemKey(type: 6)
        case .volumeUp:    return .systemKey(type: 0)
        case .volumeDown:  return .systemKey(type: 1)
        case .back:        return nil                       // 无原生事件
        }
    }

    /// HID usage → RemoteButton 快速查找表。
    static let usageMap = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.hidUsage, $0) }
    )

    /// 可重复触发的按钮（长按时持续发送事件）。
    static let repeatable: Set<RemoteButton> = [
        .up, .down, .left, .right, .back, .volumeUp, .volumeDown
    ]
}

// MARK: - 原生事件类型

/// macOS 为遥控器按钮生成的原生事件类型。
enum RemoteNativeEvent: Equatable {
    case keyboard(keyCode: UInt16)
    case systemKey(type: Int32)
}

/// 按键边沿（按下/松开）。
enum RemoteEventEdge: Equatable {
    case down
    case up
}

// MARK: - KeyChord（快捷键组合）

/// 一个按键 + 修饰键组合，例如 ⌘⇧S 或 ⌃⌥Delete。
struct KeyChord: Codable, Equatable, Hashable {
    /// 修饰键集合。
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: UInt8

        static let command = Self(rawValue: 1 << 0)
        static let control = Self(rawValue: 1 << 1)
        static let option  = Self(rawValue: 1 << 2)
        static let shift   = Self(rawValue: 1 << 3)
    }

    let keyCode: UInt16
    let keyLabel: String
    let modifiers: Modifiers

    /// 验证是否可安全注入。
    var isValid: Bool {
        keyCode <= 127 &&
        !keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        keyLabel.count <= 24
    }

    /// 显示名称（如 "⌘⇧S"、"⌃⌥Delete"）。
    var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyLabel)
        return parts.joined()
    }
}

// MARK: - ButtonAction（预设动作）

/// 遥控器按钮可映射到的预设动作。
enum ButtonAction: String, CaseIterable, Codable, Identifiable {
    case disabled
    case escape
    case returnKey
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case pageUp
    case pageDown
    /// Refreshes the current page semantically; FloatTabs uses its direct
    /// command, while ordinary browsers receive their standard Command-R.
    case reloadPage
    case deleteBackward
    case showDesktop
    case contextMenu
    case appSwitcher
    case openFloatTabs
    case openCodex
    case copy
    case paste
    case cut
    case selectAll
    case undo
    case redo
    /// FloatTabs' app-local tab navigation shortcuts.
    case floatTabsNextTab
    case floatTabsPreviousTab
    case floatTabsToggleVisibility
    case floatTabsToggleFocus
    case floatTabsSettings
    case floatTabsToggleAlwaysOnTop
    // ChatGPT / Codex desktop app — General
    case chatGPTOpenCommandMenu
    case chatGPTOpenSettings
    case chatGPTOpenKeyboardShortcuts
    case chatGPTOpenFolder
    case chatGPTNavigateBack
    case chatGPTNavigateForward
    case chatGPTIncreaseFontSize
    case chatGPTDecreaseFontSize
    case chatGPTResetFontSize
    case chatGPTToggleSidebar
    case chatGPTToggleBottomPanel
    case chatGPTOpenTerminal
    case chatGPTClearTerminal
    case chatGPTClearUnread
    case chatGPTUndo
    case chatGPTRedo
    case chatGPTCloseWindow
    case chatGPTToggleFullScreen
    case chatGPTQuit
    // ChatGPT / Codex desktop app — Chats
    case chatGPTNewChat
    case chatGPTNewStandaloneChat
    case chatGPTQuickChat
    case chatGPTNewTemporaryChat
    case chatGPTArchiveChat
    case chatGPTMarkChatUnread
    case chatGPTPinChat
    case chatGPTRenameChat
    case chatGPTOpenSideChat
    case chatGPTSearchChats
    case chatGPTFindInChat
    case chatGPTFindNext
    case chatGPTFindPrevious
    case chatGPTPreviousChat
    case chatGPTNextChat
    case chatGPTNextAttention
    case chatGPTOpenRecentChat1
    case chatGPTOpenRecentChat2
    case chatGPTOpenRecentChat3
    case chatGPTOpenRecentChat4
    case chatGPTOpenRecentChat5
    case chatGPTOpenRecentChat6
    case chatGPTGoToChat1
    case chatGPTGoToChat2
    case chatGPTGoToChat3
    case chatGPTGoToChat4
    case chatGPTGoToChat5
    case chatGPTGoToChat6
    case chatGPTGoToChat7
    case chatGPTGoToChat8
    case chatGPTGoToChat9
    // ChatGPT / Codex desktop app — Input and modes
    case chatGPTModelPicker
    case chatGPTProjectPicker
    case chatGPTStartVoiceChat
    case chatGPTStartDictation
    case chatGPTRestorePreviousPrompt
    case chatGPTApproveRequest
    case chatGPTDeclineRequest
    case chatGPTSwitchToChat
    case chatGPTSwitchToWork
    case chatGPTSwitchToCodex
    case chatGPTToggleActivity
    // ChatGPT / Codex desktop app — Workspace and browser
    case chatGPTRunEnvironmentAction
    case chatGPTSearchFiles
    case chatGPTToggleFileTree
    case chatGPTOpenReviewTab
    case chatGPTToggleReviewPanel
    case chatGPTOpenBrowserTab
    case chatGPTToggleBrowserPanel
    case chatGPTFocusAddressBar
    case chatGPTBrowserBack
    case chatGPTBrowserForward
    case chatGPTReloadBrowser
    case chatGPTReloadBrowserNoCache
    case chatGPTCopyBrowserURL
    case chatGPTToggleBrowserMode
    case chatGPTCopyConversationPath
    case chatGPTCopyChatDeepLink
    case chatGPTCopySessionID
    case chatGPTCopyWorkingDirectory
    case chatGPTTakeAppshot
    case ghosttyNewTab
    case ghosttyNewWindow
    case ghosttyPreviousTab
    case ghosttyNextTab
    case ghosttyCloseSurface
    case ghosttyNewSplitRight
    case ghosttyNewSplitDown
    case ghosttyCommandPalette
    case ghosttySearch
    case obsidianCommandPalette
    case obsidianQuickSwitcher
    case obsidianNewNote
    case obsidianNewTab
    case obsidianReopenClosedTab
    case obsidianCloseTab
    case obsidianSearch
    case obsidianToggleEditMode
    case obsidianAddProperty
    case obsidianPreviousTab
    case obsidianNextTab
    case neteasePreviousTrack
    case neteaseNextTrack
    case mouseRightClick
    case volumeUp
    case volumeDown
    case volumeMute
    case playPause

    var id: String { rawValue }

    /// Whether a preset is safe and meaningful to repeat while the physical
    /// button remains held. Toggle/open actions must stay atomic: repeating
    /// Command-B, for example, would immediately reopen a sidebar that the
    /// first tap just closed. Users can still opt into repetition explicitly
    /// for recorded shortcuts via the `.repeatWhileHeld` trigger.
    var repeatsWhenHeld: Bool {
        switch self {
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight,
             .pageUp, .pageDown, .deleteBackward,
             .volumeUp, .volumeDown:
            return true
        default:
            return false
        }
    }

    var category: ButtonActionCategory {
        switch self {
        case .disabled, .showDesktop, .contextMenu, .appSwitcher:
            return .system
        case .openFloatTabs, .openCodex:
            return .applications
        case .escape, .returnKey, .arrowUp, .arrowDown, .arrowLeft, .arrowRight,
             .pageUp, .pageDown, .reloadPage:
            return .navigation
        case .copy, .paste, .cut, .selectAll, .deleteBackward, .undo, .redo:
            return .editing
        case .volumeUp, .volumeDown, .volumeMute, .playPause:
            return .media
        case .floatTabsToggleVisibility, .floatTabsToggleFocus, .floatTabsSettings,
             .floatTabsToggleAlwaysOnTop:
            return .floatTabs
        case .floatTabsNextTab, .floatTabsPreviousTab:
            return .floatTabs
        case .chatGPTOpenCommandMenu, .chatGPTOpenSettings,
             .chatGPTOpenKeyboardShortcuts, .chatGPTOpenFolder,
             .chatGPTNavigateBack, .chatGPTNavigateForward,
             .chatGPTIncreaseFontSize, .chatGPTDecreaseFontSize,
             .chatGPTResetFontSize, .chatGPTToggleSidebar,
             .chatGPTToggleBottomPanel, .chatGPTOpenTerminal,
             .chatGPTClearTerminal, .chatGPTClearUnread,
             .chatGPTUndo, .chatGPTRedo, .chatGPTCloseWindow,
             .chatGPTToggleFullScreen, .chatGPTQuit:
            return .chatGPTGeneral
        case .chatGPTNewChat, .chatGPTNewStandaloneChat,
             .chatGPTQuickChat, .chatGPTNewTemporaryChat,
             .chatGPTArchiveChat, .chatGPTMarkChatUnread,
             .chatGPTPinChat, .chatGPTRenameChat,
             .chatGPTOpenSideChat, .chatGPTSearchChats,
             .chatGPTFindInChat, .chatGPTFindNext,
             .chatGPTFindPrevious, .chatGPTPreviousChat,
             .chatGPTNextChat, .chatGPTNextAttention,
             .chatGPTOpenRecentChat1, .chatGPTOpenRecentChat2,
             .chatGPTOpenRecentChat3, .chatGPTOpenRecentChat4,
             .chatGPTOpenRecentChat5, .chatGPTOpenRecentChat6,
             .chatGPTGoToChat1, .chatGPTGoToChat2,
             .chatGPTGoToChat3, .chatGPTGoToChat4,
             .chatGPTGoToChat5, .chatGPTGoToChat6,
             .chatGPTGoToChat7, .chatGPTGoToChat8,
             .chatGPTGoToChat9:
            return .chatGPTChats
        case .chatGPTModelPicker, .chatGPTProjectPicker,
             .chatGPTStartVoiceChat, .chatGPTStartDictation,
             .chatGPTRestorePreviousPrompt, .chatGPTApproveRequest,
             .chatGPTDeclineRequest, .chatGPTSwitchToChat,
             .chatGPTSwitchToWork, .chatGPTSwitchToCodex,
             .chatGPTToggleActivity:
            return .chatGPTInputModes
        case .chatGPTRunEnvironmentAction, .chatGPTSearchFiles,
             .chatGPTToggleFileTree, .chatGPTOpenReviewTab,
             .chatGPTToggleReviewPanel, .chatGPTOpenBrowserTab,
             .chatGPTToggleBrowserPanel, .chatGPTFocusAddressBar,
             .chatGPTBrowserBack, .chatGPTBrowserForward,
             .chatGPTReloadBrowser, .chatGPTReloadBrowserNoCache,
             .chatGPTCopyBrowserURL, .chatGPTToggleBrowserMode,
             .chatGPTCopyConversationPath, .chatGPTCopyChatDeepLink,
             .chatGPTCopySessionID, .chatGPTCopyWorkingDirectory,
             .chatGPTTakeAppshot:
            return .chatGPTWorkspaceBrowser
        case .ghosttyNewTab, .ghosttyNewWindow, .ghosttyPreviousTab,
             .ghosttyNextTab, .ghosttyCloseSurface, .ghosttyNewSplitRight,
             .ghosttyNewSplitDown, .ghosttyCommandPalette, .ghosttySearch:
            return .ghostty
        case .obsidianCommandPalette, .obsidianQuickSwitcher, .obsidianNewNote,
             .obsidianNewTab, .obsidianReopenClosedTab, .obsidianCloseTab,
             .obsidianSearch, .obsidianToggleEditMode, .obsidianAddProperty,
             .obsidianPreviousTab, .obsidianNextTab:
            return .obsidian
        case .neteasePreviousTrack, .neteaseNextTrack:
            return .netease
        case .mouseRightClick:
            return .system
        }
    }

    /// 中文显示名称。
    var displayName: String {
        switch self {
        case .disabled:        return "禁用"
        case .escape:          return "Escape"
        case .returnKey:       return "Return"
        case .arrowUp:         return "方向上"
        case .arrowDown:       return "方向下"
        case .arrowLeft:       return "方向左"
        case .arrowRight:      return "方向右"
        case .pageUp:          return "向上滚屏"
        case .pageDown:        return "向下滚屏"
        case .reloadPage:      return "刷新当前页面（FloatTabs 直连 / Command-R）"
        case .deleteBackward:  return "Delete（退格）"
        case .showDesktop:     return "显示桌面"
        case .contextMenu:     return "上下文菜单（Shift-F10）"
        case .appSwitcher:     return "切换应用（Command-Tab）"
        case .openFloatTabs:   return "打开 / 显示 / 隐藏 FloatTabs"
        case .openCodex:       return "打开 / 显示 / 隐藏 Codex"
        case .copy:            return "复制（Command-C）"
        case .paste:           return "粘贴（Command-V）"
        case .cut:             return "剪切（Command-X）"
        case .selectAll:       return "全选（Command-A）"
        case .undo:            return "撤销（Command-Z）"
        case .redo:            return "重做（Command-Shift-Z）"
        case .floatTabsNextTab:     return "FloatTabs：下一个标签"
        case .floatTabsPreviousTab: return "FloatTabs：上一个标签"
        case .floatTabsToggleVisibility: return "FloatTabs：显示 / 隐藏"
        case .floatTabsToggleFocus:      return "FloatTabs：切换对话框 / 网页焦点"
        case .floatTabsSettings:         return "FloatTabs：打开设置"
        case .floatTabsToggleAlwaysOnTop: return "FloatTabs：开启 / 关闭置顶"
        case .chatGPTOpenCommandMenu:       return "ChatGPT / Codex：命令菜单（Command-Shift-P）"
        case .chatGPTOpenSettings:          return "ChatGPT / Codex：设置（Command-逗号）"
        case .chatGPTOpenKeyboardShortcuts: return "ChatGPT / Codex：键盘快捷键（Command-/）"
        case .chatGPTOpenFolder:            return "Codex：打开文件夹（Command-O）"
        case .chatGPTNavigateBack:          return "ChatGPT / Codex：返回（Command-[）"
        case .chatGPTNavigateForward:       return "ChatGPT / Codex：前进（Command-]）"
        case .chatGPTIncreaseFontSize:      return "ChatGPT / Codex：增大字体（Command-加号）"
        case .chatGPTDecreaseFontSize:      return "ChatGPT / Codex：减小字体（Command-减号）"
        case .chatGPTResetFontSize:         return "ChatGPT / Codex：重置字体（Command-0）"
        case .chatGPTToggleSidebar:         return "ChatGPT / Codex：显示 / 隐藏侧边栏（Command-B）"
        case .chatGPTToggleBottomPanel:     return "Codex：显示 / 隐藏底部面板（Command-J）"
        case .chatGPTOpenTerminal:          return "Codex：打开 / 关闭 Terminal（Control-反引号）"
        case .chatGPTClearTerminal:         return "Codex：清空 Terminal（Control-L）"
        case .chatGPTClearUnread:           return "Codex：清除需要注意标记（Shift-Esc）"
        case .chatGPTUndo:                  return "ChatGPT / Codex：撤销上次动作（Command-Z）"
        case .chatGPTRedo:                  return "ChatGPT / Codex：重做上次动作（Command-Shift-Z）"
        case .chatGPTCloseWindow:           return "ChatGPT / Codex：关闭当前标签 / 窗口（Command-W）"
        case .chatGPTToggleFullScreen:      return "ChatGPT / Codex：切换全屏（Command-Control-F）"
        case .chatGPTQuit:                  return "ChatGPT / Codex：退出程序（Command-Q）"
        case .chatGPTNewChat:               return "ChatGPT / Codex：新建对话（Command-N）"
        case .chatGPTNewStandaloneChat:     return "Codex：新建独立对话（Command-Option-O）"
        case .chatGPTQuickChat:             return "ChatGPT：快速对话（Command-Option-N）"
        case .chatGPTNewTemporaryChat:      return "ChatGPT：新建临时对话（Command-Shift-N）"
        case .chatGPTArchiveChat:           return "ChatGPT / Codex：归档当前对话（Command-Shift-A）"
        case .chatGPTMarkChatUnread:        return "ChatGPT / Codex：标记当前对话未读（Command-Shift-U）"
        case .chatGPTPinChat:               return "ChatGPT / Codex：置顶 / 取消置顶（Command-Option-P）"
        case .chatGPTRenameChat:            return "ChatGPT / Codex：重命名当前对话（Command-Option-R）"
        case .chatGPTOpenSideChat:          return "Codex：打开侧边对话（Command-Option-S）"
        case .chatGPTSearchChats:           return "ChatGPT / Codex：搜索对话（需在应用中分配快捷键）"
        case .chatGPTFindInChat:            return "ChatGPT / Codex：在对话中查找（Command-F）"
        case .chatGPTFindNext:              return "ChatGPT / Codex：查找下一个（Command-G）"
        case .chatGPTFindPrevious:          return "ChatGPT / Codex：查找上一个（Command-Shift-G）"
        case .chatGPTPreviousChat:          return "ChatGPT / Codex：上一个对话 / 标签（Command-Option-左，直接切换）"
        case .chatGPTNextChat:              return "ChatGPT / Codex：下一个对话 / 标签（Command-Option-右，直接切换）"
        case .chatGPTNextAttention:         return "Codex：下一个需要注意的对话（Command-Option-A）"
        case .chatGPTOpenRecentChat1:       return "ChatGPT / Codex：打开最近对话 1（Command-Option-1）"
        case .chatGPTOpenRecentChat2:       return "ChatGPT / Codex：打开最近对话 2（Command-Option-2）"
        case .chatGPTOpenRecentChat3:       return "ChatGPT / Codex：打开最近对话 3（Command-Option-3）"
        case .chatGPTOpenRecentChat4:       return "ChatGPT / Codex：打开最近对话 4（Command-Option-4）"
        case .chatGPTOpenRecentChat5:       return "ChatGPT / Codex：打开最近对话 5（Command-Option-5）"
        case .chatGPTOpenRecentChat6:       return "ChatGPT / Codex：打开最近对话 6（Command-Option-6）"
        case .chatGPTGoToChat1:             return "ChatGPT / Codex：跳转对话 1（Command-1）"
        case .chatGPTGoToChat2:             return "ChatGPT / Codex：跳转对话 2（Command-2）"
        case .chatGPTGoToChat3:             return "ChatGPT / Codex：跳转对话 3（Command-3）"
        case .chatGPTGoToChat4:             return "ChatGPT / Codex：跳转对话 4（Command-4）"
        case .chatGPTGoToChat5:             return "ChatGPT / Codex：跳转对话 5（Command-5）"
        case .chatGPTGoToChat6:             return "ChatGPT / Codex：跳转对话 6（Command-6）"
        case .chatGPTGoToChat7:             return "ChatGPT / Codex：跳转对话 7（Command-7）"
        case .chatGPTGoToChat8:             return "ChatGPT / Codex：跳转对话 8（Command-8）"
        case .chatGPTGoToChat9:             return "ChatGPT / Codex：跳转对话 9（Command-9）"
        case .chatGPTModelPicker:           return "ChatGPT / Codex：模型选择（Control-Shift-M）"
        case .chatGPTProjectPicker:         return "ChatGPT / Codex：项目选择（Command-Option-Shift-O）"
        case .chatGPTStartVoiceChat:        return "ChatGPT / Codex：开始语音对话（Control-Shift-V）"
        case .chatGPTStartDictation:        return "ChatGPT / Codex：开始听写（Control-Shift-D）"
        case .chatGPTRestorePreviousPrompt: return "ChatGPT / Codex：恢复上一次输入（方向上）"
        case .chatGPTApproveRequest:        return "ChatGPT / Codex：批准请求（Return）"
        case .chatGPTDeclineRequest:        return "ChatGPT / Codex：拒绝请求（Esc）"
        case .chatGPTSwitchToChat:          return "ChatGPT / Codex：切换到 Chat（Control-1）"
        case .chatGPTSwitchToWork:          return "ChatGPT / Codex：切换到 Work（Control-2）"
        case .chatGPTSwitchToCodex:         return "ChatGPT / Codex：切换到 Codex（Control-3）"
        case .chatGPTToggleActivity:        return "ChatGPT / Codex：显示 / 隐藏 Activity（Command-Option-U）"
        case .chatGPTRunEnvironmentAction:  return "Codex：运行环境主操作（Command-Shift-D）"
        case .chatGPTSearchFiles:            return "Codex：搜索文件（Command-P）"
        case .chatGPTToggleFileTree:         return "Codex：显示 / 隐藏文件树（Command-Shift-E）"
        case .chatGPTOpenReviewTab:          return "Codex：打开审查页（Control-Shift-G）"
        case .chatGPTToggleReviewPanel:      return "Codex：显示 / 隐藏审查面板（Command-Option-B）"
        case .chatGPTOpenBrowserTab:         return "Codex：打开浏览器标签（Command-T）"
        case .chatGPTToggleBrowserPanel:     return "Codex：显示 / 隐藏浏览器面板（Command-Shift-B）"
        case .chatGPTFocusAddressBar:        return "Codex：聚焦地址栏 / 跳转行号（Command-L）"
        case .chatGPTBrowserBack:            return "Codex：浏览器后退（Command-左方向）"
        case .chatGPTBrowserForward:         return "Codex：浏览器前进（Command-右方向）"
        case .chatGPTReloadBrowser:          return "Codex：刷新浏览器页面（Command-R）"
        case .chatGPTReloadBrowserNoCache:   return "Codex：无缓存刷新浏览器（Command-Shift-R）"
        case .chatGPTCopyBrowserURL:         return "Codex：复制浏览器网址（Command-Shift-C）"
        case .chatGPTToggleBrowserMode:      return "Codex：切换浏览 / 评论模式（Command-句号）"
        case .chatGPTCopyConversationPath:   return "Codex：复制对话路径（Command-Option-Shift-C）"
        case .chatGPTCopyChatDeepLink:       return "ChatGPT / Codex：复制对话链接（Command-Option-L）"
        case .chatGPTCopySessionID:          return "ChatGPT / Codex：复制会话 ID（Command-Option-C）"
        case .chatGPTCopyWorkingDirectory:   return "Codex：复制工作目录（Command-Shift-C）"
        case .chatGPTTakeAppshot:            return "Codex：截取 Appshot（双 Command 同时按下）"
        case .ghosttyNewTab:            return "Ghostty：新建标签"
        case .ghosttyNewWindow:         return "Ghostty：新建窗口"
        case .ghosttyPreviousTab:       return "Ghostty：上一个标签"
        case .ghosttyNextTab:           return "Ghostty：下一个标签"
        case .ghosttyCloseSurface:      return "Ghostty：关闭当前 surface"
        case .ghosttyNewSplitRight:     return "Ghostty：向右新建分屏"
        case .ghosttyNewSplitDown:      return "Ghostty：向下新建分屏"
        case .ghosttyCommandPalette:    return "Ghostty：命令面板"
        case .ghosttySearch:            return "Ghostty：搜索"
        case .obsidianCommandPalette:   return "Obsidian：命令面板"
        case .obsidianQuickSwitcher:    return "Obsidian：快速切换文件"
        case .obsidianNewNote:          return "Obsidian：新建笔记"
        case .obsidianNewTab:           return "Obsidian：新建标签"
        case .obsidianReopenClosedTab:  return "Obsidian：恢复最近关闭标签"
        case .obsidianCloseTab:         return "Obsidian：关闭标签"
        case .obsidianSearch:           return "Obsidian：全库搜索"
        case .obsidianToggleEditMode:   return "Obsidian：切换编辑 / 阅读模式"
        case .obsidianAddProperty:      return "Obsidian：添加属性"
        case .obsidianPreviousTab:      return "Obsidian：上一个标签"
        case .obsidianNextTab:          return "Obsidian：下一个标签"
        case .neteasePreviousTrack:     return "网易云音乐：上一首"
        case .neteaseNextTrack:         return "网易云音乐：下一首"
        case .mouseRightClick: return "鼠标右键（当前位置）"
        case .volumeUp:        return "系统音量 +"
        case .volumeDown:      return "系统音量 -"
        case .volumeMute:      return "系统静音"
        case .playPause:       return "播放 / 暂停"
        }
    }
}

enum ButtonActionCategory: String, CaseIterable, Hashable, Identifiable {
    case system
    case applications
    case navigation
    case editing
    case media
    case floatTabs
    case chatGPTGeneral
    case chatGPTChats
    case chatGPTInputModes
    case chatGPTWorkspaceBrowser
    case ghostty
    case obsidian
    case netease

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:    return "系统控制"
        case .applications: return "程序启动"
        case .navigation:return "方向与滚动"
        case .editing:   return "复制与编辑"
        case .media:     return "媒体控制"
        case .floatTabs: return "FloatTabs"
        case .chatGPTGeneral:          return "ChatGPT / Codex · 通用"
        case .chatGPTChats:            return "ChatGPT / Codex · 对话"
        case .chatGPTInputModes:       return "ChatGPT / Codex · 输入与模式"
        case .chatGPTWorkspaceBrowser: return "ChatGPT / Codex · 工作区与浏览器"
        case .ghostty:   return "Ghostty"
        case .obsidian:  return "Obsidian"
        case .netease:   return "网易云音乐"
        }
    }

    static let chatGPTCategories: Set<ButtonActionCategory> = [
        .chatGPTGeneral,
        .chatGPTChats,
        .chatGPTInputModes,
        .chatGPTWorkspaceBrowser,
    ]
}

// MARK: - ButtonBinding（按钮绑定）

/// 自定义快捷键的触发方式。
///
/// 旧版配置没有这个字段，解码时会按 `.single` 处理，避免升级后已有的
/// Command+Q、Command+Home 等映射突然变成长按重复。
enum ShortcutTriggerMode: String, Codable, CaseIterable, Identifiable {
    case single
    case repeatWhileHeld

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .single:          return "单次点击"
        case .repeatWhileHeld: return "按住重复"
        }
    }

    var shortLabel: String {
        switch self {
        case .single:          return "单次"
        case .repeatWhileHeld: return "重复"
        }
    }

    var helpText: String {
        switch self {
        case .single:
            return "按一下只发送一次，适合打开程序、切换窗口、Command+Q 等快捷键。"
        case .repeatWhileHeld:
            return "按住约 350 ms 后按遥控器重复节奏发送，适合音量、删除、方向移动等操作。"
        }
    }
}

/// 一个按钮的完整绑定，可以是预设动作、自定义快捷键或语音键默认行为。
enum ButtonBinding: Codable, Equatable {
    case preset(ButtonAction)
    case shortcut(KeyChord, trigger: ShortcutTriggerMode)
    case voiceKeyDefault

    private enum CodingKeys: String, CodingKey { case type, action, chord, trigger }
    private enum Kind: String, Codable { case preset, shortcut, voiceKeyDefault }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .preset:
            self = .preset(try container.decode(ButtonAction.self, forKey: .action))
        case .shortcut:
            let chord = try container.decode(KeyChord.self, forKey: .chord)
            let trigger = try container.decodeIfPresent(
                ShortcutTriggerMode.self,
                forKey: .trigger
            ) ?? .single
            self = .shortcut(chord, trigger: trigger)
        case .voiceKeyDefault:
            self = .voiceKeyDefault
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .preset(action):
            try container.encode(Kind.preset, forKey: .type)
            try container.encode(action, forKey: .action)
        case let .shortcut(chord, trigger):
            try container.encode(Kind.shortcut, forKey: .type)
            try container.encode(chord, forKey: .chord)
            try container.encode(trigger, forKey: .trigger)
        case .voiceKeyDefault:
            try container.encode(Kind.voiceKeyDefault, forKey: .type)
        }
    }

    /// 显示名称。
    var displayName: String {
        switch self {
        case let .preset(action):  return action.displayName
        case let .shortcut(chord, _): return chord.displayName
        case .voiceKeyDefault:     return "语音键默认（短按自动物理麦克风 / 长按遥控器）"
        }
    }

    /// 自定义快捷键的触发方式；预设动作仍沿用按钮原本的重复规则。
    var shortcutTriggerMode: ShortcutTriggerMode? {
        if case let .shortcut(_, trigger) = self { return trigger }
        return nil
    }

    /// 是否为禁用状态。
    var isDisabled: Bool {
        if case .preset(.disabled) = self { return true }
        return false
    }
}

// MARK: - 默认映射表

/// 所有按钮的默认绑定。
enum DefaultBindings {
    static let all: [RemoteButton: ButtonBinding] = [
        .microphone:  .voiceKeyDefault,
        .power:       .preset(.disabled),
        .up:          .preset(.arrowUp),
        .down:        .preset(.arrowDown),
        .left:        .preset(.arrowLeft),
        .right:       .preset(.arrowRight),
        .ok:          .preset(.returnKey),
        .back:        .preset(.escape),
        .home:        .preset(.showDesktop),
        .menu:        .preset(.contextMenu),
        .tv:          .preset(.appSwitcher),
        .volumeUp:    .preset(.chatGPTPreviousChat),
        .volumeDown:  .preset(.chatGPTNextChat),
    ]

    /// ChatGPT/Codex 桌面端默认模板（Bundle ID: com.openai.codex）。
    /// 预设动作保留语义名称，实际快捷键由RemoteOrbit统一发送；菜单键保留为空，
    /// 方便用户自行录制。
    static let chatGPT: [RemoteButton: ButtonBinding] = [
        .microphone:  .voiceKeyDefault,
        .power:       .preset(.disabled),
        .up:          .preset(.pageUp),
        .down:        .preset(.pageDown),
        .left:        .preset(.chatGPTToggleSidebar),
        .ok:          .preset(.returnKey),
        .right:       .preset(.chatGPTToggleBottomPanel),
        .back:        .preset(.deleteBackward),
        .volumeUp:    .preset(.chatGPTPreviousChat),
        .home:        .preset(.chatGPTNextAttention),
        .volumeDown:  .preset(.chatGPTNextChat),
        .menu:        .preset(.disabled),
        .tv:          .preset(.appSwitcher),
    ]
}
