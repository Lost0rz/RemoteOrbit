import Foundation

/// A process-local timeline for one voice gesture. It is diagnostic only: it
/// never gates callbacks or changes the voice state machine.
enum VoiceTimingLogger {
    private static let lock = NSLock()
    private static var activeSessionID: UUID?
    private static var startedAt: TimeInterval = 0
    private static var timeline: [String: UInt64] = [:]
    private static var frontEdgeUnderrunStats = P1A5FrontEdgeUnderrunStats()
    private static var lastEndedSessionID: UUID?
    private static var lastEndedStartedAt: TimeInterval = 0

    static var p1A5Enabled: Bool {
        ProcessInfo.processInfo.environment["REMOTE_ORBIT_P1A5_FRONT_EDGE"] == "1"
    }

    static var currentSessionID: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return activeSessionID
    }

    static func begin(sessionID: UUID) {
        lock.lock()
        activeSessionID = sessionID
        startedAt = ProcessInfo.processInfo.systemUptime
        timeline = [:]
        frontEdgeUnderrunStats = P1A5FrontEdgeUnderrunStats()
        lastEndedSessionID = nil
        lastEndedStartedAt = 0
        lock.unlock()
        let timestamp = P1A4MonotonicClock.nowNanoseconds()
        record("T0_voice_trigger_down", timestampNanoseconds: timestamp)
        recordIfAbsent("F0_trigger_down", timestampNanoseconds: timestamp)
        mark("VOICE_DOWN", sessionID: sessionID)
    }

    /// Records a correlation timestamp without emitting a high-frequency log.
    /// The caller supplies the event timestamp so audio callbacks can be
    /// observed without changing their scheduling or producing log pressure.
    static func record(_ event: String, timestampNanoseconds: UInt64) {
        lock.lock()
        if activeSessionID != nil {
            timeline[event] = timestampNanoseconds
        }
        lock.unlock()
    }

    static func recordIfAbsent(_ event: String, timestampNanoseconds: UInt64) {
        lock.lock()
        if activeSessionID != nil, timeline[event] == nil {
            timeline[event] = timestampNanoseconds
        }
        lock.unlock()
    }

    static func hasEvent(_ event: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return timeline[event] != nil
    }

    static func recordVoiceOnset(
        _ candidate: P1A5VoiceOnsetCandidate,
        detectedAtNanoseconds: UInt64
    ) {
        recordIfAbsent(
            "F6_first_voiced_pcm_decoded",
            timestampNanoseconds: candidate.timestampNanoseconds
        )
        lock.lock()
        let sessionID = activeSessionID?.uuidString ?? "NA"
        lock.unlock()
        print(
            "[P1-A5] audio.voice_onset_candidate "
                + "session_id=\(sessionID) "
                + "monotonic_ns=\(candidate.timestampNanoseconds) "
                + "detection_monotonic_ns=\(detectedAtNanoseconds) "
                + "frame_index=\(candidate.frameIndex) "
                + String(format: "rms=%.1f peak=%d threshold=%.1f ", candidate.rms, candidate.peak, candidate.threshold)
                + "consecutive_voiced_frames=\(candidate.consecutiveVoicedFrames)"
        )
    }

    static func recordFrontEdgeUnderrun(
        timestampNanoseconds: UInt64,
        durationMilliseconds: Double,
        queuedFramesBefore: Int,
        queuedFramesAfter: Int
    ) {
        lock.lock()
        guard let onset = timeline["F6_first_voiced_pcm_decoded"],
              timestampNanoseconds >= onset else {
            lock.unlock()
            return
        }
        let distanceMilliseconds = Double(timestampNanoseconds - onset) / 1_000_000
        guard distanceMilliseconds <= 1_000 else {
            lock.unlock()
            return
        }
        frontEdgeUnderrunStats.record(
            distanceMilliseconds: distanceMilliseconds,
            durationMilliseconds: durationMilliseconds
        )
        let sessionID = activeSessionID?.uuidString ?? "NA"
        lock.unlock()
        print(
            "[P1-A5] audio.front_edge_underrun "
                + "session_id=\(sessionID) "
                + "monotonic_ns=\(timestampNanoseconds) "
                + String(format: "duration_ms=%.3f distance_from_voice_onset_ms=%.3f ", durationMilliseconds, distanceMilliseconds)
                + "queued_frames_before=\(queuedFramesBefore) queued_frames_after=\(queuedFramesAfter)"
        )
    }

    static func timelineEventName(for event: String) -> String? {
        switch event {
        case "STOP_REQUESTED": return "T5_stop_requested"
        case "PHYSICAL_UP": return "T5_physical_up"
        case "AUDIO_STOP": return "T5_audio_stop_received"
        case "AUDIO_DRAIN_BEGIN", "OUTPUT_DRAIN_BEGIN":
            return "T6_audio_drain_begin"
        case "QUEUE_EMPTY": return "T6_queue_empty"
        case "DRAIN_FINISH": return "T7_audio_drain_end"
        case "AUDIO_PIPELINE_CLOSED": return "T8_audio_pipeline_closed"
        case "OPTION_UP_REQUESTED": return "T9_option_up_requested"
        case "OPTION_UP_EMITTED": return "T10_option_up_emitted"
        default: return nil
        }
    }

    static func recordQueueEmpty(timestampNanoseconds: UInt64) {
        recordIfAbsent(
            "T6_queue_empty",
            timestampNanoseconds: timestampNanoseconds
        )
    }

    static func mark(_ event: String, sessionID: UUID? = nil) {
        lock.lock()
        guard let activeSessionID,
              sessionID == nil || sessionID == activeSessionID else {
            lock.unlock()
            return
        }
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        let shortID = String(activeSessionID.uuidString.prefix(4))
        let sessionUUID = activeSessionID.uuidString
        lock.unlock()
        let nowNanoseconds = P1A4MonotonicClock.nowNanoseconds()
        if let timelineEvent = timelineEventName(for: event) {
            record(timelineEvent, timestampNanoseconds: nowNanoseconds)
        }
        print(
            "[VOICE][\(shortID)][TIMING] \(event) "
                + String(format: "+%.1fms", elapsedMS)
                + " monotonic_ns=\(nowNanoseconds)"
                + " session_id=\(sessionUUID)"
                + " wall_clock=\(P1A4MonotonicClock.wallClockISO8601())"
        )
    }

    /// A transport close can legitimately occur after Option-Up has completed
    /// the gesture and ended the normal voice timeline. Keep that close
    /// observable without reopening or extending the gesture state machine.
    static func markForSession(_ event: String, sessionID: UUID) {
        lock.lock()
        if activeSessionID == sessionID {
            lock.unlock()
            mark(event, sessionID: sessionID)
            return
        }
        guard activeSessionID == nil,
              lastEndedSessionID == sessionID else {
            lock.unlock()
            return
        }
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - lastEndedStartedAt) * 1_000
        let shortID = String(sessionID.uuidString.prefix(4))
        let sessionUUID = sessionID.uuidString
        lock.unlock()
        let nowNanoseconds = P1A4MonotonicClock.nowNanoseconds()
        print(
            "[VOICE][\(shortID)][TIMING] \(event) "
                + String(format: "+%.1fms", elapsedMS)
                + " monotonic_ns=\(nowNanoseconds)"
                + " session_id=\(sessionUUID)"
                + " wall_clock=\(P1A4MonotonicClock.wallClockISO8601())"
        )
    }

    static func end(sessionID: UUID) {
        lock.lock()
        if activeSessionID == sessionID {
            lastEndedSessionID = sessionID
            lastEndedStartedAt = startedAt
            activeSessionID = nil
        }
        let snapshot = timeline
        let underrunSnapshot = frontEdgeUnderrunStats
        timeline = [:]
        lock.unlock()
        let orderedEvents = [
            "T0_voice_trigger_down",
            "T1_first_ble_audio_packet",
            "T2_last_ble_audio_packet_received",
            "T3_last_decoded_pcm_frame",
            "T4_last_playout_frame_submitted",
            "T4R_last_playout_frame_rendered",
            "T5_stop_requested",
            "T5_physical_up",
            "T5_audio_stop_received",
            "T6_audio_drain_begin",
            "T6_queue_empty",
            "T7_audio_drain_end",
            "T8_audio_pipeline_closed",
            "T9_option_up_requested",
            "T10_option_up_emitted"
        ]
        let values = orderedEvents.map { event in
            "\(event)=\(snapshot[event].map(String.init) ?? "NA")"
        }.joined(separator: " ")
        print(
            "[P1-A4] AUDIO_TIMELINE session_id=\(sessionID.uuidString) "
                + values
        )
        guard p1A5Enabled else { return }

        let frontEdgeEvents = [
            "F0_trigger_down",
            "F1_audio_pipeline_start_requested",
            "F2_first_ble_packet_received",
            "F3_first_pcm_decoded",
            "F4_first_pcm_submitted",
            "F5_first_pcm_rendered",
            "F6_first_voiced_pcm_decoded",
            "F7_first_voiced_pcm_submitted",
            "F8_first_voiced_pcm_rendered",
            "F9_playout_stable"
        ]
        let frontEdgeValues = frontEdgeEvents.map { event in
            "\(event)=\(snapshot[event].map(String.init) ?? "NA")"
        }.joined(separator: " ")
        let bucketNames = ["0_100", "100_250", "250_500", "500_1000"]
        let bucketValues = zip(bucketNames, underrunSnapshot.buckets).map { name, bucket in
            String(format: "UNDERRUN_%@_MS=%.3f UNDERRUN_%@_COUNT=%d", name, bucket.durationMilliseconds, name, bucket.count)
        }.joined(separator: " ")
        print(
            "[P1-A5] FRONT_EDGE_TIMELINE session_id=\(sessionID.uuidString) "
                + frontEdgeValues + " " + bucketValues
        )
    }
}

/// The physical HID path is the normal owner. This small state object only
/// records the captured edges so VoiceKeyFilter can choose the existing
/// hardware replay or copy-failure fallback without losing gesture identity.
enum HardwareOptionEdge: Equatable {
    case down
    case up
}

enum HardwareOptionResolution: Equatable {
    case hardwareReplay
    case syntheticTap
    case syntheticDown
    case noOptionEdge
}

final class HardwareOptionGate {
    private(set) var activeSessionID: UUID?
    private var downSeen = false
    private var upSeen = false
    private var copiedDownPresent = false

    @discardableResult
    func begin(sessionID: UUID) -> Bool {
        if let activeSessionID, activeSessionID != sessionID {
            _ = cancel(sessionID: activeSessionID)
        }
        if activeSessionID == sessionID {
            return true
        }
        activeSessionID = sessionID
        downSeen = false
        upSeen = false
        copiedDownPresent = false
        return true
    }

    @discardableResult
    func capture(_ edge: HardwareOptionEdge, copied: Bool) -> Bool {
        guard activeSessionID != nil else { return false }
        switch edge {
        case .down:
            downSeen = true
            copiedDownPresent = copiedDownPresent || copied
        case .up:
            guard downSeen else { return false }
            upSeen = true
        }
        return true
    }

    @discardableResult
    func resolve(sessionID: UUID) -> HardwareOptionResolution? {
        guard activeSessionID == sessionID else { return nil }
        let resolution: HardwareOptionResolution
        if copiedDownPresent {
            resolution = .hardwareReplay
        } else if !downSeen {
            resolution = .noOptionEdge
        } else if upSeen {
            resolution = .syntheticTap
        } else {
            resolution = .syntheticDown
        }
        clear()
        return resolution
    }

    @discardableResult
    func cancel(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        clear()
        return true
    }

    private func clear() {
        activeSessionID = nil
        downSeen = false
        upSeen = false
        copiedDownPresent = false
    }
}

/// Owns synthetic Option fallback edges for one voice gesture. In
/// particular, the delayed up from a short tap is ignored once a newer
/// session owns the trigger, so it cannot release the newer gesture.
final class VoiceOptionTrigger {
    typealias EventSink = (_ isDown: Bool) -> Void

    static let shared = VoiceOptionTrigger { isDown in
        if isDown {
            Key.optionDown()
        } else {
            Key.optionUp()
        }
    }

    private let eventSink: EventSink
    private(set) var activeSessionID: UUID?
    private(set) var isOptionDown = false

    init(eventSink: @escaping EventSink) {
        self.eventSink = eventSink
    }

    convenience init() {
        self.init { isDown in
            if isDown {
                Key.optionDown()
            } else {
                Key.optionUp()
            }
        }
    }

    @discardableResult
    func begin(sessionID: UUID) -> Bool {
        if let activeSessionID, activeSessionID != sessionID {
            _ = abort(sessionID: activeSessionID)
        }
        if activeSessionID != sessionID {
            activeSessionID = sessionID
            isOptionDown = false
        }
        return true
    }

    @discardableResult
    func sendDown(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID, !isOptionDown else { return false }
        isOptionDown = true
        eventSink(true)
        return true
    }

    @discardableResult
    func sendUp(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID, isOptionDown else { return false }
        isOptionDown = false
        eventSink(false)
        VoiceTimingLogger.mark("OPTION_UP_EMITTED", sessionID: sessionID)
        activeSessionID = nil
        return true
    }

    @discardableResult
    func abort(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        let wasDown = isOptionDown
        isOptionDown = false
        if wasDown {
            eventSink(false)
            VoiceTimingLogger.mark("OPTION_UP_EMITTED", sessionID: sessionID)
        }
        activeSessionID = nil
        return wasDown
    }

    @discardableResult
    func reset() -> Bool {
        guard let activeSessionID else { return false }
        return abort(sessionID: activeSessionID)
    }

    @discardableResult
    func sendTap(sessionID: UUID, duration: TimeInterval = 0.06) -> Bool {
        guard activeSessionID == sessionID else { return false }
        guard sendDown(sessionID: sessionID) else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            _ = self?.sendUp(sessionID: sessionID)
        }
        return true
    }
}
