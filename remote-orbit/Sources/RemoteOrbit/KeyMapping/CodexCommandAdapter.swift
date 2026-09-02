import AppKit
import ApplicationServices
import CoreGraphics

/// Executes Codex actions that do not have a default keyboard shortcut.
///
/// The current official command catalog leaves “Search chats” unassigned by
/// default. When Codex exposes it through its accessibility menu, pressing
/// the menu item keeps this semantic preset independent of a user-selected
/// shortcut. Other Codex actions continue to use their documented defaults.
enum CodexCommandAdapter {
    static let bundleIdentifier = "com.openai.codex"

    /// Codex is a native app rather than FloatTabs' WebKit surface, so it
    /// cannot participate in the FloatTabs DOM-focus handshake. Before the
    /// voice gesture reaches macOS dictation, use Accessibility to make the
    /// best available Codex composer the focused element.
    static func shouldPrepareInputFocus(for targetBundleIdentifier: String?) -> Bool {
        targetBundleIdentifier == bundleIdentifier
    }

    /// Focuses Codex's current text input. Codex's current Chromium surface
    /// exposes only an AXWebArea, not an AXTextArea, so an AX tree walk cannot
    /// verify the composer and only adds latency. Use a direct, window-relative
    /// composer click as the primary path; retain the AX path only as a fast
    /// compatibility fallback for a future Codex build that exposes text roles.
    static func prepareInputFocusForVoice(
        completion: @escaping (Bool, String) -> Void
    ) {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == bundleIdentifier
              }),
              AXIsProcessTrusted()
        else {
            completion(false, "application-or-accessibility-unavailable")
            return
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            != application.processIdentifier {
            _ = application.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
        }

        // A future Codex build may expose a real text role. Check only the
        // currently focused element; never recursively walk the tree here.
        let axApplication = AXUIElementCreateApplication(
            application.processIdentifier
        )
        if let focused = attributeElement(
            axApplication,
            kAXFocusedUIElementAttribute as CFString
        ), isTextInput(focused), focus(focused), isFrontmost(application) {
            completion(true, "already-ready")
            return
        }

        // The common case is Codex already being frontmost. Complete this
        // synchronously so the mapped Option edge is released before the user
        // starts speaking. The previous AX retry loop could overrun the
        // 360-ms safety fence and make its eventual click stale.
        if isFrontmost(application), clickConversationComposer() {
            completion(true, "composer-clicked")
            return
        }

        // If activation was required, allow AppKit a short handoff window,
        // without scanning or blocking on the accessibility tree.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
            guard isFrontmost(application), clickConversationComposer() else {
                completion(false, "composer-unavailable-after-activation")
                return
            }
            completion(true, "composer-clicked-after-activation")
        }
    }

    /// Explicit semantic action for a Codex mapping. Unlike a synthetic Tab,
    /// this directly focuses the composer and therefore works when the AX
    /// tree contains only a Chromium web area.
    @discardableResult
    static func focusConversationInput() -> Bool {
        guard let application = runningApplication(), AXIsProcessTrusted() else {
            return false
        }
        activateIfNeeded(application)
        guard isFrontmost(application), clickConversationComposer() else {
            return false
        }
        print("[CODEX] focus composer → clicked fallback input region")
        return true
    }

    private static func attemptFocus(
        in axApplication: AXUIElement,
        allowShallowSearch: Bool
    ) -> Bool {
        if let focused = attributeElement(
            axApplication,
            kAXFocusedUIElementAttribute as CFString
        ), isTextInput(focused) {
            let alreadyFocused = attributeValue(
                focused,
                kAXFocusedAttribute as CFString
            ) as? Bool ?? false
            if alreadyFocused || focus(focused) {
                return true
            }
        }

        // Codex can expose a very large accessibility tree. A deep scan on
        // every retry previously blocked the first voice edge for almost a
        // second when its custom editor exposed no AX text element. Search a
        // small window subtree once, then fail open promptly.
        guard allowShallowSearch else { return false }

        var roots: [AXUIElement] = []
        if let focusedWindow = attributeElement(
            axApplication,
            kAXFocusedWindowAttribute as CFString
        ) {
            roots.append(focusedWindow)
        }
        if let mainWindow = attributeElement(
            axApplication,
            kAXMainWindowAttribute as CFString
        ), !roots.contains(where: { CFEqual($0, mainWindow) }) {
            roots.append(mainWindow)
        }
        if roots.isEmpty {
            roots = attributeValue(
                axApplication,
                kAXWindowsAttribute as CFString
            ) as? [AXUIElement] ?? []
        }

        guard let candidate = roots
            .compactMap({ bestInput(in: $0, depth: 4) })
            .filter({ $0.score >= 400 })
            .max(by: { $0.score < $1.score })
        else { return false }
        return focus(candidate.element)
    }

    private static func verifyInputFocus(
        in axApplication: AXUIElement,
        application: NSRunningApplication
    ) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == application.processIdentifier,
              let focused = attributeElement(
                  axApplication,
                  kAXFocusedUIElementAttribute as CFString
              ),
              isTextInput(focused),
              let candidate = inputCandidate(for: focused),
              candidate.score >= 400
        else { return false }
        return true
    }

    /// Returns a stable Quartz point inside Codex's main content pane.
    ///
    /// A synthetic scroll event is hit-tested by its global location. Using
    /// the physical mouse position is unreliable when the pointer is over a
    /// toolbar/sidebar, and using NSEvent.mouseLocation directly mixes two
    /// coordinate systems. Window bounds come from Quartz, so this point can
    /// be used directly by CGEvent without changing focus or sending a second
    /// synthetic click.
    static func conversationScrollLocation() -> CGPoint? {
        guard let window = mainWindowBounds() else { return nil }

        // Codex normally reserves the left side for navigation. A point in
        // the right-hand content area remains valid whether the sidebar is
        // expanded or collapsed.
        let xFraction: CGFloat = window.width >= 900 ? 0.70 : 0.55
        let point = CGPoint(
            x: window.minX + window.width * xFraction,
            y: window.minY + window.height * 0.55
        )
        let inset: CGFloat = 20
        return CGPoint(
            x: min(max(point.x, window.minX + inset), window.maxX - inset),
            y: min(max(point.y, window.minY + inset), window.maxY - inset)
        )
    }

    // MARK: - Focus fallback

    private static func runningApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier
        }
    }

    private static func activateIfNeeded(_ application: NSRunningApplication) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            != application.processIdentifier {
            _ = application.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
        }
    }

    private static func isFrontmost(_ application: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
            == application.processIdentifier
    }

    /// The current Codex layout keeps the composer near the bottom of the
    /// main window and the conversation pane on the right. Keep the point
    /// window-relative so this works across displays and window sizes.
    private static func conversationInputLocation() -> CGPoint? {
        guard let window = mainWindowBounds() else { return nil }
        let xFraction: CGFloat = window.width >= 900 ? 0.70 : 0.55
        let point = CGPoint(
            x: window.minX + window.width * xFraction,
            y: window.minY + window.height * 0.88
        )
        let inset: CGFloat = 24
        return CGPoint(
            x: min(max(point.x, window.minX + inset), window.maxX - inset),
            y: min(max(point.y, window.minY + inset), window.maxY - inset)
        )
    }

    private static func clickConversationComposer() -> Bool {
        guard let point = conversationInputLocation(),
              let down = CGEvent(
                  mouseEventSource: nil,
                  mouseType: .leftMouseDown,
                  mouseCursorPosition: point,
                  mouseButton: .left
              ),
              let up = CGEvent(
                  mouseEventSource: nil,
                  mouseType: .leftMouseUp,
                  mouseCursorPosition: point,
                  mouseButton: .left
              ) else { return false }

        down.setIntegerValueField(.eventSourceUserData, value: KeyInjector.syntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: KeyInjector.syntheticMarker)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    private static func mainWindowBounds() -> CGRect? {
        guard let application = runningApplication() else { return nil }
        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]

        let candidates = windowInfo?.compactMap { info -> CGRect? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == application.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let onScreen = info[kCGWindowIsOnscreen as String] as? NSNumber,
                  onScreen.boolValue,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 500,
                  rect.height >= 300 else {
                return nil
            }
            return rect
        } ?? []

        return candidates.max(by: { $0.width * $0.height < $1.width * $1.height })
    }

    @discardableResult
    static func execute(_ action: ButtonAction) -> Bool {
        guard action == .chatGPTSearchChats,
              MappingStore.isApplicationActuallyFocused(bundleIdentifier),
              let application = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == bundleIdentifier
              }),
              AXIsProcessTrusted(),
              let menuBar = attributeElement(
                  AXUIElementCreateApplication(application.processIdentifier),
                  kAXMenuBarAttribute as CFString
              ),
              let item = findMenuItem(
                  in: menuBar,
                  titles: ["Search chats", "Search Chats", "搜索对话"],
                  depth: 8
              ),
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        else { return false }
        return true
    }

    private static func attributeElement(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> AXUIElement? {
        guard let value = attributeValue(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private struct InputCandidate {
        let element: AXUIElement
        let role: String
        let score: Int
    }

    private static func isTextInput(_ element: AXUIElement) -> Bool {
        guard let role = attributeValue(element, kAXRoleAttribute as CFString) as? String else {
            return false
        }
        return ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(role)
    }

    private static func focus(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    }

    private static func bestInput(
        in element: AXUIElement,
        depth: Int
    ) -> InputCandidate? {
        var best = inputCandidate(for: element)
        guard depth > 0 else { return best }

        for child in children(of: element) {
            guard let candidate = bestInput(in: child, depth: depth - 1) else { continue }
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }
        return best
    }

    private static func inputCandidate(for element: AXUIElement) -> InputCandidate? {
        guard let role = attributeValue(element, kAXRoleAttribute as CFString) as? String else {
            return nil
        }

        let baseScore: Int
        switch role {
        case "AXTextArea": baseScore = 700
        case "AXTextField": baseScore = 450
        case "AXComboBox": baseScore = 300
        case "AXSearchField": baseScore = 180
        default: return nil
        }

        if let enabled = attributeValue(element, kAXEnabledAttribute as CFString) as? Bool,
           !enabled {
            return nil
        }

        let labels = [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXRoleDescriptionAttribute
        ]
            .compactMap { attributeValue(element, $0 as CFString) as? String }
            .joined(separator: " ")
            .lowercased()

        var score = baseScore
        if labels.range(of: "message|prompt|ask|compose|reply|chat|input", options: .regularExpression) != nil {
            score += 160
        }
        if labels.range(of: "search|find", options: .regularExpression) != nil {
            score -= 220
        }
        if labels.range(of: "sidebar|navigation|subject", options: .regularExpression) != nil {
            score -= 120
        }

        return InputCandidate(element: element, role: role, score: score)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = attributeValue(element, kAXChildrenAttribute as CFString),
              let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func title(of element: AXUIElement) -> String? {
        attributeValue(element, kAXTitleAttribute as CFString) as? String
    }

    private static func attributeValue(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func findMenuItem(
        in element: AXUIElement,
        titles: [String],
        depth: Int
    ) -> AXUIElement? {
        if let currentTitle = title(of: element),
           titles.contains(where: { normalized($0) == normalized(currentTitle) }) {
            return element
        }
        guard depth > 0 else { return nil }
        for child in children(of: element) {
            if let match = findMenuItem(in: child, titles: titles, depth: depth - 1) {
                return match
            }
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
