import XCTest
@testable import RemoteOrbit

final class P1A5FrontEdgeDiagnosticsTests: XCTestCase {
    func testVoiceOnsetRequiresThreeConsecutiveVoicedFrames() {
        var detector = P1A5VoiceOnsetDetector()
        let quiet = [Int16](repeating: 100, count: 120)
        let voiced = [Int16](repeating: 500, count: 120)

        XCTAssertNil(detector.analyze(samples: quiet, frameIndex: 0, timestampNanoseconds: 100))
        XCTAssertNil(detector.analyze(samples: voiced, frameIndex: 1, timestampNanoseconds: 200))
        XCTAssertNil(detector.analyze(samples: voiced, frameIndex: 2, timestampNanoseconds: 300))
        let candidate = detector.analyze(samples: voiced, frameIndex: 3, timestampNanoseconds: 400)

        XCTAssertEqual(candidate?.timestampNanoseconds, 200)
        XCTAssertEqual(candidate?.frameIndex, 1)
        XCTAssertEqual(candidate?.consecutiveVoicedFrames, 3)
    }

    func testVoiceOnsetResetsAfterAQuietFrame() {
        var detector = P1A5VoiceOnsetDetector()
        let quiet = [Int16](repeating: 100, count: 120)
        let voiced = [Int16](repeating: 500, count: 120)

        XCTAssertNil(detector.analyze(samples: voiced, frameIndex: 0, timestampNanoseconds: 100))
        XCTAssertNil(detector.analyze(samples: quiet, frameIndex: 1, timestampNanoseconds: 200))
        XCTAssertNil(detector.analyze(samples: voiced, frameIndex: 2, timestampNanoseconds: 300))
        XCTAssertNil(detector.analyze(samples: voiced, frameIndex: 3, timestampNanoseconds: 400))
        XCTAssertNotNil(detector.analyze(samples: voiced, frameIndex: 4, timestampNanoseconds: 500))
    }

    func testUnderrunBucketsUseTheFixedFrontEdgeBoundaries() {
        var stats = P1A5FrontEdgeUnderrunStats()
        stats.record(distanceMilliseconds: 99.9, durationMilliseconds: 1)
        stats.record(distanceMilliseconds: 100, durationMilliseconds: 2)
        stats.record(distanceMilliseconds: 249.9, durationMilliseconds: 3)
        stats.record(distanceMilliseconds: 250, durationMilliseconds: 4)
        stats.record(distanceMilliseconds: 499.9, durationMilliseconds: 5)
        stats.record(distanceMilliseconds: 500, durationMilliseconds: 6)
        stats.record(distanceMilliseconds: 1_000, durationMilliseconds: 7)

        XCTAssertEqual(stats.buckets.map(\.count), [1, 2, 2, 2])
        XCTAssertEqual(stats.buckets.map(\.durationMilliseconds), [1, 5, 9, 13])
    }
}
