import CoreGraphics
import XCTest
@testable import RemoteOrbit

final class VoiceKeyFilterTests: XCTestCase {
    func testPendingReplayUpRemainsHardwareOwnership() throws {
        let recorder = HardwareReplayPostRecorder()
        let (filter, gestureID) = makePendingHardwareReplayUp(recorder: recorder)

        XCTAssertEqual(recorder.events.count, 1, "the copied UP must be posted once")
        XCTAssertTrue(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertFalse(
            filter.beginVoiceTriggerReconfiguration(from: .rightOption, to: .leftOption),
            "B-to-A restore must remain blocked until the replayed UP passes the filter"
        )
        XCTAssertFalse(filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode
        ))
        XCTAssertEqual(filter.pendingReplayedHardwareOptionUpGestureID, gestureID)
    }

    func testExpectedReplayedHardwareUpPassAcknowledgementAllowsRestore() throws {
        let recorder = HardwareReplayPostRecorder()
        let (filter, gestureID) = makePendingHardwareReplayUp(recorder: recorder)
        let replayedEvent = try XCTUnwrap(recorder.events.first)
        let keyCode = CGKeyCode(replayedEvent.getIntegerValueField(.keyboardEventKeycode))
        let eventType = replayedEvent.type
        let timestamp = replayedEvent.timestamp
        let flags = replayedEvent.flags
        let userData = replayedEvent.getIntegerValueField(.eventSourceUserData)
        var acknowledgements: [UUID] = []
        filter.onReplayedHardwareOptionUpPassAcknowledged = { acknowledgements.append($0) }

        XCTAssertFalse(filter.shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: keyCode))
        XCTAssertTrue(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            replayedEvent,
            type: eventType
        ))
        XCTAssertEqual(acknowledgements, [gestureID])
        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertTrue(filter.beginVoiceTriggerReconfiguration(from: .rightOption, to: .leftOption))
        XCTAssertTrue(filter.shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: keyCode))

        XCTAssertFalse(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            replayedEvent,
            type: eventType
        ), "the same component must not acknowledge twice")
        XCTAssertEqual(acknowledgements, [gestureID])
        XCTAssertEqual(replayedEvent.type, eventType)
        XCTAssertEqual(replayedEvent.timestamp, timestamp)
        XCTAssertEqual(replayedEvent.flags, flags)
        XCTAssertEqual(replayedEvent.getIntegerValueField(.keyboardEventKeycode), Int64(keyCode))
        XCTAssertEqual(replayedEvent.getIntegerValueField(.eventSourceUserData), userData)
    }

    func testPendingReplayUpWaitsForEveryCopiedComponent() throws {
        let recorder = HardwareReplayPostRecorder()
        let (filter, gestureID) = makePendingHardwareReplayUp(
            recorder: recorder,
            eventTypes: [.flagsChanged, .keyUp]
        )
        let replayedEvents = recorder.events
        XCTAssertEqual(replayedEvents.count, 2)
        var acknowledgements: [UUID] = []
        filter.onReplayedHardwareOptionUpPassAcknowledged = { acknowledgements.append($0) }

        XCTAssertTrue(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            replayedEvents[0],
            type: replayedEvents[0].type
        ))
        XCTAssertEqual(filter.pendingReplayedHardwareOptionUpGestureID, gestureID)
        XCTAssertTrue(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertTrue(acknowledgements.isEmpty)

        XCTAssertTrue(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            replayedEvents[1],
            type: replayedEvents[1].type
        ))
        XCTAssertNil(filter.pendingReplayedHardwareOptionUpGestureID)
        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertEqual(acknowledgements, [gestureID])
    }

    func testWrongKeyTypeOrTimestampCannotAcknowledgePendingReplay() throws {
        let recorder = HardwareReplayPostRecorder()
        let (filter, _) = makePendingHardwareReplayUp(recorder: recorder)
        let expectedEvent = try XCTUnwrap(recorder.events.first)
        let wrongKeyEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: VoiceTriggerKey.leftOption.cgKeyCode,
            keyDown: false
        )!
        let wrongTimestampEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: VoiceTriggerKey.rightOption.cgKeyCode,
            keyDown: false
        )!
        wrongTimestampEvent.timestamp = expectedEvent.timestamp &+ 1

        XCTAssertNotEqual(wrongTimestampEvent.timestamp, expectedEvent.timestamp)
        XCTAssertFalse(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            wrongKeyEvent,
            type: expectedEvent.type
        ))
        XCTAssertFalse(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            expectedEvent,
            type: .flagsChanged
        ))
        XCTAssertFalse(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            wrongTimestampEvent,
            type: expectedEvent.type
        ))
        XCTAssertTrue(filter.hasActiveHardwareTriggerOwnership)
    }

    func testSupersededReplayCannotAcknowledgeInvalidatedGesture() throws {
        let recorder = HardwareReplayPostRecorder()
        let (filter, gestureID) = makePendingHardwareReplayUp(recorder: recorder)
        let replayedEvent = try XCTUnwrap(recorder.events.first)
        var acknowledgements: [UUID] = []
        filter.onReplayedHardwareOptionUpPassAcknowledged = { acknowledgements.append($0) }

        filter.cancelDeferredOption(gestureID: gestureID, reason: "superseded-test")

        XCTAssertNil(filter.pendingReplayedHardwareOptionUpGestureID)
        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertFalse(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            replayedEvent,
            type: replayedEvent.type
        ))
        XCTAssertTrue(acknowledgements.isEmpty)
    }

    func testStopInvalidatesPendingReplayAndRejectsLateAcknowledgement() throws {
        let recorder = HardwareReplayPostRecorder()
        let (filter, _) = makePendingHardwareReplayUp(recorder: recorder)
        let replayedEvent = try XCTUnwrap(recorder.events.first)

        filter.stop()

        XCTAssertNil(filter.pendingReplayedHardwareOptionUpGestureID)
        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertFalse(filter.acknowledgeReplayedHardwareOptionUpIfExpected(
            replayedEvent,
            type: replayedEvent.type
        ))
    }

    func testSelectedKeyCodeAndModifierDriveFilterRecognition() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)

        for key in VoiceTriggerKey.allCases {
            XCTAssertTrue(filter.configureVoiceTriggerKey(key))
            XCTAssertTrue(filter.matchesTriggerKeyCode(key.cgKeyCode))
            XCTAssertTrue(filter.isTriggerModifierActive(flags: key.cgEventFlag))

            let otherKey = VoiceTriggerKey.allCases.first { $0 != key }!
            XCTAssertFalse(filter.matchesTriggerKeyCode(otherKey.cgKeyCode))
            let otherModifier: CGEventFlags = key.cgEventFlag == .maskAlternate
                ? .maskControl
                : .maskAlternate
            XCTAssertFalse(filter.isTriggerModifierActive(flags: otherModifier))
        }
    }

    func testIdleFilterConfigurationKeepsFilterAndSyntheticTargetsInSync() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)

        XCTAssertTrue(filter.configureVoiceTriggerKey(.rightControl))

        XCTAssertEqual(filter.voiceTriggerKey, .rightControl)
        XCTAssertEqual(trigger.voiceTriggerKey, .rightControl)
    }

    func testFilterRejectsConfigurationDuringAnActiveGesture() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()
        filter.beginOptionDeferral(gestureID: sessionID)

        XCTAssertFalse(filter.configureVoiceTriggerKey(.rightControl))

        XCTAssertEqual(filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(trigger.voiceTriggerKey, .leftOption)
        filter.cancelDeferredOption(gestureID: sessionID, reason: "test-cleanup")
    }

    func testLongConfirmationKeepsGateOpenUntilLateMappedDownArrives() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { events.append(($0, $1)) })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()

        XCTAssertTrue(filter.beginOptionDeferral(gestureID: sessionID))
        XCTAssertTrue(filter.confirmLongOption(gestureID: sessionID))
        XCTAssertTrue(filter.isOptionDeferralActive(for: sessionID))
        XCTAssertTrue(filter.captureDeferredHardwareOptionEdgeForTesting(.down, copied: false))

        XCTAssertFalse(filter.isOptionDeferralActive(for: sessionID))
        XCTAssertEqual(events.map { $0.1 }, [true])
    }

    func testShortDiscardConsumesLateMappedEdgesWithoutSyntheticTrigger() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in
            XCTFail("a short candidate must not emit a synthetic trigger")
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()

        XCTAssertTrue(filter.beginOptionDeferral(gestureID: sessionID))
        XCTAssertTrue(
            filter.discardDeferredHardwareTrigger(
                gestureID: sessionID,
                reason: "short-candidate-test"
            )
        )
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)
        XCTAssertTrue(
            filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: .flagsChanged
            )
        )
        XCTAssertTrue(
            filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: .keyUp
            )
        )
        XCTAssertTrue(
            filter.resetSuppressedHardwareTrigger(
                gestureID: sessionID,
                reason: "short-candidate-test-cleanup"
            )
        )
    }

    func testReadOnlyHardwareOwnershipReportsActiveAndSuppressedGates() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()

        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)
        filter.beginOptionDeferral(gestureID: sessionID)
        XCTAssertTrue(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertTrue(filter.captureDeferredHardwareOptionEdge(.down, copiedEvent: nil))
        XCTAssertTrue(filter.suppressDeferredHardwareTrigger(
            gestureID: sessionID,
            reason: "ownership-test"
        ))
        XCTAssertTrue(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertTrue(filter.resetSuppressedHardwareTrigger(
            gestureID: sessionID,
            reason: "ownership-test-cleanup"
        ))
        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)
    }

    func testFilterRejectsConfigurationWhenSyntheticTriggerAlreadyHasAnOwner() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()
        XCTAssertTrue(trigger.begin(sessionID: sessionID))

        XCTAssertFalse(filter.configureVoiceTriggerKey(.rightControl))

        XCTAssertEqual(filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(trigger.voiceTriggerKey, .leftOption)
        _ = trigger.abort(sessionID: sessionID)
    }

    func testSuppressedMappedTriggerEdgesAreSwallowedForAllConfiguredKeys() {
        for key in VoiceTriggerKey.allCases {
            let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
            let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
            XCTAssertTrue(filter.configureVoiceTriggerKey(key), "key=\(key)")

            let sessionID = UUID()
            filter.beginOptionDeferral(gestureID: sessionID)
            captureDeferredMappedDown(in: filter, key: key)
            XCTAssertTrue(
                filter.suppressDeferredHardwareTrigger(
                    gestureID: sessionID,
                    reason: "test-audio-only"
                ),
                "key=\(key)"
            )

            XCTAssertFalse(filter.isOptionDeferralActive(for: sessionID), "key=\(key)")
            XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID, "key=\(key)")
            XCTAssertNil(trigger.activeSessionID, "key=\(key)")
            XCTAssertFalse(trigger.isOptionDown, "key=\(key)")

            XCTAssertTrue(
                filter.shouldSuppressDiscardedHardwareTriggerEvent(
                    keyCode: key.cgKeyCode,
                    type: .keyDown
                ),
                "matching keyDown must be swallowed for key=\(key)"
            )
            XCTAssertTrue(
                filter.shouldSuppressDiscardedHardwareTriggerEvent(
                    keyCode: key.cgKeyCode,
                    type: .flagsChanged
                ),
                "matching active flagsChanged must be swallowed for key=\(key)"
            )
            XCTAssertTrue(
                filter.shouldSuppressDiscardedHardwareTriggerEvent(
                    keyCode: key.cgKeyCode,
                    type: .flagsChanged
                ),
                "matching inactive flagsChanged must be swallowed for key=\(key)"
            )
            XCTAssertTrue(
                filter.shouldSuppressDiscardedHardwareTriggerEvent(
                    keyCode: key.cgKeyCode,
                    type: .keyUp
                ),
                "matching keyUp must be swallowed for key=\(key)"
            )
            XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID, "key=\(key)")
        }
    }

    func testSuppressedMappedTriggerDoesNotSuppressUnrelatedKey() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()
        filter.beginOptionDeferral(gestureID: sessionID)
        captureDeferredMappedDown(in: filter)
        XCTAssertTrue(
            filter.suppressDeferredHardwareTrigger(
                gestureID: sessionID,
                reason: "test-audio-only"
            )
        )

        XCTAssertFalse(
            filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: 0,
                type: .keyDown
            )
        )
    }

    func testSuppressedOwnershipWaitsForPhysicalUpAndOutputDrain() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()
        filter.beginOptionDeferral(gestureID: sessionID)
        captureDeferredMappedDown(in: filter)
        XCTAssertTrue(
            filter.suppressDeferredHardwareTrigger(
                gestureID: sessionID,
                reason: "test-audio-only"
            )
        )

        XCTAssertFalse(
            filter.completeSuppressedHardwareTrigger(
                gestureID: sessionID,
                reason: "early-drain"
            )
        )
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)
        XCTAssertFalse(
            filter.armSuppressedHardwareTriggerRelease(gestureID: UUID())
        )
        XCTAssertFalse(
            filter.completeSuppressedHardwareTrigger(
                gestureID: UUID(),
                reason: "stale-drain"
            )
        )
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)

        XCTAssertTrue(
            filter.armSuppressedHardwareTriggerRelease(gestureID: sessionID)
        )
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)
        XCTAssertFalse(
            filter.completeSuppressedHardwareTrigger(
                gestureID: UUID(),
                reason: "stale-drain-after-release"
            )
        )
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)
        XCTAssertTrue(
            filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: .keyUp
            )
        )
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)
        XCTAssertTrue(
            filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: .flagsChanged,
                eventFlags: []
            )
        )
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)
        XCTAssertTrue(
            filter.completeSuppressedHardwareTrigger(
                gestureID: sessionID,
                reason: "output-drained"
            )
        )
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)
        waitForFilterTiming(0.85)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertFalse(
            filter.completeSuppressedHardwareTrigger(
                gestureID: sessionID,
                reason: "duplicate-drain"
            )
        )
        XCTAssertTrue(events.isEmpty)
    }

    func testSuppressedOwnershipBlocksTriggerReconfiguration() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()
        filter.beginOptionDeferral(gestureID: sessionID)
        captureDeferredMappedDown(in: filter)
        XCTAssertTrue(
            filter.suppressDeferredHardwareTrigger(
                gestureID: sessionID,
                reason: "test-audio-only"
            )
        )

        XCTAssertFalse(filter.configureVoiceTriggerKey(.rightControl))
        XCTAssertFalse(
            filter.beginVoiceTriggerReconfiguration(
                from: .leftOption,
                to: .rightControl
            )
        )
        XCTAssertEqual(filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(trigger.voiceTriggerKey, .leftOption)
    }

    func testResetClearsSuppressedOwnershipWithoutSyntheticEdges() {
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()
        filter.beginOptionDeferral(gestureID: sessionID)
        captureDeferredMappedDown(in: filter)
        XCTAssertTrue(
            filter.suppressDeferredHardwareTrigger(
                gestureID: sessionID,
                reason: "test-audio-only"
            )
        )

        filter.cancelActiveOptionDeferral(reason: "test-supersede")
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)

        let resetSessionID = UUID()
        filter.beginOptionDeferral(gestureID: resetSessionID)
        captureDeferredMappedDown(in: filter)
        XCTAssertTrue(
            filter.suppressDeferredHardwareTrigger(
                gestureID: resetSessionID,
                reason: "test-audio-only-reset"
            )
        )
        filter.stop()

        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertTrue(events.isEmpty)
    }

    func testQATapRecreationReusesCallbackAndOnlyReplacesTapResources() throws {
        let harness = makeTapLifecycleHarness(createResults: [true, true])
        try harness.filter.start()

        XCTAssertTrue(harness.filter.isQuiescentForQATapRecreation)
        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .recreated(attempts: 1)
        )
        XCTAssertEqual(harness.resources.createCount, 2)
        XCTAssertEqual(harness.resources.removeCount, 1)
        XCTAssertEqual(harness.resources.callbackPointers.count, 2)
        XCTAssertEqual(
            harness.resources.callbackPointers[0],
            harness.resources.callbackPointers[1],
            "Tap recreation must reuse the same VoiceKeyFilter callback"
        )
        XCTAssertTrue(harness.resources.isReadyForEventDelivery)
        XCTAssertEqual(harness.promptRecorder.values, [false], "recreation must not prompt")
        XCTAssertTrue(harness.filter.hasAcceptedQATapRecreation)
        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .rejected(reason: "one_shot_already_used")
        )
        XCTAssertEqual(harness.resources.createCount, 2)
        XCTAssertEqual(harness.resources.removeCount, 1)
    }

    func testQATapRecreationAllowsOnlyOneBoundedReplacementRetry() throws {
        let harness = makeTapLifecycleHarness(createResults: [true, false, true])
        try harness.filter.start()

        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .recreated(attempts: 2)
        )
        XCTAssertEqual(harness.resources.createCount, 3)
        XCTAssertEqual(harness.resources.removeCount, 2)
        XCTAssertTrue(harness.resources.isReadyForEventDelivery)
    }

    func testQATapRecreationFailureLeavesTapAbsentAndCannotRepeat() throws {
        let harness = makeTapLifecycleHarness(createResults: [true, false, false])
        try harness.filter.start()

        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .degraded(reason: "replacement_failed_after_one_retry")
        )
        XCTAssertEqual(harness.resources.createCount, 3)
        XCTAssertEqual(harness.resources.removeCount, 3)
        XCTAssertTrue(harness.resources.isAbsent)
        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .rejected(reason: "one_shot_already_used")
        )
        XCTAssertEqual(harness.resources.createCount, 3)
    }

    func testQATapRecreationTeardownFailureDoesNotCreateReplacementOrCleanBusinessState() throws {
        let harness = makeTapLifecycleHarness(
            createResults: [true, true],
            removalResults: [false]
        )
        var voiceKeyCallbackCount = 0
        harness.filter.onVoiceKeyDown = { voiceKeyCallbackCount += 1 }
        harness.filter.onVoiceKeyUp = { voiceKeyCallbackCount += 1 }
        try harness.filter.start()

        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .degraded(reason: "old_tap_teardown_not_verified")
        )
        XCTAssertEqual(harness.resources.createCount, 1, "failed teardown must not attempt replacement")
        XCTAssertEqual(harness.resources.removeCount, 1)
        XCTAssertTrue(harness.resources.isReadyForEventDelivery)
        XCTAssertFalse(harness.resources.isAbsent, "the fake must preserve its failed resource state")
        XCTAssertTrue(harness.filter.hasAcceptedQATapRecreation)
        XCTAssertTrue(harness.syntheticEvents.events.isEmpty, "recreation must not emit modifier edges")
        XCTAssertEqual(voiceKeyCallbackCount, 0, "recreation must not invoke voice business callbacks")
        XCTAssertEqual(harness.promptRecorder.values, [false], "recreation must not prompt")

        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .rejected(reason: "one_shot_already_used")
        )
        XCTAssertEqual(harness.resources.createCount, 1)
        XCTAssertEqual(harness.resources.removeCount, 1)
        XCTAssertTrue(harness.resources.isReadyForEventDelivery)
    }

    func testQATapRecreationRejectsShortTapDiscardWithoutCleaningOwnership() throws {
        let harness = makeTapLifecycleHarness(createResults: [true, true])
        try harness.filter.start()
        let sessionID = UUID()
        XCTAssertTrue(harness.filter.beginOptionDeferral(gestureID: sessionID))
        XCTAssertTrue(harness.filter.discardDeferredHardwareTrigger(
            gestureID: sessionID,
            reason: "qa-recreation-gate-test"
        ))

        XCTAssertTrue(harness.filter.hasShortTapDiscardOwnership)
        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .rejected(reason: "filter_ownership_active_or_uncertain")
        )
        XCTAssertEqual(harness.resources.createCount, 1)
        XCTAssertEqual(harness.resources.removeCount, 0)
        XCTAssertTrue(harness.filter.hasShortTapDiscardOwnership)
        XCTAssertTrue(harness.filter.resetSuppressedHardwareTrigger(
            gestureID: sessionID,
            reason: "qa-recreation-test-cleanup"
        ))
    }

    func testQATapRecreationRejectsCallbackOwnershipAndUntrustedProcessWithoutPrompt() throws {
        let harness = makeTapLifecycleHarness(createResults: [true, true])
        try harness.filter.start()

        var callbackResult: VoiceKeyFilter.QATapRecreationResult?
        harness.filter.withTapCallbackOwnershipForTesting {
            callbackResult = harness.filter.recreateTapResourcesForQA()
        }
        XCTAssertEqual(
            callbackResult,
            .rejected(reason: "filter_ownership_active_or_uncertain")
        )
        XCTAssertEqual(harness.resources.removeCount, 0)

        harness.accessibilityTrust.isTrusted = false
        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .rejected(reason: "accessibility_trust_unavailable")
        )
        XCTAssertEqual(harness.promptRecorder.values, [false], "QA action must never prompt")
        XCTAssertEqual(harness.resources.removeCount, 0)
    }

    func testQATapRecreationRejectsReconfigurationAndInvalidTap() throws {
        let harness = makeTapLifecycleHarness(createResults: [true, true])
        try harness.filter.start()
        XCTAssertTrue(harness.filter.beginVoiceTriggerReconfiguration(
            from: .leftOption,
            to: .rightCommand
        ))
        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .rejected(reason: "filter_ownership_active_or_uncertain")
        )
        XCTAssertEqual(harness.resources.removeCount, 0)
        harness.filter.endVoiceTriggerReconfiguration()

        harness.resources.disable()
        XCTAssertEqual(
            harness.filter.recreateTapResourcesForQA(),
            .rejected(reason: "existing_tap_invalid_or_disabled")
        )
        XCTAssertEqual(harness.resources.removeCount, 0)
    }

    private func makeTapLifecycleHarness(
        createResults: [Bool],
        removalResults: [Bool] = []
    ) -> VoiceKeyFilterTapLifecycleHarness {
        let promptRecorder = AccessibilityPromptRecorder()
        let trust = AccessibilityTrustRecorder()
        let syntheticEvents = SyntheticTriggerEventRecorder()
        let resources = FakeVoiceKeyFilterTapResourceLifecycle(
            createResults: createResults,
            removalResults: removalResults
        )
        let filter = VoiceKeyFilter(
            syntheticOptionTrigger: VoiceOptionTrigger(keyedEventSink: { key, isDown in
                syntheticEvents.events.append((key, isDown))
            }),
            tapResourceLifecycle: resources,
            accessibilityTrustCheck: { trust.isTrusted },
            accessibilityTrustRequest: { prompt in
                promptRecorder.values.append(prompt)
                return trust.isTrusted
            }
        )
        return VoiceKeyFilterTapLifecycleHarness(
            filter: filter,
            resources: resources,
            promptRecorder: promptRecorder,
            accessibilityTrust: trust,
            syntheticEvents: syntheticEvents
        )
    }

    private func captureDeferredMappedDown(
        in filter: VoiceKeyFilter,
        key: VoiceTriggerKey = .leftOption,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: key.cgKeyCode,
            keyDown: true
        ) else {
            XCTFail("could not create test trigger-down event", file: file, line: line)
            return
        }
        XCTAssertTrue(
            filter.captureDeferredHardwareOptionEdge(.down, copiedEvent: event),
            file: file,
            line: line
        )
    }

    private func makePendingHardwareReplayUp(
        recorder: HardwareReplayPostRecorder,
        eventTypes: [CGEventType] = [.keyUp]
    ) -> (VoiceKeyFilter, UUID) {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(
            syntheticOptionTrigger: trigger,
            replayEventPoster: { recorder.events.append($0) }
        )
        let gestureID = UUID()
        XCTAssertTrue(filter.configureVoiceTriggerKey(VoiceTriggerKey.rightOption))
        filter.beginOptionDeferral(gestureID: gestureID)
        XCTAssertTrue(filter.captureDeferredHardwareOptionEdgeForTesting(
            HardwareOptionEdge.down,
            copied: true
        ))
        filter.releaseDeferredOption(gestureID: gestureID, reason: "replay-up-test")
        filter.armHardwareOptionRelease(gestureID: gestureID)

        for eventType in eventTypes {
            let upEvent = CGEvent(
                keyboardEventSource: nil,
                virtualKey: VoiceTriggerKey.rightOption.cgKeyCode,
                keyDown: false
            )!
            upEvent.type = eventType
            XCTAssertEqual(
                filter.captureHeldHardwareOptionUpEvent(upEvent, type: eventType),
                .captured
            )
        }
        filter.releaseHeldHardwareOption(gestureID: gestureID, reason: "replay-up-test-drain")
        return (filter, gestureID)
    }

    private func waitForFilterTiming(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}

private final class HardwareReplayPostRecorder {
    var events: [CGEvent] = []
}

private final class VoiceKeyFilterTapLifecycleHarness {
    let filter: VoiceKeyFilter
    let resources: FakeVoiceKeyFilterTapResourceLifecycle
    let promptRecorder: AccessibilityPromptRecorder
    let accessibilityTrust: AccessibilityTrustRecorder
    let syntheticEvents: SyntheticTriggerEventRecorder

    init(
        filter: VoiceKeyFilter,
        resources: FakeVoiceKeyFilterTapResourceLifecycle,
        promptRecorder: AccessibilityPromptRecorder,
        accessibilityTrust: AccessibilityTrustRecorder,
        syntheticEvents: SyntheticTriggerEventRecorder
    ) {
        self.filter = filter
        self.resources = resources
        self.promptRecorder = promptRecorder
        self.accessibilityTrust = accessibilityTrust
        self.syntheticEvents = syntheticEvents
    }
}

private final class SyntheticTriggerEventRecorder {
    var events: [(VoiceTriggerKey, Bool)] = []
}

private final class AccessibilityPromptRecorder {
    var values: [Bool] = []
}

private final class AccessibilityTrustRecorder {
    var isTrusted = true
}

private final class FakeVoiceKeyFilterTapResourceLifecycle:
    VoiceKeyFilterTapResourceLifecycle {
    private var createResults: [Bool]
    private var removalResults: [Bool]
    private var ready = false
    private var absent = true
    private(set) var createCount = 0
    private(set) var removeCount = 0
    private(set) var callbackPointers: [UInt] = []

    var tapPort: CFMachPort? { nil }
    var isReadyForEventDelivery: Bool { ready }
    var isAbsent: Bool { absent }

    init(createResults: [Bool], removalResults: [Bool]) {
        self.createResults = createResults
        self.removalResults = removalResults
    }

    func create(
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) throws {
        createCount += 1
        callbackPointers.append(unsafeBitCast(callback, to: UInt.self))
        let succeeded = createResults.isEmpty ? true : createResults.removeFirst()
        guard succeeded else { throw VoiceKeyFilter.FilterError.tapCreationFailed }
        ready = true
        absent = false
    }

    func removeAndVerifyAbsence() -> Bool {
        removeCount += 1
        let succeeded = removalResults.isEmpty ? true : removalResults.removeFirst()
        guard succeeded else { return false }
        ready = false
        absent = true
        return true
    }

    func disable() {
        ready = false
    }
}
