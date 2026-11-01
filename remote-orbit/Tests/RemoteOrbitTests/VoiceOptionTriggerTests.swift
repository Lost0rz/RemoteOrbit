import XCTest
@testable import RemoteOrbit

final class VoiceOptionTriggerTests: XCTestCase {
    func testHardwareGateOwnerCorrelationDoesNotEmitSyntheticReceiverEdges() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(trigger.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: true))
        XCTAssertEqual(gate.resolve(sessionID: session), .hardwareReplay)
        XCTAssertFalse(trigger.abort(sessionID: session))

        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(trigger.activeSessionID)
    }

    func testHardwareLongUsesOnlyTheCapturedPhysicalDown() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: true))
        XCTAssertEqual(gate.resolve(sessionID: session), .hardwareReplay)
    }

    func testHardwareShortReplaysTheCapturedPhysicalPair() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: true))
        XCTAssertTrue(gate.capture(.up, copied: true))
        XCTAssertEqual(gate.resolve(sessionID: session), .hardwareReplay)
        XCTAssertFalse(gate.resolve(sessionID: session) != nil)
    }

    func testCopyFailureStillSelectsSyntheticFallback() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: false))
        XCTAssertEqual(gate.resolve(sessionID: session), .syntheticDown)
    }

    func testCopyFailureWithBothEdgesUsesSyntheticTapFallback() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: false))
        XCTAssertTrue(gate.capture(.up, copied: false))
        XCTAssertEqual(gate.resolve(sessionID: session), .syntheticTap)
    }

    func testMappingUnavailableUsesOneBalancedSyntheticTap() {
        var events: [Bool] = []
        let trigger = VoiceOptionTrigger { events.append($0) }
        let session = UUID()

        XCTAssertTrue(trigger.begin(sessionID: session))
        XCTAssertTrue(trigger.sendTap(sessionID: session, duration: 0.01))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(events, [true, false])
        XCTAssertNil(trigger.activeSessionID)
    }

    func testStalePhysicalGestureCannotResolveTheCurrentHardwareGate() {
        let gate = HardwareOptionGate()
        let stale = UUID()
        let current = UUID()

        XCTAssertTrue(gate.begin(sessionID: stale))
        XCTAssertTrue(gate.begin(sessionID: current))
        XCTAssertTrue(gate.capture(.down, copied: true))
        XCTAssertNil(gate.resolve(sessionID: stale))
        XCTAssertEqual(gate.activeSessionID, current)
        XCTAssertEqual(gate.resolve(sessionID: current), .hardwareReplay)
    }

    func testSuppressCapturedHardwareDownTransfersToBoundedReleaseOwnership() {
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: true))
        XCTAssertTrue(gate.suppress(sessionID: session))

        XCTAssertNil(gate.activeSessionID)
        XCTAssertEqual(gate.suppressedSessionID, session)
        XCTAssertFalse(gate.capture(.up, copied: true))
        XCTAssertTrue(gate.ownsSuppressedRelease(sessionID: session))
        XCTAssertFalse(gate.ownsSuppressedRelease(sessionID: UUID()))
        XCTAssertEqual(gate.suppressedSessionID, session)
        XCTAssertTrue(gate.armSuppressedRelease(sessionID: session))
        // Physical-up alone is insufficient.
        XCTAssertFalse(gate.completeSuppressed(sessionID: session))
        XCTAssertEqual(gate.suppressedSessionID, session)

        // Output drain alone is still insufficient.
        XCTAssertTrue(gate.markSuppressedOutputDrainCompleted(sessionID: session))
        XCTAssertFalse(gate.completeSuppressed(sessionID: session))
        XCTAssertEqual(gate.suppressedSessionID, session)

        // Ownership closes only after the mapped-release quiet window.
        XCTAssertTrue(gate.markSuppressedReleaseQuietPeriodElapsed(sessionID: session))
        XCTAssertTrue(gate.completeSuppressed(sessionID: session))
        XCTAssertNil(gate.suppressedSessionID)
    }

    func testSuppressionRequiresMatchingActiveDownAndIgnoresStaleCompletion() {
        let gate = HardwareOptionGate()
        let session = UUID()
        let other = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertFalse(gate.suppress(sessionID: other))
        XCTAssertFalse(gate.suppress(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: true))
        XCTAssertTrue(gate.suppress(sessionID: session))
        XCTAssertFalse(gate.armSuppressedRelease(sessionID: other))
        XCTAssertFalse(gate.completeSuppressed(sessionID: other))
        XCTAssertEqual(gate.suppressedSessionID, session)
        XCTAssertFalse(gate.begin(sessionID: other))
        XCTAssertTrue(gate.resetSuppressed(sessionID: session))
        XCTAssertNil(gate.suppressedSessionID)
    }

    func testStaleSyntheticTapCannotReleaseTheCurrentOwner() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let stale = UUID()
        let current = UUID()

        XCTAssertTrue(trigger.configureVoiceTriggerKey(.rightControl))
        XCTAssertTrue(trigger.begin(sessionID: stale))
        XCTAssertTrue(trigger.sendTap(sessionID: stale))
        XCTAssertTrue(trigger.begin(sessionID: current))
        XCTAssertTrue(trigger.sendDown(sessionID: current))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(events.map(\.key), [.rightControl, .rightControl, .rightControl])
        XCTAssertEqual(events.map(\.isDown), [true, false, true])
        XCTAssertTrue(trigger.isOptionDown)
        XCTAssertTrue(trigger.sendUp(sessionID: current))
        XCTAssertEqual(events.map(\.key), [
            .rightControl, .rightControl, .rightControl, .rightControl,
        ])
        XCTAssertEqual(events.map(\.isDown), [true, false, true, false])
    }

    func testIdleConfigurationRoutesDownAndUpThroughEachSelectedKey() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        var expectedKeys: [VoiceTriggerKey] = []
        var expectedEdges: [Bool] = []

        for key in VoiceTriggerKey.allCases {
            XCTAssertTrue(trigger.configureVoiceTriggerKey(key))
            let sessionID = UUID()
            XCTAssertTrue(trigger.begin(sessionID: sessionID))
            XCTAssertTrue(trigger.sendDown(sessionID: sessionID))
            XCTAssertTrue(trigger.sendUp(sessionID: sessionID))

            expectedKeys.append(contentsOf: [key, key])
            expectedEdges.append(contentsOf: [true, false])
        }

        XCTAssertEqual(events.map(\.key), expectedKeys)
        XCTAssertEqual(events.map(\.isDown), expectedEdges)
    }

    func testSelectedProfileDownAndUpUseProvidedKey() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })

        let sessionID = UUID()
        XCTAssertTrue(trigger.begin(sessionID: sessionID))
        XCTAssertTrue(
            trigger.sendDown(
                sessionID: sessionID,
                key: .rightOption,
                purpose: "voice_session_opening"
            )
        )
        XCTAssertTrue(trigger.sendUp(sessionID: sessionID))

        XCTAssertEqual(events.map(\.key), [.rightOption, .rightOption])
        XCTAssertEqual(events.map(\.isDown), [true, false])
    }

    func testSelectedProfileDownCapturesItsKeyAgainstLaterConfigurationChanges() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let sessionID = UUID()

        XCTAssertTrue(trigger.begin(sessionID: sessionID))
        XCTAssertTrue(
            trigger.sendDown(
                sessionID: sessionID,
                key: .rightOption,
                purpose: "voice_session_opening"
            )
        )
        XCTAssertFalse(trigger.configureVoiceTriggerKey(.leftControl))
        XCTAssertTrue(trigger.sendUp(sessionID: sessionID))

        XCTAssertEqual(events.map(\.key), [.rightOption, .rightOption])
    }

    func testAbortBalancesTheSelectedProfileKey() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let sessionID = UUID()

        XCTAssertTrue(trigger.begin(sessionID: sessionID))
        XCTAssertTrue(
            trigger.sendDown(
                sessionID: sessionID,
                key: .rightOption,
                purpose: "voice_session_opening"
            )
        )
        XCTAssertTrue(trigger.abort(sessionID: sessionID))

        XCTAssertEqual(events.map(\.key), [.rightOption, .rightOption])
        XCTAssertEqual(events.map(\.isDown), [true, false])
    }

    func testConfigurationIsRejectedWhileTriggerIsDown() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let sessionID = UUID()

        XCTAssertTrue(trigger.configureVoiceTriggerKey(.leftControl))
        XCTAssertTrue(trigger.begin(sessionID: sessionID))
        XCTAssertTrue(trigger.sendDown(sessionID: sessionID))

        XCTAssertFalse(trigger.configureVoiceTriggerKey(.rightControl))
        XCTAssertEqual(trigger.voiceTriggerKey, .leftControl)
        XCTAssertTrue(trigger.sendUp(sessionID: sessionID))
        XCTAssertEqual(events.map(\.key), [.leftControl, .leftControl])
        XCTAssertEqual(events.map(\.isDown), [true, false])
    }

    func testTapKeepsOneSelectedKeyAcrossTheDelayedRelease() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let sessionID = UUID()

        XCTAssertTrue(trigger.configureVoiceTriggerKey(.rightControl))
        XCTAssertTrue(trigger.begin(sessionID: sessionID))
        XCTAssertTrue(trigger.sendTap(sessionID: sessionID, duration: 0.06))
        XCTAssertFalse(trigger.configureVoiceTriggerKey(.rightOption))
        XCTAssertEqual(trigger.voiceTriggerKey, .rightControl)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(events.map(\.key), [.rightControl, .rightControl])
        XCTAssertEqual(events.map(\.isDown), [true, false])
        XCTAssertNil(trigger.activeSessionID)
    }

    func testAbortBalancesTheSelectedSyntheticTriggerKey() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let sessionID = UUID()

        XCTAssertTrue(trigger.configureVoiceTriggerKey(.rightControl))
        XCTAssertTrue(trigger.begin(sessionID: sessionID))
        XCTAssertTrue(trigger.sendDown(sessionID: sessionID))
        XCTAssertTrue(trigger.abort(sessionID: sessionID))

        XCTAssertEqual(events.map(\.key), [.rightControl, .rightControl])
        XCTAssertEqual(events.map(\.isDown), [true, false])
        XCTAssertNil(trigger.activeSessionID)
    }

}
