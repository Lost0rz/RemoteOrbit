import Foundation
import XCTest
@testable import RemoteOrbit

final class LegacyVoicePersistedPreferenceAuthorityContractTests: XCTestCase {
    func testAppStorageRetainsOnlyMomentaryCompatibilityAuthority() throws {
        let appStorage = try source("Sources/RemoteOrbit/AppStorage.swift")

        XCTAssertTrue(appStorage.contains("voiceTriggerKeyKey"))
        XCTAssertTrue(appStorage.contains("momentaryVoiceTriggerKeyKey"))
        for retiredAuthority in [
            "persistentSessionTriggerKeyKey",
            "secondaryMomentaryVoiceTriggerKeyKey",
            "persistentSessionTriggerKey",
            "secondaryMomentaryVoiceTriggerKey",
            "readPersistentSessionTriggerKey",
            "writePersistentSessionTriggerKey",
            "readSecondaryMomentaryVoiceTriggerKey",
            "writeSecondaryMomentaryVoiceTriggerKey"
        ] {
            XCTAssertFalse(
                appStorage.contains(retiredAuthority),
                "AppStorage still exposes retired authority: \(retiredAuthority)"
            )
        }
    }

    func testStartupAndRuntimeSeamsDoNotReadOrWriteRetiredPreferences() throws {
        let main = try source("Sources/RemoteOrbit/main.swift")

        for retiredCoupling in [
            "AppStorage.persistentSessionTriggerKey",
            "AppStorage.secondaryMomentaryVoiceTriggerKey",
            "readPersistedPersistentSessionTriggerKey",
            "persistPersistentSessionTriggerKey",
            "readPersistedSecondaryMomentaryVoiceTriggerKey",
            "persistSecondaryMomentaryVoiceTriggerKey",
            "persisted_persistent"
        ] {
            XCTAssertFalse(
                main.contains(retiredCoupling),
                "main.swift still couples production/runtime seams to retired preference: \(retiredCoupling)"
            )
        }

        XCTAssertFalse(main.contains("initialPersistentSessionTriggerKey"))
        XCTAssertTrue(main.contains("initialSecondaryMomentaryVoiceTriggerKey"))
        XCTAssertTrue(main.contains("VoiceInputProfileStore.persistedProfile"))
        XCTAssertTrue(main.contains("AppStorage.momentaryVoiceTriggerKey"))
    }

    func testStaleHistoricalBytesRemainUntouchedAndCannotSeedSelectedProfile() {
        let suiteName = "RemoteOrbitTests.LegacyVoicePersistedPreferenceAuthority.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let stalePersistentKey = "RemoteOrbit.persistentSessionTriggerKey"
        let staleReceiverBKey = "RemoteOrbit.secondaryMomentaryVoiceTriggerKey"
        defaults.set(VoiceTriggerKey.leftCommand.rawValue, forKey: stalePersistentKey)
        defaults.set(VoiceTriggerKey.rightCommand.rawValue, forKey: staleReceiverBKey)
        defaults.set(VoiceTriggerKey.rightControl.rawValue, forKey: AppStorage.voiceTriggerKeyKey)

        let profile = VoiceInputProfileStore.selectedProfile(from: defaults)

        XCTAssertEqual(profile.triggerKey, .rightControl)
        XCTAssertEqual(
            defaults.string(forKey: AppStorage.momentaryVoiceTriggerKeyKey),
            VoiceTriggerKey.rightControl.rawValue
        )
        XCTAssertEqual(defaults.string(forKey: stalePersistentKey), VoiceTriggerKey.leftCommand.rawValue)
        XCTAssertEqual(defaults.string(forKey: staleReceiverBKey), VoiceTriggerKey.rightCommand.rawValue)
    }

    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
