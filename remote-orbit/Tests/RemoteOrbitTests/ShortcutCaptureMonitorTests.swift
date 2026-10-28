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
}
