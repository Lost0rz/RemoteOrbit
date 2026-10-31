import XCTest
@testable import RemoteOrbit

final class VoiceReceiverReadinessTests: XCTestCase {
    private func matchingObservation(
        runningInputListenerInstalled: Bool = true,
        inputDevicesListenerInstalled: Bool = true
    ) -> VoiceReceiverProcessObservation {
        VoiceReceiverProcessObservation(
            snapshot: VoiceReceiverProcessSnapshot(
                pid: 200,
                bundleID: "com.bytedance.inputmethod.doubaoime",
                runningInput: true,
                inputDeviceIDs: [79]
            ),
            runningInputListenerInstalled: runningInputListenerInstalled,
            inputDevicesListenerInstalled: inputDevicesListenerInstalled
        )
    }

    func testSystemListenerFailureCannotPublishListening() {
        let state = VoiceReceiverReadinessEvaluator.evaluate(
            observations: [matchingObservation()],
            targetDeviceID: 79,
            excludingPID: 100,
            systemListenerInstalled: false
        )

        XCTAssertEqual(state, .unsupported)
        XCTAssertFalse(state.isListening)
    }

    func testPartialProcessListenerAuthorityCannotPublishListening() {
        let state = VoiceReceiverReadinessEvaluator.evaluate(
            observations: [
                matchingObservation(inputDevicesListenerInstalled: false)
            ],
            targetDeviceID: 79,
            excludingPID: 100,
            systemListenerInstalled: true
        )

        XCTAssertEqual(state, .unsupported)
        XCTAssertFalse(state.isListening)
    }

    func testAuthorityLossAfterListeningFallsBackToUnsupportedAndNonGreenHUD() {
        let listening = VoiceReceiverReadinessEvaluator.evaluate(
            observations: [matchingObservation()],
            targetDeviceID: 79,
            excludingPID: 100,
            systemListenerInstalled: true
        )
        let afterAuthorityLoss = VoiceReceiverReadinessEvaluator.evaluate(
            observations: [
                matchingObservation(runningInputListenerInstalled: false)
            ],
            targetDeviceID: 79,
            excludingPID: 100,
            systemListenerInstalled: true
        )

        XCTAssertEqual(
            listening,
            .listening(
                consumerPID: 200,
                bundleID: "com.bytedance.inputmethod.doubaoime"
            )
        )
        XCTAssertEqual(afterAuthorityLoss, .unsupported)
        XCTAssertEqual(
            VoiceHUDProjection.state(
                for: .streaming,
                remoteAudioAvailable: true,
                receiverReadiness: afterAuthorityLoss
            ),
            .voiceAudioReady
        )
    }

    func testEvaluatorReportsExternalConsumerListening() {
        let state = VoiceReceiverReadinessEvaluator.evaluate(
            processes: [
                VoiceReceiverProcessSnapshot(
                    pid: 100,
                    bundleID: "com.lost0rz.RemoteOrbit",
                    runningInput: true,
                    inputDeviceIDs: [79]
                ),
                VoiceReceiverProcessSnapshot(
                    pid: 200,
                    bundleID: "com.bytedance.inputmethod.doubaoime",
                    runningInput: true,
                    inputDeviceIDs: [79]
                ),
            ],
            targetDeviceID: 79,
            excludingPID: 100
        )

        XCTAssertEqual(
            state,
            .listening(
                consumerPID: 200,
                bundleID: "com.bytedance.inputmethod.doubaoime"
            )
        )
    }

    func testEvaluatorReportsInactiveWithoutMatchingExternalConsumer() {
        let state = VoiceReceiverReadinessEvaluator.evaluate(
            processes: [
                VoiceReceiverProcessSnapshot(
                    pid: 100,
                    bundleID: "com.lost0rz.RemoteOrbit",
                    runningInput: true,
                    inputDeviceIDs: [79]
                ),
                VoiceReceiverProcessSnapshot(
                    pid: 200,
                    bundleID: "com.example.other",
                    runningInput: true,
                    inputDeviceIDs: [81]
                ),
                VoiceReceiverProcessSnapshot(
                    pid: 300,
                    bundleID: "com.bytedance.inputmethod.doubaoime",
                    runningInput: false,
                    inputDeviceIDs: [79]
                ),
            ],
            targetDeviceID: 79,
            excludingPID: 100
        )

        XCTAssertEqual(state, .inactive)
    }

    func testEvaluatorExcludesRemoteOrbitOwnInput() {
        let state = VoiceReceiverReadinessEvaluator.evaluate(
            processes: [
                VoiceReceiverProcessSnapshot(
                    pid: 100,
                    bundleID: "com.lost0rz.RemoteOrbit",
                    runningInput: true,
                    inputDeviceIDs: [79]
                ),
            ],
            targetDeviceID: 79,
            excludingPID: 100
        )

        XCTAssertEqual(state, .inactive)
    }

    func testEvaluatorUsesConservativeUnsupportedStateWhenAPIUnavailable() {
        let state = VoiceReceiverReadinessEvaluator.evaluate(
            processes: [],
            targetDeviceID: 79,
            excludingPID: 100,
            apiAvailable: false
        )

        XCTAssertEqual(state, .unsupported)
        XCTAssertFalse(state.isListening)
    }

    func testOpeningProjectsToWaitingForIME() {
        XCTAssertEqual(
            VoiceHUDProjection.state(
                for: .opening,
                remoteAudioAvailable: false,
                receiverReadiness: .inactive
            ),
            .voiceStarting
        )
        XCTAssertEqual(RemoteActionHUDState.voiceStarting.title, "等待输入法")
    }

    func testStreamingAloneProjectsNonGreenAudioReady() {
        let state = VoiceHUDProjection.state(
            for: .streaming,
            remoteAudioAvailable: true,
            receiverReadiness: .inactive
        )

        XCTAssertEqual(state, .voiceAudioReady)
        XCTAssertNotEqual(state, .recording)
        XCTAssertEqual(RemoteActionHUDState.voiceAudioReady.title, "音频已就绪")
    }

    func testAudioFirstAloneProjectsNonGreenAudioReady() {
        let state = VoiceHUDProjection.state(
            for: .holding,
            remoteAudioAvailable: true,
            receiverReadiness: .inactive
        )

        XCTAssertEqual(state, .voiceAudioReady)
        XCTAssertNotEqual(state, .recording)
    }

    func testConfirmedReceiverProjectsGreenRecording() {
        let state = VoiceHUDProjection.state(
            for: .streaming,
            remoteAudioAvailable: true,
            receiverReadiness: .listening(
                consumerPID: 200,
                bundleID: "com.bytedance.inputmethod.doubaoime"
            )
        )

        XCTAssertEqual(state, .recording)
        XCTAssertEqual(RemoteActionHUDState.recording.color, .systemGreen)
    }

    func testReceiverLossImmediatelyFallsBackToAudioReady() {
        let state = VoiceHUDProjection.state(
            for: .streaming,
            remoteAudioAvailable: true,
            receiverReadiness: .inactive
        )

        XCTAssertEqual(state, .voiceAudioReady)
        XCTAssertNotEqual(state, .recording)
    }

    func testUnsupportedReceiverNeverProducesGreenFromInternalState() {
        for voiceState in [VoicePressCoordinator.State.holding, .streaming] {
            let state = VoiceHUDProjection.state(
                for: voiceState,
                remoteAudioAvailable: true,
                receiverReadiness: .unsupported
            )
            XCTAssertEqual(state, .voiceAudioReady)
            XCTAssertNotEqual(state, .recording)
        }
    }
}
