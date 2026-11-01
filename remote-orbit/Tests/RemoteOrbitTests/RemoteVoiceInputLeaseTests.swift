import XCTest
@testable import RemoteOrbit

/// Domain 6 temporary system-input lease: a promoted remote LONG temporarily
/// selects `RemoteOrbit Mic 2ch`; the persisted preferred input is restored
/// only after the final remote output drain, never at transport stop, and a
/// rapid direct repress transfers the lease without an intermediate restore.
/// All assertions run through injected closures; no test mutates the host's
/// real default input, CoreAudio, driver, or TCC state.
final class RemoteVoiceInputLeaseTests: XCTestCase {
    private func makePress(
        candidateTimerFactory: (
            (TimeInterval, @escaping () -> Void) -> VoicePressCandidateTimer
        )? = nil
    ) -> VoicePressCoordinator {
        VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in },
            candidateTimerFactory: candidateTimerFactory ?? { _, _ in
                VoicePressCandidateTimer(cancelAction: {})
            }
        )
    }

    /// Drive one full synthetic direct session from opening to a captured
    /// output-drain completion, mirroring the production Gate-A order.
    private func driveSessionToPendingDrain(
        _ press: VoicePressCoordinator,
        sessionID: UUID
    ) {
        XCTAssertTrue(
            press.keyDownForTesting(
                sessionID: sessionID,
                usesHardwareOption: false,
                profile: .defaultProfile,
            )
        )
        XCTAssertTrue(press.remoteInputLeaseHeldForTesting)
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
    }

    func testPreferredInputRestoresOnlyAfterActualOutputDrain() {
        let press = makePress()
        var drainCompletions: [() -> Void] = []
        var leaseReleases = 0
        press.onRemoteOutputDrain = { _, completion in
            drainCompletions.append(completion)
        }
        press.onRemoteInputLeaseRelease = { leaseReleases += 1 }

        let sessionA = UUID()
        driveSessionToPendingDrain(press, sessionID: sessionA)

        // Transport stop / setRemoteActive(false) must not restore the
        // persisted preferred input while queued remote PCM still owns it.
        XCTAssertEqual(drainCompletions.count, 1)
        XCTAssertTrue(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 0)

        drainCompletions[0]()
        XCTAssertFalse(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 1)

        // The final restore is bounded: a repeated drain completion for the
        // same session must not restore a second time.
        drainCompletions[0]()
        XCTAssertEqual(leaseReleases, 1)

        press.stop()
        XCTAssertEqual(leaseReleases, 1)
    }

    func testRapidDirectRepressTransfersLeaseWithoutIntermediateRestore() {
        let press = makePress()
        var livePhysicalCandidate = false
        var drainCompletions: [() -> Void] = []
        var leaseReleases = 0
        press.hasLivePhysicalCandidate = { livePhysicalCandidate }
        press.onRemoteOutputDrain = { _, completion in
            drainCompletions.append(completion)
        }
        press.onRemoteInputLeaseRelease = { leaseReleases += 1 }

        let sessionA = UUID()
        driveSessionToPendingDrain(press, sessionID: sessionA)
        XCTAssertEqual(drainCompletions.count, 1)

        // B's raw press arrives while A still owns its output drain.
        livePhysicalCandidate = true
        let sessionB = UUID()
        XCTAssertTrue(
            press.keyDownForTesting(
                sessionID: sessionB,
                usesHardwareOption: false,
                profile: .defaultProfile,
            )
        )
        XCTAssertEqual(press.pendingRepressSessionID, sessionB)

        // A's actual drain completes; the lease transfers to B instead of
        // restoring a physical input between the two sessions.
        drainCompletions[0]()
        XCTAssertTrue(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 0, "A→B must not restore the input mid-handoff")

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(
            press.currentGestureIDForDiagnostics,
            sessionB,
            "B must activate after A's completion"
        )
        XCTAssertTrue(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 0)

        livePhysicalCandidate = false
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(drainCompletions.count, 2)

        drainCompletions[1]()
        XCTAssertFalse(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 1, "final B drain restores exactly once")
    }

    func testLivePhysicalCandidateEpochRetainsLeaseUntilEpochEnds() {
        let press = makePress()
        var drainCompletions: [() -> Void] = []
        var leaseReleases = 0
        press.onRemoteOutputDrain = { _, completion in
            drainCompletions.append(completion)
        }
        press.onRemoteInputLeaseRelease = { leaseReleases += 1 }

        let sessionA = UUID()
        driveSessionToPendingDrain(press, sessionID: sessionA)

        // A replacement physical epoch is already live when A completes; the
        // lease must not flip the input while that epoch may still promote.
        press.setPreHIDPhysicalStreaming(true)
        drainCompletions[0]()
        XCTAssertTrue(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 0)

        // The epoch dies without promoting into a session: the lease is
        // released at that boundary instead of being stranded on RemoteOrbit.
        press.setPreHIDPhysicalStreaming(false)
        XCTAssertFalse(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 1)

        press.stop()
    }

    func testShortTapAfterTransferredLeaseReleasesWhenCandidateCancels() {
        var fireCandidateTimer: (() -> Void)?
        let press = makePress(
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        var livePhysicalCandidate = false
        var drainCompletions: [() -> Void] = []
        var leaseReleases = 0
        press.hasLivePhysicalCandidate = { livePhysicalCandidate }
        press.onRemoteOutputDrain = { _, completion in
            drainCompletions.append(completion)
        }
        press.onRemoteInputLeaseRelease = { leaseReleases += 1 }

        let sessionA = UUID()
        driveSessionToPendingDrain(press, sessionID: sessionA)

        livePhysicalCandidate = true
        drainCompletions[0]()
        XCTAssertTrue(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 0)

        // The epoch ends and a SHORT tap (< 300 ms, never promoted) cancels
        // its candidate: the retained lease must be released, not stranded.
        livePhysicalCandidate = false
        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(sessionID: sessionB, preparesRemoteTransport: true))
        XCTAssertNotNil(fireCandidateTimer)
        XCTAssertTrue(press.keyUp())

        XCTAssertFalse(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 1)

        press.stop()
    }

    func testPendingRepressReleasedBeforeActivationReleasesLease() {
        let press = makePress()
        var livePhysicalCandidate = false
        var drainCompletions: [() -> Void] = []
        var leaseReleases = 0
        press.hasLivePhysicalCandidate = { livePhysicalCandidate }
        press.onRemoteOutputDrain = { _, completion in
            drainCompletions.append(completion)
        }
        press.onRemoteInputLeaseRelease = { leaseReleases += 1 }

        let sessionA = UUID()
        driveSessionToPendingDrain(press, sessionID: sessionA)

        livePhysicalCandidate = true
        let sessionB = UUID()
        XCTAssertTrue(
            press.keyDownForTesting(
                sessionID: sessionB,
                usesHardwareOption: false,
                profile: .defaultProfile,
            )
        )
        XCTAssertEqual(press.pendingRepressSessionID, sessionB)

        // B is released before activation and its epoch ends. A's direct
        // session still owns the lease until its own output drain completes;
        // the release must then happen exactly once.
        livePhysicalCandidate = false
        XCTAssertFalse(press.keyUp())
        XCTAssertNil(press.pendingRepressSessionID)
        XCTAssertTrue(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 0)

        drainCompletions[0]()
        XCTAssertFalse(press.remoteInputLeaseHeldForTesting)
        XCTAssertEqual(leaseReleases, 1)

        press.stop()
    }
}
