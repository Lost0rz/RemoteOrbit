import XCTest
@testable import RemoteOrbit

final class VoiceOptionTriggerTests: XCTestCase {
    func testTimingLineIncludesMonotonicAndGateDeltas() {
        let line = VoiceTimingLogger.formatLine(
            event: "OPTION_KEY_DOWN_SEEN",
            shortID: "ABCD",
            uptime: 10.250,
            startedAt: 10.000,
            gateStartedAt: 10.100,
            firstOptionAt: 10.250,
            details: "type=keyDown"
        )

        XCTAssertEqual(
            line,
            "[VOICE][ABCD][TIMING] OPTION_KEY_DOWN_SEEN "
                + "uptime=10.250000 +250.0ms deltaRawF5=250.0ms "
                + "deltaGate=150.0ms "
                + "deltaFirstOption=0.0ms type=keyDown"
        )
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

    func testStaleSyntheticTapCannotReleaseTheCurrentOwner() {
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
}
