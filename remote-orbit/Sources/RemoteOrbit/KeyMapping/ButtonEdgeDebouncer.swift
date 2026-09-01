import Foundation

/// Filters a second press edge that follows an accepted single-shot tap too
/// quickly. The raw HID report stream can briefly alternate between a pressed
/// and empty usage set when a button bounces; that must not become two app
/// toggles. Repeatable mappings bypass this state machine entirely.
struct ButtonEdgeDebouncer {
    static let defaultInterval: TimeInterval = 0.18

    private var lastAcceptedReleaseAt: [RemoteButton: TimeInterval] = [:]
    private var suppressedButtons = Set<RemoteButton>()

    mutating func shouldEmit(
        button: RemoteButton,
        isDown: Bool,
        at uptime: TimeInterval,
        debouncing: Bool,
        interval: TimeInterval = Self.defaultInterval
    ) -> Bool {
        guard debouncing else {
            lastAcceptedReleaseAt.removeValue(forKey: button)
            suppressedButtons.remove(button)
            return true
        }

        if isDown {
            guard let lastRelease = lastAcceptedReleaseAt[button],
                  uptime - lastRelease < interval else {
                return true
            }
            suppressedButtons.insert(button)
            return false
        }

        if suppressedButtons.remove(button) != nil {
            return false
        }

        lastAcceptedReleaseAt[button] = uptime
        return true
    }

    mutating func reset() {
        lastAcceptedReleaseAt.removeAll()
        suppressedButtons.removeAll()
    }
}
