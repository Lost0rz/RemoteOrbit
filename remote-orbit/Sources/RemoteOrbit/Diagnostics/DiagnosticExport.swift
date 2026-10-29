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

private enum EvidenceStatus: String {
    case available
    case bounded
    case unavailable
    case failed
}

private enum BoundedLineRetention: Equatable {
    case beginning
    case end
}

private struct BoundedEvidenceResult {
    let status: EvidenceStatus
    let originalBytes: Int
    let exportedBytes: Int
    let reason: String?
    let metadata: [String: Any]

    init(
        status: EvidenceStatus,
        originalBytes: Int,
        exportedBytes: Int,
        reason: String?,
        metadata: [String: Any] = [:]
    ) {
        self.status = status
        self.originalBytes = originalBytes
        self.exportedBytes = exportedBytes
        self.reason = reason
        self.metadata = metadata
    }
}

private struct LogTimestampParser {
    private let fractionalISO8601: ISO8601DateFormatter
    private let ISO8601: ISO8601DateFormatter
    private let fractionalDate: DateFormatter
    private let date: DateFormatter

    init() {
        let fractionalISO8601 = ISO8601DateFormatter()
        fractionalISO8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalISO8601 = fractionalISO8601

        let ISO8601 = ISO8601DateFormatter()
        ISO8601.formatOptions = [.withInternetDateTime]
        self.ISO8601 = ISO8601

        let fractionalDate = DateFormatter()
        fractionalDate.locale = Locale(identifier: "en_US_POSIX")
        fractionalDate.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        self.fractionalDate = fractionalDate

        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        self.date = date
    }

    func milliseconds(from line: String) -> Int64? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidates: [String] = []
        if trimmed.first == "[", let closing = trimmed.firstIndex(of: "]") {
            candidates.append(String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing]))
        }
        let prefix = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        if !prefix.isEmpty {
            candidates.append(String(prefix[0]))
            if prefix.count >= 2 { candidates.append(String(prefix[0]) + " " + String(prefix[1])) }
            if prefix.count >= 3 {
                candidates.append(String(prefix[0]) + " " + String(prefix[1]) + " " + String(prefix[2]))
            }
        }

        for candidate in candidates {
            if let date = fractionalISO8601.date(from: candidate) ?? ISO8601.date(from: candidate) {
                return Int64((date.timeIntervalSince1970 * 1_000).rounded())
            }
            if let date = fractionalDate.date(from: candidate) ?? self.date.date(from: candidate) {
                return Int64((date.timeIntervalSince1970 * 1_000).rounded())
            }
        }
        return nil
    }
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
    static let maximumSessionEventCount = 10_000
    private static let maximumEvidenceBytes = 2 * 1024 * 1024

    private let authority: any DiagnosticAuthority
    private let journalURL: URL
    private let runtimeIdentity: LongTermRuntimeIdentity
    private let receiverEvidenceProvider: any ReceiverEvidenceProvider
    private let clock: () -> Date
    private let fileManager: FileManager
    private let maximumSessionEventCount: Int
    private var sessionEventCount = 0
    private var sessionEventsTruncated = false
    private var evidenceSources: [String: [String: Any]] = [:]

    init(
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared,
        journalURL: URL = DiagnosticStorage.defaultJournalURL,
        runtimeIdentity: LongTermRuntimeIdentity = .current(),
        receiverEvidenceProvider: any ReceiverEvidenceProvider = UnifiedLogReceiverEvidenceProvider(),
        clock: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default,
        maximumSessionEventCount: Int = DiagnosticExporter.maximumSessionEventCount
    ) {
        precondition(maximumSessionEventCount > 0)
        self.authority = authority
        self.journalURL = journalURL
        self.runtimeIdentity = runtimeIdentity
        self.receiverEvidenceProvider = receiverEvidenceProvider
        self.clock = clock
        self.fileManager = fileManager
        self.maximumSessionEventCount = maximumSessionEventCount
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
            sessionEventCount = 0
            sessionEventsTruncated = false
            evidenceSources.removeAll(keepingCapacity: true)
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

            do {
                try stageSessions(options: options, at: stagingURL)
            } catch {
                evidenceSources["session_events"] = [
                    "status": EvidenceStatus.failed.rawValue,
                    "reason": "session diagnostic query failed",
                    "original_bytes": 0,
                    "exported_bytes": 0,
                ]
                try writeUnavailableSessionEvents(reason: "session diagnostic query failed", at: stagingURL)
            }
            try stageRuntime(at: stagingURL)
            try stageJournal(at: stagingURL)
            try stageLogs(options: options, at: stagingURL)
            try stageReceiver(options: options, at: stagingURL)
            try stageRequiredEvidenceReceipts(at: stagingURL)
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
        var events: [DiagnosticEvent] = []
        events.reserveCapacity(min(500, maximumSessionEventCount))
        var cursor: String?
        var remainingCursor: String?
        var eventsRemainBeyondLimit = false
        while events.count < maximumSessionEventCount {
            let remainingCapacity = maximumSessionEventCount - events.count
            let pageFilter = try DiagnosticQueryFilter(
                cursor: cursor,
                startWallTimestampUnixMilliseconds: options.startWallTimestampUnixMilliseconds,
                endWallTimestampUnixMilliseconds: options.endWallTimestampUnixMilliseconds,
                limit: min(500, remainingCapacity)
            )
            let page = try authority.query(pageFilter)
            if page.events.count > remainingCapacity {
                eventsRemainBeyondLimit = true
            }
            events.append(contentsOf: page.events.prefix(remainingCapacity))
            guard let nextCursor = page.nextCursor else { break }
            guard !page.events.isEmpty else { break }
            if events.count >= maximumSessionEventCount {
                let remainingPageFilter = try DiagnosticQueryFilter(
                    cursor: nextCursor,
                    startWallTimestampUnixMilliseconds: options.startWallTimestampUnixMilliseconds,
                    endWallTimestampUnixMilliseconds: options.endWallTimestampUnixMilliseconds,
                    limit: 1
                )
                let remainingPage = try authority.query(remainingPageFilter)
                if !remainingPage.events.isEmpty {
                    eventsRemainBeyondLimit = true
                    remainingCursor = nextCursor
                }
                break
            }
            cursor = nextCursor
        }
        sessionEventCount = events.count
        sessionEventsTruncated = eventsRemainBeyondLimit || remainingCursor != nil
        let page = DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: events,
            nextCursor: sessionEventsTruncated ? events.last?.eventID.uuidString : nil
        )
        let data = try JSONEncoder().encode(page)
        try write(data: data, to: stagingURL.appendingPathComponent("sessions/diagnostic-events.json"))
        evidenceSources["session_events"] = [
            "status": EvidenceStatus.available.rawValue,
            "original_bytes": data.count,
            "exported_bytes": data.count,
            "event_count": sessionEventCount,
            "truncated": sessionEventsTruncated,
        ]
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
        evidenceSources["runtime_identity"] = evidenceObject(
            status: .available,
            originalBytes: data.count,
            exportedBytes: data.count,
            reason: nil
        )
    }

    private func stageRequiredEvidenceReceipts(at stagingURL: URL) throws {
        let logsDirectory = journalURL.deletingLastPathComponent()
        let stagedLogs = stagingURL.appendingPathComponent("logs")
        func logReceipt(_ name: String) -> [String: Any] {
            let source = logsDirectory.appendingPathComponent(name)
            let staged = stagedLogs.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else {
                return [
                    "status": EvidenceStatus.unavailable.rawValue,
                    "path": name,
                    "reason": "source not present",
                ]
            }
            let status = fileManager.fileExists(atPath: staged.path)
                ? EvidenceStatus.available.rawValue
                : EvidenceStatus.failed.rawValue
            return [
                "status": status,
                "path": name,
                "reason": status == EvidenceStatus.available.rawValue ? NSNull() : "source was not staged",
            ]
        }

        let health = DiagnosticRuntimeHealthRegistry.shared.snapshot()
        let outputReady: Bool
        if case .bool(let value) = health["audio_pipe_output_ready"] { outputReady = value } else { outputReady = false }
        let outputIdentity: String
        if case .string(let value) = health["output_device_identity"] { outputIdentity = value } else { outputIdentity = "unavailable" }
        let selectedInput: String
        if case .string(let value) = health["selected_input_identity"] { selectedInput = value } else { selectedInput = "unavailable" }

        let receipts: [String: Any] = [
            "remoteorbit_log": logReceipt("RemoteOrbit.log"),
            "voice_diagnostic_current": logReceipt("voice-diagnostic-current.jsonl"),
            "diagnostic_authority_journal": evidenceSources["journal"] ?? [
                "status": EvidenceStatus.unavailable.rawValue,
                "reason": "journal receipt unavailable",
            ],
            "session_events": evidenceSources["session_events"] ?? [
                "status": EvidenceStatus.unavailable.rawValue,
                "reason": "session receipt unavailable",
            ],
            "frozen_trace_and_session_summaries": [
                "status": fileManager.fileExists(
                    atPath: stagingURL.appendingPathComponent("sessions/diagnostic-events.json").path
                ) ? EvidenceStatus.available.rawValue : EvidenceStatus.unavailable.rawValue,
                "path": "sessions/diagnostic-events.json",
                "observation_schema_version": LongTermVoiceSessionSummary.schemaVersion,
            ],
            "runtime_identity": evidenceSources["runtime_identity"] ?? [
                "status": EvidenceStatus.unavailable.rawValue,
            ],
            "diagnostic_environment_flags": [
                "status": EvidenceStatus.available.rawValue,
                "flags": [
                    "REMOTE_ORBIT_DIAGNOSTICS",
                    "REMOTE_ORBIT_CONTINUITY_EVIDENCE",
                    "REMOTE_ORBIT_P1A5_FRONT_EDGE",
                    "REMOTE_ORBIT_P1A4_RECEIVER_FINALIZATION",
                ].map { name in
                    ["name": name, "enabled": ProcessInfo.processInfo.environment[name] == "1"]
                },
            ],
            "permissions": [
                "status": EvidenceStatus.available.rawValue,
                "input_monitoring_granted": HIDMonitor.isInputMonitoringGranted,
                "accessibility_granted": KeyInjector.isAccessibilityTrusted,
            ],
            "remoteorbit_virtual_mic": [
                "status": outputReady ? EvidenceStatus.available.rawValue : EvidenceStatus.unavailable.rawValue,
                "identity": outputIdentity,
                "ready": outputReady,
                "reason": outputReady ? NSNull() : "process output readiness unavailable",
            ],
            "selected_system_input": [
                "status": selectedInput == "unavailable" ? EvidenceStatus.unavailable.rawValue : EvidenceStatus.available.rawValue,
                "identity": selectedInput,
            ],
            "receiver_evidence": evidenceSources["receiver"] ?? [
                "status": EvidenceStatus.unavailable.rawValue,
                "reason": "receiver receipt unavailable",
            ],
            "archive_integrity": [
                "status": EvidenceStatus.available.rawValue,
                "manifest": "manifest.json",
                "sha256": "SHA256SUMS",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: receipts, options: [.sortedKeys])
        try write(data: data, to: stagingURL.appendingPathComponent("evidence/required-evidence.json"))
        evidenceSources["required_evidence"] = [
            "status": EvidenceStatus.available.rawValue,
            "path": "evidence/required-evidence.json",
            "source_count": receipts.count,
        ]
    }

    private func writeUnavailableSessionEvents(reason: String, at stagingURL: URL) throws {
        let object: [String: Any] = [
            "evidence_status": "unavailable",
            "reason": reason,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try write(data: data, to: stagingURL.appendingPathComponent("sessions/evidence-unavailable.json"))
    }

    private func stageJournal(at stagingURL: URL) throws {
        let destination = stagingURL.appendingPathComponent("journal", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let journal = JSONLinesDiagnosticJournal(fileURL: journalURL)
        var fileReceipts: [[String: Any]] = []
        for segment in journal.segmentURLs() {
            let target = destination.appendingPathComponent(segment.lastPathComponent)
            do {
                let result = try copyBounded(from: segment, to: target)
                fileReceipts.append(evidenceFileObject(
                    path: segment.lastPathComponent,
                    result: result
                ))
            } catch {
                fileReceipts.append([
                    "path": segment.lastPathComponent,
                    "status": EvidenceStatus.failed.rawValue,
                    "reason": "journal segment could not be read",
                ])
            }
        }
        evidenceSources["journal"] = evidenceSourceObject(fileReceipts: fileReceipts)
    }

    private func stageLogs(options: DiagnosticExportOptions, at stagingURL: URL) throws {
        let source = journalURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: source.path) else {
            evidenceSources["application_logs"] = [
                "status": EvidenceStatus.unavailable.rawValue,
                "reason": "logs directory unavailable",
                "files": [],
            ]
            return
        }
        let destination = stagingURL.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            evidenceSources["application_logs"] = [
                "status": EvidenceStatus.failed.rawValue,
                "reason": "approved logs directory could not be read",
                "files": [],
            ]
            return
        }
        var fileReceipts: [[String: Any]] = []
        for file in files where Self.isApprovedLogFile(file, journalURL: journalURL) {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            do {
                let result: BoundedEvidenceResult
                if file.lastPathComponent == "RemoteOrbit.log" {
                    result = try stageRemoteOrbitLog(
                        from: file,
                        to: target,
                        startMilliseconds: options.startWallTimestampUnixMilliseconds,
                        endMilliseconds: options.endWallTimestampUnixMilliseconds
                    )
                } else {
                    result = try copyBounded(from: file, to: target)
                }
                fileReceipts.append(evidenceFileObject(
                    path: file.lastPathComponent,
                    result: result
                ))
            } catch {
                fileReceipts.append([
                    "path": file.lastPathComponent,
                    "status": EvidenceStatus.failed.rawValue,
                    "reason": "approved log could not be read",
                ])
            }
        }
        evidenceSources["application_logs"] = evidenceSourceObject(fileReceipts: fileReceipts)
    }

    private func stageReceiver(options: DiagnosticExportOptions, at stagingURL: URL) throws {
        do {
            let data = try receiverEvidenceProvider.evidence(
                sinceWallMilliseconds: options.startWallTimestampUnixMilliseconds,
                untilWallMilliseconds: options.endWallTimestampUnixMilliseconds
            )
            let result: BoundedEvidenceResult
            let output: Data
            if data.count > 512 * 1024 {
                output = boundedLineData(data, maximumBytes: 512 * 1024)
                result = BoundedEvidenceResult(
                    status: .bounded,
                    originalBytes: data.count,
                    exportedBytes: output.count,
                    reason: "receiver evidence exceeded export bound"
                )
            } else {
                output = data
                result = BoundedEvidenceResult(
                    status: .available,
                    originalBytes: data.count,
                    exportedBytes: data.count,
                    reason: nil
                )
            }
            guard Self.hasUsefulReceiverTimingEvidence(output) else {
                try writeUnavailableReceiver(
                    reason: result.reason ?? "no useful receiver timing records",
                    at: stagingURL
                )
                return
            }
            try write(data: output, to: stagingURL.appendingPathComponent("receiver/unified-log-window.jsonl"))
            evidenceSources["receiver"] = evidenceObject(
                status: result.status,
                originalBytes: result.originalBytes,
                exportedBytes: result.exportedBytes,
                reason: result.reason
            )
        } catch ReceiverEvidenceError.evidenceTooLarge {
            try writeUnavailableReceiver(
                reason: "receiver evidence exceeded provider bound",
                at: stagingURL
            )
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
        evidenceSources["receiver"] = evidenceObject(
            status: .unavailable,
            originalBytes: nil,
            exportedBytes: data.count,
            reason: reason
        )
    }

    private func stageManifest(
        options: DiagnosticExportOptions,
        timestamp: Date,
        at stagingURL: URL
    ) throws {
        let includedFiles = try allFiles(at: stagingURL)
            .map { relativePath(of: $0, from: stagingURL) }
            .sorted() + ["manifest.json", "SHA256SUMS"]
        let receiverUnavailableURL = stagingURL
            .appendingPathComponent("receiver/evidence-unavailable.json")
        let evidenceErrors: [String]
        if fileManager.fileExists(atPath: receiverUnavailableURL.path),
           let data = try? Data(contentsOf: receiverUnavailableURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reason = object["reason"] as? String {
            evidenceErrors = [reason]
        } else {
            evidenceErrors = []
        }
        let object: [String: Any] = [
            "export_schema_version": 1,
            "created_at_unix_ms": Int64((timestamp.timeIntervalSince1970 * 1_000).rounded(.down)),
            "host_role": options.hostRole,
            "since_unix_ms": options.startWallTimestampUnixMilliseconds as Any,
            "until_unix_ms": options.endWallTimestampUnixMilliseconds as Any,
            "journal_schema_version": DiagnosticEvent.currentSchemaVersion,
            "observation_schema_version": LongTermVoiceSessionSummary.schemaVersion,
            "receiver_evidence_status": receiverEvidenceStatus(at: stagingURL),
            "evidence_errors": evidenceErrors,
            "evidence_sources": evidenceSources,
            "session_event_count": sessionEventCount,
            "session_event_limit": maximumSessionEventCount,
            "session_events_truncated": sessionEventsTruncated,
            "files_included": includedFiles,
            "diagnostic_dropped_event_count": authority.droppedEventCount,
            "diagnostic_write_failure_count": authority.writeFailureCount,
            "runtime_process_instance_id": runtimeIdentity.processInstanceID.uuidString,
            "runtime_app_version": runtimeIdentity.appVersion,
            "runtime_build_version": runtimeIdentity.buildVersion,
            "runtime_source_revision": runtimeIdentity.sourceRevision as Any,
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

    private func copyBounded(from source: URL, to destination: URL) throws -> BoundedEvidenceResult {
        let data = try Data(contentsOf: source)
        guard data.count > Self.maximumEvidenceBytes else {
            try write(data: data, to: destination)
            return BoundedEvidenceResult(
                status: .available,
                originalBytes: data.count,
                exportedBytes: data.count,
                reason: nil
            )
        }

        let bounded = boundedLineData(data, maximumBytes: Self.maximumEvidenceBytes)
        try write(data: bounded, to: destination)
        return BoundedEvidenceResult(
            status: bounded.isEmpty ? .unavailable : .bounded,
            originalBytes: data.count,
            exportedBytes: bounded.count,
            reason: bounded.isEmpty
                ? "source contains no complete line within export bound"
                : "source exceeded export bound"
        )
    }

    private func stageRemoteOrbitLog(
        from source: URL,
        to destination: URL,
        startMilliseconds: Int64?,
        endMilliseconds: Int64?
    ) throws -> BoundedEvidenceResult {
        let data = try Data(contentsOf: source)
        guard startMilliseconds != nil || endMilliseconds != nil else {
            return try copyBounded(from: source, to: destination)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            let bounded = boundedLineData(data, maximumBytes: Self.maximumEvidenceBytes)
            try write(data: bounded, to: destination)
            return BoundedEvidenceResult(
                status: .unavailable,
                originalBytes: data.count,
                exportedBytes: bounded.count,
                reason: "log encoding is not UTF-8; time window could not be applied"
            )
        }

        var selected = Data()
        var parseableLineCount = 0
        var unparseableLineCount = 0
        let timestampParser = LogTimestampParser()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let lineString = String(line)
            guard let timestamp = timestampParser.milliseconds(from: lineString) else {
                unparseableLineCount += 1
                continue
            }
            parseableLineCount += 1
            if let startMilliseconds, timestamp < startMilliseconds { continue }
            if let endMilliseconds, timestamp > endMilliseconds { continue }
            selected.append(contentsOf: Data((lineString + "\n").utf8))
        }

        if parseableLineCount == 0 {
            let fallback = data.count <= Self.maximumEvidenceBytes
                ? data
                : boundedLineData(data, maximumBytes: Self.maximumEvidenceBytes)
            try write(data: fallback, to: destination)
            return BoundedEvidenceResult(
                status: .bounded,
                originalBytes: data.count,
                exportedBytes: fallback.count,
                reason: unparseableLineCount == 0
                    ? "time window contained no log lines"
                    : "log timestamps could not be parsed; bounded fallback exported"
            )
        }

        let wasTruncated = selected.count > Self.maximumEvidenceBytes
        let bounded = boundedLineData(
            selected,
            maximumBytes: Self.maximumEvidenceBytes,
            retention: .end
        )
        try write(data: bounded, to: destination)
        let reason: String
        if wasTruncated {
            reason = "time_window_applied_and_older_selected_window_evidence_dropped"
        } else if unparseableLineCount > 0 {
            reason = "time_window_applied_unparseable_lines_excluded"
        } else {
            reason = "time_window_applied"
        }
        return BoundedEvidenceResult(
            status: .bounded,
            originalBytes: data.count,
            exportedBytes: bounded.count,
            reason: reason,
            metadata: [
                "selected_window_bytes": selected.count,
                "selected_window_truncated": wasTruncated,
                "truncation_direction": wasTruncated
                    ? "older_selected_window_evidence_dropped"
                    : "none",
            ]
        )
    }

    private func boundedLineData(
        _ data: Data,
        maximumBytes: Int,
        retention: BoundedLineRetention = .beginning
    ) -> Data {
        guard data.count > maximumBytes else { return data }

        var lines = data.split(omittingEmptySubsequences: false, whereSeparator: { $0 == 0x0A })
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        var selectedLines: [Data] = []
        var selectedBytes = 0
        let candidates: AnySequence<Data.SubSequence>
        switch retention {
        case .beginning:
            candidates = AnySequence(lines)
        case .end:
            candidates = AnySequence(lines.reversed())
        }
        for line in candidates {
            let lineData = Data(line)
            let requiredBytes = lineData.count + 1
            guard requiredBytes <= maximumBytes else { continue }
            guard selectedBytes + requiredBytes <= maximumBytes else { break }
            selectedLines.append(lineData)
            selectedBytes += requiredBytes
        }
        if retention == .end {
            selectedLines.reverse()
        }
        var bounded = Data(capacity: selectedBytes)
        for line in selectedLines {
            bounded.append(line)
            bounded.append(0x0A)
        }
        return bounded
    }

    private func evidenceObject(
        status: EvidenceStatus,
        originalBytes: Int?,
        exportedBytes: Int?,
        reason: String?
    ) -> [String: Any] {
        var object: [String: Any] = ["status": status.rawValue]
        if let originalBytes { object["original_bytes"] = originalBytes }
        if let exportedBytes { object["exported_bytes"] = exportedBytes }
        if let reason { object["reason"] = reason }
        return object
    }

    private func evidenceFileObject(
        path: String,
        result: BoundedEvidenceResult
    ) -> [String: Any] {
        var object = evidenceObject(
            status: result.status,
            originalBytes: result.originalBytes,
            exportedBytes: result.exportedBytes,
            reason: result.reason
        )
        for (key, value) in result.metadata {
            object[key] = value
        }
        object["path"] = path
        return object
    }

    private func evidenceSourceObject(fileReceipts: [[String: Any]]) -> [String: Any] {
        let statuses = fileReceipts.compactMap { $0["status"] as? String }
        let status: EvidenceStatus
        if statuses.contains(EvidenceStatus.failed.rawValue) {
            status = .failed
        } else if statuses.contains(EvidenceStatus.unavailable.rawValue) {
            status = .unavailable
        } else if statuses.contains(EvidenceStatus.bounded.rawValue) {
            status = .bounded
        } else if statuses.isEmpty {
            status = .unavailable
        } else {
            status = .available
        }
        var object: [String: Any] = [
            "status": status.rawValue,
            "files": fileReceipts,
        ]
        let originalBytes = fileReceipts.compactMap { $0["original_bytes"] as? Int }.reduce(0, +)
        let exportedBytes = fileReceipts.compactMap { $0["exported_bytes"] as? Int }.reduce(0, +)
        object["original_bytes"] = originalBytes
        object["exported_bytes"] = exportedBytes
        if let reason = fileReceipts.compactMap({ $0["reason"] as? String }).first {
            object["reason"] = reason
        }
        return object
    }

    private func allFiles(at root: URL) throws -> [URL] {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return (enumerator?.compactMap { item -> URL? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return url
        } ?? [])
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.starts(with: rootComponents) else { return url.lastPathComponent }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
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
            ($0 >= 65 && $0 <= 90)
                || ($0 >= 97 && $0 <= 122)
                || ($0 >= 48 && $0 <= 57)
                || $0 == 45 || $0 == 46 || $0 == 95
        }
    }

    private static func isApprovedLogFile(_ url: URL, journalURL: URL) -> Bool {
        guard url.standardizedFileURL.deletingLastPathComponent() == journalURL.standardizedFileURL.deletingLastPathComponent() else {
            return false
        }
        if url.lastPathComponent == "RemoteOrbit.log" { return true }
        guard ["json", "jsonl"].contains(url.pathExtension.lowercased()) else { return false }
        return url.standardizedFileURL != journalURL.standardizedFileURL
    }

    private static func hasUsefulReceiverTimingEvidence(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let lines = data.split(omittingEmptySubsequences: true, whereSeparator: { $0 == 0x0A })
        guard !lines.isEmpty else { return false }
        return lines.contains { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                return false
            }
            let text = object.values.compactMap { $0 as? String }.joined(separator: " ").lowercased()
            return text.contains("receiver")
                || text.contains("avcapture")
                || text.contains("didstartrunning")
                || text.contains("mic")
                || text.contains("timing")
        }
    }
}
