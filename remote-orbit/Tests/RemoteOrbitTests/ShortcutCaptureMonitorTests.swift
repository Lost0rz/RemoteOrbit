import CoreGraphics
import XCTest
@testable import RemoteOrbit

final class ShortcutCaptureMonitorTests: XCTestCase {
    func testPlainKeyIsSuppressedAndCommitsAfterRelease() {
        var machine = ShortcutCaptureStateMachine()

        let down = machine.handle(.keyDown(keyCode: 0, keyLabel: "A", modifiers: [], isRepeat: false))
        XCTAssertTrue(down.shouldSuppress)
        XCTAssertEqual(down.phase, .chordFrozen)
        XCTAssertNil(down.committed)

        let up = machine.handle(.keyUp(keyCode: 0))
        XCTAssertTrue(up.shouldSuppress)
        XCTAssertEqual(up.committed, KeyChord(keyCode: 0, keyLabel: "A", modifiers: []))
        XCTAssertEqual(up.phase, .inactive)
    }

    func testCommandSpaceWaitsForModifierReleaseBeforeCommit() {
        var machine = ShortcutCaptureStateMachine()

        XCTAssertTrue(machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: true)).shouldSuppress)
        let spaceDown = machine.handle(.keyDown(keyCode: 49, keyLabel: "Space", modifiers: .command, isRepeat: false))
        XCTAssertTrue(spaceDown.shouldSuppress)
        XCTAssertEqual(spaceDown.preview, KeyChord(keyCode: 49, keyLabel: "Space", modifiers: .command))

        let spaceUp = machine.handle(.keyUp(keyCode: 49))
        XCTAssertTrue(spaceUp.shouldSuppress)
        XCTAssertNil(spaceUp.committed)

        let commandUp = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: false))
        XCTAssertTrue(commandUp.shouldSuppress)
        XCTAssertEqual(commandUp.committed, KeyChord(keyCode: 49, keyLabel: "Space", modifiers: .command))
    }

    func testCommandShiftFourFreezesExactChordAndCommitsAfterAllReleaseEdges() {
        var machine = ShortcutCaptureStateMachine()

        XCTAssertTrue(machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: true)).shouldSuppress)
        XCTAssertTrue(machine.handle(.flagsChanged(keyCode: 60, modifier: .shift, label: "⇧", isDown: true)).shouldSuppress)

        let down = machine.handle(.keyDown(
            keyCode: 21,
            keyLabel: "4",
            modifiers: [.command, .shift],
            isRepeat: false
        ))
        XCTAssertTrue(down.shouldSuppress)
        XCTAssertEqual(down.preview, KeyChord(keyCode: 21, keyLabel: "4", modifiers: [.command, .shift]))

        XCTAssertNil(machine.handle(.keyUp(keyCode: 21)).committed)
        XCTAssertNil(machine.handle(.flagsChanged(keyCode: 60, modifier: .shift, label: "⇧", isDown: false)).committed)
        let commit = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: false))
        XCTAssertTrue(commit.shouldSuppress)
        XCTAssertEqual(commit.committed, KeyChord(keyCode: 21, keyLabel: "4", modifiers: [.command, .shift]))
    }

    func testOptionAIsFullySuppressedAndCommitsAtReleaseBoundary() {
        var machine = ShortcutCaptureStateMachine()

        XCTAssertTrue(machine.handle(.flagsChanged(keyCode: 61, modifier: .option, label: "⌥", isDown: true)).shouldSuppress)
        XCTAssertTrue(machine.handle(.keyDown(keyCode: 0, keyLabel: "A", modifiers: .option, isRepeat: false)).shouldSuppress)
        XCTAssertNil(machine.handle(.keyUp(keyCode: 0)).committed)
        let commit = machine.handle(.flagsChanged(keyCode: 61, modifier: .option, label: "⌥", isDown: false))
        XCTAssertEqual(commit.committed, KeyChord(keyCode: 0, keyLabel: "A", modifiers: .option))
    }

    func testPureCommandCommitsOnceAfterCompleteModifierGesture() {
        var machine = ShortcutCaptureStateMachine()

        XCTAssertTrue(machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: true)).shouldSuppress)
        let commit = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: false))
        XCTAssertTrue(commit.shouldSuppress)
        XCTAssertEqual(commit.committed, KeyChord(keyCode: 55, keyLabel: "⌘", modifiers: []))
        XCTAssertEqual(commit.voiceCommitted, .pureModifier(.leftCommand))
    }

    func testVoiceChordRetainsExactLeftRightModifierCodesUntilReleaseCommit() {
        var machine = ShortcutCaptureStateMachine()

        _ = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: true))
        _ = machine.handle(.flagsChanged(keyCode: 61, modifier: .option, label: "⌥", isDown: true))
        _ = machine.handle(.keyDown(keyCode: 3, keyLabel: "F", modifiers: [.command, .option], isRepeat: false))
        _ = machine.handle(.keyUp(keyCode: 3))
        _ = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: false))
        let commit = machine.handle(.flagsChanged(keyCode: 61, modifier: .option, label: "⌥", isDown: false))

        XCTAssertEqual(
            commit.voiceCommitted,
            .chord(primaryKeyCode: 3, preview: "⌥⌘F", modifierKeyCodes: [55, 61])
        )
    }

    func testVoiceModifierOnlyChordRetainsSidesAndWaitsForEveryRelease() {
        var machine = ShortcutCaptureStateMachine(voiceCaptureEnabled: true)

        let optionDown = machine.handle(modifierInput(58, isDown: true))
        XCTAssertTrue(optionDown.shouldSuppress)
        XCTAssertEqual(optionDown.voicePreview, "左 Option")
        let commandDown = machine.handle(modifierInput(54, isDown: true))
        XCTAssertTrue(commandDown.shouldSuppress)
        XCTAssertEqual(commandDown.voicePreview, "左 Option + 右 Command")

        let firstRelease = machine.handle(modifierInput(54, isDown: false))
        XCTAssertTrue(firstRelease.shouldSuppress)
        XCTAssertNil(firstRelease.voiceCommitted)
        XCTAssertEqual(firstRelease.phase, .armed)

        let commit = machine.handle(modifierInput(58, isDown: false))
        XCTAssertTrue(commit.shouldSuppress)
        XCTAssertEqual(commit.voiceCommitted, .modifierChord(modifierKeyCodes: [54, 58]))
        XCTAssertNil(commit.committed, "modifier-only recording must not invent a primary key")
        XCTAssertTrue(commit.didStop)
    }

    func testVoiceModifierOnlyChordPressOrderDoesNotChangePhysicalIdentity() {
        var firstOrder = ShortcutCaptureStateMachine(voiceCaptureEnabled: true)
        _ = firstOrder.handle(modifierInput(55, isDown: true))
        _ = firstOrder.handle(modifierInput(58, isDown: true))
        _ = firstOrder.handle(modifierInput(58, isDown: false))
        let leftToRightRelease = firstOrder.handle(modifierInput(55, isDown: false))

        var reverseOrder = ShortcutCaptureStateMachine(voiceCaptureEnabled: true)
        _ = reverseOrder.handle(modifierInput(58, isDown: true))
        _ = reverseOrder.handle(modifierInput(55, isDown: true))
        _ = reverseOrder.handle(modifierInput(55, isDown: false))
        let rightToLeftRelease = reverseOrder.handle(modifierInput(58, isDown: false))

        XCTAssertEqual(
            leftToRightRelease.voiceCommitted,
            .modifierChord(modifierKeyCodes: [55, 58])
        )
        XCTAssertEqual(
            rightToLeftRelease.voiceCommitted?.physicalIdentity,
            leftToRightRelease.voiceCommitted?.physicalIdentity
        )
        XCTAssertEqual(leftToRightRelease.voiceCommitted?.sideDescription, "左 Option + 左 Command")
    }

    func testVoiceRecorderKeepsSingleModifierAndRegularChordPaths() {
        var machine = ShortcutCaptureStateMachine(voiceCaptureEnabled: true)
        _ = machine.handle(modifierInput(58, isDown: true))
        let pureModifier = machine.handle(modifierInput(58, isDown: false))
        XCTAssertEqual(pureModifier.voiceCommitted, .pureModifier(.leftOption))

        machine.reset()
        _ = machine.handle(modifierInput(58, isDown: true))
        _ = machine.handle(.keyDown(keyCode: 3, keyLabel: "F", modifiers: .option, isRepeat: false))
        _ = machine.handle(.keyUp(keyCode: 3))
        let ordinaryChord = machine.handle(modifierInput(58, isDown: false))
        XCTAssertEqual(
            ordinaryChord.voiceCommitted,
            .chord(primaryKeyCode: 3, preview: "⌥F", modifierKeyCodes: [58])
        )
    }

    func testGenericRecorderDoesNotCreateVoiceOnlyModifierChord() {
        var machine = ShortcutCaptureStateMachine()
        _ = machine.handle(modifierInput(58, isDown: true))
        _ = machine.handle(modifierInput(54, isDown: true))
        _ = machine.handle(modifierInput(58, isDown: false))
        let completed = machine.handle(modifierInput(54, isDown: false))

        XCTAssertEqual(completed.committed, KeyChord(keyCode: 58, keyLabel: "⌥", modifiers: []))
        XCTAssertNotEqual(completed.voiceCommitted, .modifierChord(modifierKeyCodes: [54, 58]))
    }

    func testEscapeCancellationDrainsOwnedChordWithoutCommit() {
        var machine = ShortcutCaptureStateMachine()

        _ = machine.handle(.flagsChanged(keyCode: 61, modifier: .option, label: "⌥", isDown: true))
        _ = machine.handle(.keyDown(keyCode: 3, keyLabel: "F", modifiers: .option, isRepeat: false))
        _ = machine.requestCancel()
        XCTAssertNil(machine.handle(.keyUp(keyCode: 3)).voiceCommitted)
        let release = machine.handle(.flagsChanged(keyCode: 61, modifier: .option, label: "⌥", isDown: false))

        XCTAssertTrue(release.didStop)
        XCTAssertNil(release.committed)
        XCTAssertNil(release.voiceCommitted)
    }

    func testAutorepeatIsSuppressedWithoutDuplicateCaptureOrCommit() {
        var machine = ShortcutCaptureStateMachine()

        _ = machine.handle(.keyDown(keyCode: 0, keyLabel: "A", modifiers: [], isRepeat: false))
        let repeatDecision = machine.handle(.keyDown(keyCode: 0, keyLabel: "A", modifiers: [], isRepeat: true))
        XCTAssertTrue(repeatDecision.shouldSuppress)
        XCTAssertNil(repeatDecision.committed)

        let commit = machine.handle(.keyUp(keyCode: 0))
        XCTAssertEqual(commit.committed, KeyChord(keyCode: 0, keyLabel: "A", modifiers: []))
        XCTAssertEqual(machine.handle(.keyUp(keyCode: 0)).committed, nil)
    }

    func testSyntheticEventPassesThroughWithoutChangingCaptureState() {
        var machine = ShortcutCaptureStateMachine()

        let synthetic = machine.handle(.synthetic)
        XCTAssertFalse(synthetic.shouldSuppress)
        XCTAssertEqual(synthetic.phase, .armed)
        XCTAssertNil(synthetic.committed)
    }

    func testPreHeldModifierWaitsForNeutralBeforeArming() {
        var machine = ShortcutCaptureStateMachine(initiallyHeldModifiers: .command)

        let leakedDown = machine.handle(.keyDown(keyCode: 49, keyLabel: "Space", modifiers: .command, isRepeat: false))
        XCTAssertFalse(leakedDown.shouldSuppress)
        XCTAssertNil(leakedDown.committed)

        let neutral = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: false))
        XCTAssertFalse(neutral.shouldSuppress)
        XCTAssertEqual(neutral.phase, .armed)

        XCTAssertTrue(machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: true)).shouldSuppress)
        XCTAssertTrue(machine.handle(.keyDown(keyCode: 49, keyLabel: "Space", modifiers: .command, isRepeat: false)).shouldSuppress)
        _ = machine.handle(.keyUp(keyCode: 49))
        let commit = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: false))
        XCTAssertEqual(commit.committed, KeyChord(keyCode: 49, keyLabel: "Space", modifiers: .command))
    }

    func testCancellationDrainsOwnedReleaseEdgesWithoutCommitting() {
        var machine = ShortcutCaptureStateMachine()

        _ = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: true))
        _ = machine.handle(.keyDown(keyCode: 49, keyLabel: "Space", modifiers: .command, isRepeat: false))
        let requested = machine.requestCancel()
        XCTAssertFalse(requested.didStop)

        let spaceUp = machine.handle(.keyUp(keyCode: 49))
        XCTAssertTrue(spaceUp.shouldSuppress)
        XCTAssertNil(spaceUp.committed)
        let commandUp = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: false))
        XCTAssertTrue(commandUp.shouldSuppress)
        XCTAssertTrue(commandUp.didStop)
        XCTAssertNil(commandUp.committed)
    }

    func testCancellationDrainsPureModifierReleaseWithoutCommitting() {
        var machine = ShortcutCaptureStateMachine()

        _ = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: true))
        XCTAssertFalse(machine.requestCancel().didStop)

        let release = machine.handle(.flagsChanged(keyCode: 55, modifier: .command, label: "⌘", isDown: false))
        XCTAssertTrue(release.shouldSuppress)
        XCTAssertTrue(release.didStop)
        XCTAssertNil(release.committed)
    }

    func testResetStartsAStateCleanSession() {
        var machine = ShortcutCaptureStateMachine()

        _ = machine.handle(.keyDown(keyCode: 0, keyLabel: "A", modifiers: [], isRepeat: false))
        XCTAssertNotNil(machine.handle(.keyUp(keyCode: 0)).committed)

        machine.reset()
        XCTAssertEqual(machine.phase, .armed)
        _ = machine.handle(.keyDown(keyCode: 11, keyLabel: "B", modifiers: [], isRepeat: false))
        let commit = machine.handle(.keyUp(keyCode: 11))
        XCTAssertEqual(commit.committed, KeyChord(keyCode: 11, keyLabel: "B", modifiers: []))
    }

    private func modifierInput(_ keyCode: UInt16, isDown: Bool) -> ShortcutCaptureInput {
        let modifier: KeyChord.Modifiers
        let label: String
        switch keyCode {
        case 54, 55: modifier = .command; label = "⌘"
        case 59, 62: modifier = .control; label = "⌃"
        case 58, 61: modifier = .option; label = "⌥"
        case 56, 60: modifier = .shift; label = "⇧"
        case 63: modifier = []; label = "Fn"
        default: fatalError("unexpected test modifier key code \(keyCode)")
        }
        return .flagsChanged(keyCode: keyCode, modifier: modifier, label: label, isDown: isDown)
    }
}
