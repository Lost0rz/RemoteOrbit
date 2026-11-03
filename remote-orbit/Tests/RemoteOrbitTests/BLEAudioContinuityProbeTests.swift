import XCTest
@testable import RemoteOrbit

final class BLEAudioContinuityProbeTests: XCTestCase {
    func testHandlerSummaryPairsBLEArrivalToNextPCMSubmit() {
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
        ).handlerLatency

        XCTAssertEqual(summary.sampleCount, 100)
        XCTAssertEqual(summary.p50Microseconds, 50_000)
        XCTAssertEqual(summary.p95Microseconds, 95_000)
        XCTAssertEqual(summary.p99Microseconds, 99_000)
        XCTAssertEqual(summary.maxMicroseconds, 100_000)
        XCTAssertEqual(summary.over5Milliseconds, 95)
        XCTAssertEqual(summary.over10Milliseconds, 90)
        XCTAssertEqual(summary.over15Milliseconds, 85)
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

        let boundaryWindow = try XCTUnwrap(analysis.supplyWindows.dropFirst().first)
        XCTAssertEqual(boundaryWindow.queueDepthStartFrames, 1_200)
        XCTAssertEqual(boundaryWindow.queueDepthEndFrames, 720)
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
        XCTAssertEqual(analysis.handlerLatency.sampleCount, 1)
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
