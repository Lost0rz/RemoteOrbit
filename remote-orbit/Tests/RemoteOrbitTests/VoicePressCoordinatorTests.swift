import XCTest
@testable import RemoteOrbit

final class VoicePressCoordinatorTests: XCTestCase {
    func testHardwareLongReleasesOnlyThePhysicalGate() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var gateBegan = false
        var gateReleased = false
        press.onHardwareOptionGateBegin = { _ in gateBegan = true }
        press.onHardwareOptionGateLongReady = { _ in gateReleased = true }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: true
            )
        )
        press.setRemoteAudioAvailable()

        XCTAssertTrue(gateBegan)
        XCTAssertTrue(gateReleased)
        XCTAssertTrue(events.isEmpty)
        press.stop()
    }

    func testHardwareShortReleasesPhysicalGateWithoutSyntheticEvents() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var shortResult: (UUID, Bool)?
        press.onHardwareOptionGateShortResult = { sessionID, shouldRelease in
            shortResult = (sessionID, shouldRelease)
        }

        let sessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionID,
                usesHardwareOption: true
            )
        )
        press.keyUp()

        XCTAssertEqual(shortResult?.0, sessionID)
        XCTAssertEqual(shortResult?.1, true)
        XCTAssertTrue(events.isEmpty)
        press.stop()
    }

    func testMappingUnavailableLongUsesBalancedSyntheticOwner() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        let sessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionID,
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true])

        press.stop()
        XCTAssertEqual(events, [true, false])
    }

    func testShortShortLongStillPromotesTheFinalLongPress() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        press.keyUp()
        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        press.keyUp()
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testFourShortPressesDoNotPoisonTheNextLongPress() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        for _ in 0..<4 {
            XCTAssertTrue(press.keyDown(sessionID: UUID()))
            press.keyUp()
        }
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testLongStartRequestsBLEBeforeRemoteRoutePreparation() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var order: [String] = []
        press.onStateChanged = { state in
            if state == .holding {
                order.append("BLE_START_REQUEST")
            }
        }
        press.onRemoteRoutePreparation = {
            order.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        XCTAssertEqual(order, ["BLE_START_REQUEST", "REMOTE_ROUTE_PREPARATION"])
        press.stop()
    }

    func testRepressAfterPreviousRouteFinishesIsNotBlockedByOldTailWindow() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        let firstSessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID()
            )
        )
        XCTAssertEqual(
            press.lastRepressDecisionForTesting,
            "accepted-after-route-finished"
        )
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testRepressWithinHardwareBounceWindowIsRejected() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.05)

        XCTAssertFalse(press.keyDown(sessionID: UUID()))
        XCTAssertEqual(press.lastRepressDecisionForTesting, "release-bounce")
        press.stop()
    }

    func testRepressAfterHardwareDebounceButBeforeOldRouteFinishDoesNotStartSecondLongSession() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)

        XCTAssertFalse(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        XCTAssertEqual(
            press.lastRepressDecisionForTesting,
            "previous-tail-active"
        )
        XCTAssertEqual(press.currentStateForTesting, .idle)
        press.stop()
    }

    func testNormalLongTimingUnchanged() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var order: [String] = []
        press.onStateChanged = { state in
            if state == .holding {
                order.append("HOLD_CONFIRMED")
            }
        }
        press.onRemoteRoutePreparation = {
            order.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        waitForCoordinatorTiming(0.35)

        XCTAssertEqual(order, ["HOLD_CONFIRMED", "REMOTE_ROUTE_PREPARATION"])
        press.stop()
    }

    func testNormalTailTimingUnchanged() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertEqual(press.tailDrainDelayForTesting, 0.80, accuracy: 0.001)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        XCTAssertTrue(press.hasPendingTailForTesting)
        press.stop()
    }

    func testOldTailCompletionCannotClearNewGesture() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        let firstSessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])

        press.invokeTailCompletionForTesting(sessionID: firstSessionID)

        XCTAssertEqual(events, [true, false, true])
        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertTrue(press.hasRemoteAudio)
        press.stop()
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }
}
