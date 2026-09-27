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
}
