import Foundation
import CryptoKit
import XCTest
@testable import RemoteOrbit

final class DiagnosticExportTests: XCTestCase {
    func testExportWritesManifestRuntimeWindowHashesAndUnavailableReceiver() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("exports", isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("real-log".utf8).write(to: logs.appendingPathComponent("RemoteOrbit.log"))
        try Data("typed-log".utf8).write(to: logs.appendingPathComponent("diagnostic.jsonl"))
        try Data("raw".utf8).write(to: logs.appendingPathComponent("raw.txt"))
        try Data("settings".utf8).write(to: logs.appendingPathComponent("settings.backup"))
        let journalURL = logs.appendingPathComponent("events.jsonl")
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
        XCTAssertEqual(manifest["observation_schema_version"] as? Int, 1)
        XCTAssertEqual(manifest["runtime_app_version"] as? String, "1.0")
        XCTAssertEqual(manifest["runtime_build_version"] as? String, "7")
        XCTAssertEqual(manifest["runtime_source_revision"] as? String, "abc123")
        XCTAssertEqual(manifest["diagnostic_dropped_event_count"] as? Int, 0)
        XCTAssertEqual(manifest["diagnostic_write_failure_count"] as? Int, 0)
        XCTAssertEqual(manifest["evidence_errors"] as? [String], ["receiver log unavailable"])
        let evidenceSources = try XCTUnwrap(manifest["evidence_sources"] as? [String: Any])
        XCTAssertEqual(
            (evidenceSources["session_events"] as? [String: Any])?["status"] as? String,
            "available"
        )
        XCTAssertEqual(
            (evidenceSources["journal"] as? [String: Any])?["status"] as? String,
            "available"
        )
        XCTAssertEqual(
            (evidenceSources["application_logs"] as? [String: Any])?["status"] as? String,
            "bounded"
        )
        XCTAssertEqual(
            (evidenceSources["receiver"] as? [String: Any])?["status"] as? String,
            "unavailable"
        )
        let includedFiles = try XCTUnwrap(manifest["files_included"] as? [String])
        XCTAssertTrue(includedFiles.contains("manifest.json"))
        XCTAssertTrue(includedFiles.contains("SHA256SUMS"))
        XCTAssertTrue(includedFiles.contains("receiver/evidence-unavailable.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("runtime/runtime-context.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("sessions/diagnostic-events.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("journal/events.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/diagnostic.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/RemoteOrbit.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("receiver/evidence-unavailable.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("evidence/required-evidence.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/raw.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/settings.backup").path))

        let checksums = try String(contentsOf: extracted.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        XCTAssertTrue(checksums.contains("manifest.json"))
        XCTAssertTrue(checksums.contains("runtime/runtime-context.json"))
        let requiredEvidence = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: extracted.appendingPathComponent("evidence/required-evidence.json"))
            ) as? [String: Any]
        )
        XCTAssertEqual(
            (requiredEvidence["remoteorbit_log"] as? [String: Any])?["status"] as? String,
            "bounded"
        )
        XCTAssertEqual(
            (requiredEvidence["voice_diagnostic_current"] as? [String: Any])?["status"] as? String,
            "unavailable"
        )
        XCTAssertNotNil(requiredEvidence["permissions"])
        XCTAssertNotNil(requiredEvidence["archive_integrity"])
    }

    func testDiagnosticEventsWithoutSummaryDoNotClaimFrozenSummaryAvailable() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let extracted = try exportAndExtract(events: [], root: root)
        let requiredEvidence = try requiredEvidence(at: extracted)
        let frozen = try XCTUnwrap(requiredEvidence["frozen_trace_and_session_summaries"] as? [String: Any])

        XCTAssertEqual(frozen["status"] as? String, "unavailable")
        XCTAssertEqual(frozen["summary_count"] as? Int, 0)
        XCTAssertEqual(frozen["summary_status"] as? String, "unavailable")
        XCTAssertEqual(frozen["trace_count"] as? Int, 0)
        XCTAssertEqual(frozen["trace_status"] as? String, "unavailable")
        XCTAssertTrue((frozen["reason"] as? String)?.contains("absent") == true)
    }

    func testDiagnosticEventsWithoutTraceDoNotClaimFrozenTraceAvailable() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let extracted = try exportAndExtract(events: [makeSummaryEvent(sequence: 1)], root: root)
        let requiredEvidence = try requiredEvidence(at: extracted)
        let frozen = try XCTUnwrap(requiredEvidence["frozen_trace_and_session_summaries"] as? [String: Any])

        XCTAssertEqual(frozen["status"] as? String, "unavailable")
        XCTAssertEqual(frozen["summary_count"] as? Int, 1)
        XCTAssertEqual(frozen["summary_status"] as? String, "available")
        XCTAssertEqual(frozen["trace_count"] as? Int, 0)
        XCTAssertEqual(frozen["trace_status"] as? String, "unavailable")
    }

    func testSummaryAndTraceEventsMakeFrozenReceiptAvailableWithCounts() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let extracted = try exportAndExtract(
            events: [makeSummaryEvent(sequence: 1), makeTraceEvent(sequence: 2)],
            root: root
        )
        let requiredEvidence = try requiredEvidence(at: extracted)
        let frozen = try XCTUnwrap(requiredEvidence["frozen_trace_and_session_summaries"] as? [String: Any])

        XCTAssertEqual(frozen["status"] as? String, "available")
        XCTAssertEqual(frozen["summary_count"] as? Int, 1)
        XCTAssertEqual(frozen["summary_status"] as? String, "available")
        XCTAssertEqual(frozen["trace_count"] as? Int, 1)
        XCTAssertEqual(frozen["trace_status"] as? String, "available")
    }

    func testSessionEventTruncationDoesNotClaimAbsentTraceEvidence() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let extracted = try exportAndExtract(
            events: [makeSummaryEvent(sequence: 1), makeTraceEvent(sequence: 2)],
            root: root,
            maximumSessionEventCount: 1
        )
        let requiredEvidence = try requiredEvidence(at: extracted)
        let frozen = try XCTUnwrap(requiredEvidence["frozen_trace_and_session_summaries"] as? [String: Any])

        XCTAssertEqual(frozen["status"] as? String, "bounded")
        XCTAssertEqual(frozen["summary_status"] as? String, "available")
        XCTAssertEqual(frozen["trace_count"] as? Int, 0)
        XCTAssertEqual(frozen["trace_status"] as? String, "bounded")
        XCTAssertTrue(((frozen["voice.session.trace"] as? [String: Any])?["reason"] as? String ?? "").contains("may have truncated"))
        XCTAssertEqual(frozen["session_events_truncated"] as? Bool, true)
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
        let archive = try exporter.export(options: DiagnosticExportOptions(
            outputDirectory: root,
            hostRole: "TEST_HOST"
        ))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))

        let manifestData = try Data(contentsOf: extracted.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifest["host_role"] as? String, "TEST_HOST")

        XCTAssertEqual(
            try String(contentsOf: extracted.appendingPathComponent("receiver/unified-log-window.jsonl"), encoding: .utf8),
            "{\"event\":\"timing\"}\n"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("journal/events.jsonl.1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("journal/events.jsonl.2").path))
    }

    func testExportPaginatesBeyondFiveHundredEventsWithoutSilentTruncation() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let events = (1...501).map { sequence in
            DiagnosticEvent(
                input: try! DiagnosticEventInput(
                    eventType: "voice.session.summary",
                    subsystem: "voice.session",
                    category: "summary",
                    severity: .info,
                    sourceComponent: "long_term_observability",
                    sessionID: "session-\(sequence)",
                    payload: ["summary": .object([
                        "observation_schema_version": .unsignedInteger(1),
                        "anomaly_flags": .array([]),
                    ])]
                ),
                context: DiagnosticRuntimeContext(
                    processInstanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    processID: 42,
                    binaryPath: "/tmp/RemoteOrbit",
                    appVersion: "1.0",
                    buildVersion: "7",
                    sourceRevision: "abc123"
                ),
                timestamp: DiagnosticClockStamp(
                    wallTimestampUnixMilliseconds: Int64(sequence),
                    monotonic: DiagnosticMonotonicTimestamp(
                        valueNanoseconds: UInt64(sequence) * 1_000_000,
                        clockDomain: "mach_continuous_time",
                        rawTicks: UInt64(sequence) * 1_000_000,
                        timebaseNumerator: 1,
                        timebaseDenominator: 1
                    )
                ),
                sequenceNumber: UInt64(sequence)
            )
        }
        let exporter = DiagnosticExporter(
            authority: PaginatedExportAuthority(events: events),
            journalURL: root.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: Data("{\"event\":\"timing\"}\n".utf8)),
            clock: { Date(timeIntervalSince1970: 1_700_000_002) }
        )

        let archive = try exporter.export(options: DiagnosticExportOptions(outputDirectory: root))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))
        let eventsData = try Data(contentsOf: extracted.appendingPathComponent("sessions/diagnostic-events.json"))
        let page = try JSONDecoder().decode(DiagnosticQueryPage.self, from: eventsData)
        XCTAssertEqual(page.events.count, 501)

        let manifestData = try Data(contentsOf: extracted.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifest["session_event_count"] as? Int, 501)
        XCTAssertEqual(manifest["session_events_truncated"] as? Bool, false)
    }

    func testExportExactEventLimitIsNotMarkedTruncatedWithoutRemainingEvents() throws {
        let exactRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: exactRoot) }
        let exactEvents = [makeSummaryEvent(sequence: 1), makeSummaryEvent(sequence: 2)]
        let exactExporter = DiagnosticExporter(
            authority: PaginatedExportAuthority(events: exactEvents),
            journalURL: exactRoot.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: Data("{}\n".utf8)),
            clock: { Date(timeIntervalSince1970: 1_700_000_004) },
            maximumSessionEventCount: 2
        )
        let exactArchive = try exactExporter.export(
            options: DiagnosticExportOptions(outputDirectory: exactRoot)
        )
        let exactExtracted = try extract(
            archive: exactArchive,
            into: exactRoot.appendingPathComponent("extracted")
        )
        let exactManifest = try manifest(at: exactExtracted)
        XCTAssertEqual(exactManifest["session_event_count"] as? Int, 2)
        XCTAssertEqual(exactManifest["session_events_truncated"] as? Bool, false)

        let remainingRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: remainingRoot) }
        let remainingExporter = DiagnosticExporter(
            authority: PaginatedExportAuthority(
                events: [makeSummaryEvent(sequence: 1), makeSummaryEvent(sequence: 2), makeSummaryEvent(sequence: 3)]
            ),
            journalURL: remainingRoot.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: Data("{}\n".utf8)),
            clock: { Date(timeIntervalSince1970: 1_700_000_005) },
            maximumSessionEventCount: 2
        )
        let remainingArchive = try remainingExporter.export(
            options: DiagnosticExportOptions(outputDirectory: remainingRoot)
        )
        let remainingExtracted = try extract(
            archive: remainingArchive,
            into: remainingRoot.appendingPathComponent("extracted")
        )
        let remainingManifest = try manifest(at: remainingExtracted)
        XCTAssertEqual(remainingManifest["session_event_count"] as? Int, 2)
        XCTAssertEqual(remainingManifest["session_events_truncated"] as? Bool, true)
    }

    func testEmptyReceiverOutputIsUnavailableAndRealLogLayoutIsAllowlisted() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("remote-log".utf8).write(to: logs.appendingPathComponent("RemoteOrbit.log"))
        try Data("approved".utf8).write(to: logs.appendingPathComponent("diagnostic.json"))
        try Data("secret".utf8).write(to: logs.appendingPathComponent("settings.backup"))
        try FileManager.default.createDirectory(
            at: logs.appendingPathComponent("Recordings"),
            withIntermediateDirectories: true
        )
        try Data("wav".utf8).write(to: logs.appendingPathComponent("Recordings/voice.wav"))

        let exporter = DiagnosticExporter(
            authority: ExportRecordingAuthority(),
            journalURL: logs.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: Data()),
            clock: { Date(timeIntervalSince1970: 1_700_000_003) }
        )
        let archive = try exporter.export(options: DiagnosticExportOptions(outputDirectory: root))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/RemoteOrbit.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/diagnostic.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/settings.backup").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("logs/Recordings/voice.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("receiver/evidence-unavailable.json").path))

        let manifestData = try Data(contentsOf: extracted.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifest["receiver_evidence_status"] as? String, "unavailable")
        XCTAssertEqual(manifest["evidence_errors"] as? [String], ["no useful receiver timing records"])
    }

    func testOversizedRemoteOrbitLogWithTimeWindowProducesBoundedArchive() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        let before = "2026-10-29T09:59:59.000Z before-window\n"
        let inside = String(repeating: "2026-10-29T10:00:00.000Z inside-window payload\n", count: 70_000)
        let after = "2026-10-29T10:01:00.000Z after-window\n"
        try Data((before + inside + after).utf8).write(to: logs.appendingPathComponent("RemoteOrbit.log"))

        let exporter = DiagnosticExporter(
            authority: ExportRecordingAuthority(),
            journalURL: logs.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: Data()),
            clock: { Date(timeIntervalSince1970: 1_700_000_006) }
        )

        let archive = try exporter.export(options: DiagnosticExportOptions(
            outputDirectory: root,
            hostRole: "TEST_HOST",
            startWallTimestampUnixMilliseconds: 1_793_268_000_000,
            endWallTimestampUnixMilliseconds: 1_793_268_000_100
        ))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))
        let exportedLog = try Data(contentsOf: extracted.appendingPathComponent("logs/RemoteOrbit.log"))
        let exportedText = try XCTUnwrap(String(data: exportedLog, encoding: .utf8))
        let manifest = try manifest(at: extracted)

        XCTAssertLessThanOrEqual(exportedLog.count, 2 * 1024 * 1024)
        XCTAssertTrue(exportedText.contains("inside-window"))
        XCTAssertFalse(exportedText.contains("before-window"))
        XCTAssertFalse(exportedText.contains("after-window"))
        let sources = try XCTUnwrap(manifest["evidence_sources"] as? [String: Any])
        let logsSource = try XCTUnwrap(sources["application_logs"] as? [String: Any])
        XCTAssertEqual(logsSource["status"] as? String, "bounded")
        XCTAssertTrue((logsSource["reason"] as? String)?.hasPrefix("time_window_applied") == true)
    }

    func testOversizedTimeWindowRetainsNewestCompleteLinesAndReportsOlderDrop() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        let before = "2026-10-29T09:59:59.000Z before-window\n"
        let early = "2026-10-29T10:00:00.000Z EARLY_IN_WINDOW\n"
        let body = String(
            repeating: "2026-10-29T10:30:00.000Z multi-hour-window-payload\n",
            count: 65_000
        )
        let late = "2026-10-29T12:59:59.000Z LATE_IN_WINDOW\n"
        let after = "2026-10-29T13:00:01.000Z after-window\n"
        try Data((before + early + body + late + after).utf8)
            .write(to: logs.appendingPathComponent("RemoteOrbit.log"))

        let exporter = DiagnosticExporter(
            authority: ExportRecordingAuthority(),
            journalURL: logs.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: Data()),
            clock: { Date(timeIntervalSince1970: 1_700_000_010) }
        )
        let archive = try exporter.export(options: DiagnosticExportOptions(
            outputDirectory: root,
            hostRole: "TEST_HOST",
            startWallTimestampUnixMilliseconds: 1_793_268_000_000,
            endWallTimestampUnixMilliseconds: 1_793_278_800_000
        ))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))
        let exportedLog = try Data(contentsOf: extracted.appendingPathComponent("logs/RemoteOrbit.log"))
        let exportedText = try XCTUnwrap(String(data: exportedLog, encoding: .utf8))
        let manifest = try manifest(at: extracted)
        let sources = try XCTUnwrap(manifest["evidence_sources"] as? [String: Any])
        let logsSource = try XCTUnwrap(sources["application_logs"] as? [String: Any])
        let files = try XCTUnwrap(logsSource["files"] as? [[String: Any]])
        let remoteLog = try XCTUnwrap(files.first(where: { $0["path"] as? String == "RemoteOrbit.log" }))

        XCTAssertLessThanOrEqual(exportedLog.count, 2 * 1024 * 1024)
        XCTAssertFalse(exportedText.contains("before-window"))
        XCTAssertFalse(exportedText.contains("after-window"))
        XCTAssertFalse(exportedText.contains("EARLY_IN_WINDOW"))
        XCTAssertTrue(exportedText.contains("LATE_IN_WINDOW"))
        let timestamps = exportedText
            .split(separator: "\n")
            .compactMap { $0.split(separator: " ").first }
        XCTAssertEqual(timestamps, timestamps.sorted())
        XCTAssertEqual(logsSource["status"] as? String, "bounded")
        XCTAssertEqual(
            logsSource["reason"] as? String,
            "time_window_applied_and_older_selected_window_evidence_dropped"
        )
        XCTAssertEqual(remoteLog["status"] as? String, "bounded")
        XCTAssertEqual(remoteLog["selected_window_truncated"] as? Bool, true)
        XCTAssertEqual(
            remoteLog["truncation_direction"] as? String,
            "older_selected_window_evidence_dropped"
        )
        XCTAssertGreaterThan(remoteLog["selected_window_bytes"] as? Int ?? 0, 2 * 1024 * 1024)

        let requiredEvidence = try requiredEvidence(at: extracted)
        let requiredLog = try XCTUnwrap(requiredEvidence["remoteorbit_log"] as? [String: Any])
        XCTAssertEqual(requiredLog["status"] as? String, "bounded")
        XCTAssertGreaterThan(requiredLog["original_bytes"] as? Int ?? 0, requiredLog["exported_bytes"] as? Int ?? 0)
        XCTAssertEqual(requiredLog["selected_window_truncated"] as? Bool, true)
        XCTAssertEqual(
            requiredLog["truncation_direction"] as? String,
            "older_selected_window_evidence_dropped"
        )
    }

    func testBoundedVoiceDiagnosticReceiptPreservesPerFileMetadata() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let data = Data(String(repeating: "{\"event\":\"diagnostic\"}\n", count: 150_000).utf8)
        try data.write(to: logs.appendingPathComponent("voice-diagnostic-current.jsonl"))

        let extracted = try exportAndExtract(events: [], root: root)
        let requiredEvidence = try requiredEvidence(at: extracted)
        let receipt = try XCTUnwrap(requiredEvidence["voice_diagnostic_current"] as? [String: Any])

        XCTAssertEqual(receipt["status"] as? String, "bounded")
        XCTAssertEqual(receipt["original_bytes"] as? Int, data.count)
        XCTAssertLessThan(receipt["exported_bytes"] as? Int ?? data.count, data.count)
        XCTAssertEqual(receipt["path"] as? String, "voice-diagnostic-current.jsonl")
    }

    func testSelectedSystemInputReceiptUsesExportTimeAuthorityValue() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var currentIdentity: String? = "uid:before-export"
        let extracted = try exportAndExtract(
            events: [],
            root: root,
            selectedSystemInputIdentity: { currentIdentity }
        )
        currentIdentity = "uid:after-export"

        let before = try requiredEvidence(at: extracted)
        let beforeReceipt = try XCTUnwrap(before["selected_system_input"] as? [String: Any])
        XCTAssertEqual(beforeReceipt["identity"] as? String, "uid:before-export")

        let secondRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: secondRoot) }
        let secondExtracted = try exportAndExtract(
            events: [],
            root: secondRoot,
            selectedSystemInputIdentity: { currentIdentity }
        )
        let after = try requiredEvidence(at: secondExtracted)
        let afterReceipt = try XCTUnwrap(after["selected_system_input"] as? [String: Any])
        XCTAssertEqual(afterReceipt["identity"] as? String, "uid:after-export")
        XCTAssertEqual(afterReceipt["status"] as? String, "available")
    }

    func testOversizedJournalAndReceiverProducePartialArchiveWithManifestStatusesAndChecksums() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journalURL = root.appendingPathComponent("diagnostic-events-v1.jsonl")
        let journalData = Data(String(repeating: "{\"event\":\"journal\"}\n", count: 120_000).utf8)
        try journalData.write(to: journalURL)
        let receiverData = Data(String(repeating: "{\"event\":\"receiver_timing\"}\n", count: 30_000).utf8)

        let exporter = DiagnosticExporter(
            authority: ExportRecordingAuthority(),
            journalURL: journalURL,
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: receiverData),
            clock: { Date(timeIntervalSince1970: 1_700_000_007) }
        )
        let archive = try exporter.export(options: DiagnosticExportOptions(
            outputDirectory: root,
            hostRole: "TEST_HOST"
        ))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))
        let manifest = try manifest(at: extracted)
        let sources = try XCTUnwrap(manifest["evidence_sources"] as? [String: Any])
        let journalSource = try XCTUnwrap(sources["journal"] as? [String: Any])
        let receiverSource = try XCTUnwrap(sources["receiver"] as? [String: Any])

        XCTAssertEqual(journalSource["status"] as? String, "bounded")
        XCTAssertEqual(receiverSource["status"] as? String, "bounded")
        XCTAssertLessThanOrEqual(
            try Data(contentsOf: extracted.appendingPathComponent("journal/diagnostic-events-v1.jsonl")).count,
            2 * 1024 * 1024
        )
        XCTAssertLessThanOrEqual(
            try Data(contentsOf: extracted.appendingPathComponent("receiver/unified-log-window.jsonl")).count,
            512 * 1024
        )

        let checksumLines = try String(
            contentsOf: extracted.appendingPathComponent("SHA256SUMS"),
            encoding: .utf8
        ).split(separator: "\n")
        for line in checksumLines {
            let parts = line.split(separator: "  ", maxSplits: 1)
            XCTAssertEqual(parts.count, 2)
            let expected = String(parts[0])
            let path = String(parts[1])
            let data = try Data(contentsOf: extracted.appendingPathComponent(path))
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actual, expected, path)
        }
    }

    func testReceiverProviderOversizeFailureDoesNotDestroyArchive() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = DiagnosticExporter(
            authority: ExportRecordingAuthority(),
            journalURL: root.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: OversizedReceiverEvidenceProvider(),
            clock: { Date(timeIntervalSince1970: 1_700_000_008) }
        )

        let archive = try exporter.export(options: DiagnosticExportOptions(outputDirectory: root))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))
        let manifest = try manifest(at: extracted)
        XCTAssertEqual(manifest["receiver_evidence_status"] as? String, "unavailable")
        let sources = try XCTUnwrap(manifest["evidence_sources"] as? [String: Any])
        let receiverSource = try XCTUnwrap(sources["receiver"] as? [String: Any])
        XCTAssertEqual(receiverSource["status"] as? String, "unavailable")
        XCTAssertEqual(
            receiverSource["reason"] as? String,
            "receiver evidence exceeded provider bound"
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: extracted.appendingPathComponent("sessions/diagnostic-events.json").path
        ))
    }

    func testSessionQueryFailureIsRecordedWithoutDestroyingArchive() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = DiagnosticExporter(
            authority: FailingExportAuthority(),
            journalURL: root.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: Data()),
            clock: { Date(timeIntervalSince1970: 1_700_000_009) }
        )

        let archive = try exporter.export(options: DiagnosticExportOptions(outputDirectory: root))
        let extracted = try extract(archive: archive, into: root.appendingPathComponent("extracted"))
        let manifest = try manifest(at: extracted)
        let sources = try XCTUnwrap(manifest["evidence_sources"] as? [String: Any])
        let sessions = try XCTUnwrap(sources["session_events"] as? [String: Any])
        XCTAssertEqual(sessions["status"] as? String, "failed")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: extracted.appendingPathComponent("sessions/evidence-unavailable.json").path
        ))
    }

    private func exportAndExtract(
        events: [DiagnosticEvent],
        root: URL,
        maximumSessionEventCount: Int = 10_000,
        selectedSystemInputIdentity: @escaping () -> String? = { nil }
    ) throws -> URL {
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let exporter = DiagnosticExporter(
            authority: PaginatedExportAuthority(events: events),
            journalURL: logs.appendingPathComponent("diagnostic-events-v1.jsonl"),
            receiverEvidenceProvider: FixedReceiverEvidenceProvider(data: Data("{\"event\":\"timing\"}\n".utf8)),
            clock: { Date(timeIntervalSince1970: 1_700_000_011) },
            selectedSystemInputIdentity: selectedSystemInputIdentity,
            maximumSessionEventCount: maximumSessionEventCount
        )
        let archive = try exporter.export(options: DiagnosticExportOptions(outputDirectory: root))
        return try extract(archive: archive, into: root.appendingPathComponent("extracted"))
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

    private func manifest(at extracted: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: extracted.appendingPathComponent("manifest.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func requiredEvidence(at extracted: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: extracted.appendingPathComponent("evidence/required-evidence.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeSummaryEvent(sequence: Int) -> DiagnosticEvent {
        DiagnosticEvent(
            input: try! DiagnosticEventInput(
                eventType: "voice.session.summary",
                subsystem: "voice.session",
                category: "summary",
                severity: .info,
                sourceComponent: "long_term_observability",
                sessionID: "session-\(sequence)",
                payload: ["summary": .object([
                    "observation_schema_version": .unsignedInteger(1),
                    "anomaly_flags": .array([]),
                ])]
            ),
            context: DiagnosticRuntimeContext(
                processInstanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                processID: 42,
                binaryPath: "/tmp/RemoteOrbit",
                appVersion: "1.0",
                buildVersion: "7",
                sourceRevision: "abc123"
            ),
            timestamp: DiagnosticClockStamp(
                wallTimestampUnixMilliseconds: Int64(sequence),
                monotonic: DiagnosticMonotonicTimestamp(
                    valueNanoseconds: UInt64(sequence) * 1_000_000,
                    clockDomain: "mach_continuous_time",
                    rawTicks: UInt64(sequence) * 1_000_000,
                    timebaseNumerator: 1,
                    timebaseDenominator: 1
                )
            ),
            sequenceNumber: UInt64(sequence)
        )
    }

    private func makeTraceEvent(sequence: Int) -> DiagnosticEvent {
        DiagnosticEvent(
            input: try! DiagnosticEventInput(
                eventType: "voice.session.trace",
                subsystem: "voice.session",
                category: "trace",
                severity: .warning,
                sourceComponent: "long_term_observability",
                sessionID: "session-(sequence)",
                payload: [
                    "capture_id": .string("capture-(sequence)"),
                    "chunk_index": .unsignedInteger(0),
                    "chunk_count": .unsignedInteger(1),
                    "observation_schema_version": .unsignedInteger(1),
                    "observations": .array([]),
                    "dropped_observations": .unsignedInteger(0),
                ]
            ),
            context: DiagnosticRuntimeContext(
                processInstanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                processID: 42,
                binaryPath: "/tmp/RemoteOrbit",
                appVersion: "1.0",
                buildVersion: "7",
                sourceRevision: "abc123"
            ),
            timestamp: DiagnosticClockStamp(
                wallTimestampUnixMilliseconds: Int64(sequence),
                monotonic: DiagnosticMonotonicTimestamp(
                    valueNanoseconds: UInt64(sequence) * 1_000_000,
                    clockDomain: "mach_continuous_time",
                    rawTicks: UInt64(sequence) * 1_000_000,
                    timebaseNumerator: 1,
                    timebaseDenominator: 1
                )
            ),
            sequenceNumber: UInt64(sequence)
        )
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

private struct OversizedReceiverEvidenceProvider: ReceiverEvidenceProvider {
    func evidence(sinceWallMilliseconds: Int64?, untilWallMilliseconds: Int64?) throws -> Data {
        throw ReceiverEvidenceError.evidenceTooLarge
    }
}

private final class FailingExportAuthority: DiagnosticAuthority {
    var droppedEventCount: UInt64 = 0
    var writeFailureCount: UInt64 = 0

    func emit(_ input: DiagnosticEventInput) {}

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        throw DiagnosticExportError.storageUnavailable
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data {
        throw DiagnosticExportError.storageUnavailable
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

private final class PaginatedExportAuthority: DiagnosticAuthority {
    let events: [DiagnosticEvent]

    init(events: [DiagnosticEvent]) {
        self.events = events
    }

    var droppedEventCount: UInt64 { 0 }
    var writeFailureCount: UInt64 { 0 }

    func emit(_ input: DiagnosticEventInput) {}

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        let matching = events.filter(filter.matches)
        let startIndex: Int
        if let cursor = filter.cursor,
           let index = matching.firstIndex(where: { $0.eventID.uuidString == cursor }) {
            startIndex = index + 1
        } else {
            startIndex = 0
        }
        let pageEvents = Array(matching.dropFirst(startIndex).prefix(filter.limit))
        let nextCursor = pageEvents.count + startIndex < matching.count
            ? pageEvents.last?.eventID.uuidString
            : nil
        return DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: pageEvents,
            nextCursor: nextCursor
        )
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data {
        try JSONEncoder().encode(try query(filter))
    }
}
