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

    func testPersistentModeArmAndDisarmAreInternalOnly() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        var routePreparations = 0
        press.onRemoteRoutePreparation = { routePreparations += 1 }

        openPersistentSession(press)

        XCTAssertTrue(press.persistentModeArmedForTesting)
        XCTAssertFalse(press.hasActiveVoiceOwnershipForTriggerReconfiguration)
        XCTAssertTrue(events.isEmpty, "arming Persistent must not open an external ASR session")
        XCTAssertEqual(routePreparations, 0)
        XCTAssertFalse(
            VoicePressCoordinator.isPersistentSessionLongPress(heldDuration: 0.185),
            "a real-world 185ms persistent-open tap must remain short"
        )

        waitForCoordinatorTiming(0.20)
        press.keyDown(sessionID: UUID(), togglesPersistentVoiceSession: true)
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertFalse(press.persistentModeArmedForTesting)
        XCTAssertEqual(press.currentSessionModeForTesting, .idle)
        XCTAssertTrue(events.isEmpty, "disarming must not send a final cumulative-transcript trigger")
        XCTAssertEqual(routePreparations, 0)
        press.stop()
    }

    func testPersistentSessionOpenHasNoAutomaticTimeout() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        openPersistentSession(press)

        waitForCoordinatorTiming(0.35)

        XCTAssertTrue(press.persistentModeArmedForTesting)
        XCTAssertEqual(press.currentSessionModeForTesting, .persistentArmed)
        press.stop()
    }

    func testPersistentSegmentCapturesConfiguredKeyAtSegmentStart() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightCommand))

        openPersistentSession(press)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.leftControl))

        let gestureID = UUID()
        XCTAssertTrue(press.keyDown(sessionID: gestureID, togglesPersistentVoiceSession: true))
        waitForCoordinatorTiming(0.35)
        XCTAssertFalse(press.configurePersistentSessionTriggerKey(.rightOption))
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events.map(\.0), [.leftControl])
        XCTAssertEqual(events.map(\.1), [true])
        XCTAssertTrue(press.keyUp())
        press.finishLongInput(sessionID: gestureID)

        XCTAssertEqual(events.map(\.0), [.leftControl, .leftControl])
        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightOption))
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
        XCTAssertTrue(events.isEmpty, "arming a Persistent hold must not emit an open tap")
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
        XCTAssertTrue(events.isEmpty)
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
        XCTAssertEqual(press.remoteSegmentTriggerPolicyForTesting, .persistentSegmentTrigger)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertTrue(events.isEmpty, "no trigger before first PCM")

        press.setRemoteAudioAvailable()

        XCTAssertTrue(press.hasRemoteAudio)
        XCTAssertTrue(press.persistentModeArmedForTesting)
        XCTAssertEqual(events.map(\.1), [true])

        XCTAssertTrue(press.keyUp())
        XCTAssertTrue(press.hasPendingTailForTesting)
        press.invokeTailCompletionForTesting(sessionID: gestureID)
        waitForCoordinatorTiming(0.85)

        XCTAssertFalse(press.hasRemoteAudio)
        XCTAssertTrue(press.persistentModeArmedForTesting)
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
        XCTAssertTrue(press.persistentModeArmedForTesting)
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
        XCTAssertTrue(press.persistentModeArmedForTesting)
        XCTAssertTrue(events.isEmpty, "a no-PCM segment must not emit trigger edges")
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
        XCTAssertTrue(press.persistentModeArmedForTesting)
        XCTAssertTrue(events.isEmpty, "no-PCM cleanup must not emit trigger edges")
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
        XCTAssertFalse(press.persistentModeArmedForTesting)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertNil(trigger.activeSessionID)
        XCTAssertFalse(trigger.isOptionDown)
        XCTAssertTrue(events.isEmpty, "stop before first PCM must not emit trigger edges")
    }

    func testPersistentArmedModeUsesIndependentTriggerTransactionForEverySegment() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onRemoteOutputDrain = { _, completion in completion() }
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightCommand))
        openPersistentSession(press)
        XCTAssertTrue(events.isEmpty)

        var expectedEdges: [Bool] = []
        var previousGestureID: UUID?
        for _ in 0..<2 {
            waitForCoordinatorTiming(0.20)
            let gestureID = UUID()
            XCTAssertNotEqual(gestureID, previousGestureID)
            previousGestureID = gestureID
            press.keyDown(
                sessionID: gestureID,
                togglesPersistentVoiceSession: true
            )
            waitForCoordinatorTiming(0.35)
            XCTAssertEqual(press.currentStateForTesting, .holding)
            XCTAssertEqual(
                events.map(\.1),
                expectedEdges,
                "each transaction must wait for first PCM before DOWN; events=\(events.map { "\($0.0.rawValue):\($0.1)" })"
            )
            press.setRemoteAudioAvailable()
            XCTAssertTrue(press.hasRemoteAudio)
            XCTAssertEqual(events.map(\.0).last, .rightCommand)
            XCTAssertEqual(events.map(\.1).last, true)
            expectedEdges.append(true)
            XCTAssertTrue(press.keyUp())
            press.finishLongInput(sessionID: gestureID)
            XCTAssertEqual(Array(events.map(\.0).suffix(2)), [.rightCommand, .rightCommand])
            XCTAssertEqual(Array(events.map(\.1).suffix(2)), [true, false])
            expectedEdges.append(false)
            XCTAssertTrue(press.persistentModeArmedForTesting)
            XCTAssertNil(trigger.activeSessionID, "segment owner must close before the next gesture")
            XCTAssertFalse(trigger.isOptionDown)
        }

        XCTAssertEqual(events.map(\.0), Array(repeating: .rightCommand, count: 4))
        XCTAssertEqual(events.map(\.1), expectedEdges)
        waitForCoordinatorTiming(0.20)
        press.keyDown(sessionID: UUID(), togglesPersistentVoiceSession: true)
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertFalse(press.persistentModeArmedForTesting)
        XCTAssertEqual(events.map(\.1), expectedEdges, "final disarm must add no external trigger")
        press.stop()
    }

    func testPersistentSegmentUsesCapturedPersistentKeyAndSuppressesMappedMomentaryKey() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        wireHardwareGate(press, filter: filter)
        press.onRemoteOutputDrain = { _, completion in completion() }
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightOption))
        openPersistentSession(press)

        let gestureID = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        captureMappedDown(filter)
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertTrue(events.isEmpty, "physical Momentary trigger must not leak or synthesize early")

        press.setRemoteAudioAvailable()
        XCTAssertEqual(events.map(\.0), [.rightOption])
        XCTAssertEqual(events.map(\.1), [true])
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)

        XCTAssertTrue(press.keyUp())
        press.finishLongInput(sessionID: gestureID)
        XCTAssertEqual(events.map(\.0), [.rightOption, .rightOption])
        XCTAssertEqual(events.map(\.1), [true, false])
        press.stop()
        filter.stop()
    }

    func testPersistentTriggerConfigurationIsBusyOnlyDuringActiveSegment() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightCommand))
        openPersistentSession(press)

        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.leftControl))
        let gestureID = UUID()
        XCTAssertTrue(press.keyDown(sessionID: gestureID, togglesPersistentVoiceSession: true))
        waitForCoordinatorTiming(0.35)
        XCTAssertFalse(press.configurePersistentSessionTriggerKey(.rightOption))
        XCTAssertFalse(trigger.configureVoiceTriggerKey(.rightOption))

        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.keyUp())
        press.finishLongInput(sessionID: gestureID)
        XCTAssertTrue(press.persistentModeArmedForTesting)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightOption))
        XCTAssertTrue(trigger.configureVoiceTriggerKey(.rightOption))
        press.stop()
    }

    func testStoppingActivePersistentSegmentBalancesItsCapturedTrigger() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            events.append((key, down))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightCommand))
        openPersistentSession(press)
        XCTAssertTrue(events.isEmpty, "stopping an armed idle mode must be silent")

        let gestureID = UUID()
        XCTAssertTrue(press.keyDown(sessionID: gestureID, togglesPersistentVoiceSession: true))
        waitForCoordinatorTiming(0.35)
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events.map(\.0), [.rightCommand])
        XCTAssertEqual(events.map(\.1), [true])

        press.stop()

        XCTAssertEqual(events.map(\.0), [.rightCommand, .rightCommand])
        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertNil(trigger.activeSessionID)
        XCTAssertFalse(trigger.isOptionDown)
        XCTAssertEqual(press.currentSessionModeForTesting, .idle)
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
        XCTAssertFalse(press.persistentModeArmedForTesting)
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

        XCTAssertFalse(press.persistentModeArmedForTesting)
        XCTAssertTrue(events.isEmpty, "stopping an armed idle mode must not tap the trigger")
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

        XCTAssertTrue(press.persistentModeArmedForTesting)
        XCTAssertFalse(press.hasPendingTailForTesting)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertEqual(events.map(\.1), [true], "UP must wait for the output drain")

        XCTAssertNotNil(completeOutputDrain)
        completeOutputDrain?()

        XCTAssertTrue(press.persistentModeArmedForTesting)
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

        XCTAssertTrue(press.persistentModeArmedForTesting)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, gestureID)
        XCTAssertEqual(events.map(\.1), [true], "UP must wait for the output drain")
        completeOutputDrain?()

        XCTAssertTrue(press.persistentModeArmedForTesting)
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
        press.onHardwareOptionGateSuppressForPersistentSegment = { sessionID in
            filter.suppressDeferredHardwareTrigger(
                gestureID: sessionID,
                reason: "persistent-segment"
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
        press.onPersistentModeToggle = { sessionID in
            filter.suppressPersistentModeToggle(
                gestureID: sessionID,
                reason: "persistent-mode-test"
            )
        }
        press.onDeferredPersistentModeToggle = { sessionID in
            filter.suppressDeferredPersistentModeToggle(gestureID: sessionID)
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
