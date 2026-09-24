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

    func testLongDurationSnapshotUsesOutputFrameUnitsAndReportsBacklog() {
        let snapshot = AudioSessionTelemetrySnapshot(
            sessionID: "session-1",
            elapsedMilliseconds: 30_000,
            sampleRate: 16_000,
            bleNotificationsTotal: 250,
            bleBytesTotal: 30_000,
            decodedFramesTotal: 300,
            decodedSamplesTotal: 32_000,
            submittedFramesTotal: 96_000,
            renderedFramesTotal: 95_520,
            pendingRemoteFrames: 480,
            audioQueueDepthFrames: 640,
            activeUnderrunFramesTotal: 96,
            activeUnderrunCallbacksTotal: 3,
            droppedFramesTotal: 480,
            overflowFramesTotal: 480
        )

        XCTAssertEqual(snapshot.decodedOutputFramesTotal, 96_000)
        XCTAssertEqual(snapshot.decodedMinusRenderedFrames, 480)
        XCTAssertEqual(snapshot.pendingAudioMilliseconds, 10.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.decodeRenderLagMilliseconds, 10.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.downstreamDrainVisibility, .unavailable)
        XCTAssertTrue(snapshot.logLine.contains("session_id=session-1"))
        XCTAssertTrue(snapshot.logLine.contains("decoded_minus_rendered_frames=480"))
        XCTAssertTrue(snapshot.logLine.contains("downstream_drain_visibility=UNAVAILABLE"))
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
