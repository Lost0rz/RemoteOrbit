import Foundation
import XCTest
@testable import RemoteOrbit

final class DualReceiverVoiceSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RemoteOrbitTests.DualReceiverVoiceSettings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testSecondaryTriggerDefaultsOffAndIgnoresLegacyAndPersistentValues() {
        defaults.set(VoiceTriggerKey.leftCommand.rawValue, forKey: AppStorage.voiceTriggerKeyKey)
        defaults.set(
            VoiceTriggerKey.rightControl.rawValue,
            forKey: AppStorage.persistentSessionTriggerKeyKey
        )

        XCTAssertNil(AppStorage.readSecondaryMomentaryVoiceTriggerKey(from: defaults))
        XCTAssertEqual(defaults.string(forKey: AppStorage.voiceTriggerKeyKey), "left_command")
        XCTAssertEqual(
            defaults.string(forKey: AppStorage.persistentSessionTriggerKeyKey),
            "right_control"
        )
    }

    func testSecondaryTriggerRoundTripsAllSixKeysIndependently() {
        for key in VoiceTriggerKey.allCases {
            AppStorage.writeSecondaryMomentaryVoiceTriggerKey(key, to: defaults)

            XCTAssertEqual(
                defaults.string(forKey: AppStorage.secondaryMomentaryVoiceTriggerKeyKey),
                key.rawValue
            )
            XCTAssertEqual(AppStorage.readSecondaryMomentaryVoiceTriggerKey(from: defaults), key)
            XCTAssertNil(defaults.object(forKey: AppStorage.voiceTriggerKeyKey))
            XCTAssertNil(defaults.object(forKey: AppStorage.persistentSessionTriggerKeyKey))
        }
    }

    func testMissingOrInvalidSecondaryValueMeansOffAndWritingOffRemovesIt() {
        XCTAssertNil(AppStorage.readSecondaryMomentaryVoiceTriggerKey(from: defaults))

        defaults.set("not-a-trigger", forKey: AppStorage.secondaryMomentaryVoiceTriggerKeyKey)
        XCTAssertNil(AppStorage.readSecondaryMomentaryVoiceTriggerKey(from: defaults))

        AppStorage.writeSecondaryMomentaryVoiceTriggerKey(nil, to: defaults)
        XCTAssertNil(defaults.object(forKey: AppStorage.secondaryMomentaryVoiceTriggerKeyKey))
        XCTAssertNil(AppStorage.readSecondaryMomentaryVoiceTriggerKey(from: defaults))
    }

    func testDualModeRequiresDisabledShortAndDistinctReceiverKeys() {
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: false,
                receiverA: .leftOption,
                receiverB: .rightOption,
                rawHIDReady: true,
                eventSuppressorReady: true,
                mappingClearSucceeded: true
            ),
            .legacy
        )
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: true,
                receiverA: .leftOption,
                receiverB: .leftOption,
                rawHIDReady: true,
                eventSuppressorReady: true,
                mappingClearSucceeded: true
            ),
            .legacy
        )
    }
}
