enum AudioPipeActivationStep: Equatable {
    case withdrawRealtimeActive
    case clearPriorDrainWaiter
    case resetOutputRing
    case resetPlayoutReserve
    case resetSessionBookkeeping
    case publishRealtimeActive
}

/// Keeps the new-session consumer publication order explicit and executable.
/// The closures run on AudioPipe's producer-side state transition, never from
/// the CoreAudio render callback.
enum AudioPipeRemoteActivationTransition {
    static func perform(
        withdrawRealtimeActive: () -> Void,
        clearPriorDrainWaiter: () -> Void,
        resetOutputRing: () -> Void,
        resetPlayoutReserve: () -> Void,
        resetSessionBookkeeping: () -> Void,
        publishRealtimeActive: () -> Void
    ) {
        withdrawRealtimeActive()
        clearPriorDrainWaiter()
        resetOutputRing()
        resetPlayoutReserve()
        resetSessionBookkeeping()
        publishRealtimeActive()
    }
}
