import XCTest
@testable import RemoteOrbit

final class DisabledShortClassifierTests: XCTestCase {
    func testDisabledShortBindingBypassesClassifier() {
        XCTAssertTrue(
            AppController.bypassesShortClassification(
                for: .preset(.disabled)
            )
        )
    }

    func testDisabledKeyDownImmediatelyEntersHoldingAndPreparesRemoteRoute() {
        var events: [String] = []
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        press.onStateChanged = { state in
            if state == .holding {
                events.append("HOLD_CONFIRMED")
            }
        }
        press.onRemoteRoutePreparation = {
            events.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: AppController
                    .bypassesShortClassification(for: .preset(.disabled)),
                preparesRemoteTransport: true
            )
        )

        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertEqual(events, ["HOLD_CONFIRMED", "REMOTE_ROUTE_PREPARATION"])
        press.stop()
    }

    func testDisabledQuickReleaseDoesNotExecuteShortAction() {
        var shortActionCalled = false
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                onShortTap: { shortActionCalled = true },
                bypassesShortClassification: AppController
                    .bypassesShortClassification(for: .preset(.disabled))
            )
        )
        XCTAssertTrue(press.keyUp())

        XCTAssertFalse(shortActionCalled)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        press.stop()
    }

    func testVoiceKeyDefaultRemainsPendingForShortLongClassification() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertFalse(
            AppController.bypassesShortClassification(for: .voiceKeyDefault)
        )
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: AppController
                    .bypassesShortClassification(for: .voiceKeyDefault)
            )
        )

        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertTrue(press.keyUp())
        press.stop()
    }
}
