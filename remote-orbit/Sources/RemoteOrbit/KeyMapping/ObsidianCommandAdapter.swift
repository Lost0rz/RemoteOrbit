import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Executes Obsidian core commands through its command palette.
///
/// A number of useful core commands (for example, both sidebar toggles and
/// "Show backlinks") do not have a default hotkey in Obsidian. Going through
/// the command palette keeps these actions semantic and avoids asking users to
/// recreate an arbitrary shortcut in Obsidian. The command names are kept
/// limited to Obsidian core commands and enabled core-plugin commands;
/// community-plugin commands remain discoverable in Obsidian's own palette
/// and are intentionally not hard-coded here.
enum ObsidianCommandAdapter {
    static let bundleIdentifier = "md.obsidian"

    private static let commandQueue = DispatchQueue(
        label: "com.lost0rz.RemoteOrbit.obsidian-command",
        qos: .userInitiated
    )

    @discardableResult
    static func execute(_ action: ButtonAction) -> Bool {
        guard let command = commandName(for: action),
              AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
        else { return false }

        // The palette needs a short turn of the run loop before it accepts
        // text. Keep this off the HID/UI callback queue so a semantic command
        // cannot stall voice capture or the physical button state machine.
        commandQueue.async {
            run(command: command)
        }
        return true
    }

    private static func commandName(for action: ButtonAction) -> String? {
        switch action {
        case .obsidianFocusEditor: return "Focus on editor"
        case .obsidianFocusTabGroupLeft: return "Focus on tab group to the left"
        case .obsidianFocusTabGroupRight: return "Focus on tab group to the right"
        case .obsidianFocusTabGroupAbove: return "Focus on tab group above"
        case .obsidianFocusTabGroupBelow: return "Focus on tab group below"
        case .obsidianToggleLeftSidebar: return "Toggle left sidebar"
        case .obsidianToggleRightSidebar: return "Toggle right sidebar"
        case .obsidianCloseOtherTabs: return "Close all other tabs"
        case .obsidianSplitRight: return "Split right"
        case .obsidianSplitDown: return "Split down"
        case .obsidianToggleStackedTabs: return "Toggle stacked tabs"
        case .obsidianShowBacklinks: return "Show backlinks"
        case .obsidianShowOutgoingLinks: return "Show outgoing links"
        case .obsidianShowTags: return "Show tags"
        case .obsidianShowOutline: return "Show outline"
        case .obsidianShowBookmarks: return "Show bookmarks"
        case .obsidianShowAllProperties: return "Show all properties"
        case .obsidianShowFileProperties: return "Show file properties"
        case .obsidianOpenDailyNote: return "Open today's daily note"
        case .obsidianInsertTemplate: return "Insert template"
        case .obsidianOpenFileExplorer: return "Show file explorer"
        case .obsidianMoveTabToNewWindow: return "Move current tab to new window"
        case .obsidianOpenTabInNewWindow: return "Open current tab in new window"
        case .obsidianCreateNewCanvas: return "Create new canvas"
        default: return nil
        }
    }

    private static func run(command: String) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
        else { return }

        guard postKey(keyCode: 35, flags: .maskCommand) else { return } // Command-P
        usleep(140_000)
        guard postText(command) else { return }
        _ = postKey(keyCode: 36, flags: []) // Return
    }

    private static func postText(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return false }

        var didPost = false
        utf16.withUnsafeBufferPointer { buffer in
            guard let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            ),
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
            )
            else { return }

            down.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            up.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            down.setIntegerValueField(.eventSourceUserData, value: KeyInjector.syntheticMarker)
            up.setIntegerValueField(.eventSourceUserData, value: KeyInjector.syntheticMarker)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            didPost = true
        }
        return didPost
    }

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: true
              ),
              let up = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: false
              )
        else { return false }

        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: KeyInjector.syntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: KeyInjector.syntheticMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
