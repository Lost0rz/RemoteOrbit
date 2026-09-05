// KeyInjector.swift — 合成映射后的按键（单键 + 修饰键 + 系统事件）
//
// Key injection for synthesized shortcuts and system-level actions.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum KeyInjector {
    /// Keep this marker aligned with Key so the event filter recognizes
    /// synthesized events without confusing them with physical key presses.
    static let syntheticMarker: Int64 = 0x56_52_42_52 // "VRBR"

    /// Carbon 全局热键（例如 KeyboardShortcuts 框架）不会响应普通的
    /// CGEvent.post 合成事件。对带 Command 的自定义快捷键，优先让
    /// System Events 生成系统级按键。
    ///
    /// `osascript` 是一个短生命周期进程，但等待它退出可能需要几十到
    /// 数百毫秒。遥控器回调在主线程上运行时，这个等待会表现为“连按
    /// 不生效”或下一次按键要等一下。因此所有原子 System Events tap 都
    /// 进入串行后台队列，既保持顺序，又不阻塞 HID/UI 主线程。
    private static let systemEventsQueue = DispatchQueue(
        label: "com.lost0rz.RemoteOrbit.system-events",
        qos: .userInitiated
    )

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 统一入口

    @discardableResult
    static func send(
        _ binding: ButtonBinding,
        targetApplicationBundleIdentifier: String? = nil,
        scrollLinesPerStep: Int = MappingStore.defaultScrollLinesPerStep
    ) -> Bool {
        // CGEvent/System Events always deliver to the currently active app.
        // When a floating window (FloatTabs) is over the target app, activate
        // the app selected at the button-down edge before injecting the event.
        // This is deliberately done once at the public binding boundary so
        // nested preset shortcuts do not each race to resolve a new target.
        guard prepareTargetApplication(targetApplicationBundleIdentifier) else {
            return false
        }
        switch binding {
        case let .preset(action):
            return send(
                action,
                targetApplicationBundleIdentifier: targetApplicationBundleIdentifier,
                scrollLinesPerStep: scrollLinesPerStep
            )
        case let .shortcut(chord, _):
            // FloatTabs registers its refresh shortcut through its own
            // KeyboardShortcuts controller. A recorded Command-R should keep
            // the same semantic behavior as the built-in Reload action,
            // instead of depending on an injected global key event reaching a
            // menu-bar/floating-window app.
            if targetApplicationBundleIdentifier == FloatTabsCommandClient.bundleIdentifier,
               chord.keyCode == 15,
               chord.modifiers == .command {
                let sent = FloatTabsCommandClient.send(.reload)
                print("[KEY] FloatTabs Command-R → direct reload; sent=\(sent)")
                return sent
            }
            return send(chord, edge: nil)
        case .voiceKeyDefault: return true  // 语音键走 VoicePressCoordinator 流程
        }
    }

    /// 发送绑定的「松开」边沿。
    ///
    /// 当前快捷键绑定由 `send(_:)` 以完整 tap（down + up）发送；
    /// `.repeatWhileHeld` 也是按住期间重复发送完整 tap。因此遥控器松开时
    /// 不应再补发一个 keyUp，否则会产生孤立的 keyUp/修饰键释放事件，干扰
    /// 菜单栏应用和全局快捷键监听器。
    @discardableResult
    static func sendUp(_ binding: ButtonBinding) -> Bool {
        switch binding {
        case .preset:
            return true  // 预设动作是原子操作（down+up），无需额外松开
        case .shortcut:
            return true  // 快捷键已在按下/重复时完成 tap，无需再次释放
        case .voiceKeyDefault:
            return true
        }
    }

    /// Returns true when the action only has an enqueue/dispatch guarantee at
    /// this layer. The HUD must not call that state "已执行" because the
    /// receiving app or System Events process can complete later.
    static func isAsynchronous(
        _ binding: ButtonBinding,
        targetApplicationBundleIdentifier: String? = nil
    ) -> Bool {
        switch binding {
        case let .shortcut(chord, _):
            return chord.modifiers.contains(.command)
                || chord.modifiers.contains(.control)
        case let .preset(action):
            switch action {
            case .openFloatTabs, .openCodex,
                 .floatTabsSelectSlot1, .floatTabsSelectSlot2,
                 .floatTabsSelectSlot3, .floatTabsSelectSlot4,
                 .floatTabsSelectSlot5, .floatTabsSelectSlot6,
                 .floatTabsSelectSlot7, .floatTabsSelectSlot8,
                 .floatTabsSelectSlot9, .floatTabsNextTab,
                 .floatTabsPreviousTab, .floatTabsAddWebApp,
                 .floatTabsZoomIn, .floatTabsZoomOut,
                 .floatTabsResetZoom, .floatTabsAddressBar,
                 .floatTabsReturnHome, .floatTabsToggleVisibility,
                 .floatTabsSettings, .floatTabsToggleAlwaysOnTop,
                 .floatTabsTogglePin, .floatTabsSetHotResidency,
                 .floatTabsSetWarmResidency, .floatTabsSetColdResidency:
                return true
            case .floatTabsToggleFocus:
                return targetApplicationBundleIdentifier
                    != CodexCommandAdapter.bundleIdentifier
            case .pageUp, .pageDown:
                return targetApplicationBundleIdentifier
                    == FloatTabsCommandClient.bundleIdentifier
            case .reloadPage:
                // FloatTabs handles this through its distributed command;
                // every other target falls back to Command-R, which uses the
                // asynchronous System Events path.
                return true
            case .obsidianToggleLeftSidebar, .obsidianToggleRightSidebar,
                 .obsidianFocusEditor, .obsidianFocusTabGroupLeft,
                 .obsidianFocusTabGroupRight, .obsidianFocusTabGroupAbove,
                 .obsidianFocusTabGroupBelow, .obsidianCloseOtherTabs,
                 .obsidianSplitRight, .obsidianSplitDown,
                 .obsidianToggleStackedTabs,
                 .obsidianShowBacklinks, .obsidianShowOutgoingLinks,
                 .obsidianShowTags, .obsidianShowOutline,
                 .obsidianShowBookmarks, .obsidianShowAllProperties,
                 .obsidianShowFileProperties, .obsidianOpenDailyNote,
                 .obsidianInsertTemplate, .obsidianOpenFileExplorer,
                 .obsidianMoveTabToNewWindow, .obsidianOpenTabInNewWindow,
                 .obsidianCreateNewCanvas:
                return true
            default:
                return false
            }
        case .voiceKeyDefault:
            return false
        }
    }

    // MARK: - 预设动作

    @discardableResult
    static func send(
        _ action: ButtonAction,
        targetApplicationBundleIdentifier: String? = nil,
        scrollLinesPerStep: Int = MappingStore.defaultScrollLinesPerStep
    ) -> Bool {
        guard action != .disabled else { return true }
        if let result = sendExternalAction(
            action,
            targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
        ) {
            return result
        }
        guard isAccessibilityTrusted else { return false }

        switch action {
        case .disabled:
            return true
        case .escape:
            postKey(code: 53)
        case .returnKey:
            postKey(code: 36)
        case .arrowUp:
            postKey(code: 126)
        case .arrowDown:
            postKey(code: 125)
        case .arrowLeft:
            postKey(code: 123)
        case .arrowRight:
            postKey(code: 124)
        case .pageUp:
            return postPageNavigation(
                direction: .up,
                scrollLinesPerStep: scrollLinesPerStep,
                targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
            )
        case .pageDown:
            return postPageNavigation(
                direction: .down,
                scrollLinesPerStep: scrollLinesPerStep,
                targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
            )
        case .reloadPage:
            return sendPresetShortcut(keyCode: 15, keyLabel: "R", modifiers: .command)
        case .deleteBackward:
            postKey(code: 51)
        case .showDesktop:
            postKey(code: 103, flags: .maskSecondaryFn)
        case .contextMenu:
            postKey(code: 109, flags: .maskShift)
        case .appSwitcher:
            postKey(code: 48, flags: .maskCommand)
        case .inspectCurrentKeymap:
            return false // handled by AppController's contextual overlay
        case .openFloatTabs:
            return FloatTabsCommandClient.show()
        case .openCodex:
            return ApplicationLauncher.activate(bundleIdentifier: "com.openai.codex")
        case .copy:
            return sendPresetShortcut(keyCode: 8, keyLabel: "C", modifiers: .command)
        case .paste:
            return sendPresetShortcut(keyCode: 9, keyLabel: "V", modifiers: .command)
        case .cut:
            return sendPresetShortcut(keyCode: 7, keyLabel: "X", modifiers: .command)
        case .selectAll:
            return sendPresetShortcut(keyCode: 0, keyLabel: "A", modifiers: .command)
        case .undo:
            return sendPresetShortcut(keyCode: 6, keyLabel: "Z", modifiers: .command)
        case .redo:
            return sendPresetShortcut(
                keyCode: 6,
                keyLabel: "Z",
                modifiers: [.command, .shift]
            )
        case .moveToLineStart:
            return sendPresetShortcut(keyCode: 123, keyLabel: "←", modifiers: .command)
        case .moveToLineEnd:
            return sendPresetShortcut(keyCode: 124, keyLabel: "→", modifiers: .command)
        case .moveToDocumentStart:
            return sendPresetShortcut(keyCode: 126, keyLabel: "↑", modifiers: .command)
        case .moveToDocumentEnd:
            return sendPresetShortcut(keyCode: 125, keyLabel: "↓", modifiers: .command)
        case .extendSelectionLeft:
            return sendPresetShortcut(keyCode: 123, keyLabel: "←", modifiers: .shift)
        case .extendSelectionRight:
            return sendPresetShortcut(keyCode: 124, keyLabel: "→", modifiers: .shift)
        case .extendSelectionUp:
            return sendPresetShortcut(keyCode: 126, keyLabel: "↑", modifiers: .shift)
        case .extendSelectionDown:
            return sendPresetShortcut(keyCode: 125, keyLabel: "↓", modifiers: .shift)
        case .extendSelectionToLineStart:
            return sendPresetShortcut(
                keyCode: 123,
                keyLabel: "←",
                modifiers: [.command, .shift]
            )
        case .extendSelectionToLineEnd:
            return sendPresetShortcut(
                keyCode: 124,
                keyLabel: "→",
                modifiers: [.command, .shift]
            )
        case .extendSelectionToDocumentStart:
            return sendPresetShortcut(
                keyCode: 126,
                keyLabel: "↑",
                modifiers: [.command, .shift]
            )
        case .extendSelectionToDocumentEnd:
            return sendPresetShortcut(
                keyCode: 125,
                keyLabel: "↓",
                modifiers: [.command, .shift]
            )
        case .floatTabsNextTab:
            return sendPresetShortcut(keyCode: 48, keyLabel: "Tab", modifiers: .control)
        case .floatTabsPreviousTab:
            return sendPresetShortcut(
                keyCode: 48,
                keyLabel: "Tab",
                modifiers: [.control, .shift]
            )
        case .floatTabsToggleVisibility:
            return sendPresetShortcut(keyCode: 50, keyLabel: "`", modifiers: .command)
        case .floatTabsToggleFocus:
            return sendPresetShortcut(
                keyCode: 3,
                keyLabel: "F",
                modifiers: [.control, .option]
            )
        case .chatGPTFocusConversationInput:
            return false // handled by the Codex semantic adapter above
        case .floatTabsSettings:
            return sendPresetShortcut(keyCode: 43, keyLabel: ",", modifiers: .command)
        case .floatTabsToggleAlwaysOnTop:
            return false // handled by the FloatTabs semantic adapter above
        case .floatTabsSelectSlot1, .floatTabsSelectSlot2,
             .floatTabsSelectSlot3, .floatTabsSelectSlot4,
             .floatTabsSelectSlot5, .floatTabsSelectSlot6,
             .floatTabsSelectSlot7, .floatTabsSelectSlot8,
             .floatTabsSelectSlot9, .floatTabsAddWebApp,
             .floatTabsZoomIn, .floatTabsZoomOut,
             .floatTabsResetZoom, .floatTabsAddressBar,
             .floatTabsReturnHome, .floatTabsTogglePin,
             .floatTabsSetHotResidency, .floatTabsSetWarmResidency,
             .floatTabsSetColdResidency:
            return false // handled by the FloatTabs semantic adapter above
        case .chatGPTToggleSidebar:
            return sendPresetShortcut(keyCode: 11, keyLabel: "B", modifiers: .command)
        case .chatGPTToggleBottomPanel:
            return sendPresetShortcut(keyCode: 38, keyLabel: "J", modifiers: .command)
        case .chatGPTOpenCommandMenu:
            return sendPresetShortcut(
                keyCode: 35,
                keyLabel: "P",
                modifiers: [.command, .shift]
            )
        case .chatGPTOpenSettings:
            return sendPresetShortcut(keyCode: 43, keyLabel: ",", modifiers: .command)
        case .chatGPTOpenKeyboardShortcuts:
            return sendPresetShortcut(keyCode: 44, keyLabel: "/", modifiers: .command)
        case .chatGPTOpenFolder:
            return sendPresetShortcut(keyCode: 31, keyLabel: "O", modifiers: .command)
        case .chatGPTNavigateBack:
            return sendPresetShortcut(keyCode: 33, keyLabel: "[", modifiers: .command)
        case .chatGPTNavigateForward:
            return sendPresetShortcut(keyCode: 30, keyLabel: "]", modifiers: .command)
        case .chatGPTIncreaseFontSize:
            return sendPresetShortcut(
                keyCode: 24,
                keyLabel: "+",
                modifiers: [.command, .shift]
            )
        case .chatGPTDecreaseFontSize:
            return sendPresetShortcut(keyCode: 27, keyLabel: "-", modifiers: .command)
        case .chatGPTResetFontSize:
            return sendPresetShortcut(keyCode: 29, keyLabel: "0", modifiers: .command)
        case .chatGPTOpenTerminal:
            return sendPresetShortcut(keyCode: 50, keyLabel: "`", modifiers: .control)
        case .chatGPTClearTerminal:
            return sendPresetShortcut(keyCode: 37, keyLabel: "L", modifiers: .control)
        case .chatGPTClearUnread:
            return sendPresetShortcut(keyCode: 53, keyLabel: "Esc", modifiers: .shift)
        case .chatGPTUndo:
            return sendPresetShortcut(keyCode: 6, keyLabel: "Z", modifiers: .command)
        case .chatGPTRedo:
            return sendPresetShortcut(
                keyCode: 6,
                keyLabel: "Z",
                modifiers: [.command, .shift]
            )
        case .chatGPTCloseWindow:
            return sendPresetShortcut(keyCode: 13, keyLabel: "W", modifiers: .command)
        case .chatGPTToggleFullScreen:
            return sendPresetShortcut(
                keyCode: 3,
                keyLabel: "F",
                modifiers: [.command, .control]
            )
        case .chatGPTQuit:
            return sendPresetShortcut(keyCode: 12, keyLabel: "Q", modifiers: .command)
        case .chatGPTNewChat:
            return sendPresetShortcut(keyCode: 45, keyLabel: "N", modifiers: .command)
        case .chatGPTNewStandaloneChat:
            return sendPresetShortcut(
                keyCode: 31,
                keyLabel: "O",
                modifiers: [.command, .option]
            )
        case .chatGPTQuickChat:
            return sendPresetShortcut(
                keyCode: 45,
                keyLabel: "N",
                modifiers: [.command, .option]
            )
        case .chatGPTNewTemporaryChat:
            return sendPresetShortcut(
                keyCode: 45,
                keyLabel: "N",
                modifiers: [.command, .shift]
            )
        case .chatGPTArchiveChat:
            return sendPresetShortcut(
                keyCode: 0,
                keyLabel: "A",
                modifiers: [.command, .shift]
            )
        case .chatGPTMarkChatUnread:
            return sendPresetShortcut(
                keyCode: 32,
                keyLabel: "U",
                modifiers: [.command, .shift]
            )
        case .chatGPTPinChat:
            return sendPresetShortcut(
                keyCode: 35,
                keyLabel: "P",
                modifiers: [.command, .option]
            )
        case .chatGPTRenameChat:
            return sendPresetShortcut(
                keyCode: 15,
                keyLabel: "R",
                modifiers: [.command, .option]
            )
        case .chatGPTOpenSideChat:
            return sendPresetShortcut(
                keyCode: 1,
                keyLabel: "S",
                modifiers: [.command, .option]
            )
        case .chatGPTSearchChats:
            return CodexCommandAdapter.execute(action)
        case .chatGPTFindInChat:
            return sendPresetShortcut(keyCode: 3, keyLabel: "F", modifiers: .command)
        case .chatGPTFindNext:
            return sendPresetShortcut(keyCode: 5, keyLabel: "G", modifiers: .command)
        case .chatGPTFindPrevious:
            return sendPresetShortcut(
                keyCode: 5,
                keyLabel: "G",
                modifiers: [.command, .shift]
            )
        case .chatGPTPreviousChat:
            return sendPresetShortcut(
                keyCode: 123,
                keyLabel: "←",
                modifiers: [.command, .option]
            )
        case .chatGPTNextChat:
            return sendPresetShortcut(
                keyCode: 124,
                keyLabel: "→",
                modifiers: [.command, .option]
            )
        case .chatGPTNextAttention:
            return sendPresetShortcut(
                keyCode: 0,
                keyLabel: "A",
                modifiers: [.command, .option]
            )
        case .chatGPTOpenRecentChat1:
            return sendPresetShortcut(keyCode: 18, keyLabel: "1", modifiers: [.command, .option])
        case .chatGPTOpenRecentChat2:
            return sendPresetShortcut(keyCode: 19, keyLabel: "2", modifiers: [.command, .option])
        case .chatGPTOpenRecentChat3:
            return sendPresetShortcut(keyCode: 20, keyLabel: "3", modifiers: [.command, .option])
        case .chatGPTOpenRecentChat4:
            return sendPresetShortcut(keyCode: 21, keyLabel: "4", modifiers: [.command, .option])
        case .chatGPTOpenRecentChat5:
            return sendPresetShortcut(keyCode: 23, keyLabel: "5", modifiers: [.command, .option])
        case .chatGPTOpenRecentChat6:
            return sendPresetShortcut(keyCode: 22, keyLabel: "6", modifiers: [.command, .option])
        case .chatGPTGoToChat1:
            return sendPresetShortcut(keyCode: 18, keyLabel: "1", modifiers: .command)
        case .chatGPTGoToChat2:
            return sendPresetShortcut(keyCode: 19, keyLabel: "2", modifiers: .command)
        case .chatGPTGoToChat3:
            return sendPresetShortcut(keyCode: 20, keyLabel: "3", modifiers: .command)
        case .chatGPTGoToChat4:
            return sendPresetShortcut(keyCode: 21, keyLabel: "4", modifiers: .command)
        case .chatGPTGoToChat5:
            return sendPresetShortcut(keyCode: 23, keyLabel: "5", modifiers: .command)
        case .chatGPTGoToChat6:
            return sendPresetShortcut(keyCode: 22, keyLabel: "6", modifiers: .command)
        case .chatGPTGoToChat7:
            return sendPresetShortcut(keyCode: 26, keyLabel: "7", modifiers: .command)
        case .chatGPTGoToChat8:
            return sendPresetShortcut(keyCode: 28, keyLabel: "8", modifiers: .command)
        case .chatGPTGoToChat9:
            return sendPresetShortcut(keyCode: 25, keyLabel: "9", modifiers: .command)
        case .chatGPTModelPicker:
            return sendPresetShortcut(
                keyCode: 46,
                keyLabel: "M",
                modifiers: [.control, .shift]
            )
        case .chatGPTProjectPicker:
            return sendPresetShortcut(
                keyCode: 31,
                keyLabel: "O",
                modifiers: [.command, .option, .shift]
            )
        case .chatGPTStartVoiceChat:
            return sendPresetShortcut(
                keyCode: 9,
                keyLabel: "V",
                modifiers: [.control, .shift]
            )
        case .chatGPTStartDictation:
            return sendPresetShortcut(
                keyCode: 2,
                keyLabel: "D",
                modifiers: [.control, .shift]
            )
        case .chatGPTRestorePreviousPrompt:
            postKey(code: 126)
        case .chatGPTApproveRequest:
            postKey(code: 36)
        case .chatGPTDeclineRequest:
            postKey(code: 53)
        case .chatGPTSwitchToChat:
            return sendPresetShortcut(keyCode: 18, keyLabel: "1", modifiers: .control)
        case .chatGPTSwitchToWork:
            return sendPresetShortcut(keyCode: 19, keyLabel: "2", modifiers: .control)
        case .chatGPTSwitchToCodex:
            return sendPresetShortcut(keyCode: 20, keyLabel: "3", modifiers: .control)
        case .chatGPTToggleActivity:
            return sendPresetShortcut(
                keyCode: 32,
                keyLabel: "U",
                modifiers: [.command, .option]
            )
        case .chatGPTRunEnvironmentAction:
            return sendPresetShortcut(
                keyCode: 2,
                keyLabel: "D",
                modifiers: [.command, .shift]
            )
        case .chatGPTSearchFiles:
            return sendPresetShortcut(keyCode: 35, keyLabel: "P", modifiers: .command)
        case .chatGPTToggleFileTree:
            return sendPresetShortcut(
                keyCode: 14,
                keyLabel: "E",
                modifiers: [.command, .shift]
            )
        case .chatGPTOpenReviewTab:
            return sendPresetShortcut(
                keyCode: 5,
                keyLabel: "G",
                modifiers: [.control, .shift]
            )
        case .chatGPTToggleReviewPanel:
            return sendPresetShortcut(
                keyCode: 11,
                keyLabel: "B",
                modifiers: [.command, .option]
            )
        case .chatGPTOpenBrowserTab:
            return sendPresetShortcut(keyCode: 17, keyLabel: "T", modifiers: .command)
        case .chatGPTToggleBrowserPanel:
            return sendPresetShortcut(
                keyCode: 11,
                keyLabel: "B",
                modifiers: [.command, .shift]
            )
        case .chatGPTFocusAddressBar:
            return sendPresetShortcut(keyCode: 37, keyLabel: "L", modifiers: .command)
        case .chatGPTBrowserBack:
            return sendPresetShortcut(keyCode: 123, keyLabel: "←", modifiers: .command)
        case .chatGPTBrowserForward:
            return sendPresetShortcut(keyCode: 124, keyLabel: "→", modifiers: .command)
        case .chatGPTReloadBrowser:
            return sendPresetShortcut(keyCode: 15, keyLabel: "R", modifiers: .command)
        case .chatGPTReloadBrowserNoCache:
            return sendPresetShortcut(
                keyCode: 15,
                keyLabel: "R",
                modifiers: [.command, .shift]
            )
        case .chatGPTCopyBrowserURL:
            return sendPresetShortcut(
                keyCode: 8,
                keyLabel: "C",
                modifiers: [.command, .shift]
            )
        case .chatGPTToggleBrowserMode:
            return sendPresetShortcut(keyCode: 47, keyLabel: ".", modifiers: .command)
        case .chatGPTCopyConversationPath:
            return sendPresetShortcut(
                keyCode: 8,
                keyLabel: "C",
                modifiers: [.command, .option, .shift]
            )
        case .chatGPTCopyChatDeepLink:
            return sendPresetShortcut(
                keyCode: 37,
                keyLabel: "L",
                modifiers: [.command, .option]
            )
        case .chatGPTCopySessionID:
            return sendPresetShortcut(
                keyCode: 8,
                keyLabel: "C",
                modifiers: [.command, .option]
            )
        case .chatGPTCopyWorkingDirectory:
            return sendPresetShortcut(
                keyCode: 8,
                keyLabel: "C",
                modifiers: [.command, .shift]
            )
        case .chatGPTTakeAppshot:
            return sendDoubleCommand()
        case .ghosttyNewTab:
            return sendPresetShortcut(keyCode: 17, keyLabel: "T", modifiers: .command)
        case .ghosttyNewWindow:
            return sendPresetShortcut(keyCode: 45, keyLabel: "N", modifiers: .command)
        case .ghosttyPreviousTab:
            return sendPresetShortcut(
                keyCode: 48,
                keyLabel: "Tab",
                modifiers: [.control, .shift]
            )
        case .ghosttyNextTab:
            return sendPresetShortcut(keyCode: 48, keyLabel: "Tab", modifiers: .control)
        case .ghosttyCloseSurface:
            return sendPresetShortcut(keyCode: 13, keyLabel: "W", modifiers: .command)
        case .ghosttyNewSplitRight:
            return sendPresetShortcut(keyCode: 2, keyLabel: "D", modifiers: .command)
        case .ghosttyNewSplitDown:
            return sendPresetShortcut(
                keyCode: 2,
                keyLabel: "D",
                modifiers: [.command, .shift]
            )
        case .ghosttyCommandPalette:
            return sendPresetShortcut(
                keyCode: 35,
                keyLabel: "P",
                modifiers: [.command, .shift]
            )
        case .ghosttySearch:
            return sendPresetShortcut(keyCode: 3, keyLabel: "F", modifiers: .command)
        case .obsidianCommandPalette:
            return sendPresetShortcut(keyCode: 35, keyLabel: "P", modifiers: .command)
        case .obsidianQuickSwitcher:
            return sendPresetShortcut(keyCode: 31, keyLabel: "O", modifiers: .command)
        case .obsidianNewNote:
            return sendPresetShortcut(keyCode: 45, keyLabel: "N", modifiers: .command)
        case .obsidianNewTab:
            return sendPresetShortcut(keyCode: 17, keyLabel: "T", modifiers: .command)
        case .obsidianReopenClosedTab:
            return sendPresetShortcut(
                keyCode: 17,
                keyLabel: "T",
                modifiers: [.command, .shift]
            )
        case .obsidianCloseTab:
            return sendPresetShortcut(keyCode: 13, keyLabel: "W", modifiers: .command)
        case .obsidianSearch:
            return sendPresetShortcut(
                keyCode: 3,
                keyLabel: "F",
                modifiers: [.command, .shift]
            )
        case .obsidianToggleEditMode:
            return sendPresetShortcut(keyCode: 14, keyLabel: "E", modifiers: .command)
        case .obsidianAddProperty:
            return sendPresetShortcut(keyCode: 41, keyLabel: ";", modifiers: .command)
        case .obsidianIncreaseFontSize:
            return sendPresetShortcut(keyCode: 24, keyLabel: "+", modifiers: [.command, .shift])
        case .obsidianDecreaseFontSize:
            return sendPresetShortcut(keyCode: 27, keyLabel: "-", modifiers: .command)
        case .obsidianResetFontSize:
            return sendPresetShortcut(keyCode: 29, keyLabel: "0", modifiers: .command)
        case .obsidianPreviousTab:
            return sendPresetShortcut(
                keyCode: 48,
                keyLabel: "Tab",
                modifiers: [.control, .shift]
            )
        case .obsidianNextTab:
            return sendPresetShortcut(keyCode: 48, keyLabel: "Tab", modifiers: .control)
        case .obsidianGoToTab1:
            return sendPresetShortcut(keyCode: 18, keyLabel: "1", modifiers: .command)
        case .obsidianGoToTab2:
            return sendPresetShortcut(keyCode: 19, keyLabel: "2", modifiers: .command)
        case .obsidianGoToTab3:
            return sendPresetShortcut(keyCode: 20, keyLabel: "3", modifiers: .command)
        case .obsidianGoToTab4:
            return sendPresetShortcut(keyCode: 21, keyLabel: "4", modifiers: .command)
        case .obsidianGoToTab5:
            return sendPresetShortcut(keyCode: 23, keyLabel: "5", modifiers: .command)
        case .obsidianGoToTab6:
            return sendPresetShortcut(keyCode: 22, keyLabel: "6", modifiers: .command)
        case .obsidianGoToTab7:
            return sendPresetShortcut(keyCode: 26, keyLabel: "7", modifiers: .command)
        case .obsidianGoToTab8:
            return sendPresetShortcut(keyCode: 28, keyLabel: "8", modifiers: .command)
        case .obsidianGoToTab9:
            return sendPresetShortcut(keyCode: 25, keyLabel: "9", modifiers: .command)
        case .obsidianNewNoteToRight:
            return sendPresetShortcut(
                keyCode: 45,
                keyLabel: "N",
                modifiers: [.command, .shift]
            )
        case .obsidianSearchCurrentFile:
            return sendPresetShortcut(keyCode: 3, keyLabel: "F", modifiers: .command)
        case .obsidianOpenGraphView:
            return sendPresetShortcut(keyCode: 5, keyLabel: "G", modifiers: .command)
        case .obsidianOpenSettings:
            return sendPresetShortcut(keyCode: 43, keyLabel: ",", modifiers: .command)
        case .obsidianToggleLeftSidebar, .obsidianToggleRightSidebar,
             .obsidianFocusEditor, .obsidianFocusTabGroupLeft,
             .obsidianFocusTabGroupRight, .obsidianFocusTabGroupAbove,
             .obsidianFocusTabGroupBelow, .obsidianCloseOtherTabs,
             .obsidianSplitRight, .obsidianSplitDown,
             .obsidianToggleStackedTabs,
             .obsidianShowBacklinks, .obsidianShowOutgoingLinks,
             .obsidianShowTags, .obsidianShowOutline,
             .obsidianShowBookmarks, .obsidianShowAllProperties,
             .obsidianShowFileProperties, .obsidianOpenDailyNote,
             .obsidianInsertTemplate, .obsidianOpenFileExplorer,
             .obsidianMoveTabToNewWindow, .obsidianOpenTabInNewWindow,
             .obsidianCreateNewCanvas:
            return false // handled by ObsidianCommandAdapter above
        case .mouseRightClick:
            return postRightClick()
        case .volumeUp:
            postSystemKey(type: 0)
        case .volumeDown:
            postSystemKey(type: 1)
        case .volumeMute:
            postSystemKey(type: 7)
        case .playPause:
            postSystemKey(type: 16)
        case .neteasePreviousTrack:
            postSystemKey(type: 18)
        case .neteaseNextTrack:
            postSystemKey(type: 17)
        }
        return true
    }

    // MARK: - 快捷键（含修饰键组合）

    /// 发送快捷键：支持单边沿（hold 风格）或完整 tap（down+up）。
    ///
    /// 组合快捷键使用完整的物理按键顺序：先发送修饰键的
    /// `flagsChanged` 按下，再发送目标键的 keyDown/keyUp，最后释放修饰键。
    /// 仅把 Command 放进目标键 flags 的写法对普通前台应用通常有效，但部分
    /// 全局快捷键监听器（例如浏览器类菜单栏 App）要求看到真实的修饰键状态
    /// 转换，否则不会触发。
    ///
    /// 单边沿用于遥控器长按：`.down` 建立并保持修饰键，`.up` 先释放目标键再
    /// 释放修饰键。修饰键本身仍使用 `flagsChanged` 事件。
    @discardableResult
    static func send(_ chord: KeyChord, edge: RemoteEventEdge?) -> Bool {
        guard chord.isValid,
              isAccessibilityTrusted
        else { return false }

        // 修饰键使用 flagsChanged 事件而非普通 keyDown/keyUp
        if Self.isModifierKeyCode(chord.keyCode) {
            return sendModifier(chord, edge: edge)
        }

        // KeyboardShortcuts/Carbon 全局热键不会被普通 CGEvent 注入触发。
        // System Events 的 key code 命令会经过 macOS 的系统按键服务，
        // 可同时覆盖 Float Tabs 这类菜单栏应用和 Codex 的 Control+`。
        // 原子 tap 改为后台串行发送，避免在 HID 主线程同步等待
        // /usr/bin/osascript。真正的 down/up 边沿仍使用 CGEvent，保证
        // 需要保持修饰键时有成对的释放事件。
        if chord.modifiers.contains(.command) || chord.modifiers.contains(.control) {
            switch edge {
            case .down, .up:
                break
            case nil:
                enqueueSystemEvents(chord)
                return true
            }
        }

        return sendViaCGEvents(chord, edge: edge)
    }

    /// Sends the non-blocking System Events path and falls back to the normal
    /// CGEvent sequence only if the helper process cannot deliver the tap.
    private static func enqueueSystemEvents(_ chord: KeyChord) {
        systemEventsQueue.async {
            guard !sendViaSystemEvents(chord) else { return }
            _ = sendViaCGEvents(chord, edge: nil)
        }
    }

    /// The direct CGEvent implementation is kept separate from the System
    /// Events decision so the background fallback cannot recurse back into the
    /// asynchronous branch above.
    @discardableResult
    private static func sendViaCGEvents(
        _ chord: KeyChord,
        edge: RemoteEventEdge?
    ) -> Bool {

        guard let source = CGEventSource(stateID: .hidSystemState)
        else { return false }
        let modifierSpecs = modifierSpecs(for: chord.modifiers)
        let combinedFlags = cgFlags(for: chord.modifiers)

        func makeEvent(isDown: Bool) -> CGEvent? {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(chord.keyCode),
                keyDown: isDown
            ) else { return nil }
            event.flags = combinedFlags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            return event
        }

        func postTarget(isDown: Bool) -> Bool {
            guard let event = makeEvent(isDown: isDown) else { return false }
            event.post(tap: .cghidEventTap)
            return true
        }

        switch edge {
        case .down:
            guard postModifiers(modifierSpecs, source: source, isDown: true),
                  postTarget(isDown: true)
            else { return false }
        case .up:
            guard postTarget(isDown: false),
                  postModifiers(modifierSpecs, source: source, isDown: false)
            else { return false }
        case nil:
            guard postModifiers(modifierSpecs, source: source, isDown: true),
                  postTarget(isDown: true),
                  postTarget(isDown: false),
                  postModifiers(modifierSpecs, source: source, isDown: false)
            else { return false }
        }
        return true
    }

    private struct ModifierSpec {
        let keyCode: CGKeyCode
        let flag: CGEventFlags
    }

    /// 通过 macOS System Events 发送原子快捷键。
    /// 这条路径专门兼容 RegisterEventHotKey/KeyboardShortcuts 注册的全局热键。
    private static func sendViaSystemEvents(_ chord: KeyChord) -> Bool {
        var downModifiers: [String] = []
        if chord.modifiers.contains(.command) { downModifiers.append("command") }
        if chord.modifiers.contains(.control) { downModifiers.append("control") }
        if chord.modifiers.contains(.option)  { downModifiers.append("option") }
        if chord.modifiers.contains(.shift)   { downModifiers.append("shift") }

        let modifiers = downModifiers.map { "\($0) down" }
        let usingClause = modifiers.isEmpty ? "{}" : "{\(modifiers.joined(separator: ", "))}"
        let script = "tell application \"System Events\" to key code \(chord.keyCode) using \(usingClause)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[KEY] System Events fallback failed to start: \(error.localizedDescription)")
            return false
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            print("[KEY] System Events fallback failed: \(message)")
            return false
        }
        return true
    }

    /// 进程退出前释放可能由旧版 CGEvent 路径留下的修饰键状态。
    static func releaseAll() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        for keyCode in [55, 59, 58, 56] as [CGKeyCode] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
            ) else { continue }
            event.type = .flagsChanged
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// 使用左侧修饰键建立可被全局快捷键监听器识别的按键序列。
    private static func modifierSpecs(for modifiers: KeyChord.Modifiers) -> [ModifierSpec] {
        var result: [ModifierSpec] = []
        if modifiers.contains(.command) {
            result.append(ModifierSpec(keyCode: 55, flag: .maskCommand))
        }
        if modifiers.contains(.control) {
            result.append(ModifierSpec(keyCode: 59, flag: .maskControl))
        }
        if modifiers.contains(.option) {
            result.append(ModifierSpec(keyCode: 58, flag: .maskAlternate))
        }
        if modifiers.contains(.shift) {
            result.append(ModifierSpec(keyCode: 56, flag: .maskShift))
        }
        return result
    }

    /// 发送修饰键按下/释放的 flagsChanged 序列。
    private static func postModifiers(
        _ specs: [ModifierSpec],
        source: CGEventSource,
        isDown: Bool
    ) -> Bool {
        guard !specs.isEmpty else { return true }

        var activeFlags: CGEventFlags = []
        if isDown {
            for spec in specs {
                activeFlags.insert(spec.flag)
                guard postModifier(spec, source: source, flags: activeFlags, isDown: true)
                else { return false }
            }
        } else {
            activeFlags = specs.reduce(into: CGEventFlags()) { flags, spec in
                flags.insert(spec.flag)
            }
            for spec in specs.reversed() {
                activeFlags.remove(spec.flag)
                guard postModifier(spec, source: source, flags: activeFlags, isDown: false)
                else { return false }
            }
        }
        return true
    }

    private static func postModifier(
        _ spec: ModifierSpec,
        source: CGEventSource,
        flags: CGEventFlags,
        isDown: Bool
    ) -> Bool {
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: spec.keyCode,
            keyDown: isDown
        ) else { return false }
        event.type = .flagsChanged
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cghidEventTap)
        return true
    }

    /// 发送修饰键的 flagsChanged 事件。
    /// 同时发送一个普通 keyDown/keyUp 事件，让输入法等应用也能检测到修饰键按下。
    private static func sendModifier(_ chord: KeyChord, edge: RemoteEventEdge?) -> Bool {
        // 根据 keyCode 确定对应的 CGEventFlags
        let keyFlags: CGEventFlags
        switch chord.keyCode {
        case 54, 55: keyFlags = .maskCommand
        case 59, 62: keyFlags = .maskControl
        case 58, 61: keyFlags = .maskAlternate
        case 56, 60: keyFlags = .maskShift
        case 63:     keyFlags = .maskSecondaryFn
        default:     return false
        }

        // 组合 chord 自带的修饰键 + 该修饰键本身
        var combinedFlags = cgFlags(for: chord.modifiers)
        combinedFlags.insert(keyFlags)

        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        func postModifierEvents(isDown: Bool) {
            // 1) flagsChanged 事件——更新系统修饰键状态
            let type = CGEventType(rawValue: 12)! // flagsChanged
            if let flagsEvent = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(chord.keyCode), keyDown: isDown) {
                flagsEvent.type = type
                flagsEvent.flags = isDown ? combinedFlags : cgFlags(for: chord.modifiers)
                flagsEvent.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                flagsEvent.post(tap: .cghidEventTap)
            }

            // 2) 同时发送普通 keyDown/keyUp 事件——让输入法等应用检测到按键
            if let keyEvent = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(chord.keyCode), keyDown: isDown) {
                keyEvent.flags = isDown ? combinedFlags : cgFlags(for: chord.modifiers)
                keyEvent.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                keyEvent.post(tap: .cgSessionEventTap)
            }
        }

        switch edge {
        case .down:
            postModifierEvents(isDown: true)
        case .up:
            postModifierEvents(isDown: false)
        case nil:
            postModifierEvents(isDown: true)
            postModifierEvents(isDown: false)
        }
        return true
    }

    // MARK: - Private helpers

    /// Make the event destination match the app selected by MappingStore.
    ///
    /// A focused AX element can belong to Codex while a FloatTabs panel is
    /// still the frontmost floating window. Posting a keyboard event without
    /// correcting that mismatch makes Return/shortcut actions appear to be
    /// ignored by Codex. Activation is best-effort: if the target has exited,
    /// the normal frontmost delivery path remains available.
    @discardableResult
    private static func prepareTargetApplication(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              frontmost != bundleIdentifier,
              let target = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == bundleIdentifier
              })
        else { return true }

        let activated = target.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if activated {
            print("[KEY] activated target app → \(bundleIdentifier)")
        } else {
            print("[KEY] target app activation failed → \(bundleIdentifier)")
        }
        return activated
    }

    /// 先尝试软件直连/Accessibility 适配。返回 nil 表示没有执行成功，
    /// 调用方随后继续走稳定的快捷键回退路径；返回 false 表示目标 App 不可用。
    private static func sendExternalAction(
        _ action: ButtonAction,
        targetApplicationBundleIdentifier: String?
    ) -> Bool? {
        switch action {
        case .floatTabsSelectSlot1:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 1)
        case .floatTabsSelectSlot2:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 2)
        case .floatTabsSelectSlot3:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 3)
        case .floatTabsSelectSlot4:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 4)
        case .floatTabsSelectSlot5:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 5)
        case .floatTabsSelectSlot6:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 6)
        case .floatTabsSelectSlot7:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 7)
        case .floatTabsSelectSlot8:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 8)
        case .floatTabsSelectSlot9:
            return FloatTabsCommandClient.send(.selectSlot, slotIndex: 9)
        case .floatTabsNextTab:
            return FloatTabsCommandClient.send(.nextSlot)
        case .floatTabsPreviousTab:
            return FloatTabsCommandClient.send(.previousSlot)
        case .floatTabsAddWebApp:
            return FloatTabsCommandClient.send(.addWebApp)
        case .floatTabsZoomIn:
            return FloatTabsCommandClient.send(.zoomIn)
        case .floatTabsZoomOut:
            return FloatTabsCommandClient.send(.zoomOut)
        case .floatTabsResetZoom:
            return FloatTabsCommandClient.send(.resetZoom)
        case .floatTabsAddressBar:
            return FloatTabsCommandClient.send(.addressBar)
        case .floatTabsReturnHome:
            return FloatTabsCommandClient.send(.returnHome)
        case .floatTabsToggleVisibility:
            return FloatTabsCommandClient.send(.toggleVisibility)
        case .floatTabsToggleFocus:
            let effectiveTarget = targetApplicationBundleIdentifier
                ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if effectiveTarget == CodexCommandAdapter.bundleIdentifier {
                // Keep older mappings that used the generic focus action
                // functional after Codex stopped exposing its composer as an
                // AXTextArea.
                return CodexCommandAdapter.focusConversationInput()
            }
            return FloatTabsCommandClient.send(.togglePrimaryFocus)
        case .floatTabsSettings:
            return FloatTabsCommandClient.send(.settings)
        case .floatTabsTogglePin, .floatTabsToggleAlwaysOnTop:
            return FloatTabsCommandClient.send(.togglePin)
        case .floatTabsSetHotResidency:
            return FloatTabsCommandClient.send(
                .setResidency,
                residencyPolicy: "hot"
            )
        case .floatTabsSetWarmResidency:
            return FloatTabsCommandClient.send(
                .setResidency,
                residencyPolicy: "warm"
            )
        case .floatTabsSetColdResidency:
            return FloatTabsCommandClient.send(
                .setResidency,
                residencyPolicy: "cold"
            )
        case .openFloatTabs:
            return FloatTabsCommandClient.toggleOrShow()
        case .openCodex:
            return ApplicationLauncher.toggle(bundleIdentifier: "com.openai.codex")
        case .reloadPage:
            guard targetApplicationBundleIdentifier == FloatTabsCommandClient.bundleIdentifier
            else { return nil }
            return FloatTabsCommandClient.send(.reload)
        case .chatGPTFocusConversationInput:
            guard targetApplicationBundleIdentifier == CodexCommandAdapter.bundleIdentifier
                    || (targetApplicationBundleIdentifier == nil
                        && NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                            == CodexCommandAdapter.bundleIdentifier)
            else { return false }
            return CodexCommandAdapter.focusConversationInput()
        case .ghosttyNewTab, .ghosttyNewWindow, .ghosttyPreviousTab,
             .ghosttyNextTab, .ghosttyCloseSurface, .ghosttyNewSplitRight,
             .ghosttyNewSplitDown, .ghosttyCommandPalette, .ghosttySearch:
            return GhosttyCommandAdapter.execute(action) ? true : nil
        case .obsidianToggleLeftSidebar, .obsidianToggleRightSidebar,
             .obsidianFocusEditor, .obsidianFocusTabGroupLeft,
             .obsidianFocusTabGroupRight, .obsidianFocusTabGroupAbove,
             .obsidianFocusTabGroupBelow, .obsidianCloseOtherTabs,
             .obsidianSplitRight, .obsidianSplitDown,
             .obsidianToggleStackedTabs,
             .obsidianShowBacklinks, .obsidianShowOutgoingLinks,
             .obsidianShowTags, .obsidianShowOutline,
             .obsidianShowBookmarks, .obsidianShowAllProperties,
             .obsidianShowFileProperties, .obsidianOpenDailyNote,
             .obsidianInsertTemplate, .obsidianOpenFileExplorer,
             .obsidianMoveTabToNewWindow, .obsidianOpenTabInNewWindow,
             .obsidianCreateNewCanvas:
            guard targetApplicationBundleIdentifier == ObsidianCommandAdapter.bundleIdentifier
                    || (targetApplicationBundleIdentifier == nil
                        && NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                            == ObsidianCommandAdapter.bundleIdentifier)
            else { return false }
            return ObsidianCommandAdapter.execute(action)
        default:
            return nil
        }
    }

    private static func sendPresetShortcut(
        keyCode: UInt16,
        keyLabel: String,
        modifiers: KeyChord.Modifiers
    ) -> Bool {
        send(
            KeyChord(keyCode: keyCode, keyLabel: keyLabel, modifiers: modifiers),
            edge: nil
        )
    }

    /// Codex Appshots use the two physical Command keys simultaneously rather
    /// than a normal key plus modifiers. Keep the press/release sequence
    /// balanced so this special preset cannot leave Command logically held.
    private static func sendDoubleCommand() -> Bool {
        guard isAccessibilityTrusted,
              let source = CGEventSource(stateID: .hidSystemState)
        else { return false }

        let leftCommand = CGKeyCode(55)
        let rightCommand = CGKeyCode(54)
        let events: [(CGKeyCode, Bool, CGEventFlags)] = [
            (leftCommand, true, .maskCommand),
            (rightCommand, true, .maskCommand),
            (rightCommand, false, .maskCommand),
            (leftCommand, false, []),
        ]

        for (keyCode, isDown, flags) in events {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: isDown
            ) else { return false }
            event.type = .flagsChanged
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    enum PageNavigationDirection {
        case up
        case down
    }

    /// FloatTabs receives semantic commands and converts its line value into
    /// the native WebKit wheel sign. Its `scrollUp` command therefore needs
    /// the opposite command name from the system/Codex path to produce the
    /// same visible direction.
    static func directFloatTabsScrollCommand(
        for direction: PageNavigationDirection
    ) -> FloatTabsDirectCommand {
        direction == .up ? .scrollDown : .scrollUp
    }

    /// 将滚动送到正确的目标。
    ///
    /// 普通滚轮事件由鼠标位置决定目标窗口。FloatTabs 是跨应用显示的
    /// 独立 WebView，鼠标仍可能停在原来的应用上，所以这里发送本地语义
    /// 命令，让 FloatTabs 直接滚动当前 WebView 的真实滚动容器；其他应用
    /// 继续沿用系统滚轮行为，保持原有映射兼容性。
    private static func postPageNavigation(
        direction: PageNavigationDirection,
        scrollLinesPerStep: Int,
        targetApplicationBundleIdentifier: String? = nil
    ) -> Bool {
        let targetBundleIdentifier = targetApplicationBundleIdentifier
            ?? MappingStore.preferredApplicationBundleIdentifier()
        if targetBundleIdentifier == "com.lost0rz.FloatTabs" {
            let command = directFloatTabsScrollCommand(for: direction)
            if FloatTabsCommandClient.send(
                command,
                scrollLines: clampedScrollLinesPerStep(scrollLinesPerStep)
            ) {
                return true
            }
        }

        let lines = Int32(clampedScrollLinesPerStep(scrollLinesPerStep))
        let signedLines = direction == .up ? lines : -lines
        let location: CGPoint?
        if targetBundleIdentifier == CodexCommandAdapter.bundleIdentifier {
            location = CodexCommandAdapter.conversationScrollLocation()
        } else if targetBundleIdentifier == ObsidianCommandAdapter.bundleIdentifier {
            // Obsidian can keep multiple editable files in the main pane and
            // the right sidebar. Follow the current AX editor focus so a
            // scroll action never falls back to the old mouse location.
            location = ObsidianCommandAdapter.activeEditorScrollLocation()
        } else {
            location = nil
        }
        return postScroll(
            lines: signedLines,
            location: location,
            targetBundleIdentifier: targetBundleIdentifier
        )
    }

    /// 发送滚轮事件。普通应用继续使用当前鼠标位置上的标准滚动事件；
    /// FloatTabs 路径由 `postPageNavigation` 改为本地网页滚动命令。
    @discardableResult
    private static func postScroll(
        lines: Int32,
        location: CGPoint? = nil,
        targetBundleIdentifier: String? = nil
    ) -> Bool {
        let isCodex = targetBundleIdentifier == CodexCommandAdapter.bundleIdentifier

        // Codex is a Chromium surface. Its renderer can ignore a scroll event
        // that still carries the HID source used for ordinary system input.
        // FloatTabs already uses this source-free construction successfully;
        // use the same event shape for Codex, while keeping the HID-source
        // path for ordinary native applications unchanged.
        let event: CGEvent?
        if isCodex {
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: lines,
                wheel2: 0,
                wheel3: 0
            )
        } else {
            guard let source = CGEventSource(stateID: .hidSystemState) else {
                return false
            }
            event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 1,
                wheel1: lines,
                wheel2: 0,
                wheel3: 0
            )
        }
        guard let event else { return false }

        // CGEvent.location uses Quartz's top-left global coordinate system,
        // while NSEvent.mouseLocation is AppKit's bottom-left coordinate
        // system. Passing the latter through unchanged can place the event in
        // Codex's title bar, sidebar, or outside the window altogether. Codex
        // gets a window-derived content point; ordinary apps get the same
        // physical pointer location after the coordinate conversion.
        let resolvedLocation = location ?? quartzMouseLocation()
        event.location = resolvedLocation
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        // Chromium/Codex receives application-session events more reliably
        // than events re-entered at the HID tap. The target app is activated
        // by prepareTargetApplication before this method is reached.
        event.post(tap: isCodex ? .cgSessionEventTap : .cghidEventTap)
        let mode: String
        if isCodex {
            mode = "codex-session"
        } else if location == nil {
            mode = "pointer"
        } else {
            mode = "native-content"
        }
        print(
            "[SCROLL] target=\(targetBundleIdentifier ?? "frontmost") "
                + "mode=\(mode) lines=\(lines) "
                + "point=(\(Int(resolvedLocation.x)),\(Int(resolvedLocation.y)))"
        )
        return true
    }

    /// Convert AppKit's global pointer position into Quartz coordinates.
    /// The display-aware conversion also keeps this correct when a monitor
    /// is arranged above/below the primary display.
    private static func quartzMouseLocation() -> CGPoint {
        let appKitPoint = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) })
                ?? NSScreen.main else {
            return appKitPoint
        }

        let localX = appKitPoint.x - screen.frame.minX
        let localY = appKitPoint.y - screen.frame.minY
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID
        let displayBounds = displayID.map(CGDisplayBounds)

        return CGPoint(
            x: (displayBounds?.minX ?? screen.frame.minX) + localX,
            y: (displayBounds?.minY ?? screen.frame.minY)
                + screen.frame.height
                - localY
        )
    }

    private static func clampedScrollLinesPerStep(_ value: Int) -> Int {
        min(
            max(value, MappingStore.scrollLinesPerStepRange.lowerBound),
            MappingStore.scrollLinesPerStepRange.upperBound
        )
    }

    /// 修饰键 keyCode 集合。
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 59, 62, 58, 61, 56, 60, 63]

    private static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    private static func cgFlags(for modifiers: KeyChord.Modifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option)  { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift)   { flags.insert(.maskShift) }
        return flags
    }

    private static func postKey(code: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 在鼠标当前位置发送右键点击（down + up）。
    private static func postRightClick() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let locationProbe = CGEvent(source: source)
        else { return false }
        let location = locationProbe.location
        guard let down = CGEvent(
                  mouseEventSource: source,
                  mouseType: .rightMouseDown,
                  mouseCursorPosition: location,
                  mouseButton: .right
              ),
              let up = CGEvent(
                  mouseEventSource: source,
                  mouseType: .rightMouseUp,
                  mouseCursorPosition: location,
                  mouseButton: .right
              )
        else { return false }
        down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// 发送系统事件（音量+/-、静音、播放暂停等）。
    private static func postSystemKey(type: Int32) {
        postSystemKey(type: type, isDown: true)
        postSystemKey(type: type, isDown: false)
    }

    private static func postSystemKey(type: Int32, isDown: Bool) {
        let keyState = isDown ? 0xA : 0xB
        let data1 = Int((type << 16) | Int32(keyState << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        guard let cgEvent = event.cgEvent else { return }
        cgEvent.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
