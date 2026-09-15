import CoreGraphics
import XCTest
@testable import RemoteOrbit

final class VoiceSyntheticOptionObserverTests: XCTestCase {
    func testClassifiesSyntheticOptionFlagsAndKeyboardEdges() throws {
        let downFlags = try XCTUnwrap(
            VoiceSyntheticOptionObserver.classify(
                userData: Key.syntheticMarker,
                keyCode: VK.option,
                type: .flagsChanged,
                flags: .maskAlternate
            )
        )
        let downKey = try XCTUnwrap(
            VoiceSyntheticOptionObserver.classify(
                userData: Key.syntheticMarker,
                keyCode: VK.option,
                type: .keyDown,
                flags: .maskAlternate
            )
        )
        let upFlags = try XCTUnwrap(
            VoiceSyntheticOptionObserver.classify(
                userData: Key.syntheticMarker,
                keyCode: VK.option,
                type: .flagsChanged,
                flags: []
            )
        )
        let upKey = try XCTUnwrap(
            VoiceSyntheticOptionObserver.classify(
                userData: Key.syntheticMarker,
                keyCode: VK.option,
                type: .keyUp,
                flags: []
            )
        )

        XCTAssertEqual(downFlags, .init(direction: .down, component: .flags))
        XCTAssertEqual(downKey, .init(direction: .down, component: .key))
        XCTAssertEqual(upFlags, .init(direction: .up, component: .flags))
        XCTAssertEqual(upKey, .init(direction: .up, component: .key))
    }

    func testIgnoresNonSyntheticOrNonOptionEvents() {
        XCTAssertNil(
            VoiceSyntheticOptionObserver.classify(
                userData: 0,
                keyCode: VK.option,
                type: .keyDown,
                flags: .maskAlternate
            )
        )
        XCTAssertNil(
            VoiceSyntheticOptionObserver.classify(
                userData: Key.syntheticMarker,
                keyCode: VK.rightOption,
                type: .keyDown,
                flags: .maskAlternate
            )
        )
        XCTAssertNil(
            VoiceSyntheticOptionObserver.classify(
                userData: Key.syntheticMarker,
                keyCode: VK.option,
                type: .mouseMoved,
                flags: []
            )
        )
    }
}
