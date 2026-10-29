import Darwin
import Foundation

/// A two-word, lock-free timestamp pair for the CoreAudio output callback.
/// It records only first/last non-zero remote output; no allocation, I/O,
/// formatting, JSON, or blocking diagnostic lock is performed on the callback.
final class DiagnosticOutputBoundaryClock: @unchecked Sendable {
    static let shared = DiagnosticOutputBoundaryClock()

    private var firstTimestamp: Int64 = 0
    private var lastTimestamp: Int64 = 0

    func reset() {
        _ = OSAtomicCompareAndSwap64Barrier(
            OSAtomicAdd64Barrier(0, &firstTimestamp),
            0,
            &firstTimestamp
        )
        _ = OSAtomicCompareAndSwap64Barrier(
            OSAtomicAdd64Barrier(0, &lastTimestamp),
            0,
            &lastTimestamp
        )
    }

    func record(timestampNanoseconds: UInt64) {
        let value = Int64(min(timestampNanoseconds, UInt64(Int64.max)))
        _ = OSAtomicCompareAndSwap64Barrier(0, value, &firstTimestamp)
        while true {
            let old = OSAtomicAdd64Barrier(0, &lastTimestamp)
            if old >= value || OSAtomicCompareAndSwap64Barrier(old, value, &lastTimestamp) {
                break
            }
        }
    }

    func snapshot() -> (first: UInt64, last: UInt64) {
        let first = OSAtomicAdd64Barrier(0, &firstTimestamp)
        let last = OSAtomicAdd64Barrier(0, &lastTimestamp)
        return (UInt64(max(0, first)), UInt64(max(0, last)))
    }
}

/// Bounded, machine-readable runtime state used by the 041 diagnostics. The
/// registry deliberately contains scalar state only: it never stores HID
/// reports, PCM, text, or filesystem paths.
final class DiagnosticRuntimeHealthRegistry: @unchecked Sendable {
    static let shared = DiagnosticRuntimeHealthRegistry()

    private let lock = NSLock()
    private var values: [String: DiagnosticJSONValue] = [
        "hid_manager_running": .bool(false),
        "hid_device_active": .bool(false),
        "mapping_enabled": .string("unknown"),
        "mapping_verified": .string("unknown"),
        "physical_voice_key_down": .bool(false),
        "gesture_state": .string("idle"),
        "ble_connected": .bool(false),
        "ble_peripheral_state": .string("unknown"),
        "ble_transport_state": .string("unknown"),
        "transport_prepared": .bool(false),
        "atvv_ready": .bool(false),
        "atvv_streaming": .bool(false),
        "mic_open_state": .string("unavailable"),
        "audio_drain_state": .string("idle"),
        "audio_pipe_remote_active": .bool(false),
        "audio_pipe_output_ready": .bool(false),
        "audio_pipe_queue_depth_frames": .unsignedInteger(0),
        "audio_pipe_queue_has_remote_frames": .bool(false),
        "output_device_identity": .string("unavailable"),
        "selected_input_identity": .string("unavailable"),
        "last_hid_report_uptime_ms": .unsignedInteger(0),
        "last_mic_transition_uptime_ms": .unsignedInteger(0),
    ]

    func set(_ key: String, _ value: DiagnosticJSONValue) {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    func setBool(_ key: String, _ value: Bool) { set(key, .bool(value)) }
    func setString(_ key: String, _ value: String) { set(key, .string(value)) }
    func setUnsigned(_ key: String, _ value: UInt64) { set(key, .unsignedInteger(value)) }

    func recordHIDReport(at uptimeMilliseconds: UInt64) {
        setUnsigned("last_hid_report_uptime_ms", uptimeMilliseconds)
    }

    func recordMicrophoneTransition(at uptimeMilliseconds: UInt64) {
        setUnsigned("last_mic_transition_uptime_ms", uptimeMilliseconds)
    }

    func recordSelectedInputIdentity(_ identity: String?) {
        setString("selected_input_identity", identity ?? "unavailable")
    }

    func markOutputDevice(ready: Bool, identity: String?) {
        lock.lock()
        values["audio_pipe_output_ready"] = .bool(ready)
        values["output_device_identity"] = .string(identity ?? "unavailable")
        lock.unlock()
    }

    func updateAudioPipe(_ snapshot: AudioPipeDiagnosticsSnapshot) {
        lock.lock()
        values["audio_pipe_queue_depth_frames"] = .unsignedInteger(
            UInt64(max(0, snapshot.currentQueueDepthFrames))
        )
        values["audio_pipe_remote_active"] = .bool(snapshot.remoteActive)
        values["audio_pipe_queue_has_remote_frames"] = .bool(snapshot.queueHasRemoteFrames)
        lock.unlock()
    }

    func snapshot(extra: [String: DiagnosticJSONValue] = [:]) -> [String: DiagnosticJSONValue] {
        lock.lock()
        var result = values
        lock.unlock()
        let now = UInt64(max(0, ProcessInfo.processInfo.systemUptime * 1_000))
        for (timestampKey, ageKey) in [
            ("last_hid_report_uptime_ms", "last_hid_report_age_ms"),
            ("last_mic_transition_uptime_ms", "last_mic_transition_age_ms"),
        ] {
            if case .unsignedInteger(let timestamp) = result[timestampKey], timestamp > 0 {
                result[ageKey] = .unsignedInteger(now >= timestamp ? now - timestamp : 0)
            } else {
                result[ageKey] = .string("unavailable")
            }
        }
        for (key, value) in extra {
            result[key] = value
        }
        return result
    }
}

enum DiagnosticAudioMeterCadence {
    static let idleIntervalSeconds: TimeInterval = 30

    static func shouldEmit(
        mode: String,
        now: TimeInterval,
        lastIdleEmission: TimeInterval
    ) -> Bool {
        mode != "idle" || now - lastIdleEmission >= idleIntervalSeconds
    }
}

final class DiagnosticRuntimeHealthService: @unchecked Sendable {
    static let shared = DiagnosticRuntimeHealthService()

    private let authority: any DiagnosticAuthority
    private let registry: DiagnosticRuntimeHealthRegistry
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    init(
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared,
        registry: DiagnosticRuntimeHealthRegistry = .shared,
        queue: DispatchQueue = DispatchQueue(label: "com.remoteorbit.diagnostic-health")
    ) {
        self.authority = authority
        self.registry = registry
        self.queue = queue
    }

    func start() {
        lock.lock()
        guard timer == nil else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .seconds(30),
            repeating: .seconds(30),
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.emitHeartbeat()
        }
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    func stopForTesting() {
        lock.lock()
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
    }

    func emitHeartbeat() {
        emit(cadence: "idle_30s", extra: [:])
    }

    func recordStateTransition(
        _ transition: String,
        attemptID: String? = nil
    ) {
        var extra: [String: DiagnosticJSONValue] = [
            "transition": .string(transition),
        ]
        if let attemptID {
            extra["voice_attempt_id"] = .string(attemptID)
        }
        emit(cadence: "state_transition", extra: extra)
    }

    private func emit(cadence: String, extra: [String: DiagnosticJSONValue]) {
        var state = registry.snapshot(extra: extra)
        state["diagnostic_dropped_event_count"] = .unsignedInteger(authority.droppedEventCount)
        state["diagnostic_write_failure_count"] = .unsignedInteger(authority.writeFailureCount)
        guard let input = try? DiagnosticEventInput(
            eventType: "voice.runtime.health",
            subsystem: "voice.runtime",
            category: "health",
            severity: .info,
            sourceComponent: "diagnostic_hardening",
            payload: [
                "cadence": .string(cadence),
                "state": .object(state),
            ]
        ) else { return }
        authority.emit(input)
    }
}

final class VoiceStartWatchdog: @unchecked Sendable {
    static let stallAfterNanoseconds: UInt64 = 750_000_000
    static let failureAfterNanoseconds: UInt64 = 2_000_000_000

    private struct ActiveWatch {
        let attemptID: String
        var sessionID: String
        var startedAt: UInt64
        var lastStage: String
        var state: [String: DiagnosticJSONValue]
        var armed = false
        var audioStartSeen = false
        var audioFirstSeen = false
        var stallEmitted = false
        var failureEmitted = false
    }

    private let authority: any DiagnosticAuthority
    private let registry: DiagnosticRuntimeHealthRegistry
    private let clock: () -> UInt64
    private let automaticallySchedule: Bool
    private let lock = NSLock()
    private var active: ActiveWatch?
    private var timer: DispatchSourceTimer?

    init(
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared,
        registry: DiagnosticRuntimeHealthRegistry = .shared,
        clock: @escaping () -> UInt64 = P1A4MonotonicClock.nowNanoseconds,
        automaticallySchedule: Bool = false
    ) {
        self.authority = authority
        self.registry = registry
        self.clock = clock
        self.automaticallySchedule = automaticallySchedule
        if automaticallySchedule { startTimer() }
    }

    func begin(
        attemptID: String,
        sessionID: String = "unavailable",
        timestampNanoseconds: UInt64
    ) {
        lock.lock()
        active = ActiveWatch(
            attemptID: attemptID,
            sessionID: sessionID,
            startedAt: timestampNanoseconds,
            lastStage: "PHYSICAL_DOWN",
            state: registry.snapshot()
        )
        lock.unlock()
    }

    func holdConfirmed(
        attemptID: String,
        sessionID: String,
        timestampNanoseconds: UInt64,
        state: [String: DiagnosticJSONValue]
    ) {
        lock.lock()
        guard var active, active.attemptID == attemptID else {
            lock.unlock()
            return
        }
        active.sessionID = sessionID
        active.startedAt = timestampNanoseconds
        active.lastStage = "HOLD_CONFIRMED"
        active.state = state
        active.armed = true
        self.active = active
        lock.unlock()
        if automaticallySchedule { startTimer() }
    }

    func update(
        attemptID: String,
        stage: String,
        state: [String: DiagnosticJSONValue]
    ) {
        lock.lock()
        guard var active, active.attemptID == attemptID else {
            lock.unlock()
            return
        }
        active.lastStage = stage
        active.state = state
        if stage == "AUDIO_START" {
            active.audioStartSeen = true
        } else if stage == "AUDIO_FIRST" {
            active.audioFirstSeen = true
        }
        self.active = active
        lock.unlock()
    }

    func audioFirstArrived(attemptID: String) {
        lock.lock()
        guard active?.attemptID == attemptID, active?.audioFirstSeen == true else {
            lock.unlock()
            return
        }
        self.active = nil
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
    }

    func end(attemptID: String) {
        lock.lock()
        guard active?.attemptID == attemptID else {
            lock.unlock()
            return
        }
        self.active = nil
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
    }

    func evaluate(at timestampNanoseconds: UInt64) {
        let emission: (stageEvent: String, attemptID: String, sessionID: String, lastStage: String, missingStage: String, elapsedMS: Double, state: [String: DiagnosticJSONValue])?
        lock.lock()
        guard var active,
              active.armed,
              timestampNanoseconds >= active.startedAt else {
            lock.unlock()
            return
        }
        let elapsed = timestampNanoseconds - active.startedAt
        let missingStage = active.audioStartSeen ? "AUDIO_FIRST" : "AUDIO_START"
        if elapsed >= Self.failureAfterNanoseconds, !active.failureEmitted {
            active.failureEmitted = true
            emission = (
                "VOICE_START_FAILURE",
                active.attemptID,
                active.sessionID,
                active.lastStage,
                missingStage,
                Double(elapsed) / 1_000_000,
                active.state
            )
            self.active = active
        } else if elapsed >= Self.stallAfterNanoseconds, !active.stallEmitted {
            active.stallEmitted = true
            emission = (
                "VOICE_START_STALL",
                active.attemptID,
                active.sessionID,
                active.lastStage,
                missingStage,
                Double(elapsed) / 1_000_000,
                active.state
            )
            self.active = active
        } else {
            emission = nil
        }
        lock.unlock()

        guard let emission else { return }
        emit(
            stageEvent: emission.stageEvent,
            attemptID: emission.attemptID,
            sessionID: emission.sessionID,
            lastStage: emission.lastStage,
            missingStage: emission.missingStage,
            elapsedMS: emission.elapsedMS,
            state: emission.state
        )
        if emission.stageEvent == "VOICE_START_FAILURE" {
            emitFailureClassification(
                attemptID: emission.attemptID,
                missingStage: emission.missingStage,
                state: emission.state
            )
        }
    }

    private func startTimer() {
        lock.lock()
        guard timer == nil else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.remoteorbit.voice-start-watchdog")
        )
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.evaluate(at: self.clock())
        }
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    private func emit(
        stageEvent: String,
        attemptID: String,
        sessionID: String,
        lastStage: String,
        missingStage: String,
        elapsedMS: Double,
        state: [String: DiagnosticJSONValue]
    ) {
        guard let input = try? DiagnosticEventInput(
            eventType: "voice.start.watchdog",
            subsystem: "voice.start",
            category: "watchdog",
            severity: .warning,
            sourceComponent: "diagnostic_hardening",
            sessionID: sessionID == "unavailable" ? nil : sessionID,
            correlationID: attemptID,
            payload: [
                "voice_attempt_id": .string(attemptID),
                "stage_event": .string(stageEvent),
                "last_successful_stage": .string(lastStage),
                "missing_stage": .string(missingStage),
                "elapsed_ms": .double(elapsedMS),
                "state": .object(state),
            ]
        ) else { return }
        authority.emit(input)
    }

    private func emitFailureClassification(
        attemptID: String,
        missingStage: String,
        state: [String: DiagnosticJSONValue]
    ) {
        guard let input = try? DiagnosticEventInput(
            eventType: "voice.failure.classified",
            subsystem: "voice.failure",
            category: "classification",
            severity: .warning,
            sourceComponent: "diagnostic_hardening",
            correlationID: attemptID,
            payload: [
                "voice_attempt_id": .string(attemptID),
                "layer": .string("start_path"),
                "classification": .string("VOICE_START_FAILURE"),
                "status": .string("observed"),
                "reason": .string(missingStage + "_MISSING"),
                "state": .object(state),
            ]
        ) else { return }
        authority.emit(input)
    }
}

final class VoiceAttemptDiagnostics: @unchecked Sendable {
    static let shared = VoiceAttemptDiagnostics(automaticallyScheduleWatchdog: true)

    private struct Attempt {
        let id: UUID
        let startedAt: UInt64
        var sessionID: UUID?
        var lastStage: String
        var lastStageAt: UInt64
        var state: [String: DiagnosticJSONValue]
    }

    private let authority: any DiagnosticAuthority
    private let registry: DiagnosticRuntimeHealthRegistry
    private let health: DiagnosticRuntimeHealthService
    private let watchdog: VoiceStartWatchdog
    private let clock: () -> UInt64
    private let lock = NSLock()
    private var current: Attempt?

    init(
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared,
        registry: DiagnosticRuntimeHealthRegistry = .shared,
        health: DiagnosticRuntimeHealthService = .shared,
        clock: @escaping () -> UInt64 = P1A4MonotonicClock.nowNanoseconds,
        automaticallyScheduleWatchdog: Bool = false
    ) {
        self.authority = authority
        self.registry = registry
        self.health = health
        self.clock = clock
        self.watchdog = VoiceStartWatchdog(
            authority: authority,
            registry: registry,
            clock: clock,
            automaticallySchedule: automaticallyScheduleWatchdog
        )
    }

    @discardableResult
    func beginPhysicalAttempt(
        timestampNanoseconds: UInt64? = nil,
        state: [String: DiagnosticJSONValue] = [:]
    ) -> UUID {
        let timestamp = timestampNanoseconds ?? clock()
        lock.lock()
        if let current {
            let id = current.id
            lock.unlock()
            return id
        }
        let id = UUID()
        current = Attempt(
            id: id,
            startedAt: timestamp,
            sessionID: nil,
            lastStage: "PHYSICAL_DOWN",
            lastStageAt: timestamp,
            state: mergedState(extra: state)
        )
        let snapshot = current!
        lock.unlock()
        watchdog.begin(attemptID: id.uuidString, timestampNanoseconds: timestamp)
        emitStage(snapshot: snapshot)
        return id
    }

    @discardableResult
    func ensureSession(_ sessionID: UUID) -> UUID {
        if currentID == nil {
            _ = beginPhysicalAttempt(state: ["physical_source": .string("voice_input")])
        }
        lock.lock()
        guard var current else {
            lock.unlock()
            return sessionID
        }
        current.sessionID = sessionID
        current.lastStage = "GESTURE_BEGIN"
        current.lastStageAt = clock()
        self.current = current
        let snapshot = current
        lock.unlock()
        watchdog.update(
            attemptID: snapshot.id.uuidString,
            stage: snapshot.lastStage,
            state: snapshot.state
        )
        emitStage(snapshot: snapshot)
        return snapshot.id
    }

    var currentID: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return current?.id
    }

    func attemptID(for sessionID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let current, current.sessionID?.uuidString == sessionID else { return nil }
        return current.id.uuidString
    }

    func stage(
        _ stage: String,
        sessionID: UUID? = nil,
        timestampNanoseconds: UInt64? = nil,
        state: [String: DiagnosticJSONValue] = [:]
    ) {
        let timestamp = timestampNanoseconds ?? clock()
        switch stage {
        case "BLE_START_REQUEST", "REMOTE_ROUTE_BEGIN":
            registry.setString("mic_open_state", "pending")
        case "MIC_OPEN_TX":
            registry.setString("mic_open_state", "requested")
        case "AUDIO_START":
            registry.setString("mic_open_state", "streaming")
            registry.setBool("atvv_streaming", true)
        case "AUDIO_STOP":
            registry.setBool("atvv_streaming", false)
            registry.setString("audio_drain_state", "draining")
        case "DRAIN_FINISH", "AUDIO_PIPELINE_CLOSED":
            registry.setString("audio_drain_state", "idle")
        default:
            break
        }
        lock.lock()
        guard var current,
              sessionID == nil || current.sessionID == sessionID else {
            lock.unlock()
            return
        }
        current.lastStage = stage
        current.lastStageAt = timestamp
        current.state = mergedState(extra: state)
        let snapshot = current
        self.current = current
        lock.unlock()

        watchdog.update(
            attemptID: snapshot.id.uuidString,
            stage: stage,
            state: snapshot.state
        )
        if stage == "HOLD_CONFIRMED", let sessionID = snapshot.sessionID {
            registry.setString("gesture_state", "holding")
            watchdog.holdConfirmed(
                attemptID: snapshot.id.uuidString,
                sessionID: sessionID.uuidString,
                timestampNanoseconds: timestamp,
                state: snapshot.state
            )
        } else if stage == "AUDIO_FIRST" {
            watchdog.audioFirstArrived(attemptID: snapshot.id.uuidString)
        } else if stage == "PHYSICAL_UP" || stage == "AUDIO_PIPELINE_CLOSED" {
            registry.setString("gesture_state", "idle")
        }
        health.recordStateTransition(stage, attemptID: snapshot.id.uuidString)
        emitStage(snapshot: snapshot)
        if stage == "MIC_OPEN_WRITE_FAILED" {
            emitFailureClassification(
                attemptID: snapshot.id.uuidString,
                layer: "transport",
                classification: "MIC_OPEN_WRITE_FAILURE",
                status: "observed",
                reason: "MIC_OPEN_COMMAND_NOT_WRITTEN",
                state: snapshot.state
            )
        }
    }

    func end(sessionID: UUID?) {
        lock.lock()
        guard let current,
              sessionID == nil || current.sessionID == sessionID else {
            lock.unlock()
            return
        }
        self.current = nil
        lock.unlock()
        watchdog.end(attemptID: current.id.uuidString)
    }

    func evaluateWatchdogForTesting(at timestampNanoseconds: UInt64) {
        watchdog.evaluate(at: timestampNanoseconds)
    }

    private func mergedState(extra: [String: DiagnosticJSONValue]) -> [String: DiagnosticJSONValue] {
        var result = registry.snapshot()
        for (key, value) in extra { result[key] = value }
        return result
    }

    private func emitStage(snapshot: Attempt) {
        let sessionID = snapshot.sessionID?.uuidString ?? "unavailable"
        let elapsedMS = snapshot.lastStageAt >= snapshot.startedAt
            ? Double(snapshot.lastStageAt - snapshot.startedAt) / 1_000_000
            : 0
        guard let input = try? DiagnosticEventInput(
            eventType: "voice.attempt.stage",
            subsystem: "voice.attempt",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "diagnostic_hardening",
            sessionID: sessionID == "unavailable" ? nil : sessionID,
            correlationID: snapshot.id.uuidString,
            payload: [
                "voice_attempt_id": .string(snapshot.id.uuidString),
                "session_id": .string(sessionID),
                "stage": .string(snapshot.lastStage),
                "elapsed_ms": .double(elapsedMS),
                "state": .object(snapshot.state),
            ]
        ) else { return }
        authority.emit(input)
    }

    private func emitFailureClassification(
        attemptID: String,
        layer: String,
        classification: String,
        status: String,
        reason: String,
        state: [String: DiagnosticJSONValue]
    ) {
        guard let input = try? DiagnosticEventInput(
            eventType: "voice.failure.classified",
            subsystem: "voice.failure",
            category: "classification",
            severity: .warning,
            sourceComponent: "diagnostic_hardening",
            correlationID: attemptID,
            payload: [
                "voice_attempt_id": .string(attemptID),
                "layer": .string(layer),
                "classification": .string(classification),
                "status": .string(status),
                "reason": .string(reason),
                "state": .object(state),
            ]
        ) else { return }
        authority.emit(input)
    }
}

struct DiagnosticUnderrunEpisode: Equatable, Sendable {
    let beginTimestampNanoseconds: UInt64
    let endTimestampNanoseconds: UInt64
    let missingFrames: UInt64
    let queueDepthBeforeFrames: UInt64?
    let minimumQueueDepthAfterFrames: UInt64
    let previousBLEAgeNanoseconds: UInt64?
    let previousPCMSubmitAgeNanoseconds: UInt64?
    let nextBLEAgeNanoseconds: UInt64?
    let nextPCMSubmitAgeNanoseconds: UInt64?
    let lifecyclePhase: String

    var eventSpanDurationNanoseconds: UInt64 {
        endTimestampNanoseconds >= beginTimestampNanoseconds
            ? endTimestampNanoseconds - beginTimestampNanoseconds
            : 0
    }

    var estimatedMissingAudioDurationNanoseconds: UInt64 {
        let numerator = missingFrames.multipliedReportingOverflow(by: DiagnosticAudioTimingAuthority.nanosecondsPerSecond)
        guard !numerator.overflow else { return UInt64.max }
        return numerator.partialValue / DiagnosticAudioTimingAuthority.outputSampleRateHz
    }

    func toDiagnosticJSONValue() -> DiagnosticJSONValue {
        .object([
            "begin_timestamp_nanoseconds": .unsignedInteger(beginTimestampNanoseconds),
            "end_timestamp_nanoseconds": .unsignedInteger(endTimestampNanoseconds),
            "event_span_duration_nanoseconds": .unsignedInteger(eventSpanDurationNanoseconds),
            "estimated_missing_audio_duration_nanoseconds": .unsignedInteger(estimatedMissingAudioDurationNanoseconds),
            "missing_frames": .unsignedInteger(missingFrames),
            "queue_depth_before_frames": queueDepthBeforeFrames.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
            "minimum_queue_depth_after_frames": .unsignedInteger(minimumQueueDepthAfterFrames),
            "previous_ble_age_nanoseconds": previousBLEAgeNanoseconds.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
            "previous_pcm_submit_age_nanoseconds": previousPCMSubmitAgeNanoseconds.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
            "next_ble_age_nanoseconds": nextBLEAgeNanoseconds.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
            "next_pcm_submit_age_nanoseconds": nextPCMSubmitAgeNanoseconds.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
            "lifecycle_phase": .string(lifecyclePhase),
        ])
    }
}

enum DiagnosticAudioTimingAuthority {
    /// AudioPipe renders at 48 kHz. Missing-frame duration is an estimate
    /// derived from this explicit output-clock authority, not from event span.
    static let outputSampleRateHz: UInt64 = 48_000
    static let nanosecondsPerSecond: UInt64 = 1_000_000_000
}

enum DiagnosticUnderrunEpisodeBuilder {
    static func build(_ points: [LongTermObservationPoint]) -> [DiagnosticUnderrunEpisode] {
        let sorted = points.sorted {
            if $0.timestampNanoseconds == $1.timestampNanoseconds {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.timestampNanoseconds < $1.timestampNanoseconds
        }
        let starvation = sorted.filter { $0.kind == .queueStarvation && $0.unfilledFrames > 0 }
        guard !starvation.isEmpty else { return [] }
        let firstPCM = sorted.first { $0.kind == .pcmSubmitted }?.timestampNanoseconds
        var episodes: [DiagnosticUnderrunEpisode] = []
        var start = starvation[0]
        var end = starvation[0]
        var missing = end.unfilledFrames
        var minimumQueue = end.queueDepthAfterFrames
        for point in starvation.dropFirst() {
            let samePhase = phase(for: point, firstPCM: firstPCM) == phase(for: end, firstPCM: firstPCM)
            if samePhase && point.timestampNanoseconds - end.timestampNanoseconds <= 100_000_000 {
                end = point
                missing &+= point.unfilledFrames
                minimumQueue = min(minimumQueue, point.queueDepthAfterFrames)
            } else {
                episodes.append(makeEpisode(start: start, end: end, missing: missing, minimumQueue: minimumQueue, points: sorted, firstPCM: firstPCM))
                start = point
                end = point
                missing = end.unfilledFrames
                minimumQueue = end.queueDepthAfterFrames
            }
        }
        episodes.append(makeEpisode(start: start, end: end, missing: missing, minimumQueue: minimumQueue, points: sorted, firstPCM: firstPCM))
        return episodes
    }

    private static func phase(
        for point: LongTermObservationPoint,
        firstPCM: UInt64?
    ) -> String {
        if point.marker == .tail { return "tail" }
        if point.marker == .active {
            if let firstPCM, point.timestampNanoseconds < firstPCM { return "startup" }
            return "active"
        }
        return "idle_or_local"
    }

    private static func makeEpisode(
        start: LongTermObservationPoint,
        end: LongTermObservationPoint,
        missing: UInt64,
        minimumQueue: UInt64,
        points: [LongTermObservationPoint],
        firstPCM: UInt64?
    ) -> DiagnosticUnderrunEpisode {
        func age(before kind: LongTermObservationKind) -> UInt64? {
            guard let prior = points.last(where: { $0.kind == kind && $0.timestampNanoseconds <= start.timestampNanoseconds }) else { return nil }
            return start.timestampNanoseconds - prior.timestampNanoseconds
        }
        func age(after kind: LongTermObservationKind) -> UInt64? {
            guard let next = points.first(where: { $0.kind == kind && $0.timestampNanoseconds >= end.timestampNanoseconds }) else { return nil }
            return next.timestampNanoseconds - end.timestampNanoseconds
        }
        return DiagnosticUnderrunEpisode(
            beginTimestampNanoseconds: start.timestampNanoseconds,
            endTimestampNanoseconds: end.timestampNanoseconds,
            missingFrames: missing,
            queueDepthBeforeFrames: start.queueDepthBeforeFrames,
            minimumQueueDepthAfterFrames: minimumQueue,
            previousBLEAgeNanoseconds: age(before: .bleArrival),
            previousPCMSubmitAgeNanoseconds: age(before: .pcmSubmitted),
            nextBLEAgeNanoseconds: age(after: .bleArrival),
            nextPCMSubmitAgeNanoseconds: age(after: .pcmSubmitted),
            lifecyclePhase: phase(for: start, firstPCM: firstPCM)
        )
    }
}

enum DiagnosticHardeningSessionEmitter {
    static func emit(
        summary: LongTermVoiceSessionSummary,
        trace: FixedCapacityObservationTraceSnapshot,
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared
    ) {
        let points = trace.allIncludingIncident
        let rendered = points.filter { $0.kind == .render && $0.filledFrames > 0 }
        let callbackOutput = DiagnosticOutputBoundaryClock.shared.snapshot()
        let firstRender = rendered.first?.timestampNanoseconds ?? 0
        let lastRender = rendered.last?.timestampNanoseconds ?? 0
        let firstOutput = callbackOutput.first
        let lastOutput = callbackOutput.last
        let runtime = DiagnosticRuntimeHealthRegistry.shared.snapshot()
        let outputIdentity = stringValue(runtime["output_device_identity"]) ?? "unavailable"
        let selectedInput = SystemAudioDeviceManager.defaultInputDevice?.stableIdentifier
            ?? "unavailable"
        let outputReady = boolValue(runtime["audio_pipe_output_ready"]) ?? false
        let attemptID = VoiceAttemptDiagnostics.shared.attemptID(for: summary.sessionID) ?? "unavailable"
        let hasAudioPath = summary.audioStartTimestampNanoseconds != nil
            || summary.audioFirstTimestampNanoseconds != nil
            || summary.submittedFrames > 0
            || summary.renderedFrames > 0
        guard hasAudioPath else { return }

        if let input = try? DiagnosticEventInput(
            eventType: "voice.output.boundary",
            subsystem: "voice.output",
            category: "boundary",
            severity: .info,
            sourceComponent: "diagnostic_hardening",
            sessionID: summary.sessionID,
            correlationID: attemptID == "unavailable" ? nil : attemptID,
            payload: [
                "voice_attempt_id": .string(attemptID),
                "first_nonzero_output_timestamp_ns": .unsignedInteger(firstOutput),
                "last_nonzero_output_timestamp_ns": .unsignedInteger(lastOutput),
                "first_render_timestamp_ns": .unsignedInteger(firstRender),
                "last_render_timestamp_ns": .unsignedInteger(lastRender),
                "nonzero_output_observed": .bool(callbackOutput.first > 0),
                "output_device_identity": .string(outputIdentity),
                "output_ready": .bool(outputReady),
                "selected_input_identity": .string(selectedInput),
                "consumer_evidence": .string("unavailable"),
            ]
        ) {
            authority.emit(input)
        }

        if summary.anomalyFlags.contains(where: {
            [.activeDeficit, .queueStarvation, .decodeGap, .notificationGap, .deliveryDeficit].contains($0)
        }) {
            emitFailure(
                authority: authority,
                attemptID: attemptID,
                layer: "audio_continuity",
                classification: "AUDIO_CONTINUITY_FAILURE",
                status: "observed",
                reason: "SESSION_ANOMALY_FLAGS",
                state: [
                    "anomaly_flags": .array(summary.anomalyFlags.map { .string($0.rawValue) }),
                    "active_underrun_episodes": .unsignedInteger(UInt64(summary.underrunEpisodes.filter { $0.lifecyclePhase == "active" }.count)),
                    "tail_underrun_episodes": .unsignedInteger(UInt64(summary.underrunEpisodes.filter { $0.lifecyclePhase == "tail" }.count)),
                ]
            )
        }

        if !outputReady {
            emitFailure(
                authority: authority,
                attemptID: attemptID,
                layer: "output_boundary",
                classification: "OUTPUT_CONSUMER_FAILURE",
                status: "observed",
                reason: "OUTPUT_DEVICE_NOT_READY",
                state: [
                    "output_device_identity": .string(outputIdentity),
                    "consumer_evidence": .string("unavailable"),
                ]
            )
        } else if firstOutput == 0 && summary.renderedFrames > 0 {
            emitFailure(
                authority: authority,
                attemptID: attemptID,
                layer: "output_boundary",
                classification: "OUTPUT_CONSUMER_FAILURE",
                status: "unknown",
                reason: "CONSUMER_CALLBACK_EVIDENCE_UNAVAILABLE",
                state: ["consumer_evidence": .string("unavailable")]
            )
        }
    }

    private static func emitFailure(
        authority: any DiagnosticAuthority,
        attemptID: String,
        layer: String,
        classification: String,
        status: String,
        reason: String,
        state: [String: DiagnosticJSONValue]
    ) {
        guard let input = try? DiagnosticEventInput(
            eventType: "voice.failure.classified",
            subsystem: "voice.failure",
            category: "classification",
            severity: .warning,
            sourceComponent: "diagnostic_hardening",
            correlationID: attemptID == "unavailable" ? nil : attemptID,
            payload: [
                "voice_attempt_id": .string(attemptID),
                "layer": .string(layer),
                "classification": .string(classification),
                "status": .string(status),
                "reason": .string(reason),
                "state": .object(state),
            ]
        ) else { return }
        authority.emit(input)
    }

    private static func stringValue(_ value: DiagnosticJSONValue?) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }

    private static func boolValue(_ value: DiagnosticJSONValue?) -> Bool? {
        guard case .bool(let value) = value else { return nil }
        return value
    }
}
