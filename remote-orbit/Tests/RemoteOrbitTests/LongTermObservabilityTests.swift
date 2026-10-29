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

    func testIntentionalRecentOverwriteIsRetentionMetadataOnly() {
        var trace = FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 2)
        for timestamp in UInt64(1)...4 {
            trace.append(point(timestamp: timestamp))
        }

        let snapshot = trace.snapshot()
        let summary = LongTermVoiceSessionSummary(sessionID: "session-1", captureID: "capture-1")

        XCTAssertEqual(snapshot.overwrittenObservationCount, 1)
        XCTAssertEqual(snapshot.droppedObservationCount, 0)
        XCTAssertFalse(
            LongTermObservabilityThresholds().classify(summary: summary, trace: snapshot).contains(.traceOverwritten)
        )
    }

    func testHealthyLongSessionWrapsWithoutPersistingAnIncidentTrace() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let sessionID = UUID()
        service.begin(sessionID: sessionID, timestampNanoseconds: 1)
        for timestamp in UInt64(1)...700 {
            service.observeTracePoint(point(timestamp: timestamp))
        }

        let summary = try XCTUnwrap(service.end(sessionID: sessionID))

        XCTAssertTrue(summary.traceOverwrittenObservationCount > 0)
        XCTAssertTrue(summary.anomalyFlags.isEmpty)
        XCTAssertEqual(authority.inputs.filter { $0.eventType == "voice.session.trace" }.count, 0)
    }

    func testActualObservationDropRemainsAnAnomaly() {
        var trace = FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 1)
        trace.append(point(timestamp: 10))
        trace.append(point(timestamp: 9))

        let flags = LongTermObservabilityThresholds().classify(
            summary: LongTermVoiceSessionSummary(sessionID: "session-1", captureID: "capture-1"),
            trace: trace.snapshot()
        )

        XCTAssertTrue(flags.contains(.traceDropped))
    }

    func testIncidentFreezePreservesMiddleWindowAfterLaterRecentWrap() {
        var trace = FixedCapacityObservationTrace(frontCapacity: 2, recentCapacity: 3)
        for timestamp in UInt64(1)...5 {
            trace.append(point(timestamp: timestamp))
        }

        trace.freezeIncidentWindow()
        for timestamp in UInt64(6)...20 {
            trace.append(point(timestamp: timestamp))
        }

        XCTAssertEqual(trace.snapshot().incident.map(\.timestampNanoseconds), [1, 2, 3, 4, 5])
    }

    func testIncidentFreezeStopsIncidentWindowGrowth() {
        var trace = FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 1, incidentCapacity: 4)
        trace.append(point(timestamp: 1))
        trace.freezeIncidentWindow()
        for timestamp in UInt64(2)...5 {
            trace.append(point(timestamp: timestamp))
        }

        XCTAssertEqual(trace.snapshot().incident.map(\.timestampNanoseconds), [1])
    }

    func testTraceContainsCorrelatableTransportToRenderStages() {
        var trace = FixedCapacityObservationTrace(frontCapacity: 8, recentCapacity: 8)
        trace.append(point(timestamp: 10, kind: .bleArrival))
        trace.append(point(timestamp: 20, kind: .decodeComplete))
        trace.append(point(timestamp: 30, kind: .pcmSubmitted))
        trace.append(point(timestamp: 40, kind: .render))

        XCTAssertEqual(
            trace.snapshot().all.map(\.kind),
            [.bleArrival, .decodeComplete, .pcmSubmitted, .render]
        )
        XCTAssertTrue(trace.snapshot().all.map(\.timestampNanoseconds).isStrictlyIncreasing)
    }

    func testMainQueueLagRetainsBoundedIncidentTimestamps() {
        var accumulator = MainQueueLagAccumulator(
            bucketUpperBoundsNanoseconds: [10, 100, UInt64.max],
            maxIncidentSampleCount: 2,
            incidentLagThresholdNanoseconds: 50
        )
        accumulator.record(lagNanoseconds: 80, timestampNanoseconds: 1_000)
        accumulator.record(lagNanoseconds: 90, timestampNanoseconds: 2_000)
        accumulator.record(lagNanoseconds: 100, timestampNanoseconds: 3_000)

        XCTAssertEqual(
            accumulator.summary.incidentOccurrences.map(\.timestampNanoseconds),
            [1_000, 2_000]
        )
        XCTAssertEqual(accumulator.summary.sampleCount, 3)
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
            histogram: [1],
            incidentOccurrences: [MainQueueLagOccurrence(timestampNanoseconds: 1, lagNanoseconds: 101)]
        )
        summary.expectedSamples = 10
        summary.deliveredSamples = 8
        summary.deliveryRatio = 0.8
        summary.deficitSamples = 2
        summary.deficitMilliseconds = 0.125
        summary.authorityWriteFailureCount = 1
        var trace = FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 1)
        trace.append(point(timestamp: 1))
        trace.append(point(timestamp: 0))

        let thresholds = LongTermObservabilityThresholds(
            maxNotificationGapCount: 0,
            maxDecodeGapCount: 0,
            maxDeliveryDeficitMilliseconds: 0,
            maxActiveDeficitFrames: 0,
            maxTailDeficitFrames: 0,
            maxQueueStarvationCount: 0,
            maxMainQueueP95LagNanoseconds: 100,
            maxTraceDroppedObservations: 0,
            maxAuthorityWriteFailures: 0
        )
        let flags = Set(thresholds.classify(summary: summary, trace: trace.snapshot()))

        XCTAssertEqual(flags, Set<LongTermAnomalyFlag>([
            .notificationGap,
            .decodeGap,
            .activeDeficit,
            .tailDeficit,
            .queueStarvation,
            .deliveryDeficit,
            .mainQueueLag,
            .traceDropped,
            .authorityWriteFailure,
        ]))
    }

    func testLifecycleOrderViolationIsAnExplicitAnomalyFlag() {
        var summary = LongTermVoiceSessionSummary(sessionID: "session-1", captureID: "capture-1")
        summary.audioStartTimestampNanoseconds = 200
        summary.audioFirstTimestampNanoseconds = 100

        XCTAssertEqual(summary.calculatedLifecycleInconsistencyCount(), 1)
        summary.lifecycleInconsistencyCount = summary.calculatedLifecycleInconsistencyCount()
        let flags = LongTermObservabilityThresholds().classify(
            summary: summary,
            trace: FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 1).snapshot()
        )

        XCTAssertTrue(flags.contains(.lifecycleInconsistency))
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

    func testMainQueueProbeSignalsMaterialLagForIncidentFreeze() {
        var incidentCount = 0
        let probe = MainQueueResponsivenessProbe(
            sampleIntervalNanoseconds: 1_000_000,
            incidentLagThresholdNanoseconds: 50,
            onMaterialLag: { incidentCount += 1 }
        )
        probe.start()
        probe.record(lagNanoseconds: 80, timestampNanoseconds: 1_000)
        let summary = probe.stop()

        XCTAssertEqual(incidentCount, 1)
        XCTAssertEqual(summary.incidentOccurrences.count, 1)
    }

    func testMainQueueThresholdDoesNotFreezeBelowBoundaryThenPersistsLaterAnomaly() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let sessionID = UUID()
        let base = P1A4MonotonicClock.nowNanoseconds()
        service.begin(sessionID: sessionID, timestampNanoseconds: base)
        service.observeTracePoint(point(timestamp: base + 1))

        var materialCallbackCount = 0
        let probe = MainQueueResponsivenessProbe(
            sampleIntervalNanoseconds: 1_000_000,
            onMaterialLag: {
                materialCallbackCount += 1
                service.markMaterialAnomaly(trigger: .mainQueueLag)
            }
        )
        probe.record(lagNanoseconds: 50_000_000, timestampNanoseconds: base + 2)
        XCTAssertEqual(materialCallbackCount, 0)
        probe.record(lagNanoseconds: 50_000_001, timestampNanoseconds: base + 3)
        XCTAssertEqual(materialCallbackCount, 1)
        service.observeTracePoint(point(timestamp: base + 4))
        let lagSummary = probe.stop()
        service.observeLongTermAudioSnapshot(
            LongTermAudioObservationSnapshot(
                trace: FixedCapacityObservationTrace(frontCapacity: 1, recentCapacity: 1).snapshot(),
                mainQueueLag: lagSummary
            )
        )

        let summary = try XCTUnwrap(service.end(sessionID: sessionID))
        XCTAssertTrue(summary.anomalyFlags.contains(.mainQueueLag))
        XCTAssertTrue(summary.tracePersisted)
        XCTAssertEqual(summary.incidentTrigger, "main_queue_lag")
        XCTAssertEqual(authority.inputs.filter { $0.eventType == "voice.session.trace" }.count, 1)
    }

    func testProductionPathMaterialGapMergesTransportAndAudioAfterBothRingsWrap() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let pipe = AudioPipe.shared
        let sessionID = UUID()
        let base = P1A4MonotonicClock.nowNanoseconds()
        service.begin(sessionID: sessionID, timestampNanoseconds: base)
        pipe.beginRemoteAudioDiagnostics()
        defer {
            _ = pipe.setRemoteActive(false)
            _ = pipe.endRemoteAudioDiagnostics()
        }

        service.observeNotification(
            bytes: 120,
            gapNanoseconds: 120_000_000,
            timestampNanoseconds: base + 1
        )
        service.observeDecode(
            frameCount: 1,
            sampleCount: 160,
            timestampNanoseconds: base + 2
        )
        _ = pipe.setRemoteActive(true)
        pipe.feed(samples: Array(repeating: Int16(7), count: 320))
        pipe.recordLongTermRenderObservationForTesting(
            timestampNanoseconds: base + 1_000_000_000,
            requestedFrames: 480,
            filledFrames: 0,
            unfilledFrames: 480,
            queueDepthFrames: 0
        )
        for offset in UInt64(1)...700 {
            service.observeTracePoint(point(timestamp: base + 2_000_000_000 + offset))
            pipe.recordLongTermRenderObservationForTesting(
                timestampNanoseconds: base + 1_000_000_000 + offset,
                requestedFrames: 480,
                filledFrames: 480,
                unfilledFrames: 0,
                queueDepthFrames: 480
            )
        }

        service.observeLongTermAudioSnapshot(pipe.takeLongTermObservationSnapshot())
        let summary = try XCTUnwrap(service.end(sessionID: sessionID))
        let traceInputs = authority.inputs.filter { $0.eventType == "voice.session.trace" }
        let observations = traceInputs.flatMap { input -> [DiagnosticJSONValue] in
            guard case .array(let values) = input.payload["observations"] else { return [] }
            return values
        }
        let kinds = Set(observations.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let kind) = object["kind"] else { return nil }
            return kind
        })

        XCTAssertTrue(summary.tracePersisted)
        XCTAssertEqual(summary.incidentTriggerSource, "long_term_service")
        XCTAssertTrue(kinds.isSuperset(of: [
            "ble_arrival", "decode_complete", "pcm_submitted", "render", "queue_starvation",
        ]))
        XCTAssertGreaterThan(summary.traceOverwrittenObservationCount, 0)
        XCTAssertTrue(traceInputs.allSatisfy { $0.incidentID == String(summary.incidentIdentity ?? 0) })
    }

    func testProductionPathAudioStarvationMergesTransportEvidenceWhenAudioTriggersFirst() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current(),
            thresholds: LongTermObservabilityThresholds(maxNotificationGapCount: 0)
        )
        let pipe = AudioPipe.shared
        let sessionID = UUID()
        let base = P1A4MonotonicClock.nowNanoseconds()
        service.begin(sessionID: sessionID, timestampNanoseconds: base)
        pipe.beginRemoteAudioDiagnostics()
        defer {
            _ = pipe.setRemoteActive(false)
            _ = pipe.endRemoteAudioDiagnostics()
        }

        service.observeNotification(
            bytes: 120,
            gapNanoseconds: 30_000_000,
            timestampNanoseconds: base + 1
        )
        service.observeDecode(
            frameCount: 1,
            sampleCount: 160,
            timestampNanoseconds: base + 2
        )
        _ = pipe.setRemoteActive(true)
        pipe.feed(samples: Array(repeating: Int16(7), count: 320))
        pipe.recordLongTermRenderObservationForTesting(
            timestampNanoseconds: base + 1_000_000_000,
            requestedFrames: 480,
            filledFrames: 0,
            unfilledFrames: 480,
            queueDepthFrames: 0
        )

        service.observeLongTermAudioSnapshot(pipe.takeLongTermObservationSnapshot())
        let summary = try XCTUnwrap(service.end(sessionID: sessionID))
        let observations = authority.inputs
            .filter { $0.eventType == "voice.session.trace" }
            .flatMap { input -> [DiagnosticJSONValue] in
                guard case .array(let values) = input.payload["observations"] else { return [] }
                return values
            }
        let kinds = Set(observations.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let kind) = object["kind"] else { return nil }
            return kind
        })

        XCTAssertEqual(summary.incidentTriggerSource, "audio_pipe")
        XCTAssertEqual(summary.incidentTrigger, "render_starvation")
        XCTAssertTrue(kinds.isSuperset(of: [
            "ble_arrival", "decode_complete", "pcm_submitted", "render", "queue_starvation",
        ]))
    }

    func testPreHIDBLEIncidentSurvivesBindingAndBothRecentRingsWrap() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let pipe = AudioPipe.shared
        let base = P1A4MonotonicClock.nowNanoseconds()
        let sessionID = UUID()
        pipe.beginRemoteAudioDiagnostics()
        defer {
            _ = pipe.setRemoteActive(false)
            _ = pipe.endRemoteAudioDiagnostics()
            LongTermIncidentCoordinator.shared.endCapture()
        }

        let captureID = service.observeTransportStart(
            protocolVersion: "2",
            mode: "remote",
            codec: "ADPCM",
            sampleRate: 16_000,
            timestampNanoseconds: base
        )
        service.observeNotification(
            bytes: 120,
            gapNanoseconds: 120_000_000,
            timestampNanoseconds: base + 1
        )
        service.observeDecode(
            frameCount: 1,
            sampleCount: 160,
            timestampNanoseconds: base + 2
        )
        service.observeTracePoint(point(timestamp: base + 3, kind: .pcmSubmitted))
        _ = pipe.setRemoteActive(true)
        pipe.feed(samples: Array(repeating: Int16(7), count: 320))
        pipe.recordLongTermRenderObservationForTesting(
            timestampNanoseconds: base + 1_000_000_000,
            requestedFrames: 480,
            filledFrames: 480,
            unfilledFrames: 0,
            queueDepthFrames: 480
        )

        for offset in UInt64(1)...700 {
            service.observeTracePoint(
                point(timestamp: base + 3_000_000_000 + offset)
            )
            pipe.recordLongTermRenderObservationForTesting(
                timestampNanoseconds: base + 1_000_000_000 + offset,
                requestedFrames: 480,
                filledFrames: 480,
                unfilledFrames: 0,
                queueDepthFrames: 480
            )
        }

        service.begin(sessionID: sessionID, timestampNanoseconds: base + 4_000_000_000)
        service.observeLongTermAudioSnapshot(pipe.takeLongTermObservationSnapshot())
        let summary = try XCTUnwrap(service.end(sessionID: sessionID))
        let observations = authority.inputs
            .filter { $0.eventType == "voice.session.trace" }
            .flatMap { input -> [DiagnosticJSONValue] in
                guard case .array(let values) = input.payload["observations"] else { return [] }
                return values
            }
        let kinds = Set(observations.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let kind) = object["kind"] else { return nil }
            return kind
        })

        XCTAssertEqual(summary.captureID, captureID.uuidString)
        XCTAssertNotNil(summary.incidentIdentity)
        XCTAssertEqual(summary.incidentAnchorTimestampNanoseconds, base + 1)
        XCTAssertEqual(summary.incidentTriggerSource, "long_term_service")
        XCTAssertEqual(summary.incidentTrigger, "ble_gap")
        XCTAssertTrue(kinds.isSuperset(of: [
            "ble_arrival", "decode_complete", "pcm_submitted", "render",
        ]))
        XCTAssertGreaterThan(summary.traceOverwrittenObservationCount, 0)
    }

    func testPreHIDAudioPipeIncidentSurvivesBindingAndJoinsTransportEvidence() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current(),
            thresholds: LongTermObservabilityThresholds(maxNotificationGapCount: 0)
        )
        let pipe = AudioPipe.shared
        let base = P1A4MonotonicClock.nowNanoseconds()
        let sessionID = UUID()
        pipe.beginRemoteAudioDiagnostics()
        defer {
            _ = pipe.setRemoteActive(false)
            _ = pipe.endRemoteAudioDiagnostics()
            LongTermIncidentCoordinator.shared.endCapture()
        }

        _ = pipe.setRemoteActive(true)
        pipe.recordLongTermRenderObservationForTesting(
            timestampNanoseconds: base + 1,
            requestedFrames: 480,
            filledFrames: 0,
            unfilledFrames: 480,
            queueDepthFrames: 0
        )
        _ = service.observeTransportStart(
            protocolVersion: "2",
            mode: "remote",
            codec: "ADPCM",
            sampleRate: 16_000,
            timestampNanoseconds: base + 2
        )
        service.observeNotification(
            bytes: 120,
            gapNanoseconds: 30_000_000,
            timestampNanoseconds: base + 3
        )
        service.observeDecode(
            frameCount: 1,
            sampleCount: 160,
            timestampNanoseconds: base + 4
        )
        service.observeTracePoint(point(timestamp: base + 5, kind: .pcmSubmitted))
        service.begin(sessionID: sessionID, timestampNanoseconds: base + 5)
        service.observeLongTermAudioSnapshot(pipe.takeLongTermObservationSnapshot())
        let summary = try XCTUnwrap(service.end(sessionID: sessionID))
        let observations = authority.inputs
            .filter { $0.eventType == "voice.session.trace" }
            .flatMap { input -> [DiagnosticJSONValue] in
                guard case .array(let values) = input.payload["observations"] else { return [] }
                return values
            }
        let kinds = Set(observations.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let kind) = object["kind"] else { return nil }
            return kind
        })

        XCTAssertEqual(summary.incidentTriggerSource, "audio_pipe")
        XCTAssertEqual(summary.incidentTrigger, "render_starvation")
        XCTAssertTrue(kinds.isSuperset(of: [
            "ble_arrival", "decode_complete", "pcm_submitted", "render", "queue_starvation",
        ]))
    }

    func testPreHIDFirstIncidentRemainsFirstAfterHIDAnomaly() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let base = P1A4MonotonicClock.nowNanoseconds()
        let sessionID = UUID()
        _ = service.observeTransportStart(
            protocolVersion: "2",
            mode: "remote",
            codec: "ADPCM",
            sampleRate: 16_000,
            timestampNanoseconds: base
        )
        service.observeNotification(
            bytes: 120,
            gapNanoseconds: 120_000_000,
            timestampNanoseconds: base + 1
        )
        service.begin(sessionID: sessionID, timestampNanoseconds: base + 2)
        service.markMaterialAnomaly(trigger: .manual)
        let first = try XCTUnwrap(service.end(sessionID: sessionID))

        XCTAssertEqual(first.incidentTriggerSource, "long_term_service")
        XCTAssertEqual(first.incidentTrigger, "ble_gap")
        XCTAssertNotNil(first.incidentIdentity)
    }

    func testGestureFirstCaptureKeepsGenerationWhenTransportStartsLater() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let sessionID = UUID()
        service.begin(sessionID: sessionID, timestampNanoseconds: 1)
        service.markMaterialAnomaly(trigger: .manual)
        service.observeTransportStart(
            protocolVersion: "2",
            mode: "remote",
            codec: "ADPCM",
            sampleRate: 16_000,
            timestampNanoseconds: 2
        )

        let summary = try XCTUnwrap(service.end(sessionID: sessionID))

        XCTAssertEqual(summary.incidentTriggerSource, "long_term_service")
        XCTAssertEqual(summary.incidentTrigger, "manual")
        XCTAssertEqual(summary.audioStartTimestampNanoseconds, 2)
    }

    func testNewCaptureStartsWithCleanIncidentGeneration() throws {
        let firstAuthority = CapturingLongTermAuthority()
        let firstService = LongTermObservabilityService(
            authority: firstAuthority,
            runtimeIdentity: .current()
        )
        let firstSessionID = UUID()
        firstService.begin(sessionID: firstSessionID, timestampNanoseconds: 1)
        firstService.markMaterialAnomaly(trigger: .manual)
        let first = try XCTUnwrap(firstService.end(sessionID: firstSessionID))

        let secondAuthority = CapturingLongTermAuthority()
        let secondService = LongTermObservabilityService(
            authority: secondAuthority,
            runtimeIdentity: .current()
        )
        let secondSessionID = UUID()
        secondService.begin(sessionID: secondSessionID, timestampNanoseconds: 2)
        secondService.markMaterialAnomaly(trigger: .manual)
        let second = try XCTUnwrap(secondService.end(sessionID: secondSessionID))

        XCTAssertNotEqual(first.incidentIdentity, second.incidentIdentity)
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
                maxDecodeGapCount: 3,
                maxActiveDeficitFrames: 1_000
            )
        )
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let captureID = service.observeTransportStart(
            protocolVersion: "2",
            mode: "remote",
            codec: "ADPCM",
            sampleRate: 16_000,
            reason: 7,
            streamID: 9,
            timestampNanoseconds: 100
        )

        service.begin(sessionID: sessionID, timestampNanoseconds: 200)
        service.observeControl(policy: "momentary_trigger", classification: "hold", triggerSource: "hardware")
        service.mark("MIC_OPEN_TX", timestampNanoseconds: 300, sessionID: sessionID)
        service.mark("AUDIO_START", timestampNanoseconds: 400, sessionID: sessionID)
        service.mark("AUDIO_FIRST", timestampNanoseconds: 500, sessionID: sessionID)
        service.observeNotification(bytes: 120, gapNanoseconds: 30_000_000)
        service.observeTransportMetrics(
            notificationCount: 3,
            notificationBytes: 360,
            notificationSizeMin: 120,
            notificationSizeMax: 120,
            notificationSizeDistribution: "120=3",
            notificationFrameSizeDistribution: "==frameSize=3",
            notificationMaxGapMilliseconds: 30,
            notificationP95GapMilliseconds: 30,
            gapOver20Milliseconds: 1,
            gapOver30Milliseconds: 0,
            gapOver50Milliseconds: 0,
            gapOver100Milliseconds: 0,
            decodeRejectCount: 1,
            zeroSampleDecodeCount: 2,
            audioSyncCount: 1,
            decodedAudioDurationMilliseconds: 20,
            measurementElapsedMilliseconds: 25,
            expectedSamples: 400,
            deliveredSamples: 320,
            deliveryRatio: 0.8,
            deficitSamples: 80,
            deficitMilliseconds: 5
        )
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
        XCTAssertGreaterThanOrEqual(authority.inputs.count, 2)
        let input = try XCTUnwrap(authority.inputs.first { $0.eventType == "voice.session.summary" })
        XCTAssertEqual(input.eventType, "voice.session.summary")
        XCTAssertEqual(input.sessionID, sessionID.uuidString)
        XCTAssertEqual(input.incidentID, nil)
        guard case .object(let payload) = input.payload["summary"] else {
            return XCTFail("summary payload must be an object")
        }
        XCTAssertEqual(payload["capture_id"], .string(captureID.uuidString))
        XCTAssertEqual(payload["audio_start_reason"], .unsignedInteger(7))
        XCTAssertEqual(payload["audio_stream_id"], .unsignedInteger(9))
        XCTAssertEqual(payload["physical_down_timestamp_nanoseconds"], .unsignedInteger(200))
        XCTAssertEqual(payload["mic_open_timestamp_nanoseconds"], .unsignedInteger(300))
        XCTAssertEqual(payload["audio_first_timestamp_nanoseconds"], .unsignedInteger(500))
        XCTAssertEqual(payload["drain_finish_timestamp_nanoseconds"], .unsignedInteger(900))
        XCTAssertEqual(payload["notification_count"], .unsignedInteger(3))
        XCTAssertEqual(payload["notification_gap_count"], .unsignedInteger(1))
        XCTAssertEqual(payload["notification_size_distribution"], .string("120=3"))
        XCTAssertEqual(payload["notification_p95_gap_milliseconds"], .double(30))
        XCTAssertEqual(payload["decoded_sample_count"], .unsignedInteger(320))
        XCTAssertEqual(payload["decode_reject_count"], .unsignedInteger(1))
        XCTAssertEqual(payload["zero_sample_decode_count"], .unsignedInteger(2))
        XCTAssertEqual(payload["audio_sync_count"], .unsignedInteger(1))
        XCTAssertEqual(payload["expected_samples"], .unsignedInteger(400))
        XCTAssertEqual(payload["deficit_samples"], .unsignedInteger(80))
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

    func testLateLifecycleAfterEndEmitsCorrelatedFollowup() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let sessionID = UUID()
        service.begin(sessionID: sessionID, timestampNanoseconds: 1)
        let summary = try XCTUnwrap(service.end(sessionID: sessionID))

        service.mark("MIC_CLOSE_TX", timestampNanoseconds: 2, sessionID: sessionID)

        XCTAssertEqual(authority.inputs.map(\.eventType), [
            "voice.session.summary",
            "voice.session.lifecycle_followup",
        ])
        let followup = try XCTUnwrap(authority.inputs.last)
        XCTAssertEqual(followup.sessionID, sessionID.uuidString)
        XCTAssertEqual(followup.correlationID, summary.captureID)
        XCTAssertEqual(followup.payload["event"], .string("MIC_CLOSE_TX"))
        XCTAssertEqual(followup.payload["timestamp_nanoseconds"], .unsignedInteger(2))
    }

    func testMaterialDeliveryDeficitIsExplicitEvenWithoutDecodeRejects() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let sessionID = UUID()
        service.begin(sessionID: sessionID, timestampNanoseconds: 1)
        service.observeTransportMetrics(
            notificationCount: 10,
            notificationBytes: 1_200,
            notificationSizeMin: 120,
            notificationSizeMax: 120,
            notificationSizeDistribution: "120=10",
            notificationFrameSizeDistribution: "==frameSize=10",
            notificationMaxGapMilliseconds: 10,
            notificationP95GapMilliseconds: 10,
            gapOver20Milliseconds: 0,
            gapOver30Milliseconds: 0,
            gapOver50Milliseconds: 0,
            gapOver100Milliseconds: 0,
            decodeRejectCount: 0,
            zeroSampleDecodeCount: 0,
            audioSyncCount: 0,
            decodedAudioDurationMilliseconds: 100,
            measurementElapsedMilliseconds: 300,
            expectedSamples: 16_000,
            deliveredSamples: 8_000,
            deliveryRatio: 0.5,
            deficitSamples: 8_000,
            deficitMilliseconds: 500
        )

        let summary = try XCTUnwrap(service.end(sessionID: sessionID))
        XCTAssertTrue(summary.anomalyFlags.contains(.deliveryDeficit))
        XCTAssertEqual(summary.decodeRejectCount, 0)
        XCTAssertEqual(summary.zeroSampleDecodeCount, 0)
    }

    func testAnomalyTraceContainsMonotonicTransportToRenderEvidence() throws {
        let authority = CapturingLongTermAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let sessionID = UUID()
        service.begin(sessionID: sessionID, timestampNanoseconds: 1)
        service.observeNotification(bytes: 120, gapNanoseconds: 120_000_000, timestampNanoseconds: 100)
        service.observeDecode(frameCount: 1, sampleCount: 160, timestampNanoseconds: 110)
        service.observeTracePoint(point(timestamp: 120, kind: .pcmSubmitted))
        service.observeTracePoint(point(timestamp: 130, kind: .render))

        _ = try XCTUnwrap(service.end(sessionID: sessionID))
        let traceInput = try XCTUnwrap(authority.inputs.first { $0.eventType == "voice.session.trace" })
        guard case .array(let observations) = traceInput.payload["observations"] else {
            return XCTFail("trace observations must be an array")
        }
        let kinds = observations.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let kind) = object["kind"] else { return nil }
            return kind
        }
        XCTAssertEqual(kinds, ["ble_arrival", "decode_complete", "pcm_submitted", "render"])
        let sourceSequences = observations.compactMap { value -> UInt64? in
            guard case .object(let object) = value,
                  case .string(let source) = object["source"],
                  case .unsignedInteger(let sequence) = object["source_sequence"] else { return nil }
            XCTAssertEqual(source, "voice_service")
            return sequence
        }
        XCTAssertEqual(sourceSequences, [1, 2, 3, 4])
        let timestamps = observations.compactMap { value -> UInt64? in
            guard case .object(let object) = value,
                  case .unsignedInteger(let timestamp) = object["timestamp_nanoseconds"] else { return nil }
            return timestamp
        }
        XCTAssertTrue(timestamps.isStrictlyIncreasing)
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
                    && object["queue_depth_after_frames"] != nil
                    && object["byte_or_sample_count"] != nil
            })
            XCTAssertEqual(input.sessionID, sessionID.uuidString)
            XCTAssertEqual(chunkIndex < chunkCount, true)
        }
    }

    private func point(
        timestamp: UInt64,
        kind: LongTermObservationKind = .lifecycle
    ) -> LongTermObservationPoint {
        LongTermObservationPoint(
            timestampNanoseconds: timestamp,
            kind: kind,
            requestedFrames: 1,
            filledFrames: 1,
            unfilledFrames: 0,
            queueDepthFrames: 1,
            byteOrSampleCount: 1,
            marker: .active
        )
    }
}

private extension Array where Element == UInt64 {
    var isStrictlyIncreasing: Bool {
        zip(self, dropFirst()).allSatisfy { $0 < $1 }
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
