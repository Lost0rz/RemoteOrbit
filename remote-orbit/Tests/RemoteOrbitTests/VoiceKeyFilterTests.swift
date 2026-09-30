import CoreGraphics
import XCTest
@testable import RemoteOrbit

final class VoiceKeyFilterTests: XCTestCase {
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

    private func waitForFilterTiming(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}
