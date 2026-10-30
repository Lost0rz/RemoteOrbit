import Foundation
import XCTest
@testable import RemoteOrbit

final class AudioPipePlayoutReserveTests: XCTestCase {
    func testDecisionBlocksResetPublicationOrder() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)
        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 2_000),
            .consume
        )
        let sessionASnapshot = reserve.snapshot(at: 3_000)
        XCTAssertEqual(sessionASnapshot.state, .started)
        XCTAssertEqual(sessionASnapshot.startDepthFrames, 2_160)

        XCTAssertTrue(reserve.claimDecisionForTesting())
        let resetWaiting = expectation(description: "reset waits for decision")
        let resetFinished = expectation(description: "reset completes after decision")
        DispatchQueue.global(qos: .userInitiated).async {
            reserve.resetForTesting(at: 10_000) {
                resetWaiting.fulfill()
            }
            resetFinished.fulfill()
        }

        wait(for: [resetWaiting], timeout: 1)
        reserve.releaseDecisionForTesting()
        wait(for: [resetFinished], timeout: 1)

        let resetSnapshot = reserve.snapshot(at: 11_000)
        XCTAssertEqual(resetSnapshot.state, .waitingForReserve)
        XCTAssertNil(resetSnapshot.startDepthFrames)
        XCTAssertNil(resetSnapshot.startReason)
    }

    func testResetNeverBlocksRealtimeDecision() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)
        reserve.beginResetForTesting()

        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 2_000),
            .wait
        )
        reserve.endResetForTesting()

        let snapshot = reserve.snapshot(at: 3_000)
        XCTAssertEqual(snapshot.state, .waitingForReserve)
        XCTAssertNil(snapshot.startDepthFrames)
        XCTAssertNil(snapshot.startReason)
    }

    func testStaleDecisionCannotResurrectNewSession() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)
        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 2_000),
            .consume
        )
        XCTAssertTrue(reserve.claimDecisionForTesting())

        let resetFinished = expectation(description: "new session reset")
        DispatchQueue.global(qos: .userInitiated).async {
            reserve.reset(at: 10_000)
            resetFinished.fulfill()
        }
        reserve.releaseDecisionForTesting()
        wait(for: [resetFinished], timeout: 1)

        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 480, now: 11_000),
            .wait
        )
        let sessionBSnapshot = reserve.snapshot(at: 11_000)
        XCTAssertEqual(sessionBSnapshot.state, .waitingForReserve)
        XCTAssertNil(sessionBSnapshot.startDepthFrames)
        XCTAssertNil(sessionBSnapshot.startReason)
    }

    func testStaleDecisionCannotCorruptNewSessionStartMetadata() {
        let reserve = AudioPipePlayoutReserve(candidate: .milliseconds45)
        reserve.reset(at: 1_000)
        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 2_000),
            .consume
        )
        XCTAssertTrue(reserve.claimDecisionForTesting())

        let resetFinished = expectation(description: "new session reset")
        DispatchQueue.global(qos: .userInitiated).async {
            reserve.reset(at: 10_000)
            resetFinished.fulfill()
        }
        reserve.releaseDecisionForTesting()
        wait(for: [resetFinished], timeout: 1)

        XCTAssertEqual(
            reserve.decision(remoteActive: true, queuedFrames: 2_160, now: 12_000),
            .consume
        )
        let sessionBSnapshot = reserve.snapshot(at: 13_000)
        XCTAssertEqual(sessionBSnapshot.state, .started)
        XCTAssertEqual(sessionBSnapshot.startDepthFrames, 2_160)
        XCTAssertEqual(sessionBSnapshot.startReason, .threshold)
        XCTAssertEqual(sessionBSnapshot.waitDurationNanoseconds, 2_000)
    }

    func testDecisionSourceHasNoRealtimeWaitOrSpin() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RemoteOrbit/AudioPipePlayoutReserve.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let decisionStart = try XCTUnwrap(source.range(of: "func decision("))
        let snapshotStart = try XCTUnwrap(
            source.range(of: "func snapshot(", range: decisionStart.upperBound..<source.endIndex)
        )
        let decisionBody = String(source[decisionStart.lowerBound..<snapshotStart.lowerBound])

        XCTAssertFalse(decisionBody.contains("sched_yield"))
        XCTAssertFalse(decisionBody.contains("while true"))
        XCTAssertFalse(decisionBody.contains("Thread.sleep"))
        XCTAssertTrue(decisionBody.contains("tryAcquireDecision"))
    }
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
