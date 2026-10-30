import XCTest
@testable import RemoteOrbit

final class BLEBridgeTests: XCTestCase {
    private final class AdmissionProbe {
        var transportPreparations = 0
        var admissionNotifications = 0
        var optionEdges: [Bool] = []
    }

    private final class AdmissionHarness {
        let bridge: BLEBridge
        let press: VoicePressCoordinator
        let probe: AdmissionProbe

        init() {
            let probe = AdmissionProbe()
            let bridge = BLEBridge()
            let press = VoicePressCoordinator(
                optionTrigger: VoiceOptionTrigger { probe.optionEdges.append($0) }
            )
            self.probe = probe
            self.bridge = bridge
            self.press = press

            press.onRemoteTransportPreparation = {
                probe.transportPreparations += 1
            }
            press.isVoiceSessionAdmissionBlocked = { [weak bridge] in
                bridge?.isVoiceSessionAdmissionBlocked ?? false
            }
            bridge.onVoiceSessionAdmissionAvailable = { [weak press] in
                probe.admissionNotifications += 1
                press?.voiceSessionAdmissionBecameAvailable()
            }
            bridge.onStreamingChanged = { [weak press] streaming, _ in
                press?.setRemoteStreaming(streaming)
            }
            bridge.onConnectionChanged = { [weak press] connected in
                if !connected {
                    press?.handleTransportLoss()
                }
            }
        }

        func deferNextPress() -> UUID {
            XCTAssertTrue(
                press.keyDown(
                    sessionID: UUID(),
                    bypassesShortClassification: true
                )
            )
            press.setRemoteAudioAvailable()
            XCTAssertTrue(press.keyUp())
            press.setRemoteStreaming(false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.20))

            bridge.beginAudioStopDrainForTesting()
            let deferredSessionID = UUID()
            XCTAssertTrue(
                press.keyDown(
                    sessionID: deferredSessionID,
                    preparesRemoteTransport: true
                )
            )
            return deferredSessionID
        }

        func wait(_ interval: TimeInterval = 0.05) {
            RunLoop.main.run(until: Date().addingTimeInterval(interval))
        }

        func shutdown() {
            bridge.stop()
            press.stop()
        }
    }

    func testNormalAudioDrainCompletionReplaysDeferredRepressExactlyOnce() {
        let harness = AdmissionHarness()
        defer { harness.shutdown() }
        let deferredSessionID = harness.deferNextPress()

        harness.bridge.completeAudioStopDrainForTesting()
        harness.wait()

        XCTAssertEqual(harness.probe.admissionNotifications, 1)
        XCTAssertNil(harness.press.pendingRepressSessionID)
        XCTAssertEqual(harness.press.currentGestureIDForDiagnostics, deferredSessionID)
        XCTAssertEqual(harness.probe.transportPreparations, 1)

        // A stale completion after the barrier has already retired is a no-op.
        harness.bridge.completeAudioStopDrainForTesting()
        harness.wait()
        XCTAssertEqual(harness.probe.admissionNotifications, 1)
        XCTAssertEqual(harness.probe.transportPreparations, 1)
    }

    func testPhysicalUpBeforeAudioDrainRetirementDoesNotReplayDeferredRepress() {
        let harness = AdmissionHarness()
        defer { harness.shutdown() }
        _ = harness.deferNextPress()

        XCTAssertFalse(harness.press.keyUp())
        harness.bridge.completeAudioStopDrainForTesting()
        harness.wait()

        XCTAssertEqual(harness.probe.admissionNotifications, 1)
        XCTAssertNil(harness.press.pendingRepressSessionID)
        XCTAssertNil(harness.press.currentGestureIDForDiagnostics)
        XCTAssertEqual(harness.probe.transportPreparations, 0)
        XCTAssertEqual(harness.probe.optionEdges, [true, false])
    }

    func testCanceledAudioDrainCompletionAfterResetCannotReplayResolvedPressTwice() {
        let harness = AdmissionHarness()
        defer { harness.shutdown() }
        let deferredSessionID = harness.deferNextPress()

        harness.bridge.resetTransportForTesting()
        harness.wait()
        XCTAssertEqual(harness.probe.admissionNotifications, 1)
        XCTAssertNil(harness.press.pendingRepressSessionID)
        XCTAssertEqual(harness.press.currentGestureIDForDiagnostics, deferredSessionID)
        XCTAssertEqual(harness.probe.transportPreparations, 1)

        // The canceled Session A work item cannot produce a second replay.
        harness.bridge.completeAudioStopDrainForTesting()
        harness.wait()
        XCTAssertEqual(harness.probe.admissionNotifications, 1)
        XCTAssertEqual(harness.probe.transportPreparations, 1)
        XCTAssertEqual(harness.probe.optionEdges, [true, false])
    }

    func testExplicitTransportStopRetiresAudioDrainBarrierAndReplaysDeferredRepressExactlyOnce() {
        let harness = AdmissionHarness()
        defer { harness.shutdown() }
        let deferredSessionID = harness.deferNextPress()

        harness.bridge.stop()
        harness.wait()

        XCTAssertEqual(harness.probe.admissionNotifications, 1)
        XCTAssertNil(harness.press.pendingRepressSessionID)
        XCTAssertEqual(harness.press.currentGestureIDForDiagnostics, deferredSessionID)
        XCTAssertEqual(harness.probe.transportPreparations, 1)

        // Repeated stop and the canceled Session A completion cannot notify twice.
        harness.bridge.stop()
        harness.bridge.completeAudioStopDrainForTesting()
        harness.wait()
        XCTAssertEqual(harness.probe.admissionNotifications, 1)
        XCTAssertEqual(harness.probe.transportPreparations, 1)
        XCTAssertEqual(harness.probe.optionEdges, [true, false])
    }

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

    func testReadyTransportSurvivesVoiceSessionCloseAndCanReuseMicOpen() {
        var state = BLEVoiceTransportState()

        state.prepareTransport()
        state.beginConnection()
        XCTAssertEqual(state.connectionState, .connecting)

        state.markReady()
        XCTAssertEqual(state.connectionState, .ready)
        XCTAssertTrue(state.canReuseReadyTransport)

        state.requestVoiceInput()
        state.micOpenRequested = true
        state.finishVoiceSession()

        XCTAssertEqual(state.connectionState, .ready)
        XCTAssertTrue(state.canReuseReadyTransport)
        XCTAssertFalse(state.voiceInputRequested)
        XCTAssertFalse(state.micOpenRequested)

        state.requestVoiceInput()
        XCTAssertTrue(state.shouldRequestMicOpen)
    }

    func testFatalTransportResetClearsReadyStateBeforeReconnect() {
        var state = BLEVoiceTransportState()

        state.prepareTransport()
        state.beginConnection()
        state.markReady()
        state.requestVoiceInput()

        state.markDisconnected()

        XCTAssertEqual(state.connectionState, .disconnected)
        XCTAssertFalse(state.canReuseReadyTransport)
        XCTAssertFalse(state.atvvReady)
        XCTAssertFalse(state.transportPrepared)
    }

    func testBLEBridgeUsesDedicatedSerialQueueAndMarshalsCallbacksToMain() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        let queueIdentity = bridge.queueIdentityForTesting()
        XCTAssertEqual(queueIdentity.label, "com.remoteorbit.ble")
        XCTAssertTrue(queueIdentity.isDedicatedQueue)

        let callback = expectation(description: "audio callback returns to main")
        bridge.onAudioFrame = {
            XCTAssertTrue(Thread.isMainThread)
            callback.fulfill()
        }
        bridge.deliverAudioFrameCallbackForTesting()

        wait(for: [callback], timeout: 1.0)
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

    func testPostReleaseGraceKeepsVoiceIntentUntilActualClose() {
        var state = BLEVoiceTransportState()
        state.prepareTransport()
        state.requestVoiceInput()
        state.atvvReady = true
        state.micOpenRequested = true

        XCTAssertTrue(state.deferVoiceInputCloseForPostReleaseGrace())
        XCTAssertTrue(state.voiceInputRequested)
        XCTAssertTrue(state.micOpenRequested)

        state.commitVoiceInputClose()

        XCTAssertFalse(state.voiceInputRequested)
        XCTAssertFalse(state.micOpenRequested)
    }

    func testPostReleaseGraceCannotBeginWithoutVoiceIntent() {
        let state = BLEVoiceTransportState()

        XCTAssertFalse(state.deferVoiceInputCloseForPostReleaseGrace())
        XCTAssertFalse(state.voiceInputRequested)
        XCTAssertFalse(state.micOpenRequested)
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
