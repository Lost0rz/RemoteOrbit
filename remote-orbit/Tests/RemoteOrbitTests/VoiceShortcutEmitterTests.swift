import CoreGraphics
import XCTest
@testable import RemoteOrbit

final class VoiceShortcutEmitterTests: XCTestCase {
    func testCoordinatorWaitsForLongPromotionAndOutputDrainBeforeChordRelease() {
        let sink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(sink: sink)
        var syntheticOptionEvents: [(VoiceTriggerKey, Bool)] = []
        let optionTrigger = VoiceOptionTrigger(
            keyedEventSink: { syntheticOptionEvents.append(($0, $1)) }
        )
        var promoteCandidate: (() -> Void)?
        var drainOutput: (() -> Void)?
        let press = VoicePressCoordinator(
            optionTrigger: optionTrigger,
            voiceShortcutEmitter: emitter,
            candidateTimerFactory: { _, fire in
                promoteCandidate = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        let profile = VoiceInputProfile(
            id: "custom-option-f",
            displayName: "Option + F",
            binding: .chord(primaryKeyCode: 3, preview: "⌥F", modifierKeyCodes: [61])
        )

        XCTAssertTrue(press.keyDown(sessionID: UUID(), profile: profile))
        XCTAssertTrue(press.keyUp())
        XCTAssertTrue(sink.events.isEmpty)
        XCTAssertTrue(syntheticOptionEvents.isEmpty)

        XCTAssertTrue(press.keyDown(sessionID: UUID(), usesHardwareOption: true, profile: profile))
        promoteCandidate?()
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .keyDown])
        XCTAssertTrue(syntheticOptionEvents.isEmpty)
        press.onRemoteOutputDrain = { _, completion in drainOutput = completion }
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)

        XCTAssertEqual(sink.events.count, 2, "release must wait for the output-drain callback")
        drainOutput?()
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(sink.events.map(\.keyCode), [61, 3, 3, 61])
        XCTAssertTrue(syntheticOptionEvents.isEmpty)
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)
        press.stop()
    }

    func testChordEdgesUseFixedModifierOrderAndReverseReleaseAfterPrimary() {
        let sink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(sink: sink)
        let sessionID = UUID()
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3,
            preview: "右 Command + 右 Option + F",
            modifierKeyCodes: [61, 54]
        )

        XCTAssertTrue(emitter.begin(sessionID: sessionID, binding: binding))
        XCTAssertEqual(sink.events.map(\.keyCode), [61, 54, 3])
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .flagsChanged, .keyDown])
        XCTAssertTrue(sink.events[0].flags & CGEventFlags.maskAlternate.rawValue != 0)
        XCTAssertTrue(sink.events[1].flags & CGEventFlags.maskCommand.rawValue != 0)

        XCTAssertTrue(emitter.end(sessionID: sessionID))
        XCTAssertEqual(sink.events.map(\.keyCode), [61, 54, 3, 3, 54, 61])
        XCTAssertEqual(sink.events.map(\.kind), [
            .flagsChanged, .flagsChanged, .keyDown,
            .keyUp, .flagsChanged, .flagsChanged,
        ])
        XCTAssertEqual(sink.events[3].flags, sink.events[2].flags)
        XCTAssertFalse(sink.events[4].flags & CGEventFlags.maskCommand.rawValue != 0)
        XCTAssertTrue(sink.events[4].flags & CGEventFlags.maskAlternate.rawValue != 0)
        XCTAssertEqual(sink.events[5].flags, 0)
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)
    }

    func testPartialPrimaryConstructionFailureCompensatesOwnedModifier() {
        let sink = RecordingVoiceShortcutSink(failingCallIndexes: [1])
        let emitter = VoiceShortcutEmitter(sink: sink)
        let sessionID = UUID()

        XCTAssertFalse(emitter.begin(
            sessionID: sessionID,
            binding: .chord(primaryKeyCode: 3, preview: "⌘F", modifierKeyCodes: [55])
        ))
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .flagsChanged])
        XCTAssertEqual(sink.events.map(\.keyCode), [55, 55])
        XCTAssertEqual(sink.events.last?.flags, 0)
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)
    }

    func testLateDrainForRetiredSessionCannotReleaseNewOwner() {
        let sink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(sink: sink)
        let first = UUID()
        let second = UUID()
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3,
            preview: "⌥F",
            modifierKeyCodes: [58]
        )

        XCTAssertTrue(emitter.begin(sessionID: first, binding: binding))
        XCTAssertTrue(emitter.end(sessionID: first))
        XCTAssertTrue(emitter.begin(sessionID: second, binding: binding))
        let beforeLateEnd = sink.events

        XCTAssertFalse(emitter.end(sessionID: first))
        XCTAssertEqual(sink.events, beforeLateEnd)
        XCTAssertEqual(emitter.ownedSessionIDs, [second])
        XCTAssertTrue(emitter.abort(sessionID: second))
    }
}

private final class RecordingVoiceShortcutSink: VoiceShortcutEventSink {
    private(set) var events: [VoiceShortcutSyntheticEvent] = []
    private let failingCallIndexes: Set<Int>
    private var callIndex = 0

    init(failingCallIndexes: Set<Int> = []) {
        self.failingCallIndexes = failingCallIndexes
    }

    func post(_ event: VoiceShortcutSyntheticEvent) -> Bool {
        defer { callIndex += 1 }
        guard !failingCallIndexes.contains(callIndex) else { return false }
        events.append(event)
        return true
    }
}
