import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Executes Obsidian core commands.
///
/// Commands that do not have a stable semantic API use the Obsidian command
/// palette. Document-pane focus is different: Obsidian's built-in
/// `editor:focus-left/right` only walks the main editor root and cannot reach
/// a markdown document opened in the right sidebar. Focus actions therefore
/// use Obsidian CLI `eval` to call `workspace.setActiveLeaf` inside Obsidian's
/// own workspace model. This crosses the main/sidebar boundary without
/// synthesizing Accessibility focus or keyboard events.
enum ObsidianCommandAdapter {
    static let bundleIdentifier = "md.obsidian"

    private static let commandQueue = DispatchQueue(
        label: "com.lost0rz.RemoteOrbit.obsidian-command",
        qos: .userInitiated
    )
    private static let scrollStateLock = NSLock()
    private static var rememberedEditorFrame: CGRect?

    @discardableResult
    static func execute(_ action: ButtonAction) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
        else { return false }

        if let focusCommand = focusCommand(for: action) {
            guard let executableURL = cliExecutableURL() else {
                print("[OBSIDIAN] CLI unavailable; focus action not sent: \(focusCommand.label)")
                return false
            }
            commandQueue.async {
                runFocusCLI(executableURL: executableURL, command: focusCommand)
            }
            return true
        }

        guard AXIsProcessTrusted(), let command = commandName(for: action) else {
            return false
        }

        // The palette needs a short turn of the run loop before it accepts
        // text. Keep this off the HID/UI callback queue so semantic commands
        // cannot stall voice capture or the physical button state machine.
        commandQueue.async {
            runPaletteCommand(command)
        }
        return true
    }

    // MARK: - CLI document focus

    private enum FocusCommand {
        case current
        case left
        case right
        case above
        case below

        var label: String {
            switch self {
            case .current: return "current"
            case .left: return "left"
            case .right: return "right"
            case .above: return "above"
            case .below: return "below"
            }
        }
    }

    private static func focusCommand(for action: ButtonAction) -> FocusCommand? {
        switch action {
        case .obsidianFocusEditor: return .current
        case .obsidianFocusTabGroupLeft: return .left
        case .obsidianFocusTabGroupRight: return .right
        case .obsidianFocusTabGroupAbove: return .above
        case .obsidianFocusTabGroupBelow: return .below
        default: return nil
        }
    }

    /// The evaluated code intentionally works with visible markdown leaves,
    /// rather than Obsidian's `getAdjacentLeafInDirection`, because that
    /// built-in helper stays inside the current workspace root and does not
    /// cross from the center editor to the right sidebar.
    private static func focusJavaScript(for command: FocusCommand) -> String {
        let direction: String
        switch command {
        case .current: direction = "current"
        case .left: direction = "left"
        case .right: direction = "right"
        case .above: direction = "above"
        case .below: direction = "below"
        }

        return """
        (()=>{const w=app.workspace,a=w.activeLeaf;if(!a)return "__RO_FOCUS__|no-active";if("\(direction)"==="current"){a.getContainer?.().focus?.();return "__RO_FOCUS__|current"}const f=a.containerEl?.getBoundingClientRect();if(!f)return "__RO_FOCUS__|no-active-rect";const d="\(direction)";const c=w.getLeavesOfType("markdown").map(l=>({l,r:l.containerEl?.getBoundingClientRect()})).filter(x=>x.l!==a&&x.r&&x.r.width>0&&x.r.height>0&&((d==="right"&&x.r.left>=f.right-4)||(d==="left"&&x.r.right<=f.left+4)||(d==="above"&&x.r.bottom<=f.top+4)||(d==="below"&&x.r.top>=f.bottom-4))).sort((x,y)=>{const p=z=>{const q=d==="left"||d==="right"?Math.abs((z.r?.left||0)-f.left):Math.abs((z.r?.top||0)-f.top);const s=d==="left"||d==="right"?Math.abs((z.r?.top||0)-f.top):Math.abs((z.r?.left||0)-f.left);return q+s*.75};return p(x)-p(y)})[0];if(!c)return "__RO_FOCUS__|none";w.setActiveLeaf(c.l,{focus:true});const r=c.r;return "__RO_FOCUS__|ok|"+(c.l.view?.file?.path||"")+"|"+r.left+"|"+r.top+"|"+r.width+"|"+r.height})()
        """
    }

    private static func runFocusCLI(executableURL: URL, command: FocusCommand) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
        else { return }

        let process = Process()
        process.executableURL = executableURL
        let script = focusJavaScript(for: command)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.arguments = [
            "eval",
            "code=\(script)"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                print("[OBSIDIAN] CLI focus failed (\(command.label)): \(output)")
                return
            }

            rememberEditorFrame(from: output)
            print("[OBSIDIAN] CLI focus \(command.label): \(output)")
        } catch {
            print("[OBSIDIAN] CLI focus launch failed (\(command.label)): \(error)")
        }
    }

    private static func cliExecutableURL() -> URL? {
        var candidates = [
            URL(fileURLWithPath: "/usr/local/bin/obsidian"),
            URL(fileURLWithPath: "/opt/homebrew/bin/obsidian"),
            URL(fileURLWithPath: "/Applications/Obsidian.app/Contents/MacOS/obsidian-cli")
        ]
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            candidates.append(appURL.appendingPathComponent("Contents/MacOS/obsidian-cli"))
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The focus action returns the active leaf's viewport rectangle. Convert
    /// it to a global Quartz point for KeyInjector's scroll event. This is a
    /// cache populated by the CLI result, so scrolling never needs a second
    /// Accessibility-tree scan or a retry loop.
    static func activeEditorScrollLocation() -> CGPoint? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier else {
            return nil
        }
        scrollStateLock.lock()
        defer { scrollStateLock.unlock() }
        guard let frame = rememberedEditorFrame else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func rememberEditorFrame(from output: String) {
        let values = output
            .split(separator: "|")
            .suffix(4)
            .compactMap { Double($0) }
        guard values.count == 4,
              let windowFrame = obsidianWindowFrame()
        else { return }

        let viewportFrame = CGRect(
            x: values[0],
            y: values[1],
            width: values[2],
            height: values[3]
        )
        let globalFrame = CGRect(
            x: windowFrame.minX + viewportFrame.minX,
            y: windowFrame.minY + viewportFrame.minY,
            width: viewportFrame.width,
            height: viewportFrame.height
        )
        scrollStateLock.lock()
        rememberedEditorFrame = globalFrame
        scrollStateLock.unlock()
    }

    private static func obsidianWindowFrame() -> CGRect? {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else { return nil }

        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]

        let frames = windowInfo?.compactMap { info -> CGRect? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == application.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let onScreen = info[kCGWindowIsOnscreen as String] as? NSNumber,
                  onScreen.boolValue,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 500,
                  frame.height >= 300 else {
                return nil
            }
            return frame
        } ?? []

        return frames.max(by: { $0.width * $0.height < $1.width * $1.height })
    }

    // MARK: - Obsidian command palette

    private static func commandName(for action: ButtonAction) -> String? {
        switch action {
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

    private static func runPaletteCommand(_ command: String) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier else {
            return
        }
        guard postKey(keyCode: 35, flags: .maskCommand) else { return }
        usleep(140_000)
        guard postText(command) else { return }
        _ = postKey(keyCode: 36, flags: [])
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
            ) else { return }

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
              ) else { return false }

        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: KeyInjector.syntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: KeyInjector.syntheticMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
