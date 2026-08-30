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

    /// Returns a stable Quartz point inside Codex's main content pane.
    ///
    /// A synthetic scroll event is hit-tested by its global location. Using
    /// the physical mouse position is unreliable when the pointer is over a
    /// toolbar/sidebar, and using NSEvent.mouseLocation directly mixes two
    /// coordinate systems. Window bounds come from Quartz, so this point can
    /// be used directly by CGEvent without changing focus or sending a second
    /// synthetic click.
    static func conversationScrollLocation() -> CGPoint? {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else { return nil }

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

        guard let window = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }

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

    @discardableResult
    static func execute(_ action: ButtonAction) -> Bool {
        guard action == .chatGPTSearchChats,
              MappingStore.preferredApplicationBundleIdentifier() == bundleIdentifier,
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
