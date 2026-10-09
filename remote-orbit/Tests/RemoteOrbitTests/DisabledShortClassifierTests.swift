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

    func testDisabledQuickReleaseIsDroppedWithoutActivatingRemoteRoute() {
        var gateBeginCount = 0
        var gateCancelCount = 0
        var gateShortReplayCount = 0
        var transportPreparationCount = 0
        var holdCount = 0
        var remoteRouteCount = 0
        var syntheticEdges: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { syntheticEdges.append($0) }
        )
        press.onHardwareOptionGateBegin = { _ in gateBeginCount += 1 }
        press.onHardwareOptionGateCancel = { _ in gateCancelCount += 1 }
        press.onHardwareOptionGateShortReplay = { _ in gateShortReplayCount += 1 }
        press.onStateChanged = { state in
            if state == .holding {
                holdCount += 1
            }
        }
        press.onRemoteTransportPreparation = {
            transportPreparationCount += 1
        }
        press.onRemoteRoutePreparation = {
            remoteRouteCount += 1
        }

        let disabledBinding: ButtonBinding = .preset(.disabled)
        let bypassesShortClassification = AppController
            .bypassesShortClassification(for: disabledBinding)
        XCTAssertFalse(bypassesShortClassification)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                onShortTap: {
                    // Production's Disabled handler is a non-nil log-only no-op.
                },
                bypassesShortClassification: bypassesShortClassification,
                usesHardwareOption: true,
                preparesRemoteTransport: true
            )
        )

        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertEqual(gateBeginCount, 1)
        XCTAssertEqual(transportPreparationCount, 1)
        XCTAssertEqual(holdCount, 0)
        XCTAssertEqual(remoteRouteCount, 0)

        XCTAssertTrue(press.keyUp())

        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertEqual(gateCancelCount, 1)
        XCTAssertEqual(gateShortReplayCount, 0)
        XCTAssertEqual(holdCount, 0)
        XCTAssertEqual(remoteRouteCount, 0)
        XCTAssertTrue(syntheticEdges.isEmpty)
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

    func testDisabledTrueLongEntersHoldingOnlyAfterExistingThreshold() {
        var events: [String] = []
        var syntheticEdges: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { syntheticEdges.append($0) }
        )
        press.onStateChanged = { state in
            if state == .holding {
                events.append("HOLD_CONFIRMED")
            }
        }
        press.onRemoteTransportPreparation = {
            events.append("TRANSPORT_PREPARATION")
        }
        press.onRemoteRoutePreparation = {
            events.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertEqual(
            VoicePressCoordinator.holdActivationThreshold,
            0.30,
            accuracy: 0.001
        )
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: AppController
                    .bypassesShortClassification(for: .preset(.disabled)),
                preparesRemoteTransport: true
            )
        )
        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertEqual(events, ["TRANSPORT_PREPARATION"])

        waitForCoordinatorTiming(
            VoicePressCoordinator.holdActivationThreshold + 0.05
        )

        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertEqual(
            events,
            ["TRANSPORT_PREPARATION", "HOLD_CONFIRMED", "REMOTE_ROUTE_PREPARATION"]
        )
        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(events.filter { $0 == "HOLD_CONFIRMED" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "REMOTE_ROUTE_PREPARATION" }.count, 1)
        XCTAssertTrue(syntheticEdges.isEmpty)
        press.stop()
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }
}
