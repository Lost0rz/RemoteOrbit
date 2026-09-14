import XCTest
@testable import RemoteOrbit

final class BLEBridgeTests: XCTestCase {
    func testLateAudioStartDuringDrainIsIgnoredAndPreservesDrainInputs() {
        let decision = BLEBridge.audioStartDisposition(
            drainPending: true,
            currentStreamID: 84,
            incomingStreamID: 85,
            pendingAudioStopReason: 0x02
        )

        XCTAssertEqual(
            decision,
            .ignoredDuringDrain(
                currentStreamID: 84,
                incomingStreamID: 85,
                pendingAudioStopReason: 0x02
            )
        )
    }

    func testAudioStartAfterDrainIsAccepted() {
        let decision = BLEBridge.audioStartDisposition(
            drainPending: false,
            currentStreamID: 84,
            incomingStreamID: 85,
            pendingAudioStopReason: 0x02
        )

        XCTAssertEqual(decision, .accepted)
    }

    func testDrainGuardDoesNotDependOnVoiceInputRequested() {
        let decision = BLEBridge.audioStartDisposition(
            drainPending: true,
            currentStreamID: 84,
            incomingStreamID: 85,
            pendingAudioStopReason: nil
        )

        XCTAssertEqual(
            decision,
            .ignoredDuringDrain(
                currentStreamID: 84,
                incomingStreamID: 85,
                pendingAudioStopReason: nil
            )
        )
    }
}
