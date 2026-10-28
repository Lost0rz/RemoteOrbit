import XCTest
@testable import RemoteOrbit

final class LongTermObservabilityTests: XCTestCase {
    func testFixedTracePreservesFrontAndWrapsRecentWithoutAllocatingOnAppend() {
        var trace = FixedCapacityObservationTrace(frontCapacity: 2, recentCapacity: 3)
        for timestamp in UInt64(1)...6 {
            trace.append(point(timestamp: timestamp))
        }

        let snapshot = trace.snapshot()
        XCTAssertEqual(snapshot.front.map(\.timestampNanoseconds), [1, 2])
        XCTAssertEqual(snapshot.recent.map(\.timestampNanoseconds), [4, 5, 6])
        XCTAssertEqual(snapshot.overwrittenObservationCount, 1)
        XCTAssertEqual(snapshot.droppedObservationCount, 0)
        XCTAssertEqual(snapshot.all.map(\.timestampNanoseconds), [1, 2, 4, 5, 6])
    }

    func testTraceDropsOutOfOrderAndWhenNoCapacityIsAvailable() {
        var trace = FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 0)
        trace.append(point(timestamp: 10))
        trace.append(point(timestamp: 9))
        trace.append(point(timestamp: 11))

        XCTAssertEqual(trace.droppedObservationCount, 2)
        XCTAssertEqual(trace.snapshot().all.map(\.timestampNanoseconds), [10])
    }

    func testSummaryAccountsForExpectedDeliveredAndActiveTailDeficits() {
        var summary = LongTermVoiceSessionSummary(sessionID: "session-1", captureID: "capture-1")
        summary.recordDelivery(expectedFrames: 100, deliveredFrames: 90, marker: .active)
        summary.recordDelivery(expectedFrames: 50, deliveredFrames: 45, marker: .tail)

        XCTAssertEqual(summary.expectedFrames, 150)
        XCTAssertEqual(summary.deliveredFrames, 135)
        XCTAssertEqual(summary.deficitFrames, 15)
        XCTAssertEqual(summary.activeExpectedFrames, 100)
        XCTAssertEqual(summary.activeDeliveredFrames, 90)
        XCTAssertEqual(summary.activeDeficitFrames, 10)
        XCTAssertEqual(summary.tailExpectedFrames, 50)
        XCTAssertEqual(summary.tailDeliveredFrames, 45)
        XCTAssertEqual(summary.tailDeficitFrames, 5)
    }

    func testThresholdClassificationReturnsObservationFlagsOnly() {
        var summary = LongTermVoiceSessionSummary(sessionID: "session-1", captureID: "capture-1")
        summary.notificationGapCount = 1
        summary.decodeGapCount = 1
        summary.activeExpectedFrames = 10
        summary.activeDeliveredFrames = 8
        summary.tailExpectedFrames = 10
        summary.tailDeliveredFrames = 8
        summary.queueStarvationCount = 1
        summary.mainQueueLag = MainQueueLagSummary(
            sampleCount: 1,
            maxLagNanoseconds: 101,
            p95LagNanoseconds: 101,
            histogram: [1]
        )
        summary.authorityWriteFailureCount = 1
        var trace = FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 1)
        trace.append(point(timestamp: 1))
        trace.append(point(timestamp: 2))
        trace.append(point(timestamp: 3))

        let thresholds = LongTermObservabilityThresholds(
            maxNotificationGapCount: 0,
            maxDecodeGapCount: 0,
            maxActiveDeficitFrames: 0,
            maxTailDeficitFrames: 0,
            maxQueueStarvationCount: 0,
            maxMainQueueP95LagNanoseconds: 100,
            maxTraceDroppedObservations: 0,
            maxAuthorityWriteFailures: 0
        )
        let flags = Set(thresholds.classify(summary: summary, trace: trace.snapshot()))

        XCTAssertEqual(flags, Set([
            .notificationGap,
            .decodeGap,
            .activeDeficit,
            .tailDeficit,
            .queueStarvation,
            .mainQueueLag,
            .traceOverwritten,
            .authorityWriteFailure,
        ]))
    }

    func testMainQueueLagAccumulatorProvidesP95AndHistogram() {
        var accumulator = MainQueueLagAccumulator(bucketUpperBoundsNanoseconds: [10, 20, 50, 100])
        for value in [1, 9, 11, 19, 20, 70, 100] {
            accumulator.record(lagNanoseconds: UInt64(value))
        }

        let summary = accumulator.summary
        XCTAssertEqual(summary.sampleCount, 7)
        XCTAssertEqual(summary.maxLagNanoseconds, 100)
        XCTAssertEqual(summary.p95LagNanoseconds, 100)
        XCTAssertEqual(summary.histogram, [2, 3, 0, 2])
    }

    func testMainQueueProbeCanBeStartedStoppedAndReturnsRecordedSamples() {
        let probe = MainQueueResponsivenessProbe(sampleIntervalNanoseconds: 1_000_000)
        probe.start()
        probe.record(lagNanoseconds: 3)
        let summary = probe.stop()

        XCTAssertGreaterThanOrEqual(summary.sampleCount, 1)
        XCTAssertGreaterThanOrEqual(summary.maxLagNanoseconds, 3)
        XCTAssertEqual(probe.stop(), summary)
    }

    func testSummaryDiagnosticValueHasStableAccountingKeys() throws {
        var summary = LongTermVoiceSessionSummary(sessionID: "session-1", captureID: "capture-1")
        summary.recordDelivery(expectedFrames: 10, deliveredFrames: 8, marker: .active)
        let value = summary.toDiagnosticJSONValue()
        guard case .object(let object) = value else {
            return XCTFail("summary must encode as an object")
        }

        XCTAssertEqual(object["schema_version"], .unsignedInteger(1))
        XCTAssertEqual(object["session_id"], .string("session-1"))
        XCTAssertEqual(object["capture_id"], .string("capture-1"))
        XCTAssertEqual(object["expected_frames"], .unsignedInteger(10))
        XCTAssertEqual(object["delivered_frames"], .unsignedInteger(8))
        XCTAssertEqual(object["deficit_frames"], .unsignedInteger(2))
    }

    func testServiceEmitsAlwaysOnSummaryWithPreHIDCaptureBindingAndUnavailableReceiver() throws {
        let authority = CapturingLongTermAuthority()
        let runtime = LongTermRuntimeIdentity(
            processInstanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            processID: 99,
            binaryPath: "/tmp/RemoteOrbit-test",
            appVersion: "1.2.3",
            buildVersion: "99",
            sourceRevision: "abc123"
        )
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: runtime,
            thresholds: LongTermObservabilityThresholds(
                maxNotificationGapCount: 1,
                maxActiveDeficitFrames: 1_000
            )
        )
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let captureID = service.observeTransportStart(
            protocolVersion: "2",
            mode: "remote",
            codec: "ADPCM",
            sampleRate: 16_000,
            timestampNanoseconds: 100
        )

        service.begin(sessionID: sessionID, timestampNanoseconds: 200)
        service.observeControl(policy: "momentary_trigger", classification: "hold", triggerSource: "hardware")
        service.mark("MIC_OPEN_TX", timestampNanoseconds: 300, sessionID: sessionID)
        service.mark("AUDIO_START", timestampNanoseconds: 400, sessionID: sessionID)
        service.mark("AUDIO_FIRST", timestampNanoseconds: 500, sessionID: sessionID)
        service.observeNotification(bytes: 120, gapNanoseconds: 30_000_000)
        service.observeDecode(frameCount: 2, sampleCount: 320)
        service.observeSupply(submittedFrames: 320)
        service.observePlayout(expectedFrames: 320, deliveredFrames: 300, marker: .active)
        service.mark("PHYSICAL_UP", timestampNanoseconds: 600, sessionID: sessionID)
        service.mark("AUDIO_STOP", timestampNanoseconds: 700, sessionID: sessionID)
        service.mark("AUDIO_DRAIN_BEGIN", timestampNanoseconds: 800, sessionID: sessionID)
        service.mark("DRAIN_FINISH", timestampNanoseconds: 900, sessionID: sessionID)
        service.mark("AUDIO_PIPELINE_CLOSED", timestampNanoseconds: 1_000, sessionID: sessionID)

        let summary = try XCTUnwrap(service.end(sessionID: sessionID))
        XCTAssertEqual(summary.captureID, captureID.uuidString)
        XCTAssertEqual(authority.inputs.count, 1)
        let input = try XCTUnwrap(authority.inputs.first)
        XCTAssertEqual(input.eventType, "voice.session.summary")
        XCTAssertEqual(input.sessionID, sessionID.uuidString)
        XCTAssertEqual(input.incidentID, nil)
        guard case .object(let payload) = input.payload["summary"] else {
            return XCTFail("summary payload must be an object")
        }
        XCTAssertEqual(payload["capture_id"], .string(captureID.uuidString))
        XCTAssertEqual(payload["physical_down_timestamp_nanoseconds"], .unsignedInteger(200))
        XCTAssertEqual(payload["mic_open_timestamp_nanoseconds"], .unsignedInteger(300))
        XCTAssertEqual(payload["audio_first_timestamp_nanoseconds"], .unsignedInteger(500))
        XCTAssertEqual(payload["drain_finish_timestamp_nanoseconds"], .unsignedInteger(900))
        XCTAssertEqual(payload["notification_count"], .unsignedInteger(1))
        XCTAssertEqual(payload["notification_gap_count"], .unsignedInteger(1))
        XCTAssertEqual(payload["decoded_sample_count"], .unsignedInteger(320))
        XCTAssertEqual(payload["submitted_frames"], .unsignedInteger(320))
        XCTAssertEqual(payload["rendered_frames"], .unsignedInteger(300))
        XCTAssertEqual(payload["receiver_evidence_status"], .string("unavailable"))
        XCTAssertEqual(payload["runtime_process_id"], .integer(99))
        XCTAssertEqual(payload["runtime_source_revision"], .string("abc123"))
    }

    func testNormalSessionPersistsSummaryOnly() {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let sessionID = UUID()
        service.begin(sessionID: sessionID, timestampNanoseconds: 1)

        let summary = service.end(sessionID: sessionID)

        XCTAssertEqual(summary?.anomalyFlags, [])
        XCTAssertEqual(authority.inputs.map(\.eventType), ["voice.session.summary"])
    }

    func testAnomalousSessionPersistsSummaryAndBoundedTraceChunks() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current(),
            thresholds: LongTermObservabilityThresholds(maxNotificationGapCount: 0)
        )
        let sessionID = UUID()
        service.begin(sessionID: sessionID, timestampNanoseconds: 1)
        service.observeNotification(bytes: 120, gapNanoseconds: 30_000_000)

        var trace = FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 129)
        for timestamp in UInt64(1)...130 {
            trace.append(point(timestamp: timestamp))
        }
        service.observeLongTermAudioSnapshot(
            LongTermAudioObservationSnapshot(trace: trace.snapshot(), mainQueueLag: .empty)
        )

        let summary = try XCTUnwrap(service.end(sessionID: sessionID))
        XCTAssertTrue(summary.anomalyFlags.contains(.notificationGap))
        XCTAssertTrue(summary.tracePersisted)
        XCTAssertEqual(authority.inputs.first?.eventType, "voice.session.summary")
        let traceInputs = authority.inputs.dropFirst()
        XCTAssertEqual(traceInputs.map(\.eventType), ["voice.session.trace", "voice.session.trace"])

        for input in traceInputs {
            guard case .string(let captureID) = input.payload["capture_id"],
                  case .unsignedInteger(let chunkIndex) = input.payload["chunk_index"],
                  case .unsignedInteger(let chunkCount) = input.payload["chunk_count"],
                  case .unsignedInteger(let schemaVersion) = input.payload["observation_schema_version"],
                  case .array(let observations) = input.payload["observations"] else {
                return XCTFail("trace payload is not machine-readable")
            }
            XCTAssertEqual(captureID, summary.captureID)
            XCTAssertEqual(chunkCount, 2)
            XCTAssertEqual(schemaVersion, 1)
            XCTAssertLessThanOrEqual(observations.count, 128)
            XCTAssertTrue(observations.allSatisfy { value in
                guard case .object(let object) = value else { return false }
                return object["timestamp_nanoseconds"] != nil
                    && object["requested_frames"] != nil
                    && object["filled_frames"] != nil
                    && object["unfilled_frames"] != nil
                    && object["queue_depth_frames"] != nil
                    && object["byte_or_sample_count"] != nil
            })
            XCTAssertEqual(input.sessionID, sessionID.uuidString)
            XCTAssertEqual(chunkIndex < chunkCount, true)
        }
    }

    private func point(timestamp: UInt64) -> LongTermObservationPoint {
        LongTermObservationPoint(
            timestampNanoseconds: timestamp,
            kind: .lifecycle,
            requestedFrames: 1,
            filledFrames: 1,
            unfilledFrames: 0,
            queueDepthFrames: 1,
            byteOrSampleCount: 1,
            marker: .active
        )
    }
}

private final class CapturingLongTermAuthority: DiagnosticAuthority {
    var droppedEventCount: UInt64 = 0
    var writeFailureCount: UInt64 = 0
    var inputs: [DiagnosticEventInput] = []

    func emit(_ input: DiagnosticEventInput) {
        inputs.append(input)
    }

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        DiagnosticQueryPage(schemaVersion: DiagnosticEvent.currentSchemaVersion, events: [], nextCursor: nil)
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data {
        try JSONEncoder().encode(
            DiagnosticQueryPage(schemaVersion: DiagnosticEvent.currentSchemaVersion, events: [], nextCursor: nil)
        )
    }
}
