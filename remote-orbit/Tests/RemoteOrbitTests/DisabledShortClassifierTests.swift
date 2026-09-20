import XCTest
@testable import RemoteOrbit

final class DisabledShortClassifierTests: XCTestCase {
    func testDisabledShortBindingDoesNotBypassClassifier() {
        XCTAssertFalse(
            AppController.bypassesShortClassification(
                for: .preset(.disabled)
            )
        )
    }

    func testDisabledShortReleaseStaysInsideClassifier() {
        var states: [VoicePressCoordinator.State] = []
        var shortActionCalled = false
        var gateShortResult: (UUID, Bool)?
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in
            XCTFail("disabled short press must not emit a synthetic Option event")
        })
        let sessionID = UUID()
        press.onStateChanged = { states.append($0) }
        press.onHardwareOptionGateShortResult = { gateShortResult = ($0, $1) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionID,
                onShortTap: { shortActionCalled = true },
                bypassesShortClassification: AppController
                    .bypassesShortClassification(for: .preset(.disabled)),
                usesHardwareOption: true
            )
        )
        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertTrue(press.keyUp())

        XCTAssertEqual(states, [.pending, .idle])
        XCTAssertTrue(shortActionCalled)
        XCTAssertEqual(gateShortResult?.0, sessionID)
        XCTAssertEqual(gateShortResult?.1, false)
        XCTAssertFalse(press.hasPendingTailForTesting)
        press.stop()
    }

    func testDisabledLongStillEntersHoldingAfterClassifierThreshold() {
        var holdingCount = 0
        var routePreparationCount = 0
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        press.onStateChanged = { state in
            if state == .holding {
                holdingCount += 1
            }
        }
        press.onRemoteRoutePreparation = {
            routePreparationCount += 1
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                onShortTap: {},
                bypassesShortClassification: AppController
                    .bypassesShortClassification(for: .preset(.disabled))
            )
        )
        waitForClassifierTiming(0.35)

        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertEqual(holdingCount, 1)
        XCTAssertEqual(routePreparationCount, 1)
        press.stop()
    }

    private func waitForClassifierTiming(_ interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }
}
