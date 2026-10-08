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
        XCTAssertEqual(harness.activationCount, 0)
        XCTAssertEqual(harness.remoteRouted, false)
        XCTAssertEqual(harness.voicePress.currentStateForTesting, .idle)
        XCTAssertTrue(harness.triggerEdges.isEmpty)
    }

    func testSecondQuickReleaseCancelsPrewarmWithoutActivationOrRoute() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 300.0)
        harness.edge(isDown: false, at: 300.050)
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

    func testClassifiedAAndAudioStartWaitForFirstPCMBeforeLeftOptionDown() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 600.0)
        harness.scheduler.advance(to: 600.350)

        XCTAssertEqual(harness.recognizer.stateForTesting, .activeA)
        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteStreaming(true)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteAudioAvailable()
        XCTAssertEqual(harness.triggerEdges, ["left_option:down"])

        harness.voicePress.stop()
        XCTAssertEqual(harness.triggerEdges, ["left_option:down", "left_option:up"])
    }

    func testClassifiedBAndAudioStartWaitForFirstPCMBeforeRightOptionDown() {
        let harness = makeHarness()

        harness.edge(isDown: true, at: 700.0)
        harness.edge(isDown: false, at: 700.050)
        harness.edge(isDown: true, at: 700.200)
        harness.scheduler.advance(to: 700.551)

        XCTAssertEqual(harness.recognizer.stateForTesting, .activeB)
        XCTAssertEqual(harness.activationCount, 1)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteStreaming(true)
        XCTAssertTrue(harness.triggerEdges.isEmpty)

        harness.voicePress.setRemoteAudioAvailable()
        XCTAssertEqual(harness.triggerEdges, ["right_option:down"])

        harness.voicePress.stop()
        XCTAssertEqual(harness.triggerEdges, ["right_option:down", "right_option:up"])
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

    private func makeHarness() -> DualReceiverVoiceTransactionHarness {
        DualReceiverVoiceTransactionHarness()
    }
}

private final class DualReceiverVoiceTransactionHarness {
    let scheduler = TransactionTestScheduler()
    let voicePress: VoicePressCoordinator
    let recognizer: DualReceiverVoiceGestureRecognizer
    private let triggerRecorder = TransactionTriggerRecorder()
    private(set) var controller: AppController!
    private(set) var prewarmCount = 0
    private(set) var activationCount = 0
    private(set) var cancelCount = 0
    private(set) var stopVoiceInputCount = 0

    var triggerEdges: [String] { triggerRecorder.events }
    var remoteRouted: Bool {
        voicePress.diagnosticStateFields["remote_routed"] as? Bool ?? false
    }

    init() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { [triggerRecorder] key, isDown in
            triggerRecorder.append("\(key.rawValue):\(isDown ? "down" : "up")")
        })
        voicePress = VoicePressCoordinator(optionTrigger: trigger)
        recognizer = DualReceiverVoiceGestureRecognizer(
            monotonicNow: { [scheduler] in scheduler.now },
            schedule: { [scheduler] delay, work in scheduler.schedule(delay: delay, work: work) }
        )
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        controller = nil
        controller = AppController(
            filter: filter,
            voicePress: voicePress,
            dualReceiverVoiceGestureRecognizer: recognizer,
            initiallyHIDConnected: true,
            isVoiceHIDMappingEnabled: { false },
            applyVoiceHIDMapping: { _, _ in true },
            rawHIDReadiness: { true },
            eventSuppressorReadiness: { true },
            prepareVoiceTransport: { [unowned self] in prewarmCount += 1 },
            activateVoiceInput: { [unowned self] in activationCount += 1 },
            cancelVoiceTransportPreparation: { [unowned self] in cancelCount += 1 },
            stopVoiceInput: { [unowned self] in stopVoiceInputCount += 1 }
        )
        voicePress.onRemoteOutputDrain = { _, completion in completion() }
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
