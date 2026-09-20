import XCTest
@testable import RemoteOrbit

final class AudioPipeTests: XCTestCase {
    func testOutputDrainRequiresInactiveRouteAndEmptyQueue() {
        XCTAssertFalse(
            AudioPipe.isOutputDrained(remoteActive: true, queuedFrames: 0)
        )
        XCTAssertFalse(
            AudioPipe.isOutputDrained(remoteActive: false, queuedFrames: 128)
        )
        XCTAssertTrue(
            AudioPipe.isOutputDrained(remoteActive: false, queuedFrames: 0)
        )
    }

    func testNegativeQueueAccountingIsAlsoDrained() {
        XCTAssertTrue(
            AudioPipe.isOutputDrained(remoteActive: false, queuedFrames: -1)
        )
    }

    func testPendingRemotePCMReportsHowMuchWasFlushedOnActivation() {
        let pipe = AudioPipe.shared
        pipe.setRemoteActive(false)
        pipe.endRemoteCandidate()
        pipe.beginRemoteCandidate()

        let samples = Array(repeating: Int16(7), count: 320)
        pipe.feed(samples: samples)

        let flushed = pipe.setRemoteActive(true)

        XCTAssertEqual(flushed, samples.count)
        pipe.setRemoteActive(false)
        pipe.endRemoteCandidate()
    }

    func testPendingRemotePCMIsDiscardedWhenCandidateEndsBeforeNextGesture() {
        let pipe = AudioPipe.shared
        pipe.setRemoteActive(false)
        pipe.endRemoteCandidate()
        pipe.beginRemoteCandidate()
        pipe.feed(samples: Array(repeating: Int16(9), count: 64))
        pipe.endRemoteCandidate()

        let flushed = pipe.setRemoteActive(true)

        XCTAssertEqual(flushed, 0)
        pipe.setRemoteActive(false)
    }
}
