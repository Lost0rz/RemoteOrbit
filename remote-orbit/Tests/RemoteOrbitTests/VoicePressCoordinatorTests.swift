import XCTest
@testable import RemoteOrbit

final class VoicePressCoordinatorTests: XCTestCase {
    func testDisabledShortStartsTransportPreparationWithoutSkippingClassifier() {
        var events: [String] = []
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        press.onRemoteTransportPreparation = {
            events.append("BLE_PREPARE_REQUEST")
        }
        press.onRemoteRoutePreparation = {
            events.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                preparesRemoteTransport: true
            )
        )

        XCTAssertEqual(events, ["BLE_PREPARE_REQUEST"])
        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertFalse(press.shouldShowPendingVoiceUI)
        press.keyUp()
        press.stop()
    }

    func testDisabledShortWithPendingAudioHasNoVisibleOptionAction() {
        var optionEvents: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { optionEvents.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                preparesRemoteTransport: true
            )
        )
        AudioPipe.shared.feed(samples: Array(repeating: Int16(9), count: 64))
        press.setRemoteAudioAvailable()

        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertFalse(press.shouldShowPendingVoiceUI)
        XCTAssertTrue(optionEvents.isEmpty)
        XCTAssertTrue(press.keyUp())
        press.stop()
    }

    func testPendingRemoteAudioIsQueuedBeforeLongOptionActivation() {
        var order: [String] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _ in
                order.append("OPTION_DOWN_RELEASE")
            }
        )
        press.onStateChanged = { state in
            if state == .holding {
                order.append("HOLD_CONFIRMED")
            }
        }
        press.onRemoteRoutePreparation = {
            order.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                preparesRemoteTransport: true
            )
        )
        AudioPipe.shared.feed(samples: Array(repeating: Int16(7), count: 320))
        press.setRemoteAudioAvailable()
        waitForCoordinatorTiming(0.35)

        XCTAssertEqual(
            order,
            ["HOLD_CONFIRMED", "REMOTE_ROUTE_PREPARATION", "OPTION_DOWN_RELEASE"]
        )
        press.keyUp()
        press.stop()
    }

    func testHardwareOptionUpWaitsForOutputDrain() {
        var order: [String] = []
        var completeOutputDrain: (() -> Void)?
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in
            XCTFail("hardware replay must not use synthetic Option")
        })
        press.onHardwareOptionGateBegin = { _ in
            order.append("OPTION_GATE_BEGIN")
        }
        press.onHardwareOptionGateLongReady = { _ in
            order.append("OPTION_DOWN_RELEASE")
        }
        press.onHardwareOptionGatePhysicalUp = { _ in
            order.append("PHYSICAL_UP")
        }
        press.onHardwareOptionGateOutputDrained = { _ in
            order.append("OPTION_UP_RELEASE")
        }
        press.onRemoteOutputDrain = { _, completion in
            order.append("WAIT_OUTPUT_DRAIN")
            completeOutputDrain = completion
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: true
            )
        )
        press.setRemoteStreaming(true)
        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)

        XCTAssertEqual(
            order,
            [
                "OPTION_GATE_BEGIN",
                "OPTION_DOWN_RELEASE",
                "PHYSICAL_UP",
                "WAIT_OUTPUT_DRAIN",
            ]
        )
        XCTAssertNotNil(completeOutputDrain)
        XCTAssertNotEqual(order.last, "OPTION_UP_RELEASE")

        completeOutputDrain?()

        XCTAssertEqual(order.last, "OPTION_UP_RELEASE")
        press.stop()
    }

    func testSyntheticOptionUpAlsoWaitsForOutputDrain() {
        var events: [Bool] = []
        var completeOutputDrain: (() -> Void)?
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        press.onRemoteOutputDrain = { _, completion in
            completeOutputDrain = completion
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteStreaming(true)
        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)

        XCTAssertEqual(events, [true])
        completeOutputDrain?()
        XCTAssertEqual(events, [true, false])
        press.stop()
    }

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

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        XCTAssertEqual(
            press.lastRepressDecisionForTesting,
            "deferred-previous-tail-active"
        )
        XCTAssertNotNil(press.pendingRepressSessionID)
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

    func testRepressDuringPreviousTailIsDeferredNotDropped() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)

        let deferredSessionID = UUID()
        XCTAssertTrue(press.keyDown(sessionID: deferredSessionID))
        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)
        XCTAssertEqual(states.last, .idle)
        press.stop()
    }

    func testDeferredRepressStartsWhenPreviousRouteFinishes() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.22)

        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        XCTAssertNotNil(press.pendingRepressSessionID)
        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.40)

        XCTAssertNil(press.pendingRepressSessionID)
        XCTAssertEqual(states.last, .holding)
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])
        press.stop()
    }

    func testDeferredRepressUsesOriginalPhysicalDownForHoldThreshold() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        waitForCoordinatorTiming(0.35)
        XCTAssertNotNil(press.pendingRepressSessionID)
        XCTAssertEqual(states.last, .idle)

        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testDeferredRepressReleasedBeforeTailFinishIsCancelled() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        XCTAssertNotNil(press.pendingRepressSessionID)

        XCTAssertFalse(press.keyUp())
        XCTAssertNil(press.pendingRepressSessionID)
        press.setRemoteStreaming(false)
        XCTAssertEqual(events, [true, false])
        press.stop()
    }

    func testDeferredRepressDoesNotStartBleBeforePreviousRouteOff() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        XCTAssertEqual(states.last, .idle)

        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testDeferredRepressStaleTailCompletionCannotClearActivatedGesture() {
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
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        XCTAssertNotNil(press.pendingRepressSessionID)

        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])

        press.invokeTailCompletionForTesting(sessionID: firstSessionID)

        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertTrue(press.hasRemoteAudio)
        XCTAssertEqual(events, [true, false, true])
        press.stop()
    }

    func testDeferredRepressWaitsUntilOldTransportCallbackStackFinishes() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        let deferredSessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(
            press.keyDown(
                sessionID: deferredSessionID,
                bypassesShortClassification: true
            )
        )
        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)

        // STREAMING_FALSE(A): A finishes logically, but B must not activate
        // inside the old BLE callback stack.
        press.setRemoteStreaming(false)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)
        XCTAssertTrue(press.hasDeferredRepressAwaitingActivationForTesting)

        // CONNECTION_FALSE(A): old teardown cleanup must preserve B.
        press.stopCurrentVoiceStatePreservingDeferredRepress()
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)

        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.stop()
    }

    func testOldConnectionFalseCannotCancelDeferredNextGesture() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        let deferredSessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: deferredSessionID,
                bypassesShortClassification: true
            )
        )

        press.setRemoteStreaming(false)
        press.stopCurrentVoiceStatePreservingDeferredRepress()

        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.stop()
    }

    func testDeferredRepressActivatesAfterTeardownBarrier() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        press.setRemoteStreaming(false)
        XCTAssertEqual(events, [true, false])
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(events, [true, false])
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])
        press.stop()
    }

    func testDeferredRepressReleasedDuringTeardownBarrierIsCancelled() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteStreaming(false)

        XCTAssertFalse(press.keyUp())
        XCTAssertNil(press.pendingRepressSessionID)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertEqual(events, [true, false])
        press.stop()
    }

    func testNormalAudioStopPathUsesTheSameTeardownBarrier() {
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
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        press.setRemoteStreaming(false)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertTrue(press.hasDeferredRepressAwaitingActivationForTesting)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.stop()
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }
}
