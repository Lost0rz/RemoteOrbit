import Foundation

enum AppStorage {
    static let loggingEnabledKey = "RemoteOrbit.loggingEnabled"
    static let recordingEnabledKey = "RemoteOrbit.recordingEnabled"
    /// Legacy preference retained as the compatibility alias for the
    /// momentary remote-microphone trigger.
    static let voiceTriggerKeyKey = "RemoteOrbit.voiceTriggerKey"
    static let momentaryVoiceTriggerKeyKey = "RemoteOrbit.momentaryVoiceTriggerKey"

    static let logsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RemoteOrbit", isDirectory: true)
    }()

    static let logFile = logsDirectory.appendingPathComponent("RemoteOrbit.log")

    static let recordingsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/RemoteOrbit/Recordings",
                isDirectory: true
            )
    }()

    /// Canonical user-owned configuration storage. Keep this outside the app
    /// bundle so replacing `/Applications/RemoteOrbit.app` cannot replace or
    /// reset the user's mappings.
    static let configurationDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/RemoteOrbit/Configuration",
                isDirectory: true
            )
    }()

    static let mappingConfigurationFile = configurationDirectory
        .appendingPathComponent("mapping-v3.json")

    static func prepare() {
        migrateVoiceTriggerKeys(from: UserDefaults.standard)
        VoiceShortcutStore.migrate(from: UserDefaults.standard)
        UserDefaults.standard.register(defaults: [
            loggingEnabledKey: false,
            recordingEnabledKey: false,
            voiceTriggerKeyKey: VoiceTriggerKey.defaultValue.rawValue,
            VoiceInputProfileStore.selectedProfileIDKey:
                VoiceInputProfile.defaultProfile.id,
        ])
        DiagnosticsRuntimeGate.shared.configureFromProcessEnvironment(
            loggingEnabled: loggingEnabled
        )
        ensureDirectory(logsDirectory)
        ensureDirectory(recordingsDirectory)
        ensureDirectory(configurationDirectory)

        // The app uses ~/Library/Logs as its single persistent log location.
        try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: "/tmp/remote-orbit.log")
        )
    }

    static var loggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: loggingEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: loggingEnabledKey)
            DiagnosticsRuntimeGate.shared.setLoggingEnabled(newValue)
        }
    }

    static var recordingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: recordingEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingEnabledKey) }
    }

    static var voiceTriggerKey: VoiceTriggerKey {
        get { readMomentaryVoiceTriggerKey(from: UserDefaults.standard) }
        set { writeVoiceTriggerKey(newValue, to: UserDefaults.standard) }
    }

    static var momentaryVoiceTriggerKey: VoiceTriggerKey {
        get { readMomentaryVoiceTriggerKey(from: UserDefaults.standard) }
        set { writeMomentaryVoiceTriggerKey(newValue, to: UserDefaults.standard) }
    }

    static func readVoiceTriggerKey(from defaults: UserDefaults) -> VoiceTriggerKey {
        guard let rawValue = defaults.string(forKey: voiceTriggerKeyKey),
              let key = VoiceTriggerKey(rawValue: rawValue) else {
            return .defaultValue
        }
        return key
    }

    static func writeVoiceTriggerKey(_ key: VoiceTriggerKey, to defaults: UserDefaults) {
        defaults.set(key.rawValue, forKey: voiceTriggerKeyKey)
        defaults.set(key.rawValue, forKey: momentaryVoiceTriggerKeyKey)
    }

    static func readMomentaryVoiceTriggerKey(from defaults: UserDefaults) -> VoiceTriggerKey {
        readSemanticTriggerKey(
            momentaryVoiceTriggerKeyKey,
            from: defaults
        )
    }

    static func writeMomentaryVoiceTriggerKey(
        _ key: VoiceTriggerKey,
        to defaults: UserDefaults
    ) {
        defaults.set(key.rawValue, forKey: momentaryVoiceTriggerKeyKey)
        defaults.set(key.rawValue, forKey: voiceTriggerKeyKey)
    }

    static func migrateVoiceTriggerKeys(from defaults: UserDefaults) {
        guard let legacyRawValue = defaults.string(forKey: voiceTriggerKeyKey),
              let legacyKey = VoiceTriggerKey(rawValue: legacyRawValue) else {
            return
        }
        if defaults.object(forKey: momentaryVoiceTriggerKeyKey) == nil {
            defaults.set(legacyKey.rawValue, forKey: momentaryVoiceTriggerKeyKey)
        }
    }

    private static func readSemanticTriggerKey(
        _ key: String,
        from defaults: UserDefaults
    ) -> VoiceTriggerKey {
        if defaults.object(forKey: key) == nil {
            migrateVoiceTriggerKeys(from: defaults)
        }
        guard let rawValue = defaults.string(forKey: key),
              let triggerKey = VoiceTriggerKey(rawValue: rawValue) else {
            return .defaultValue
        }
        return triggerKey
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    static func byteSize(of url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let attributes = try? fm.attributesOfItem(atPath: fileURL.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  let size = attributes[.size] as? NSNumber else {
                continue
            }
            total &+= size.uint64Value
        }
        return total
    }

    static func logsTotalByteSize() -> UInt64 {
        Log.flush()
        VoiceDiagnosticLogger.shared.flush()
        return byteSize(of: logsDirectory)
    }

    static func clearAllLogs() {
        Log.clear()
        VoiceDiagnosticLogger.shared.clear()
        DiagnosticAuthorityService.shared.clear()

        let activeNames: Set<String> = [
            logFile.lastPathComponent,
            logFile.appendingPathExtension("1").lastPathComponent,
            VoiceDiagnosticLogger.currentLogURL.lastPathComponent,
            VoiceDiagnosticLogger.currentLogURL.appendingPathExtension("1").lastPathComponent,
            DiagnosticStorage.defaultJournalURL.lastPathComponent,
        ]
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for file in files where !activeNames.contains(file.lastPathComponent) {
                try? fm.removeItem(at: file)
            }
        }
    }

    static func clearFiles(in directory: URL) {
        let fm = FileManager.default
        ensureDirectory(directory)
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }

    static func formattedSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
    }
}
