import XCTest
@testable import RemoteOrbit

final class ButtonGestureRecognizerTests: XCTestCase {
    private func context(
        profile: ButtonGestureProfile
    ) -> ButtonGestureContext {
        ButtonGestureContext(
            baseBinding: .preset(.returnKey),
            profile: profile,
            targetApplicationBundleIdentifier: "com.example.test"
        )
    }

    func testSingleTapIsEmittedImmediatelyWhenNoDoubleTapIsConfigured() {
        let recognizer = ButtonGestureRecognizer()
        let expectation = expectation(description: "single tap")
        var received: [ButtonGestureEventKind] = []
        recognizer.onEvent = { event in
            received.append(event.kind)
            expectation.fulfill()
        }

        let profile = ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.copy),
            longPressBehavior: .triggerOnce
        )
        recognizer.handleDown(button: .ok, context: context(profile: profile), at: 10.0)
        recognizer.handleUp(button: .ok, at: 10.1)

        wait(for: [expectation], timeout: 0.2)
        XCTAssertEqual(received, [.singleTap])
    }

    func testDoubleTapReplacesThePendingSingleTap() {
        let recognizer = ButtonGestureRecognizer()
        let expectation = expectation(description: "double tap")
        var received: [ButtonGestureEventKind] = []
        recognizer.onEvent = { event in
            received.append(event.kind)
            expectation.fulfill()
        }

        let profile = ButtonGestureProfile(
            isEnabled: true,
            doubleTap: .preset(.copy)
        )
        let context = context(profile: profile)
        recognizer.handleDown(button: .ok, context: context, at: 10.0)
        recognizer.handleUp(button: .ok, at: 10.05)
        recognizer.handleDown(button: .ok, context: context, at: 10.15)
        recognizer.handleUp(button: .ok, at: 10.20)

        wait(for: [expectation], timeout: 0.2)
        XCTAssertEqual(received, [.doubleTap])
    }

    func testLongPressFiresOnceAndDoesNotAlsoEmitSingleTap() {
        let recognizer = ButtonGestureRecognizer()
        let expectation = expectation(description: "long press")
        var received: [ButtonGestureEventKind] = []
        recognizer.onEvent = { event in
            received.append(event.kind)
            expectation.fulfill()
        }

        let profile = ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.paste),
            longPressBehavior: .triggerOnce
        )
        recognizer.handleDown(button: .ok, context: context(profile: profile), at: 10.0)

        wait(for: [expectation], timeout: 0.6)
        recognizer.handleUp(button: .ok, at: 10.5)

        XCTAssertEqual(received, [.longPress])
    }

    func testLongPressFallsBackToReleaseWhenItsTimerWasDelayed() {
        let recognizer = ButtonGestureRecognizer()
        var received: [ButtonGestureEventKind] = []
        recognizer.onEvent = { received.append($0.kind) }

        let profile = ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.reloadPage),
            longPressBehavior: .triggerOnce
        )
        recognizer.handleDown(
            button: .menu,
            context: context(profile: profile),
            at: 10.0
        )
        // Do not wait for the scheduled timer. This simulates a main-run-loop
        // delay and verifies that release classification still prefers long.
        recognizer.handleUp(button: .menu, at: 10.5)

        XCTAssertEqual(received, [.longPress])
    }

    func testRepeatStopsAfterRelease() {
        let recognizer = ButtonGestureRecognizer()
        let repeatExpectation = expectation(description: "repeat steps")
        repeatExpectation.expectedFulfillmentCount = 2
        var receivedCount = 0
        recognizer.onEvent = { event in
            guard event.kind == .repeatStep else { return }
            receivedCount += 1
            repeatExpectation.fulfill()
        }

        let profile = ButtonGestureProfile(
            isEnabled: true,
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld
        )
        recognizer.handleDown(button: .back, context: context(profile: profile), at: 10.0)

        wait(for: [repeatExpectation], timeout: 0.7)
        recognizer.handleUp(button: .back, at: 10.5)
        let countAtRelease = receivedCount
        let quiet = expectation(description: "no repeat after release")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            quiet.fulfill()
        }
        wait(for: [quiet], timeout: 0.4)

        XCTAssertEqual(receivedCount, countAtRelease)
        XCTAssertGreaterThanOrEqual(receivedCount, 2)
    }

    func testOldTemplateDataWithoutGestureProfilesStillDecodes() throws {
        let template = AppMappingTemplate(
            appBundleIdentifier: "com.example.test",
            appName: "Test",
            templateName: "Default",
            bindings: [.ok: .preset(.returnKey)]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(template)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "gestureProfiles")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            AppMappingTemplate.self,
            from: oldData
        )
        XCTAssertNil(decoded.gestureProfiles)
    }

    func testCommandRLongPressProfileIsRecognizedAsAdvancedGesture() {
        let profile = ButtonGestureProfile(
            isEnabled: true,
            longPress: .shortcut(
                KeyChord(
                    keyCode: 15,
                    keyLabel: "R",
                    modifiers: .command
                ),
                trigger: .single
            ),
            longPressBehavior: .triggerOnce
        )

        XCTAssertTrue(profile.usesAdvancedGestures)
        XCTAssertEqual(profile.longPress?.displayName, "⌘R")
    }

    func testFloatTabsBrowsePresetExposesSemanticReload() throws {
        let preset = try XCTUnwrap(
            AppTemplatePresetLibrary.preset(id: "floatTabs.browse")
        )

        XCTAssertEqual(
            preset.bindings[.menu],
            .preset(.reloadPage)
        )
        XCTAssertTrue(
            AppTemplatePresetLibrary
                .categories(for: "com.lost0rz.FloatTabs")
                .contains(.navigation)
        )
    }
}
