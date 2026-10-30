import XCTest
import AudioToolbox
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

    func testRingBackedQueuePreservesTailUntilNextSessionReset() {
        let pipe = AudioPipe.shared
        pipe.setRemoteActive(false)
        pipe.endRemoteCandidate()
        pipe.beginRemoteCandidate()
        _ = pipe.setRemoteActive(true)
        pipe.feed(samples: Array(repeating: Int16(3), count: 160))

        XCTAssertEqual(pipe.queuedOutputFrames, 480)

        _ = pipe.setRemoteActive(false)
        XCTAssertEqual(pipe.queuedOutputFrames, 480)

        _ = pipe.setRemoteActive(true)
        XCTAssertEqual(pipe.queuedOutputFrames, 0)
        _ = pipe.setRemoteActive(false)
        pipe.endRemoteCandidate()
    }

    func testOutputDrainCompletionWaitsForActualRingEmpty() {
        let pipe = AudioPipe.shared
        _ = pipe.setRemoteActive(true)
        pipe.feed(samples: Array(repeating: Int16(3), count: 160))
        XCTAssertGreaterThan(pipe.queuedOutputFrames, 0)

        _ = pipe.setRemoteActive(false)
        let completion = expectation(description: "output drain completion")
        var didComplete = false
        pipe.waitForOutputDrain {
            didComplete = true
            completion.fulfill()
        }
        XCTAssertFalse(didComplete)

        var output = [Float](repeating: -1, count: 480 * 2)
        output.withUnsafeMutableBytes { rawBuffer in
            let buffer = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(rawBuffer.count),
                mData: rawBuffer.baseAddress
            )
            var outputData = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: buffer
            )
            withUnsafeMutablePointer(to: &outputData) { pointer in
                pipe.render(pointer)
            }
        }

        XCTAssertEqual(pipe.queuedOutputFrames, 0)
        wait(for: [completion], timeout: 1)
        XCTAssertTrue(didComplete)

        _ = pipe.setRemoteActive(true)
        _ = pipe.setRemoteActive(false)
    }
}
