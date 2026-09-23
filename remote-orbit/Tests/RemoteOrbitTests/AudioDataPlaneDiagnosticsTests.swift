import XCTest
@testable import RemoteOrbit

final class AudioDataPlaneDiagnosticsTests: XCTestCase {
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
}
