import XCTest
@testable import RemoteOrbit

final class AudioDataPlaneMeasurementBoundaryTests: XCTestCase {
    func testDeliveryRatioExcludesPostStopDrainIdle() {
        let timing = AudioDeliveryTiming.measure(
            streamStartedAt: 0,
            audioStopReceivedAt: 10.0,
            lastAudioAt: 10.0,
            drainFinishedAt: 10.35
        )
        let delivery = AudioDeliveryAccounting.measure(
            decodedSamples: 160_000,
            sampleRate: 16_000,
            elapsedSeconds: timing.measurementElapsedSeconds
        )

        XCTAssertEqual(timing.measurementElapsedSeconds, 10.0, accuracy: 0.0001)
        XCTAssertEqual(timing.lifecycleElapsedSeconds, 10.35, accuracy: 0.0001)
        XCTAssertEqual(delivery.deliveryRatio, 1.0, accuracy: 0.0001)
    }

    func testDeliveryRatioStillReportsRealPcmDeficit() {
        let timing = AudioDeliveryTiming.measure(
            streamStartedAt: 0,
            audioStopReceivedAt: 10.0,
            lastAudioAt: 10.0,
            drainFinishedAt: 10.35
        )
        let delivery = AudioDeliveryAccounting.measure(
            decodedSamples: 144_000,
            sampleRate: 16_000,
            elapsedSeconds: timing.measurementElapsedSeconds
        )

        XCTAssertEqual(delivery.deliveryRatio, 0.9, accuracy: 0.0001)
        XCTAssertEqual(delivery.deficitSamples, 16_000)
    }

    func testLateTailExtendsMeasurementOnlyThroughLastAudioFrame() {
        let timing = AudioDeliveryTiming.measure(
            streamStartedAt: 0,
            audioStopReceivedAt: 10.0,
            lastAudioAt: 10.08,
            drainFinishedAt: 10.35
        )

        XCTAssertEqual(timing.measurementElapsedSeconds, 10.08, accuracy: 0.0001)
        XCTAssertEqual(timing.lifecycleElapsedSeconds, 10.35, accuracy: 0.0001)
        XCTAssertEqual(timing.stopToLastAudioMilliseconds ?? -1, 80, accuracy: 0.0001)
        XCTAssertEqual(timing.postLastAudioDrainMilliseconds ?? -1, 270, accuracy: 0.0001)
    }

    func testNoAudioFallsBackToAudioStopForDeliveryMeasurement() {
        let timing = AudioDeliveryTiming.measure(
            streamStartedAt: 0,
            audioStopReceivedAt: 2.5,
            lastAudioAt: nil,
            drainFinishedAt: 2.85
        )

        XCTAssertEqual(timing.measurementElapsedSeconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(timing.lastAudioAtMilliseconds, nil)
        XCTAssertEqual(timing.postLastAudioDrainMilliseconds, nil)
    }

    func testIdleRemoteRenderIsNotAccountedAsUnderrun() {
        let render = AudioPipeRenderAccounting.measure(
            requestedFrames: 512,
            availableRemoteFrames: 0,
            pendingRemoteFrames: 0,
            remoteActive: false,
            remoteWasActive: false
        )

        XCTAssertEqual(render.state, .idle)
        XCTAssertFalse(render.accounted)
        XCTAssertEqual(render.activeUnderrunFrames, 0)
        XCTAssertEqual(render.activeUnderrunCallbacks, 0)
        XCTAssertEqual(render.idleRenderCallbacks, 1)
    }

    func testActiveRemoteStarvationIsCountedAsAnUnderrun() {
        let render = AudioPipeRenderAccounting.measure(
            requestedFrames: 512,
            availableRemoteFrames: 0,
            pendingRemoteFrames: 0,
            remoteActive: true,
            remoteWasActive: true
        )

        XCTAssertEqual(render.state, .activeRemote)
        XCTAssertTrue(render.accounted)
        XCTAssertEqual(render.activeUnderrunFrames, 512)
        XCTAssertEqual(render.activeUnderrunCallbacks, 1)
    }

    func testTailDrainCountsRemoteFramesWithoutActiveUnderrun() {
        let render = AudioPipeRenderAccounting.measure(
            requestedFrames: 512,
            availableRemoteFrames: 300,
            pendingRemoteFrames: 300,
            remoteActive: false,
            remoteWasActive: true
        )

        XCTAssertEqual(render.state, .tailDrain)
        XCTAssertEqual(render.tailRenderedFrames, 300)
        XCTAssertEqual(render.activeUnderrunFrames, 0)
        XCTAssertEqual(render.activeUnderrunCallbacks, 0)
        XCTAssertEqual(render.tailEmptyCallbacks, 0)
    }

    func testTailDrainEmptyCallbackIsSeparateFromIdleAndUnderrun() {
        let render = AudioPipeRenderAccounting.measure(
            requestedFrames: 512,
            availableRemoteFrames: 0,
            pendingRemoteFrames: 0,
            remoteActive: false,
            remoteWasActive: true
        )

        XCTAssertEqual(render.state, .tailDrain)
        XCTAssertEqual(render.tailEmptyCallbacks, 1)
        XCTAssertEqual(render.activeUnderrunCallbacks, 0)
        XCTAssertEqual(render.idleRenderCallbacks, 0)
    }

    func testLocalOnlyQueueDoesNotEnterRemoteDiagnostics() {
        XCTAssertEqual(
            AudioRemoteQueueAttribution.remoteQueueDepth(
                totalQueueFrames: 512,
                pendingRemoteFrames: 0
            ),
            0
        )
        XCTAssertEqual(
            AudioRemoteQueueAttribution.remoteDroppedFrames(
                totalDroppedFrames: 128,
                pendingRemoteFrames: 0
            ),
            0
        )
        XCTAssertEqual(
            AudioRemoteQueueAttribution.remoteDroppedFrames(
                totalDroppedFrames: 128,
                pendingRemoteFrames: 64,
                sourceIsRemote: false
            ),
            0
        )
        XCTAssertFalse(
            AudioRemoteQueueAttribution.shouldRecordCompaction(
                remoteActive: false,
                pendingRemoteFrames: 0
            )
        )
    }

    func testMixedQueueAttributesOnlyDroppedRemotePrefix() {
        XCTAssertEqual(
            AudioRemoteQueueAttribution.remoteQueueDepth(
                totalQueueFrames: 512,
                pendingRemoteFrames: 64
            ),
            64
        )
        XCTAssertEqual(
            AudioRemoteQueueAttribution.remoteDroppedFrames(
                totalDroppedFrames: 128,
                pendingRemoteFrames: 64
            ),
            64
        )
    }
}
