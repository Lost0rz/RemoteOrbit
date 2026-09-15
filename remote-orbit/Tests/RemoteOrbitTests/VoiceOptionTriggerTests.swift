import XCTest
@testable import RemoteOrbit

final class VoiceOptionTriggerTests: XCTestCase {
    func testHardwareGateSelectsHardwareForCopiedPhysicalDown() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: true))
        XCTAssertEqual(gate.resolve(sessionID: session), .hardwareReplay)
        XCTAssertEqual(gate.owner(for: session), .hardware)
        gate.completeHardwareReplay(
            sessionID: session,
            replayedDown: true,
            replayedUp: false
        )
        XCTAssertFalse(gate.shouldSuppressLateHardwareEvent(.up, sessionID: session))
    }

    func testHardwareGateReleasesCapturedShortPairWithoutSyntheticOwner() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertEqual(gate.captureEvent(.down, copied: true), .deferred)
        XCTAssertEqual(gate.captureEvent(.up, copied: true), .deferred)
        XCTAssertEqual(gate.resolve(sessionID: session), .hardwareReplay)
        XCTAssertEqual(gate.owner(for: session), .hardware)
        gate.completeHardwareReplay(
            sessionID: session,
            replayedDown: true,
            replayedUp: true
        )

        XCTAssertNil(gate.activeSessionID)
        XCTAssertEqual(gate.state, .resolved)
    }

    func testFallbackOwnerSuppressesLateHardwareEdge() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertEqual(gate.resolve(sessionID: session), .noOptionEdge)
        XCTAssertEqual(
            gate.selectFallback(sessionID: session, reason: "no-option-edge"),
            .syntheticDown
        )
        XCTAssertTrue(gate.shouldSuppressLateHardwareEvent(.down, sessionID: session))
        XCTAssertTrue(gate.shouldSuppressLateHardwareEvent(.up, sessionID: session))
    }

    func testNoPCMCancellationClearsGateBeforeLatePhysicalOption() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        _ = gate.captureEvent(.down, copied: true)
        XCTAssertTrue(gate.cancel(sessionID: session))
        XCTAssertEqual(gate.state, .cancelled)
        XCTAssertFalse(gate.shouldSuppressLateHardwareEvent(.up, sessionID: session))
        XCTAssertEqual(gate.captureEvent(.up, copied: true), .ignored)
    }

    func testCopyFailureSelectsSyntheticFallbackEvenAfterCopiedDown() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertEqual(gate.captureEvent(.down, copied: true), .deferred)
        XCTAssertEqual(gate.captureEvent(.up, copied: false), .deferred)
        XCTAssertEqual(gate.resolve(sessionID: session), .syntheticTap)
        XCTAssertEqual(
            gate.selectFallback(sessionID: session, reason: "copy-failed"),
            .syntheticTap
        )
        XCTAssertTrue(gate.shouldSuppressLateHardwareEvent(.down, sessionID: session))
        XCTAssertTrue(gate.shouldSuppressLateHardwareEvent(.up, sessionID: session))
    }

    func testHardwareReplayAllowsOnlyTheUnreplayedPhysicalUp() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: true))
        XCTAssertEqual(gate.resolve(sessionID: session), .hardwareReplay)
        gate.completeHardwareReplay(
            sessionID: session,
            replayedDown: true,
            replayedUp: false
        )

        XCTAssertTrue(gate.shouldSuppressLateHardwareEvent(.down, sessionID: session))
        XCTAssertFalse(gate.shouldSuppressLateHardwareEvent(.up, sessionID: session))
    }

    func testOptionLifecycleEmitsStructuredRequestFacts() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        var events: [Bool] = []
        let trigger = VoiceOptionTrigger(
            eventSink: { events.append($0) },
            diagnostics: diagnostics
        )

        XCTAssertTrue(trigger.begin(sessionID: session))
        XCTAssertTrue(trigger.sendDown(sessionID: session))
        XCTAssertTrue(trigger.sendUp(sessionID: session))

        XCTAssertEqual(
            diagnostics.events(for: session)
                .filter { $0.event.hasSuffix("_REQUEST") }
                .map(\.event),
            ["OPTION_DOWN_REQUEST", "OPTION_UP_REQUEST"]
        )
        XCTAssertEqual(events, [true, false])
    }

    func testSendDownAndUpAreBalancedForOneSession() {
        var events: [Bool] = []
        let trigger = VoiceOptionTrigger { events.append($0) }
        let session = UUID()

        XCTAssertTrue(trigger.begin(sessionID: session))
        XCTAssertTrue(trigger.sendDown(sessionID: session))
        XCTAssertFalse(trigger.sendDown(sessionID: session))
        XCTAssertTrue(trigger.sendUp(sessionID: session))
        XCTAssertFalse(trigger.sendUp(sessionID: session))

        XCTAssertEqual(events, [true, false])
        XCTAssertNil(trigger.activeSessionID)
        XCTAssertFalse(trigger.isOptionDown)
    }

    func testBeginningNewSessionBalancesPreviousOwnerBeforeTakingOwnership() {
        var events: [Bool] = []
        let trigger = VoiceOptionTrigger { events.append($0) }
        let stale = UUID()
        let current = UUID()

        XCTAssertTrue(trigger.begin(sessionID: stale))
        XCTAssertTrue(trigger.sendDown(sessionID: stale))
        XCTAssertTrue(trigger.begin(sessionID: current))

        XCTAssertEqual(events, [true, false])
        XCTAssertEqual(trigger.activeSessionID, current)
        XCTAssertFalse(trigger.isOptionDown)
    }

    func testStaleDelayedTapUpCannotReleaseCurrentSession() {
        var events: [Bool] = []
        let trigger = VoiceOptionTrigger { events.append($0) }
        let stale = UUID()
        let current = UUID()

        XCTAssertTrue(trigger.begin(sessionID: stale))
        XCTAssertTrue(trigger.sendTap(sessionID: stale, duration: 0.03))
        XCTAssertTrue(trigger.begin(sessionID: current))
        XCTAssertTrue(trigger.sendDown(sessionID: current))
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))

        XCTAssertEqual(events, [true, false, true])
        XCTAssertTrue(trigger.isOptionDown)
        XCTAssertTrue(trigger.sendUp(sessionID: current))
        XCTAssertEqual(events, [true, false, true, false])
    }

    func testTapProducesOneBalancedSyntheticPair() {
        var events: [Bool] = []
        let trigger = VoiceOptionTrigger { events.append($0) }
        let session = UUID()

        XCTAssertTrue(trigger.begin(sessionID: session))
        XCTAssertTrue(trigger.sendTap(sessionID: session, duration: 0.01))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(events, [true, false])
        XCTAssertNil(trigger.activeSessionID)
    }
}
