import Foundation

/// Runtime authority for the optional two-receiver gesture path.
/// Configuration that does not request dual mode remains on the legacy path;
/// a requested mode that cannot satisfy raw-input safety stays unavailable.
enum DualReceiverVoiceMode: Equatable {
    enum UnavailabilityReason: Equatable {
        case rawHIDUnavailable
        case eventSuppressorUnavailable
        case mappingClearFailed
        case legacyMappingRestoreFailed
    }

    case legacy
    case unavailable(UnavailabilityReason)
    case active(receiverA: VoiceTriggerKey, receiverB: VoiceTriggerKey)

    static func evaluate(
        shortIsDisabled: Bool,
        receiverA: VoiceTriggerKey,
        receiverB: VoiceTriggerKey?,
        rawHIDReady: Bool,
        eventSuppressorReady: Bool,
        mappingClearSucceeded: Bool
    ) -> DualReceiverVoiceMode {
        guard shortIsDisabled,
              let receiverB,
              receiverA != receiverB else {
            return .legacy
        }
        guard rawHIDReady else { return .unavailable(.rawHIDUnavailable) }
        guard eventSuppressorReady else {
            return .unavailable(.eventSuppressorUnavailable)
        }
        guard mappingClearSucceeded else {
            return .unavailable(.mappingClearFailed)
        }
        return .active(receiverA: receiverA, receiverB: receiverB)
    }

    static func canChangeConfiguration(
        while ownership: DualReceiverVoiceOwnership
    ) -> Bool {
        ownership == .idle
    }
}

/// Voice-path ownership phases that make a receiver/configuration change unsafe.
/// The runtime maps its concrete coordinator/filter/classifier state into these
/// phases before accepting a mode change.
enum DualReceiverVoiceOwnership: CaseIterable, Equatable {
    case idle
    case firstTapPending
    case waitingSecondTap
    case activeTransaction
    case physicalRelease
    case outputDrain
    case runtimeReconfiguration
}

enum DualReceiverVoiceModeUpdateResult: Equatable {
    case applied(DualReceiverVoiceMode)
    case busy
    case unavailable(DualReceiverVoiceMode.UnavailabilityReason)
}
