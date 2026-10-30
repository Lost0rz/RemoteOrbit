import XCTest
import AudioToolbox
@testable import RemoteOrbit

final class AudioPipeTests: XCTestCase {
    func testActivePublicationOrderInitializesConsumerStateBeforeRealtimeActive() {
        var observed: [AudioPipeActivationStep] = []

        AudioPipeRemoteActivationTransition.perform(
            withdrawRealtimeActive: { observed.append(.withdrawRealtimeActive) },
            clearPriorDrainWaiter: { observed.append(.clearPriorDrainWaiter) },
            resetOutputRing: { observed.append(.resetOutputRing) },
            resetPlayoutReserve: { observed.append(.resetPlayoutReserve) },
            resetSessionBookkeeping: { observed.append(.resetSessionBookkeeping) },
            publishRealtimeActive: { observed.append(.publishRealtimeActive) }
        )

        XCTAssertEqual(
            observed,
            [
                .withdrawRealtimeActive,
                .clearPriorDrainWaiter,
                .resetOutputRing,
                .resetPlayoutReserve,
                .resetSessionBookkeeping,
                .publishRealtimeActive
            ]
        )
    }

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

    func testPrebufferPromotedOnPhysicalStreamAdoption() {
        let pipe = AudioPipe.shared
        pipe.setRemoteActive(false)
        pipe.endRemoteCandidate()
        pipe.beginRemoteCandidate()

        let samples = Array(repeating: Int16(11), count: 160)
        pipe.feed(samples: samples)
        pipe.beginRemoteCandidate()

        XCTAssertEqual(pipe.setRemoteActive(true), samples.count)
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

    func testReserveWaitDoesNotConsumePCMOrAdvanceDiagnosticsMarkers() {
        let pipe = AudioPipe.shared
        _ = pipe.setRemoteActive(false)
        _ = pipe.setRemoteActive(true)
        pipe.feed(samples: Array(repeating: Int16(3), count: 160))

        let output = render(pipe, frames: 480)

        XCTAssertTrue(output.allSatisfy { $0 == 0 })
        XCTAssertEqual(pipe.queuedOutputFrames, 480)
        let snapshot = pipe.takeAudioDiagnosticsSnapshot()
        XCTAssertEqual(snapshot.reserveState, .waitingForReserve)
        XCTAssertEqual(snapshot.reserveConfiguredFrames, 2_160)
        XCTAssertEqual(snapshot.underrunCallbackCount, 0)
        XCTAssertEqual(snapshot.renderedRemoteFrames, 0)

        _ = pipe.setRemoteActive(false)
    }

    func testThresholdStartConsumesPCMAndThenCountsARealUnderflowWithoutRearm() {
        let pipe = AudioPipe.shared
        _ = pipe.setRemoteActive(false)
        pipe.beginRemoteAudioDiagnostics()
        _ = pipe.setRemoteActive(true)
        pipe.feed(samples: Array(repeating: Int16(3), count: 720))

        let firstOutput = render(pipe, frames: 480)
        XCTAssertTrue(firstOutput.contains { abs($0) > 0.0001 })

        let beforeUnderflow = pipe.takeAudioDiagnosticsSnapshot()
        XCTAssertEqual(beforeUnderflow.reserveState, .started)
        XCTAssertEqual(beforeUnderflow.reserveStartReason, .threshold)

        for _ in 0..<4 {
            _ = render(pipe, frames: 480)
        }
        let afterUnderflow = pipe.takeAudioDiagnosticsSnapshot()
        XCTAssertEqual(afterUnderflow.reserveState, .started)
        XCTAssertGreaterThan(afterUnderflow.underrunCallbackCount, 0)

        _ = pipe.setRemoteActive(false)
        _ = pipe.endRemoteAudioDiagnostics()
    }

    func testTailBypassRendersShortUtteranceBeforeReserveThresholdAndDrains() {
        let pipe = AudioPipe.shared
        _ = pipe.setRemoteActive(false)
        _ = pipe.setRemoteActive(true)
        pipe.feed(samples: Array(repeating: Int16(3), count: 160))
        _ = pipe.setRemoteActive(false)

        let completion = expectation(description: "tail drain completion")
        pipe.waitForOutputDrain { completion.fulfill() }
        let output = render(pipe, frames: 480)

        XCTAssertTrue(output.contains { abs($0) > 0.0001 })
        XCTAssertEqual(pipe.queuedOutputFrames, 0)
        wait(for: [completion], timeout: 1)

        let snapshot = pipe.takeAudioDiagnosticsSnapshot()
        XCTAssertEqual(snapshot.reserveState, .started)
        XCTAssertEqual(snapshot.reserveStartReason, .tailBypass)
    }

    private func render(_ pipe: AudioPipe, frames: Int) -> [Float] {
        var output = [Float](repeating: -1, count: frames * 2)
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
        return output
    }
}
