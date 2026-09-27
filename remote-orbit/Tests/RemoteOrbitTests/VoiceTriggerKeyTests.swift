import CoreGraphics
import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceTriggerKeyTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RemoteOrbitTests.VoiceTriggerKey.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAllCasesUseTheFrozenContractOrder() {
        XCTAssertEqual(
            VoiceTriggerKey.allCases,
            [.leftOption, .rightOption, .leftControl, .rightControl]
        )
    }

    func testDefaultValueIsLeftOption() {
        XCTAssertEqual(VoiceTriggerKey.defaultValue, .leftOption)
    }

    func testLeftOptionMetadataIsStable() {
        let key = VoiceTriggerKey.leftOption

        XCTAssertEqual(key.rawValue, "left_option")
        XCTAssertEqual(key.displayName, "左 Option")
        XCTAssertEqual(key.hidUsage, 0xE2)
        XCTAssertEqual(key.hidutilDestination, 0x7000000E2)
        XCTAssertEqual(key.cgKeyCode, 58)
        XCTAssertEqual(key.cgEventFlag, .maskAlternate)
    }

    func testRightOptionMetadataIsStable() {
        let key = VoiceTriggerKey.rightOption

        XCTAssertEqual(key.rawValue, "right_option")
        XCTAssertEqual(key.displayName, "右 Option")
        XCTAssertEqual(key.hidUsage, 0xE6)
        XCTAssertEqual(key.hidutilDestination, 0x7000000E6)
        XCTAssertEqual(key.cgKeyCode, 61)
        XCTAssertEqual(key.cgEventFlag, .maskAlternate)
    }

    func testLeftControlMetadataIsStable() {
        let key = VoiceTriggerKey.leftControl

        XCTAssertEqual(key.rawValue, "left_control")
        XCTAssertEqual(key.displayName, "左 Control")
        XCTAssertEqual(key.hidUsage, 0xE0)
        XCTAssertEqual(key.hidutilDestination, 0x7000000E0)
        XCTAssertEqual(key.cgKeyCode, 59)
        XCTAssertEqual(key.cgEventFlag, .maskControl)
    }

    func testRightControlMetadataIsStable() {
        let key = VoiceTriggerKey.rightControl

        XCTAssertEqual(key.rawValue, "right_control")
        XCTAssertEqual(key.displayName, "右 Control")
        XCTAssertEqual(key.hidUsage, 0xE4)
        XCTAssertEqual(key.hidutilDestination, 0x7000000E4)
        XCTAssertEqual(key.cgKeyCode, 62)
        XCTAssertEqual(key.cgEventFlag, .maskControl)
    }

    func testCodableRoundTripPreservesEverySupportedKey() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for key in VoiceTriggerKey.allCases {
            let data = try encoder.encode(key)
            XCTAssertEqual(try decoder.decode(VoiceTriggerKey.self, from: data), key)
        }
    }

    func testInvalidStoredRawValueFallsBackToLeftOption() {
        defaults.set("foobar", forKey: AppStorage.voiceTriggerKeyKey)

        XCTAssertEqual(AppStorage.readVoiceTriggerKey(from: defaults), .leftOption)
    }

    func testIsolatedDefaultsWithoutStoredValueUseLeftOption() {
        XCTAssertEqual(AppStorage.readVoiceTriggerKey(from: defaults), .leftOption)
    }

    func testIsolatedDefaultsPersistVoiceTriggerKey() {
        AppStorage.writeVoiceTriggerKey(.rightControl, to: defaults)
        XCTAssertEqual(AppStorage.readVoiceTriggerKey(from: defaults), .rightControl)

        AppStorage.writeVoiceTriggerKey(.rightOption, to: defaults)
        XCTAssertEqual(AppStorage.readVoiceTriggerKey(from: defaults), .rightOption)
    }
}
