import Foundation

/// The low-frequency, user-selected voice-input destination. A profile is
/// configuration, not session state; a session captures one profile before it
/// emits its first trigger edge.
struct VoiceInputProfile: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let binding: VoiceShortcutBinding

    /// Compatibility projection used only by the six legacy pure-modifier
    /// profiles. Chords deliberately have no synthetic/fake modifier value.
    var triggerKey: VoiceTriggerKey? { binding.pureModifierKey }

    init(id: String, displayName: String, binding: VoiceShortcutBinding) {
        self.id = id
        self.displayName = displayName
        self.binding = binding
    }

    init(id: String, displayName: String, triggerKey: VoiceTriggerKey) {
        self.init(id: id, displayName: displayName, binding: .pureModifier(triggerKey))
    }

    static let legacySeeds: [VoiceInputProfile] = [
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

    static let supported: [VoiceInputProfile] = legacySeeds

    static let defaultProfile = supported[0]

    static func profiles(from snapshot: VoiceShortcutSnapshot) -> [VoiceInputProfile] {
        snapshot.entries.map(\.profile)
    }
}

enum VoiceInputProfileStore {
    static let selectedProfileIDKey = "RemoteOrbit.voiceInputProfileID"

    static func selectedProfile(from defaults: UserDefaults) -> VoiceInputProfile {
        let loaded = VoiceShortcutStore.load(from: defaults)
        return loaded.snapshot.activeEntry?.profile ?? .defaultProfile
    }

    static func writeSelectedProfile(
        _ profile: VoiceInputProfile,
        to defaults: UserDefaults
    ) {
        let loaded = VoiceShortcutStore.load(from: defaults)
        guard loaded.isWritable else { return }
        var snapshot = loaded.snapshot
        guard snapshot.entries.contains(where: { $0.id == profile.id }) else { return }
        snapshot.activeEntryID = profile.id
        do {
            try VoiceShortcutStore.persist(snapshot, to: defaults)
            defaults.set(profile.id, forKey: selectedProfileIDKey)
            if let key = profile.triggerKey {
                AppStorage.writeMomentaryVoiceTriggerKey(key, to: defaults)
            }
        } catch {
            return
        }
    }

    static func migrate(from defaults: UserDefaults) {
        VoiceShortcutStore.migrate(from: defaults)
    }

    static func persistedProfile(from defaults: UserDefaults) -> VoiceInputProfile? {
        VoiceShortcutStore.load(from: defaults).snapshot.activeEntry?.profile
    }

    static func profile(for triggerKey: VoiceTriggerKey) -> VoiceInputProfile {
        VoiceInputProfile.supported.first { $0.triggerKey == triggerKey } ?? .defaultProfile
    }

}
