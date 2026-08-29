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
    /// System Events 生成系统级按键；记录已完成的原子 tap，避免随后
    /// 的遥控器 key-up 再发一个多余的 key-up。
    private static var systemEventsTaps = Set<KeyChord>()

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
        case let .shortcut(chord, _): return send(chord, edge: nil)
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

    // MARK: - 预设动作

    @discardableResult
    static func send(
        _ action: ButtonAction,
        targetApplicationBundleIdentifier: String? = nil,
        scrollLinesPerStep: Int = MappingStore.defaultScrollLinesPerStep
    ) -> Bool {
        guard action != .disabled else { return true }
        if let result = sendExternalAction(action) {
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
            postPageNavigation(
                direction: .up,
                scrollLinesPerStep: scrollLinesPerStep,
                targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
            )
        case .pageDown:
            postPageNavigation(
                direction: .down,
                scrollLinesPerStep: scrollLinesPerStep,
                targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
            )
        case .deleteBackward:
            postKey(code: 51)
        case .showDesktop:
            postKey(code: 103, flags: .maskSecondaryFn)
        case .contextMenu:
            postKey(code: 109, flags: .maskShift)
        case .appSwitcher:
            postKey(code: 48, flags: .maskCommand)
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
        case .floatTabsSettings:
            return sendPresetShortcut(keyCode: 43, keyLabel: ",", modifiers: .command)
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
        case .obsidianCloseTab:
            return sendPresetShortcut(keyCode: 13, keyLabel: "W", modifiers: .command)
        case .obsidianSearch:
            return sendPresetShortcut(
                keyCode: 3,
                keyLabel: "F",
                modifiers: [.command, .shift]
            )
        case .obsidianPreviousTab:
            return sendPresetShortcut(
                keyCode: 48,
                keyLabel: "Tab",
                modifiers: [.control, .shift]
            )
        case .obsidianNextTab:
            return sendPresetShortcut(keyCode: 48, keyLabel: "Tab", modifiers: .control)
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
        if chord.modifiers.contains(.command) || chord.modifiers.contains(.control) {
            switch edge {
            case .down:
                if sendViaSystemEvents(chord) {
                    systemEventsTaps.insert(chord)
                    return true
                }
            case .up:
                if systemEventsTaps.remove(chord) != nil {
                    return true
                }
            case nil:
                if sendViaSystemEvents(chord) {
                    return true
                }
            }
        }

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
        systemEventsTaps.removeAll()
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
    private static func sendExternalAction(_ action: ButtonAction) -> Bool? {
        switch action {
        case .floatTabsNextTab:
            return FloatTabsCommandClient.send(.nextSlot)
        case .floatTabsPreviousTab:
            return FloatTabsCommandClient.send(.previousSlot)
        case .floatTabsToggleVisibility:
            return FloatTabsCommandClient.send(.toggleVisibility)
        case .floatTabsToggleFocus:
            return FloatTabsCommandClient.send(.togglePrimaryFocus)
        case .floatTabsSettings:
            return FloatTabsCommandClient.send(.settings)
        case .openFloatTabs:
            return FloatTabsCommandClient.toggleOrShow()
        case .openCodex:
            return ApplicationLauncher.toggle(bundleIdentifier: "com.openai.codex")
        case .ghosttyNewTab, .ghosttyNewWindow, .ghosttyPreviousTab,
             .ghosttyNextTab, .ghosttyCloseSurface, .ghosttyNewSplitRight,
             .ghosttyNewSplitDown, .ghosttyCommandPalette, .ghosttySearch:
            return GhosttyCommandAdapter.execute(action) ? true : nil
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

    private enum PageNavigationDirection {
        case up
        case down
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
    ) {
        let targetBundleIdentifier = targetApplicationBundleIdentifier
            ?? MappingStore.preferredApplicationBundleIdentifier()
        if targetBundleIdentifier == "com.lost0rz.FloatTabs" {
            let command: FloatTabsDirectCommand = direction == .up ? .scrollUp : .scrollDown
            if FloatTabsCommandClient.send(
                command,
                scrollLines: clampedScrollLinesPerStep(scrollLinesPerStep)
            ) {
                return
            }
        }

        let lines = Int32(clampedScrollLinesPerStep(scrollLinesPerStep))
        postScroll(lines: direction == .up ? lines : -lines)
    }

    /// 发送滚轮事件。普通应用继续使用当前鼠标位置上的标准滚动事件；
    /// FloatTabs 路径由 `postPageNavigation` 改为本地网页滚动命令。
    private static func postScroll(lines: Int32) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                  scrollWheelEvent2Source: source,
                  units: .line,
                  wheelCount: 1,
                  wheel1: lines,
                  wheel2: 0,
                  wheel3: 0
              )
        else { return }
        // A CG scroll event without an explicit location can be ignored by
        // Electron/WebKit when the pointer has not moved recently. Keep the
        // event at the current pointer location so Codex receives it in the
        // same scroll area as a physical mouse wheel.
        event.location = NSEvent.mouseLocation
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cghidEventTap)
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
