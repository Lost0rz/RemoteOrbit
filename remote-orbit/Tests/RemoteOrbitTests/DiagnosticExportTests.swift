import Foundation
import XCTest
@testable import RemoteOrbit

final class DiagnosticExportTests: XCTestCase {
    func testExportWritesManifestRuntimeWindowHashesAndUnavailableReceiver() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("exports", isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("typed-log".utf8).write(to: logs.appendingPathComponent("diagnostic.jsonl"))
        try Data("raw".utf8).write(to: logs.appendingPathComponent("raw.txt"))
        try Data("settings".utf8).write(to: logs.appendingPathComponent("settings.backup"))
        let journalURL = root.appendingPathComponent("events.jsonl")
        try Data("journal\n".utf8).write(to: journalURL)

        let exporter = DiagnosticExporter(
            authority: ExportRecordingAuthority(),
            journalURL: journalURL,
            runtimeIdentity: LongTermRuntimeIdentity(
                processInstanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                processID: 42,
                binaryPath: "/tmp/RemoteOrbit",
                appVersion: "1.0",
                buildVersion: "7",
                sourceRevision: "abc123"
            ),
            receiverEvidenceProvider: UnavailableReceiverEvidenceProvider(),
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let archive = try exporter.export(options: DiagnosticExportOptions(
            outputDirectory: output,
            hostRole: "controller",
            startWallTimestampUnixMilliseconds: 100,
            endWallTimestampUnixMilliseconds: 200
        ))
        XCTAssertEqual(archive.pathExtension, "gz")
        XCTAssertTrue(archive.lastPathComponent.hasPrefix("RemoteOrbit-diagnostics-"))

        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))
        let manifestData = try Data(contentsOf: extracted.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifest["export_schema_version"] as? Int, 1)
        XCTAssertEqual(manifest["host_role"] as? String, "controller")
        XCTAssertEqual((manifest["since_unix_ms"] as? NSNumber)?.int64Value, 100)
        XCTAssertEqual((manifest["until_unix_ms"] as? NSNumber)?.int64Value, 200)
        XCTAssertEqual(manifest["receiver_evidence_status"] as? String, "unavailable")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("runtime/runtime-context.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("sessions/diagnostic-events.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("journal/events.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/diagnostic.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("receiver/evidence-unavailable.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/raw.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/settings.backup").path))

        let checksums = try String(contentsOf: extracted.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        XCTAssertTrue(checksums.contains("manifest.json"))
        XCTAssertTrue(checksums.contains("runtime/runtime-context.json"))
    }

    func testExportIncludesBoundedReceiverEvidenceAndRotatedJournalSegments() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journalURL = root.appendingPathComponent("events.jsonl")
        try Data("current\n".utf8).write(to: journalURL)
        try Data("older\n".utf8).write(to: journalURL.appendingPathExtension("1"))
        try Data("oldest\n".utf8).write(to: journalURL.appendingPathExtension("2"))

        let provider = FixedReceiverEvidenceProvider(data: Data("{\"event\":\"timing\"}\n".utf8))
        let exporter = DiagnosticExporter(
            authority: ExportRecordingAuthority(),
            journalURL: journalURL,
            runtimeIdentity: .current(),
            receiverEvidenceProvider: provider,
            clock: { Date(timeIntervalSince1970: 1_700_000_001) }
        )
        let archive = try exporter.export(options: DiagnosticExportOptions(outputDirectory: root))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))

        XCTAssertEqual(
            try String(contentsOf: extracted.appendingPathComponent("receiver/unified-log-window.jsonl"), encoding: .utf8),
            "{\"event\":\"timing\"}\n"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("journal/events.jsonl.1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("journal/events.jsonl.2").path))
    }

    private func extract(archive: URL, into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", directory.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return directory
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-export-" + UUID().uuidString, isDirectory: true)
    }
}

private struct UnavailableReceiverEvidenceProvider: ReceiverEvidenceProvider {
    func evidence(sinceWallMilliseconds: Int64?, untilWallMilliseconds: Int64?) throws -> Data {
        throw ReceiverEvidenceError.unavailable("receiver log unavailable")
    }
}

private struct FixedReceiverEvidenceProvider: ReceiverEvidenceProvider {
    let data: Data

    func evidence(sinceWallMilliseconds: Int64?, untilWallMilliseconds: Int64?) throws -> Data {
        data
    }
}

private final class ExportRecordingAuthority: DiagnosticAuthority {
    var droppedEventCount: UInt64 = 0
    var writeFailureCount: UInt64 = 0

    func emit(_ input: DiagnosticEventInput) {}

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        DiagnosticQueryPage(schemaVersion: DiagnosticEvent.currentSchemaVersion, events: [], nextCursor: nil)
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data {
        try JSONEncoder().encode(
            DiagnosticQueryPage(schemaVersion: DiagnosticEvent.currentSchemaVersion, events: [], nextCursor: nil)
        )
    }
}
