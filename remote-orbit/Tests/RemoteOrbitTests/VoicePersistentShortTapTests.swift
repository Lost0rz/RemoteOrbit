import CoreGraphics
import XCTest
@testable import RemoteOrbit

final class VoicePersistentShortTapTests: XCTestCase {
    private final class EventRecorder {
        var values: [(VoiceTriggerKey, Bool)] = []
    }

    private struct Harness {
        let recorder: EventRecorder
        let trigger: VoiceOptionTrigger
        let filter: VoiceKeyFilter
        let press: VoicePressCoordinator
    }

    func testNoOptionEdgeShortOpenArmsInternallyWithoutSyntheticTap() {
        let harness = makeHarness(key: .rightOption)

        let gestureID = shortTap(harness, usesHardwareOption: true)

        XCTAssertTrue(harness.press.persistentModeArmedForTesting)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, gestureID)
        stop(harness)
    }

    func testNoOptionEdgeShortCloseDisarmsInternallyWithoutSyntheticTap() {
        let harness = makeHarness(key: .leftControl)
        _ = shortTap(harness, usesHardwareOption: false)
        XCTAssertTrue(harness.press.persistentModeArmedForTesting)
        waitForCoordinatorTiming(0.20)

        _ = shortTap(harness, usesHardwareOption: true)

        XCTAssertFalse(harness.press.persistentModeArmedForTesting)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        stop(harness)
    }

    func testCapturedPhysicalMappedPairIsDiscardedWithoutSyntheticTap() {
        let harness = makeHarness(key: .rightOption)
        let gestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        guard let down = CGEvent(
            keyboardEventSource: nil,
            virtualKey: VoiceTriggerKey.rightOption.cgKeyCode,
            keyDown: true
        ), let up = CGEvent(
            keyboardEventSource: nil,
            virtualKey: VoiceTriggerKey.rightOption.cgKeyCode,
            keyDown: false
        ) else {
            XCTFail("could not create mapped trigger events")
            stop(harness)
            return
        }
        XCTAssertTrue(harness.filter.captureDeferredHardwareOptionEdge(.down, copiedEvent: down))
        XCTAssertTrue(harness.filter.captureDeferredHardwareOptionEdge(.up, copiedEvent: up))

        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertTrue(harness.recorder.values.isEmpty)
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, gestureID)
        stop(harness)
    }

    func testLateMappedEdgesAfterShortResolutionAreSuppressed() {
        let harness = makeHarness(key: .rightCommand)
        _ = shortTap(harness, usesHardwareOption: true)
        let edgeCountAfterModeToggle = harness.recorder.values.count
        XCTAssertNotNil(harness.filter.suppressedHardwareTriggerSessionID)

        XCTAssertTrue(suppresses(harness.filter, key: .rightCommand, type: .keyDown))
        XCTAssertTrue(suppresses(
            harness.filter,
            key: .rightCommand,
            type: .flagsChanged,
            flags: VoiceTriggerKey.rightCommand.cgEventFlag
        ))
        XCTAssertTrue(suppresses(
            harness.filter,
            key: .rightCommand,
            type: .flagsChanged,
            flags: CGEventFlags(rawValue: 0)
        ))
        XCTAssertTrue(suppresses(harness.filter, key: .rightCommand, type: .keyUp))
        XCTAssertEqual(harness.recorder.values.count, edgeCountAfterModeToggle)
        stop(harness)
    }

    func testUnrelatedKeyPassesWhileShortDiscardIsActive() {
        let harness = makeHarness(key: .leftOption)
        _ = shortTap(harness, usesHardwareOption: true)
        XCTAssertNotNil(harness.filter.suppressedHardwareTriggerSessionID)

        XCTAssertFalse(
            harness.filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: 0,
                type: .keyDown
            )
        )
        stop(harness)
    }

    func testLateMappedEdgeRestartsBoundedShortDiscardQuietWindow() {
        let harness = makeHarness(key: .rightCommand)
        let gestureID = shortTap(harness, usesHardwareOption: true)
        waitForCoordinatorTiming(0.45)

        XCTAssertTrue(suppresses(harness.filter, key: .rightCommand, type: .keyDown))
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, gestureID)
        waitForCoordinatorTiming(0.45)
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, gestureID)

        waitForCoordinatorTiming(0.40)
        XCTAssertNil(harness.filter.suppressedHardwareTriggerSessionID)
        stop(harness)
    }

    func testShortLongClassifierKeepsOriginalThreeHundredMillisecondBoundary() {
        for heldDuration in [0.05, 0.15, 0.25] {
            XCTAssertFalse(
                VoicePressCoordinator.isLongPress(heldDuration: heldDuration),
                "heldDuration=\(heldDuration)"
            )
        }
        XCTAssertTrue(VoicePressCoordinator.isLongPress(heldDuration: 0.31))
    }

    func testAllConfiguredKeysSuppressLateMappedEdgesWithoutSyntheticTap() {
        for key in VoiceTriggerKey.allCases {
            let harness = makeHarness(key: key)
            _ = shortTap(harness, usesHardwareOption: true)

            XCTAssertTrue(harness.recorder.values.isEmpty, "key=\(key)")
            XCTAssertTrue(suppresses(harness.filter, key: key, type: .keyDown), "key=\(key)")
            XCTAssertTrue(suppresses(
                harness.filter,
                key: key,
                type: .flagsChanged,
                flags: key.cgEventFlag
            ), "key=\(key)")
            XCTAssertTrue(suppresses(
                harness.filter,
                key: key,
                type: .flagsChanged,
                flags: CGEventFlags(rawValue: 0)
            ), "key=\(key)")
            XCTAssertTrue(suppresses(harness.filter, key: key, type: .keyUp), "key=\(key)")
            stop(harness)
        }
    }

    func testExternalTriggerAbortDoesNotBlockInternalPersistentModeToggles() {
        let harness = makeHarness(key: .rightOption)
        let gestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        _ = harness.trigger.abort(sessionID: gestureID)

        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertTrue(harness.press.persistentModeArmedForTesting)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        XCTAssertNil(harness.trigger.activeSessionID)
        waitForCoordinatorTiming(0.20)

        let closeGestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: closeGestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        _ = harness.trigger.abort(sessionID: closeGestureID)

        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertFalse(harness.press.persistentModeArmedForTesting)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        stop(harness)
    }

    func testPersistentShortCloseWaitsForPriorAudioSuppressionOwner() {
        let harness = makeHarness(key: .rightOption)
        let openGestureID = shortTap(harness, usesHardwareOption: false)
        XCTAssertTrue(harness.press.persistentModeArmedForTesting)
        XCTAssertTrue(harness.press.configurePersistentSessionTriggerKey(.leftControl))
        XCTAssertTrue(harness.filter.resetSuppressedHardwareTrigger(
            gestureID: openGestureID,
            reason: "test-prepare-audio-suppression"
        ))
        waitForCoordinatorTiming(0.20)

        let oldSegmentOwner = UUID()
        harness.filter.beginOptionDeferral(gestureID: oldSegmentOwner)
        guard let mappedDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: VoiceTriggerKey.rightOption.cgKeyCode,
            keyDown: true
        ) else {
            XCTFail("could not create mapped trigger-down event")
            stop(harness)
            return
        }
        XCTAssertTrue(harness.filter.captureDeferredHardwareOptionEdge(
            .down,
            copiedEvent: mappedDown
        ))
        XCTAssertTrue(harness.filter.suppressDeferredHardwareTrigger(
            gestureID: oldSegmentOwner,
            reason: "test-audio-only-hold"
        ))
        XCTAssertTrue(harness.filter.armSuppressedHardwareTriggerRelease(
            gestureID: oldSegmentOwner
        ))
        XCTAssertTrue(harness.filter.completeSuppressedHardwareTrigger(
            gestureID: oldSegmentOwner,
            reason: "test-output-drained"
        ))

        let closeGestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: closeGestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertTrue(harness.filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode,
            type: .keyDown
        ))
        XCTAssertTrue(harness.filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode,
            type: .keyUp
        ))
        waitForCoordinatorTiming(0.13)
        XCTAssertTrue(harness.press.keyUp())

        XCTAssertTrue(harness.press.persistentModeArmedForTesting)
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, oldSegmentOwner)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        XCTAssertTrue(harness.press.hasPendingPersistentToggleForTesting)
        XCTAssertTrue(
            harness.press.hasActiveVoiceOwnershipForTriggerReconfiguration,
            "a classified short toggle waiting for its gate owner must remain active voice ownership"
        )
        XCTAssertTrue(harness.press.hasReleaseOrTailOwnershipForReconfiguration)
        XCTAssertFalse(harness.press.configurePersistentSessionTriggerKey(.leftOption))
        XCTAssertFalse(harness.press.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertEqual(harness.press.currentStateForTesting, .idle)
        XCTAssertTrue(harness.recorder.values.isEmpty)

        XCTAssertTrue(harness.filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: oldSegmentOwner
        ))
        waitForCoordinatorTiming(0.08)

        XCTAssertFalse(harness.press.persistentModeArmedForTesting)
        XCTAssertFalse(harness.press.hasPendingPersistentToggleForTesting)
        XCTAssertNotNil(harness.filter.suppressedHardwareTriggerSessionID)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        XCTAssertTrue(harness.filter.hasActiveHardwareTriggerOwnership)
        XCTAssertFalse(harness.filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: oldSegmentOwner
        ))
        harness.press.suppressedHardwareGateDidClose(ownerID: oldSegmentOwner)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        stop(harness)
    }

    func testStopCancelsDeferredCloseBeforeLateGateCompletion() {
        let (harness, oldOwner) = prepareDeferredPersistentClose()
        let edgesBeforeStop = harness.recorder.values
        XCTAssertTrue(harness.press.hasPendingPersistentToggleForTesting)

        harness.press.stop()

        XCTAssertFalse(harness.press.hasPendingPersistentToggleForTesting)
        XCTAssertNil(harness.trigger.activeSessionID)
        let modeAfterStop = harness.press.currentSessionModeForTesting
        XCTAssertTrue(harness.filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: oldOwner
        ))
        waitForCoordinatorTiming(0.08)

        XCTAssertEqual(modeAfterStop, .idle)
        XCTAssertEqual(harness.press.currentSessionModeForTesting, modeAfterStop)
        XCTAssertEqual(harness.recorder.values.map(\.1), edgesBeforeStop.map(\.1))
        stop(harness)
    }

    func testSuppressionInvalidationCancelsDeferredCloseWithoutStateCommit() {
        let (harness, oldOwner) = prepareDeferredPersistentClose()
        let edgesBeforeInvalidation = harness.recorder.values
        XCTAssertTrue(harness.press.hasPendingPersistentToggleForTesting)

        XCTAssertTrue(harness.filter.resetSuppressedHardwareTrigger(
            gestureID: oldOwner,
            reason: "device-removed"
        ))

        XCTAssertFalse(harness.press.hasPendingPersistentToggleForTesting)
        XCTAssertTrue(harness.press.persistentModeArmedForTesting)
        XCTAssertNil(harness.trigger.activeSessionID)
        harness.press.suppressedHardwareGateDidClose(ownerID: oldOwner)
        XCTAssertEqual(harness.recorder.values.map(\.1), edgesBeforeInvalidation.map(\.1))
        stop(harness)
    }

    func testDeviceRemovalCancelsDeferredCloseBeforeLateQuietCompletion() {
        let (harness, oldOwner) = prepareDeferredPersistentClose()
        let edgesBeforeRemoval = harness.recorder.values
        XCTAssertTrue(harness.press.hasPendingPersistentToggleForTesting)

        harness.press.handleTransportLoss(deviceRemoved: true)

        XCTAssertFalse(harness.press.hasPendingPersistentToggleForTesting)
        XCTAssertTrue(harness.press.persistentModeArmedForTesting)
        XCTAssertNil(harness.filter.suppressedHardwareTriggerSessionID)
        XCTAssertFalse(harness.filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: oldOwner
        ))
        harness.press.suppressedHardwareGateDidClose(ownerID: oldOwner)
        XCTAssertEqual(harness.recorder.values.map(\.1), edgesBeforeRemoval.map(\.1))
        stop(harness)
    }

    private func prepareDeferredPersistentClose() -> (Harness, UUID) {
        let harness = makeHarness(key: .rightOption)
        let openGestureID = shortTap(harness, usesHardwareOption: false)
        XCTAssertTrue(harness.press.persistentModeArmedForTesting)
        XCTAssertTrue(harness.press.configurePersistentSessionTriggerKey(.leftControl))
        XCTAssertTrue(harness.filter.resetSuppressedHardwareTrigger(
            gestureID: openGestureID,
            reason: "test-prepare-audio-suppression"
        ))
        waitForCoordinatorTiming(0.20)

        let oldOwner = UUID()
        harness.filter.beginOptionDeferral(gestureID: oldOwner)
        guard let mappedDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: VoiceTriggerKey.rightOption.cgKeyCode,
            keyDown: true
        ) else {
            XCTFail("could not create mapped trigger-down event")
            return (harness, oldOwner)
        }
        XCTAssertTrue(harness.filter.captureDeferredHardwareOptionEdge(
            .down,
            copiedEvent: mappedDown
        ))
        XCTAssertTrue(harness.filter.suppressDeferredHardwareTrigger(
            gestureID: oldOwner,
            reason: "test-audio-only-hold"
        ))
        XCTAssertTrue(harness.filter.armSuppressedHardwareTriggerRelease(gestureID: oldOwner))
        XCTAssertTrue(harness.filter.completeSuppressedHardwareTrigger(
            gestureID: oldOwner,
            reason: "test-output-drained"
        ))

        XCTAssertTrue(harness.press.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertTrue(harness.filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode,
            type: .keyDown
        ))
        XCTAssertTrue(harness.filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode,
            type: .keyUp
        ))
        waitForCoordinatorTiming(0.13)
        XCTAssertTrue(harness.press.keyUp())
        XCTAssertTrue(harness.press.hasPendingPersistentToggleForTesting)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        return (harness, oldOwner)
    }

    private func makeHarness(key: VoiceTriggerKey) -> Harness {
        let recorder = EventRecorder()
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            recorder.values.append((key, isDown))
        })
        XCTAssertTrue(trigger.configureVoiceTriggerKey(key))
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        XCTAssertTrue(filter.configureVoiceTriggerKey(key))
        let press = VoicePressCoordinator(optionTrigger: trigger)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(key))
        press.onHardwareOptionGateBegin = { filter.beginOptionDeferral(gestureID: $0) }
        press.onHardwareOptionGateShortReplay = { gestureID in
            filter.releaseDeferredOption(gestureID: gestureID, reason: "short-tap-test")
        }
        press.onPersistentModeToggle = { gestureID in
            filter.suppressPersistentModeToggle(
                gestureID: gestureID,
                reason: "persistent-short-tap-test",
            )
        }
        press.onDeferredPersistentModeToggle = { gestureID in
            filter.suppressDeferredPersistentModeToggle(gestureID: gestureID)
        }
        press.onHardwareOptionGateCancel = {
            filter.cancelDeferredOption(gestureID: $0, reason: "short-tap-test-cleanup")
        }
        press.onHardwareOptionGateResetSuppression = { ownerID in
            _ = filter.resetSuppressedHardwareTrigger(
                gestureID: ownerID,
                reason: "short-tap-test-device-removal"
            )
        }
        filter.onSuppressedHardwareTriggerSafelyClosed = { [weak press] ownerID in
            press?.suppressedHardwareGateDidClose(ownerID: ownerID)
        }
        filter.onSuppressedHardwareTriggerInvalidated = { [weak press] ownerID, reason in
            press?.suppressedHardwareGateWasInvalidated(ownerID: ownerID, reason: reason)
        }
        return Harness(recorder: recorder, trigger: trigger, filter: filter, press: press)
    }

    @discardableResult
    private func shortTap(
        _ harness: Harness,
        usesHardwareOption: Bool
    ) -> UUID {
        let gestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: usesHardwareOption
        ))
        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.08)
        return gestureID
    }

    private func suppresses(
        _ filter: VoiceKeyFilter,
        key: VoiceTriggerKey,
        type: CGEventType,
        flags: CGEventFlags? = nil
    ) -> Bool {
        filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: key.cgKeyCode,
            type: type,
            eventFlags: flags
        )
    }

    private func stop(_ harness: Harness) {
        if let owner = harness.filter.suppressedHardwareTriggerSessionID {
            _ = harness.filter.resetSuppressedHardwareTrigger(
                gestureID: owner,
                reason: "short-tap-test-cleanup"
            )
        }
        harness.press.stop()
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}
