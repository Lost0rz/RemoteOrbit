import XCTest
@testable import RemoteOrbit

final class HIDButtonDownPolicyTests: XCTestCase {
    func testLegacyMicrophoneAndSingleShotButtonsKeepTheDebounceFence() {
        let legacyMicrophonePolicy = HIDButtonDownPolicy.resolve(
            button: .microphone,
            shouldRepeat: false,
            usesAdvancedGestures: false
        )
        XCTAssertTrue(legacyMicrophonePolicy.shouldDebounce)

        let singleShotPolicy = HIDButtonDownPolicy.resolve(
            button: .home,
            shouldRepeat: false,
            usesAdvancedGestures: false
        )
        XCTAssertTrue(singleShotPolicy.shouldDebounce)

        for (button, policy) in [
            (RemoteButton.microphone, legacyMicrophonePolicy),
            (.home, singleShotPolicy),
        ] {
            var debouncer = ButtonEdgeDebouncer()
            XCTAssertTrue(
                debouncer.shouldEmit(
                    button: button,
                    isDown: true,
                    at: 200.0,
                    debouncing: policy.shouldDebounce
                )
            )
            XCTAssertTrue(
                debouncer.shouldEmit(
                    button: button,
                    isDown: false,
                    at: 200.05,
                    debouncing: policy.shouldDebounce
                )
            )
            XCTAssertFalse(
                debouncer.shouldEmit(
                    button: button,
                    isDown: true,
                    at: 200.159810,
                    debouncing: policy.shouldDebounce
                )
            )
        }
    }

    func testLivePhysicalCandidateBypassesOnlyMicrophoneDebounce() {
        let microphone = HIDButtonDownPolicy.resolve(
            button: .microphone,
            shouldRepeat: false,
            usesAdvancedGestures: false,
            hasLivePhysicalCandidate: true
        )
        XCTAssertFalse(microphone.shouldDebounce)

        let home = HIDButtonDownPolicy.resolve(
            button: .home,
            shouldRepeat: false,
            usesAdvancedGestures: false,
            hasLivePhysicalCandidate: true
        )
        XCTAssertTrue(home.shouldDebounce)
    }

    func testNoLivePhysicalCandidatePreservesMicrophoneDebounce() {
        let policy = HIDButtonDownPolicy.resolve(
            button: .microphone,
            shouldRepeat: false,
            usesAdvancedGestures: false,
            hasLivePhysicalCandidate: false
        )
        XCTAssertTrue(policy.shouldDebounce)
    }

    func testRepeatableAndAdvancedGenericButtonsKeepTheirExistingBypass() {
        let repeatablePolicy = HIDButtonDownPolicy.resolve(
            button: .down,
            shouldRepeat: true,
            usesAdvancedGestures: false
        )
        XCTAssertFalse(repeatablePolicy.shouldDebounce)
        XCTAssertTrue(repeatablePolicy.shouldRepeat)

        let advancedPolicy = HIDButtonDownPolicy.resolve(
            button: .home,
            shouldRepeat: false,
            usesAdvancedGestures: true
        )
        XCTAssertFalse(advancedPolicy.shouldDebounce)
        XCTAssertFalse(advancedPolicy.shouldRepeat)
        XCTAssertEqual(ButtonEdgeDebouncer.defaultInterval, 0.18)
    }
}
