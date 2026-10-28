import XCTest
@testable import RemoteOrbit

final class DiagnosticCLITests: XCTestCase {
    func testNonDiagnosticLaunchDoesNotEnterCLI() {
        let authority = RecordingDiagnosticAuthority()
        let result = DiagnosticCLI.runIfRequested(
            arguments: ["RemoteOrbit"],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { _ in },
            errorOutput: { _ in }
        )
        XCTAssertNil(result)
        XCTAssertEqual(authority.snapshotCallCount, 0)
        XCTAssertEqual(authority.queryCallCount, 0)
    }

    func testQueryUsesAuthoritySnapshotAndExistingFilterContract() throws {
        let authority = RecordingDiagnosticAuthority()
        var stdout: [String] = []
        var stderr: [String] = []
        let processID = UUID()

        let code = DiagnosticCLI.run(
            arguments: [
                "query",
                "--event-type", "application.frontmost.transition",
                "--subsystem", "application.frontmost",
                "--category", "transition",
                "--severity", "info",
                "--process-instance", processID.uuidString,
                "--session", "session-1",
                "--incident", "incident-1",
                "--correlation", "correlation-1",
                "--limit", "25",
            ],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { stdout.append($0) },
            errorOutput: { stderr.append($0) }
        )

        XCTAssertEqual(code, 0)
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(authority.snapshotCallCount, 1)
        let filter = try XCTUnwrap(authority.lastSnapshotFilter)
        XCTAssertEqual(filter.eventTypes, ["application.frontmost.transition"])
        XCTAssertEqual(filter.subsystems, ["application.frontmost"])
        XCTAssertEqual(filter.categories, ["transition"])
        XCTAssertEqual(filter.severities, [.info])
        XCTAssertEqual(filter.processInstanceID, processID)
        XCTAssertEqual(filter.sessionID, "session-1")
        XCTAssertEqual(filter.incidentID, "incident-1")
        XCTAssertEqual(filter.correlationID, "correlation-1")
        XCTAssertEqual(filter.limit, 25)
        XCTAssertEqual(stdout.count, 1)
    }

    func testSnapshotAliasUsesSameAuthoritySnapshotPath() {
        let authority = RecordingDiagnosticAuthority()
        let code = DiagnosticCLI.run(
            arguments: ["snapshot", "--limit", "1"],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { _ in },
            errorOutput: { _ in }
        )

        XCTAssertEqual(code, 0)
        XCTAssertEqual(authority.snapshotCallCount, 1)
        XCTAssertEqual(authority.queryCallCount, 0)
    }

    func testQueryParsesWallClockWindow() throws {
        let authority = RecordingDiagnosticAuthority()
        let code = DiagnosticCLI.run(
            arguments: [
                "query",
                "--since-unix-ms", "100",
                "--until-unix-ms", "200",
            ],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { _ in },
            errorOutput: { _ in }
        )

        XCTAssertEqual(code, 0)
        let filter = try XCTUnwrap(authority.lastSnapshotFilter)
        XCTAssertEqual(filter.startWallTimestampUnixMilliseconds, 100)
        XCTAssertEqual(filter.endWallTimestampUnixMilliseconds, 200)
    }

    func testExportParsesOutputHostRoleAndWallClockWindow() throws {
        let authority = RecordingDiagnosticAuthority()
        var captured: DiagnosticExportOptions?
        var stdout: [String] = []
        let code = DiagnosticCLI.run(
            arguments: [
                "export",
                "--output", "/tmp/remoteorbit-export",
                "--host-role", "receiver",
                "--since-unix-ms", "100",
                "--until-unix-ms", "200",
            ],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { stdout.append($0) },
            errorOutput: { _ in },
            exportHandler: { options in
                captured = options
                return URL(fileURLWithPath: "/tmp/RemoteOrbit-diagnostics-test.tar.gz")
            }
        )

        XCTAssertEqual(code, 0)
        XCTAssertEqual(captured?.outputDirectory.path, "/tmp/remoteorbit-export")
        XCTAssertEqual(captured?.hostRole, "receiver")
        XCTAssertEqual(captured?.startWallTimestampUnixMilliseconds, 100)
        XCTAssertEqual(captured?.endWallTimestampUnixMilliseconds, 200)
        XCTAssertEqual(stdout, ["/tmp/RemoteOrbit-diagnostics-test.tar.gz"])
    }

    func testExportRequiresOutputDirectory() {
        let authority = RecordingDiagnosticAuthority()
        var stderr: [String] = []
        let code = DiagnosticCLI.run(
            arguments: ["export"],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { _ in },
            errorOutput: { stderr.append($0) }
        )

        XCTAssertEqual(code, 64)
        XCTAssertTrue(stderr.joined(separator: "\n").contains("output"))
    }

    func testUnknownControlCommandFailsClosedWithoutAuthorityAccess() {
        let authority = RecordingDiagnosticAuthority()
        var stderr: [String] = []
        let code = DiagnosticCLI.run(
            arguments: ["restart"],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { _ in },
            errorOutput: { stderr.append($0) }
        )

        XCTAssertEqual(code, 64)
        XCTAssertEqual(authority.snapshotCallCount, 0)
        XCTAssertEqual(authority.queryCallCount, 0)
        XCTAssertTrue(stderr.joined(separator: "\n").contains("unknown diagnostics command"))
    }

    func testInvalidFilterFailsClosedBeforeAuthorityAccess() {
        let authority = RecordingDiagnosticAuthority()
        let code = DiagnosticCLI.run(
            arguments: ["query", "--limit", "0"],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { _ in },
            errorOutput: { _ in }
        )

        XCTAssertEqual(code, 65)
        XCTAssertEqual(authority.snapshotCallCount, 0)
    }

    func testVerifyPropagatesJournalCorruptionAsDataError() {
        let authority = RecordingDiagnosticAuthority()
        authority.queryError = .corruptJournal(7)
        var stderr: [String] = []

        let code = DiagnosticCLI.run(
            arguments: ["verify"],
            authority: authority,
            journalURL: URL(fileURLWithPath: "/tmp/unused"),
            output: { _ in },
            errorOutput: { stderr.append($0) }
        )

        XCTAssertEqual(code, 65)
        XCTAssertEqual(authority.queryCallCount, 1)
        XCTAssertTrue(stderr.joined(separator: "\n").contains("record 7"))
    }

    func testStatusReportsCanonicalReadOnlyStorageMetadata() throws {
        let authority = RecordingDiagnosticAuthority()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("diagnostic-events-v1.jsonl")
        try Data("abc".utf8).write(to: journal)

        var stdout: [String] = []
        let code = DiagnosticCLI.run(
            arguments: ["status"],
            authority: authority,
            journalURL: journal,
            output: { stdout.append($0) },
            errorOutput: { _ in }
        )

        XCTAssertEqual(code, 0)
        XCTAssertEqual(authority.snapshotCallCount, 0)
        XCTAssertEqual(authority.queryCallCount, 0)
        let data = try XCTUnwrap(stdout.first?.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["backend"] as? String, "diagnostic_authority_v1")
        XCTAssertEqual(object["mode"] as? String, "read_only")
        XCTAssertEqual(object["journal_exists"] as? Bool, true)
        XCTAssertEqual((object["journal_size_bytes"] as? NSNumber)?.uint64Value, 3)
        XCTAssertEqual(object["journal_path"] as? String, journal.path)
        XCTAssertEqual((object["schema_version"] as? NSNumber)?.intValue, 1)
    }
}

private final class RecordingDiagnosticAuthority: DiagnosticAuthority {
    var droppedEventCount: UInt64 = 0
    var snapshotCallCount = 0
    var queryCallCount = 0
    var lastSnapshotFilter: DiagnosticQueryFilter?
    var queryError: DiagnosticQueryError?

    func emit(_ input: DiagnosticEventInput) {}

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        queryCallCount += 1
        if let queryError {
            throw queryError
        }
        return DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: [],
            nextCursor: nil
        )
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data {
        snapshotCallCount += 1
        lastSnapshotFilter = filter
        return try JSONEncoder().encode(
            DiagnosticQueryPage(
                schemaVersion: DiagnosticEvent.currentSchemaVersion,
                events: [],
                nextCursor: nil
            )
        )
    }
}
