import Foundation

enum AppStorage {
    static let loggingEnabledKey = "RemoteOrbit.loggingEnabled"
    static let recordingEnabledKey = "RemoteOrbit.recordingEnabled"

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

    /// Mapping snapshots are kept outside UserDefaults so a failed decode or
    /// an accidental reset cannot make the only copy of a user's templates
    /// unrecoverable.
    static let mappingBackupsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/RemoteOrbit/Backups/Mappings",
                isDirectory: true
            )
    }()

    static func prepare() {
        UserDefaults.standard.register(defaults: [
            loggingEnabledKey: false,
            recordingEnabledKey: false,
        ])
        ensureDirectory(logsDirectory)
        ensureDirectory(recordingsDirectory)
        ensureDirectory(mappingBackupsDirectory)

        // The app uses ~/Library/Logs as its single persistent log location.
        try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: "/tmp/remote-orbit.log")
        )
    }

    static var loggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: loggingEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: loggingEnabledKey) }
    }

    static var recordingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: recordingEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingEnabledKey) }
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
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
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
