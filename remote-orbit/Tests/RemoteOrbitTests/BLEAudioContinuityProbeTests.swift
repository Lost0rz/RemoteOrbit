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
