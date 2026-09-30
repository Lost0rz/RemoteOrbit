import CoreGraphics
import Foundation
import IOKit.hidsystem
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
            [
                .leftOption,
                .rightOption,
                .leftControl,
                .rightControl,
                .leftCommand,
                .rightCommand,
            ]
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

    func testLeftCommandMetadataIsStable() {
        let key = VoiceTriggerKey.leftCommand

        XCTAssertEqual(key.rawValue, "left_command")
        XCTAssertEqual(key.displayName, "左 Command")
        XCTAssertEqual(key.hidUsage, 0xE3)
        XCTAssertEqual(key.hidutilDestination, 0x7000000E3)
        XCTAssertEqual(key.cgKeyCode, 55)
        XCTAssertEqual(key.cgEventFlag, .maskCommand)
    }

    func testRightCommandMetadataIsStable() {
        let key = VoiceTriggerKey.rightCommand

        XCTAssertEqual(key.rawValue, "right_command")
        XCTAssertEqual(key.displayName, "右 Command")
        XCTAssertEqual(key.hidUsage, 0xE7)
        XCTAssertEqual(key.hidutilDestination, 0x7000000E7)
        XCTAssertEqual(key.cgKeyCode, 54)
        XCTAssertEqual(key.cgEventFlag, .maskCommand)
    }

    func testSyntheticModifierFlagsPreserveDeviceSideIdentityForEveryKey() {
        let cases: [(
            key: VoiceTriggerKey,
            genericFlag: CGEventFlags,
            deviceSideFlag: CGEventFlags,
            oppositeDeviceSideFlag: CGEventFlags
        )] = [
            (
                .leftOption,
                .maskAlternate,
                CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK)),
                CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))
            ),
            (
                .rightOption,
                .maskAlternate,
                CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK)),
                CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
            ),
            (
                .leftControl,
                .maskControl,
                CGEventFlags(rawValue: UInt64(NX_DEVICELCTLKEYMASK)),
                CGEventFlags(rawValue: UInt64(NX_DEVICERCTLKEYMASK))
            ),
            (
                .rightControl,
                .maskControl,
                CGEventFlags(rawValue: UInt64(NX_DEVICERCTLKEYMASK)),
                CGEventFlags(rawValue: UInt64(NX_DEVICELCTLKEYMASK))
            ),
            (
                .leftCommand,
                .maskCommand,
                CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK)),
                CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))
            ),
            (
                .rightCommand,
                .maskCommand,
                CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK)),
                CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.key.cgEventFlag, testCase.genericFlag)
            XCTAssertEqual(testCase.key.deviceSideCGEventFlag, testCase.deviceSideFlag)
            XCTAssertTrue(testCase.key.syntheticModifierFlags.contains(testCase.genericFlag))
            XCTAssertTrue(testCase.key.syntheticModifierFlags.contains(testCase.deviceSideFlag))
            XCTAssertFalse(testCase.key.syntheticModifierFlags.contains(testCase.oppositeDeviceSideFlag))
            XCTAssertEqual(
                testCase.key.syntheticModifierFlags,
                testCase.genericFlag.union(testCase.deviceSideFlag)
            )
        }

        XCTAssertNotEqual(
            VoiceTriggerKey.leftOption.syntheticModifierFlags,
            VoiceTriggerKey.rightOption.syntheticModifierFlags
        )
        XCTAssertNotEqual(
            VoiceTriggerKey.leftControl.syntheticModifierFlags,
            VoiceTriggerKey.rightControl.syntheticModifierFlags
        )
        XCTAssertNotEqual(
            VoiceTriggerKey.leftCommand.syntheticModifierFlags,
            VoiceTriggerKey.rightCommand.syntheticModifierFlags
        )
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

        for key in [VoiceTriggerKey.leftCommand, .rightCommand] {
            AppStorage.writeVoiceTriggerKey(key, to: defaults)
            XCTAssertEqual(defaults.string(forKey: AppStorage.voiceTriggerKeyKey), key.rawValue)
            XCTAssertEqual(AppStorage.readVoiceTriggerKey(from: defaults), key)
        }
    }

    func testLegacyVoiceTriggerKeyMigratesToBothSemanticKeys() {
        defaults.set(VoiceTriggerKey.rightCommand.rawValue, forKey: AppStorage.voiceTriggerKeyKey)

        XCTAssertEqual(AppStorage.readPersistentSessionTriggerKey(from: defaults), .rightCommand)
        XCTAssertEqual(AppStorage.readMomentaryVoiceTriggerKey(from: defaults), .rightCommand)
        XCTAssertEqual(
            defaults.string(forKey: AppStorage.persistentSessionTriggerKeyKey),
            VoiceTriggerKey.rightCommand.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: AppStorage.momentaryVoiceTriggerKeyKey),
            VoiceTriggerKey.rightCommand.rawValue
        )
    }

    func testPersistentAndMomentaryTriggerKeysPersistIndependentlyAndKeepLegacyAlias() {
        AppStorage.writePersistentSessionTriggerKey(.leftCommand, to: defaults)
        AppStorage.writeMomentaryVoiceTriggerKey(.rightControl, to: defaults)

        XCTAssertEqual(AppStorage.readPersistentSessionTriggerKey(from: defaults), .leftCommand)
        XCTAssertEqual(AppStorage.readMomentaryVoiceTriggerKey(from: defaults), .rightControl)
        XCTAssertEqual(AppStorage.readVoiceTriggerKey(from: defaults), .rightControl)
        XCTAssertEqual(
            defaults.string(forKey: AppStorage.voiceTriggerKeyKey),
            VoiceTriggerKey.rightControl.rawValue
        )
    }
}
