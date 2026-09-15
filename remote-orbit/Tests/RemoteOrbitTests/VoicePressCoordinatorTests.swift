import XCTest
@testable import RemoteOrbit

final class VoicePressCoordinatorTests: XCTestCase {
    func testPhysicalLongPathReleasesHardwareWithoutSyntheticEvents() {
        var syntheticEvents: [Bool] = []
        var gateBegan: UUID?
        var gateReleased: UUID?
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { syntheticEvents.append($0) }
        )
        press.onHardwareOptionGateBegin = { gateBegan = $0 }
        press.onHardwareOptionGateLongReady = { gateReleased = $0 }

        let session = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: session,
                bypassesShortClassification: true,
                usesHardwareOption: true
            )
        )
        press.setRemoteAudioAvailable()

        XCTAssertEqual(gateBegan, session)
        XCTAssertEqual(gateReleased, session)
        XCTAssertTrue(syntheticEvents.isEmpty)
        press.stop()
        XCTAssertTrue(syntheticEvents.isEmpty)
    }

    func testAcceptedGestureStartsStructuredSessionDiagnostics() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger(
                eventSink: { _ in },
                diagnostics: diagnostics
            ),
            diagnostics: diagnostics
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: session,
                bypassesShortClassification: true,
                shortBindingMode: "disabled",
                targetBundleID: "com.example.target"
            )
        )

        let events = diagnostics.events(for: session)
        XCTAssertEqual(events.first?.event, "SESSION_BEGIN")
        XCTAssertTrue(events.contains { $0.event == "VOICE_DOWN_PHYSICAL" })
        XCTAssertTrue(events.contains { $0.event == "HOLD_CONFIRMED" })
        press.stop()
    }

    func testNoPCMSessionSummaryIdentifiesNoPCMCompletion() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger(
                eventSink: { _ in },
                diagnostics: diagnostics
            ),
            diagnostics: diagnostics
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: session,
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        XCTAssertTrue(press.keyUp())

        XCTAssertEqual(diagnostics.summary(for: session)?.completion, .noPCM)
        XCTAssertEqual(diagnostics.summary(for: session)?.lifecycle, .aborted)
        XCTAssertFalse(diagnostics.summary(for: session)?.firstPCM ?? true)
        press.stop()
    }

    func testLongPressDoesNotSendOptionBeforeFirstPCM() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )

        XCTAssertTrue(events.isEmpty)
        press.keyUp()
        XCTAssertTrue(events.isEmpty)
        press.stop()
    }

    func testLongPressSendsOneSyntheticOptionDownAfterFirstPCM() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        press.setRemoteAudioAvailable()
        press.setRemoteAudioAvailable()
        press.setRemoteAudioAvailable()

        XCTAssertEqual(events, [true])
        press.stop()
        XCTAssertEqual(events, [true, false])
    }

    func testLongPressReleaseAfterFirstPCMWaitsForDrainThenSendsOptionUp() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        XCTAssertEqual(events, [true])

        press.setRemoteStreaming(false)
        XCTAssertEqual(events, [true, false])
    }

    func testLongPressStopAfterFirstPCMBalancesSyntheticOption() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true])

        press.stop()
        XCTAssertEqual(events, [true, false])
    }

    func testLongPressDisconnectAfterFirstPCMBalancesSyntheticOption() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        press.setRemoteAudioAvailable()
        press.setRemoteStreaming(false)

        XCTAssertEqual(events, [true, false])
    }

    func testDefaultShortUsesOneBalancedSyntheticTap() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false
            )
        )
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertEqual(events, [true, false])
    }

    func testDefaultShortSummaryWaitsForDelayedOptionUp() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger(
                eventSink: { _ in },
                diagnostics: diagnostics
            ),
            diagnostics: diagnostics
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: session,
                usesHardwareOption: false
            )
        )
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)

        let summary = diagnostics.summary(for: session)
        XCTAssertEqual(summary?.completion, .shortTap)
        XCTAssertEqual(summary?.optionDownRequests, 1)
        XCTAssertEqual(summary?.optionUpRequests, 1)
        XCTAssertEqual(summary?.invariantViolations, 0)
    }

    func testConfiguredShortActionDoesNotSendDefaultOption() {
        var events: [Bool] = []
        var actionCalled = false
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                onShortTap: { actionCalled = true }
            )
        )
        XCTAssertTrue(press.keyUp())

        XCTAssertTrue(actionCalled)
        XCTAssertTrue(events.isEmpty)
    }

    func testConfiguredHardwareShortActionCancelsGateWithoutOptionLeak() {
        var events: [Bool] = []
        var gateCancelled: UUID?
        var actionCalled = false
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        press.onHardwareOptionGateShortResult = { sessionID, shouldRelease in
            if !shouldRelease {
                gateCancelled = sessionID
            }
        }

        let session = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: session,
                onShortTap: { actionCalled = true },
                usesHardwareOption: true
            )
        )
        XCTAssertTrue(press.keyUp())

        XCTAssertTrue(actionCalled)
        XCTAssertEqual(gateCancelled, session)
        XCTAssertTrue(events.isEmpty)
    }

    func testDisabledShortBypassReleasedBeforePCMDoesNotSendOption() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                onShortTap: { },
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertTrue(events.isEmpty)

        XCTAssertTrue(press.keyUp())

        XCTAssertTrue(events.isEmpty)
    }

    func testDisabledShortBypassFirstPCMUsesRemoteLongOption() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                onShortTap: { },
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        XCTAssertEqual(press.currentStateForTesting, .holding)

        press.setRemoteAudioAvailable()

        XCTAssertEqual(events, [true])
        press.stop()
        XCTAssertEqual(events, [true, false])
    }

    func testLongPressSafetyTailBalancesOptionWhenStreamingFalseNeverArrives() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true])

        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(events, [true])
        XCTAssertTrue(press.hasPendingTailForTesting)

        waitForCoordinatorTiming(press.tailDrainDelayForTesting + 0.08)

        XCTAssertEqual(events, [true, false])
        XCTAssertFalse(press.hasPendingTailForTesting)
        XCTAssertEqual(press.currentStateForTesting, .idle)
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
                bypassesShortClassification: true,
                usesHardwareOption: false
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
