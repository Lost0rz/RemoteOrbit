import CoreGraphics
import XCTest
@testable import RemoteOrbit

final class PersistentSessionRotationTests: XCTestCase {
    private final class EventRecorder {
        var events: [(VoiceTriggerKey, Bool)] = []
    }

    func testShortArmOpensExternalPersistentSessionWithOneTap() {
        let harness = makeHarness(ownerKey: .rightCommand)

        togglePersistentSession(harness)

        XCTAssertEqual(harness.recorder.events.map(\.0), [.rightCommand, .rightCommand])
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false])
        XCTAssertEqual(harness.press.diagnosticStateFields["persistent_mode"] as? String, "persistent_open")
        harness.press.stop()
    }

    func testPersistentAudioIsEdgeFreeUntilDrainThenRotatesCloseReopen() {
        let harness = makeHarness(ownerKey: .rightOption)
        togglePersistentSession(harness)
        let armEvents = harness.recorder.events.map(\.1)
        XCTAssertEqual(armEvents, [true, false])

        let segmentID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: segmentID,
            togglesPersistentVoiceSession: true
        ))
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(String(describing: harness.press.remoteSegmentTriggerPolicyForTesting), "audioOnlyPersistentSegment")
        harness.press.setRemoteAudioAvailable()
        XCTAssertEqual(harness.recorder.events.map(\.1), armEvents, "audio must not emit Persistent trigger edges")

        XCTAssertTrue(harness.press.keyUp())
        harness.press.invokeTailCompletionForTesting(sessionID: segmentID)
        waitForCoordinatorTiming(0.25)

        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightOption, count: 6))
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false, true, false])
        XCTAssertEqual(harness.press.diagnosticStateFields["persistent_mode"] as? String, "persistent_open")
        XCTAssertEqual(harness.press.diagnosticStateFields["synthetic_owner"] as? String, "none")
        XCTAssertEqual(harness.press.diagnosticStateFields["synthetic_down"] as? Bool, false)
        harness.press.stop()
    }

    func testNoPCMHoldDoesNotRotateExternalSession() {
        let harness = makeHarness(ownerKey: .leftControl)
        togglePersistentSession(harness)
        let armEdges = harness.recorder.events.map(\.1)

        XCTAssertTrue(harness.press.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true
        ))
        waitForCoordinatorTiming(0.35)
        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.10)

        XCTAssertEqual(harness.recorder.events.map(\.1), armEdges)
        XCTAssertEqual(harness.press.diagnosticStateFields["persistent_mode"] as? String, "persistent_open")
        harness.press.stop()
    }

    func testTwoSegmentsRotateIndependently() {
        let harness = makeHarness(ownerKey: .rightCommand)
        togglePersistentSession(harness)

        for segmentNumber in 1...2 {
            waitForCoordinatorTiming(0.20)
            completeAudioSegment(harness)
            let expectedEdgeCount = 2 + (segmentNumber * 4)
            XCTAssertEqual(harness.recorder.events.count, expectedEdgeCount)
            XCTAssertEqual(harness.press.currentSessionModeForTesting, .persistentOpen)
            XCTAssertNil(harness.trigger.activeSessionID)
            XCTAssertFalse(harness.trigger.isOptionDown)
        }

        XCTAssertEqual(harness.recorder.events.map(\.1), [
            true, false, true, false, true, false, true, false, true, false,
        ])
        harness.press.stop()
    }

    func testOwnerKeyStaysFrozenAcrossRotationDisarmAndNextArmUsesNewConfig() {
        let harness = makeHarness(ownerKey: .rightOption)
        togglePersistentSession(harness)
        XCTAssertEqual(harness.press.persistentSessionTriggerOwnerKeyForTesting, .rightOption)
        XCTAssertTrue(harness.press.configurePersistentSessionTriggerKey(.leftControl))

        completeAudioSegment(harness)
        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightOption, count: 6))
        XCTAssertEqual(harness.press.persistentSessionTriggerOwnerKeyForTesting, .rightOption)

        waitForCoordinatorTiming(0.20)
        togglePersistentSession(harness)
        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightOption, count: 8))
        XCTAssertNil(harness.press.persistentSessionTriggerOwnerKeyForTesting)

        waitForCoordinatorTiming(0.20)
        togglePersistentSession(harness)
        XCTAssertEqual(Array(harness.recorder.events.map(\.0).suffix(2)), [.leftControl, .leftControl])
        XCTAssertEqual(harness.press.persistentSessionTriggerOwnerKeyForTesting, .leftControl)
        harness.press.stop()
    }

    func testPhysicalMomentaryPairIsSuppressedWhilePersistentAudioUsesNoTriggerEdges() {
        let harness = makeHarness(ownerKey: .rightOption)
        togglePersistentSession(harness)
        let segmentID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: segmentID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: VoiceTriggerKey.leftOption.cgKeyCode,
                keyDown: isDown
            ) else {
                XCTFail("could not create physical Momentary trigger event")
                harness.press.stop()
                return
            }
            XCTAssertTrue(harness.filter.captureDeferredHardwareOptionEdge(
                isDown ? .down : .up,
                copiedEvent: event
            ))
        }

        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, segmentID)
        harness.press.setRemoteAudioAvailable()
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false])
        XCTAssertTrue(harness.press.keyUp())
        harness.press.invokeTailCompletionForTesting(sessionID: segmentID)
        waitForCoordinatorTiming(0.25)

        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightOption, count: 6))
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false, true, false])
        harness.press.stop()
        harness.filter.stop()
    }

    func testCloseFailureKeepsExternalSessionOpenAndOwner() {
        let harness = makeHarness(ownerKey: .rightCommand)
        togglePersistentSession(harness)
        var purposes: [String] = []
        harness.press.persistentTapDispatchForTesting = { sessionID, key, purpose, completion in
            purposes.append(purpose)
            guard purpose != "persistent_segment_close" else { return false }
            return harness.trigger.sendTap(
                sessionID: sessionID,
                key: key,
                duration: 0.01,
                purpose: purpose,
                completion: completion
            )
        }

        completeAudioSegment(harness)

        XCTAssertEqual(purposes, ["persistent_segment_close"])
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .persistentOpen)
        XCTAssertEqual(harness.press.persistentSessionTriggerOwnerKeyForTesting, .rightCommand)
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false])
        harness.press.stop()
    }

    func testReopenFailureFailsClosedAfterCloseTap() {
        let harness = makeHarness(ownerKey: .rightCommand)
        togglePersistentSession(harness)
        var purposes: [String] = []
        harness.press.persistentTapDispatchForTesting = { sessionID, key, purpose, completion in
            purposes.append(purpose)
            guard purpose != "persistent_segment_reopen" else { return false }
            return harness.trigger.sendTap(
                sessionID: sessionID,
                key: key,
                duration: 0.01,
                purpose: purpose,
                completion: completion
            )
        }

        completeAudioSegment(harness)

        XCTAssertEqual(purposes, ["persistent_segment_close", "persistent_segment_reopen"])
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
        XCTAssertNil(harness.press.persistentSessionTriggerOwnerKeyForTesting)
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false])
        harness.press.stop()
    }

    func testStopDuringCloseTapBalancesEdgeAndPreventsReopen() {
        let harness = makeHarness(ownerKey: .rightCommand)
        togglePersistentSession(harness)
        harness.press.persistentTapDispatchForTesting = { sessionID, key, purpose, completion in
            harness.trigger.sendTap(
                sessionID: sessionID,
                key: key,
                duration: purpose == "persistent_segment_close" ? 0.25 : 0.01,
                purpose: purpose,
                completion: completion
            )
        }

        beginAudioSegment(harness)
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true])
        harness.press.stop()
        waitForCoordinatorTiming(0.35)

        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightCommand, count: 4))
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false])
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
        XCTAssertNil(harness.press.persistentSessionTriggerOwnerKeyForTesting)
        XCTAssertNil(harness.trigger.activeSessionID)
    }

    func testStopAfterCloseUpBeforeQueuedReopenPreventsReopen() {
        let harness = makeHarness(ownerKey: .leftCommand)
        togglePersistentSession(harness)
        var purposes: [String] = []
        harness.press.persistentTapDispatchForTesting = { sessionID, key, purpose, completion in
            purposes.append(purpose)
            return harness.trigger.sendTap(
                sessionID: sessionID,
                key: key,
                duration: 0.01,
                purpose: purpose
            ) { succeeded in
                if purpose == "persistent_segment_close", succeeded {
                    harness.press.stop()
                }
                completion(succeeded)
            }
        }

        beginAudioSegment(harness)
        waitForCoordinatorTiming(0.25)

        XCTAssertEqual(purposes, ["persistent_segment_close"])
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false])
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
        XCTAssertNil(harness.press.persistentSessionTriggerOwnerKeyForTesting)
        XCTAssertNil(harness.trigger.activeSessionID)
    }

    func testStopDuringReopenTapBalancesEdgeAndPreventsLateCompletion() {
        let harness = makeHarness(ownerKey: .rightOption)
        togglePersistentSession(harness)
        var purposes: [String] = []
        harness.press.persistentTapDispatchForTesting = { sessionID, key, purpose, completion in
            purposes.append(purpose)
            return harness.trigger.sendTap(
                sessionID: sessionID,
                key: key,
                duration: purpose == "persistent_segment_reopen" ? 0.30 : 0.01,
                purpose: purpose,
                completion: completion
            )
        }

        beginAudioSegment(harness)
        waitForCoordinatorTiming(0.12)
        XCTAssertEqual(purposes, ["persistent_segment_close", "persistent_segment_reopen"])
        XCTAssertTrue(harness.trigger.isOptionDown)
        harness.press.stop()
        waitForCoordinatorTiming(0.35)

        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightOption, count: 6))
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false, true, false])
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
        XCTAssertNil(harness.press.persistentSessionTriggerOwnerKeyForTesting)
        XCTAssertNil(harness.trigger.activeSessionID)
        XCTAssertFalse(harness.trigger.isOptionDown)
    }

    func testRapidShortReleaseBeforeRotationCompletesRetainsDisarmIntent() {
        let harness = makeHarness(ownerKey: .rightCommand)
        openSessionWithoutMappedOwner(harness)
        let purposes = installTapRecorder(harness, segmentTapDuration: 0.18)
        beginAudioSegment(harness)
        waitForCoordinatorTiming(0.19)

        let rapidGestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: rapidGestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertTrue(harness.filter.isOptionDeferralActive(for: rapidGestureID))
        XCTAssertTrue(sendMappedPair(harness.filter, gestureID: rapidGestureID).isEmpty)
        XCTAssertTrue(harness.press.keyUp(), "physical UP before rotation completion must retain SHORT intent")
        XCTAssertEqual(
            purposes.values,
            ["persistent_segment_close", "persistent_segment_reopen"],
            "final DISARM must wait for rotation"
        )

        waitForCoordinatorTiming(0.65)

        XCTAssertEqual(purposes.values, [
            "persistent_segment_close",
            "persistent_segment_reopen",
            "persistent_close",
        ])
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
        XCTAssertNil(harness.press.persistentSessionTriggerOwnerKeyForTesting)
        XCTAssertNil(harness.trigger.activeSessionID)
        XCTAssertFalse(harness.trigger.isOptionDown)
        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightCommand, count: 8))
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false, true, false, true, false])
    }

    func testRapidMappedMomentaryPairDuringRotationNeverLeaks() {
        let harness = makeHarness(ownerKey: .rightOption)
        XCTAssertTrue(harness.trigger.configureVoiceTriggerKey(.leftOption))
        XCTAssertTrue(harness.filter.configureVoiceTriggerKey(.leftOption))
        openSessionWithoutMappedOwner(harness)
        let purposes = installTapRecorder(harness, segmentTapDuration: 0.16)
        beginAudioSegment(harness)
        waitForCoordinatorTiming(0.19)

        let rapidGestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: rapidGestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        let visibleKeys = sendMappedPair(harness.filter, gestureID: rapidGestureID)
        XCTAssertTrue(visibleKeys.isEmpty, "mapped Left Option must be swallowed during rotation")
        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.60)

        XCTAssertEqual(purposes.values, [
            "persistent_segment_close",
            "persistent_segment_reopen",
            "persistent_close",
        ])
        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightOption, count: 8))
        XCTAssertFalse(harness.recorder.events.contains { $0.0 == .leftOption })
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
    }

    func testRapidDownDoesNotAbortReopenTapOwner() {
        let harness = makeHarness(ownerKey: .rightCommand)
        openSessionWithoutMappedOwner(harness)
        let purposes = installTapRecorder(harness, segmentTapDuration: 0.20)
        beginAudioSegment(harness)
        waitForCoordinatorTiming(0.22)
        XCTAssertEqual(purposes.values, ["persistent_segment_close", "persistent_segment_reopen"])
        let reopenOwner = harness.trigger.activeSessionID
        XCTAssertNotNil(reopenOwner)
        XCTAssertTrue(harness.trigger.isOptionDown)

        let rapidGestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: rapidGestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertEqual(harness.trigger.activeSessionID, reopenOwner)
        XCTAssertTrue(harness.trigger.isOptionDown)
        XCTAssertTrue(harness.filter.isOptionDeferralActive(for: rapidGestureID))
        XCTAssertTrue(sendMappedPair(harness.filter, gestureID: rapidGestureID).isEmpty)
        XCTAssertTrue(harness.press.keyUp())

        waitForCoordinatorTiming(0.55)
        XCTAssertEqual(purposes.values, [
            "persistent_segment_close",
            "persistent_segment_reopen",
            "persistent_close",
        ])
        XCTAssertEqual(harness.recorder.events.map(\.1), Array(repeating: [true, false], count: 4).flatMap { $0 })
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
    }

    func testRapidLongReleaseDuringRotationIsDroppedWithoutDisarm() {
        let harness = makeHarness(ownerKey: .leftControl)
        openSessionWithoutMappedOwner(harness)
        let purposes = installTapRecorder(harness, segmentTapDuration: 0.50)
        beginAudioSegment(harness)
        waitForCoordinatorTiming(0.19)

        let heldGestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: heldGestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertTrue(harness.filter.isOptionDeferralActive(for: heldGestureID))
        XCTAssertTrue(sendMappedPair(harness.filter, gestureID: heldGestureID).isEmpty)
        waitForCoordinatorTiming(0.32)
        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.60)

        XCTAssertEqual(purposes.values, ["persistent_segment_close", "persistent_segment_reopen"])
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .persistentOpen)
        XCTAssertEqual(harness.press.persistentSessionTriggerOwnerKeyForTesting, .leftControl)
        XCTAssertFalse(harness.recorder.events.contains { $0.0 == .leftOption })
        harness.press.stop()
    }

    func testExistingSuppressionOwnerIsPreservedAndRapidDisarmClosesExactlyOnce() {
        let harness = makeHarness(ownerKey: .rightOption)
        XCTAssertTrue(harness.trigger.configureVoiceTriggerKey(.leftOption))
        XCTAssertTrue(harness.filter.configureVoiceTriggerKey(.leftOption))
        openSessionWithoutMappedOwner(harness)
        let purposes = installTapRecorder(harness, segmentTapDuration: 0.10)
        let segmentID = beginAudioSegment(harness, usesHardwareOption: true)
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, segmentID)
        waitForCoordinatorTiming(0.19)

        let rapidGestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: rapidGestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, segmentID)
        XCTAssertTrue(sendMappedPair(harness.filter, gestureID: rapidGestureID).isEmpty)
        XCTAssertTrue(harness.press.keyUp())

        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(purposes.values, ["persistent_segment_close", "persistent_segment_reopen"])
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .persistentOpen)
        XCTAssertTrue(harness.filter.completeSuppressedHardwareTriggerQuietPeriod(gestureID: segmentID))
        harness.press.suppressedHardwareGateDidClose(ownerID: segmentID)
        waitForCoordinatorTiming(0.15)

        XCTAssertEqual(purposes.values, [
            "persistent_segment_close",
            "persistent_segment_reopen",
            "persistent_close",
        ])
        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .rightOption, count: 8))
        XCTAssertFalse(harness.recorder.events.contains { $0.0 == .leftOption })
        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
        XCTAssertNil(harness.press.persistentSessionTriggerOwnerKeyForTesting)
    }

    func testStopCancelsReleasedDeferredDisarmAndMappedGate() {
        let harness = makeHarness(ownerKey: .rightCommand)
        openSessionWithoutMappedOwner(harness)
        let purposes = installTapRecorder(harness, segmentTapDuration: 0.24)
        beginAudioSegment(harness)
        waitForCoordinatorTiming(0.19)

        let rapidGestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: rapidGestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertTrue(harness.filter.isOptionDeferralActive(for: rapidGestureID))
        XCTAssertTrue(sendMappedPair(harness.filter, gestureID: rapidGestureID).isEmpty)
        XCTAssertTrue(harness.press.keyUp())
        harness.press.stop()
        waitForCoordinatorTiming(0.60)

        XCTAssertEqual(harness.press.currentSessionModeForTesting, .idle)
        XCTAssertNil(harness.press.persistentSessionTriggerOwnerKeyForTesting)
        XCTAssertNil(harness.trigger.activeSessionID)
        XCTAssertFalse(harness.trigger.isOptionDown)
        XCTAssertFalse(harness.filter.hasActiveHardwareTriggerOwnership)
        XCTAssertEqual(purposes.values, ["persistent_segment_close"])
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false])
    }

    func testShortDisarmAddsOnlyOneCloseTap() {
        let harness = makeHarness(ownerKey: .leftCommand)
        togglePersistentSession(harness)
        waitForCoordinatorTiming(0.20)
        togglePersistentSession(harness)

        XCTAssertEqual(harness.recorder.events.map(\.0), Array(repeating: .leftCommand, count: 4))
        XCTAssertEqual(harness.recorder.events.map(\.1), [true, false, true, false])
        XCTAssertEqual(harness.press.diagnosticStateFields["persistent_mode"] as? String, "idle")
        harness.press.stop()
    }

    private struct Harness {
        let recorder: EventRecorder
        let trigger: VoiceOptionTrigger
        let filter: VoiceKeyFilter
        let press: VoicePressCoordinator
    }

    private final class TapPurposeRecorder {
        var values: [String] = []
    }

    private func makeHarness(ownerKey: VoiceTriggerKey) -> Harness {
        let recorder = EventRecorder()
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, down in
            recorder.events.append((key, down))
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(optionTrigger: trigger)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(ownerKey))

        press.onPersistentModeToggle = { gestureID in
            filter.suppressPersistentModeToggle(gestureID: gestureID, reason: "rotation-test")
        }
        press.onDeferredPersistentModeToggle = { gestureID in
            filter.suppressDeferredPersistentModeToggle(gestureID: gestureID)
        }
        press.onHardwareOptionGateBegin = { filter.beginOptionDeferral(gestureID: $0) }
        press.onDeferredMappedTriggerGateBegin = {
            filter.beginDeferredMappedTriggerGateOnly(gestureID: $0)
        }
        press.onDeferredMappedTriggerGateDiscard = {
            filter.discardDeferredMappedTriggerGateOnly(gestureID: $0)
        }
        press.onDeferredMappedTriggerGateCancel = { gestureID, waitingOn, reason in
            filter.cancelDeferredMappedTriggerGateOnly(
                gestureID: gestureID,
                waitingOn: waitingOn,
                reason: reason
            )
        }
        press.onHardwareOptionGateSuppressForPersistentSegment = { gestureID in
            filter.suppressDeferredHardwareTrigger(gestureID: gestureID, reason: "persistent-audio-only")
        }
        press.onHardwareOptionGatePhysicalUp = { filter.armHardwareOptionRelease(gestureID: $0) }
        press.onHardwareOptionGateOutputDrained = {
            filter.releaseHeldHardwareOption(gestureID: $0, reason: "persistent-output-drained")
        }
        press.onHardwareOptionGateResetSuppression = {
            _ = filter.resetSuppressedHardwareTrigger(gestureID: $0, reason: "device-removed")
        }
        press.onHardwareOptionGateCancel = { filter.cancelDeferredOption(gestureID: $0, reason: "cancel") }
        filter.onSuppressedHardwareTriggerSafelyClosed = { [weak press] ownerID in
            press?.suppressedHardwareGateDidClose(ownerID: ownerID)
        }
        filter.onSuppressedHardwareTriggerInvalidated = { [weak press] ownerID, reason in
            press?.suppressedHardwareGateWasInvalidated(ownerID: ownerID, reason: reason)
        }
        press.onRemoteOutputDrain = { _, completion in completion() }
        return Harness(recorder: recorder, trigger: trigger, filter: filter, press: press)
    }

    private func togglePersistentSession(_ harness: Harness) {
        XCTAssertTrue(harness.press.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true
        ))
        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.10)
    }

    private func completeAudioSegment(_ harness: Harness) {
        beginAudioSegment(harness)
        waitForCoordinatorTiming(0.25)
    }

    @discardableResult
    private func beginAudioSegment(
        _ harness: Harness,
        usesHardwareOption: Bool = false
    ) -> UUID {
        let segmentID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: segmentID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: usesHardwareOption
        ))
        if usesHardwareOption {
            XCTAssertTrue(harness.filter.captureDeferredHardwareOptionEdge(
                .down,
                copiedEvent: mappedEvent(.leftOption, isDown: true)
            ))
        }
        waitForCoordinatorTiming(0.35)
        harness.press.setRemoteAudioAvailable()
        if usesHardwareOption {
            XCTAssertTrue(harness.filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: .keyUp
            ))
        }
        XCTAssertTrue(harness.press.keyUp())
        harness.press.invokeTailCompletionForTesting(sessionID: segmentID)
        return segmentID
    }

    private func openSessionWithoutMappedOwner(_ harness: Harness) {
        togglePersistentSession(harness)
        if let owner = harness.filter.suppressedHardwareTriggerSessionID {
            _ = harness.filter.resetSuppressedHardwareTrigger(
                gestureID: owner,
                reason: "test-open-session-settled"
            )
        }
    }

    private func installTapRecorder(
        _ harness: Harness,
        segmentTapDuration: TimeInterval
    ) -> TapPurposeRecorder {
        let purposes = TapPurposeRecorder()
        harness.press.persistentTapDispatchForTesting = { sessionID, key, purpose, completion in
            purposes.values.append(purpose)
            return harness.trigger.sendTap(
                sessionID: sessionID,
                key: key,
                duration: purpose == "persistent_segment_close"
                    || purpose == "persistent_segment_reopen"
                    ? segmentTapDuration
                    : 0.01,
                purpose: purpose,
                completion: completion
            )
        }
        return purposes
    }

    private func sendMappedPair(
        _ filter: VoiceKeyFilter,
        gestureID: UUID
    ) -> [VoiceTriggerKey] {
        var visible: [VoiceTriggerKey] = []
        for isDown in [true, false] {
            let type: CGEventType = isDown ? .keyDown : .keyUp
            if filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: type
            ) {
                continue
            }
            if filter.isOptionDeferralActive(for: gestureID),
               filter.captureDeferredHardwareOptionEdge(
                   isDown ? .down : .up,
                   copiedEvent: mappedEvent(.leftOption, isDown: isDown)
               ) {
                continue
            }
            visible.append(.leftOption)
        }
        return visible
    }

    private func mappedEvent(_ key: VoiceTriggerKey, isDown: Bool) -> CGEvent? {
        CGEvent(keyboardEventSource: nil, virtualKey: key.cgKeyCode, keyDown: isDown)
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}
