import XCTest
@testable import RemoteOrbit

final class VoiceReceiverReadinessTests: XCTestCase {
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
