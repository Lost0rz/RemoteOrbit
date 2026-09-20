import XCTest
@testable import RemoteOrbit

final class BLEBridgeTests: XCTestCase {
    func testPendingPreparationKeepsTransportAndVoiceIntentSeparate() {
        var state = BLEVoiceTransportState()

        state.requestPendingPreCapture()

        XCTAssertTrue(state.pendingPreCaptureRequested)
        XCTAssertFalse(state.voiceInputRequested)
        XCTAssertFalse(state.isStarted)

        state.prepareTransport()

        XCTAssertTrue(state.isStarted)
        XCTAssertTrue(state.isPreparing)
    }

    func testPendingPreparationNeverRequestsMicOpenAfterCapabilities() {
        var state = BLEVoiceTransportState()

        state.requestPendingPreCapture()
        state.prepareTransport()
        state.atvvReady = true

        XCTAssertFalse(state.voiceInputRequested)
        XCTAssertFalse(state.shouldRequestMicOpen)
    }

    func testStartSearchDuringPreparationCannotRequestMicOpen() {
        var state = BLEVoiceTransportState()

        state.requestPendingPreCapture()
        state.prepareTransport()
        state.atvvReady = true

        XCTAssertFalse(state.shouldRequestMicOpen)
    }

    func testPromotingPreparedTransportRequestsMicOpenOnlyAfterActivation() {
        var state = BLEVoiceTransportState()

        state.requestPendingPreCapture()
        state.prepareTransport()
        state.atvvReady = true
        XCTAssertFalse(state.shouldRequestMicOpen)

        state.requestVoiceInput()

        XCTAssertTrue(state.voiceInputRequested)
        XCTAssertFalse(state.pendingPreCaptureRequested)
        XCTAssertTrue(state.shouldRequestMicOpen)
    }

    func testCancellingPendingPreparationRemovesAllVoiceRequests() {
        var state = BLEVoiceTransportState()

        state.requestPendingPreCapture()
        state.prepareTransport()
        state.atvvReady = true

        state.cancelTransportPreparation()

        XCTAssertFalse(state.pendingPreCaptureRequested)
        XCTAssertFalse(state.voiceInputRequested)
        XCTAssertFalse(state.shouldRequestMicOpen)
    }

    func testTransportPrewarmDoesNotRequestVoiceOrMicOpen() {
        var state = BLEVoiceTransportState()

        state.prepareTransport()

        XCTAssertTrue(state.isStarted)
        XCTAssertFalse(state.voiceInputRequested)
        XCTAssertFalse(state.shouldRequestMicOpen)
    }

    func testVoiceActivationRequestsMicAfterAStartedPrewarm() {
        var state = BLEVoiceTransportState()

        state.prepareTransport()
        state.requestVoiceInput()
        state.atvvReady = true

        XCTAssertTrue(state.isStarted)
        XCTAssertTrue(state.voiceInputRequested)
        XCTAssertTrue(state.shouldRequestMicOpen)
    }

    func testVoiceActivationRetriesAfterPrewarmLostItsPeripheral() {
        var state = BLEVoiceTransportState()

        state.prepareTransport()
        state.requestVoiceInput()

        XCTAssertTrue(
            state.shouldRetryConnection(
                peripheralState: nil,
                isScanning: false,
                hasReconnectWork: false
            )
        )
    }

    func testRepeatedVoiceActivationKeepsOnePendingMicOpenRequest() {
        var state = BLEVoiceTransportState()

        state.prepareTransport()
        state.requestVoiceInput()
        state.atvvReady = true

        state.requestVoiceInput()

        XCTAssertTrue(state.shouldRequestMicOpen)

        state.micOpenRequested = true
        state.requestVoiceInput()
        XCTAssertFalse(state.shouldRequestMicOpen)
    }

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
