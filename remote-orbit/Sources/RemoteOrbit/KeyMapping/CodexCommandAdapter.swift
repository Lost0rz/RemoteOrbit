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
    /// cannot participate in the FloatTabs DOM-focus handshake. The voice
    /// path must preserve Codex's current insertion target: Codex may have a
    /// bottom composer and a separate inline edit composer at the same time.
    static func shouldPrepareInputFocus(for targetBundleIdentifier: String?) -> Bool {
        targetBundleIdentifier == bundleIdentifier
    }

    /// Prepares Codex for voice without changing an already active focus.
    /// Codex's current Chromium surface exposes only an AXWebArea, not an
    /// AXTextArea. Clicking a fixed window-relative composer here therefore
    /// steals focus from an inline editor and makes voice input land in the
    /// wrong place. An explicit “focus composer” mapping still uses that
    /// click; the voice gesture itself is fail-open and focus-preserving.
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

        let wasFrontmost = isFrontmost(application)
        if wasFrontmost {
            // If Codex is already frontmost, do not write any AX attributes
            // and do not synthesize a click. This preserves either the bottom
            // composer or an inline edit field selected by the user. The
            // focused role is only diagnostic because Chromium commonly
            // reports AXWebArea.
            let axApplication = AXUIElementCreateApplication(
                application.processIdentifier
            )
            if let focused = attributeElement(
                axApplication,
                kAXFocusedUIElementAttribute as CFString
            ) {
                completion(
                    true,
                    isTextInput(focused) ? "focus-preserved-text-input" : "focus-preserved"
                )
                return
            }

            // AX can briefly return no focused element during a renderer
            // transition. The correct behavior is still to preserve focus,
            // not to click a guessed composer and destroy the user's target.
            completion(true, "focus-preserved-during-transition")
            return
        }

        _ = application.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        )

        // Codex was activated from another app. Complete the handoff with the
        // existing window-relative composer fallback only when AX did not
        // expose a focused element after activation. The frontmost path above
        // never reaches this click, so inline editing remains untouched.
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

    /// Returns a stable Quartz point inside Codex's main content pane.
    ///
    /// A synthetic scroll event is hit-tested by its global location. Using
    /// the physical mouse position is unreliable when the pointer is over a
    /// toolbar/sidebar, and using NSEvent.mouseLocation directly mixes two
    /// coordinate systems. Window bounds come from Quartz, so this point can
    /// be used directly by CGEvent without changing focus or sending a second
    /// synthetic click.
    static func conversationScrollLocation() -> CGPoint? {
        guard let window = mainWindowBounds(for: bundleIdentifier) else { return nil }

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

    /// Resolves a safe Quartz scroll point inside apps that arrange a left
    /// navigation rail alongside one or more main content/diff/preview panes.
    /// If the physical pointer is already inside the app's right-side content
    /// area, keep it there so the user scrolls whichever sub-pane they are
    /// hovering; otherwise aim at the main content pane.
    static func sidebarAppScrollLocation(
        for bundleIdentifier: String,
        currentPointer: CGPoint
    ) -> CGPoint? {
        guard let window = mainWindowBounds(for: bundleIdentifier) else { return nil }

        let sidebarInset = min(260, window.width * 0.28)
        let contentRect = CGRect(
            x: window.minX + sidebarInset,
            y: window.minY + 52,
            width: max(40, window.width - sidebarInset - 16),
            height: max(40, window.height - 68)
        )
        if contentRect.contains(currentPointer) {
            return currentPointer
        }

        let xFraction: CGFloat = window.width >= 900 ? 0.62 : 0.55
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
        runningApplication(for: bundleIdentifier)
    }

    private static func runningApplication(
        for bundleIdentifier: String
    ) -> NSRunningApplication? {
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
        guard let window = mainWindowBounds(for: bundleIdentifier) else { return nil }
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

    static func mainWindowBounds(for bundleIdentifier: String) -> CGRect? {
        guard let application = runningApplication(for: bundleIdentifier) else { return nil }
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

    private static func isTextInput(_ element: AXUIElement) -> Bool {
        guard let role = attributeValue(element, kAXRoleAttribute as CFString) as? String else {
            return false
        }
        return ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(role)
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
