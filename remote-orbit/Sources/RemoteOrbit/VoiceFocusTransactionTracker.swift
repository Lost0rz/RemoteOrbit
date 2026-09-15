import Foundation

/// Owns the identity of the one voice-focus transaction that may release the
/// synthetic Option lifecycle. The app drives this object from the main thread; keeping
/// the token logic separate makes stale-callback behavior deterministic and
/// directly testable without HID or Accessibility services.
final class VoiceFocusTransactionTracker {
    private(set) var activeGestureID: UUID?

    @discardableResult
    func begin(_ gestureID: UUID) -> UUID? {
        let previous = activeGestureID
        activeGestureID = gestureID
        return previous
    }

    @discardableResult
    func complete(_ gestureID: UUID) -> Bool {
        guard activeGestureID == gestureID else { return false }
        activeGestureID = nil
        return true
    }

    @discardableResult
    func cancel(_ gestureID: UUID) -> Bool {
        complete(gestureID)
    }

    func cancelAll() {
        activeGestureID = nil
    }
}
