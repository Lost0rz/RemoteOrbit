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

    private func beginAudioSegment(_ harness: Harness) {
        let segmentID = UUID()
        XCTAssertTrue(harness.press.keyDown(
            sessionID: segmentID,
            togglesPersistentVoiceSession: true
        ))
        waitForCoordinatorTiming(0.35)
        harness.press.setRemoteAudioAvailable()
        XCTAssertTrue(harness.press.keyUp())
        harness.press.invokeTailCompletionForTesting(sessionID: segmentID)
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}
