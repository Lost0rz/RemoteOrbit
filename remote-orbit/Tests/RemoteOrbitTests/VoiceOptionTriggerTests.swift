import XCTest
@testable import RemoteOrbit

final class VoiceOptionTriggerTests: XCTestCase {
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
