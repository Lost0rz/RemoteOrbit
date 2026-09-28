import XCTest
@testable import RemoteOrbit

final class RemoteVoiceKeyMappingTests: XCTestCase {
    func testLeftOptionMappingUsesTheFrozenDestination() {
        XCTAssertEqual(
            RemoteVoiceKeyMapping.mappingJSON(for: .leftOption),
            "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000003E,\"HIDKeyboardModifierMappingDst\":0x7000000E2}]}"
        )
    }

    func testRightOptionMappingUsesTheFrozenDestination() {
        XCTAssertEqual(
            RemoteVoiceKeyMapping.mappingJSON(for: .rightOption),
            "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000003E,\"HIDKeyboardModifierMappingDst\":0x7000000E6}]}"
        )
    }

    func testLeftControlMappingUsesTheFrozenDestination() {
        XCTAssertEqual(
            RemoteVoiceKeyMapping.mappingJSON(for: .leftControl),
            "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000003E,\"HIDKeyboardModifierMappingDst\":0x7000000E0}]}"
        )
    }

    func testRightControlMappingUsesTheFrozenDestination() {
        XCTAssertEqual(
            RemoteVoiceKeyMapping.mappingJSON(for: .rightControl),
            "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000003E,\"HIDKeyboardModifierMappingDst\":0x7000000E4}]}"
        )
    }

    func testLeftCommandMappingUsesTheFrozenDestination() {
        XCTAssertEqual(
            RemoteVoiceKeyMapping.mappingJSON(for: .leftCommand),
            "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000003E,\"HIDKeyboardModifierMappingDst\":0x7000000E3}]}"
        )
    }

    func testRightCommandMappingUsesTheFrozenDestination() {
        XCTAssertEqual(
            RemoteVoiceKeyMapping.mappingJSON(for: .rightCommand),
            "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000003E,\"HIDKeyboardModifierMappingDst\":0x7000000E7}]}"
        )
    }

    func testEmptyMappingRemainsUnchanged() {
        XCTAssertEqual(
            RemoteVoiceKeyMapping.emptyMappingJSON,
            "{\"UserKeyMapping\":[]}"
        )
    }
}
