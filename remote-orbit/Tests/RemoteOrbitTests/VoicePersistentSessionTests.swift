import XCTest
@testable import RemoteOrbit

final class VoicePersistentSessionTests: XCTestCase {
    func testDefaultIMEVoiceBindingSelectsPersistentModeWithoutLocalMicrophone() {
        XCTAssertFalse(
            VoicePressCoordinator.usesLocalMicrophone(
                forShortBinding: .voiceKeyDefault
            )
        )
        XCTAssertTrue(
            VoicePressCoordinator.togglesPersistentVoiceSession(
                forShortBinding: .voiceKeyDefault
            )
        )
        XCTAssertFalse(
            VoicePressCoordinator.togglesPersistentVoiceSession(
                forShortBinding: .preset(.chatGPTStartVoiceChat)
            )
        )
    }

    func testTapOpensAndClosesPersistentSessionWithOneConfiguredTapEach() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        var routePreparations = 0
        press.onRemoteRoutePreparation = { routePreparations += 1 }

        openPersistentSession(press)

        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertFalse(press.hasActiveVoiceOwnershipForTriggerReconfiguration)
        XCTAssertEqual(events.map(\.0), [.leftOption, .leftOption])
        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertEqual(routePreparations, 0)
        XCTAssertFalse(
            VoicePressCoordinator.isPersistentSessionLongPress(heldDuration: 0.185),
            "a real-world 185ms persistent-open tap must remain short"
        )

        waitForCoordinatorTiming(0.20)
        press.keyDown(sessionID: UUID(), togglesPersistentVoiceSession: true)
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertFalse(press.persistentSessionActiveForTesting)
        XCTAssertEqual(press.currentSessionModeForTesting, .idle)
        XCTAssertEqual(events.map(\.1), [true, false, true, false])
        XCTAssertEqual(routePreparations, 0)
        press.stop()
    }

    func testPersistentSessionOpenHasNoAutomaticTimeout() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        openPersistentSession(press)

        waitForCoordinatorTiming(0.35)

        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertEqual(press.currentSessionModeForTesting, .persistentOpen)
        press.stop()
    }

    func testPersistentCloseUsesKeyCapturedWhenSessionOpened() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightCommand))

        openPersistentSession(press)
        XCTAssertEqual(press.persistentSessionTriggerOwnerKeyForTesting, .rightCommand)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.leftControl))

        waitForCoordinatorTiming(0.20)
        press.keyDown(sessionID: UUID(), togglesPersistentVoiceSession: true)
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertEqual(events.map(\.0), [
            .rightCommand, .rightCommand, .rightCommand, .rightCommand,
        ])
        XCTAssertNil(press.persistentSessionTriggerOwnerKeyForTesting)
        press.stop()
    }

    func testRuntimeOnlyPersistentTriggerIsIndependentFromReceiverBState() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger(keyedEventSink: { key, down in
                events.append((key, down))
            })
        )
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.leftCommand))
        openPersistentSession(press)

        XCTAssertEqual(events.map(\.0), [.leftCommand, .leftCommand])
        XCTAssertEqual(events.map(\.1), [true, false])
        press.stop()
    }

    func testPersistentSessionUsesSharedClassifierAndPreparesOnlyTransportWhilePending() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        var transportPreparations = 0
        var routePreparations = 0
        press.onRemoteTransportPreparation = { transportPreparations += 1 }
        press.onRemoteRoutePreparation = { routePreparations += 1 }
        openPersistentSession(press)

        let gestureID = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true,
            preparesRemoteTransport: true
        ))
        captureMappedDown(filter)
        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertEqual(transportPreparations, 1)
        XCTAssertEqual(routePreparations, 0)
        XCTAssertEqual(events.map(\.1), [true, false], "no input trigger before hold commit")
        XCTAssertFalse(press.hasRemoteAudio)
        XCTAssertFalse(VoicePressCoordinator.isLongPress(heldDuration: 0.299))
        XCTAssertTrue(VoicePressCoordinator.isLongPress(heldDuration: 0.300))
        XCTAssertFalse(VoicePressCoordinator.isPersistentSessionLongPress(heldDuration: 0.185))
        XCTAssertFalse(VoicePressCoordinator.isPersistentSessionLongPress(heldDuration: 0.250))
        XCTAssertFalse(VoicePressCoordinator.isPersistentSessionLongPress(heldDuration: 0.299))
        XCTAssertTrue(VoicePressCoordinator.isPersistentSessionLongPress(heldDuration: 0.300))
        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertEqual(routePreparations, 0)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertTrue(press.keyUp())
        press.stop()
    }

    func testPersistentHoldSuppressesMappedTriggerAndUsesFirstAudioGate() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        openPersistentSession(press)
        let gestureID = UUID()

        press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        )
        captureMappedDown(filter)
        waitForCoordinatorTiming(0.35)

        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertEqual(press.remoteSegmentTriggerPolicyForTesting, .audioOnly)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertEqual(events.map(\.1), [true, false])

        press.setRemoteAudioAvailable()

        XCTAssertTrue(press.hasRemoteAudio)
        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertEqual(events.map(\.1), [true, false])

        XCTAssertTrue(press.keyUp())
        XCTAssertTrue(press.hasPendingTailForTesting)
        press.invokeTailCompletionForTesting(sessionID: gestureID)
        waitForCoordinatorTiming(0.85)

        XCTAssertFalse(press.hasRemoteAudio)
        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertEqual(events.map(\.1), [true, false])
        press.stop()
    }

    func testPersistentNoAudioHoldCompletesSuppressionWithoutTriggerEdges() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        openPersistentSession(press)
        let gestureID = UUID()

        press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        )
        captureMappedDown(filter)
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)

        press.setRemoteStreaming(false)

        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertFalse(
            press.keyDown(
                sessionID: UUID(),
                togglesPersistentVoiceSession: true,
                usesHardwareOption: true
            )
        )
        XCTAssertTrue(press.keyUp())

        waitForCoordinatorTiming(0.85)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertEqual(events.map(\.1), [true, false])
        press.stop()
    }

    func testNoPCMPhysicalReleaseKeepsLateMappedReleaseSuppressed() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in events.append((key, down)) })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        openPersistentSession(press)
        let gestureID = UUID()
        press.keyDown(sessionID: gestureID, togglesPersistentVoiceSession: true, usesHardwareOption: true)
        captureMappedDown(filter)
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertTrue(press.keyUp())
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyUp
        ), "late mapped release after no-PCM cleanup must remain swallowed")
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .flagsChanged,
            eventFlags: []
        ), "second mapped release representation must also be swallowed")
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertNil(trigger.activeSessionID)
        XCTAssertFalse(trigger.isOptionDown)
        press.stop()
    }

    func testStopDuringActiveSuppressionClearsOwnerWithoutTriggerEdges() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in events.append((key, down)) })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        openPersistentSession(press)
        let gestureID = UUID()
        press.keyDown(sessionID: gestureID, togglesPersistentVoiceSession: true, usesHardwareOption: true)
        captureMappedDown(filter)
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        press.stop()
        XCTAssertFalse(press.persistentSessionActiveForTesting)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertNil(trigger.activeSessionID)
        XCTAssertFalse(trigger.isOptionDown)
        XCTAssertEqual(events.map(\.1), [true, false])
    }

    func testPersistentSessionAcceptsMultipleAudioOnlySegmentsThenClosesByTap() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        openPersistentSession(press)
        var acceptedAudioSegments = 0

        for _ in 0..<3 {
            waitForCoordinatorTiming(0.20)
            let gestureID = UUID()
            press.keyDown(
                sessionID: gestureID,
                togglesPersistentVoiceSession: true,
                usesHardwareOption: true
            )
            captureMappedDown(filter)
            waitForCoordinatorTiming(0.35)
            press.setRemoteAudioAvailable()
            if press.hasRemoteAudio { acceptedAudioSegments += 1 }
            XCTAssertEqual(events.map(\.1), [true, false])
            XCTAssertTrue(press.keyUp())
            press.invokeTailCompletionForTesting(sessionID: gestureID)
            waitForCoordinatorTiming(0.85)
            XCTAssertTrue(press.persistentSessionActiveForTesting)
            XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        }

        XCTAssertEqual(acceptedAudioSegments, 3)
        XCTAssertEqual(events.map(\.1), [true, false])
        waitForCoordinatorTiming(0.20)
        press.keyDown(sessionID: UUID(), togglesPersistentVoiceSession: true)
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertFalse(press.persistentSessionActiveForTesting)
        XCTAssertEqual(events.map(\.1), [true, false, true, false])
        press.stop()
    }

    func testMomentarySessionStillWaitsForFirstPCMThenBalancesTriggerAfterDrain() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onRemoteOutputDrain = { _, completion in completion() }

        let gestureID = UUID()
        press.keyDown(sessionID: gestureID, usesLocalMicrophone: false)
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertEqual(press.remoteSegmentTriggerPolicyForTesting, .momentaryTrigger)
        XCTAssertTrue(events.isEmpty)

        press.setRemoteAudioAvailable()
        XCTAssertEqual(events.map(\.1), [true])
        XCTAssertTrue(press.keyUp())
        press.invokeTailCompletionForTesting(sessionID: gestureID)

        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertFalse(press.persistentSessionActiveForTesting)
        press.stop()
    }

    func testExplicitStopResetsPersistentOwnershipWithoutAnotherTriggerTap() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        openPersistentSession(press)

        press.stop()

        XCTAssertFalse(press.persistentSessionActiveForTesting)
        XCTAssertEqual(events.map(\.1), [true, false])
    }

    func testTransportLossDrainsPersistentSegmentAndKeepsSessionOpen() {
        var events: [(VoiceTriggerKey, Bool)] = []
        var completeOutputDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        press.onRemoteOutputDrain = { _, completion in
            completeOutputDrain = completion
        }
        openPersistentSession(press)
        let gestureID = UUID()

        press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        )
        captureMappedDown(filter)
        waitForCoordinatorTiming(0.35)
        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.hasRemoteAudio)

        press.handleTransportLoss()

        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertFalse(press.hasPendingTailForTesting)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertEqual(events.map(\.1), [true, false])

        XCTAssertNotNil(completeOutputDrain)
        completeOutputDrain?()

        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.85)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertEqual(events.map(\.1), [true, false])
        press.stop()
    }

    func testHIDRemovalResetsSuppressedSegmentAfterOutputDrainWithoutClosingSession() {
        var events: [(VoiceTriggerKey, Bool)] = []
        var completeOutputDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        press.onRemoteOutputDrain = { _, completion in
            completeOutputDrain = completion
        }
        openPersistentSession(press)
        let gestureID = UUID()

        press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        )
        captureMappedDown(filter)
        waitForCoordinatorTiming(0.35)
        press.setRemoteAudioAvailable()

        press.handleTransportLoss(deviceRemoved: true)

        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertEqual(events.map(\.1), [true, false])
        completeOutputDrain?()

        XCTAssertTrue(press.persistentSessionActiveForTesting)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertEqual(events.map(\.1), [true, false])
        press.stop()
    }

    func testOpenPersistentSettingsSessionDoesNotBlockVoiceTriggerReconfiguration() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        openPersistentSession(press)

        XCTAssertFalse(press.hasActiveVoiceOwnershipForTriggerReconfiguration)
        press.stop()
    }

    private func openPersistentSession(_ press: VoicePressCoordinator) {
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                togglesPersistentVoiceSession: true
            )
        )
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)
    }

    private func wireHardwareGate(_ press: VoicePressCoordinator, filter: VoiceKeyFilter) {
        press.onHardwareOptionGateBegin = { filter.beginOptionDeferral(gestureID: $0) }
        press.onHardwareOptionGateSuppressForAudioOnly = { sessionID in
            filter.suppressDeferredHardwareTrigger(
                gestureID: sessionID,
                reason: "persistent-audio-only"
            )
        }
        press.onHardwareOptionGateResetSuppression = { sessionID in
            _ = filter.resetSuppressedHardwareTrigger(
                gestureID: sessionID,
                reason: "device-removed-after-drain"
            )
        }
        press.onHardwareOptionGateLongReady = { sessionID in
            filter.releaseDeferredOption(gestureID: sessionID, reason: "first-pcm")
        }
        press.onHardwareOptionGateShortReplay = { sessionID in
            filter.releaseDeferredOption(gestureID: sessionID, reason: "short-tap")
        }
        press.onPersistentSessionTriggerTap = { sessionID, triggerKey, purpose in
            filter.emitPersistentShortTap(
                gestureID: sessionID,
                reason: "persistent-session-test",
                triggerKey: triggerKey,
                purpose: purpose
            )
        }
        press.onDeferredPersistentSessionTriggerTap = { sessionID, triggerKey, purpose in
            filter.emitDeferredPersistentShortTap(
                gestureID: sessionID,
                triggerKey: triggerKey,
                purpose: purpose
            )
        }
        press.onHardwareOptionGateCancel = {
            filter.cancelDeferredOption(gestureID: $0, reason: "cancel")
        }
        filter.onSuppressedHardwareTriggerSafelyClosed = { [weak press] ownerID in
            press?.suppressedHardwareGateDidClose(ownerID: ownerID)
        }
        filter.onSuppressedHardwareTriggerInvalidated = { [weak press] ownerID, reason in
            press?.suppressedHardwareGateWasInvalidated(ownerID: ownerID, reason: reason)
        }
        press.onHardwareOptionGatePhysicalUp = { filter.armHardwareOptionRelease(gestureID: $0) }
        press.onHardwareOptionGateOutputDrained = {
            filter.releaseHeldHardwareOption(gestureID: $0, reason: "drained")
        }
        press.onRemoteOutputDrain = { _, completion in completion() }
    }

    private func captureMappedDown(
        _ filter: VoiceKeyFilter,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: VoiceTriggerKey.leftOption.cgKeyCode,
            keyDown: true
        ) else {
            XCTFail("could not create mapped trigger-down event", file: file, line: line)
            return
        }
        if filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyDown
        ) {
            return
        }
        XCTAssertTrue(filter.captureDeferredHardwareOptionEdge(.down, copiedEvent: event), file: file, line: line)
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}
