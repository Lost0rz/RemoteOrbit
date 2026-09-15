import XCTest
import CoreGraphics
@testable import RemoteOrbit

final class VoiceOptionTriggerTests: XCTestCase {
    func testTraceFormattingRunsOnDiagnosticQueue() {
        let expectation = expectation(description: "diagnostic formatting")
        var ranOnDiagnosticQueue = false

        VoiceOptionTrace.enqueueFormattingProbeForTesting { isOnQueue in
            ranOnDiagnosticQueue = isOnQueue
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(ranOnDiagnosticQueue)
    }

    func testControlTraceRequiresExplicitOptIn() {
        XCTAssertFalse(
            VoiceOptionTrace.controlTraceEnabled(environment: [:])
        )
        XCTAssertFalse(
            VoiceOptionTrace.controlTraceEnabled(
                environment: ["REMOTEORBIT_OPTION_CONTROL_TRACE": "0"]
            )
        )
        XCTAssertTrue(
            VoiceOptionTrace.controlTraceEnabled(
                environment: ["REMOTEORBIT_OPTION_CONTROL_TRACE": "1"]
            )
        )
    }

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

    func testDiagnosticSessionIDsDoNotParticipateInGateResolution() {
        let gate = HardwareOptionGate()
        let firstDiagnosticSession = UUID()
        let secondDiagnosticSession = UUID()
        let productGestureID = UUID()

        VoiceOptionTrace.bindGestureSession(
            diagnosticSessionID: firstDiagnosticSession,
            gestureID: productGestureID
        )
        VoiceOptionTrace.gateBegin(
            sessionID: productGestureID,
            uptime: 10
        )
        VoiceOptionTrace.gateBegin(
            sessionID: secondDiagnosticSession,
            uptime: 11
        )
        XCTAssertTrue(gate.begin(sessionID: productGestureID))
        XCTAssertTrue(gate.capture(.down, copied: true))

        VoiceOptionTrace.waitForDiagnosticsForTesting()

        XCTAssertEqual(
            gate.resolve(sessionID: productGestureID),
            .hardwareReplay
        )
        XCTAssertNil(gate.resolve(sessionID: secondDiagnosticSession))
        VoiceOptionTrace.scheduleSessionEnd(productGestureID)
        VoiceOptionTrace.waitForDiagnosticsForTesting()
    }

    func testDiagnosticsDoNotPostOptionEventsOrChangeGateState() {
        var postedEvents: [Bool] = []
        let trigger = VoiceOptionTrigger { postedEvents.append($0) }
        let gate = HardwareOptionGate()
        let session = UUID()

        XCTAssertTrue(gate.begin(sessionID: session))
        XCTAssertTrue(gate.capture(.down, copied: true))
        let activeSessionBeforeTrace = gate.activeSessionID
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 58,
            keyDown: true
        ) else {
            XCTFail("could not create test Option event")
            return
        }

        VoiceOptionTrace.optionEvent(
            sessionID: session,
            type: .keyDown,
            event: event,
            uptime: 12,
            firstOptionEvent: true
        )
        VoiceOptionTrace.controlOptionEvent(
            type: .keyDown,
            event: event,
            uptime: 12
        )
        VoiceOptionTrace.waitForDiagnosticsForTesting()

        XCTAssertEqual(gate.activeSessionID, activeSessionBeforeTrace)
        XCTAssertEqual(gate.resolve(sessionID: session), .hardwareReplay)
        XCTAssertTrue(postedEvents.isEmpty)
        _ = trigger
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
