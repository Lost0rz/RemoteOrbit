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
            bridge.onPreHIDPhysicalStreamChanged = { [weak press] streaming, _ in
                press?.setPreHIDPhysicalStreaming(streaming)
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

    func testPhysicalAudioStartBeforeHIDUsesPreHIDStreamOwnership() {
        XCTAssertEqual(
            BLEBridge.streamOwnershipForAudioStart(
                micOpenRequested: false,
                voiceInputRequested: false
            ),
            .preHIDPhysical
        )
        XCTAssertEqual(
            BLEBridge.streamOwnershipForAudioStart(
                micOpenRequested: true,
                voiceInputRequested: true
            ),
            .voiceSession
        )
    }

    func testPhysicalAudioStartBeforeHIDThenMatchingHIDIsAdmissible() {
        let harness = AdmissionHarness()
        defer { harness.shutdown() }

        harness.bridge.beginPreHIDPhysicalStreamForTesting()
        harness.wait()

        XCTAssertTrue(
            harness.press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(harness.press.currentStateForTesting, .opening)
        XCTAssertTrue(harness.press.hasReleaseOrTailOwnershipForReconfiguration)
    }

    func testPhysicalReason03DifferentStreamSupersedesOldPhysicalDrainAndStaleDrainCannotRetireIt() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.requestVoiceActivationForTesting()
        bridge.beginPreHIDPhysicalStreamForTesting()
        bridge.beginAudioStopDrainForTesting()
        XCTAssertTrue(bridge.isVoiceSessionAdmissionBlocked)

        bridge.receiveAudioStartForTesting(reason: 0x03, streamID: 0x4c)

        XCTAssertFalse(bridge.isVoiceSessionAdmissionBlocked)
        XCTAssertTrue(bridge.hasLivePreHIDPhysicalCandidateForTesting)

        // A later B drain makes the stale-A callback observable: it must not
        // complete B's barrier or clear B's ownership.
        bridge.beginAudioStopDrainForTesting()
        bridge.completeStaleAudioStopDrainForTesting()
        XCTAssertTrue(bridge.isVoiceSessionAdmissionBlocked)
        XCTAssertTrue(bridge.hasLivePreHIDPhysicalCandidateForTesting)
        XCTAssertEqual(bridge.streamOwnershipForTesting, .preHIDPhysical)

        // The current B completion still retires normally.
        bridge.completeAudioStopDrainForTesting()
        XCTAssertFalse(bridge.hasLivePreHIDPhysicalCandidateForTesting)
        XCTAssertEqual(bridge.streamOwnershipForTesting, .none)
    }

    func testReleasedHostMicOpenActiveDrainReason03DifferentStreamSupersedesImmediately() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.requestVoiceActivationForTesting()
        bridge.beginAudioStartForTesting()
        bridge.releasePhysicalVoiceInputForTesting()
        bridge.beginAudioStopDrainForTesting()
        XCTAssertTrue(bridge.isVoiceSessionAdmissionBlocked)
        XCTAssertTrue(bridge.postReleaseGraceWaitingForTesting)

        bridge.receiveAudioStartForTesting(reason: 0x03, streamID: 0x61)

        XCTAssertFalse(bridge.isVoiceSessionAdmissionBlocked)
        XCTAssertEqual(bridge.streamOwnershipForTesting, .preHIDPhysical)
        XCTAssertTrue(bridge.hasLivePreHIDPhysicalCandidateForTesting)
        XCTAssertFalse(bridge.postReleaseGraceWaitingForTesting)
        XCTAssertFalse(bridge.voiceInputRequestedForTesting)
        XCTAssertFalse(bridge.micOpenRequestedForTesting)
        XCTAssertEqual(bridge.micCloseRequestCountForTesting, 0)
        XCTAssertTrue(bridge.canReuseReadyTransportForTesting)

        // A canceled old drain callback cannot retire the replacement B epoch.
        bridge.beginAudioStopDrainForTesting()
        bridge.completeStaleAudioStopDrainForTesting()
        XCTAssertTrue(bridge.isVoiceSessionAdmissionBlocked)
        XCTAssertTrue(bridge.hasLivePreHIDPhysicalCandidateForTesting)
        XCTAssertEqual(bridge.streamOwnershipForTesting, .preHIDPhysical)
    }

    func testSameStreamAndNonPhysicalReasonDoNotSupersedePhysicalDrain() {
        let sameStream = BLEBridge.audioStartDisposition(
            drainPending: true,
            currentStreamID: 0x4c,
            incomingStreamID: 0x4c,
            pendingAudioStopReason: 0x02,
            incomingReason: 0x03,
            currentStreamOwnership: .voiceSession,
            releasedHostMicOpenDrainSupersessionEligible: true
        )
        XCTAssertEqual(
            sameStream,
            .ignoredDuringDrain(
                currentStreamID: 0x4c,
                incomingStreamID: 0x4c,
                pendingAudioStopReason: 0x02
            )
        )

        let nonPhysicalReason = BLEBridge.audioStartDisposition(
            drainPending: true,
            currentStreamID: 0x4c,
            incomingStreamID: 0x4d,
            pendingAudioStopReason: 0x02,
            incomingReason: 0x02,
            currentStreamOwnership: .voiceSession,
            releasedHostMicOpenDrainSupersessionEligible: true
        )
        XCTAssertEqual(
            nonPhysicalReason,
            .ignoredDuringDrain(
                currentStreamID: 0x4c,
                incomingStreamID: 0x4d,
                pendingAudioStopReason: 0x02
            )
        )

        XCTAssertEqual(
            BLEBridge.audioStartDisposition(
                drainPending: true,
                currentStreamID: 0x4c,
                incomingStreamID: 0x4d,
                pendingAudioStopReason: 0x02,
                incomingReason: 0x03,
                currentStreamOwnership: .voiceSession,
                currentStreamIsPhysical: true
            ),
            .supersedePhysicalDrain
        )
    }

    func testHOST_AUDIO_STOP_DRAINED_THEN_REASON03_BEFORE_HID_SUPERSEDES_HOST_GRACE() {
        let bridge = BLEBridge()
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in }
        )
        defer {
            bridge.stop()
            press.stop()
        }
        bridge.onPreHIDPhysicalStreamChanged = { [weak press] streaming, _ in
            press?.setPreHIDPhysicalStreaming(streaming)
        }
        press.onStateChanged = { state in
            if state == .opening {
                bridge.requestVoiceActivationForTesting()
            }
        }

        bridge.requestVoiceActivationForTesting()
        bridge.beginAudioStartForTesting()
        bridge.releasePhysicalVoiceInputForTesting()
        bridge.beginAudioStopDrainForTesting()
        bridge.completeAudioStopDrainForTesting()
        XCTAssertTrue(bridge.postReleaseGraceWaitingForTesting)

        bridge.receiveAudioStartForTesting(reason: 0x03, streamID: 0x4c)

        XCTAssertEqual(bridge.streamOwnershipForTesting, .preHIDPhysical)
        XCTAssertFalse(bridge.postReleaseGraceWaitingForTesting)
        XCTAssertFalse(bridge.voiceInputRequestedForTesting)
        XCTAssertFalse(bridge.micOpenRequestedForTesting)
        XCTAssertEqual(bridge.micCloseRequestCountForTesting, 0)
        XCTAssertTrue(bridge.canReuseReadyTransportForTesting)

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(bridge.streamOwnershipForTesting, .voiceSession)
    }

    func testSUPERSEDED_HOST_GRACE_CALLBACK_CANNOT_CLOSE_NEW_PHYSICAL_STREAM() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.requestVoiceActivationForTesting()
        bridge.releasePhysicalVoiceInputForTesting()
        let oldSessionID = bridge.postReleaseGraceSessionIDForTesting!
        let oldGeneration = bridge.postReleaseGraceGenerationForTesting

        bridge.receiveAudioStartForTesting(reason: 0x03, streamID: 0x4d)

        XCTAssertFalse(
            bridge.expirePostReleaseGraceForTesting(
                sessionID: oldSessionID,
                generation: oldGeneration
            )
        )
        XCTAssertEqual(bridge.streamOwnershipForTesting, .preHIDPhysical)
        XCTAssertEqual(bridge.micCloseRequestCountForTesting, 0)
    }

    func testSUPERSEDED_HOST_REQUEST_RETAINS_READY() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.requestVoiceActivationForTesting()
        bridge.releasePhysicalVoiceInputForTesting()
        bridge.receiveAudioStartForTesting(reason: 0x03, streamID: 0x4e)

        XCTAssertTrue(bridge.canReuseReadyTransportForTesting)
        XCTAssertFalse(bridge.micOpenRequestedForTesting)
    }

    func testNORMAL_HOST_AUDIO_START_REASON_NOT_03_IS_NOT_SUPERSEDED() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.requestVoiceActivationForTesting()
        bridge.releasePhysicalVoiceInputForTesting()
        bridge.receiveAudioStartForTesting(reason: 0x02, streamID: 0x4f)

        XCTAssertEqual(bridge.streamOwnershipForTesting, .voiceSession)
        XCTAssertTrue(bridge.micOpenRequestedForTesting)
        XCTAssertTrue(bridge.postReleaseGraceWaitingForTesting)
    }

    func testREASON03_WITHOUT_RELEASED_HOST_GRACE_DOES_NOT_APPLY_HOST_SUPERSESSION_RULE() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.requestVoiceActivationForTesting()
        bridge.receiveAudioStartForTesting(reason: 0x03, streamID: 0x50)

        XCTAssertEqual(bridge.streamOwnershipForTesting, .voiceSession)
        XCTAssertTrue(bridge.micOpenRequestedForTesting)
        XCTAssertFalse(bridge.postReleaseGraceWaitingForTesting)
    }

    func testAdoptPhysicalStreamWithoutDuplicateMicOpen() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.beginPreHIDPhysicalStreamForTesting()
        bridge.requestVoiceActivationForTesting()

        XCTAssertEqual(bridge.streamOwnershipForTesting, .voiceSession)
        XCTAssertFalse(bridge.micOpenRequestedForTesting)
    }

    func testHostMicOpenPathRemainsForReadyTransportWithoutPhysicalStream() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.requestVoiceActivationForTesting()

        XCTAssertEqual(bridge.streamOwnershipForTesting, .none)
        XCTAssertEqual(bridge.micOpenRequestCountForTesting, 1)
    }

    func testAdoptedStreamRetirementClearsOwnership() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.beginPreHIDPhysicalStreamForTesting()
        bridge.requestVoiceActivationForTesting()
        XCTAssertEqual(bridge.streamOwnershipForTesting, .voiceSession)

        bridge.beginAudioStopDrainForTesting()
        bridge.completeAudioStopDrainForTesting()

        XCTAssertEqual(bridge.streamOwnershipForTesting, .none)
    }

    func testRapidNextSessionAfterAdoptedStreamUsesHostMicOpenWhenNeeded() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.beginPreHIDPhysicalStreamForTesting()
        bridge.requestVoiceActivationForTesting()
        bridge.beginAudioStopDrainForTesting()
        bridge.completeAudioStopDrainForTesting()
        bridge.requestVoiceActivationForTesting()

        XCTAssertEqual(bridge.streamOwnershipForTesting, .none)
        XCTAssertEqual(bridge.micOpenRequestCountForTesting, 1)
    }

    func testAdoptedPhysicalReleaseAndAudioStopRetiresStaleIntent() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.beginPreHIDPhysicalStreamForTesting()
        bridge.requestVoiceActivationForTesting()
        XCTAssertEqual(bridge.streamOwnershipForTesting, .voiceSession)
        XCTAssertFalse(bridge.micOpenRequestedForTesting)

        bridge.releasePhysicalVoiceInputForTesting()
        XCTAssertTrue(bridge.postReleaseGraceWaitingForTesting)
        XCTAssertTrue(bridge.voiceInputRequestedForTesting)

        bridge.beginAudioStopDrainForTesting()
        bridge.completeAudioStopDrainForTesting()

        XCTAssertFalse(bridge.postReleaseGraceWaitingForTesting)
        XCTAssertFalse(bridge.voiceInputRequestedForTesting)
        XCTAssertFalse(bridge.micOpenRequestedForTesting)
        XCTAssertEqual(bridge.micCloseRequestCountForTesting, 0)
    }

    func testAdoptedPhysicalRetirementPreservesReady() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.beginPreHIDPhysicalStreamForTesting()
        bridge.requestVoiceActivationForTesting()
        bridge.releasePhysicalVoiceInputForTesting()
        bridge.beginAudioStopDrainForTesting()
        bridge.completeAudioStopDrainForTesting()

        XCTAssertTrue(bridge.canReuseReadyTransportForTesting)
        XCTAssertEqual(bridge.streamOwnershipForTesting, .none)
    }

    func testRapidNextPhysicalStreamDuringFormerGraceIsAdmissible() {
        let harness = AdmissionHarness()
        defer { harness.shutdown() }

        harness.bridge.beginPreHIDPhysicalStreamForTesting()
        harness.bridge.requestVoiceActivationForTesting()
        harness.bridge.releasePhysicalVoiceInputForTesting()
        harness.bridge.beginAudioStopDrainForTesting()
        harness.bridge.completeAudioStopDrainForTesting()
        harness.wait()

        harness.bridge.beginPreHIDPhysicalStreamForTesting()
        harness.wait()
        XCTAssertTrue(
            harness.press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )

        harness.bridge.requestVoiceActivationForTesting()
        harness.wait()
        XCTAssertEqual(harness.bridge.streamOwnershipForTesting, .voiceSession)
        XCTAssertFalse(harness.bridge.micOpenRequestedForTesting)
    }

    func testHostMicOpenGraceUnchanged() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.requestVoiceActivationForTesting()
        XCTAssertTrue(bridge.micOpenRequestedForTesting)
        bridge.releasePhysicalVoiceInputForTesting()

        XCTAssertTrue(bridge.postReleaseGraceWaitingForTesting)
        XCTAssertTrue(bridge.voiceInputRequestedForTesting)

        bridge.completeNoAudioVoiceCloseForTesting()

        XCTAssertFalse(bridge.postReleaseGraceWaitingForTesting)
        XCTAssertFalse(bridge.voiceInputRequestedForTesting)
        XCTAssertFalse(bridge.micOpenRequestedForTesting)
        XCTAssertEqual(bridge.micCloseRequestCountForTesting, 1)
        XCTAssertTrue(bridge.canReuseReadyTransportForTesting)
    }

    func testAudioStopBeforePhysicalReleaseDoesNotRetireIntent() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        bridge.beginPreHIDPhysicalStreamForTesting()
        bridge.requestVoiceActivationForTesting()
        bridge.beginAudioStopDrainForTesting()
        bridge.completeAudioStopDrainForTesting()

        XCTAssertTrue(bridge.voiceInputRequestedForTesting)
        XCTAssertFalse(bridge.postReleaseGraceWaitingForTesting)

        bridge.releasePhysicalVoiceInputForTesting()

        XCTAssertFalse(bridge.postReleaseGraceWaitingForTesting)
        XCTAssertFalse(bridge.voiceInputRequestedForTesting)
        XCTAssertTrue(bridge.canReuseReadyTransportForTesting)
    }

    func testRepeatedRapidAdoptedPhysicalSessionsRemainAdmissible() {
        let bridge = BLEBridge()
        defer { bridge.stop() }

        for _ in 0..<5 {
            bridge.beginPreHIDPhysicalStreamForTesting()
            bridge.requestVoiceActivationForTesting()
            XCTAssertEqual(bridge.streamOwnershipForTesting, .voiceSession)
            XCTAssertFalse(bridge.micOpenRequestedForTesting)

            bridge.releasePhysicalVoiceInputForTesting()
            bridge.beginAudioStopDrainForTesting()
            bridge.completeAudioStopDrainForTesting()

            XCTAssertFalse(bridge.voiceInputRequestedForTesting)
            XCTAssertTrue(bridge.canReuseReadyTransportForTesting)
        }
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

    func testVoiceIntentTransportResetNotifiesConnectionLossBeforeReady() {
        let bridge = BLEBridge()
        var connectionEvents: [Bool] = []
        bridge.onConnectionChanged = { connectionEvents.append($0) }
        bridge.requestVoiceInputForTesting()

        bridge.resetTransportForTesting()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(connectionEvents, [false])
        bridge.stop()
    }

    func testNoAudioVoiceCloseNotifiesStreamingRetirement() {
        let bridge = BLEBridge()
        var streamingEvents: [Bool] = []
        bridge.onStreamingChanged = { streaming, _ in streamingEvents.append(streaming) }
        bridge.requestVoiceInputForTesting()

        bridge.completeNoAudioVoiceCloseForTesting()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(streamingEvents, [false])
        bridge.stop()
    }

    func testReadyTransportSurvivesVoiceSessionCloseAndCanReuseMicOpen() {
        var state = BLEVoiceTransportState()

        establishStrictReady(&state)
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

        establishStrictReady(&state)
        state.requestVoiceInput()

        state.markDisconnected()

        XCTAssertEqual(state.connectionState, .disconnected)
        XCTAssertFalse(state.canReuseReadyTransport)
        XCTAssertFalse(state.atvvReady)
        XCTAssertFalse(state.transportPrepared)
    }

    func testCapabilitiesBeforeNotifyWaitsForBothConfirmedNotifications() {
        var state = BLEVoiceTransportState()
        state.prepareTransport()
        state.beginConnection()
        state.requestVoiceInput()
        state.markAudioCharacteristicDiscovered()
        state.markCommandCharacteristicDiscovered()
        state.markControlCharacteristicDiscovered()
        state.markCapabilitiesAccepted()

        XCTAssertFalse(state.evaluateATVVReadiness())
        XCTAssertEqual(state.connectionState, .connecting)
        XCTAssertFalse(state.shouldRequestMicOpen)

        state.markAudioNotificationConfirmed()
        XCTAssertFalse(state.evaluateATVVReadiness())
        XCTAssertFalse(state.shouldRequestMicOpen)

        state.markControlNotificationConfirmed()
        XCTAssertTrue(state.evaluateATVVReadiness())
        XCTAssertEqual(state.connectionState, .ready)
        XCTAssertTrue(state.shouldRequestMicOpen)
        XCTAssertFalse(state.evaluateATVVReadiness())
    }

    func testNotifyBeforeCapabilitiesWaitsForAcceptedCapabilities() {
        var state = BLEVoiceTransportState()
        state.prepareTransport()
        state.beginConnection()
        state.markAudioCharacteristicDiscovered()
        state.markCommandCharacteristicDiscovered()
        state.markControlCharacteristicDiscovered()
        state.markAudioNotificationConfirmed()
        state.markControlNotificationConfirmed()

        XCTAssertFalse(state.evaluateATVVReadiness())
        XCTAssertEqual(state.connectionState, .connecting)

        state.markCapabilitiesAccepted()
        XCTAssertTrue(state.evaluateATVVReadiness())
        XCTAssertEqual(state.connectionState, .ready)
        XCTAssertFalse(state.evaluateATVVReadiness())
    }

    func testPartialNotificationConfirmationCannotBecomeReady() {
        var state = BLEVoiceTransportState()
        state.prepareTransport()
        state.beginConnection()
        state.markAudioCharacteristicDiscovered()
        state.markCommandCharacteristicDiscovered()
        state.markControlCharacteristicDiscovered()
        state.markCapabilitiesAccepted()

        state.markAudioNotificationConfirmed()
        XCTAssertFalse(state.evaluateATVVReadiness())
        XCTAssertFalse(state.canReuseReadyTransport)

        state.markDisconnected()
        state.prepareTransport()
        state.beginConnection()
        state.markAudioCharacteristicDiscovered()
        state.markCommandCharacteristicDiscovered()
        state.markControlCharacteristicDiscovered()
        state.markCapabilitiesAccepted()
        state.markControlNotificationConfirmed()
        XCTAssertFalse(state.evaluateATVVReadiness())
        XCTAssertFalse(state.canReuseReadyTransport)
    }

    func testNotificationFailureCannotLeaveReusableReady() {
        var state = BLEVoiceTransportState()
        establishStrictReady(&state)

        state.markDisconnected()

        XCTAssertEqual(state.connectionState, .disconnected)
        XCTAssertFalse(state.canReuseReadyTransport)
        XCTAssertFalse(state.audioNotificationConfirmed)
        XCTAssertFalse(state.controlNotificationConfirmed)
        XCTAssertFalse(state.capabilitiesAccepted)
    }

    func testResetClearsConfirmedNotificationsAndCapabilities() {
        var state = BLEVoiceTransportState()
        establishStrictReady(&state)

        state.beginConnection()

        XCTAssertEqual(state.connectionState, .connecting)
        XCTAssertFalse(state.audioCharacteristicDiscovered)
        XCTAssertFalse(state.commandCharacteristicDiscovered)
        XCTAssertFalse(state.controlCharacteristicDiscovered)
        XCTAssertFalse(state.audioNotificationConfirmed)
        XCTAssertFalse(state.controlNotificationConfirmed)
        XCTAssertFalse(state.capabilitiesAccepted)
        XCTAssertFalse(state.atvvReady)
        XCTAssertFalse(state.evaluateATVVReadiness())
        XCTAssertFalse(state.canReuseReadyTransport)
    }

    func testReadyReusePreservesConfirmedReadinessFactsAfterVoiceClose() {
        var state = BLEVoiceTransportState()
        establishStrictReady(&state)
        state.requestVoiceInput()
        state.micOpenRequested = true

        state.finishVoiceSession()

        XCTAssertTrue(state.audioNotificationConfirmed)
        XCTAssertTrue(state.controlNotificationConfirmed)
        XCTAssertTrue(state.capabilitiesAccepted)
        XCTAssertEqual(state.connectionState, .ready)
        XCTAssertTrue(state.canReuseReadyTransport)

        state.requestVoiceInput()
        XCTAssertTrue(state.shouldRequestMicOpen)
    }

    func testMicOpenEligibilityRequiresStrictReadyFacts() {
        var state = BLEVoiceTransportState()
        state.prepareTransport()
        state.beginConnection()
        state.requestVoiceInput()
        state.markAudioCharacteristicDiscovered()
        state.markCommandCharacteristicDiscovered()
        state.markControlCharacteristicDiscovered()
        state.markCapabilitiesAccepted()

        XCTAssertFalse(state.shouldRequestMicOpen)
        state.markAudioNotificationConfirmed()
        XCTAssertFalse(state.evaluateATVVReadiness())
        XCTAssertFalse(state.shouldRequestMicOpen)
        state.markControlNotificationConfirmed()
        XCTAssertTrue(state.evaluateATVVReadiness())
        XCTAssertTrue(state.shouldRequestMicOpen)
    }

    private func establishStrictReady(_ state: inout BLEVoiceTransportState) {
        state.prepareTransport()
        state.beginConnection()
        state.markAudioCharacteristicDiscovered()
        state.markCommandCharacteristicDiscovered()
        state.markControlCharacteristicDiscovered()
        state.markAudioNotificationConfirmed()
        state.markControlNotificationConfirmed()
        state.markCapabilitiesAccepted()
        XCTAssertTrue(state.evaluateATVVReadiness())
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
