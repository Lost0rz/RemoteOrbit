import CryptoKit
import Foundation

struct DiagnosticExportOptions: Equatable, Sendable {
    let outputDirectory: URL
    let hostRole: String
    let startWallTimestampUnixMilliseconds: Int64?
    let endWallTimestampUnixMilliseconds: Int64?

    init(
        outputDirectory: URL,
        hostRole: String = "controller",
        startWallTimestampUnixMilliseconds: Int64? = nil,
        endWallTimestampUnixMilliseconds: Int64? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.hostRole = hostRole
        self.startWallTimestampUnixMilliseconds = startWallTimestampUnixMilliseconds
        self.endWallTimestampUnixMilliseconds = endWallTimestampUnixMilliseconds
    }
}

enum DiagnosticExportError: Error, Equatable {
    case invalidOptions(String)
    case storageUnavailable
    case receiverUnavailable(String)
    case archiveFailed
    case evidenceTooLarge
}

enum ReceiverEvidenceError: Error, Equatable {
    case unavailable(String)
    case commandFailed(Int32)
    case evidenceTooLarge
}

protocol ReceiverEvidenceProvider: Sendable {
    func evidence(
        sinceWallMilliseconds: Int64?,
        untilWallMilliseconds: Int64?
    ) throws -> Data
}

struct UnifiedLogReceiverEvidenceProvider: ReceiverEvidenceProvider {
    let maximumBytes: Int

    init(maximumBytes: Int = 512 * 1024) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
    }

    func evidence(
        sinceWallMilliseconds: Int64?,
        untilWallMilliseconds: Int64?
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        var arguments = ["show", "--style", "json", "--info"]
        if let sinceWallMilliseconds {
            arguments += ["--start", Self.dateString(milliseconds: sinceWallMilliseconds)]
        } else {
            arguments += ["--last", "1h"]
        }
        if let untilWallMilliseconds {
            arguments += ["--end", Self.dateString(milliseconds: untilWallMilliseconds)]
        }
        arguments += [
            "--predicate",
            "subsystem == 'com.remoteorbit.receiver' AND category == 'receiver_timing'",
        ]
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw ReceiverEvidenceError.unavailable("unified log command unavailable")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ReceiverEvidenceError.commandFailed(process.terminationStatus)
        }
        guard data.count <= maximumBytes else {
            throw ReceiverEvidenceError.evidenceTooLarge
        }
        return data
    }

    private static func dateString(milliseconds: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1_000))
    }
}

final class DiagnosticExporter: @unchecked Sendable {
    private let authority: any DiagnosticAuthority
    private let journalURL: URL
    private let runtimeIdentity: LongTermRuntimeIdentity
    private let receiverEvidenceProvider: any ReceiverEvidenceProvider
    private let clock: () -> Date
    private let fileManager: FileManager

    init(
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared,
        journalURL: URL = DiagnosticStorage.defaultJournalURL,
        runtimeIdentity: LongTermRuntimeIdentity = .current(),
        receiverEvidenceProvider: any ReceiverEvidenceProvider = UnifiedLogReceiverEvidenceProvider(),
        clock: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.authority = authority
        self.journalURL = journalURL
        self.runtimeIdentity = runtimeIdentity
        self.receiverEvidenceProvider = receiverEvidenceProvider
        self.clock = clock
        self.fileManager = fileManager
    }

    func export(options: DiagnosticExportOptions) throws -> URL {
        guard Self.isToken(options.hostRole) else {
            throw DiagnosticExportError.invalidOptions("host role must be a stable token")
        }
        if let start = options.startWallTimestampUnixMilliseconds,
           let end = options.endWallTimestampUnixMilliseconds,
           start > end {
            throw DiagnosticExportError.invalidOptions("start wall timestamp must not exceed end")
        }

        do {
            try fileManager.createDirectory(
                at: options.outputDirectory,
                withIntermediateDirectories: true
            )
            let timestamp = clock()
            let archiveURL = uniqueArchiveURL(
                directory: options.outputDirectory,
                timestamp: timestamp
            )
            let stagingURL = options.outputDirectory
                .appendingPathComponent(".remoteorbit-export-" + UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: stagingURL) }

            try stageSessions(options: options, at: stagingURL)
            try stageRuntime(at: stagingURL)
            try stageJournal(at: stagingURL)
            try stageLogs(at: stagingURL)
            try stageReceiver(options: options, at: stagingURL)
            try stageManifest(options: options, timestamp: timestamp, at: stagingURL)
            try stageChecksums(at: stagingURL)
            try makeArchive(stagingURL: stagingURL, archiveURL: archiveURL)
            return archiveURL
        } catch let error as DiagnosticExportError {
            throw error
        } catch {
            throw DiagnosticExportError.storageUnavailable
        }
    }

    private func stageSessions(options: DiagnosticExportOptions, at stagingURL: URL) throws {
        let filter = try DiagnosticQueryFilter(
            startWallTimestampUnixMilliseconds: options.startWallTimestampUnixMilliseconds,
            endWallTimestampUnixMilliseconds: options.endWallTimestampUnixMilliseconds,
            limit: 500
        )
        let data = try authority.snapshot(filter)
        try write(data: data, to: stagingURL.appendingPathComponent("sessions/diagnostic-events.json"))
    }

    private func stageRuntime(at stagingURL: URL) throws {
        let object: [String: Any] = [
            "process_instance_id": runtimeIdentity.processInstanceID.uuidString,
            "process_id": runtimeIdentity.processID,
            "binary_path": runtimeIdentity.binaryPath,
            "app_version": runtimeIdentity.appVersion,
            "build_version": runtimeIdentity.buildVersion,
            "source_revision": runtimeIdentity.sourceRevision as Any,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try write(data: data, to: stagingURL.appendingPathComponent("runtime/runtime-context.json"))
    }

    private func stageJournal(at stagingURL: URL) throws {
        let destination = stagingURL.appendingPathComponent("journal", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let journal = JSONLinesDiagnosticJournal(fileURL: journalURL)
        for segment in journal.segmentURLs() {
            try copyBounded(
                from: segment,
                to: destination.appendingPathComponent(segment.lastPathComponent)
            )
        }
    }

    private func stageLogs(at stagingURL: URL) throws {
        let source = journalURL.deletingLastPathComponent().appendingPathComponent("logs", isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else { return }
        let destination = stagingURL.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let files = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for file in files where ["json", "jsonl"].contains(file.pathExtension.lowercased()) {
            try copyBounded(from: file, to: destination.appendingPathComponent(file.lastPathComponent))
        }
    }

    private func stageReceiver(options: DiagnosticExportOptions, at stagingURL: URL) throws {
        do {
            let data = try receiverEvidenceProvider.evidence(
                sinceWallMilliseconds: options.startWallTimestampUnixMilliseconds,
                untilWallMilliseconds: options.endWallTimestampUnixMilliseconds
            )
            guard data.count <= 512 * 1024 else { throw DiagnosticExportError.evidenceTooLarge }
            try write(data: data, to: stagingURL.appendingPathComponent("receiver/unified-log-window.jsonl"))
        } catch ReceiverEvidenceError.evidenceTooLarge {
            throw DiagnosticExportError.evidenceTooLarge
        } catch ReceiverEvidenceError.unavailable(let reason) {
            try writeUnavailableReceiver(reason: reason, at: stagingURL)
        } catch ReceiverEvidenceError.commandFailed(let status) {
            try writeUnavailableReceiver(
                reason: "receiver log command failed: " + String(status),
                at: stagingURL
            )
        } catch {
            try writeUnavailableReceiver(reason: "receiver evidence unavailable", at: stagingURL)
        }
    }

    private func writeUnavailableReceiver(reason: String, at stagingURL: URL) throws {
        let object: [String: Any] = [
            "evidence_status": "unavailable",
            "reason": reason,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try write(data: data, to: stagingURL.appendingPathComponent("receiver/evidence-unavailable.json"))
    }

    private func stageManifest(
        options: DiagnosticExportOptions,
        timestamp: Date,
        at stagingURL: URL
    ) throws {
        let object: [String: Any] = [
            "export_schema_version": 1,
            "created_at_unix_ms": Int64((timestamp.timeIntervalSince1970 * 1_000).rounded(.down)),
            "host_role": options.hostRole,
            "since_unix_ms": options.startWallTimestampUnixMilliseconds as Any,
            "until_unix_ms": options.endWallTimestampUnixMilliseconds as Any,
            "journal_schema_version": DiagnosticEvent.currentSchemaVersion,
            "receiver_evidence_status": receiverEvidenceStatus(at: stagingURL),
            "runtime_process_instance_id": runtimeIdentity.processInstanceID.uuidString,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try write(data: data, to: stagingURL.appendingPathComponent("manifest.json"))
    }

    private func receiverEvidenceStatus(at stagingURL: URL) -> String {
        fileManager.fileExists(
            atPath: stagingURL.appendingPathComponent("receiver/unified-log-window.jsonl").path
        ) ? "available" : "unavailable"
    }

    private func stageChecksums(at stagingURL: URL) throws {
        let files = try allFiles(at: stagingURL).filter { $0.lastPathComponent != "SHA256SUMS" }
        let lines = try files.map { url -> String in
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return digest + "  " + relativePath(of: url, from: stagingURL)
        }.sorted().joined(separator: "\n") + "\n"
        try write(data: Data(lines.utf8), to: stagingURL.appendingPathComponent("SHA256SUMS"))
    }

    private func makeArchive(stagingURL: URL, archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archiveURL.path, "-C", stagingURL.path, "."]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DiagnosticExportError.archiveFailed }
    }

    private func write(data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func copyBounded(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source)
        guard data.count <= 2 * 1024 * 1024 else { throw DiagnosticExportError.evidenceTooLarge }
        try write(data: data, to: destination)
    }

    private func allFiles(at root: URL) throws -> [URL] {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try (enumerator?.compactMap { item -> URL? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return url
        } ?? [])
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        String(url.path.dropFirst(root.path.count + 1))
    }

    private func uniqueArchiveURL(directory: URL, timestamp: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "RemoteOrbit-diagnostics-" + formatter.string(from: timestamp)
        var url = directory.appendingPathComponent(base).appendingPathExtension("tar.gz")
        if fileManager.fileExists(atPath: url.path) {
            url = directory
                .appendingPathComponent(base + "-" + String(UUID().uuidString.prefix(8)))
                .appendingPathExtension("tar.gz")
        }
        return url
    }

    private static func isToken(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 64 else { return false }
        return bytes.allSatisfy {
            ($0 >= 97 && $0 <= 122)
                || ($0 >= 48 && $0 <= 57)
                || $0 == 45 || $0 == 46 || $0 == 95
        }
    }
}
