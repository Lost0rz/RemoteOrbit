import XCTest
@testable import RemoteOrbit

final class BLEAudioContinuityProbeTests: XCTestCase {
    func testHandlerSummaryReportsExactPercentilesAndThresholdCounts() {
        var probe = BLEAudioContinuityProbe()
        probe.reset(startTimestampNanoseconds: 0, initialQueueDepthFrames: 0)

        for millisecond in 1...100 {
            let start = UInt64(millisecond) * 200_000_000
            probe.recordHandlerDuration(
                startTimestampNanoseconds: start,
                endTimestampNanoseconds: start + UInt64(millisecond) * 1_000_000
            )
        }

        let summary = probe.handlerSummary()
        XCTAssertEqual(summary.sampleCount, 100)
        XCTAssertEqual(summary.p50Microseconds, 50_000)
        XCTAssertEqual(summary.p95Microseconds, 95_000)
        XCTAssertEqual(summary.p99Microseconds, 99_000)
        XCTAssertEqual(summary.maxMicroseconds, 100_000)
        XCTAssertEqual(summary.over5Milliseconds, 95)
        XCTAssertEqual(summary.over10Milliseconds, 90)
        XCTAssertEqual(summary.over15Milliseconds, 85)
    }

    func testOneSecondSupplyWindowReportsEffectiveRateGapAndQueueDepth() throws {
        var probe = BLEAudioContinuityProbe()
        let start: UInt64 = 1_000_000_000
        probe.reset(
            startTimestampNanoseconds: start,
            initialQueueDepthFrames: 2_160
        )

        probe.recordNotification(timestampNanoseconds: start)
        probe.recordDecodedSamples(4_000)
        probe.recordNotification(timestampNanoseconds: start + 500_000_000)
        probe.recordDecodedSamples(8_000)
        probe.recordNotification(timestampNanoseconds: start + 1_000_000_000)
        probe.recordDecodedSamples(4_000)

        let window = try XCTUnwrap(
            probe.closeWindowIfNeeded(
                at: start + 1_000_000_000,
                queueDepthFrames: 720
            )
        )
        XCTAssertEqual(window.index, 0)
        XCTAssertEqual(window.elapsedNanoseconds, 1_000_000_000)
        XCTAssertEqual(window.decodedSamples, 16_000)
        XCTAssertEqual(window.notificationCount, 3)
        XCTAssertEqual(window.maxNotificationGapNanoseconds, 500_000_000)
        XCTAssertEqual(window.queueDepthStartFrames, 2_160)
        XCTAssertEqual(window.queueDepthEndFrames, 720)
        XCTAssertEqual(window.effectiveSourceHz, 16_000, accuracy: 0.001)
    }

    func testFinalPartialWindowUsesLastNotificationNotDrainFinish() throws {
        var probe = BLEAudioContinuityProbe()
        let start: UInt64 = 5_000_000_000
        probe.reset(startTimestampNanoseconds: start, initialQueueDepthFrames: 720)
        probe.recordNotification(timestampNanoseconds: start + 100_000_000)
        probe.recordDecodedSamples(3_200)
        probe.recordNotification(timestampNanoseconds: start + 300_000_000)
        probe.recordDecodedSamples(1_600)

        let window = try XCTUnwrap(probe.finish(queueDepthFrames: 0))
        XCTAssertEqual(window.elapsedNanoseconds, 300_000_000)
        XCTAssertEqual(window.decodedSamples, 4_800)
        XCTAssertEqual(window.notificationCount, 2)
        XCTAssertEqual(window.effectiveSourceHz, 16_000, accuracy: 0.001)
        XCTAssertEqual(window.queueDepthStartFrames, 720)
        XCTAssertEqual(window.queueDepthEndFrames, 0)
    }

    func testWindowDoesNotEmitBeforeTargetDuration() {
        var probe = BLEAudioContinuityProbe()
        probe.reset(startTimestampNanoseconds: 10, initialQueueDepthFrames: 0)
        probe.recordNotification(timestampNanoseconds: 500_000_010)
        probe.recordDecodedSamples(8_000)

        XCTAssertNil(
            probe.closeWindowIfNeeded(
                at: 999_999_999,
                queueDepthFrames: 0
            )
        )
    }
}
