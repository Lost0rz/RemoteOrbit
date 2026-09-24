import Foundation

/// A process-local timeline for one voice gesture. It is diagnostic only: it
/// never gates callbacks or changes the voice state machine.
enum VoiceTimingLogger {
    private static let lock = NSLock()
    private static var activeSessionID: UUID?
    private static var startedAt: TimeInterval = 0
    private static var timeline: [String: UInt64] = [:]
    private static var frontEdgeUnderrunStats = P1A5FrontEdgeUnderrunStats()

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
        let timelineEvent: String?
        switch event {
        case "STOP_REQUESTED": timelineEvent = "T5_stop_requested"
        case "AUDIO_DRAIN_BEGIN": timelineEvent = "T6_audio_drain_begin"
        case "DRAIN_FINISH": timelineEvent = "T7_audio_drain_end"
        case "AUDIO_PIPELINE_CLOSED": timelineEvent = "T8_audio_pipeline_closed"
        default: timelineEvent = nil
        }
        if let timelineEvent {
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

    static func end(sessionID: UUID) {
        lock.lock()
        if activeSessionID == sessionID {
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
            "T6_audio_drain_begin",
            "T7_audio_drain_end",
            "T8_audio_pipeline_closed"
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
        activeSessionID = nil
        eventSink(false)
        return true
    }

    @discardableResult
    func abort(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        let wasDown = isOptionDown
        isOptionDown = false
        activeSessionID = nil
        if wasDown {
            eventSink(false)
        }
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
