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
enum RemoteNativeEvent: Equatable, Hashable {
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
    case spaceKey
    case tabKey
    case shiftTabKey
    case escape
    case returnKey
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case pageUp
    case pageDown
    case keyboardPageUp
    case keyboardPageDown
    case navigateBack
    case navigateForward
    /// Refreshes the current page semantically; FloatTabs uses its direct
    /// command, while ordinary browsers receive their standard Command-R.
    case reloadPage
    case newTab
    case closeTabOrWindow
    case reopenClosedTab
    case previousTab
    case nextTab
    case deleteBackward
    case forwardDelete
    case showDesktop
    case contextMenu
    case appSwitcher
    case cycleAppWindows
    case missionControl
    case toggleFullScreen
    /// Opens a read-only controller-shaped view of the mappings that are
    /// active for the current foreground application.
    case inspectCurrentKeymap
    case openFloatTabs
    case openCodex
    case openT3Code
    case openGemini
    case openGhostty
    case openChrome
    case openObsidian
    case openAntigravity
    case openWeChat
    case copy
    case paste
    case pastePlainText
    case cut
    case selectAll
    case undo
    case redo
    case find
    case findNext
    case findPrevious
    // System-level caret and range selection actions. They operate on the
    // text control that already owns the insertion point; Remote Orbit does
    // not inspect or change the receiving app's document contents.
    case moveToLineStart
    case moveToLineEnd
    case moveToDocumentStart
    case moveToDocumentEnd
    case extendSelectionLeft
    case extendSelectionRight
    case extendSelectionUp
    case extendSelectionDown
    case extendSelectionToLineStart
    case extendSelectionToLineEnd
    case extendSelectionToDocumentStart
    case extendSelectionToDocumentEnd
    /// FloatTabs' app-local tab navigation shortcuts.
    case floatTabsSelectSlot1
    case floatTabsSelectSlot2
    case floatTabsSelectSlot3
    case floatTabsSelectSlot4
    case floatTabsSelectSlot5
    case floatTabsSelectSlot6
    case floatTabsSelectSlot7
    case floatTabsSelectSlot8
    case floatTabsSelectSlot9
    case floatTabsNextTab
    case floatTabsPreviousTab
    case floatTabsAddWebApp
    case floatTabsZoomIn
    case floatTabsZoomOut
    case floatTabsResetZoom
    case floatTabsAddressBar
    case floatTabsReturnHome
    case floatTabsTogglePin
    case floatTabsSetHotResidency
    case floatTabsSetWarmResidency
    case floatTabsSetColdResidency
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
    case chatGPTInterruptTerminal
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
    case chatGPTQuickCommandSearch
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
    case chatGPTScrollToTop
    case chatGPTScrollToBottom
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
    /// Focuses the Codex conversation composer when its Chromium surface does
    /// not expose an AX text input element.
    case chatGPTFocusConversationInput
    case chatGPTRestorePreviousPrompt
    case chatGPTInsertNewline
    case chatGPTStopGeneration
    case chatGPTPastePlainText
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
    // Ghostty terminal
    case ghosttyNewTab
    case ghosttyNewWindow
    case ghosttyPreviousTab
    case ghosttyNextTab
    case ghosttyGoToTab1
    case ghosttyGoToTab2
    case ghosttyGoToTab3
    case ghosttyGoToTab4
    case ghosttyGoToTab5
    case ghosttyGoToTab6
    case ghosttyGoToTab7
    case ghosttyGoToTab8
    case ghosttyLastTab
    case ghosttyCloseSurface
    case ghosttyCloseTab
    case ghosttyCloseWindow
    case ghosttyNewSplitRight
    case ghosttyNewSplitDown
    case ghosttyPreviousSplit
    case ghosttyNextSplit
    case ghosttyFocusSplitUp
    case ghosttyFocusSplitDown
    case ghosttyFocusSplitLeft
    case ghosttyFocusSplitRight
    case ghosttyToggleSplitZoom
    case ghosttyEqualizeSplits
    case ghosttyPreviousPrompt
    case ghosttyNextPrompt
    case ghosttyClearScreen
    case ghosttyInterrupt
    case ghosttyScrollToTop
    case ghosttyScrollToBottom
    case ghosttyScrollToSelection
    case ghosttyCommandPalette
    case ghosttySearch
    case ghosttyFindNext
    case ghosttyFindPrevious
    case ghosttyIncreaseFontSize
    case ghosttyDecreaseFontSize
    case ghosttyResetFontSize
    case ghosttyToggleFullScreen
    case ghosttyOpenConfig
    case ghosttyReloadConfig
    case ghosttyToggleInspector
    // Obsidian
    case obsidianCommandPalette
    case obsidianQuickSwitcher
    case obsidianNewNote
    case obsidianNewTab
    case obsidianReopenClosedTab
    case obsidianCloseTab
    case obsidianSearch
    case obsidianToggleEditMode
    case obsidianAddProperty
    case obsidianIncreaseFontSize
    case obsidianDecreaseFontSize
    case obsidianResetFontSize
    case obsidianFocusEditor
    case obsidianFocusTabGroupLeft
    case obsidianFocusTabGroupRight
    case obsidianFocusTabGroupAbove
    case obsidianFocusTabGroupBelow
    case obsidianPreviousTab
    case obsidianNextTab
    case obsidianToggleLeftSidebar
    case obsidianToggleRightSidebar
    case obsidianGoToTab1
    case obsidianGoToTab2
    case obsidianGoToTab3
    case obsidianGoToTab4
    case obsidianGoToTab5
    case obsidianGoToTab6
    case obsidianGoToTab7
    case obsidianGoToTab8
    case obsidianGoToTab9
    case obsidianNewNoteToRight
    case obsidianSearchCurrentFile
    case obsidianOpenGraphView
    case obsidianOpenSettings
    case obsidianCloseOtherTabs
    case obsidianSplitRight
    case obsidianSplitDown
    case obsidianToggleStackedTabs
    case obsidianShowBacklinks
    case obsidianShowOutgoingLinks
    case obsidianShowTags
    case obsidianShowOutline
    case obsidianShowBookmarks
    case obsidianShowAllProperties
    case obsidianShowFileProperties
    case obsidianOpenDailyNote
    case obsidianInsertTemplate
    case obsidianOpenFileExplorer
    case obsidianMoveTabToNewWindow
    case obsidianOpenTabInNewWindow
    case obsidianCreateNewCanvas
    // NetEase Cloud Music
    case neteasePreviousTrack
    case neteaseNextTrack
    // Browser exclusive (Chrome, Safari, Arc, Edge, Firefox)
    case browserAddressBar
    case browserNewTab
    case browserNewPrivateWindow
    case browserCloseTab
    case browserReopenClosedTab
    case browserPreviousTab
    case browserNextTab
    case browserGoToTab1
    case browserGoToTab2
    case browserGoToTab3
    case browserGoToTab4
    case browserGoToTab5
    case browserGoToTab6
    case browserGoToTab7
    case browserGoToTab8
    case browserLastTab
    case browserBack
    case browserForward
    case browserReload
    case browserReloadNoCache
    case browserBookmarkPage
    case browserHistory
    case browserDownloads
    case browserDeveloperTools
    case browserZoomIn
    case browserZoomOut
    case browserResetZoom
    // IINA media player exclusive
    case iinaPlayPause
    case iinaSeekBackward
    case iinaSeekForward
    case iinaPreviousFrame
    case iinaNextFrame
    case iinaSpeedDown
    case iinaSpeedUp
    case iinaResetSpeed
    case iinaVolumeUp
    case iinaVolumeDown
    case iinaToggleMute
    case iinaPreviousFile
    case iinaNextFile
    case iinaToggleFullScreen
    case iinaPictureInPicture
    case iinaToggleOnTop
    case iinaCycleSubtitles
    case iinaCycleAudio
    case iinaShowPlaylist
    case iinaScreenshot
    // Code & AI Workspace exclusive (T3 Code, Antigravity, VS Code, Cursor)
    case workspaceCommandPalette
    case workspaceQuickOpen
    case workspaceGlobalSearch
    case workspaceFindInFile
    case workspaceNavigateBack
    case workspaceNavigateForward
    case workspaceToggleSidebar
    case workspaceToggleBottomPanel
    case workspaceToggleTerminal
    case workspaceNewChatOrWindow
    case workspaceSplitEditor
    case workspaceCloseTab
    case workspacePreviousTab
    case workspaceNextTab
    case workspaceOpenSettings
    // Xcode exclusive
    case xcodeRun
    case xcodeStop
    case xcodeBuild
    case xcodeTest
    case xcodeOpenQuickly
    case xcodeFindInProject
    case xcodeToggleNavigator
    case xcodeToggleDebugArea
    case xcodeToggleInspector
    case xcodeClearConsole
    case xcodePreviousHistory
    case xcodeNextHistory
    case xcodeCloseTab
    // T3 Code desktop exclusive
    case t3NewChat
    case t3NewLocalChat
    case t3NewQuickChat
    case t3PreviousThread
    case t3NextThread
    case t3GoToThread1
    case t3GoToThread2
    case t3GoToThread3
    case t3GoToThread4
    case t3GoToThread5
    case t3GoToThread6
    case t3GoToThread7
    case t3GoToThread8
    case t3GoToThread9
    case t3SettleThread
    case t3PinThread
    case t3SendAndNewThread
    case t3SteerQueuedMessage
    case t3StashDraft
    case t3Dictation
    case t3CopyThreadRef
    case t3CopyPRNumber
    case t3ToggleSidebar
    case t3ToggleTerminal
    case t3ToggleDiff
    case t3TogglePreview
    case t3ToggleRightPanel
    case t3ToggleThreadPanel
    case t3NavigateBack
    case t3NavigateForward
    case t3ClosePanel
    case t3ReopenClosed
    case t3PreviewRefresh
    case t3CommandPalette
    case t3FilePicker
    case t3ProjectSearch
    case t3FindInChat
    case t3ModelPicker
    case t3SwitchMode
    case t3SwitchEffort
    case t3SwitchWorkspace
    case t3SwitchBranch
    case t3OpenInEditor
    case t3OpenUsage
    case t3OpenSettings
    // Gemini desktop exclusive
    case geminiNewChat
    case geminiNewTemporaryChat
    case geminiSendOrApproveOnce
    case geminiApproveForThread
    case geminiApproveAlways
    case geminiInsertNewline
    case geminiStopOrDeny
    case geminiSwitchAntigravity
    case geminiAreaScreenshot
    case geminiReloadChats
    case geminiFindInChat
    case geminiFindNext
    case geminiFindPrevious
    case geminiIncreaseTextSize
    case geminiDecreaseTextSize
    case geminiResetTextSize
    case geminiCloseWindow
    case geminiOpenSettings
    // WeChat exclusive
    case wechatSearch
    case wechatNewGroupChat
    case wechatLineBreak
    case wechatScreenshot
    case wechatLock
    case wechatCloseWindow
    case wechatOpenSettings
    // System & Media
    case mouseRightClick
    case volumeUp
    case volumeDown
    case volumeMute
    case playPause
    case mediaPreviousTrack
    case mediaNextTrack

    var id: String { rawValue }

    /// Whether a preset is safe and meaningful to repeat while the physical
    /// button remains held. Toggle/open actions must stay atomic: repeating
    /// Command-B, for example, would immediately reopen a sidebar that the
    /// first tap just closed. Users can still opt into repetition explicitly
    /// for recorded shortcuts via the `.repeatWhileHeld` trigger.
    var repeatsWhenHeld: Bool {
        switch self {
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight,
             .pageUp, .pageDown, .keyboardPageUp, .keyboardPageDown,
             .deleteBackward, .forwardDelete,
             .volumeUp, .volumeDown,
             .iinaSeekBackward, .iinaSeekForward,
             .iinaVolumeUp, .iinaVolumeDown:
            return true
        default:
            return false
        }
    }

    var category: ButtonActionCategory {
        switch self {
        case .disabled, .showDesktop, .contextMenu, .appSwitcher,
             .cycleAppWindows, .missionControl, .toggleFullScreen,
             .inspectCurrentKeymap, .mouseRightClick:
            return .system
        case .openFloatTabs, .openCodex, .openT3Code, .openGemini,
             .openGhostty, .openChrome, .openObsidian,
             .openAntigravity, .openWeChat:
            return .applications
        case .spaceKey, .tabKey, .shiftTabKey,
             .escape, .returnKey, .arrowUp, .arrowDown, .arrowLeft, .arrowRight,
             .pageUp, .pageDown, .keyboardPageUp, .keyboardPageDown,
             .navigateBack, .navigateForward, .reloadPage,
             .newTab, .closeTabOrWindow, .reopenClosedTab,
             .previousTab, .nextTab:
            return .navigation
        case .copy, .paste, .pastePlainText, .cut, .selectAll,
             .deleteBackward, .forwardDelete, .undo, .redo,
             .find, .findNext, .findPrevious:
            return .editing
        case .moveToLineStart, .moveToLineEnd, .moveToDocumentStart,
             .moveToDocumentEnd, .extendSelectionLeft, .extendSelectionRight,
             .extendSelectionUp, .extendSelectionDown,
             .extendSelectionToLineStart, .extendSelectionToLineEnd,
             .extendSelectionToDocumentStart, .extendSelectionToDocumentEnd:
            return .selection
        case .volumeUp, .volumeDown, .volumeMute, .playPause,
             .mediaPreviousTrack, .mediaNextTrack:
            return .media
        case .floatTabsSelectSlot1, .floatTabsSelectSlot2,
             .floatTabsSelectSlot3, .floatTabsSelectSlot4,
             .floatTabsSelectSlot5, .floatTabsSelectSlot6,
             .floatTabsSelectSlot7, .floatTabsSelectSlot8,
             .floatTabsSelectSlot9, .floatTabsNextTab,
             .floatTabsPreviousTab, .floatTabsAddWebApp,
             .floatTabsZoomIn, .floatTabsZoomOut,
             .floatTabsResetZoom, .floatTabsAddressBar,
             .floatTabsReturnHome, .floatTabsTogglePin,
             .floatTabsSetHotResidency, .floatTabsSetWarmResidency,
             .floatTabsSetColdResidency, .floatTabsToggleVisibility,
             .floatTabsToggleFocus, .floatTabsSettings,
             .floatTabsToggleAlwaysOnTop:
            return .floatTabs
        case .chatGPTOpenCommandMenu, .chatGPTOpenSettings,
             .chatGPTOpenKeyboardShortcuts, .chatGPTOpenFolder,
             .chatGPTNavigateBack, .chatGPTNavigateForward,
             .chatGPTIncreaseFontSize, .chatGPTDecreaseFontSize,
             .chatGPTResetFontSize, .chatGPTToggleSidebar,
             .chatGPTToggleBottomPanel, .chatGPTOpenTerminal,
             .chatGPTClearTerminal, .chatGPTInterruptTerminal,
             .chatGPTClearUnread, .chatGPTUndo, .chatGPTRedo,
             .chatGPTCloseWindow, .chatGPTToggleFullScreen, .chatGPTQuit:
            return .chatGPTGeneral
        case .chatGPTNewChat, .chatGPTNewStandaloneChat,
             .chatGPTQuickChat, .chatGPTNewTemporaryChat,
             .chatGPTQuickCommandSearch,
             .chatGPTArchiveChat, .chatGPTMarkChatUnread,
             .chatGPTPinChat, .chatGPTRenameChat,
             .chatGPTOpenSideChat, .chatGPTSearchChats,
             .chatGPTFindInChat, .chatGPTFindNext,
             .chatGPTFindPrevious, .chatGPTPreviousChat,
             .chatGPTNextChat, .chatGPTNextAttention,
             .chatGPTScrollToTop, .chatGPTScrollToBottom,
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
             .chatGPTFocusConversationInput,
             .chatGPTRestorePreviousPrompt, .chatGPTInsertNewline,
             .chatGPTStopGeneration, .chatGPTPastePlainText,
             .chatGPTApproveRequest, .chatGPTDeclineRequest,
             .chatGPTSwitchToChat, .chatGPTSwitchToWork,
             .chatGPTSwitchToCodex, .chatGPTToggleActivity:
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
             .ghosttyNextTab, .ghosttyGoToTab1, .ghosttyGoToTab2,
             .ghosttyGoToTab3, .ghosttyGoToTab4, .ghosttyGoToTab5,
             .ghosttyGoToTab6, .ghosttyGoToTab7, .ghosttyGoToTab8,
             .ghosttyLastTab, .ghosttyCloseSurface, .ghosttyCloseTab,
             .ghosttyCloseWindow, .ghosttyNewSplitRight, .ghosttyNewSplitDown,
             .ghosttyPreviousSplit, .ghosttyNextSplit,
             .ghosttyFocusSplitUp, .ghosttyFocusSplitDown,
             .ghosttyFocusSplitLeft, .ghosttyFocusSplitRight,
             .ghosttyToggleSplitZoom, .ghosttyEqualizeSplits,
             .ghosttyPreviousPrompt, .ghosttyNextPrompt,
             .ghosttyClearScreen, .ghosttyInterrupt,
             .ghosttyScrollToTop, .ghosttyScrollToBottom,
             .ghosttyScrollToSelection, .ghosttyCommandPalette,
             .ghosttySearch, .ghosttyFindNext, .ghosttyFindPrevious,
             .ghosttyIncreaseFontSize, .ghosttyDecreaseFontSize,
             .ghosttyResetFontSize, .ghosttyToggleFullScreen,
             .ghosttyOpenConfig, .ghosttyReloadConfig,
             .ghosttyToggleInspector:
            return .ghostty
        case .obsidianCommandPalette, .obsidianQuickSwitcher, .obsidianNewNote,
             .obsidianNewTab, .obsidianReopenClosedTab, .obsidianCloseTab,
             .obsidianSearch, .obsidianToggleEditMode, .obsidianAddProperty,
             .obsidianIncreaseFontSize, .obsidianDecreaseFontSize,
             .obsidianResetFontSize,
             .obsidianFocusEditor, .obsidianFocusTabGroupLeft,
             .obsidianFocusTabGroupRight, .obsidianFocusTabGroupAbove,
             .obsidianFocusTabGroupBelow,
             .obsidianPreviousTab, .obsidianNextTab,
             .obsidianToggleLeftSidebar, .obsidianToggleRightSidebar,
             .obsidianGoToTab1, .obsidianGoToTab2, .obsidianGoToTab3,
             .obsidianGoToTab4, .obsidianGoToTab5, .obsidianGoToTab6,
             .obsidianGoToTab7, .obsidianGoToTab8, .obsidianGoToTab9,
             .obsidianNewNoteToRight, .obsidianSearchCurrentFile,
             .obsidianOpenGraphView, .obsidianOpenSettings,
             .obsidianCloseOtherTabs, .obsidianSplitRight, .obsidianSplitDown,
             .obsidianToggleStackedTabs,
             .obsidianShowBacklinks, .obsidianShowOutgoingLinks,
             .obsidianShowTags, .obsidianShowOutline, .obsidianShowBookmarks,
             .obsidianShowAllProperties,
             .obsidianShowFileProperties, .obsidianOpenDailyNote,
             .obsidianInsertTemplate, .obsidianOpenFileExplorer,
             .obsidianMoveTabToNewWindow, .obsidianOpenTabInNewWindow,
             .obsidianCreateNewCanvas:
            return .obsidian
        case .neteasePreviousTrack, .neteaseNextTrack:
            return .netease
        case .browserAddressBar, .browserNewTab, .browserNewPrivateWindow,
             .browserCloseTab, .browserReopenClosedTab, .browserPreviousTab,
             .browserNextTab, .browserGoToTab1, .browserGoToTab2,
             .browserGoToTab3, .browserGoToTab4, .browserGoToTab5,
             .browserGoToTab6, .browserGoToTab7, .browserGoToTab8,
             .browserLastTab, .browserBack, .browserForward,
             .browserReload, .browserReloadNoCache, .browserBookmarkPage,
             .browserHistory, .browserDownloads, .browserDeveloperTools,
             .browserZoomIn, .browserZoomOut, .browserResetZoom:
            return .browser
        case .iinaPlayPause, .iinaSeekBackward, .iinaSeekForward,
             .iinaPreviousFrame, .iinaNextFrame, .iinaSpeedDown,
             .iinaSpeedUp, .iinaResetSpeed, .iinaVolumeUp,
             .iinaVolumeDown, .iinaToggleMute, .iinaPreviousFile,
             .iinaNextFile, .iinaToggleFullScreen, .iinaPictureInPicture,
             .iinaToggleOnTop, .iinaCycleSubtitles, .iinaCycleAudio,
             .iinaShowPlaylist, .iinaScreenshot:
            return .iina
        case .workspaceCommandPalette, .workspaceQuickOpen, .workspaceGlobalSearch,
             .workspaceFindInFile, .workspaceNavigateBack, .workspaceNavigateForward,
             .workspaceToggleSidebar, .workspaceToggleBottomPanel, .workspaceToggleTerminal,
             .workspaceNewChatOrWindow, .workspaceSplitEditor, .workspaceCloseTab,
             .workspacePreviousTab, .workspaceNextTab, .workspaceOpenSettings:
            return .codeWorkspace
        case .xcodeRun, .xcodeStop, .xcodeBuild, .xcodeTest,
             .xcodeOpenQuickly, .xcodeFindInProject, .xcodeToggleNavigator,
             .xcodeToggleDebugArea, .xcodeToggleInspector, .xcodeClearConsole,
             .xcodePreviousHistory, .xcodeNextHistory, .xcodeCloseTab:
            return .xcode
        case .t3NewChat, .t3NewLocalChat, .t3NewQuickChat,
             .t3PreviousThread, .t3NextThread,
             .t3GoToThread1, .t3GoToThread2, .t3GoToThread3,
             .t3GoToThread4, .t3GoToThread5, .t3GoToThread6,
             .t3GoToThread7, .t3GoToThread8, .t3GoToThread9,
             .t3SettleThread, .t3PinThread,
             .t3SendAndNewThread, .t3SteerQueuedMessage,
             .t3StashDraft, .t3Dictation,
             .t3CopyThreadRef, .t3CopyPRNumber,
             .t3ToggleSidebar, .t3ToggleTerminal,
             .t3ToggleDiff, .t3TogglePreview,
             .t3ToggleRightPanel, .t3ToggleThreadPanel,
             .t3NavigateBack, .t3NavigateForward,
             .t3ClosePanel, .t3ReopenClosed, .t3PreviewRefresh,
             .t3CommandPalette, .t3FilePicker,
             .t3ProjectSearch, .t3FindInChat,
             .t3ModelPicker, .t3SwitchMode,
             .t3SwitchEffort, .t3SwitchWorkspace,
             .t3SwitchBranch, .t3OpenInEditor,
             .t3OpenUsage, .t3OpenSettings:
            return .t3Code
        case .geminiNewChat, .geminiNewTemporaryChat,
             .geminiSendOrApproveOnce, .geminiApproveForThread,
             .geminiApproveAlways, .geminiInsertNewline,
             .geminiStopOrDeny, .geminiSwitchAntigravity,
             .geminiAreaScreenshot, .geminiReloadChats,
             .geminiFindInChat, .geminiFindNext, .geminiFindPrevious,
             .geminiIncreaseTextSize, .geminiDecreaseTextSize,
             .geminiResetTextSize, .geminiCloseWindow,
             .geminiOpenSettings:
            return .gemini
        case .wechatSearch, .wechatNewGroupChat, .wechatLineBreak,
             .wechatScreenshot, .wechatLock,
             .wechatCloseWindow, .wechatOpenSettings:
            return .wechat
        }
    }

    /// 中文显示名称。
    var displayName: String {
        switch self {
        case .disabled:          return "禁用"
        case .spaceKey:          return "Space（空格 / 预览 / 暂停）"
        case .tabKey:            return "Tab（下一焦点）"
        case .shiftTabKey:       return "Shift-Tab（上一焦点）"
        case .escape:            return "Escape"
        case .returnKey:         return "Return"
        case .arrowUp:           return "方向上"
        case .arrowDown:         return "方向下"
        case .arrowLeft:         return "方向左"
        case .arrowRight:        return "方向右"
        case .pageUp:            return "向上滚屏（平滑滚轮）"
        case .pageDown:          return "向下滚屏（平滑滚轮）"
        case .keyboardPageUp:    return "上一页（Page Up 键）"
        case .keyboardPageDown:  return "下一页（Page Down 键）"
        case .navigateBack:      return "通用后退（Command-[）"
        case .navigateForward:   return "通用前进（Command-]）"
        case .reloadPage:        return "刷新当前页面（Command-R）"
        case .newTab:            return "新建标签页（Command-T）"
        case .closeTabOrWindow:  return "关闭当前标签 / 窗口（Command-W）"
        case .reopenClosedTab:   return "恢复刚关闭的标签（Command-Shift-T）"
        case .previousTab:       return "上一个标签页（Control-Shift-Tab）"
        case .nextTab:           return "下一个标签页（Control-Tab）"
        case .deleteBackward:    return "Delete（退格删除）"
        case .forwardDelete:     return "Forward Delete（向后删除）"
        case .showDesktop:       return "显示桌面"
        case .contextMenu:       return "上下文菜单（Shift-F10）"
        case .appSwitcher:       return "切换应用（Command-Tab）"
        case .cycleAppWindows:   return "切换同应用窗口（Command-反引号）"
        case .missionControl:    return "调度中心 Mission Control（Control-上方向）"
        case .toggleFullScreen:  return "切换全屏（Control-Command-F）"
        case .inspectCurrentKeymap: return "检查当前快捷映射"
        case .openFloatTabs:     return "打开 / 显示 / 隐藏 FloatTabs"
        case .openCodex:         return "打开 / 显示 / 隐藏 Codex"
        case .openT3Code:        return "打开 / 显示 / 隐藏 T3 Code"
        case .openGemini:        return "打开 / 显示 / 隐藏 Gemini"
        case .openGhostty:       return "打开 / 显示 / 隐藏 Ghostty"
        case .openChrome:        return "打开 / 显示 / 隐藏 Chrome"
        case .openObsidian:      return "打开 / 显示 / 隐藏 Obsidian"
        case .openAntigravity:   return "打开 / 显示 / 隐藏 Antigravity"
        case .openWeChat:        return "打开 / 显示 / 隐藏微信"
        case .copy:              return "复制（Command-C）"
        case .paste:             return "粘贴（Command-V）"
        case .pastePlainText:    return "纯文本粘贴（Command-Shift-V）"
        case .cut:               return "剪切（Command-X）"
        case .selectAll:         return "全选（Command-A）"
        case .undo:              return "撤销（Command-Z）"
        case .redo:              return "重做（Command-Shift-Z）"
        case .find:              return "查找（Command-F）"
        case .findNext:          return "查找下一个（Command-G）"
        case .findPrevious:      return "查找上一个（Command-Shift-G）"
        case .moveToLineStart:             return "光标移到行首（Command-左方向）"
        case .moveToLineEnd:               return "光标移到行尾（Command-右方向）"
        case .moveToDocumentStart:         return "光标移到文档开头（Command-上方向）"
        case .moveToDocumentEnd:           return "光标移到文档末尾（Command-下方向）"
        case .extendSelectionLeft:         return "向左扩展选择（Shift-左方向）"
        case .extendSelectionRight:        return "向右扩展选择（Shift-右方向）"
        case .extendSelectionUp:           return "向上扩展选择（Shift-上方向）"
        case .extendSelectionDown:         return "向下扩展选择（Shift-下方向）"
        case .extendSelectionToLineStart:  return "选择到行首（Command-Shift-左方向）"
        case .extendSelectionToLineEnd:    return "选择到行尾（Command-Shift-右方向）"
        case .extendSelectionToDocumentStart: return "选择到文档开头（Command-Shift-上方向）"
        case .extendSelectionToDocumentEnd:   return "选择到文档末尾（Command-Shift-下方向）"
        case .floatTabsSelectSlot1: return "FloatTabs：直达标签 1"
        case .floatTabsSelectSlot2: return "FloatTabs：直达标签 2"
        case .floatTabsSelectSlot3: return "FloatTabs：直达标签 3"
        case .floatTabsSelectSlot4: return "FloatTabs：直达标签 4"
        case .floatTabsSelectSlot5: return "FloatTabs：直达标签 5"
        case .floatTabsSelectSlot6: return "FloatTabs：直达标签 6"
        case .floatTabsSelectSlot7: return "FloatTabs：直达标签 7"
        case .floatTabsSelectSlot8: return "FloatTabs：直达标签 8"
        case .floatTabsSelectSlot9: return "FloatTabs：直达标签 9"
        case .floatTabsNextTab:     return "FloatTabs：下一个标签"
        case .floatTabsPreviousTab: return "FloatTabs：上一个标签"
        case .floatTabsAddWebApp:   return "FloatTabs：新增网页"
        case .floatTabsZoomIn:      return "FloatTabs：放大页面"
        case .floatTabsZoomOut:     return "FloatTabs：缩小页面"
        case .floatTabsResetZoom:   return "FloatTabs：重置页面缩放"
        case .floatTabsAddressBar:  return "FloatTabs：打开地址栏"
        case .floatTabsReturnHome:  return "FloatTabs：回到主页"
        case .floatTabsTogglePin:  return "FloatTabs：置顶 / 自动隐藏"
        case .floatTabsSetHotResidency:  return "FloatTabs：设为 Hot 驻留"
        case .floatTabsSetWarmResidency: return "FloatTabs：设为 Warm 驻留"
        case .floatTabsSetColdResidency: return "FloatTabs：设为 Cold 驻留"
        case .floatTabsToggleVisibility: return "FloatTabs：显示 / 隐藏"
        case .floatTabsToggleFocus:      return "FloatTabs：切换对话框 / 网页焦点"
        case .floatTabsSettings:         return "FloatTabs：打开设置"
        case .floatTabsToggleAlwaysOnTop: return "FloatTabs：开启 / 关闭置顶"
        case .chatGPTOpenCommandMenu:       return "Codex：命令菜单（Command-Shift-P）"
        case .chatGPTOpenSettings:          return "Codex：设置（Command-逗号）"
        case .chatGPTOpenKeyboardShortcuts: return "Codex：键盘快捷键（Command-/）"
        case .chatGPTOpenFolder:            return "Codex：打开文件夹（Command-O）"
        case .chatGPTNavigateBack:          return "Codex：返回（Command-[）"
        case .chatGPTNavigateForward:       return "Codex：前进（Command-]）"
        case .chatGPTIncreaseFontSize:      return "Codex：增大字体（Command-加号）"
        case .chatGPTDecreaseFontSize:      return "Codex：减小字体（Command-减号）"
        case .chatGPTResetFontSize:         return "Codex：重置字体（Command-0）"
        case .chatGPTToggleSidebar:         return "Codex：显示 / 隐藏侧边栏（Command-B）"
        case .chatGPTToggleBottomPanel:     return "Codex：显示 / 隐藏底部面板（Command-J）"
        case .chatGPTOpenTerminal:          return "Codex：打开 / 关闭 Terminal（Control-反引号）"
        case .chatGPTClearTerminal:         return "Codex：清空 Terminal（Control-L）"
        case .chatGPTInterruptTerminal:     return "Codex：中断终端命令（Control-C）"
        case .chatGPTClearUnread:           return "Codex：清除需要注意标记（Shift-Esc）"
        case .chatGPTUndo:                  return "Codex：撤销上次动作（Command-Z）"
        case .chatGPTRedo:                  return "Codex：重做上次动作（Command-Shift-Z）"
        case .chatGPTCloseWindow:           return "Codex：关闭当前标签 / 窗口（Command-W）"
        case .chatGPTToggleFullScreen:      return "Codex：切换全屏（Command-Control-F）"
        case .chatGPTQuit:                  return "Codex：退出程序（Command-Q）"
        case .chatGPTNewChat:               return "Codex：新建对话（Command-N）"
        case .chatGPTNewStandaloneChat:     return "Codex：新建独立对话（Command-Option-O）"
        case .chatGPTQuickChat:             return "Codex：快速对话（Command-Option-N）"
        case .chatGPTNewTemporaryChat:      return "Codex：新建临时对话（Command-Shift-N）"
        case .chatGPTQuickCommandSearch:    return "Codex：快速跳转 / 搜索对话（Command-K）"
        case .chatGPTArchiveChat:           return "Codex：归档当前对话（Command-Shift-A）"
        case .chatGPTMarkChatUnread:        return "Codex：标记当前对话未读（Command-Shift-U）"
        case .chatGPTPinChat:               return "Codex：置顶 / 取消置顶（Command-Option-P）"
        case .chatGPTRenameChat:            return "Codex：重命名当前对话（Command-Option-R）"
        case .chatGPTOpenSideChat:          return "Codex：打开侧边对话（Command-Option-S）"
        case .chatGPTSearchChats:           return "Codex：搜索对话（需在应用中分配快捷键）"
        case .chatGPTFindInChat:            return "Codex：在对话中查找（Command-F）"
        case .chatGPTFindNext:              return "Codex：查找下一个（Command-G）"
        case .chatGPTFindPrevious:          return "Codex：查找上一个（Command-Shift-G）"
        case .chatGPTPreviousChat:          return "Codex：上一个对话 / 标签（Command-Option-左，直接切换）"
        case .chatGPTNextChat:              return "Codex：下一个对话 / 标签（Command-Option-右，直接切换）"
        case .chatGPTNextAttention:         return "Codex：下一个需要注意的对话（Command-Option-A）"
        case .chatGPTScrollToTop:           return "Codex：跳到对话顶部（Command-上方向）"
        case .chatGPTScrollToBottom:        return "Codex：跳到对话底部（Command-下方向）"
        case .chatGPTOpenRecentChat1:       return "Codex：打开最近对话 1（Command-Option-1）"
        case .chatGPTOpenRecentChat2:       return "Codex：打开最近对话 2（Command-Option-2）"
        case .chatGPTOpenRecentChat3:       return "Codex：打开最近对话 3（Command-Option-3）"
        case .chatGPTOpenRecentChat4:       return "Codex：打开最近对话 4（Command-Option-4）"
        case .chatGPTOpenRecentChat5:       return "Codex：打开最近对话 5（Command-Option-5）"
        case .chatGPTOpenRecentChat6:       return "Codex：打开最近对话 6（Command-Option-6）"
        case .chatGPTGoToChat1:             return "Codex：跳转对话 1（Command-1）"
        case .chatGPTGoToChat2:             return "Codex：跳转对话 2（Command-2）"
        case .chatGPTGoToChat3:             return "Codex：跳转对话 3（Command-3）"
        case .chatGPTGoToChat4:             return "Codex：跳转对话 4（Command-4）"
        case .chatGPTGoToChat5:             return "Codex：跳转对话 5（Command-5）"
        case .chatGPTGoToChat6:             return "Codex：跳转对话 6（Command-6）"
        case .chatGPTGoToChat7:             return "Codex：跳转对话 7（Command-7）"
        case .chatGPTGoToChat8:             return "Codex：跳转对话 8（Command-8）"
        case .chatGPTGoToChat9:             return "Codex：跳转对话 9（Command-9）"
        case .chatGPTModelPicker:           return "Codex：模型选择（Control-Shift-M）"
        case .chatGPTProjectPicker:         return "Codex：项目选择（Command-Option-Shift-O）"
        case .chatGPTStartVoiceChat:        return "Codex：开始语音对话（Control-Shift-V）"
        case .chatGPTStartDictation:        return "Codex：开始听写（Control-Shift-D）"
        case .chatGPTFocusConversationInput: return "Codex：聚焦对话输入框（辅助功能点击）"
        case .chatGPTRestorePreviousPrompt: return "Codex：恢复上一次输入（方向上）"
        case .chatGPTInsertNewline:         return "Codex：输入框换行不发送（Shift-Return）"
        case .chatGPTStopGeneration:        return "Codex：停止当前生成（Escape）"
        case .chatGPTPastePlainText:        return "Codex：纯文本粘贴（Command-Shift-V）"
        case .chatGPTApproveRequest:        return "Codex：批准请求（Return）"
        case .chatGPTDeclineRequest:        return "Codex：拒绝请求（Esc）"
        case .chatGPTSwitchToChat:          return "Codex：切换到 Chat（Control-1）"
        case .chatGPTSwitchToWork:          return "Codex：切换到 Work（Control-2）"
        case .chatGPTSwitchToCodex:         return "Codex：切换到 Codex（Control-3）"
        case .chatGPTToggleActivity:        return "Codex：显示 / 隐藏 Activity（Command-Option-U）"
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
        case .chatGPTCopyChatDeepLink:       return "Codex：复制对话链接（Command-Option-L）"
        case .chatGPTCopySessionID:          return "Codex：复制会话 ID（Command-Option-C）"
        case .chatGPTCopyWorkingDirectory:   return "Codex：复制工作目录（Command-Shift-C）"
        case .chatGPTTakeAppshot:            return "Codex：截取 Appshot（双 Command 同时按下）"
        case .ghosttyNewTab:             return "Ghostty：新建标签（Command-T）"
        case .ghosttyNewWindow:          return "Ghostty：新建窗口（Command-N）"
        case .ghosttyPreviousTab:        return "Ghostty：上一个标签（Control-Shift-Tab）"
        case .ghosttyNextTab:            return "Ghostty：下一个标签（Control-Tab）"
        case .ghosttyGoToTab1:           return "Ghostty：切换到标签 1（Command-1）"
        case .ghosttyGoToTab2:           return "Ghostty：切换到标签 2（Command-2）"
        case .ghosttyGoToTab3:           return "Ghostty：切换到标签 3（Command-3）"
        case .ghosttyGoToTab4:           return "Ghostty：切换到标签 4（Command-4）"
        case .ghosttyGoToTab5:           return "Ghostty：切换到标签 5（Command-5）"
        case .ghosttyGoToTab6:           return "Ghostty：切换到标签 6（Command-6）"
        case .ghosttyGoToTab7:           return "Ghostty：切换到标签 7（Command-7）"
        case .ghosttyGoToTab8:           return "Ghostty：切换到标签 8（Command-8）"
        case .ghosttyLastTab:            return "Ghostty：最后一个标签（Command-9）"
        case .ghosttyCloseSurface:       return "Ghostty：关闭当前 surface（Command-W）"
        case .ghosttyCloseTab:           return "Ghostty：关闭当前标签（Command-Option-W）"
        case .ghosttyCloseWindow:        return "Ghostty：关闭当前窗口（Command-Shift-W）"
        case .ghosttyNewSplitRight:      return "Ghostty：向右新建分屏（Command-D）"
        case .ghosttyNewSplitDown:       return "Ghostty：向下新建分屏（Command-Shift-D）"
        case .ghosttyPreviousSplit:      return "Ghostty：上一个分屏（Command-[）"
        case .ghosttyNextSplit:          return "Ghostty：下一个分屏（Command-]）"
        case .ghosttyFocusSplitUp:       return "Ghostty：聚焦上方分屏（Command-Option-上）"
        case .ghosttyFocusSplitDown:     return "Ghostty：聚焦下方分屏（Command-Option-下）"
        case .ghosttyFocusSplitLeft:     return "Ghostty：聚焦左侧分屏（Command-Option-左）"
        case .ghosttyFocusSplitRight:    return "Ghostty：聚焦右侧分屏（Command-Option-右）"
        case .ghosttyToggleSplitZoom:    return "Ghostty：放大 / 还原当前分屏（Command-Shift-Return）"
        case .ghosttyEqualizeSplits:     return "Ghostty：均分所有分屏（Control-Command-=）"
        case .ghosttyPreviousPrompt:     return "Ghostty：跳到上一个提示符（Command-上）"
        case .ghosttyNextPrompt:         return "Ghostty：跳到下一个提示符（Command-下）"
        case .ghosttyClearScreen:        return "Ghostty：清屏（Command-K）"
        case .ghosttyInterrupt:          return "Ghostty：中断当前命令（Control-C）"
        case .ghosttyScrollToTop:        return "Ghostty：滚动到顶部（Command-Home）"
        case .ghosttyScrollToBottom:     return "Ghostty：滚动到底部（Command-End）"
        case .ghosttyScrollToSelection:  return "Ghostty：滚动到选中文本（Command-J）"
        case .ghosttyCommandPalette:     return "Ghostty：命令面板（Command-Shift-P）"
        case .ghosttySearch:             return "Ghostty：搜索（Command-F）"
        case .ghosttyFindNext:           return "Ghostty：查找下一个（Command-G）"
        case .ghosttyFindPrevious:       return "Ghostty：查找上一个（Command-Shift-G）"
        case .ghosttyIncreaseFontSize:   return "Ghostty：增大字号（Command-+）"
        case .ghosttyDecreaseFontSize:   return "Ghostty：减小字号（Command--）"
        case .ghosttyResetFontSize:      return "Ghostty：重置字号（Command-0）"
        case .ghosttyToggleFullScreen:   return "Ghostty：切换全屏（Command-Return）"
        case .ghosttyOpenConfig:         return "Ghostty：打开配置文件（Command-逗号）"
        case .ghosttyReloadConfig:       return "Ghostty：重载配置（Command-Shift-逗号）"
        case .ghosttyToggleInspector:    return "Ghostty：切换检查器（Command-Option-I）"
        case .obsidianCommandPalette:   return "Obsidian：命令面板"
        case .obsidianQuickSwitcher:    return "Obsidian：快速切换文件"
        case .obsidianNewNote:          return "Obsidian：新建笔记"
        case .obsidianNewTab:           return "Obsidian：新建标签"
        case .obsidianReopenClosedTab:  return "Obsidian：恢复最近关闭标签"
        case .obsidianCloseTab:         return "Obsidian：关闭标签"
        case .obsidianSearch:           return "Obsidian：全库搜索"
        case .obsidianToggleEditMode:   return "Obsidian：切换编辑 / 阅读模式"
        case .obsidianAddProperty:      return "Obsidian：添加属性"
        case .obsidianIncreaseFontSize: return "Obsidian：增大字体（Command-加号）"
        case .obsidianDecreaseFontSize: return "Obsidian：减小字体（Command-减号）"
        case .obsidianResetFontSize:    return "Obsidian：重置字体（Command-0）"
        case .obsidianFocusEditor:      return "Obsidian：聚焦编辑器"
        case .obsidianFocusTabGroupLeft:return "Obsidian：聚焦左侧分栏"
        case .obsidianFocusTabGroupRight:return "Obsidian：聚焦右侧分栏"
        case .obsidianFocusTabGroupAbove:return "Obsidian：聚焦上方分栏"
        case .obsidianFocusTabGroupBelow:return "Obsidian：聚焦下方分栏"
        case .obsidianPreviousTab:      return "Obsidian：上一个标签"
        case .obsidianNextTab:          return "Obsidian：下一个标签"
        case .obsidianToggleLeftSidebar:  return "Obsidian：显示 / 隐藏左侧边栏"
        case .obsidianToggleRightSidebar: return "Obsidian：显示 / 隐藏右侧边栏"
        case .obsidianGoToTab1:          return "Obsidian：切换到标签 1"
        case .obsidianGoToTab2:          return "Obsidian：切换到标签 2"
        case .obsidianGoToTab3:          return "Obsidian：切换到标签 3"
        case .obsidianGoToTab4:          return "Obsidian：切换到标签 4"
        case .obsidianGoToTab5:          return "Obsidian：切换到标签 5"
        case .obsidianGoToTab6:          return "Obsidian：切换到标签 6"
        case .obsidianGoToTab7:          return "Obsidian：切换到标签 7"
        case .obsidianGoToTab8:          return "Obsidian：切换到标签 8"
        case .obsidianGoToTab9:          return "Obsidian：最后一个标签"
        case .obsidianNewNoteToRight:   return "Obsidian：向右新建笔记"
        case .obsidianSearchCurrentFile:return "Obsidian：搜索当前文件"
        case .obsidianOpenGraphView:    return "Obsidian：打开关系图谱"
        case .obsidianOpenSettings:     return "Obsidian：打开设置"
        case .obsidianCloseOtherTabs:  return "Obsidian：关闭其他标签"
        case .obsidianSplitRight:      return "Obsidian：向右分屏"
        case .obsidianSplitDown:       return "Obsidian：向下分屏"
        case .obsidianToggleStackedTabs:return "Obsidian：切换堆叠标签"
        case .obsidianShowBacklinks:   return "Obsidian：显示反向链接"
        case .obsidianShowOutgoingLinks:return "Obsidian：显示出链"
        case .obsidianShowTags:        return "Obsidian：显示标签视图"
        case .obsidianShowOutline:     return "Obsidian：显示大纲"
        case .obsidianShowBookmarks:   return "Obsidian：显示书签"
        case .obsidianShowAllProperties:return "Obsidian：显示全部属性"
        case .obsidianShowFileProperties:return "Obsidian：显示文件属性"
        case .obsidianOpenDailyNote:   return "Obsidian：打开今日日记"
        case .obsidianInsertTemplate:  return "Obsidian：插入模板"
        case .obsidianOpenFileExplorer:return "Obsidian：显示文件列表"
        case .obsidianMoveTabToNewWindow:return "Obsidian：移动当前标签到新窗口"
        case .obsidianOpenTabInNewWindow:return "Obsidian：在新窗口打开当前标签"
        case .obsidianCreateNewCanvas:return "Obsidian：新建 Canvas"
        case .neteasePreviousTrack:     return "网易云音乐：上一首"
        case .neteaseNextTrack:         return "网易云音乐：下一首"
        case .browserAddressBar:        return "浏览器：定位地址栏（Command-L）"
        case .browserNewTab:            return "浏览器：新建标签页（Command-T）"
        case .browserNewPrivateWindow:  return "浏览器：新建无痕 / 私密窗口（Command-Shift-N）"
        case .browserCloseTab:          return "浏览器：关闭当前标签（Command-W）"
        case .browserReopenClosedTab:   return "浏览器：恢复刚关闭标签（Command-Shift-T）"
        case .browserPreviousTab:       return "浏览器：上一个标签（Control-Shift-Tab）"
        case .browserNextTab:           return "浏览器：下一个标签（Control-Tab）"
        case .browserGoToTab1:          return "浏览器：直达标签 1（Command-1）"
        case .browserGoToTab2:          return "浏览器：直达标签 2（Command-2）"
        case .browserGoToTab3:          return "浏览器：直达标签 3（Command-3）"
        case .browserGoToTab4:          return "浏览器：直达标签 4（Command-4）"
        case .browserGoToTab5:          return "浏览器：直达标签 5（Command-5）"
        case .browserGoToTab6:          return "浏览器：直达标签 6（Command-6）"
        case .browserGoToTab7:          return "浏览器：直达标签 7（Command-7）"
        case .browserGoToTab8:          return "浏览器：直达标签 8（Command-8）"
        case .browserLastTab:           return "浏览器：最后一个标签（Command-9）"
        case .browserBack:              return "浏览器：后退（Command-[）"
        case .browserForward:           return "浏览器：前进（Command-]）"
        case .browserReload:            return "浏览器：刷新页面（Command-R）"
        case .browserReloadNoCache:     return "浏览器：强制无缓存刷新（Command-Shift-R）"
        case .browserBookmarkPage:      return "浏览器：加入书签（Command-D）"
        case .browserHistory:           return "浏览器：历史记录（Command-Y）"
        case .browserDownloads:         return "浏览器：下载列表（Command-Option-L）"
        case .browserDeveloperTools:    return "浏览器：开发者工具（Command-Option-I）"
        case .browserZoomIn:            return "浏览器：放大页面（Command-+）"
        case .browserZoomOut:           return "浏览器：缩小页面（Command--）"
        case .browserResetZoom:         return "浏览器：实际大小（Command-0）"
        case .iinaPlayPause:            return "IINA：播放 / 暂停（Space）"
        case .iinaSeekBackward:         return "IINA：快退 5 秒（左方向）"
        case .iinaSeekForward:          return "IINA：快进 5 秒（右方向）"
        case .iinaPreviousFrame:        return "IINA：上一帧（,）"
        case .iinaNextFrame:            return "IINA：下一帧（.）"
        case .iinaSpeedDown:            return "IINA：减速播放 0.5x（Command-[）"
        case .iinaSpeedUp:              return "IINA：加速播放 2x（Command-]）"
        case .iinaResetSpeed:           return "IINA：重置 1.0x 倍速（Command-\\）"
        case .iinaVolumeUp:             return "IINA：增大音量（上方向）"
        case .iinaVolumeDown:           return "IINA：减小音量（下方向）"
        case .iinaToggleMute:           return "IINA：静音（Command-/）"
        case .iinaPreviousFile:         return "IINA：上一个文件（Command-左）"
        case .iinaNextFile:             return "IINA：下一个文件（Command-右）"
        case .iinaToggleFullScreen:     return "IINA：切换全屏（Control-Command-F）"
        case .iinaPictureInPicture:     return "IINA：画中画（Control-Command-P）"
        case .iinaToggleOnTop:          return "IINA：窗口置顶（Control-Command-T）"
        case .iinaCycleSubtitles:       return "IINA：切换字幕轨（Control-Command-S）"
        case .iinaCycleAudio:           return "IINA：切换音轨（Control-Command-A）"
        case .iinaShowPlaylist:         return "IINA：显示播放列表（Command-Shift-P）"
        case .iinaScreenshot:           return "IINA：截图（Command-S）"
        case .workspaceCommandPalette:    return "工作区：命令面板（Command-Shift-P）"
        case .workspaceQuickOpen:         return "工作区：快速打开文件（Command-P）"
        case .workspaceGlobalSearch:      return "工作区：全局搜索（Command-Shift-F）"
        case .workspaceFindInFile:        return "工作区：当前页查找（Command-F）"
        case .workspaceNavigateBack:      return "工作区：文件导航后退（Control--）"
        case .workspaceNavigateForward:   return "工作区：文件导航前进（Control-Shift--）"
        case .workspaceToggleSidebar:     return "工作区：显示 / 隐藏侧边栏（Command-B）"
        case .workspaceToggleBottomPanel: return "工作区：显示 / 隐藏底部面板（Command-J）"
        case .workspaceToggleTerminal:    return "工作区：显示 / 隐藏终端（Control-反引号）"
        case .workspaceNewChatOrWindow:   return "工作区：新建对话 / 窗口（Command-N）"
        case .workspaceSplitEditor:       return "工作区：向右分屏（Command-\\）"
        case .workspaceCloseTab:          return "工作区：关闭当前标签（Command-W）"
        case .workspacePreviousTab:       return "工作区：上一个标签（Control-Shift-Tab）"
        case .workspaceNextTab:           return "工作区：下一个标签（Control-Tab）"
        case .workspaceOpenSettings:      return "工作区：打开设置（Command-逗号）"
        case .xcodeRun:                   return "Xcode：运行（Command-R）"
        case .xcodeStop:                  return "Xcode：停止运行（Command-句号）"
        case .xcodeBuild:                 return "Xcode：编译（Command-B）"
        case .xcodeTest:                  return "Xcode：运行测试（Command-U）"
        case .xcodeOpenQuickly:           return "Xcode：快速打开（Command-Shift-O）"
        case .xcodeFindInProject:         return "Xcode：项目内查找（Command-Shift-F）"
        case .xcodeToggleNavigator:       return "Xcode：显示 / 隐藏左侧导航栏（Command-0）"
        case .xcodeToggleDebugArea:       return "Xcode：显示 / 隐藏调试区（Command-Shift-Y）"
        case .xcodeToggleInspector:       return "Xcode：显示 / 隐藏右侧检查器（Command-Option-0）"
        case .xcodeClearConsole:          return "Xcode：清空控制台（Command-K）"
        case .xcodePreviousHistory:       return "Xcode：上一文件历史（Control-Command-左）"
        case .xcodeNextHistory:           return "Xcode：下一文件历史（Control-Command-右）"
        case .xcodeCloseTab:              return "Xcode：关闭当前标签（Command-W）"
        case .t3NewChat:                  return "T3 Code：新建对话（Command-Shift-O）"
        case .t3NewLocalChat:             return "T3 Code：新建本地对话（Command-Shift-N）"
        case .t3NewQuickChat:             return "T3 Code：新建无项目对话（Command-Option-N）"
        case .t3PreviousThread:           return "T3 Code：上一个对话线程（Command-Shift-[）"
        case .t3NextThread:               return "T3 Code：下一个对话线程（Command-Shift-]）"
        case .t3GoToThread1:              return "T3 Code：跳转线程 1（Command-1）"
        case .t3GoToThread2:              return "T3 Code：跳转线程 2（Command-2）"
        case .t3GoToThread3:              return "T3 Code：跳转线程 3（Command-3）"
        case .t3GoToThread4:              return "T3 Code：跳转线程 4（Command-4）"
        case .t3GoToThread5:              return "T3 Code：跳转线程 5（Command-5）"
        case .t3GoToThread6:              return "T3 Code：跳转线程 6（Command-6）"
        case .t3GoToThread7:              return "T3 Code：跳转线程 7（Command-7）"
        case .t3GoToThread8:              return "T3 Code：跳转线程 8（Command-8）"
        case .t3GoToThread9:              return "T3 Code：跳转线程 9（Command-9）"
        case .t3SettleThread:             return "T3 Code：收起 / Settle 当前线程（Command-Shift-S）"
        case .t3PinThread:                return "T3 Code：置顶当前线程（Command-Shift-P）"
        case .t3SendAndNewThread:         return "T3 Code：发送并开启新线程（Command-Option-Return）"
        case .t3SteerQueuedMessage:       return "T3 Code：插队引导运行中回合（Command-Shift-Return）"
        case .t3StashDraft:               return "T3 Code：暂存输入草稿（Command-S）"
        case .t3Dictation:                return "T3 Code：内置语音听写（Command-Shift-D）"
        case .t3CopyThreadRef:            return "T3 Code：复制线程引用链接（Command-Shift-C）"
        case .t3CopyPRNumber:             return "T3 Code：复制关联 PR 编号（Command-Shift-K）"
        case .t3ToggleSidebar:            return "T3 Code：显示 / 隐藏左侧栏（Command-B）"
        case .t3ToggleTerminal:           return "T3 Code：显示 / 隐藏底部终端（Command-J）"
        case .t3ToggleDiff:               return "T3 Code：打开 / 关闭代码 Diff（Command-D）"
        case .t3TogglePreview:            return "T3 Code：打开 / 关闭浏览器预览（Command-Shift-J）"
        case .t3ToggleRightPanel:         return "T3 Code：显示 / 隐藏右侧面板（Command-Option-B）"
        case .t3ToggleThreadPanel:        return "T3 Code：显示 / 隐藏线程面板（Command-Shift-B）"
        case .t3NavigateBack:             return "T3 Code：视图后退（Command-[）"
        case .t3NavigateForward:          return "T3 Code：视图前进（Command-]）"
        case .t3ClosePanel:               return "T3 Code：关闭当前面板 / 终端（Command-W）"
        case .t3ReopenClosed:             return "T3 Code：恢复刚关闭视图（Command-Shift-T）"
        case .t3PreviewRefresh:           return "T3 Code：刷新预览页（Command-R）"
        case .t3CommandPalette:           return "T3 Code：命令面板（Command-K）"
        case .t3FilePicker:               return "T3 Code：快速查找文件（Command-P）"
        case .t3ProjectSearch:            return "T3 Code：全局项目搜索（Command-Shift-F）"
        case .t3FindInChat:               return "T3 Code：对话 / 预览内查找（Command-F）"
        case .t3ModelPicker:              return "T3 Code：切换模型（Command-Shift-M）"
        case .t3SwitchMode:               return "T3 Code：切换 Plan / Default 模式（Command-Shift-A）"
        case .t3SwitchEffort:             return "T3 Code：切换推理强度 Effort（Command-Shift-E）"
        case .t3SwitchWorkspace:          return "T3 Code：切换 Local / Worktree（Command-Shift-X）"
        case .t3SwitchBranch:             return "T3 Code：切换 Git 分支（Command-Shift-G）"
        case .t3OpenInEditor:             return "T3 Code：在外部编辑器打开（Command-O）"
        case .t3OpenUsage:                return "T3 Code：查看用量统计（Command-U）"
        case .t3OpenSettings:             return "T3 Code：打开设置（Command-逗号）"
        case .geminiNewChat:              return "Gemini：发起新对话（Command-N）"
        case .geminiNewTemporaryChat:     return "Gemini：发起新的临时对话（Command-Shift-N）"
        case .geminiSendOrApproveOnce:    return "Gemini：发送消息 / 允许一次权限（Command-Return）"
        case .geminiApproveForThread:     return "Gemini：允许本对话权限（Command-Option-Return）"
        case .geminiApproveAlways:        return "Gemini：始终允许权限（Command-Shift-Return）"
        case .geminiInsertNewline:        return "Gemini：输入换行不发送（Shift-Return）"
        case .geminiStopOrDeny:           return "Gemini：停止回答 / 拒绝权限（Escape）"
        case .geminiSwitchAntigravity:    return "Gemini：切换 Antigravity 模式（Command-Shift-A）"
        case .geminiAreaScreenshot:       return "Gemini：区域截图加入对话（Command-Shift-6）"
        case .geminiReloadChats:          return "Gemini：重新加载对话（Command-R）"
        case .geminiFindInChat:           return "Gemini：在对话中查找（Command-F）"
        case .geminiFindNext:             return "Gemini：查找下一项（Command-G）"
        case .geminiFindPrevious:         return "Gemini：查找上一项（Command-Shift-G）"
        case .geminiIncreaseTextSize:     return "Gemini：将文字调大（Command-+）"
        case .geminiDecreaseTextSize:     return "Gemini：将文字调小（Command--）"
        case .geminiResetTextSize:        return "Gemini：正常文字大小（Command-0）"
        case .geminiCloseWindow:          return "Gemini：关闭窗口（Command-W）"
        case .geminiOpenSettings:         return "Gemini：打开设置（Command-逗号）"
        case .wechatSearch:               return "微信：搜索联系人 / 聊天（Command-F）"
        case .wechatNewGroupChat:         return "微信：发起群聊（Command-N）"
        case .wechatLineBreak:            return "微信：输入换行不发送（Shift-Return）"
        case .wechatScreenshot:           return "微信：截屏（Control-Command-A）"
        case .wechatLock:                 return "微信：锁定微信（Control-Command-L）"
        case .wechatCloseWindow:          return "微信：关闭窗口（Command-W）"
        case .wechatOpenSettings:         return "微信：打开设置（Command-逗号）"
        case .mouseRightClick:  return "鼠标右键（当前位置）"
        case .volumeUp:         return "系统音量 +"
        case .volumeDown:       return "系统音量 -"
        case .volumeMute:       return "系统静音"
        case .playPause:        return "播放 / 暂停"
        case .mediaPreviousTrack: return "上一曲（系统媒体）"
        case .mediaNextTrack:     return "下一曲（系统媒体）"
        }
    }

    /// 通用方向与浏览动作在设置选择器中的二级分组。
    var navigationGroup: NavigationActionGroup? {
        switch self {
        case .spaceKey, .tabKey, .shiftTabKey, .escape, .returnKey:
            return .quickKeys
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight,
             .pageUp, .pageDown, .keyboardPageUp, .keyboardPageDown:
            return .directionalAndScroll
        case .navigateBack, .navigateForward, .reloadPage,
             .newTab, .closeTabOrWindow, .reopenClosedTab,
             .previousTab, .nextTab:
            return .tabsAndPages
        default:
            return nil
        }
    }

    /// 光标与选择动作在设置选择器中的二级分组。
    var selectionGroup: SelectionActionGroup? {
        switch self {
        case .moveToLineStart, .moveToLineEnd,
             .moveToDocumentStart, .moveToDocumentEnd:
            return .cursorJump
        case .extendSelectionLeft, .extendSelectionRight,
             .extendSelectionUp, .extendSelectionDown,
             .extendSelectionToLineStart, .extendSelectionToLineEnd,
             .extendSelectionToDocumentStart, .extendSelectionToDocumentEnd:
            return .extendSelection
        default:
            return nil
        }
    }

    /// Ghostty 动作在设置选择器中的二级分组。
    var ghosttyGroup: GhosttyActionGroup? {
        switch self {
        case .ghosttyNewTab, .ghosttyNewWindow, .ghosttyPreviousTab,
             .ghosttyNextTab, .ghosttyGoToTab1, .ghosttyGoToTab2,
             .ghosttyGoToTab3, .ghosttyGoToTab4, .ghosttyGoToTab5,
             .ghosttyGoToTab6, .ghosttyGoToTab7, .ghosttyGoToTab8,
             .ghosttyLastTab, .ghosttyCloseSurface, .ghosttyCloseTab,
             .ghosttyCloseWindow, .ghosttyToggleFullScreen:
            return .tabsAndWindows
        case .ghosttyNewSplitRight, .ghosttyNewSplitDown,
             .ghosttyPreviousSplit, .ghosttyNextSplit,
             .ghosttyFocusSplitUp, .ghosttyFocusSplitDown,
             .ghosttyFocusSplitLeft, .ghosttyFocusSplitRight,
             .ghosttyToggleSplitZoom, .ghosttyEqualizeSplits:
            return .splitsAndFocus
        case .ghosttyPreviousPrompt, .ghosttyNextPrompt,
             .ghosttyClearScreen, .ghosttyInterrupt,
             .ghosttyScrollToTop, .ghosttyScrollToBottom,
             .ghosttyScrollToSelection:
            return .terminalAndPrompts
        case .ghosttyCommandPalette, .ghosttySearch,
             .ghosttyFindNext, .ghosttyFindPrevious,
             .ghosttyIncreaseFontSize, .ghosttyDecreaseFontSize,
             .ghosttyResetFontSize, .ghosttyOpenConfig,
             .ghosttyReloadConfig, .ghosttyToggleInspector:
            return .searchFontAndConfig
        default:
            return nil
        }
    }

    /// 浏览器动作在设置选择器中的二级分组。
    var browserGroup: BrowserActionGroup? {
        switch self {
        case .browserNewTab, .browserNewPrivateWindow, .browserCloseTab,
             .browserReopenClosedTab, .browserPreviousTab, .browserNextTab,
             .browserGoToTab1, .browserGoToTab2, .browserGoToTab3,
             .browserGoToTab4, .browserGoToTab5, .browserGoToTab6,
             .browserGoToTab7, .browserGoToTab8, .browserLastTab:
            return .tabsAndWindows
        case .browserAddressBar, .browserBack, .browserForward,
             .browserReload, .browserReloadNoCache, .browserBookmarkPage,
             .browserHistory, .browserDownloads, .browserDeveloperTools,
             .browserZoomIn, .browserZoomOut, .browserResetZoom:
            return .navigationAndTools
        default:
            return nil
        }
    }

    /// IINA 动作在设置选择器中的二级分组。
    var iinaGroup: IINAActionGroup? {
        switch self {
        case .iinaPlayPause, .iinaSeekBackward, .iinaSeekForward,
             .iinaPreviousFrame, .iinaNextFrame, .iinaSpeedDown,
             .iinaSpeedUp, .iinaResetSpeed, .iinaVolumeUp,
             .iinaVolumeDown, .iinaToggleMute:
            return .playbackAndSeek
        case .iinaPreviousFile, .iinaNextFile, .iinaToggleFullScreen,
             .iinaPictureInPicture, .iinaToggleOnTop, .iinaCycleSubtitles,
             .iinaCycleAudio, .iinaShowPlaylist, .iinaScreenshot:
            return .playlistAndWindow
        default:
            return nil
        }
    }

    /// 工作区 IDE 动作在设置选择器中的二级分组。
    var codeWorkspaceGroup: CodeWorkspaceActionGroup? {
        switch self {
        case .workspaceCommandPalette, .workspaceQuickOpen, .workspaceGlobalSearch,
             .workspaceFindInFile, .workspaceNavigateBack, .workspaceNavigateForward:
            return .commandsAndFiles
        case .workspaceToggleSidebar, .workspaceToggleBottomPanel,
             .workspaceToggleTerminal, .workspaceNewChatOrWindow,
             .workspaceSplitEditor, .workspaceCloseTab,
             .workspacePreviousTab, .workspaceNextTab,
             .workspaceOpenSettings:
            return .layoutAndTabs
        default:
            return nil
        }
    }

    /// Obsidian 动作在设置选择器中的二级分组。顶层仍统一归入
    /// ``ButtonActionCategory.obsidian``，因此不会污染其他 App 的动作列表。
    var obsidianGroup: ObsidianActionGroup? {
        switch self {
        case .obsidianFocusEditor, .obsidianFocusTabGroupLeft,
             .obsidianFocusTabGroupRight, .obsidianFocusTabGroupAbove,
             .obsidianFocusTabGroupBelow:
            return .cliWorkspace
        case .obsidianToggleLeftSidebar,
             .obsidianToggleRightSidebar, .obsidianOpenFileExplorer,
             .obsidianSplitRight, .obsidianSplitDown,
             .obsidianToggleStackedTabs:
            return .focusAndLayout
        case .obsidianPreviousTab, .obsidianNextTab,
             .obsidianGoToTab1, .obsidianGoToTab2, .obsidianGoToTab3,
             .obsidianGoToTab4, .obsidianGoToTab5, .obsidianGoToTab6,
             .obsidianGoToTab7, .obsidianGoToTab8, .obsidianGoToTab9,
             .obsidianNewTab, .obsidianReopenClosedTab, .obsidianCloseTab,
             .obsidianCloseOtherTabs, .obsidianMoveTabToNewWindow,
             .obsidianOpenTabInNewWindow:
            return .tabsAndWindows
        case .obsidianNewNote, .obsidianNewNoteToRight,
             .obsidianToggleEditMode, .obsidianAddProperty,
             .obsidianIncreaseFontSize, .obsidianDecreaseFontSize,
             .obsidianResetFontSize,
             .obsidianOpenDailyNote, .obsidianInsertTemplate,
             .obsidianCreateNewCanvas:
            return .notesAndEditing
        case .obsidianCommandPalette, .obsidianQuickSwitcher,
             .obsidianSearch, .obsidianSearchCurrentFile:
            return .searchAndCommands
        case .obsidianOpenGraphView, .obsidianShowBacklinks,
             .obsidianShowOutgoingLinks, .obsidianShowTags,
             .obsidianShowOutline, .obsidianShowBookmarks,
             .obsidianShowAllProperties, .obsidianShowFileProperties:
            return .viewsAndProperties
        case .obsidianOpenSettings:
            return .settings
        default:
            return nil
        }
    }

    /// T3 Code 动作在设置选择器中的二级分组。
    var t3CodeGroup: T3CodeActionGroup? {
        switch self {
        case .t3NewChat, .t3NewLocalChat, .t3NewQuickChat,
             .t3PreviousThread, .t3NextThread,
             .t3GoToThread1, .t3GoToThread2, .t3GoToThread3,
             .t3GoToThread4, .t3GoToThread5, .t3GoToThread6,
             .t3GoToThread7, .t3GoToThread8, .t3GoToThread9,
             .t3SettleThread, .t3PinThread,
             .t3SendAndNewThread, .t3SteerQueuedMessage,
             .t3StashDraft, .t3Dictation,
             .t3CopyThreadRef, .t3CopyPRNumber:
            return .threadsAndComposer
        case .t3ToggleSidebar, .t3ToggleTerminal,
             .t3ToggleDiff, .t3TogglePreview,
             .t3ToggleRightPanel, .t3ToggleThreadPanel,
             .t3NavigateBack, .t3NavigateForward,
             .t3ClosePanel, .t3ReopenClosed, .t3PreviewRefresh:
            return .panelsAndViews
        case .t3CommandPalette, .t3FilePicker,
             .t3ProjectSearch, .t3FindInChat,
             .t3ModelPicker, .t3SwitchMode,
             .t3SwitchEffort, .t3SwitchWorkspace,
             .t3SwitchBranch, .t3OpenInEditor,
             .t3OpenUsage, .t3OpenSettings:
            return .modelsAndSearch
        default:
            return nil
        }
    }
}

enum ButtonActionCategory: String, CaseIterable, Hashable, Identifiable {
    case navigation
    case editing
    case selection
    case media
    case system
    case applications
    case floatTabs
    case chatGPTGeneral
    case chatGPTChats
    case chatGPTInputModes
    case chatGPTWorkspaceBrowser
    case t3Code
    case gemini
    case ghostty
    case obsidian
    case netease
    case browser
    case iina
    case codeWorkspace
    case xcode
    case wechat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .navigation:              return "导航、滚动与通用标签"
        case .editing:                 return "复制、编辑与查找"
        case .selection:               return "光标与文本选择"
        case .media:                   return "媒体与音量控制"
        case .system:                  return "系统与窗口控制"
        case .applications:            return "程序快速启动"
        case .floatTabs:               return "FloatTabs"
        case .chatGPTGeneral:          return "Codex · 通用与终端"
        case .chatGPTChats:            return "Codex · 对话与滚动"
        case .chatGPTInputModes:       return "Codex · 输入与模式"
        case .chatGPTWorkspaceBrowser: return "Codex · 工作区与浏览器"
        case .t3Code:                  return "T3 Code"
        case .gemini:                  return "Gemini"
        case .ghostty:                 return "Ghostty"
        case .obsidian:                return "Obsidian"
        case .netease:                 return "网易云音乐"
        case .browser:                 return "浏览器专属"
        case .iina:                    return "IINA 播放器"
        case .codeWorkspace:           return "IDE / 工作区"
        case .xcode:                   return "Xcode"
        case .wechat:                  return "微信"
        }
    }

    static let codexCategories: Set<ButtonActionCategory> = [
        .chatGPTGeneral,
        .chatGPTChats,
        .chatGPTInputModes,
        .chatGPTWorkspaceBrowser,
    ]
}

enum NavigationActionGroup: String, CaseIterable, Hashable, Identifiable {
    case quickKeys
    case directionalAndScroll
    case tabsAndPages

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quickKeys:            return "常用单键与焦点"
        case .directionalAndScroll: return "方向、滚屏与翻页"
        case .tabsAndPages:         return "通用标签与浏览"
        }
    }
}

enum SelectionActionGroup: String, CaseIterable, Hashable, Identifiable {
    case cursorJump
    case extendSelection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursorJump:      return "光标跳转"
        case .extendSelection: return "扩展选择"
        }
    }
}

enum GhosttyActionGroup: String, CaseIterable, Hashable, Identifiable {
    case tabsAndWindows
    case splitsAndFocus
    case terminalAndPrompts
    case searchFontAndConfig

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tabsAndWindows:      return "Ghostty · 标签与窗口"
        case .splitsAndFocus:      return "Ghostty · 分屏与焦点"
        case .terminalAndPrompts:  return "Ghostty · 终端与提示符"
        case .searchFontAndConfig: return "Ghostty · 搜索、字号与配置"
        }
    }
}

enum BrowserActionGroup: String, CaseIterable, Hashable, Identifiable {
    case tabsAndWindows
    case navigationAndTools

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tabsAndWindows:     return "浏览器 · 标签与窗口"
        case .navigationAndTools: return "浏览器 · 地址、导航与工具"
        }
    }
}

enum IINAActionGroup: String, CaseIterable, Hashable, Identifiable {
    case playbackAndSeek
    case playlistAndWindow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .playbackAndSeek:   return "IINA · 播放、进度与倍速"
        case .playlistAndWindow: return "IINA · 文件、字幕与窗口"
        }
    }
}

enum CodeWorkspaceActionGroup: String, CaseIterable, Hashable, Identifiable {
    case commandsAndFiles
    case layoutAndTabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandsAndFiles: return "工作区 · 命令、文件与搜索"
        case .layoutAndTabs:    return "工作区 · 布局、终端与标签"
        }
    }
}

enum T3CodeActionGroup: String, CaseIterable, Hashable, Identifiable {
    case threadsAndComposer
    case panelsAndViews
    case modelsAndSearch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .threadsAndComposer: return "T3 Code · 对话、线程与输入"
        case .panelsAndViews:     return "T3 Code · 面板、Diff 与预览"
        case .modelsAndSearch:    return "T3 Code · 模型、模式与检索"
        }
    }
}

/// Obsidian 专属动作的二级分类。它只影响设置页的展示，不改变动作的
/// 顶层 App 作用域判断。
enum ObsidianActionGroup: String, CaseIterable, Hashable, Identifiable {
    case cliWorkspace
    case focusAndLayout
    case tabsAndWindows
    case notesAndEditing
    case searchAndCommands
    case viewsAndProperties
    case settings

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cliWorkspace:         return "Obsidian · CLI 文档与分栏"
        case .focusAndLayout:      return "Obsidian · 焦点与布局"
        case .tabsAndWindows:      return "Obsidian · 标签与窗口"
        case .notesAndEditing:     return "Obsidian · 笔记与编辑"
        case .searchAndCommands:   return "Obsidian · 搜索与命令"
        case .viewsAndProperties:  return "Obsidian · 视图与属性"
        case .settings:            return "Obsidian · 设置"
        }
    }
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

/// Optional gesture slots layered on top of a button's existing single-click
/// binding. The base binding remains the single-click action; these slots are
/// only consulted when the user enables the advanced gesture switch.
enum ButtonGestureSlot: String, Codable, CaseIterable, Identifiable {
    case doubleTap
    case longPress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .doubleTap: return "双击"
        case .longPress: return "长按"
        }
    }
}

/// A behavior that may independently inherit the global mapping while an App
/// template is active. Long press is one slot because its execution mode
/// (once or repeat) is mutually exclusive.
enum GlobalMappingSlot: String, Codable, CaseIterable, Identifiable {
    case single
    case doubleTap
    case longPress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .single: return "单击"
        case .doubleTap: return "双击"
        case .longPress: return "长按"
        }
    }
}

struct GlobalMappingKey: Codable, Hashable {
    let button: RemoteButton
    let slot: GlobalMappingSlot

    init(button: RemoteButton, slot: GlobalMappingSlot) {
        self.button = button
        self.slot = slot
    }
}

/// The long-press slot can either fire once or become a controlled repeat
/// stream. Keeping this mutually exclusive prevents a long press from
/// triggering two different actions at the same threshold.
enum ButtonLongPressBehavior: String, Codable, CaseIterable, Identifiable {
    case none
    case triggerOnce
    case repeatWhileHeld

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无"
        case .triggerOnce: return "长按触发一次"
        case .repeatWhileHeld: return "按住重复"
        }
    }
}

/// Extra gestures for one physical button. This is deliberately separate from
/// `ButtonBinding` so old configurations remain byte-for-byte compatible and
/// an unchecked button follows the existing edge/repeat path exactly.
struct ButtonGestureProfile: Codable, Equatable {
    /// These flags are independent so a button can expose only double-click,
    /// only long press, or both. `isEnabled` remains as a compatibility
    /// facade for older callers and stored v3 profiles.
    var doubleTapEnabled: Bool
    var longPressEnabled: Bool
    var doubleTap: ButtonBinding?
    var longPress: ButtonBinding?
    var longPressBehavior: ButtonLongPressBehavior

    init(
        isEnabled: Bool = false,
        doubleTap: ButtonBinding? = nil,
        longPress: ButtonBinding? = nil,
        longPressBehavior: ButtonLongPressBehavior = .none,
        doubleTapEnabled: Bool? = nil,
        longPressEnabled: Bool? = nil
    ) {
        self.doubleTap = doubleTap
        self.longPress = longPress
        self.longPressBehavior = longPressBehavior
        self.doubleTapEnabled = doubleTapEnabled
            ?? (isEnabled && doubleTap?.isUsableGestureAction == true)
        self.longPressEnabled = longPressEnabled
            ?? (isEnabled && longPress?.isUsableGestureAction == true
                && longPressBehavior != .none)
    }

    static let disabled = ButtonGestureProfile()

    /// Compatibility facade for code and configurations written before each
    /// gesture had its own enable switch.
    var isEnabled: Bool {
        get { doubleTapEnabled || longPressEnabled }
        set {
            doubleTapEnabled = newValue
            longPressEnabled = newValue
        }
    }

    /// Whether this profile should take the raw edge away from the legacy
    /// immediate-send/repeat path.
    var usesAdvancedGestures: Bool {
        let hasDoubleTap = doubleTapEnabled && doubleTap?.isUsableGestureAction == true
        let hasLongPress = longPressEnabled && longPress?.isUsableGestureAction == true
            && longPressBehavior != .none
        return hasDoubleTap || hasLongPress
    }

    func isEnabled(for slot: ButtonGestureSlot) -> Bool {
        switch slot {
        case .doubleTap: return doubleTapEnabled
        case .longPress: return longPressEnabled
        }
    }

    mutating func setEnabled(_ enabled: Bool, for slot: ButtonGestureSlot) {
        switch slot {
        case .doubleTap: doubleTapEnabled = enabled
        case .longPress: longPressEnabled = enabled
        }
    }

    func binding(for slot: ButtonGestureSlot) -> ButtonBinding? {
        switch slot {
        case .doubleTap: return doubleTap
        case .longPress: return longPress
        }
    }

    mutating func setBinding(_ binding: ButtonBinding?, for slot: ButtonGestureSlot) {
        switch slot {
        case .doubleTap: doubleTap = binding
        case .longPress: longPress = binding
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case doubleTapEnabled
        case longPressEnabled
        case doubleTap
        case longPress
        case longPressBehavior
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let decodedDoubleTap = try container.decodeIfPresent(
            ButtonBinding.self,
            forKey: .doubleTap
        )
        let decodedLongPress = try container.decodeIfPresent(
            ButtonBinding.self,
            forKey: .longPress
        )
        let decodedBehavior = try container.decodeIfPresent(
            ButtonLongPressBehavior.self,
            forKey: .longPressBehavior
        ) ?? .none

        doubleTap = decodedDoubleTap
        longPress = decodedLongPress
        longPressBehavior = decodedBehavior
        doubleTapEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .doubleTapEnabled
        ) ?? (legacyEnabled && decodedDoubleTap?.isUsableGestureAction == true)
        longPressEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .longPressEnabled
        ) ?? (legacyEnabled && decodedLongPress?.isUsableGestureAction == true
            && decodedBehavior != .none)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(doubleTapEnabled, forKey: .doubleTapEnabled)
        try container.encode(longPressEnabled, forKey: .longPressEnabled)
        try container.encodeIfPresent(doubleTap, forKey: .doubleTap)
        try container.encodeIfPresent(longPress, forKey: .longPress)
        try container.encode(longPressBehavior, forKey: .longPressBehavior)
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
            let rawAction = try container.decode(String.self, forKey: .action)
            if let action = ButtonAction(rawValue: rawAction) {
                self = .preset(action)
            } else if rawAction == "codexCopyLatestResponse" {
                // This experimental action was removed because Codex does not
                // expose its reply-level Copy control through Accessibility.
                // Keep old v3 configurations loadable and disable only this
                // stale binding instead of discarding every user mapping.
                self = .preset(.disabled)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .action,
                    in: container,
                    debugDescription: "Unknown ButtonAction: \(rawAction)"
                )
            }
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
        case .voiceKeyDefault:     return "语音键默认（长按遥控器语音输入）"
        }
    }

    /// Compact label used by the transient action HUD. Preset actions already
    /// carry their semantic name; shortcut hints in parentheses belong in the
    /// settings picker, not in the small runtime confirmation overlay.
    var hudDisplayName: String {
        switch self {
        case let .preset(action):
            let name = action.displayName
            guard let separator = name.firstIndex(of: "（") else { return name }
            return String(name[..<separator])
        case let .shortcut(chord, _):
            return chord.displayName
        case .voiceKeyDefault:
            return "遥控器语音输入"
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

    /// Voice-default is owned by VoicePressCoordinator and cannot be used as
    /// a generic gesture action. Disabled bindings also mean “no gesture”.
    var isUsableGestureAction: Bool {
        switch self {
        case .preset(.disabled), .voiceKeyDefault:
            return false
        default:
            return true
        }
    }
}

// MARK: - 默认映射表

/// 所有按钮的默认绑定。
enum DefaultBindings {
    static let all: [RemoteButton: ButtonBinding] = [
        // Keep the historical token in the mapping schema. The product surface
        // presents microphone as the retained remote LONG voice behavior.
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
        .volumeUp:    .preset(.volumeUp),
        .volumeDown:  .preset(.volumeDown),
    ]

    /// Codex 桌面端默认模板（Bundle ID: com.openai.codex）。
    /// 预设动作保留语义名称，实际快捷键由RemoteOrbit统一发送；菜单键保留为空，
    /// 方便用户自行录制。物理方向遵循直觉：上键看到上面的内容，
    /// 下键看到下面的内容。
    static let codex: [RemoteButton: ButtonBinding] = [
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
