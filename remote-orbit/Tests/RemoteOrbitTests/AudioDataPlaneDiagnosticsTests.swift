import XCTest
@testable import RemoteOrbit

final class AudioDataPlaneDiagnosticsTests: XCTestCase {
    func testVoiceTimingLoggerMapsTailEventsToDistinctTimelineFields() {
        XCTAssertEqual(
            VoiceTimingLogger.timelineEventName(for: "AUDIO_STOP"),
            "T5_audio_stop_received"
        )
        XCTAssertEqual(
            VoiceTimingLogger.timelineEventName(for: "QUEUE_EMPTY"),
            "T6_queue_empty"
        )
        XCTAssertEqual(
            VoiceTimingLogger.timelineEventName(for: "DRAIN_FINISH"),
            "T7_audio_drain_end"
        )
        XCTAssertEqual(
            VoiceTimingLogger.timelineEventName(for: "AUDIO_PIPELINE_CLOSED"),
            "T8_audio_pipeline_closed"
        )
        XCTAssertEqual(
            VoiceTimingLogger.timelineEventName(for: "OPTION_UP_REQUESTED"),
            "T9_option_up_requested"
        )
        XCTAssertEqual(
            VoiceTimingLogger.timelineEventName(for: "OPTION_UP_EMITTED"),
            "T10_option_up_emitted"
        )
        XCTAssertEqual(
            VoiceTimingLogger.timelineEventName(for: "PHYSICAL_UP"),
            "T5_physical_up"
        )
        XCTAssertNil(VoiceTimingLogger.timelineEventName(for: "unknown"))
    }

    func testOutputDrainBoundaryOnlyClaimsAppQueueEmpty() {
        XCTAssertTrue(AudioPipe.isOutputDrained(remoteActive: false, queuedFrames: 0))
        XCTAssertFalse(AudioPipe.isOutputDrained(remoteActive: false, queuedFrames: 1))
        XCTAssertFalse(AudioPipe.isOutputDrained(remoteActive: true, queuedFrames: 0))
    }

    func testAudioPipeDiagnosticsCountersTrackSubmittedAndRenderedRemoteFrames() {
        var counters = AudioPipeDiagnosticsCounters()
        counters.reset(currentQueueDepthFrames: 0)

        counters.recordSubmittedRemoteFrames(1_440)
        counters.recordRenderedRemoteFrames(960)

        let snapshot = counters.snapshot(
            currentQueueDepthFrames: 480,
            audioQueueDepthFrames: 640,
            pendingRemoteFrames: 480,
            sampleRate: 48_000
        )

        XCTAssertEqual(snapshot.submittedRemoteFrames, 1_440)
        XCTAssertEqual(snapshot.renderedRemoteFrames, 960)
        XCTAssertEqual(snapshot.currentQueueDepthFrames, 480)
        XCTAssertEqual(snapshot.pendingRemoteFrames, 480)
        XCTAssertEqual(snapshot.audioQueueDepthFrames, 640)
    }

    func testAudioPipeDiagnosticsWindowResetDoesNotChangeSessionCumulativeCounters() {
        var session = AudioPipeDiagnosticsCounters()
        var window = AudioPipeDiagnosticsCounters()
        session.reset(currentQueueDepthFrames: 0)
        window.reset(currentQueueDepthFrames: 0)

        session.recordSubmittedRemoteFrames(2_880)
        session.recordRenderedRemoteFrames(2_400)
        window.recordSubmittedRemoteFrames(480)
        window.recordRenderedRemoteFrames(480)

        let windowBeforeReset = window.snapshot(
            currentQueueDepthFrames: 0,
            audioQueueDepthFrames: 0,
            pendingRemoteFrames: 0,
            sampleRate: 48_000
        )
        window.reset(currentQueueDepthFrames: 0)
        let windowAfterReset = window.snapshot(
            currentQueueDepthFrames: 0,
            audioQueueDepthFrames: 0,
            pendingRemoteFrames: 0,
            sampleRate: 48_000
        )
        let sessionAfterWindowReset = session.snapshot(
            currentQueueDepthFrames: 480,
            audioQueueDepthFrames: 480,
            pendingRemoteFrames: 480,
            sampleRate: 48_000
        )

        XCTAssertEqual(windowBeforeReset.submittedRemoteFrames, 480)
        XCTAssertEqual(windowBeforeReset.renderedRemoteFrames, 480)
        XCTAssertEqual(windowAfterReset.submittedRemoteFrames, 0)
        XCTAssertEqual(windowAfterReset.renderedRemoteFrames, 0)
        XCTAssertEqual(sessionAfterWindowReset.submittedRemoteFrames, 2_880)
        XCTAssertEqual(sessionAfterWindowReset.renderedRemoteFrames, 2_400)
    }

    func testContinuityLedgerCorrelatesMonotonicSupplyAndActiveUnderrunBuckets() {
        let sessionID = UUID()
        let start: UInt64 = 1_000_000_000
        var ledger = AudioContinuityBucketLedger(sessionStartNanoseconds: start)

        ledger.recordBLE(timestampNanoseconds: start + 10_000_000, bytes: 120)
        ledger.recordBLE(timestampNanoseconds: start + 90_000_000, bytes: 120)
        ledger.recordDecoded(
            timestampNanoseconds: start + 95_000_000,
            frameCount: 1,
            sampleCount: 160
        )
        ledger.recordSubmitted(
            timestampNanoseconds: start + 98_000_000,
            frames: 480,
            queueDepthFrames: 480
        )
        ledger.recordRender(
            timestampNanoseconds: start + 105_000_000,
            accounting: AudioPipeRenderAccounting(
                state: .activeRemote,
                accounted: true,
                activeRequestedFrames: 480,
                activeFilledFrames: 0,
                activeUnderrunFrames: 480,
                activeUnderrunCallbacks: 1,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            ),
            queueDepthBefore: 480,
            queueDepthAfter: 0
        )

        XCTAssertEqual(ledger.bucketCount, 2)
        XCTAssertEqual(ledger.bucket(at: 0)?.bleGapOver50Milliseconds, 1)
        XCTAssertEqual(ledger.bucket(at: 0)?.decodedSampleCount, 160)
        XCTAssertEqual(ledger.bucket(at: 0)?.submittedRemoteFrames, 480)
        XCTAssertEqual(ledger.bucket(at: 1)?.activeUnderrunFrames, 480)
        XCTAssertEqual(ledger.bucket(at: 1)?.queueEndFrames, 0)

        let lines = ledger.reportLines(sessionID: sessionID)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("bucket_ms=100"))
        XCTAssertTrue(lines[1].contains("start_ms=0 end_ms=100"))
        XCTAssertTrue(lines[1].contains("ble_gap_gt50=1"))
        XCTAssertTrue(lines[2].contains("start_ms=100 end_ms=200"))
        XCTAssertTrue(lines[2].contains("active_underrun_frames=480"))
    }

    func testContinuityLedgerKeepsTailUnderrunSeparateFromActiveUnderrun() {
        let start: UInt64 = 2_000_000_000
        var ledger = AudioContinuityBucketLedger(sessionStartNanoseconds: start)

        ledger.recordRender(
            timestampNanoseconds: start + 20_000_000,
            accounting: AudioPipeRenderAccounting(
                state: .tailDrain,
                accounted: true,
                activeRequestedFrames: 0,
                activeFilledFrames: 0,
                activeUnderrunFrames: 0,
                activeUnderrunCallbacks: 0,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 1,
                idleRenderCallbacks: 0
            ),
            queueDepthBefore: 0,
            queueDepthAfter: 0
        )

        XCTAssertEqual(ledger.bucket(at: 0)?.tailEmptyCallbacks, 1)
        XCTAssertEqual(ledger.bucket(at: 0)?.activeUnderrunFrames, 0)
    }

    func testAudioStartBeforeHIDPreservesPreSessionRenderUntilLateBinding() {
        let captureID = UUID()
        let audioStart: UInt64 = 2_500_000_000
        let capture = AudioContinuityCaptureContext(
            captureID: captureID,
            sessionID: nil,
            startNanoseconds: audioStart
        )
        var renderLedger = AudioContinuityRenderLedger(capture: capture)

        renderLedger.recordRender(
            timestampNanoseconds: audioStart + 50_000_000,
            accounting: AudioPipeRenderAccounting(
                state: .activeRemote,
                accounted: true,
                activeRequestedFrames: 480,
                activeFilledFrames: 0,
                activeUnderrunFrames: 480,
                activeUnderrunCallbacks: 1,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            ),
            queueDepthBefore: 0,
            queueDepthAfter: 0
        )

        let sessionID = UUID()
        let session = AudioContinuitySessionContext(
            sessionID: sessionID,
            startNanoseconds: audioStart + 80_000_000
        )
        XCTAssertFalse(
            renderLedger.bind(
                captureID: UUID(),
                session: session
            )
        )
        XCTAssertTrue(
            renderLedger.bind(
                captureID: captureID,
                session: session
            )
        )

        let snapshot = renderLedger.snapshot()
        XCTAssertEqual(snapshot?.captureID, captureID)
        XCTAssertEqual(snapshot?.session.sessionID, sessionID)
        XCTAssertEqual(snapshot?.session.startNanoseconds, audioStart)
        XCTAssertEqual(snapshot?.buckets.first?.activeUnderrunFrames, 480)
        var joinedLedger = AudioContinuityBucketLedger(
            sessionStartNanoseconds: audioStart,
            captureID: captureID
        )
        joinedLedger.mergeRenderSnapshot(snapshot!)
        XCTAssertEqual(joinedLedger.bucket(at: 0)?.activeUnderrunFrames, 480)
        XCTAssertFalse(
            renderLedger.bind(
                captureID: captureID,
                session: AudioContinuitySessionContext(
                    sessionID: UUID(),
                    startNanoseconds: audioStart + 90_000_000
                )
            )
        )
    }

    func testHIDBeforeAudioStartKeepsBoundSessionIdentity() {
        let sessionID = UUID()
        let sessionStart: UInt64 = 2_800_000_000
        let capture = AudioContinuityCaptureContext(
            captureID: UUID(),
            sessionID: sessionID,
            startNanoseconds: sessionStart
        )
        var renderLedger = AudioContinuityRenderLedger(capture: capture)
        renderLedger.recordOverflow(
            timestampNanoseconds: sessionStart + 105_000_000,
            frames: 12
        )

        let snapshot = renderLedger.snapshot()
        XCTAssertEqual(snapshot?.captureID, capture.captureID)
        XCTAssertEqual(snapshot?.session.sessionID, sessionID)
        XCTAssertEqual(snapshot?.buckets.first?.overflowDroppedFrames, 12)
    }

    func testRenderSnapshotRequiresMatchingCaptureIdentityForSessionJoin() {
        let session = AudioContinuitySessionContext(
            sessionID: UUID(),
            startNanoseconds: 2_900_000_000
        )
        let capture = AudioContinuityCaptureContext(
            captureID: UUID(),
            sessionID: session.sessionID,
            startNanoseconds: session.startNanoseconds
        )
        var renderLedger = AudioContinuityRenderLedger(capture: capture)
        renderLedger.recordOverflow(
            timestampNanoseconds: session.startNanoseconds + 105_000_000,
            frames: 8
        )
        let snapshot = renderLedger.snapshot()!

        var wrongCaptureLedger = AudioContinuityBucketLedger(
            sessionStartNanoseconds: session.startNanoseconds,
            captureID: UUID()
        )
        wrongCaptureLedger.mergeRenderSnapshot(snapshot)
        XCTAssertNil(wrongCaptureLedger.bucket(at: 1))

        var matchingLedger = AudioContinuityBucketLedger(
            sessionStartNanoseconds: session.startNanoseconds,
            captureID: capture.captureID
        )
        matchingLedger.mergeRenderSnapshot(snapshot)
        XCTAssertEqual(
            matchingLedger.bucket(at: 1)?.overflowDroppedFrames,
            8
        )
    }

    func testRenderLedgerUsesFixedSessionOwnedStorageAndResetsBetweenSessions() {
        let firstSession = AudioContinuitySessionContext(
            sessionID: UUID(),
            startNanoseconds: 3_000_000_000
        )
        var renderLedger = AudioContinuityRenderLedger()
        renderLedger.reset(session: firstSession)

        renderLedger.recordRender(
            timestampNanoseconds: firstSession.startNanoseconds + 105_000_000,
            accounting: AudioPipeRenderAccounting(
                state: .activeRemote,
                accounted: true,
                activeRequestedFrames: 480,
                activeFilledFrames: 0,
                activeUnderrunFrames: 480,
                activeUnderrunCallbacks: 1,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            ),
            queueDepthBefore: 480,
            queueDepthAfter: 0
        )

        let firstSnapshot = renderLedger.snapshot()
        XCTAssertEqual(firstSnapshot?.session, firstSession)
        XCTAssertEqual(firstSnapshot?.buckets.count, 1)
        XCTAssertEqual(firstSnapshot?.buckets.first?.index, 1)
        XCTAssertEqual(firstSnapshot?.buckets.first?.activeUnderrunFrames, 480)

        let secondSession = AudioContinuitySessionContext(
            sessionID: UUID(),
            startNanoseconds: 4_000_000_000
        )
        renderLedger.reset(session: secondSession)
        XCTAssertNil(renderLedger.snapshot())

        renderLedger.recordRender(
            timestampNanoseconds: firstSession.startNanoseconds + 105_000_000,
            accounting: AudioPipeRenderAccounting(
                state: .activeRemote,
                accounted: true,
                activeRequestedFrames: 480,
                activeFilledFrames: 0,
                activeUnderrunFrames: 480,
                activeUnderrunCallbacks: 1,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            ),
            queueDepthBefore: 480,
            queueDepthAfter: 0
        )
        XCTAssertNil(renderLedger.snapshot())

        renderLedger.recordOverflow(
            timestampNanoseconds: secondSession.startNanoseconds + 205_000_000,
            frames: 32
        )
        XCTAssertEqual(renderLedger.snapshot()?.session, secondSession)
        XCTAssertEqual(renderLedger.snapshot()?.buckets.first?.overflowDroppedFrames, 32)
    }

    func testRenderLedgerDisabledContextDoesNotCollect() {
        var renderLedger = AudioContinuityRenderLedger()
        XCTAssertEqual(renderLedger.storageCount, 0)
        renderLedger.reset(session: nil)
        XCTAssertEqual(renderLedger.storageCount, 0)
        renderLedger.recordRender(
            timestampNanoseconds: 1_000_000_000,
            accounting: AudioPipeRenderAccounting(
                state: .activeRemote,
                accounted: true,
                activeRequestedFrames: 480,
                activeFilledFrames: 0,
                activeUnderrunFrames: 480,
                activeUnderrunCallbacks: 1,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            ),
            queueDepthBefore: 480,
            queueDepthAfter: 0
        )
        renderLedger.recordOverflow(
            timestampNanoseconds: 1_000_000_000,
            frames: 32
        )

        XCTAssertNil(renderLedger.snapshot())
    }

    func testRenderLedgerSnapshotRemainsStableAfterCaptureIsDetached() {
        let session = AudioContinuitySessionContext(
            sessionID: UUID(),
            startNanoseconds: 7_000_000_000
        )
        var activeLedger = AudioContinuityRenderLedger(session: session)
        activeLedger.recordOverflow(
            timestampNanoseconds: session.startNanoseconds + 105_000_000,
            frames: 24
        )

        let detachedLedger = activeLedger
        activeLedger = AudioContinuityRenderLedger()

        let snapshot = detachedLedger.snapshot()
        XCTAssertEqual(snapshot?.session, session)
        XCTAssertEqual(snapshot?.buckets.first?.overflowDroppedFrames, 24)
        XCTAssertEqual(activeLedger.storageCount, 0)
    }

    func testRenderLedgerReportsBoundedCapacityDrops() {
        let session = AudioContinuitySessionContext(
            sessionID: UUID(),
            startNanoseconds: 6_000_000_000
        )
        var renderLedger = AudioContinuityRenderLedger()
        renderLedger.reset(session: session)
        renderLedger.recordOverflow(
            timestampNanoseconds: session.startNanoseconds
                + UInt64(AudioContinuityRenderLedger.maxBucketCount)
                    * AudioContinuityBucketLedger.bucketWidthNanoseconds,
            frames: 32
        )

        let snapshot = renderLedger.snapshot()
        XCTAssertEqual(snapshot?.droppedObservationCount, 1)
        XCTAssertTrue(snapshot?.buckets.isEmpty == true)
    }

    func testRenderSnapshotMergesActiveTailAndOverflowIntoCentralLedger() {
        let session = AudioContinuitySessionContext(
            sessionID: UUID(),
            startNanoseconds: 5_000_000_000
        )
        var renderLedger = AudioContinuityRenderLedger()
        renderLedger.reset(session: session)
        renderLedger.recordRender(
            timestampNanoseconds: session.startNanoseconds + 105_000_000,
            accounting: AudioPipeRenderAccounting(
                state: .activeRemote,
                accounted: true,
                activeRequestedFrames: 480,
                activeFilledFrames: 0,
                activeUnderrunFrames: 480,
                activeUnderrunCallbacks: 1,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            ),
            queueDepthBefore: 480,
            queueDepthAfter: 0
        )
        renderLedger.recordRender(
            timestampNanoseconds: session.startNanoseconds + 205_000_000,
            accounting: AudioPipeRenderAccounting(
                state: .tailDrain,
                accounted: true,
                activeRequestedFrames: 0,
                activeFilledFrames: 0,
                activeUnderrunFrames: 0,
                activeUnderrunCallbacks: 0,
                tailRenderedFrames: 240,
                tailEmptyCallbacks: 1,
                idleRenderCallbacks: 0
            ),
            queueDepthBefore: 0,
            queueDepthAfter: 0
        )
        renderLedger.recordOverflow(
            timestampNanoseconds: session.startNanoseconds + 205_000_000,
            frames: 16
        )

        var centralLedger = AudioContinuityBucketLedger(
            sessionStartNanoseconds: session.startNanoseconds
        )
        centralLedger.mergeRenderSnapshot(renderLedger.snapshot()!)

        XCTAssertEqual(centralLedger.bucket(at: 1)?.activeUnderrunFrames, 480)
        XCTAssertEqual(centralLedger.bucket(at: 2)?.tailRenderedFrames, 240)
        XCTAssertEqual(centralLedger.bucket(at: 2)?.tailEmptyCallbacks, 1)
        XCTAssertEqual(centralLedger.bucket(at: 2)?.overflowDroppedFrames, 16)
        XCTAssertTrue(
            centralLedger.reportLines(sessionID: session.sessionID)[0]
                .contains("render_capacity_dropped=0")
        )
    }

    func testDeliveryRatioAtFullRateHasNoDeficit() {
        let result = AudioDeliveryAccounting.measure(
            decodedSamples: 80_000,
            sampleRate: 16_000,
            elapsedSeconds: 5.0
        )

        XCTAssertEqual(result.expectedSamples, 80_000)
        XCTAssertEqual(result.deliveryRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.deficitSamples, 0)
        XCTAssertEqual(result.deficitMilliseconds, 0.0, accuracy: 0.0001)
    }

    func testDeliveryRatioReportsNinetyFivePercentDeficit() {
        let result = AudioDeliveryAccounting.measure(
            decodedSamples: 76_000,
            sampleRate: 16_000,
            elapsedSeconds: 5.0
        )

        XCTAssertEqual(result.expectedSamples, 80_000)
        XCTAssertEqual(result.deliveryRatio, 0.95, accuracy: 0.0001)
        XCTAssertEqual(result.deficitSamples, 4_000)
        XCTAssertEqual(result.deficitMilliseconds, 250.0, accuracy: 0.0001)
    }

    func testDeliveryRatioReportsNinetyPercentDeficit() {
        let result = AudioDeliveryAccounting.measure(
            decodedSamples: 72_000,
            sampleRate: 16_000,
            elapsedSeconds: 5.0
        )

        XCTAssertEqual(result.expectedSamples, 80_000)
        XCTAssertEqual(result.deliveryRatio, 0.90, accuracy: 0.0001)
        XCTAssertEqual(result.deficitSamples, 8_000)
        XCTAssertEqual(result.deficitMilliseconds, 500.0, accuracy: 0.0001)
    }

    func testDeliveryRatioDefendsAgainstZeroElapsedTime() {
        let result = AudioDeliveryAccounting.measure(
            decodedSamples: 160,
            sampleRate: 16_000,
            elapsedSeconds: 0
        )

        XCTAssertEqual(result.expectedSamples, 0)
        XCTAssertEqual(result.deliveryRatio, 0.0, accuracy: 0.0001)
        XCTAssertEqual(result.deficitSamples, 0)
        XCTAssertEqual(result.deficitMilliseconds, 0.0, accuracy: 0.0001)
    }

    func testDeliveryRatioSupportsEightKilohertzCodec() {
        let result = AudioDeliveryAccounting.measure(
            decodedSamples: 7_600,
            sampleRate: 8_000,
            elapsedSeconds: 1.0
        )

        XCTAssertEqual(result.expectedSamples, 8_000)
        XCTAssertEqual(result.deliveryRatio, 0.95, accuracy: 0.0001)
        XCTAssertEqual(result.deficitSamples, 400)
        XCTAssertEqual(result.deficitMilliseconds, 50.0, accuracy: 0.0001)
    }

    func testDeliveryRatioSupportsSixteenKilohertzCodec() {
        let result = AudioDeliveryAccounting.measure(
            decodedSamples: 15_200,
            sampleRate: 16_000,
            elapsedSeconds: 1.0
        )

        XCTAssertEqual(result.expectedSamples, 16_000)
        XCTAssertEqual(result.deliveryRatio, 0.95, accuracy: 0.0001)
        XCTAssertEqual(result.deficitSamples, 800)
        XCTAssertEqual(result.deficitMilliseconds, 50.0, accuracy: 0.0001)
    }

    func testRenderFillAccountingReportsCompleteFill() {
        let result = AudioRenderFillAccounting.measure(
            requestedFrames: 512,
            availableFrames: 512
        )

        XCTAssertEqual(result.filledFrames, 512)
        XCTAssertEqual(result.unfilledFrames, 0)
        XCTAssertFalse(result.underrun)
    }

    func testRenderFillAccountingReportsUnderrun() {
        let result = AudioRenderFillAccounting.measure(
            requestedFrames: 512,
            availableFrames: 300
        )

        XCTAssertEqual(result.filledFrames, 300)
        XCTAssertEqual(result.unfilledFrames, 212)
        XCTAssertTrue(result.underrun)
    }

    func testQueueOverflowAccountingReportsDroppedFramesAndDuration() {
        let result = AudioQueueOverflowAccounting.measure(
            availableBefore: 100_000,
            maximumQueuedFrames: 96_000,
            sampleRate: 48_000
        )

        XCTAssertEqual(result.availableBefore, 100_000)
        XCTAssertEqual(result.maximumQueuedFrames, 96_000)
        XCTAssertEqual(result.droppedFrames, 4_000)
        XCTAssertEqual(result.droppedMilliseconds, 83.3333, accuracy: 0.001)
    }

    func testQueueOverflowAccountingReportsNoDropBelowLimit() {
        let result = AudioQueueOverflowAccounting.measure(
            availableBefore: 95_999,
            maximumQueuedFrames: 96_000,
            sampleRate: 48_000
        )

        XCTAssertEqual(result.droppedFrames, 0)
        XCTAssertEqual(result.droppedMilliseconds, 0.0, accuracy: 0.0001)
    }
    func testFrameAccumulatorEmitsExactFrame() {
        var accumulator = ATVVFrameAccumulator(frameSize: 120)

        let frames = accumulator.append(Data(repeating: 0x01, count: 120))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].count, 120)
        XCTAssertEqual(accumulator.bufferedByteCount, 0)
    }

    func testFrameAccumulatorCombinesPartialNotifications() {
        var accumulator = ATVVFrameAccumulator(frameSize: 120)

        XCTAssertTrue(accumulator.append(Data(repeating: 0x01, count: 82)).isEmpty)
        let frames = accumulator.append(Data(repeating: 0x02, count: 38))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].prefix(82), Data(repeating: 0x01, count: 82))
        XCTAssertEqual(frames[0].suffix(38), Data(repeating: 0x02, count: 38))
        XCTAssertEqual(accumulator.bufferedByteCount, 0)
    }

    func testFrameAccumulatorEmitsMultipleFramesFromOneNotification() {
        var accumulator = ATVVFrameAccumulator(frameSize: 120)

        let frames = accumulator.append(Data(repeating: 0x03, count: 240))

        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(frames.allSatisfy { $0 == Data(repeating: 0x03, count: 120) })
        XCTAssertEqual(accumulator.bufferedByteCount, 0)
    }

    func testFrameAccumulatorRetainsPartialRemainder() {
        var accumulator = ATVVFrameAccumulator(frameSize: 120)

        let frames = accumulator.append(Data(repeating: 0x04, count: 250))

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(accumulator.bufferedByteCount, 10)
    }

    func testFrameAccumulatorResetClearsRemainder() {
        var accumulator = ATVVFrameAccumulator(frameSize: 120)

        _ = accumulator.append(Data(repeating: 0x05, count: 82))
        accumulator.reset()

        XCTAssertEqual(accumulator.bufferedByteCount, 0)
        XCTAssertTrue(accumulator.append(Data(repeating: 0x06, count: 38)).isEmpty)
    }

    func testAudioSyncBoundaryClearsPartialV10Frame() throws {
        let protocolHandler = ATVVProtocol()
        try protocolHandler.acceptCapabilities(
            ATVVCapabilities(
                version: .v10,
                codecs: ATVVCodec.adpcm16k.rawValue,
                interactionModel: 0,
                frameSize: 120
            )
        )
        _ = protocolHandler.decodeAudio(Data(repeating: 0x07, count: 82))

        protocolHandler.applyAudioSync(
            codec: .adpcm16k,
            sequence: 10,
            predictor: 0,
            stepIndex: 0
        )

        XCTAssertEqual(protocolHandler.bufferedAudioBytesForTesting, 0)
    }

    func testNewStreamBoundaryClearsPartialV10Frame() throws {
        let protocolHandler = ATVVProtocol()
        try protocolHandler.acceptCapabilities(
            ATVVCapabilities(
                version: .v10,
                codecs: ATVVCodec.adpcm16k.rawValue,
                interactionModel: 0,
                frameSize: 120
            )
        )
        protocolHandler.beginAudioStream(codec: .adpcm16k)
        _ = protocolHandler.decodeAudio(Data(repeating: 0x08, count: 82))
        protocolHandler.endAudioStream()

        XCTAssertEqual(protocolHandler.bufferedAudioBytesForTesting, 0)
    }
}
