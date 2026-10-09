import Foundation

/// Records which device mapping owns the next dual-receiver voice press.
/// This type owns no HID or process operations; RemoteVoiceKeyMapping remains
/// the only device-scoped mapping authority.
struct DualReceiverMappedTriggerState: Equatable {
    enum Phase: Equatable {
        case primaryReady
        case armingSecondary(gestureID: UUID, generation: UInt64)
        case secondaryReady(gestureID: UUID)
        case secondaryActive(gestureID: UUID)
        case restoringPrimary(generation: UInt64)
        case blockedUntilRelease(gestureID: UUID)
        case unavailable(reason: UnavailabilityReason)
    }

    enum UnavailabilityReason: Equatable {
        case dualModeInactive
        case dualModeUnavailable
        case mappingApplyFailed
        case filterConfigurationFailed
        case primaryRestoreFailed
    }

    private(set) var phase: Phase
    private(set) var generation: UInt64 = 0

    init(initialPhase: Phase = .unavailable(reason: .dualModeInactive)) {
        phase = initialPhase
    }

    /// Starts a new A->B transition only while A owns the idle mapping.
    mutating func beginSecondaryArming(gestureID: UUID) -> UInt64? {
        guard phase == .primaryReady else { return nil }
        let next = advanceGeneration()
        phase = .armingSecondary(gestureID: gestureID, generation: next)
        return next
    }

    /// A completion from a superseded arm is ignored.
    @discardableResult
    mutating func completeSecondaryArming(
        gestureID: UUID,
        generation completedGeneration: UInt64
    ) -> Bool {
        guard phase == .armingSecondary(
            gestureID: gestureID,
            generation: completedGeneration
        ) else {
            return false
        }
        phase = .secondaryReady(gestureID: gestureID)
        return true
    }

    /// Admits only the gesture whose B mapping reached ready.
    @discardableResult
    mutating func admitSecondaryPress(gestureID: UUID) -> Bool {
        guard phase == .secondaryReady(gestureID: gestureID) else { return false }
        phase = .secondaryActive(gestureID: gestureID)
        return true
    }

    /// Cancels an in-flight A->B completion when that gesture must be discarded.
    @discardableResult
    mutating func blockPressUntilRelease(gestureID: UUID) -> Bool {
        guard case let .armingSecondary(ownerGestureID, _) = phase,
              ownerGestureID == gestureID else {
            return false
        }
        _ = advanceGeneration()
        phase = .blockedUntilRelease(gestureID: gestureID)
        return true
    }

    mutating func beginPrimaryRestore() -> UInt64 {
        let next = advanceGeneration()
        phase = .restoringPrimary(generation: next)
        return next
    }

    /// A stale restore cannot change current ownership. Failure leaves the
    /// runtime locked until an explicit reconciliation establishes A again.
    @discardableResult
    mutating func completePrimaryRestore(
        generation completedGeneration: UInt64,
        succeeded: Bool
    ) -> Bool {
        guard phase == .restoringPrimary(generation: completedGeneration) else {
            return false
        }
        phase = succeeded
            ? .primaryReady
            : .unavailable(reason: .primaryRestoreFailed)
        return true
    }

    mutating func establishPrimaryReady() {
        _ = advanceGeneration()
        phase = .primaryReady
    }

    mutating func markUnavailable(reason: UnavailabilityReason) {
        _ = advanceGeneration()
        phase = .unavailable(reason: reason)
    }

    @discardableResult
    private mutating func advanceGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }
}
