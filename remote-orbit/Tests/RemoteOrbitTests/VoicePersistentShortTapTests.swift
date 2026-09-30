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

    func testNoOptionEdgeShortOpenEmitsOneConfiguredSyntheticTap() {
        let harness = makeHarness(key: .rightOption)

        let gestureID = shortTap(harness, usesHardwareOption: true)

        XCTAssertTrue(harness.press.persistentSessionActiveForTesting)
        XCTAssertEqual(harness.recorder.values.map(\.0), [.rightOption, .rightOption])
        XCTAssertEqual(harness.recorder.values.map(\.1), [true, false])
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, gestureID)
        stop(harness)
    }

    func testNoOptionEdgeShortCloseEmitsOneAdditionalConfiguredTap() {
        let harness = makeHarness(key: .leftControl)
        _ = shortTap(harness, usesHardwareOption: false)
        XCTAssertTrue(harness.press.persistentSessionActiveForTesting)
        waitForCoordinatorTiming(0.20)

        _ = shortTap(harness, usesHardwareOption: true)

        XCTAssertFalse(harness.press.persistentSessionActiveForTesting)
        XCTAssertEqual(
            harness.recorder.values.map(\.0),
            [.leftControl, .leftControl, .leftControl, .leftControl]
        )
        XCTAssertEqual(harness.recorder.values.map(\.1), [true, false, true, false])
        stop(harness)
    }

    func testCapturedPhysicalMappedPairIsDiscardedInFavorOfSyntheticTap() {
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

        XCTAssertEqual(harness.recorder.values.map(\.0), [.rightOption, .rightOption])
        XCTAssertEqual(harness.recorder.values.map(\.1), [true, false])
        XCTAssertEqual(harness.filter.suppressedHardwareTriggerSessionID, gestureID)
        stop(harness)
    }

    func testLateMappedEdgesAfterShortResolutionAreSuppressed() {
        let harness = makeHarness(key: .rightCommand)
        _ = shortTap(harness, usesHardwareOption: true)
        let edgeCountAfterSemanticTap = harness.recorder.values.count
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
        XCTAssertEqual(harness.recorder.values.count, edgeCountAfterSemanticTap)
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

    func testAllConfiguredKeysProduceOneTapAndDiscardLateMappedEdges() {
        for key in VoiceTriggerKey.allCases {
            let harness = makeHarness(key: key)
            _ = shortTap(harness, usesHardwareOption: true)

            XCTAssertEqual(harness.recorder.values.map(\.0), [key, key], "key=\(key)")
            XCTAssertEqual(harness.recorder.values.map(\.1), [true, false], "key=\(key)")
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

    func testFailedShortOpenDoesNotCommitPersistentSession() {
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

        XCTAssertFalse(harness.press.persistentSessionActiveForTesting)
        XCTAssertTrue(harness.recorder.values.isEmpty)
        XCTAssertNil(harness.trigger.activeSessionID)
        stop(harness)
    }

    func testFailedShortCloseLeavesPersistentSessionOpen() {
        let harness = makeHarness(key: .leftCommand)
        _ = shortTap(harness, usesHardwareOption: false)
        XCTAssertTrue(harness.press.persistentSessionActiveForTesting)
        waitForCoordinatorTiming(0.20)

        let gestureID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: gestureID,
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        _ = harness.trigger.abort(sessionID: gestureID)

        XCTAssertTrue(harness.press.keyUp())
        waitForCoordinatorTiming(0.08)

        XCTAssertTrue(harness.press.persistentSessionActiveForTesting)
        stop(harness)
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
        press.onHardwareOptionGateBegin = { filter.beginOptionDeferral(gestureID: $0) }
        press.onHardwareOptionGateShortReplay = { gestureID in
            filter.releaseDeferredOption(gestureID: gestureID, reason: "short-tap-test")
        }
        press.onPersistentSessionTriggerTap = { gestureID in
            filter.emitPersistentShortTap(
                gestureID: gestureID,
                reason: "persistent-short-tap-test"
            )
        }
        press.onHardwareOptionGateCancel = {
            filter.cancelDeferredOption(gestureID: $0, reason: "short-tap-test-cleanup")
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
