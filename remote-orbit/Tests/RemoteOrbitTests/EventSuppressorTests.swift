import AppKit
import CoreGraphics
import XCTest
@testable import RemoteOrbit

final class EventSuppressorTests: XCTestCase {
    func testUnrelatedVolumeDownPassesWhileRemoteIsConnectedWithoutVolumeHID() throws {
        let suppressor = EventSuppressor()
        suppressor.setRemotePowerSuppressionEnabled(true)

        XCTAssertFalse(try handleSystemKey(1, edge: .down, with: suppressor))
    }

    func testUnrelatedVolumeUpPassesWhileRemoteIsConnectedWithoutVolumeHID() throws {
        let suppressor = EventSuppressor()
        suppressor.setRemotePowerSuppressionEnabled(true)

        XCTAssertFalse(try handleSystemKey(0, edge: .down, with: suppressor))
    }

    func testMutePassesWhileRemoteIsConnected() throws {
        let suppressor = EventSuppressor()
        suppressor.setRemotePowerSuppressionEnabled(true)

        XCTAssertFalse(try handleSystemKey(7, edge: .down, with: suppressor))
    }

    func testRemoteVolumeDownIsSuppressedWhileHIDButtonIsHeld() throws {
        let suppressor = EventSuppressor()
        suppressor.updateHeld(button: .volumeDown, isDown: true)

        XCTAssertTrue(try handleSystemKey(1, edge: .down, with: suppressor))
    }

    func testRemoteVolumeUpIsSuppressedWhileHIDButtonIsHeld() throws {
        let suppressor = EventSuppressor()
        suppressor.updateHeld(button: .volumeUp, isDown: true)

        XCTAssertTrue(try handleSystemKey(0, edge: .down, with: suppressor))
    }

    func testOppositeVolumeEventPassesWhileRemoteVolumeUpIsHeld() throws {
        let suppressor = EventSuppressor()
        suppressor.updateHeld(button: .volumeUp, isDown: true)

        XCTAssertFalse(try handleSystemKey(1, edge: .down, with: suppressor))
    }

    func testMatchingNativeVolumeDownKeyUpIsSuppressedAfterRemoteOwnedDown() throws {
        let suppressor = EventSuppressor()
        suppressor.updateHeld(button: .volumeDown, isDown: true)
        XCTAssertTrue(try handleSystemKey(1, edge: .down, with: suppressor))

        suppressor.updateHeld(button: .volumeDown, isDown: false)
        XCTAssertTrue(try handleSystemKey(1, edge: .up, with: suppressor))
    }

    func testNativeVolumeDownKeyUpPassesWhenItsDownWasNotSuppressed() throws {
        let suppressor = EventSuppressor()
        XCTAssertFalse(try handleSystemKey(1, edge: .down, with: suppressor))

        suppressor.updateHeld(button: .volumeDown, isDown: false)
        XCTAssertFalse(try handleSystemKey(1, edge: .up, with: suppressor))
    }

    func testRemoteMicrophoneF5PairIsParkedWithoutSuppressingUnrelatedKeys() throws {
        let suppressor = EventSuppressor()
        suppressor.updateHeld(button: .microphone, isDown: true)

        let f5Down = try keyboardEvent(keyCode: 96, isDown: true)
        XCTAssertTrue(suppressor.handle(type: .keyDown, event: f5Down))

        suppressor.updateHeld(button: .microphone, isDown: false)
        let f5Up = try keyboardEvent(keyCode: 96, isDown: false)
        XCTAssertTrue(suppressor.handle(type: .keyUp, event: f5Up))

        let unrelatedDown = try keyboardEvent(keyCode: 59, isDown: true)
        let unrelatedUp = try keyboardEvent(keyCode: 59, isDown: false)
        XCTAssertFalse(suppressor.handle(type: .keyDown, event: unrelatedDown))
        XCTAssertFalse(suppressor.handle(type: .keyUp, event: unrelatedUp))
    }

    private func handleSystemKey(
        _ keyType: Int32,
        edge: RemoteEventEdge,
        with suppressor: EventSuppressor
    ) throws -> Bool {
        let keyState = edge == .down ? 0xA : 0xB
        let data1 = (Int(keyType) << 16) | (keyState << 8)
        let nsEvent = try XCTUnwrap(NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: 0
        ))
        let cgEvent = try XCTUnwrap(nsEvent.cgEvent)
        return suppressor.handle(type: cgEvent.type, event: cgEvent)
    }

    private func keyboardEvent(keyCode: CGKeyCode, isDown: Bool) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: isDown
        ))
    }
}
