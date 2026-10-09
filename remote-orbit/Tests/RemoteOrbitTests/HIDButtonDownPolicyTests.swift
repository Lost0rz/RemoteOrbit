import XCTest
@testable import RemoteOrbit

final class HIDButtonDownPolicyTests: XCTestCase {
    func testActiveDualReceiverMicrophoneAcceptsSecondDownAtObservedGap() {
        let mode = DualReceiverVoiceMode.active(
            receiverA: .leftOption,
            receiverB: .rightOption
        )
        guard case .active = mode else {
            return XCTFail("fixture must exercise active dual-receiver mode")
        }

        let policy = HIDButtonDownPolicy.resolve(
            button: .microphone,
            shouldRepeat: false,
            usesAdvancedGestures: false,
            dualReceiverVoiceMode: mode
        )
        XCTAssertFalse(
            policy.shouldDebounce,
            "active dual-receiver microphone edges must reach the multi-edge recognizer"
        )

        var now: TimeInterval = 100.0
        let recognizer = DualReceiverVoiceGestureRecognizer(
            monotonicNow: { now },
            schedule: { _, _ in { } }
        )
        var events: [DualReceiverVoiceGestureRecognizer.Event] = []
        recognizer.onEvent = { events.append($0) }
        var debouncer = ButtonEdgeDebouncer()
        let firstDownEmitted = debouncer.shouldEmit(
            button: .microphone,
            isDown: true,
            at: now,
            debouncing: policy.shouldDebounce
        )
        XCTAssertTrue(firstDownEmitted)
        guard let gestureID = recognizer.handleDown(at: now) else {
            return XCTFail("first microphone down must start a dual-receiver gesture")
        }

        now = 100.05
        let firstUpEmitted = debouncer.shouldEmit(
            button: .microphone,
            isDown: false,
            at: now,
            debouncing: policy.shouldDebounce
        )
        XCTAssertTrue(firstUpEmitted)
        XCTAssertEqual(recognizer.handleUp(at: now), gestureID)

        now = 100.159810
        let secondDownEmitted = debouncer.shouldEmit(
            button: .microphone,
            isDown: true,
            at: now,
            debouncing: policy.shouldDebounce
        )
        XCTAssertTrue(
            secondDownEmitted,
            "the second DOWN 109.810 ms after UP must not be swallowed"
        )
        XCTAssertEqual(recognizer.handleDown(at: now), gestureID)
        XCTAssertEqual(recognizer.stateForTesting, .secondPressPending)

        now = 100.509810
        XCTAssertEqual(recognizer.handleUp(at: now), gestureID)
        XCTAssertEqual(
            events,
            [
                .awaitingSecondPress(gestureID: gestureID, firstUpAt: 100.05),
                .classified(gestureID: gestureID, receiver: .b),
            ]
        )
    }

    func testLegacyMicrophoneAndSingleShotButtonsKeepTheDebounceFence() {
        let legacyMicrophonePolicy = HIDButtonDownPolicy.resolve(
            button: .microphone,
            shouldRepeat: false,
            usesAdvancedGestures: false,
            dualReceiverVoiceMode: .legacy
        )
        XCTAssertTrue(legacyMicrophonePolicy.shouldDebounce)

        let unavailableDualModeMicrophonePolicy = HIDButtonDownPolicy.resolve(
            button: .microphone,
            shouldRepeat: false,
            usesAdvancedGestures: false,
            dualReceiverVoiceMode: .unavailable(.rawHIDUnavailable)
        )
        XCTAssertTrue(unavailableDualModeMicrophonePolicy.shouldDebounce)

        let singleShotPolicy = HIDButtonDownPolicy.resolve(
            button: .home,
            shouldRepeat: false,
            usesAdvancedGestures: false,
            dualReceiverVoiceMode: .active(
                receiverA: .leftOption,
                receiverB: .rightOption
            )
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

    func testRepeatableAndAdvancedGenericButtonsKeepTheirExistingBypass() {
        let repeatablePolicy = HIDButtonDownPolicy.resolve(
            button: .down,
            shouldRepeat: true,
            usesAdvancedGestures: false,
            dualReceiverVoiceMode: .legacy
        )
        XCTAssertFalse(repeatablePolicy.shouldDebounce)
        XCTAssertTrue(repeatablePolicy.shouldRepeat)

        let advancedPolicy = HIDButtonDownPolicy.resolve(
            button: .home,
            shouldRepeat: false,
            usesAdvancedGestures: true,
            dualReceiverVoiceMode: .legacy
        )
        XCTAssertFalse(advancedPolicy.shouldDebounce)
        XCTAssertFalse(advancedPolicy.shouldRepeat)
        XCTAssertEqual(ButtonEdgeDebouncer.defaultInterval, 0.18)
    }
}
