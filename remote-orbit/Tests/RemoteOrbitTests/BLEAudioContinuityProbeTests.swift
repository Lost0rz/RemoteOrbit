import XCTest
@testable import RemoteOrbit

final class BLEAudioContinuityProbeTests: XCTestCase {
    func testHandlerTelemetryUsesFixedBucketsAndThresholdCounts() {
        var telemetry = BLEAudioHandlerTelemetry()
        telemetry.reset()
        for index in 0..<100 {
            telemetry.record(
                durationNanoseconds: UInt64(index) * 250_000 + 100_000
            )
        }

        let summary = telemetry.summary()
        XCTAssertEqual(summary.sampleCount, 100)
        XCTAssertEqual(summary.p50Microseconds, 12_500)
        XCTAssertEqual(summary.p95Microseconds, 23_750)
        XCTAssertEqual(summary.p99Microseconds, 24_750)
        XCTAssertEqual(summary.maxMicroseconds, 24_850)
        XCTAssertEqual(summary.over5Milliseconds, 80)
        XCTAssertEqual(summary.over10Milliseconds, 60)
        XCTAssertEqual(summary.over15Milliseconds, 40)
    }

    func testHandlerTelemetryOverflowUsesObservedMaximumForHighPercentile() {
        var telemetry = BLEAudioHandlerTelemetry()
        telemetry.reset()
        telemetry.record(durationNanoseconds: 1_000_000)
        telemetry.record(durationNanoseconds: 50_000_000)

        let summary = telemetry.summary()
        XCTAssertEqual(summary.sampleCount, 2)
        XCTAssertEqual(summary.p99Microseconds, 50_000)
        XCTAssertEqual(summary.maxMicroseconds, 50_000)
        XCTAssertEqual(summary.over15Milliseconds, 1)
    }

    func testIngressToSubmitSummaryPairsBLEArrivalToNextPCMSubmit() {
        var points: [LongTermObservationPoint] = []
        for millisecond in 1...100 {
            let arrival = UInt64(millisecond) * 200_000_000
            points.append(point(
                timestamp: arrival,
                kind: .bleArrival,
                source: "voice_service",
                sequence: UInt64(millisecond * 2 - 1)
            ))
            points.append(point(
                timestamp: arrival + UInt64(millisecond) * 1_000_000,
                kind: .pcmSubmitted,
                source: "audio_pipe",
                sequence: UInt64(millisecond * 2)
            ))
        }

        let summary = BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: nil,
            streamID: 1
        ).ingressToSubmitLatency

        XCTAssertEqual(summary.sampleCount, 100)
        XCTAssertEqual(summary.p50Microseconds, 50_000)
        XCTAssertEqual(summary.p95Microseconds, 95_000)
        XCTAssertEqual(summary.p99Microseconds, 99_000)
        XCTAssertEqual(summary.maxMicroseconds, 100_000)
        XCTAssertEqual(summary.over5Milliseconds, 95)
        XCTAssertEqual(summary.over10Milliseconds, 90)
        XCTAssertEqual(summary.over15Milliseconds, 85)
    }

    func testIngressToSubmitSummaryExcludesPreHIDCandidateDwell() {
        let points = [
            point(timestamp: 100_000_000, kind: .bleArrival, source: "voice_service", sequence: 1),
            point(timestamp: 150_000_000, kind: .pcmSubmitted, source: "audio_pipe", sequence: 1),
            point(timestamp: 300_000_000, kind: .bleArrival, source: "voice_service", sequence: 2),
            point(timestamp: 305_000_000, kind: .pcmSubmitted, source: "audio_pipe", sequence: 2),
        ]

        let summary = BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: 100_000_000,
            handlerStartNanoseconds: 200_000_000,
            streamID: 1
        ).ingressToSubmitLatency

        XCTAssertEqual(summary.sampleCount, 1)
        XCTAssertEqual(summary.p50Microseconds, 5_000)
        XCTAssertEqual(summary.maxMicroseconds, 5_000)
    }

    func testSupplyWindowReportsEffectiveRateGapAndQueueDepth() throws {
        let start: UInt64 = 1_000_000_000
        let points = [
            point(timestamp: start, kind: .bleArrival, source: "voice_service", sequence: 1),
            point(timestamp: start + 100_000_000, kind: .decodeComplete, count: 4_000, source: "voice_service", sequence: 2),
            point(timestamp: start + 100_000_000, kind: .pcmSubmitted, queueBefore: 2_160, queueAfter: 2_000, source: "audio_pipe", sequence: 1),
            point(timestamp: start + 500_000_000, kind: .bleArrival, source: "voice_service", sequence: 3),
            point(timestamp: start + 600_000_000, kind: .decodeComplete, count: 8_000, source: "voice_service", sequence: 4),
            point(timestamp: start + 999_000_000, kind: .bleArrival, source: "voice_service", sequence: 5),
            point(timestamp: start + 999_000_000, kind: .decodeComplete, count: 4_000, source: "voice_service", sequence: 6),
            point(timestamp: start + 1_000_000_000, kind: .render, queueBefore: 1_200, queueAfter: 720, source: "audio_pipe", sequence: 2),
        ]

        let analysis = BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: start,
            streamID: 1
        )
        XCTAssertEqual(analysis.supplyWindows.count, 1)
        let window = try XCTUnwrap(analysis.supplyWindows.first)
        XCTAssertEqual(window.index, 0)
        XCTAssertEqual(window.elapsedNanoseconds, 1_000_000_000)
        XCTAssertEqual(window.decodedSamples, 16_000)
        XCTAssertEqual(window.notificationCount, 3)
        XCTAssertEqual(window.maxNotificationGapNanoseconds, 500_000_000)
        XCTAssertEqual(window.queueDepthStartFrames, 2_160)
        XCTAssertEqual(window.queueDepthEndFrames, 2_000)
        XCTAssertEqual(window.effectiveSourceHz, 16_000, accuracy: 0.001)
        XCTAssertTrue(window.traceContiguous)
    }

    func testFinalPartialWindowUsesObservedEnd() throws {
        let start: UInt64 = 5_000_000_000
        let points = [
            point(timestamp: start + 100_000_000, kind: .bleArrival, source: "voice_service", sequence: 1),
            point(timestamp: start + 100_000_000, kind: .decodeComplete, count: 3_200, source: "voice_service", sequence: 2),
            point(timestamp: start + 100_000_000, kind: .pcmSubmitted, queueBefore: 720, queueAfter: 480, source: "audio_pipe", sequence: 1),
            point(timestamp: start + 300_000_000, kind: .bleArrival, source: "voice_service", sequence: 3),
            point(timestamp: start + 300_000_000, kind: .decodeComplete, count: 1_600, source: "voice_service", sequence: 4),
            point(timestamp: start + 300_000_000, kind: .render, queueBefore: 480, queueAfter: 0, source: "audio_pipe", sequence: 2),
        ]

        let analysis = BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: start,
            streamID: 1
        )
        let window = try XCTUnwrap(analysis.supplyWindows.first)
        XCTAssertEqual(window.elapsedNanoseconds, 300_000_000)
        XCTAssertEqual(window.decodedSamples, 4_800)
        XCTAssertEqual(window.notificationCount, 2)
        XCTAssertEqual(window.effectiveSourceHz, 16_000, accuracy: 0.001)
        XCTAssertEqual(window.queueDepthStartFrames, 720)
        XCTAssertEqual(window.queueDepthEndFrames, 0)
        XCTAssertTrue(window.traceContiguous)
    }

    func testSequenceGapMarksSupplyWindowNonContiguous() throws {
        let start: UInt64 = 9_000_000_000
        let points = [
            point(timestamp: start, kind: .bleArrival, source: "voice_service", sequence: 1),
            point(timestamp: start + 100_000_000, kind: .decodeComplete, count: 3_200, source: "voice_service", sequence: 2),
            point(timestamp: start + 400_000_000, kind: .bleArrival, source: "voice_service", sequence: 10),
            point(timestamp: start + 500_000_000, kind: .decodeComplete, count: 3_200, source: "voice_service", sequence: 11),
            point(timestamp: start + 1_000_000_000, kind: .render, queueBefore: 480, queueAfter: 0, source: "audio_pipe", sequence: 1),
        ]

        let analysis = BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: start,
            streamID: 1
        )
        let window = try XCTUnwrap(analysis.supplyWindows.first)
        XCTAssertFalse(window.traceContiguous)
    }

    func testLifecyclePointDoesNotManufactureSequenceGap() throws {
        let start: UInt64 = 12_000_000_000
        let points = [
            point(timestamp: start, kind: .bleArrival, source: "voice_service", sequence: 1),
            point(timestamp: start + 100_000_000, kind: .lifecycle, source: "voice_service", sequence: 2),
            point(timestamp: start + 200_000_000, kind: .decodeComplete, count: 3_200, source: "voice_service", sequence: 3),
            point(timestamp: start + 1_000_000_000, kind: .render, queueBefore: 480, queueAfter: 0, source: "audio_pipe", sequence: 1),
        ]

        let analysis = BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: start,
            streamID: 1
        )
        let window = try XCTUnwrap(analysis.supplyWindows.first)
        XCTAssertTrue(window.traceContiguous)
    }

    func testAnalysisFiltersDifferentStreamIdentity() {
        let points = [
            point(timestamp: 100, kind: .bleArrival, source: "voice_service", sequence: 1, streamID: 1),
            point(timestamp: 200, kind: .pcmSubmitted, source: "audio_pipe", sequence: 1, streamID: 1),
            point(timestamp: 300, kind: .bleArrival, source: "voice_service", sequence: 2, streamID: 2),
            point(timestamp: 400, kind: .pcmSubmitted, source: "audio_pipe", sequence: 2, streamID: 2),
        ]
        let analysis = BLEAudioContinuityAnalysis.analyze(
            points: points,
            audioStartNanoseconds: nil,
            streamID: 1
        )
        XCTAssertEqual(analysis.ingressToSubmitLatency.sampleCount, 1)
    }

    func testAudioContinuityCLIUsesCompleteSummaryStatistics() throws {
        let windows = [statisticsWindow(
            validity: "VALID",
            decodedSamples: 16_000,
            effectiveSourceHz: .unsignedInteger(16_000)
        )]
        let report = try runAudioContinuityCLI(events: [
            summaryEvent(statistics: statisticsPayload(windows: windows)),
            traceEvent(observations: supplementalTracePoints()),
        ])

        XCTAssertEqual(report["report_schema_version"] as? Int, 2)
        XCTAssertEqual(
            report["supply_window_source"] as? String,
            "per_second_audio_supply_statistics"
        )
        XCTAssertEqual(report["legacy_only"] as? Bool, false)
        let reportWindows = try XCTUnwrap(report["supply_windows"] as? [[String: Any]])
        XCTAssertEqual(reportWindows.count, 1)
        XCTAssertEqual(reportWindows[0]["decoded_pcm_samples"] as? Int, 16_000)
        XCTAssertEqual(reportWindows[0]["effective_source_hz"] as? Int, 16_000)
        XCTAssertNil(reportWindows[0]["start_ms"])
        let persisted = try XCTUnwrap(
            report["per_second_audio_supply_statistics"] as? [String: Any]
        )
        XCTAssertEqual(persisted["ring_overwrite_count"] as? Int, 4)
        let gaps = try XCTUnwrap(
            persisted["producer_sequence_gap_counts"] as? [String: Any]
        )
        XCTAssertEqual(gaps["voice_service"] as? Int, 2)
        XCTAssertEqual(gaps["audio_pipe"] as? Int, 3)
        let outOfOrder = try XCTUnwrap(
            persisted["producer_timestamp_out_of_order_counts"] as? [String: Any]
        )
        XCTAssertEqual(outOfOrder["voice_service"] as? Int, 1)
        XCTAssertEqual(outOfOrder["audio_pipe"] as? Int, 2)
        let missingTimestamps = try XCTUnwrap(
            persisted["producer_missing_timestamp_counts"] as? [String: Any]
        )
        XCTAssertEqual(missingTimestamps["audio_pipe"] as? Int, 1)
        let latency = try XCTUnwrap(report["ingress_to_submit_latency"] as? [String: Any])
        XCTAssertEqual(latency["role"] as? String, "supplemental")
        XCTAssertEqual(latency["evidence_source"] as? String, "legacy_voice_session_trace")
    }

    func testAudioContinuityCLIReportsStatisticsWhenLegacyTraceIsMissing() throws {
        let report = try runAudioContinuityCLI(events: [
            summaryEvent(statistics: statisticsPayload(windows: [
                statisticsWindow(
                    validity: "VALID",
                    decodedSamples: 8_000,
                    effectiveSourceHz: .unsignedInteger(8_000)
                ),
            ])),
        ])

        XCTAssertEqual(report["supply_window_source"] as? String, "per_second_audio_supply_statistics")
        XCTAssertEqual((report["supply_windows"] as? [[String: Any]])?.count, 1)
        let trace = try XCTUnwrap(report["legacy_trace_evidence"] as? [String: Any])
        XCTAssertEqual(trace["status"] as? String, "MISSING")
        let latency = try XCTUnwrap(report["ingress_to_submit_latency"] as? [String: Any])
        XCTAssertEqual(latency["sample_count"] as? Int, 0)
        XCTAssertTrue(latency["p50_us"] is NSNull)
    }

    func testAudioContinuityCLIKeepsStatisticsAuthoritativeWithIncompleteTrace() throws {
        let statistics = statisticsPayload(windows: [
            statisticsWindow(
                validity: "VALID",
                decodedSamples: 16_000,
                effectiveSourceHz: .unsignedInteger(16_000)
            ),
        ])
        let report = try runAudioContinuityCLI(events: [
            summaryEvent(statistics: statistics),
            traceEvent(
                observations: supplementalTracePoints(),
                chunkIndex: 0,
                chunkCount: 2,
                droppedObservations: 1
            ),
        ])

        XCTAssertEqual(report["supply_window_source"] as? String, "per_second_audio_supply_statistics")
        let preserved = try XCTUnwrap(
            report["per_second_audio_supply_statistics"] as? [String: Any]
        )
        XCTAssertEqual(preserved["ring_overwrite_count"] as? Int, 4)
        XCTAssertEqual((preserved["windows"] as? [[String: Any]])?.first?["validity"] as? String, "VALID")
        let trace = try XCTUnwrap(report["legacy_trace_evidence"] as? [String: Any])
        XCTAssertEqual(trace["status"] as? String, "INCOMPLETE")
        XCTAssertEqual(trace["dropped_observation_count"] as? Int, 1)
        let latency = try XCTUnwrap(report["ingress_to_submit_latency"] as? [String: Any])
        XCTAssertEqual(latency["trace_status"] as? String, "INCOMPLETE")
    }

    func testAudioContinuityCLIExposesInvalidWindowAndNullRate() throws {
        let report = try runAudioContinuityCLI(events: [
            summaryEvent(statistics: statisticsPayload(windows: [
                statisticsWindow(
                    validity: "INVALID",
                    invalidReasons: ["voice_service_sequence_gap"],
                    decodedSamples: 8_000,
                    effectiveSourceHz: .null
                ),
            ])),
        ])

        let window = try XCTUnwrap((report["supply_windows"] as? [[String: Any]])?.first)
        XCTAssertEqual(window["validity"] as? String, "INVALID")
        XCTAssertEqual(window["invalid_reasons"] as? [String], ["voice_service_sequence_gap"])
        XCTAssertTrue(window["effective_source_hz"] is NSNull)
    }

    func testAudioContinuityCLISeparatesValidZeroSupplyFromMissingEvidence() throws {
        let report = try runAudioContinuityCLI(events: [
            summaryEvent(statistics: statisticsPayload(windows: [
                statisticsWindow(
                    validity: "VALID",
                    decodedSamples: 0,
                    effectiveSourceHz: .unsignedInteger(0)
                ),
            ])),
        ])

        let window = try XCTUnwrap((report["supply_windows"] as? [[String: Any]])?.first)
        XCTAssertEqual(window["validity"] as? String, "VALID")
        XCTAssertEqual(window["decoded_pcm_samples"] as? Int, 0)
        XCTAssertEqual(window["effective_source_hz"] as? Int, 0)
    }

    func testAudioContinuityCLILabelsHistoricalLegacyOnlySession() throws {
        let report = try runAudioContinuityCLI(events: [
            summaryEvent(statistics: .null, includeStatisticsField: false),
            traceEvent(observations: supplementalTracePoints()),
        ])

        XCTAssertEqual(report["supply_window_source"] as? String, "legacy_voice_session_trace")
        XCTAssertEqual(report["legacy_only"] as? Bool, true)
        XCTAssertTrue(report["per_second_audio_supply_statistics"] is NSNull)
        let windows = try XCTUnwrap(report["supply_windows"] as? [[String: Any]])
        XCTAssertFalse(windows.isEmpty)
        XCTAssertEqual(windows[0]["evidence_source"] as? String, "legacy_voice_session_trace")
        XCTAssertEqual(windows[0]["validity"] as? String, "LEGACY_CONTIGUOUS")
    }

    func testAudioContinuityCLIDoesNotTreatNewFormatNullAsHistorical() throws {
        let report = try runAudioContinuityCLI(events: [
            summaryEvent(statistics: .null),
            traceEvent(observations: supplementalTracePoints()),
        ])

        XCTAssertEqual(report["supply_window_source"] as? String, "per_second_audio_supply_statistics")
        XCTAssertEqual(report["legacy_only"] as? Bool, false)
        XCTAssertEqual(report["supply_statistics_status"] as? String, "UNAVAILABLE")
        XCTAssertTrue(report["per_second_audio_supply_statistics"] is NSNull)
        XCTAssertTrue((report["supply_windows"] as? [[String: Any]])?.isEmpty == true)
    }

    private func runAudioContinuityCLI(events: [DiagnosticEvent]) throws -> [String: Any] {
        var output: String?
        var errors: [String] = []
        let status = DiagnosticCLI.run(
            arguments: ["audio-continuity", "--session", "session-1"],
            authority: FixtureDiagnosticAuthority(events: events),
            journalURL: URL(fileURLWithPath: "/tmp/remoteorbit-cli-fixture.jsonl"),
            output: { output = $0 },
            errorOutput: { errors.append($0) }
        )
        XCTAssertEqual(status, 0, errors.joined(separator: "\n"))
        XCTAssertTrue(errors.isEmpty)
        let data = try XCTUnwrap(output?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func summaryEvent(
        statistics: DiagnosticJSONValue,
        includeStatisticsField: Bool = true
    ) -> DiagnosticEvent {
        var summary: [String: DiagnosticJSONValue] = [
            "audio_start_timestamp_nanoseconds": .unsignedInteger(1_000_000_000),
            "hold_confirmed_timestamp_nanoseconds": .unsignedInteger(1_000_000_000),
            "audio_stream_id": .unsignedInteger(7),
        ]
        if includeStatisticsField {
            summary["per_second_audio_supply_statistics"] = statistics
        }
        return makeEvent(
            eventType: "voice.session.summary",
            category: "summary",
            severity: .info,
            payload: ["summary": .object(summary)]
        )
    }

    private func traceEvent(
        observations: [DiagnosticJSONValue],
        chunkIndex: UInt64 = 0,
        chunkCount: UInt64 = 1,
        droppedObservations: UInt64 = 0
    ) -> DiagnosticEvent {
        makeEvent(
            eventType: "voice.session.trace",
            category: "trace",
            severity: .warning,
            payload: [
                "capture_id": .string("capture-1"),
                "chunk_index": .unsignedInteger(chunkIndex),
                "chunk_count": .unsignedInteger(chunkCount),
                "observation_schema_version": .unsignedInteger(1),
                "observations": .array(observations),
                "dropped_observations": .unsignedInteger(droppedObservations),
            ]
        )
    }

    private func makeEvent(
        eventType: String,
        category: String,
        severity: DiagnosticSeverity,
        payload: [String: DiagnosticJSONValue]
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            input: try! DiagnosticEventInput(
                eventType: eventType,
                subsystem: "voice.session",
                category: category,
                severity: severity,
                sourceComponent: "long_term_observability",
                sessionID: "session-1",
                payload: payload
            ),
            context: DiagnosticRuntimeContext(
                processInstanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                processID: 42,
                binaryPath: "/tmp/RemoteOrbit",
                appVersion: "0.2.15",
                buildVersion: "44",
                sourceRevision: "fixture"
            ),
            timestamp: DiagnosticClockStamp(
                wallTimestampUnixMilliseconds: 1,
                monotonic: DiagnosticMonotonicTimestamp(
                    valueNanoseconds: 1_000_000_000,
                    clockDomain: "mach_continuous_time",
                    rawTicks: 1_000_000_000,
                    timebaseNumerator: 1,
                    timebaseDenominator: 1
                )
            ),
            sequenceNumber: 1
        )
    }

    private func statisticsPayload(windows: [DiagnosticJSONValue]) -> DiagnosticJSONValue {
        .object([
            "session_start_timestamp_nanoseconds": .unsignedInteger(1_000_000_000),
            "session_end_timestamp_nanoseconds": .unsignedInteger(3_000_000_000),
            "window_width_nanoseconds": .unsignedInteger(1_000_000_000),
            "capacity_windows": .unsignedInteger(64),
            "ring_overwrite_count": .unsignedInteger(4),
            "producer_sequence_gap_counts": .object([
                "voice_service": .unsignedInteger(2),
                "audio_pipe": .unsignedInteger(3),
            ]),
            "producer_timestamp_out_of_order_counts": .object([
                "voice_service": .unsignedInteger(1),
                "audio_pipe": .unsignedInteger(2),
            ]),
            "producer_missing_timestamp_counts": .object([
                "voice_service": .unsignedInteger(0),
                "audio_pipe": .unsignedInteger(1),
            ]),
            "invalid_window_ranges": .array([]),
            "windows": .array(windows),
        ])
    }

    private func statisticsWindow(
        validity: String,
        invalidReasons: [String] = [],
        decodedSamples: UInt64,
        effectiveSourceHz: DiagnosticJSONValue
    ) -> DiagnosticJSONValue {
        .object([
            "second": .unsignedInteger(1),
            "validity": .string(validity),
            "invalid_reasons": .array(invalidReasons.map(DiagnosticJSONValue.string)),
            "ble_notification_count": .unsignedInteger(30),
            "ble_notification_gap_count": .unsignedInteger(1),
            "ble_notification_gap_total_nanoseconds": .unsignedInteger(40_000_000),
            "ble_notification_gap_max_nanoseconds": .unsignedInteger(40_000_000),
            "decoded_pcm_samples": .unsignedInteger(decodedSamples),
            "effective_source_hz": effectiveSourceHz,
            "audio_pipe_queue_observation_count": .unsignedInteger(10),
            "audio_pipe_render_observation_count": .unsignedInteger(20),
            "audio_pipe_queue_start_depth_frames": .unsignedInteger(960),
            "audio_pipe_queue_end_depth_frames": .unsignedInteger(480),
            "active_underrun_frames": .unsignedInteger(0),
        ])
    }

    private func supplementalTracePoints() -> [DiagnosticJSONValue] {
        [
            tracePoint(
                timestamp: 1_100_000_000,
                kind: "ble_arrival",
                source: "voice_service",
                sequence: 1
            ),
            tracePoint(
                timestamp: 1_200_000_000,
                kind: "pcm_submitted",
                source: "audio_pipe",
                sequence: 1
            ),
            tracePoint(
                timestamp: 1_999_000_000,
                kind: "render",
                source: "audio_pipe",
                sequence: 2
            ),
        ]
    }

    private func tracePoint(
        timestamp: UInt64,
        kind: String,
        source: String,
        sequence: UInt64
    ) -> DiagnosticJSONValue {
        .object([
            "timestamp_nanoseconds": .unsignedInteger(timestamp),
            "kind": .string(kind),
            "requested_frames": .unsignedInteger(480),
            "filled_frames": .unsignedInteger(480),
            "unfilled_frames": .unsignedInteger(0),
            "queue_depth_after_frames": .unsignedInteger(480),
            "byte_or_sample_count": .unsignedInteger(1_600),
            "marker": .string("active"),
            "stream_identity": .unsignedInteger(7),
            "source": .string(source),
            "source_sequence": .unsignedInteger(sequence),
        ])
    }

    private func point(
        timestamp: UInt64,
        kind: LongTermObservationKind,
        count: UInt64 = 0,
        queueBefore: UInt64? = nil,
        queueAfter: UInt64 = 0,
        source: String,
        sequence: UInt64,
        streamID: UInt64 = 1
    ) -> LongTermObservationPoint {
        LongTermObservationPoint(
            timestampNanoseconds: timestamp,
            kind: kind,
            requestedFrames: 0,
            filledFrames: 0,
            unfilledFrames: 0,
            queueDepthFrames: queueAfter,
            byteOrSampleCount: count,
            marker: .active,
            streamIdentity: streamID,
            sequence: sequence,
            queueDepthBeforeFrames: queueBefore,
            source: source
        )
    }
}

private final class FixtureDiagnosticAuthority: DiagnosticAuthority {
    let events: [DiagnosticEvent]
    let droppedEventCount: UInt64 = 0

    init(events: [DiagnosticEvent]) {
        self.events = events
    }

    func emit(_ input: DiagnosticEventInput) {}

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: events.filter(filter.matches),
            nextCursor: nil
        )
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data {
        try JSONEncoder().encode(query(filter))
    }
}
