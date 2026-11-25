import Darwin

enum AudioPipePlayoutReserveCandidate: Int, CaseIterable, Equatable {
    case zero = 0
    case milliseconds45 = 45
    case milliseconds75 = 75
    case milliseconds100 = 100

    static let outputSampleRate = 48_000
    static let defaultCandidate: AudioPipePlayoutReserveCandidate = .milliseconds45

    var milliseconds: Int { rawValue }

    var frames: Int {
        milliseconds * Self.outputSampleRate / 1_000
    }
}

enum AudioPipePlayoutReserveState: Equatable {
    case waitingForReserve
    case started
}

enum AudioPipePlayoutReserveStartReason: Equatable {
    case threshold
    case tailBypass
}

enum AudioPipePlayoutReserveDecision: Equatable {
    case wait
    case consume
    case tailBypass
}

struct AudioPipePlayoutReserveSnapshot: Equatable {
    let candidate: AudioPipePlayoutReserveCandidate
    let configuredReserveFrames: Int
    let selectedDefaultCandidate: AudioPipePlayoutReserveCandidate
    let state: AudioPipePlayoutReserveState
    let startDepthFrames: Int?
    let waitDurationNanoseconds: UInt64
    let startReason: AudioPipePlayoutReserveStartReason?
}

/// Serializes reserve decisions with producer-side session reset. The render
/// side only attempts one CAS and never waits; reset is the only path allowed
/// to yield while an already-running decision retires.
final class AudioPipePlayoutReserveLifecycleGate: @unchecked Sendable {
    // 0 = idle, 1 = decision in flight, 2 = reset in progress.
    private var state: Int32 = 0

    @discardableResult
    func tryAcquireDecision() -> Bool {
        OSAtomicCompareAndSwap32Barrier(0, 1, &state)
    }

    func releaseDecision() {
        _ = OSAtomicCompareAndSwap32Barrier(1, 0, &state)
    }

    func acquireReset(onFirstWait: (() -> Void)? = nil) {
        var reportedWait = false
        let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        var spins = 0
        while true {
            if OSAtomicCompareAndSwap32Barrier(0, 2, &state) {
                return
            }
            if !reportedWait {
                onFirstWait?()
                reportedWait = true
            }
            let currentState = OSAtomicAdd32Barrier(0, &state)
            if clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- start > 500_000_000,
               OSAtomicCompareAndSwap32Barrier(currentState, 2, &state) {
                return
            }
            spins &+= 1
            if spins < 64 {
                sched_yield()
            } else {
                usleep(50)
            }
        }
    }

    func releaseReset() {
        _ = OSAtomicCompareAndSwap32Barrier(2, 0, &state)
    }

    func isIdle() -> Bool {
        OSAtomicAdd32Barrier(0, &state) == 0
    }
}

/// One fixed startup threshold for one remote stream. The render-facing
/// decision uses only bounded scalar atomics; all evidence is read off-path.
final class AudioPipePlayoutReserve: @unchecked Sendable {
    let candidate: AudioPipePlayoutReserveCandidate

    private let lifecycleGate = AudioPipePlayoutReserveLifecycleGate()

    // 0 = waiting, 1 = metadata publication in progress, 2 = started.
    // AudioPipe has one CoreAudio render-side writer. The intermediate scalar
    // state also keeps an off-path snapshot from exposing partial metadata if
    // another caller is ever added.
    private var state: Int32 = 0
    private var resetTimestampNanoseconds: Int64 = 0
    private var startTimestampNanoseconds: Int64 = 0
    private var startDepthFrames: Int64 = 0
    private var startReason: Int32 = 0

    init(candidate: AudioPipePlayoutReserveCandidate = .defaultCandidate) {
        self.candidate = candidate
    }

    func reset(at timestampNanoseconds: UInt64) {
        reset(
            at: timestampNanoseconds,
            onFirstWait: nil
        )
    }

    func decision(
        remoteActive: Bool,
        queuedFrames: Int,
        now timestampNanoseconds: UInt64
    ) -> AudioPipePlayoutReserveDecision {
        guard lifecycleGate.tryAcquireDecision() else {
            return .wait
        }
        defer { lifecycleGate.releaseDecision() }

        let currentState = atomicLoad32(&state)
        guard currentState == 0 else {
            return currentState == 1 ? .wait : .consume
        }

        if !remoteActive {
            guard queuedFrames > 0 else {
                // An inactive empty ring has no tail to drain. In particular,
                // it must not publish a new session's reserve as STARTED.
                return .consume
            }
            if startOnce(
                reason: .tailBypass,
                depthFrames: queuedFrames,
                timestampNanoseconds: timestampNanoseconds
            ) {
                return .tailBypass
            }
            return .consume
        }

        guard candidate.frames == 0 || queuedFrames >= candidate.frames else {
            return .wait
        }

        _ = startOnce(
            reason: .threshold,
            depthFrames: queuedFrames,
            timestampNanoseconds: timestampNanoseconds
        )
        return .consume
    }

    func snapshot(at timestampNanoseconds: UInt64) -> AudioPipePlayoutReserveSnapshot {
        for attempt in 0..<4_096 {
            guard lifecycleGate.isIdle() else {
                if attempt < 64 {
                    sched_yield()
                } else {
                    usleep(20)
                }
                continue
            }
            let stateBefore = atomicLoad32(&state)
            let reset = UInt64(max(0, atomicLoad64(&resetTimestampNanoseconds)))
            let startedAt = UInt64(max(0, atomicLoad64(&startTimestampNanoseconds)))
            let depth = Int(max(0, atomicLoad64(&startDepthFrames)))
            let reason = Self.reason(rawValue: atomicLoad32(&startReason))
            let stateAfter = atomicLoad32(&state)

            guard stateBefore == stateAfter, lifecycleGate.isIdle() else { continue }

            let started = stateAfter == 2
            let waitEnd = startedAt > 0 ? startedAt : timestampNanoseconds
            return AudioPipePlayoutReserveSnapshot(
                candidate: candidate,
                configuredReserveFrames: candidate.frames,
                selectedDefaultCandidate: .defaultCandidate,
                state: started ? .started : .waitingForReserve,
                startDepthFrames: started ? depth : nil,
                waitDurationNanoseconds: waitEnd >= reset ? waitEnd - reset : 0,
                startReason: started ? reason : nil
            )
        }

        let stateAfter = atomicLoad32(&state)
        let reset = UInt64(max(0, atomicLoad64(&resetTimestampNanoseconds)))
        let startedAt = UInt64(max(0, atomicLoad64(&startTimestampNanoseconds)))
        let depth = Int(max(0, atomicLoad64(&startDepthFrames)))
        let reason = Self.reason(rawValue: atomicLoad32(&startReason))
        let started = stateAfter == 2
        let waitEnd = startedAt > 0 ? startedAt : timestampNanoseconds
        return AudioPipePlayoutReserveSnapshot(
            candidate: candidate,
            configuredReserveFrames: candidate.frames,
            selectedDefaultCandidate: .defaultCandidate,
            state: started ? .started : .waitingForReserve,
            startDepthFrames: started ? depth : nil,
            waitDurationNanoseconds: waitEnd >= reset ? waitEnd - reset : 0,
            startReason: started ? reason : nil
        )
    }

    // Deterministic test seams exercise the same lifecycle gate used by the
    // production decision/reset paths without adding a render-time hook.
    @discardableResult
    func claimDecisionForTesting() -> Bool {
        lifecycleGate.tryAcquireDecision()
    }

    func releaseDecisionForTesting() {
        lifecycleGate.releaseDecision()
    }

    func beginResetForTesting() {
        lifecycleGate.acquireReset()
    }

    func endResetForTesting() {
        lifecycleGate.releaseReset()
    }

    func resetForTesting(
        at timestampNanoseconds: UInt64,
        onFirstWait: @escaping () -> Void
    ) {
        reset(
            at: timestampNanoseconds,
            onFirstWait: onFirstWait
        )
    }

    private func reset(
        at timestampNanoseconds: UInt64,
        onFirstWait: (() -> Void)?
    ) {
        lifecycleGate.acquireReset(onFirstWait: onFirstWait)
        // Withdraw STARTED before clearing its metadata. Because reset owns
        // the lifecycle gate, no stale decision can publish after this point.
        atomicStore32(0, to: &state)
        atomicStore64(safeInt64(timestampNanoseconds), to: &resetTimestampNanoseconds)
        atomicStore64(0, to: &startTimestampNanoseconds)
        atomicStore64(0, to: &startDepthFrames)
        atomicStore32(0, to: &startReason)
        lifecycleGate.releaseReset()
    }

    private func startOnce(
        reason: AudioPipePlayoutReserveStartReason,
        depthFrames: Int,
        timestampNanoseconds: UInt64
    ) -> Bool {
        guard OSAtomicCompareAndSwap32Barrier(0, 1, &state) else {
            return false
        }
        // Publish all start evidence before the externally visible STARTED
        // state. The single render-side writer assumption is covered by the
        // AudioPipeRealtime reserve tests and preserved by this scalar claim.
        atomicStore64(
            safeInt64(timestampNanoseconds),
            to: &startTimestampNanoseconds
        )
        atomicStore64(Int64(max(0, depthFrames)), to: &startDepthFrames)
        atomicStore32(Self.rawValue(for: reason), to: &startReason)
        atomicStore32(2, to: &state)
        return true
    }

    private static func rawValue(for reason: AudioPipePlayoutReserveStartReason) -> Int32 {
        switch reason {
        case .threshold: return 1
        case .tailBypass: return 2
        }
    }

    private static func reason(rawValue: Int32) -> AudioPipePlayoutReserveStartReason? {
        switch rawValue {
        case 1: return .threshold
        case 2: return .tailBypass
        default: return nil
        }
    }
}

struct AudioPipeReserveSimulationMetrics: Equatable {
    let candidate: AudioPipePlayoutReserveCandidate
    let startupLatencyMilliseconds: Int
    let actualStartDepthFrames: Int
    let activeUnderrunCallbacks: Int
    let activeUnderrunFrames: Int
    let tailBypassCount: Int
    let droppedOrStrandedPCM: Int
}

/// Deterministic, bounded evidence for candidate selection. This is test and
/// audit support, not a runtime adaptive-jitter controller.
enum AudioPipeReserveSimulation {
    private static let callbackFrames = 480
    private static let callbackNanoseconds: UInt64 = 10_000_000

    static func shortJitterComparison() -> [AudioPipeReserveSimulationMetrics] {
        let arrivals = [480, 0, 0, 0, 3_600] + Array(repeating: 600, count: 16)
        return AudioPipePlayoutReserveCandidate.allCases.map {
            simulate(candidate: $0, arrivals: arrivals)
        }
    }

    static func sustainedDeficitComparison() -> [AudioPipeReserveSimulationMetrics] {
        let arrivals = [4_800] + Array(repeating: 240, count: 24)
        return AudioPipePlayoutReserveCandidate.allCases.map {
            simulate(candidate: $0, arrivals: arrivals)
        }
    }

    static func selectSmallestUseful(
        from comparison: [AudioPipeReserveSimulationMetrics]
    ) -> AudioPipePlayoutReserveCandidate? {
        guard let control = comparison.first(where: { $0.candidate == .zero }) else {
            return nil
        }
        return comparison
            .filter { $0.candidate != .zero }
            .sorted { $0.candidate.milliseconds < $1.candidate.milliseconds }
            .first {
                $0.activeUnderrunFrames < control.activeUnderrunFrames
                    && $0.tailBypassCount == 0
                    && $0.droppedOrStrandedPCM == 0
            }?
            .candidate
    }

    private static func simulate(
        candidate: AudioPipePlayoutReserveCandidate,
        arrivals: [Int]
    ) -> AudioPipeReserveSimulationMetrics {
        let reserve = AudioPipePlayoutReserve(candidate: candidate)
        reserve.reset(at: 1)
        var queuedFrames = 0
        var startTick: Int?
        var activeUnderrunCallbacks = 0
        var activeUnderrunFrames = 0
        var tailBypassCount = 0

        for (tick, incomingFrames) in arrivals.enumerated() {
            queuedFrames += incomingFrames
            let decision = reserve.decision(
                remoteActive: true,
                queuedFrames: queuedFrames,
                now: UInt64(tick) * callbackNanoseconds + 1
            )
            switch decision {
            case .wait:
                continue
            case .consume, .tailBypass:
                if startTick == nil { startTick = tick }
                if decision == .tailBypass { tailBypassCount += 1 }
            }

            let consumed = min(queuedFrames, callbackFrames)
            if decision == .consume, consumed < callbackFrames {
                activeUnderrunCallbacks += 1
                activeUnderrunFrames += callbackFrames - consumed
            }
            queuedFrames -= consumed
        }

        while queuedFrames > 0 {
            let decision = reserve.decision(
                remoteActive: false,
                queuedFrames: queuedFrames,
                now: UInt64(arrivals.count) * callbackNanoseconds + 1
            )
            if decision == .tailBypass { tailBypassCount += 1 }
            queuedFrames -= min(queuedFrames, callbackFrames)
        }

        let snapshot = reserve.snapshot(
            at: UInt64(arrivals.count) * callbackNanoseconds + 1
        )
        return AudioPipeReserveSimulationMetrics(
            candidate: candidate,
            startupLatencyMilliseconds: (startTick ?? arrivals.count) * 10,
            actualStartDepthFrames: snapshot.startDepthFrames ?? 0,
            activeUnderrunCallbacks: activeUnderrunCallbacks,
            activeUnderrunFrames: activeUnderrunFrames,
            tailBypassCount: tailBypassCount,
            droppedOrStrandedPCM: queuedFrames
        )
    }
}

private func safeInt64(_ value: UInt64) -> Int64 {
    Int64(min(value, UInt64(Int64.max)))
}

private func atomicLoad32(_ value: UnsafeMutablePointer<Int32>) -> Int32 {
    OSAtomicAdd32Barrier(0, value)
}

private func atomicLoad64(_ value: UnsafeMutablePointer<Int64>) -> Int64 {
    OSAtomicAdd64Barrier(0, value)
}

private func atomicStore32(_ newValue: Int32, to value: UnsafeMutablePointer<Int32>) {
    while true {
        let oldValue = atomicLoad32(value)
        if OSAtomicCompareAndSwap32Barrier(oldValue, newValue, value) { return }
    }
}

private func atomicStore64(_ newValue: Int64, to value: UnsafeMutablePointer<Int64>) {
    while true {
        let oldValue = atomicLoad64(value)
        if OSAtomicCompareAndSwap64Barrier(oldValue, newValue, value) { return }
    }
}
