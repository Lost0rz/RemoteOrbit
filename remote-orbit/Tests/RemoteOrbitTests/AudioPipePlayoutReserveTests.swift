import Foundation
import XCTest
@testable import RemoteOrbit

final class AudioPipePlayoutReserveTests: XCTestCase {
    func testCandidatesConvertToExact48kFrameThresholds() {
        XCTAssertEqual(AudioPipePlayoutReserveCandidate.zero.frames, 0)
        XCTAssertEqual(AudioPipePlayoutReserveCandidate.milliseconds45.frames, 2_160)
        XCTAssertEqual(AudioPipePlayoutReserveCandidate.milliseconds75.frames, 3_600)
        XCTAssertEqual(AudioPipePlayoutReserveCandidate.milliseconds100.frames, 4_800)
    }

    func testInactiveEmptyDoesNotTailBypassOrStartReserve() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)

        XCTAssertEqual(
            reserve.decision(remoteActive: false, queuedFrames: 0, now: 2_000),
            .consume
        )

        let snapshot = reserve.snapshot(at: 2_000)
        XCTAssertEqual(snapshot.state, .waitingForReserve)
        XCTAssertNil(snapshot.startDepthFrames)
        XCTAssertNil(snapshot.startReason)
    }

    func testInactiveTailStillBypassesReserveExactlyOnce() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)

        XCTAssertEqual(
            reserve.decision(remoteActive: false, queuedFrames: 320, now: 2_000),
            .tailBypass
        )
        XCTAssertEqual(
            reserve.decision(remoteActive: false, queuedFrames: 320, now: 3_000),
            .consume
        )
        XCTAssertEqual(reserve.snapshot(at: 3_000).startReason, .tailBypass)
    }

    func testZeroMillisecondControlStartsOnFirstAvailablePCM() {
        let reserve = AudioPipePlayoutReserve(candidate: .zero)
        reserve.reset(at: 1_000)

        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 1, now: 2_000),
            .consume
        )
        XCTAssertEqual(reserve.snapshot(at: 2_000).startDepthFrames, 1)
        XCTAssertEqual(reserve.snapshot(at: 2_000).startReason, .threshold)
    }

    func testReserveWaitsUntilConfiguredThresholdThenStartsOnce() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)

        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_159, now: 2_000),
            .wait
        )
        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 3_000),
            .consume
        )
        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 0, now: 4_000),
            .consume
        )
        XCTAssertEqual(reserve.snapshot(at: 4_000).startDepthFrames, 2_160)
    }

    func testEachPositiveCandidateWaitsBelowThresholdAndStartsAtThreshold() {
        for candidate in [
            AudioPipePlayoutReserveCandidate.milliseconds45,
            .milliseconds75,
            .milliseconds100
        ] {
            let reserve = AudioPipePlayoutReserve(candidate: candidate)
            reserve.reset(at: 1_000)

            XCTAssertEqual(
                reserve.decision(
                    remoteActive: true,
                    queuedFrames: candidate.frames - 1,
                    now: 2_000
                ),
                .wait,
                "candidate=\(candidate)"
            )
            XCTAssertEqual(
                reserve.decision(
                    remoteActive: true,
                    queuedFrames: candidate.frames,
                    now: 3_000
                ),
                .consume,
                "candidate=\(candidate)"
            )
        }
    }

    func testTailBypassStartsBelowThresholdAndNeverStrandsQueuedFrames() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds100)
        reserve.reset(at: 1_000)

        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 320, now: 2_000),
            .wait
        )
        XCTAssertEqual(
            reserve.decision(remoteActive: false, queuedFrames: 320, now: 3_000),
            .tailBypass
        )
        XCTAssertEqual(reserve.snapshot(at: 3_000).startReason, .tailBypass)
        XCTAssertEqual(
            reserve.decision(remoteActive: false, queuedFrames: 0, now: 4_000),
            .consume
        )
    }

    func testResetCreatesFreshWaitingStateAfterPreviousStreamStarted() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)
        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 2_000),
            .consume
        )

        reserve.reset(at: 10_000)

        XCTAssertEqual(reserve.snapshot(at: 10_000).state, .waitingForReserve)
        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_159, now: 11_000),
            .wait
        )
    }

    func testNewSessionResetAfterPreviousStartDoesNotStartDuringInactiveEmptyWindow() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)
        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 2_000),
            .consume
        )

        reserve.reset(at: 10_000)
        XCTAssertEqual(
            reserve.decision(remoteActive: false, queuedFrames: 0, now: 11_000),
            .consume
        )
        XCTAssertEqual(reserve.snapshot(at: 11_000).state, .waitingForReserve)

        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 480, now: 12_000),
            .wait
        )
        let snapshot = reserve.snapshot(at: 12_000)
        XCTAssertEqual(snapshot.state, .waitingForReserve)
        XCTAssertNil(snapshot.startReason)
    }

    func testStartedSnapshotPublishesCoherentStartMetadata() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)

        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 3_000),
            .consume
        )

        let snapshot = reserve.snapshot(at: 4_000)
        XCTAssertEqual(snapshot.state, .started)
        XCTAssertNotNil(snapshot.startDepthFrames)
        XCTAssertEqual(snapshot.startDepthFrames, 2_160)
        XCTAssertEqual(snapshot.startReason, .threshold)
        XCTAssertGreaterThan(snapshot.waitDurationNanoseconds, 0)
    }

    func testConcurrentRenderDecisionsCannotPublishPartialStartMetadata() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)
        let decisionsLock = NSLock()
        var decisions = [AudioPipePlayoutReserveDecision]()
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            let decision = reserve.decision(
                remoteActive: true,
                queuedFrames: 2_160,
                now: UInt64(2_000 + index)
            )
            decisionsLock.lock()
            decisions.append(decision)
            decisionsLock.unlock()
        }

        XCTAssertTrue(decisions.allSatisfy { $0 == .wait || $0 == .consume })
        let snapshot = reserve.snapshot(at: 3_000)
        XCTAssertEqual(snapshot.state, .started)
        XCTAssertNotNil(snapshot.startDepthFrames)
        XCTAssertNotNil(snapshot.startReason)
        XCTAssertGreaterThan(snapshot.waitDurationNanoseconds, 0)
    }

    func testCandidateComparisonShowsSmallestUsefulCandidateAndSustainedDeficitLimit() {
        let comparison = AudioPipeReserveSimulation.shortJitterComparison()

        XCTAssertEqual(comparison.map(\.candidate), [.zero, .milliseconds45, .milliseconds75, .milliseconds100])
        XCTAssertGreaterThan(comparison[0].activeUnderrunFrames, 0)
        XCTAssertEqual(comparison[1].activeUnderrunFrames, 0)
        XCTAssertEqual(comparison[2].activeUnderrunFrames, 0)
        XCTAssertEqual(comparison[3].activeUnderrunFrames, 0)
        XCTAssertEqual(comparison[1].tailBypassCount, 0)
        XCTAssertEqual(comparison[1].droppedOrStrandedPCM, 0)
        XCTAssertEqual(
            AudioPipeReserveSimulation.selectSmallestUseful(from: comparison),
            .milliseconds45
        )
        XCTAssertEqual(comparison[0].startupLatencyMilliseconds, 0)
        XCTAssertEqual(comparison[0].actualStartDepthFrames, 480)
        XCTAssertEqual(comparison[0].activeUnderrunCallbacks, 3)
        XCTAssertEqual(comparison[0].activeUnderrunFrames, 1_440)
        XCTAssertEqual(comparison[1].startupLatencyMilliseconds, 40)
        XCTAssertEqual(comparison[1].actualStartDepthFrames, 4_080)
        XCTAssertEqual(comparison[2].startupLatencyMilliseconds, 40)
        XCTAssertEqual(comparison[2].actualStartDepthFrames, 4_080)
        XCTAssertEqual(comparison[3].startupLatencyMilliseconds, 60)
        XCTAssertEqual(comparison[3].actualStartDepthFrames, 5_280)

        let deficit = AudioPipeReserveSimulation.sustainedDeficitComparison()
        XCTAssertEqual(deficit.count, 4)
        XCTAssertTrue(deficit.allSatisfy { $0.activeUnderrunFrames > 0 })
        XCTAssertTrue(deficit.allSatisfy { $0.activeUnderrunCallbacks == 6 })
        XCTAssertTrue(deficit.allSatisfy { $0.activeUnderrunFrames == 1_440 })
        XCTAssertTrue(deficit.allSatisfy { $0.droppedOrStrandedPCM == 0 })
    }
}
