import Foundation

/// The low-frequency, user-selected voice-input destination. A profile is
/// configuration, not session state; a session captures one profile before it
/// emits its first trigger edge.
struct VoiceInputProfile: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let triggerKey: VoiceTriggerKey

    static let supported: [VoiceInputProfile] = [
        VoiceInputProfile(
            id: "system-left-option",
            displayName: "左 Option · 默认语音输入",
            triggerKey: .leftOption
        ),
        VoiceInputProfile(
            id: "system-right-option",
            displayName: "右 Option · 语音输入",
            triggerKey: .rightOption
        ),
        VoiceInputProfile(
            id: "system-left-control",
            displayName: "左 Control · 语音输入",
            triggerKey: .leftControl
        ),
        VoiceInputProfile(
            id: "system-right-control",
            displayName: "右 Control · 语音输入",
            triggerKey: .rightControl
        ),
        VoiceInputProfile(
            id: "system-left-command",
            displayName: "左 Command · 语音输入",
            triggerKey: .leftCommand
        ),
        VoiceInputProfile(
            id: "system-right-command",
            displayName: "右 Command · 语音输入",
            triggerKey: .rightCommand
        ),
    ]

    static let defaultProfile = supported[0]
}

enum VoiceInputProfileStore {
    static let selectedProfileIDKey = "RemoteOrbit.voiceInputProfileID"

    static func selectedProfile(from defaults: UserDefaults) -> VoiceInputProfile {
        if let rawID = defaults.string(forKey: selectedProfileIDKey),
           let profile = supportedProfile(withID: rawID) {
            return profile
        }

        // The old momentary trigger is the only legacy runtime preference
        // allowed to seed this authority. Persistent and receiver-B keys are
        // deliberately not consulted, so they cannot compete after migration.
        let legacyKey = AppStorage.readMomentaryVoiceTriggerKey(from: defaults)
        let profile = VoiceInputProfile.supported.first {
            $0.triggerKey == legacyKey
        } ?? .defaultProfile
        writeSelectedProfile(profile, to: defaults)
        return profile
    }

    static func writeSelectedProfile(
        _ profile: VoiceInputProfile,
        to defaults: UserDefaults
    ) {
        defaults.set(profile.id, forKey: selectedProfileIDKey)
        // Keep the old key as a compatibility projection for rollback and
        // older settings readers. Runtime voice ownership never reads it.
        AppStorage.writeMomentaryVoiceTriggerKey(profile.triggerKey, to: defaults)
    }

    static func migrate(from defaults: UserDefaults) {
        _ = selectedProfile(from: defaults)
    }

    static func persistedProfile(from defaults: UserDefaults) -> VoiceInputProfile? {
        guard let rawID = defaults.string(forKey: selectedProfileIDKey) else {
            return nil
        }
        return supportedProfile(withID: rawID)
    }

    static func profile(for triggerKey: VoiceTriggerKey) -> VoiceInputProfile {
        VoiceInputProfile.supported.first { $0.triggerKey == triggerKey } ?? .defaultProfile
    }

    private static func supportedProfile(withID id: String) -> VoiceInputProfile? {
        VoiceInputProfile.supported.first { $0.id == id }
    }
}
