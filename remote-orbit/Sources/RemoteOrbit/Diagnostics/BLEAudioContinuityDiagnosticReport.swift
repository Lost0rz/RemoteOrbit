import Foundation

enum BLEAudioContinuityDiagnosticReport {
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
        let handlerStart = summaryObject.flatMap {
            unsigned($0["hold_confirmed_timestamp_nanoseconds"])
        }
        let streamID = summaryObject.flatMap {
            unsigned($0["audio_stream_id"])
        }

        let points = relevant
            .filter { $0.eventType == "voice.session.trace" }
            .flatMap { event -> [LongTermObservationPoint] in
                guard case .array(let observations)? = event.payload["observations"] else {
                    return []
                }
                return observations.compactMap(parsePoint)
            }
        guard !points.isEmpty else { return nil }

        let analysis = BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: audioStart,
            handlerStartNanoseconds: handlerStart,
            streamID: streamID
        )
        return [
            "session_id": sessionID,
            "stream_id": streamID.map { NSNumber(value: $0) as Any } ?? NSNull(),
            "metric": "ble_arrival_to_pcm_submit",
            "handler_latency": [
                "sample_count": analysis.handlerLatency.sampleCount,
                "p50_us": analysis.handlerLatency.p50Microseconds,
                "p95_us": analysis.handlerLatency.p95Microseconds,
                "p99_us": analysis.handlerLatency.p99Microseconds,
                "max_us": analysis.handlerLatency.maxMicroseconds,
                "gt5ms": analysis.handlerLatency.over5Milliseconds,
                "gt10ms": analysis.handlerLatency.over10Milliseconds,
                "gt15ms": analysis.handlerLatency.over15Milliseconds,
            ],
            "supply_windows": analysis.supplyWindows.map { window in
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
                ] as [String: Any]
            },
        ]
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
}
