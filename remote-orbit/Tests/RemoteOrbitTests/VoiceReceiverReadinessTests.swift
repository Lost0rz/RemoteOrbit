import CoreAudio
import XCTest
@testable import RemoteOrbit

final class VoiceReceiverReadinessTests: XCTestCase {
    private final class FakeReadSource: VoiceReceiverReadSource {
        var targetID: AudioDeviceID? = 79
        var objectIDs: [AudioObjectID]? = [1]
        var pids: [AudioObjectID: Int32?] = [1: 200]
        var runningInputs: [AudioObjectID: Bool?] = [1: true]
        var inputDevices: [AudioObjectID: [AudioDeviceID]?] = [1: [79]]
        var bundleIDs: [AudioObjectID: String?] = [1: "com.bytedance.inputmethod.doubaoime"]
        private(set) var runningInputReadCount = 0
        private(set) var inputDeviceReadCount = 0
        private(set) var bundleIDReadCount = 0

        func targetDeviceID(named _: String) -> AudioDeviceID? {
            targetID
        }

        func processObjectIDs() -> [AudioObjectID]? {
            objectIDs
        }

        func processPID(_ objectID: AudioObjectID) -> Int32? {
            pids[objectID] ?? nil
        }

        func processIsRunningInput(_ objectID: AudioObjectID) -> Bool? {
            runningInputReadCount += 1
            return runningInputs[objectID] ?? nil
        }

        func processInputDeviceIDs(_ objectID: AudioObjectID) -> [AudioDeviceID]? {
            inputDeviceReadCount += 1
            return inputDevices[objectID] ?? nil
        }

        func processBundleID(_ objectID: AudioObjectID) -> String? {
            bundleIDReadCount += 1
            return bundleIDs[objectID] ?? nil
        }
    }

    private final class FakeProbe: VoiceReceiverReadinessProbe {
        var samples: [VoiceReceiverReadiness]
        private(set) var beginGenerationCount = 0
        private(set) var sampleCount = 0

        init(samples: [VoiceReceiverReadiness] = [.inactive]) {
            self.samples = samples
        }

        func beginGeneration() {
            beginGenerationCount += 1
        }

        func sample() -> VoiceReceiverReadiness {
            sampleCount += 1
            return samples[min(sampleCount - 1, samples.count - 1)]
        }
    }

    private final class BlockingProbe: VoiceReceiverReadinessProbe {
        let sampleEntered = DispatchSemaphore(value: 0)
        let releaseSample = DispatchSemaphore(value: 0)
        private(set) var sampleCount = 0

        func beginGeneration() {}

        func sample() -> VoiceReceiverReadiness {
            sampleCount += 1
            sampleEntered.signal()
            releaseSample.wait()
            return .inactive
        }
    }

    private final class FakeTimer: VoiceReceiverReadinessTimer {
        var eventHandler: (() -> Void)?
        private(set) var wasCancelled = false
        private(set) var wasResumed = false

        func schedule(
            deadline _: DispatchTime,
            repeating _: DispatchTimeInterval,
            leeway _: DispatchTimeInterval
        ) {}

        func resume() {
            wasResumed = true
        }

        func cancel() {
            wasCancelled = true
        }
    }

    private final class TimerStore {
        var timers: [FakeTimer] = []
    }

    private func makeMonitor(
        probe: VoiceReceiverReadinessProbe,
        timerStore: TimerStore
    ) -> VoiceReceiverReadinessMonitor {
        VoiceReceiverReadinessMonitor(
            probe: probe,
            timerFactory: { _ in
                let timer = FakeTimer()
                timerStore.timers.append(timer)
                return timer
            }
        )
    }

    func testProbeExcludesOwnPIDBeforeRunningInputRead() {
        guard #available(macOS 14.2, *) else { return }
        let source = FakeReadSource()
        source.pids = [1: 100]
        let probe = CoreAudioVoiceReceiverProbe(excludedPID: 100, source: source)

        XCTAssertEqual(probe.sample(), .inactive)
        XCTAssertEqual(source.runningInputReadCount, 0)
        XCTAssertEqual(source.inputDeviceReadCount, 0)
    }

    func testProbeDoesNotReadDevicesForNonRunningProcess() {
        guard #available(macOS 14.2, *) else { return }
        let source = FakeReadSource()
        source.runningInputs = [1: false]
        let probe = CoreAudioVoiceReceiverProbe(excludedPID: 100, source: source)

        XCTAssertEqual(probe.sample(), .inactive)
        XCTAssertEqual(source.runningInputReadCount, 1)
        XCTAssertEqual(source.inputDeviceReadCount, 0)
    }

    func testProbeRequiresRunningInputAndTargetDevice() {
        guard #available(macOS 14.2, *) else { return }
        let source = FakeReadSource()
        source.inputDevices = [1: [81]]
        let probe = CoreAudioVoiceReceiverProbe(excludedPID: 100, source: source)

        XCTAssertEqual(probe.sample(), .inactive)
        XCTAssertEqual(source.inputDeviceReadCount, 1)
        XCTAssertEqual(source.bundleIDReadCount, 0)

        source.inputDevices = [1: [79]]
        XCTAssertEqual(
            probe.sample(),
            .listening(
                consumerPID: 200,
                bundleID: "com.bytedance.inputmethod.doubaoime"
            )
        )
        XCTAssertEqual(source.bundleIDReadCount, 1)
    }

    func testProbeSkipsUnreadableProcessAndRecoversOnNextTick() {
        guard #available(macOS 14.2, *) else { return }
        let source = FakeReadSource()
        source.pids = [1: nil]
        let probe = CoreAudioVoiceReceiverProbe(excludedPID: 100, source: source)

        XCTAssertEqual(probe.sample(), .inactive)

        source.pids = [1: 200]
        XCTAssertEqual(
            probe.sample(),
            .listening(consumerPID: 200, bundleID: "com.bytedance.inputmethod.doubaoime")
        )
    }

    func testProbeTopLevelProcessListFailureIsUnsupported() {
        guard #available(macOS 14.2, *) else { return }
        let source = FakeReadSource()
        source.objectIDs = nil
        let probe = CoreAudioVoiceReceiverProbe(excludedPID: 100, source: source)

        XCTAssertEqual(probe.sample(), .unsupported)
        XCTAssertFalse(probe.sample().isListening)
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

    func testActivationSamplesImmediatelyAndCreatesOneTimer() {
        let probe = FakeProbe()
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)

        monitor.activate()
        monitor.waitForIdleForTesting()

        XCTAssertEqual(probe.beginGenerationCount, 1)
        XCTAssertEqual(probe.sampleCount, 1)
        XCTAssertEqual(timerStore.timers.count, 1)
        XCTAssertTrue(timerStore.timers[0].wasResumed)
        XCTAssertEqual(monitor.activeTimerCountForTesting, 1)
    }

    func testActivateCallerReturnsWhileProbeIsBlocked() {
        let probe = BlockingProbe()
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)
        let callerReturned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            monitor.activate()
            callerReturned.signal()
        }

        XCTAssertEqual(probe.sampleEntered.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(callerReturned.wait(timeout: .now() + 1), .success)
        probe.releaseSample.signal()
        monitor.waitForIdleForTesting()
    }

    func testDeactivateCallerReturnsWhileReadinessQueueIsBlocked() {
        let probe = BlockingProbe()
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)
        let activationReturned = DispatchSemaphore(value: 0)
        let deactivationReturned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            monitor.activate()
            activationReturned.signal()
        }
        XCTAssertEqual(probe.sampleEntered.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(activationReturned.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            monitor.deactivate()
            deactivationReturned.signal()
        }

        XCTAssertEqual(deactivationReturned.wait(timeout: .now() + 1), .success)
        probe.releaseSample.signal()
        monitor.waitForIdleForTesting()
    }

    func testRepeatedActivationIsIdempotent() {
        let probe = FakeProbe()
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)

        monitor.activate()
        monitor.activate()
        monitor.activate()
        monitor.waitForIdleForTesting()

        XCTAssertEqual(probe.beginGenerationCount, 1)
        XCTAssertEqual(probe.sampleCount, 1)
        XCTAssertEqual(timerStore.timers.count, 1)
        XCTAssertEqual(monitor.activeTimerCountForTesting, 1)
    }

    func testRapidLifecycleCommandsPreserveFIFOAndOneActiveTimer() {
        let probe = FakeProbe()
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)

        monitor.activate()
        monitor.deactivate()
        monitor.activate()
        monitor.waitForIdleForTesting()

        XCTAssertEqual(probe.beginGenerationCount, 2)
        XCTAssertEqual(probe.sampleCount, 2)
        XCTAssertEqual(timerStore.timers.count, 2)
        XCTAssertTrue(timerStore.timers[0].wasCancelled)
        XCTAssertTrue(timerStore.timers[1].wasResumed)
        XCTAssertEqual(monitor.activeTimerCountForTesting, 1)
    }

    func testDeactivateCancelsTimerAndPublishesNonListeningState() {
        let probe = FakeProbe(samples: [.listening(consumerPID: 200, bundleID: nil)])
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)

        monitor.activate()
        monitor.deactivate()
        monitor.waitForIdleForTesting()

        XCTAssertTrue(timerStore.timers[0].wasCancelled)
        XCTAssertEqual(monitor.activeTimerCountForTesting, 0)
        XCTAssertEqual(monitor.currentStateForTesting, .inactive)
    }

    func testStaleGenerationCannotPublishOrSampleAfterReactivation() {
        let probe = FakeProbe()
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)

        monitor.activate()
        monitor.waitForIdleForTesting()
        let oldGeneration = monitor.currentGenerationForTesting
        monitor.deactivate()
        monitor.waitForIdleForTesting()
        monitor.activate()
        monitor.waitForIdleForTesting()
        let currentGeneration = monitor.currentGenerationForTesting

        monitor.invokeTimerGenerationForTesting(oldGeneration)
        XCTAssertEqual(probe.sampleCount, 2)

        monitor.invokeTimerGenerationForTesting(currentGeneration)
        XCTAssertEqual(probe.sampleCount, 3)
    }

    func testStaleGenerationCannotDeliverAfterDeactivateAndReactivate() {
        let probe = FakeProbe(
            samples: [
                .listening(consumerPID: 200, bundleID: "com.bytedance.inputmethod.doubaoime"),
                .listening(consumerPID: 200, bundleID: "com.bytedance.inputmethod.doubaoime"),
            ]
        )
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)
        var delivered: [VoiceReceiverReadiness] = []
        monitor.onStateChanged = { readiness in
            delivered.append(readiness)
        }

        DispatchQueue.global().sync {
            monitor.activate()
            monitor.waitForIdleForTesting()
            let oldGeneration = monitor.currentGenerationForTesting
            monitor.deactivate()
            monitor.waitForIdleForTesting()
            monitor.activate()
            monitor.waitForIdleForTesting()

            monitor.invokeTimerGenerationForTesting(oldGeneration)
            monitor.waitForIdleForTesting()
        }

        let mainQueueFlushed = expectation(description: "main readiness deliveries flushed")
        DispatchQueue.main.async {
            mainQueueFlushed.fulfill()
        }
        wait(for: [mainQueueFlushed], timeout: 1)

        XCTAssertEqual(
            delivered,
            [
                .listening(consumerPID: 200, bundleID: "com.bytedance.inputmethod.doubaoime"),
                .inactive,
                .listening(consumerPID: 200, bundleID: "com.bytedance.inputmethod.doubaoime"),
            ]
        )
    }

    func testLargeLifecycleStressKeepsSchedulerStateBounded() {
        let probe = FakeProbe()
        let timerStore = TimerStore()
        let monitor = makeMonitor(probe: probe, timerStore: timerStore)

        for _ in 0..<100_000 {
            monitor.activate()
            monitor.activate()
            monitor.deactivate()
        }
        monitor.waitForIdleForTesting()

        XCTAssertEqual(monitor.activeTimerCountForTesting, 0)
        XCTAssertEqual(probe.sampleCount, 100_000)
        XCTAssertEqual(probe.beginGenerationCount, 100_000)
    }

    func testReadinessSourceContainsNoCoreAudioListenerRegistrationCalls() throws {
        let source = try sourceText(relativePath: "Sources/RemoteOrbit/VoiceReceiverReadiness.swift")

        XCTAssertFalse(source.contains("AudioObjectAddPropertyListenerBlock"))
        XCTAssertFalse(source.contains("AudioObjectRemovePropertyListenerBlock"))
    }

    func testReadinessLifecycleCallersDoNotSynchronouslyWaitOnReadinessQueue() throws {
        let source = try sourceText(relativePath: "Sources/RemoteOrbit/VoiceReceiverReadiness.swift")

        XCTAssertTrue(source.contains("func activate() {\n        queue.async"))
        XCTAssertTrue(source.contains("func deactivate() {\n        queue.async"))
        XCTAssertFalse(source.contains("func activate() {\n        queue.sync"))
        XCTAssertFalse(source.contains("func deactivate() {\n        queue.sync"))
    }

    func testHUDDoesNotSynchronouslyReadMonitorState() throws {
        let source = try sourceText(relativePath: "Sources/RemoteOrbit/main.swift")

        XCTAssertFalse(source.contains("voiceReceiverReadinessMonitor.currentState"))
        XCTAssertTrue(source.contains("lastReceiverReadiness"))
        XCTAssertTrue(
            source.contains(
                "case .draining, .idle:\n                self?.lastReceiverReadiness = .inactive\n                self?.voiceReceiverReadinessMonitor.deactivate()"
            )
        )
    }

    func testReadinessPublicationDoesNotSynchronouslyHopBackFromMain() throws {
        let source = try sourceText(relativePath: "Sources/RemoteOrbit/VoiceReceiverReadiness.swift")

        XCTAssertFalse(source.contains("pendingStateDelivery"))
        XCTAssertFalse(source.contains("stateDeliveryScheduled"))
        XCTAssertFalse(source.contains("self.queue.sync"))
    }

    private func sourceText(relativePath: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
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
