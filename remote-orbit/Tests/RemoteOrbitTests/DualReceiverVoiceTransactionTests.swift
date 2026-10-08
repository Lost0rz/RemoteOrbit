import XCTest
@testable import RemoteOrbit

final class DualReceiverVoiceTransactionTests: XCTestCase {
    func testFirstDownOnlyPrewarmsAndClassifiedAHoldActivatesWithoutSecondWait() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 100.0)

        XCTAssertEqual(harness.prewarmCount, 1)
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.cancelCount, 0)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.scheduler.advance(to: 100.349)
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.remoteRouted, false)

        harness.scheduler.advance(to: 100.350)

        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .holding)
        XCTAssertEqual(harness.remoteRouted, true)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.scheduler.advance(to: 100.650)
        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.edge(isDown: false, at: 100.700)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertEqual(harness.stopVoiceInputCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testFirstQuickReleaseKeepsPrewarmUntilDoubleWindowThenCancels() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 200.0)
        harness.edge(isDown: false, at: 200.050)

        XCTAssertEqual(harness.prewarmCount, 1)
        XCTAssertEqual(harness.cancelCount, 0)
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.scheduler.advance(to: 200.350)
        XCTAssertEqual(harness.cancelCount, 0)
        XCTAssertEqual(harness.activationCount, 0)

        harness.scheduler.advance(to: 200.351)
        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertEqual(harness.hardwareGateCancelCount, 1)
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testSecondDownDuringDelayedSecondaryArmIsDiscardedAndRestoredAfterUp() {
        let harness = makeHarness(mappingApplyDelay: 0.25)

        harness.edge(isDown: true, at: 1_250.0)
        harness.edge(isDown: false, at: 1_250.050)
        let gestureID = harness.recognizer.currentGestureID!
        XCTAssertEqual(
            harness.controller.dualReceiverMappedTriggerState.phase,
            .armingSecondary(
                gestureID: gestureID,
                generation: harness.controller.dualReceiverMappedTriggerState.generation
            )
        )

        harness.edge(isDown: true, at: 1_250.200)

        XCTAssertEqual(
            harness.controller.dualReceiverMappedTriggerState.phase,
            .blockedUntilRelease(gestureID: gestureID)
        )
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.scheduler.advance(to: 1_250.551)
        harness.voicePress.setRemoteAudioAvailable()
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
        XCTAssertEqual(
            harness.controller.dualReceiverMappedTriggerState.phase,
            .blockedUntilRelease(gestureID: gestureID)
        )

        harness.edge(isDown: false, at: 1_250.600)
        guard case .restoringPrimary = harness.controller.dualReceiverMappedTriggerState.phase else {
            XCTFail("blocked second UP must begin restoring A")
            return
        }
        harness.edge(isDown: true, at: 1_250.700)
        XCTAssertEqual(harness.prewarmCount, 1)
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.dualReceiverMappedTriggerState.phase == .primaryReady
                && !harness.controller.voiceTriggerReconfigurationInProgress
                && harness.mappingApplyKeys.count == 3
        })
        XCTAssertEqual(
            harness.mappingApplyKeys,
            [.leftOption, .rightOption, .leftOption]
        )
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testSecondaryReadyBLongUsesHardwareGateAndNeverSyntheticTrigger() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 1_300.0)
        harness.edge(isDown: false, at: 1_300.050)
        awaitSecondaryReady(harness)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .rightOption)
        let gestureID = harness.recognizer.currentGestureID!
        let secondDownAt = 1_300.200
        harness.edge(isDown: true, at: secondDownAt)

        XCTAssertEqual(harness.hardwareGateBeginCount, 2)
        XCTAssertTrue(harness.hardwareGateIsActive)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.scheduler.advance(to: secondDownAt + 0.350)
        XCTAssertEqual(harness.recognizer.stateForTesting, .activeB)
        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertEqual(harness.hardwareGateLongReadyCount, 0)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteStreaming(true)
        XCTAssertEqual(harness.hardwareGateLongReadyCount, 0)
        harness.voicePress.setRemoteAudioAvailable()
        XCTAssertEqual(harness.hardwareGateLongReadyCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        let sessionID = harness.voicePress.currentGestureIDForDiagnostics!
        harness.edge(isDown: false, at: secondDownAt + 0.400)
        XCTAssertEqual(harness.hardwareGatePhysicalUpCount, 1)
        harness.voicePress.setRemoteStreaming(false)
        harness.completeOutputDrain(for: sessionID)
        XCTAssertEqual(harness.hardwareGateOutputDrainedCount, 1)
        XCTAssertEqual(gestureID, sessionID)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testSecondQuickReleaseCancelsPrewarmWithoutActivationOrRoute() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 300.0)
        harness.edge(isDown: false, at: 300.050)
        awaitSecondaryReady(harness)
        harness.edge(isDown: true, at: 300.200)
        harness.edge(isDown: false, at: 300.250)

        XCTAssertEqual(harness.prewarmCount, 1)
        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testSecondLongHoldClassifiesBAndActivatesAt350Milliseconds() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 400.0)
        harness.edge(isDown: false, at: 400.050)
        awaitSecondaryReady(harness)
        harness.edge(isDown: true, at: 400.200)

        XCTAssertEqual(harness.prewarmCount, 1)
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertEqual(
            harness.recognizer.stateForTesting,
            .secondPressPending
        )

        harness.scheduler.advance(to: 400.549)
        XCTAssertEqual(harness.activationCount, 0)

        harness.scheduler.advance(to: 400.550)
        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertEqual(harness.remoteRouted, true)
        XCTAssertEqual(harness.recognizer.stateForTesting, .activeB)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .holding)
        XCTAssertEqual(harness.cancelCount, 0)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.edge(isDown: false, at: 400.600)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertEqual(harness.stopVoiceInputCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testReleaseAtThresholdConsumesSynchronousClassificationWhenTimerWasDelayed() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 500.0)
        harness.edge(isDown: false, at: 500.350)

        XCTAssertEqual(harness.prewarmCount, 1)
        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertEqual(harness.cancelCount, 0)
        XCTAssertEqual(harness.stopVoiceInputCount, 1)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testClassifiedAUsesHardwareGateOnlyAfterFirstPCM() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 600.0)

        XCTAssertEqual(harness.hardwareGateBeginCount, 1)
        XCTAssertTrue(harness.hardwareGateIsActive)
        XCTAssertEqual(harness.hardwareGateLongReadyCount, 0)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.scheduler.advance(to: 600.350)

        XCTAssertEqual(harness.recognizer.stateForTesting, .activeA)
        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertTrue(harness.hardwareGateIsActive)
        XCTAssertEqual(harness.hardwareGateLongReadyCount, 0)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteStreaming(true)
        XCTAssertEqual(harness.hardwareGateLongReadyCount, 0)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteAudioAvailable()
        XCTAssertEqual(harness.hardwareGateLongReadyCount, 1)
        XCTAssertFalse(harness.hardwareGateIsActive)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        let sessionID = harness.voicePress.currentGestureIDForDiagnostics!
        harness.edge(isDown: false, at: 600.400)
        XCTAssertEqual(harness.hardwareGatePhysicalUpCount, 1)
        harness.voicePress.setRemoteStreaming(false)
        harness.completeOutputDrain(for: sessionID)
        XCTAssertEqual(harness.hardwareGateOutputDrainedCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.stop()
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testClassifiedBAndAudioStartWaitForFirstPCMThroughHardwareGate() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 700.0)
        harness.edge(isDown: false, at: 700.050)
        awaitSecondaryReady(harness)
        harness.edge(isDown: true, at: 700.200)
        XCTAssertEqual(harness.hardwareGateBeginCount, 2)
        XCTAssertTrue(harness.hardwareGateIsActive)
        harness.scheduler.advance(to: 700.551)

        XCTAssertEqual(harness.recognizer.stateForTesting, .activeB)
        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteStreaming(true)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteAudioAvailable()
        XCTAssertEqual(harness.hardwareGateLongReadyCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.stop()
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testClassifiedHoldReleasedWithoutFirstPCMEmitsNoReceiverEdges() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 800.0)
        harness.scheduler.advance(to: 800.350)
        harness.voicePress.setRemoteStreaming(true)

        XCTAssertTrue(harness.triggerEdges.isEmpty)
        harness.edge(isDown: false, at: 800.400)

        XCTAssertTrue(harness.triggerEdges.isEmpty)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(harness.remoteRouted, false)
    }

    func testABReceiverReleaseBalancesSelectedKeyAfterOutputDrain() throws {
        for receiver in [DualReceiverVoiceGestureRecognizer.Receiver.a, .b] {
            let harness = makeHarness()
            let downAt: TimeInterval = receiver == .a ? 900 : 1_000
            if receiver == .a {
                harness.edge(isDown: true, at: downAt)
                harness.scheduler.advance(to: downAt + 0.351)
            } else {
                harness.edge(isDown: true, at: downAt)
                harness.edge(isDown: false, at: downAt + 0.050)
                awaitSecondaryReady(harness)
                harness.edge(isDown: true, at: downAt + 0.200)
                harness.scheduler.advance(to: downAt + 0.551)
            }
            XCTAssertEqual(
                harness.recognizer.stateForTesting,
                receiver == .a ? .activeA : .activeB
            )

            harness.voicePress.setRemoteStreaming(true)
            harness.voicePress.setRemoteAudioAvailable()
            let sessionID = try XCTUnwrap(
                harness.voicePress.currentGestureIDForDiagnostics
            )
            XCTAssertEqual(harness.hardwareGateLongReadyCount, 1)
            XCTAssertTrue(harness.triggerEdges.isEmpty)

            harness.edge(isDown: false, at: downAt + 0.700)
            harness.voicePress.setRemoteStreaming(false)
            XCTAssertEqual(harness.hardwareGatePhysicalUpCount, 1)
            XCTAssertTrue(harness.triggerEdges.isEmpty)

            harness.completeOutputDrain(for: sessionID)
            XCTAssertEqual(harness.hardwareGateOutputDrainedCount, 1)
            XCTAssertTrue(harness.triggerEdges.isEmpty)
            XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        }
    }

    func testHIDDisconnectWhilePendingCancelsRecognizerAndPrewarm() {
        let harness = makeHarness()
        harness.edge(isDown: true, at: 1_100)

        XCTAssertEqual(harness.prewarmCount, 1)
        XCTAssertEqual(harness.hardwareGateBeginCount, 1)
        harness.controller.cancelDualReceiverGestureStateForHIDRemoval()
        XCTAssertEqual(harness.hardwareGateCancelCount, 1)
        harness.voicePress.handleTransportLoss(deviceRemoved: true)

        XCTAssertEqual(harness.cancelCount, 1)
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.recognizer.stateForTesting, .idle)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertFalse(harness.remoteRouted)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testHIDDisconnectDuringActiveAUsesHardwareOwnerWithoutSyntheticEdges() {
        let harness = makeHarness()
        harness.edge(isDown: true, at: 1_200)
        harness.scheduler.advance(to: 1_200.351)
        harness.voicePress.setRemoteAudioAvailable()

        XCTAssertEqual(harness.hardwareGateLongReadyCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
        harness.controller.cancelDualReceiverGestureStateForHIDRemoval()
        harness.voicePress.handleTransportLoss(deviceRemoved: true)

        XCTAssertTrue(harness.triggerEdges.isEmpty)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertFalse(harness.remoteRouted)

        harness.controller.cancelDualReceiverGestureStateForHIDRemoval()
        harness.voicePress.handleTransportLoss(deviceRemoved: true)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    private func makeHarness(
        mappingApplyDelay: TimeInterval = 0
    ) -> DualReceiverVoiceTransactionHarness {
        DualReceiverVoiceTransactionHarness(mappingApplyDelay: mappingApplyDelay)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func awaitSecondaryReady(
        _ harness: DualReceiverVoiceTransactionHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(waitUntil(timeout: 2) {
            if case .secondaryReady = harness.controller.dualReceiverMappedTriggerState.phase {
                return true
            }
            return false
        }, file: file, line: line)
    }
}

private final class DualReceiverVoiceTransactionHarness {
    private let mappingLock = NSLock()
    private var mappingApplyKeysStorage: [VoiceTriggerKey] = []
    private let mappingApplyDelay: TimeInterval
    let scheduler = TransactionTestScheduler()
    let voicePress: VoicePressCoordinator
    let recognizer: DualReceiverVoiceGestureRecognizer
    private let triggerRecorder = TransactionTriggerRecorder()
    private(set) var controller: AppController!
    private(set) var prewarmCount = 0
    private(set) var activationCount = 0
    private(set) var cancelCount = 0
    private(set) var stopVoiceInputCount = 0
    private(set) var hardwareGateBeginCount = 0
    private(set) var hardwareGateCancelCount = 0
    private(set) var hardwareGateLongReadyCount = 0
    private(set) var hardwareGatePhysicalUpCount = 0
    private(set) var hardwareGateOutputDrainedCount = 0
    private var outputDrainCompletions: [UUID: () -> Void] = [:]
    private var filter: VoiceKeyFilter!

    var triggerEdges: [String] { triggerRecorder.events }
    var mappingApplyKeys: [VoiceTriggerKey] {
        mappingLock.lock()
        defer { mappingLock.unlock() }
        return mappingApplyKeysStorage
    }
    var hardwareGateIsActive: Bool { filter.hasActiveHardwareTriggerOwnership }
    var remoteRouted: Bool {
        voicePress.diagnosticStateFields["remote_routed"] as? Bool ?? false
    }

    init(mappingApplyDelay: TimeInterval = 0) {
        self.mappingApplyDelay = mappingApplyDelay
        let trigger = VoiceOptionTrigger(keyedEventSink: { [triggerRecorder] key, isDown in
            triggerRecorder.append("\(key.rawValue):\(isDown ? "down" : "up")")
        })
        voicePress = VoicePressCoordinator(optionTrigger: trigger)
        recognizer = DualReceiverVoiceGestureRecognizer(
            monotonicNow: { [scheduler] in scheduler.now },
            schedule: { [scheduler] delay, work in scheduler.schedule(delay: delay, work: work) }
        )
        filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        controller = nil
        let applyMapping: (Bool, VoiceTriggerKey) -> Bool = { [unowned self] _, key in
            if self.mappingApplyDelay > 0 {
                Thread.sleep(forTimeInterval: self.mappingApplyDelay)
            }
            self.mappingLock.lock()
            self.mappingApplyKeysStorage.append(key)
            self.mappingLock.unlock()
            return true
        }
        controller = AppController(
            filter: filter,
            voicePress: voicePress,
            dualReceiverVoiceGestureRecognizer: recognizer,
            initiallyHIDConnected: true,
            isVoiceHIDMappingEnabled: { false },
            applyVoiceHIDMapping: applyMapping,
            rawHIDReadiness: { true },
            eventSuppressorReadiness: { true },
            prepareVoiceTransport: { [unowned self] in prewarmCount += 1 },
            activateVoiceInput: { [unowned self] in activationCount += 1 },
            cancelVoiceTransportPreparation: { [unowned self] in cancelCount += 1 },
            stopVoiceInput: { [unowned self] in stopVoiceInputCount += 1 }
        )
        voicePress.onRemoteOutputDrain = { [unowned self] sessionID, completion in
            outputDrainCompletions[sessionID] = completion
        }
        voicePress.onHardwareOptionGateBegin = { [unowned self] sessionID in
            hardwareGateBeginCount += 1
            filter.beginOptionDeferral(gestureID: sessionID)
        }
        voicePress.onHardwareOptionGateCancel = { [unowned self] sessionID in
            hardwareGateCancelCount += 1
            filter.cancelDeferredOption(gestureID: sessionID, reason: "transaction-test")
        }
        voicePress.onHardwareOptionGateLongReady = { [unowned self] sessionID in
            hardwareGateLongReadyCount += 1
            filter.releaseDeferredOption(gestureID: sessionID, reason: "transaction-test-ready")
        }
        voicePress.onHardwareOptionGatePhysicalUp = { [unowned self] sessionID in
            hardwareGatePhysicalUpCount += 1
            filter.armHardwareOptionRelease(gestureID: sessionID)
        }
        voicePress.onHardwareOptionGateOutputDrained = { [unowned self] sessionID in
            hardwareGateOutputDrainedCount += 1
            filter.releaseHeldHardwareOption(gestureID: sessionID, reason: "transaction-test-drain")
        }
        XCTAssertEqual(
            controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
    }

    func edge(isDown: Bool, at timestamp: TimeInterval) {
        scheduler.setNow(timestamp)
        controller.handleDualReceiverMicrophoneEdge(isDown: isDown, at: timestamp)
    }

    func completeOutputDrain(for sessionID: UUID) {
        let completion = outputDrainCompletions.removeValue(forKey: sessionID)
        completion?()
    }
}

private final class TransactionTestScheduler {
    private struct Work {
        let id: UUID
        let deadline: TimeInterval
        let action: () -> Void
        var isCancelled = false
    }

    private(set) var now: TimeInterval = 0
    private var work: [Work] = []

    func setNow(_ timestamp: TimeInterval) {
        now = timestamp
    }

    func schedule(delay: TimeInterval, work action: @escaping () -> Void) -> () -> Void {
        let id = UUID()
        work.append(Work(id: id, deadline: now + delay, action: action))
        return { [weak self] in self?.cancel(id: id) }
    }

    func advance(to timestamp: TimeInterval) {
        now = timestamp
        while let index = work.indices
            .filter({ !work[$0].isCancelled && work[$0].deadline <= timestamp })
            .min(by: { work[$0].deadline < work[$1].deadline }) {
            let scheduled = work.remove(at: index)
            scheduled.action()
        }
        work.removeAll(where: \.isCancelled)
    }

    private func cancel(id: UUID) {
        guard let index = work.firstIndex(where: { $0.id == id }) else { return }
        work[index].isCancelled = true
    }
}

private final class TransactionTriggerRecorder {
    private var storage: [String] = []
    var events: [String] { storage }
    func append(_ event: String) { storage.append(event) }
}
