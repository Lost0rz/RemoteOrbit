import Foundation

enum AudioSupplyStatisticsProducer: String, Equatable, Sendable {
    case voiceService = "voice_service"
    case audioPipe = "audio_pipe"
}

enum AudioSupplyInvalidReason: UInt16, CaseIterable, Sendable {
    case voiceServiceSequenceGap = 1
    case voiceServiceTimestampOutOfOrder = 2
    case voiceServiceObservationDrop = 4
    case audioPipeSequenceGap = 8
    case audioPipeTimestampOutOfOrder = 16
    case audioPipeObservationDrop = 32
    case coreAudioMailboxOverflow = 64
    case statisticsRingOverwrite = 128
    case incompleteBoundaryWindow = 256
    case audioPipeWindowMissing = 512
    case audioPipeQueueDepthMissing = 1024
    case producerTimestampMissing = 2048
    case voiceServiceWindowMissing = 4096

    var diagnosticName: String {
        switch self {
        case .voiceServiceSequenceGap: return "voice_service_source_sequence_gap"
        case .voiceServiceTimestampOutOfOrder: return "voice_service_timestamp_out_of_order"
        case .voiceServiceObservationDrop: return "voice_service_diagnostic_observation_drop"
        case .audioPipeSequenceGap: return "audio_pipe_source_sequence_gap"
        case .audioPipeTimestampOutOfOrder: return "audio_pipe_timestamp_out_of_order"
        case .audioPipeObservationDrop: return "audio_pipe_diagnostic_observation_drop"
        case .coreAudioMailboxOverflow: return "coreaudio_mailbox_overflow"
        case .statisticsRingOverwrite: return "statistics_ring_overwrite"
        case .incompleteBoundaryWindow: return "incomplete_boundary_window"
        case .audioPipeWindowMissing: return "audio_pipe_window_missing"
        case .audioPipeQueueDepthMissing: return "audio_pipe_queue_depth_missing"
        case .producerTimestampMissing: return "producer_timestamp_missing"
        case .voiceServiceWindowMissing: return "voice_service_window_missing"
        }
    }
}

struct AudioSupplyStatisticsWindow: Equatable, Sendable {
    let second: UInt64
    var notificationCount: UInt64 = 0
    var notificationGapCount: UInt64 = 0
    var notificationGapTotalNanoseconds: UInt64 = 0
    var notificationGapMaxNanoseconds: UInt64 = 0
    var decodedPCMSamples: UInt64 = 0
    var queueObservationCount: UInt64 = 0
    var renderObservationCount: UInt64 = 0
    var queueStartDepthFrames: UInt64?
    var queueEndDepthFrames: UInt64?
    var activeUnderrunFrames: UInt64 = 0
    var invalidReasonMask: UInt16 = 0

    var invalidReasons: [String] {
        AudioSupplyInvalidReason.allCases
            .filter { invalidReasonMask & $0.rawValue != 0 }
            .map(\.diagnosticName)
    }

    mutating func invalidate(_ reason: AudioSupplyInvalidReason) {
        invalidReasonMask |= reason.rawValue
    }
}

struct AudioSupplyStatisticsInvalidRange: Equatable, Sendable {
    let firstSecond: UInt64
    let lastSecond: UInt64
    let producer: AudioSupplyStatisticsProducer
    let reason: String
}

struct AudioSupplyProducerStatisticsSnapshot: Equatable, Sendable {
    let producer: AudioSupplyStatisticsProducer
    let sessionStartNanoseconds: UInt64
    let sessionEndNanoseconds: UInt64
    let windows: [AudioSupplyStatisticsWindow]
    let ringOverwriteCount: UInt64
    let invalidRanges: [AudioSupplyStatisticsInvalidRange]
    let sequenceGapCount: UInt64
    let timestampOutOfOrderCount: UInt64
    let missingTimestampCount: UInt64
}

struct AudioSupplyStatisticsSnapshot: Equatable, Sendable {
    let sessionStartNanoseconds: UInt64?
    let sessionEndNanoseconds: UInt64?
    let windows: [AudioSupplyStatisticsWindow]
    let ringOverwriteCount: UInt64
    let invalidRanges: [AudioSupplyStatisticsInvalidRange]
    let effectiveSourceHzBySecond: [UInt64: UInt64]
    let voiceServiceSequenceGapCount: UInt64
    let voiceServiceTimestampOutOfOrderCount: UInt64
    let voiceServiceMissingTimestampCount: UInt64
    let audioPipeSequenceGapCount: UInt64
    let audioPipeTimestampOutOfOrderCount: UInt64
    let audioPipeMissingTimestampCount: UInt64

    func toDiagnosticJSONValue() -> DiagnosticJSONValue {
        .object([
            "session_start_timestamp_nanoseconds": sessionStartNanoseconds.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
            "session_end_timestamp_nanoseconds": sessionEndNanoseconds.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
            "window_width_nanoseconds": .unsignedInteger(AudioSupplyStatisticsRing.windowWidthNanoseconds),
            "capacity_windows": .unsignedInteger(UInt64(AudioSupplyStatisticsRing.capacity)),
            "ring_overwrite_count": .unsignedInteger(ringOverwriteCount),
            "producer_sequence_gap_counts": .object([
                "voice_service": .unsignedInteger(voiceServiceSequenceGapCount),
                "audio_pipe": .unsignedInteger(audioPipeSequenceGapCount),
            ]),
            "producer_timestamp_out_of_order_counts": .object([
                "voice_service": .unsignedInteger(voiceServiceTimestampOutOfOrderCount),
                "audio_pipe": .unsignedInteger(audioPipeTimestampOutOfOrderCount),
            ]),
            "producer_missing_timestamp_counts": .object([
                "voice_service": .unsignedInteger(voiceServiceMissingTimestampCount),
                "audio_pipe": .unsignedInteger(audioPipeMissingTimestampCount),
            ]),
            "invalid_window_ranges": .array(invalidRanges.map { range in
                .object([
                    "first_second": .unsignedInteger(range.firstSecond),
                    "last_second": .unsignedInteger(range.lastSecond),
                    "producer": .string(range.producer.rawValue),
                    "reason": .string(range.reason),
                    "validity": .string("INVALID"),
                ])
            }),
            "windows": .array(windows.map { window in
                let effectiveHz = effectiveSourceHzBySecond[window.second]
                let reasons = window.invalidReasons
                return .object([
                    "second": .unsignedInteger(window.second),
                    "validity": .string(reasons.isEmpty ? "VALID" : "INVALID"),
                    "invalid_reasons": .array(reasons.map(DiagnosticJSONValue.string)),
                    "ble_notification_count": .unsignedInteger(window.notificationCount),
                    "ble_notification_gap_count": .unsignedInteger(window.notificationGapCount),
                    "ble_notification_gap_total_nanoseconds": .unsignedInteger(window.notificationGapTotalNanoseconds),
                    "ble_notification_gap_max_nanoseconds": .unsignedInteger(window.notificationGapMaxNanoseconds),
                    "decoded_pcm_samples": .unsignedInteger(window.decodedPCMSamples),
                    "effective_source_hz": effectiveHz.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
                    "audio_pipe_queue_observation_count": .unsignedInteger(window.queueObservationCount),
                    "audio_pipe_render_observation_count": .unsignedInteger(window.renderObservationCount),
                    "audio_pipe_queue_start_depth_frames": window.queueStartDepthFrames.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
                    "audio_pipe_queue_end_depth_frames": window.queueEndDepthFrames.map(DiagnosticJSONValue.unsignedInteger) ?? .null,
                    "active_underrun_frames": .unsignedInteger(window.activeUnderrunFrames),
                ])
            }),
        ])
    }
}

/// A per-producer ring of 64 session-relative one-second windows. Producers
/// append from their existing non-realtime ownership path; snapshots are joined
/// only after both producer streams have been detached.
struct AudioSupplyStatisticsRing: Equatable, Sendable {
    static let capacity = 64
    static let windowWidthNanoseconds: UInt64 = 1_000_000_000

    private let producer: AudioSupplyStatisticsProducer
    private let sessionStartNanoseconds: UInt64
    private var slots: [AudioSupplyStatisticsWindow?]
    private var lastSequence: UInt64 = 0
    private var lastTimestampNanoseconds: UInt64?
    private var ringOverwriteCount: UInt64 = 0
    private var overwrittenFirstSecond: UInt64?
    private var overwrittenLastSecond: UInt64?
    private var sequenceGapCount: UInt64 = 0
    private var timestampOutOfOrderCount: UInt64 = 0
    private var missingTimestampCount: UInt64 = 0

    init(
        producer: AudioSupplyStatisticsProducer,
        sessionStartNanoseconds: UInt64,
        initialSequence: UInt64 = 0
    ) {
        self.producer = producer
        self.sessionStartNanoseconds = sessionStartNanoseconds
        lastSequence = initialSequence
        slots = Array(repeating: nil, count: Self.capacity)
    }

    mutating func record(_ point: LongTermObservationPoint, gapNanoseconds: UInt64? = nil) {
        guard point.source == producer.rawValue else { return }
        guard let second = secondIndex(for: point.timestampNanoseconds) else {
            missingTimestampCount &+= 1
            return
        }
        var window = slot(for: second)
        window.invalidReasonMask |= validateSequence(point)

        switch producer {
        case .voiceService:
            switch point.kind {
            case .bleArrival:
                window.notificationCount &+= 1
                if let gapNanoseconds, gapNanoseconds > 0 {
                    window.notificationGapCount &+= 1
                    window.notificationGapTotalNanoseconds &+= gapNanoseconds
                    window.notificationGapMaxNanoseconds = max(
                        window.notificationGapMaxNanoseconds,
                        gapNanoseconds
                    )
                }
            case .decodeComplete:
                window.decodedPCMSamples &+= point.byteOrSampleCount
            default:
                break
            }
        case .audioPipe:
            switch point.kind {
            case .pcmSubmitted, .render:
                window.queueObservationCount &+= 1
                if point.kind == .render { window.renderObservationCount &+= 1 }
                if window.queueStartDepthFrames == nil {
                    window.queueStartDepthFrames = point.queueDepthBeforeFrames
                }
                window.queueEndDepthFrames = point.queueDepthAfterFrames
                if point.kind == .render,
                   point.marker == .active {
                    window.activeUnderrunFrames &+= point.unfilledFrames
                }
            default:
                break
            }
        }
        store(window)
    }

    mutating func recordMissingTimestamp() {
        missingTimestampCount &+= 1
    }

    mutating func invalidate(
        timestampNanoseconds: UInt64,
        reason: AudioSupplyInvalidReason
    ) {
        guard let second = secondIndex(for: timestampNanoseconds) else {
            missingTimestampCount &+= 1
            return
        }
        var window = slot(for: second)
        window.invalidate(reason)
        store(window)
    }

    mutating func invalidate(
        from firstTimestampNanoseconds: UInt64,
        through lastTimestampNanoseconds: UInt64,
        reason: AudioSupplyInvalidReason
    ) {
        guard let first = secondIndex(for: firstTimestampNanoseconds),
              let last = secondIndex(for: lastTimestampNanoseconds) else {
            missingTimestampCount &+= 1
            return
        }
        let lower = min(first, last)
        let upper = max(first, last)
        let retainedStart = upper >= UInt64(Self.capacity - 1)
            ? upper - UInt64(Self.capacity - 1)
            : 0
        if lower < retainedStart {
            recordOverwrittenRange(lower, min(upper, retainedStart - 1))
        }
        let boundedLower = max(lower, retainedStart)
        guard boundedLower <= upper else { return }
        for second in boundedLower...upper {
            var window = slot(for: second)
            window.invalidate(reason)
            store(window)
        }
    }

    mutating func snapshot(through sessionEndNanoseconds: UInt64) -> AudioSupplyProducerStatisticsSnapshot {
        let elapsed = sessionEndNanoseconds >= sessionStartNanoseconds
            ? sessionEndNanoseconds - sessionStartNanoseconds
            : 0
        let lastSecond = elapsed == 0
            ? 0
            : (elapsed - 1) / Self.windowWidthNanoseconds
        let retainedFirst = lastSecond >= UInt64(Self.capacity - 1)
            ? lastSecond - UInt64(Self.capacity - 1)
            : 0
        if retainedFirst > 0 {
            recordOverwrittenRange(0, retainedFirst - 1)
        }
        if retainedFirst <= lastSecond {
            for second in retainedFirst...lastSecond {
                var window = slot(for: second)
                let windowEnd = sessionStartNanoseconds
                    &+ ((second &+ 1) &* Self.windowWidthNanoseconds)
                if windowEnd > sessionEndNanoseconds {
                    window.invalidate(.incompleteBoundaryWindow)
                }
                if producer == .audioPipe, window.renderObservationCount == 0 {
                    window.invalidate(.audioPipeWindowMissing)
                }
                if producer == .audioPipe,
                   window.queueStartDepthFrames == nil || window.queueEndDepthFrames == nil {
                    window.invalidate(.audioPipeQueueDepthMissing)
                }
                store(window)
            }
        }
        if missingTimestampCount > 0, retainedFirst <= lastSecond {
            for second in retainedFirst...lastSecond {
                var window = slot(for: second)
                window.invalidate(.producerTimestampMissing)
                store(window)
            }
        }
        let windows = slots.compactMap { $0 }.sorted { $0.second < $1.second }
        let ranges: [AudioSupplyStatisticsInvalidRange] = if let first = overwrittenFirstSecond,
                                                               let last = overwrittenLastSecond {
            [AudioSupplyStatisticsInvalidRange(
                firstSecond: first,
                lastSecond: last,
                producer: producer,
                reason: "statistics_ring_overwrite"
            )]
        } else {
            []
        }
        return AudioSupplyProducerStatisticsSnapshot(
            producer: producer,
            sessionStartNanoseconds: sessionStartNanoseconds,
            sessionEndNanoseconds: sessionEndNanoseconds,
            windows: windows,
            ringOverwriteCount: ringOverwriteCount,
            invalidRanges: ranges,
            sequenceGapCount: sequenceGapCount,
            timestampOutOfOrderCount: timestampOutOfOrderCount,
            missingTimestampCount: missingTimestampCount
        )
    }

    private mutating func validateSequence(
        _ point: LongTermObservationPoint
    ) -> UInt16 {
        var reasons: UInt16 = 0
        let expected = lastSequence &+ 1
        if point.sequence != expected {
            sequenceGapCount &+= point.sequence > expected ? point.sequence - expected : 1
            let reason: AudioSupplyInvalidReason = producer == .voiceService
                ? .voiceServiceSequenceGap
                : .audioPipeSequenceGap
            reasons |= reason.rawValue
            if let lastTimestampNanoseconds {
                invalidate(
                    from: lastTimestampNanoseconds,
                    through: point.timestampNanoseconds,
                    reason: reason
                )
            }
        }
        if let lastTimestampNanoseconds,
           point.timestampNanoseconds < lastTimestampNanoseconds {
            timestampOutOfOrderCount &+= 1
            let reason: AudioSupplyInvalidReason = producer == .voiceService
                ? .voiceServiceTimestampOutOfOrder
                : .audioPipeTimestampOutOfOrder
            reasons |= reason.rawValue
            invalidate(
                timestampNanoseconds: lastTimestampNanoseconds,
                reason: reason
            )
        }
        lastSequence = max(lastSequence, point.sequence)
        if lastTimestampNanoseconds == nil
            || point.timestampNanoseconds > lastTimestampNanoseconds! {
            lastTimestampNanoseconds = point.timestampNanoseconds
        }
        return reasons
    }

    private func secondIndex(for timestampNanoseconds: UInt64) -> UInt64? {
        guard timestampNanoseconds >= sessionStartNanoseconds else { return nil }
        return (timestampNanoseconds - sessionStartNanoseconds) / Self.windowWidthNanoseconds
    }

    private mutating func slot(for second: UInt64) -> AudioSupplyStatisticsWindow {
        let index = Int(second % UInt64(Self.capacity))
        if let existing = slots[index], existing.second == second { return existing }
        if let existing = slots[index] {
            if existing.second > second {
                recordOverwrittenRange(second, second)
                var unavailable = AudioSupplyStatisticsWindow(second: second)
                unavailable.invalidate(.statisticsRingOverwrite)
                return unavailable
            }
            recordOverwrittenRange(existing.second, existing.second)
        }
        let window = AudioSupplyStatisticsWindow(second: second)
        slots[index] = window
        return window
    }

    private mutating func store(_ window: AudioSupplyStatisticsWindow) {
        let index = Int(window.second % UInt64(Self.capacity))
        if let existing = slots[index], existing.second > window.second { return }
        slots[index] = window
    }

    private mutating func recordOverwrittenRange(_ first: UInt64, _ last: UInt64) {
        guard first <= last else { return }
        overwrittenFirstSecond = min(overwrittenFirstSecond ?? first, first)
        overwrittenLastSecond = max(overwrittenLastSecond ?? last, last)
        let rangeCount = (overwrittenLastSecond ?? last)
            &- (overwrittenFirstSecond ?? first)
            &+ 1
        ringOverwriteCount = max(ringOverwriteCount, rangeCount)
    }
}

extension AudioSupplyStatisticsSnapshot {
    static func join(
        voiceService: AudioSupplyProducerStatisticsSnapshot?,
        audioPipe: AudioSupplyProducerStatisticsSnapshot?,
        sessionEndNanoseconds: UInt64?
    ) -> AudioSupplyStatisticsSnapshot {
        guard let voiceService, let audioPipe,
              voiceService.sessionStartNanoseconds == audioPipe.sessionStartNanoseconds,
              let sessionEndNanoseconds else {
            return AudioSupplyStatisticsSnapshot(
                sessionStartNanoseconds: voiceService?.sessionStartNanoseconds
                    ?? audioPipe?.sessionStartNanoseconds,
                sessionEndNanoseconds: sessionEndNanoseconds,
                windows: [],
                ringOverwriteCount: (voiceService?.ringOverwriteCount ?? 0)
                    &+ (audioPipe?.ringOverwriteCount ?? 0),
                invalidRanges: (voiceService?.invalidRanges ?? []) + (audioPipe?.invalidRanges ?? []),
                effectiveSourceHzBySecond: [:],
                voiceServiceSequenceGapCount: voiceService?.sequenceGapCount ?? 0,
                voiceServiceTimestampOutOfOrderCount: voiceService?.timestampOutOfOrderCount ?? 0,
                voiceServiceMissingTimestampCount: voiceService?.missingTimestampCount ?? 0,
                audioPipeSequenceGapCount: audioPipe?.sequenceGapCount ?? 0,
                audioPipeTimestampOutOfOrderCount: audioPipe?.timestampOutOfOrderCount ?? 0,
                audioPipeMissingTimestampCount: audioPipe?.missingTimestampCount ?? 0
            )
        }

        let serviceBySecond = Dictionary(uniqueKeysWithValues: voiceService.windows.map { ($0.second, $0) })
        let pipeBySecond = Dictionary(uniqueKeysWithValues: audioPipe.windows.map { ($0.second, $0) })
        let allSeconds = Set(serviceBySecond.keys).union(pipeBySecond.keys).sorted()
        var windows: [AudioSupplyStatisticsWindow] = []
        windows.reserveCapacity(allSeconds.count)
        var effectiveSourceHz: [UInt64: UInt64] = [:]
        for second in allSeconds {
            var joined = AudioSupplyStatisticsWindow(second: second)
            if let service = serviceBySecond[second] {
                joined.notificationCount = service.notificationCount
                joined.notificationGapCount = service.notificationGapCount
                joined.notificationGapTotalNanoseconds = service.notificationGapTotalNanoseconds
                joined.notificationGapMaxNanoseconds = service.notificationGapMaxNanoseconds
                joined.decodedPCMSamples = service.decodedPCMSamples
                joined.invalidReasonMask |= service.invalidReasonMask
            } else {
                joined.invalidate(.voiceServiceWindowMissing)
            }
            if let pipe = pipeBySecond[second] {
                joined.queueObservationCount = pipe.queueObservationCount
                joined.renderObservationCount = pipe.renderObservationCount
                joined.queueStartDepthFrames = pipe.queueStartDepthFrames
                joined.queueEndDepthFrames = pipe.queueEndDepthFrames
                joined.activeUnderrunFrames = pipe.activeUnderrunFrames
                joined.invalidReasonMask |= pipe.invalidReasonMask
            } else {
                joined.invalidate(.audioPipeWindowMissing)
            }
            let end = voiceService.sessionStartNanoseconds
                &+ ((second &+ 1) &* AudioSupplyStatisticsRing.windowWidthNanoseconds)
            if end > sessionEndNanoseconds {
                joined.invalidate(.incompleteBoundaryWindow)
            }
            if joined.invalidReasonMask == 0 {
                effectiveSourceHz[second] = joined.decodedPCMSamples
            }
            windows.append(joined)
        }

        return AudioSupplyStatisticsSnapshot(
            sessionStartNanoseconds: voiceService.sessionStartNanoseconds,
            sessionEndNanoseconds: sessionEndNanoseconds,
            windows: windows,
            ringOverwriteCount: voiceService.ringOverwriteCount &+ audioPipe.ringOverwriteCount,
            invalidRanges: voiceService.invalidRanges + audioPipe.invalidRanges,
            effectiveSourceHzBySecond: effectiveSourceHz,
            voiceServiceSequenceGapCount: voiceService.sequenceGapCount,
            voiceServiceTimestampOutOfOrderCount: voiceService.timestampOutOfOrderCount,
            voiceServiceMissingTimestampCount: voiceService.missingTimestampCount,
            audioPipeSequenceGapCount: audioPipe.sequenceGapCount,
            audioPipeTimestampOutOfOrderCount: audioPipe.timestampOutOfOrderCount,
            audioPipeMissingTimestampCount: audioPipe.missingTimestampCount
        )
    }
}
