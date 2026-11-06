import Foundation

enum BLEAudioContinuityDiagnosticReport {
    private static let statisticsKey = "per_second_audio_supply_statistics"

    static func make(
        events: [DiagnosticEvent],
        sessionID: String
    ) -> [String: Any]? {
        let relevant = events.filter { $0.sessionID == sessionID }
        let summaryObject = relevant
            .first(where: { $0.eventType == "voice.session.summary" })
            .flatMap { object($0.payload["summary"]) }
        let audioStart = summaryObject.flatMap {
            unsigned($0["audio_start_timestamp_nanoseconds"])
        }
        let activeStart = summaryObject.flatMap {
            unsigned($0["hold_confirmed_timestamp_nanoseconds"])
        }
        let streamID = summaryObject.flatMap {
            unsigned($0["audio_stream_id"])
        }

        let persistedStatistics = summaryObject?[statisticsKey]
        let hasStatisticsField = summaryObject?.keys.contains(statisticsKey) == true
        let statistics = persistedStatistics.flatMap(object)
        // A non-null but malformed new-format payload is not a historical session.
        // Fail closed instead of silently substituting trace-derived supply data.
        let statisticsAreNull = persistedStatistics.map {
            if case .null = $0 { return true }
            return false
        } ?? false
        guard !hasStatisticsField || statisticsAreNull || statistics != nil else {
            return nil
        }
        let statisticsWindows: [DiagnosticJSONValue]?
        if let statistics {
            guard case .array(let windows)? = statistics["windows"],
                  windows.allSatisfy({ object($0) != nil }) else { return nil }
            statisticsWindows = windows
        } else if hasStatisticsField {
            statisticsWindows = []
        } else {
            statisticsWindows = nil
        }

        let traceEvents = relevant.filter { $0.eventType == "voice.session.trace" }
        let observations = traceEvents.flatMap { event -> [DiagnosticJSONValue] in
            guard case .array(let observations)? = event.payload["observations"] else {
                return []
            }
            return observations
        }
        let points = observations.compactMap(parsePoint)
        guard hasStatisticsField || !points.isEmpty else { return nil }

        let analysis = points.isEmpty ? nil : BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: audioStart,
            handlerStartNanoseconds: activeStart,
            streamID: streamID
        )
        let trace = traceEvidence(
            events: traceEvents,
            parsedPointCount: points.count,
            unparsedObservationCount: observations.count - points.count
        )
        let latency = latencyReport(
            analysis?.ingressToSubmitLatency,
            traceStatus: trace.status
        )

        let supplyWindows: [[String: Any]]
        let supplyWindowSource: String
        if let statisticsWindows {
            supplyWindowSource = statisticsKey
            supplyWindows = statisticsWindows.map(dictionaryValue)
        } else {
            supplyWindowSource = "legacy_voice_session_trace"
            supplyWindows = (analysis?.supplyWindows ?? []).map { window in
                [
                    "index": window.index,
                    "start_ms": Double(window.startNanoseconds) / 1_000_000,
                    "elapsed_ms": window.elapsedMilliseconds,
                    "decoded_samples": window.decodedSamples,
                    "effective_source_hz": window.traceContiguous
                        ? window.effectiveSourceHz as Any
                        : NSNull(),
                    "notifications": window.notificationCount,
                    "max_notification_gap_ms": window.maxNotificationGapMilliseconds,
                    "queue_start_frames": window.queueDepthStartFrames.map { NSNumber(value: $0) as Any } ?? NSNull(),
                    "queue_end_frames": window.queueDepthEndFrames.map { NSNumber(value: $0) as Any } ?? NSNull(),
                    "trace_contiguous": window.traceContiguous,
                    "validity": window.traceContiguous ? "LEGACY_CONTIGUOUS" : "LEGACY_INCOMPLETE",
                    "evidence_source": "legacy_voice_session_trace",
                ] as [String: Any]
            }
        }

        return [
            "report_schema_version": 2,
            "session_id": sessionID,
            "stream_id": streamID.map { NSNumber(value: $0) as Any } ?? NSNull(),
            "supply_window_source": supplyWindowSource,
            "legacy_only": !hasStatisticsField,
            "supply_statistics_status": statistics == nil ? "UNAVAILABLE" : "AVAILABLE",
            statisticsKey: statistics.map { foundationValue(.object($0)) } ?? NSNull(),
            "supply_windows": supplyWindows,
            "legacy_trace_evidence": trace.dictionary,
            // Kept for the existing CLI consumer shape; the fields explicitly mark
            // this latency view as supplemental trace evidence, never supply data.
            "ingress_to_submit_latency": latency,
        ]
    }

    private static func latencyReport(
        _ summary: BLEAudioHandlerLatencySummary?,
        traceStatus: String
    ) -> [String: Any] {
        let sampleCount = summary?.sampleCount ?? 0
        let hasSamples = sampleCount > 0
        return [
            "metric": "ble_arrival_to_pcm_submit",
            "role": "supplemental",
            "evidence_source": "legacy_voice_session_trace",
            "trace_status": traceStatus,
            "sample_count": sampleCount,
            "p50_us": hasSamples ? summary?.p50Microseconds as Any : NSNull(),
            "p95_us": hasSamples ? summary?.p95Microseconds as Any : NSNull(),
            "p99_us": hasSamples ? summary?.p99Microseconds as Any : NSNull(),
            "max_us": hasSamples ? summary?.maxMicroseconds as Any : NSNull(),
            "gt5ms": summary?.over5Milliseconds ?? 0,
            "gt10ms": summary?.over10Milliseconds ?? 0,
            "gt15ms": summary?.over15Milliseconds ?? 0,
        ]
    }

    private static func traceEvidence(
        events: [DiagnosticEvent],
        parsedPointCount: Int,
        unparsedObservationCount: Int
    ) -> TraceEvidence {
        guard !events.isEmpty else {
            return TraceEvidence(
                status: "MISSING",
                expectedChunkCount: nil,
                observedChunkCount: 0,
                droppedObservationCount: 0,
                unparsedObservationCount: 0
            )
        }

        let captureGroups = Dictionary(grouping: events) {
            string($0.payload["capture_id"]) ?? "__missing_capture_id__"
        }
        var expectedChunkCount: UInt64 = 0
        var observedChunkCount = 0
        var chunksComplete = true
        for captureEvents in captureGroups.values {
            let chunkCounts = Set(captureEvents.compactMap {
                unsigned($0.payload["chunk_count"])
            })
            guard chunkCounts.count == 1,
                  let expected = chunkCounts.first,
                  expected > 0,
                  expected <= UInt64(Int.max) else {
                chunksComplete = false
                continue
            }
            let indexes = Set(captureEvents.compactMap { event -> UInt64? in
                guard let index = unsigned(event.payload["chunk_index"]),
                      index < expected else { return nil }
                return index
            })
            expectedChunkCount = saturatingAdd(expectedChunkCount, expected)
            observedChunkCount += indexes.count
            chunksComplete = chunksComplete && indexes.count == Int(expected)
        }
        let droppedObservationCount = events.reduce(UInt64(0)) { total, event in
            let dropped = unsigned(event.payload["dropped_observations"]) ?? 0
            let (sum, overflow) = total.addingReportingOverflow(dropped)
            return overflow ? UInt64.max : sum
        }
        let complete = parsedPointCount > 0
            && unparsedObservationCount == 0
            && expectedChunkCount > 0
            && chunksComplete
            && droppedObservationCount == 0
        return TraceEvidence(
            status: complete ? "COMPLETE" : "INCOMPLETE",
            expectedChunkCount: expectedChunkCount > 0 ? expectedChunkCount : nil,
            observedChunkCount: observedChunkCount,
            droppedObservationCount: droppedObservationCount,
            unparsedObservationCount: unparsedObservationCount
        )
    }

    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }

    private struct TraceEvidence {
        let status: String
        let expectedChunkCount: UInt64?
        let observedChunkCount: Int
        let droppedObservationCount: UInt64
        let unparsedObservationCount: Int

        var dictionary: [String: Any] {
            [
                "status": status,
                "expected_chunk_count": expectedChunkCount.map { NSNumber(value: $0) as Any } ?? NSNull(),
                "observed_chunk_count": observedChunkCount,
                "dropped_observation_count": droppedObservationCount,
                "unparsed_observation_count": unparsedObservationCount,
            ]
        }
    }

    private static func parsePoint(_ value: DiagnosticJSONValue) -> LongTermObservationPoint? {
        guard let fields = object(value),
              let timestamp = unsigned(fields["timestamp_nanoseconds"]),
              let kindName = string(fields["kind"]),
              let kind = LongTermObservationKind(rawValue: kindName),
              let requested = unsigned(fields["requested_frames"]),
              let filled = unsigned(fields["filled_frames"]),
              let unfilled = unsigned(fields["unfilled_frames"]),
              let queueAfter = unsigned(fields["queue_depth_after_frames"]),
              let count = unsigned(fields["byte_or_sample_count"]),
              let markerName = string(fields["marker"]),
              let marker = LongTermObservationSemanticMarker(rawValue: markerName),
              let streamIdentity = unsigned(fields["stream_identity"]),
              let source = string(fields["source"]),
              let sequence = unsigned(fields["source_sequence"])
        else {
            return nil
        }
        return LongTermObservationPoint(
            timestampNanoseconds: timestamp,
            kind: kind,
            requestedFrames: requested,
            filledFrames: filled,
            unfilledFrames: unfilled,
            queueDepthFrames: queueAfter,
            byteOrSampleCount: count,
            marker: marker,
            streamIdentity: streamIdentity,
            sequence: sequence,
            queueDepthBeforeFrames: optionalUnsigned(fields["queue_depth_before_frames"]),
            source: source
        )
    }

    private static func object(
        _ value: DiagnosticJSONValue?
    ) -> [String: DiagnosticJSONValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }

    private static func object(
        _ value: DiagnosticJSONValue
    ) -> [String: DiagnosticJSONValue]? {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private static func string(_ value: DiagnosticJSONValue?) -> String? {
        guard case .string(let string)? = value else { return nil }
        return string
    }

    private static func unsigned(_ value: DiagnosticJSONValue?) -> UInt64? {
        guard let value else { return nil }
        switch value {
        case .unsignedInteger(let number):
            return number
        case .integer(let number) where number >= 0:
            return UInt64(number)
        default:
            return nil
        }
    }

    private static func optionalUnsigned(_ value: DiagnosticJSONValue?) -> UInt64? {
        guard let value else { return nil }
        if case .null = value { return nil }
        return unsigned(value)
    }

    private static func foundationValue(_ value: DiagnosticJSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let value):
            return NSNumber(value: value)
        case .integer(let value):
            return NSNumber(value: value)
        case .unsignedInteger(let value):
            return NSNumber(value: value)
        case .double(let value):
            return NSNumber(value: value)
        case .string(let value):
            return value
        case .array(let values):
            return values.map(foundationValue)
        case .object(let values):
            return values.mapValues(foundationValue)
        }
    }

    private static func dictionaryValue(_ value: DiagnosticJSONValue) -> [String: Any] {
        guard case .object(let object) = value else { return [:] }
        return object.mapValues(foundationValue)
    }
}
