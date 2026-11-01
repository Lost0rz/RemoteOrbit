import XCTest
@testable import RemoteOrbit

final class LegacyVoiceProductSurfaceContractTests: XCTestCase {
    func testSettingsSourceDoesNotOwnRetiredVoiceControls() throws {
        let settingsView = try source("Sources/RemoteOrbit/KeyMapping/SettingsView.swift")
        let settingsWindow = try source("Sources/RemoteOrbit/KeyMapping/SettingsWindow.swift")
        let main = try source("Sources/RemoteOrbit/main.swift")

        XCTAssertTrue(settingsView.contains("语音键 · 直接传输控制"))
        for retiredSurface in [
            "PersistentSessionTriggerKeyChangeHandler",
            "SecondaryVoiceTriggerKeyChangeHandler",
            "MicrophoneShortBindingChangeHandler",
            "VoiceSettingsRuntimeBridge",
            "MicrophoneShortInputMode",
            "microphoneSingleBehaviorCard",
            "microphoneSecondaryTriggerCard",
            "requestPersistentSessionTriggerKeyChange",
            "requestSecondaryVoiceTriggerKeyChange",
            "持续会话",
            "Receiver B"
        ] {
            XCTAssertFalse(
                settingsView.contains(retiredSurface),
                "SettingsView still owns retired surface: \(retiredSurface)"
            )
        }

        for retiredWiring in [
            "initialMomentaryVoiceTriggerKey",
            "initialPersistentSessionTriggerKey",
            "onVoiceTriggerChanged",
            "onPersistentSessionTriggerKeyChanged",
            "VoiceTriggerChangeHandler"
        ] {
            XCTAssertFalse(
                settingsWindow.contains(retiredWiring),
                "SettingsWindow still carries retired Settings-only wiring: \(retiredWiring)"
            )
        }

        for retiredBridge in [
            "VoiceSettingsRuntimeBridge",
            "onPersistentSessionTriggerKeyChanged",
            "initialPersistentSessionTriggerKey"
        ] {
            XCTAssertFalse(
                main.contains(retiredBridge),
                "main.swift still carries retired Settings-only bridge: \(retiredBridge)"
            )
        }
    }

    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
