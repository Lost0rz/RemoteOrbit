import XCTest
@testable import RemoteOrbit

final class AudioPathIsolationDiagnosticsTests: XCTestCase {
    func testMainQueueStallMonitorRecordsOnlyLagAboveThreshold() {
        var monitor = MainQueueStallMonitor(
            interval: 0.25,
            threshold: 0.05
        )
        monitor.start(sessionID: "session-1", at: 10.0)

        XCTAssertNil(monitor.record(actualUptime: 10.25))

        guard let event = monitor.record(actualUptime: 10.56) else {
            XCTFail("expected a main-queue stall event")
            return
        }
        XCTAssertEqual(event.sessionID, "session-1")
        XCTAssertEqual(event.elapsedMilliseconds, 560.0, accuracy: 0.0001)
        XCTAssertEqual(event.expectedFireMilliseconds, 500.0, accuracy: 0.0001)
        XCTAssertEqual(event.actualFireMilliseconds, 560.0, accuracy: 0.0001)
        XCTAssertEqual(event.lagMilliseconds, 60.0, accuracy: 0.0001)

        XCTAssertEqual(monitor.summary.stallCount, 1)
        XCTAssertEqual(monitor.summary.maxLagMilliseconds, 60.0, accuracy: 0.0001)
        XCTAssertEqual(monitor.summary.p95LagMilliseconds, 60.0, accuracy: 0.0001)
    }

    func testIsolationWindowTracksNotificationBurstByteAndDecodeRatios() throws {
        var accumulator = AudioPathIsolationWindowAccumulator(
            sessionID: "session-1",
            startedAt: 100.0
        )

        accumulator.recordNotification(
            size: 120,
            gapMilliseconds: nil,
            completeFramesFromBytes: 1,
            frameAccumulatorBufferedBytes: 0,
            at: 100.1
        )
        accumulator.recordNotification(
            size: 120,
            gapMilliseconds: 0.5,
            completeFramesFromBytes: 1,
            frameAccumulatorBufferedBytes: 0,
            at: 100.2
        )
        accumulator.recordNotification(
            size: 60,
            gapMilliseconds: 250.0,
            completeFramesFromBytes: 0,
            frameAccumulatorBufferedBytes: 60,
            at: 100.3
        )
        accumulator.recordDecoded(
            frameCount: 2,
            sampleCount: 480,
            rejected: false
        )

        let snapshot = try XCTUnwrap(accumulator.roll(at: 101.1))
        XCTAssertEqual(snapshot.notificationCount, 3)
        XCTAssertEqual(snapshot.notificationBytes, 300)
        XCTAssertEqual(snapshot.completeFramesFromBytes, 2)
        XCTAssertEqual(snapshot.decodedFrames, 2)
        XCTAssertEqual(snapshot.decodedSamples, 480)
        XCTAssertEqual(snapshot.frameAccumulatorBufferedBytes, 60)
        XCTAssertEqual(snapshot.maxCallbackGapMilliseconds, 250.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.callbacksWithGapOver20, 1)
        XCTAssertEqual(snapshot.callbacksWithGapOver50, 1)
        XCTAssertEqual(snapshot.callbacksWithGapOver100, 1)
        XCTAssertEqual(snapshot.burstCallbacksUnder2Milliseconds, 1)
        XCTAssertEqual(snapshot.burstBytesUnder2Milliseconds, 120)
        XCTAssertEqual(snapshot.byteToFrameRatio(frameSize: 120), 0.8, accuracy: 0.0001)
        XCTAssertEqual(snapshot.frameToDecodeRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.decodeRejects, 0)
    }

    func testProcessingTimingSummaryComputesAverageP95AndMax() {
        var timing = AudioPathProcessingTimingAccumulator()
        timing.record(stage: .handleAudio, milliseconds: 0.1)
        timing.record(stage: .handleAudio, milliseconds: 0.2)
        timing.record(stage: .handleAudio, milliseconds: 1.0)

        let summary = timing.summary(for: .handleAudio)
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.averageMilliseconds, 0.4333333, accuracy: 0.0001)
        XCTAssertEqual(summary.p95Milliseconds, 1.0, accuracy: 0.0001)
        XCTAssertEqual(summary.maxMilliseconds, 1.0, accuracy: 0.0001)
    }
}
