import Foundation
import XCTest
@testable import RemoteOrbit

final class FrontmostApplicationDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
    }

    override func tearDown() {
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        super.tearDown()
    }

    func testFrontmostTransitionCatalogAcceptsStableProcessAndApplicationIdentity() throws {
        let input = try DiagnosticEventInput(
            eventType: "application.frontmost.transition",
            subsystem: "application.frontmost",
            category: "transition",
            severity: .info,
            sourceComponent: "frontmost_application_observer",
            payload: [
                "previous_bundle_identifier": .string("com.example.editor"),
                "previous_process_id": .unsignedInteger(101),
                "current_bundle_identifier": .string("com.example.browser"),
                "current_process_id": .unsignedInteger(202),
            ]
        )

        XCTAssertEqual(
            input.payload["current_bundle_identifier"],
            .string("com.example.browser")
        )
        XCTAssertEqual(
            input.payload["current_process_id"],
            .unsignedInteger(202)
        )
    }

    func testFrontmostTransitionCatalogRejectsInvalidPayloadTypes() {
        XCTAssertThrowsError(try DiagnosticEventInput(
            eventType: "application.frontmost.transition",
            subsystem: "application.frontmost",
            category: "transition",
            severity: .info,
            sourceComponent: "frontmost_application_observer",
            payload: [
                "previous_bundle_identifier": .string("com.example.editor"),
                "previous_process_id": .string("101"),
                "current_bundle_identifier": .string("com.example.browser"),
                "current_process_id": .unsignedInteger(202),
            ]
        ))
    }

    func testInitialFrontmostBaselineAndRepeatedIdentityEmitNothing() throws {
        let (authority, directory) = try makeAuthority()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reporter = FrontmostApplicationTransitionReporter(authority: authority)
        let editor = try identity("com.example.editor", pid: 101)

        reporter.establishBaseline(editor)
        reporter.observe(editor)

        XCTAssertTrue(try frontmostEvents(from: authority).isEmpty)
    }

    func testApplicationTransitionsEmitOnceAndPreservePreviousAndCurrentIdentity() throws {
        let (authority, directory) = try makeAuthority()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reporter = FrontmostApplicationTransitionReporter(authority: authority)
        let editor = try identity("com.example.editor", pid: 101)
        let browser = try identity("com.example.browser", pid: 202)
        let terminal = try identity("com.example.terminal", pid: 303)

        reporter.establishBaseline(editor)
        reporter.observe(browser)
        reporter.observe(browser)
        reporter.observe(terminal)
        reporter.observe(terminal)

        let events = try frontmostEvents(from: authority)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.eventType), [
            "application.frontmost.transition",
            "application.frontmost.transition",
        ])
        XCTAssertEqual(events[0].payload, [
            "previous_bundle_identifier": .string("com.example.editor"),
            "previous_process_id": .integer(101),
            "current_bundle_identifier": .string("com.example.browser"),
            "current_process_id": .integer(202),
        ])
        XCTAssertEqual(events[1].payload, [
            "previous_bundle_identifier": .string("com.example.browser"),
            "previous_process_id": .integer(202),
            "current_bundle_identifier": .string("com.example.terminal"),
            "current_process_id": .integer(303),
        ])
    }

    func testProcessRestartIsAnIdentityTransitionForTheSameApplication() throws {
        let (authority, directory) = try makeAuthority()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reporter = FrontmostApplicationTransitionReporter(authority: authority)
        let firstProcess = try identity("com.example.editor", pid: 101)
        let relaunchedProcess = try identity("com.example.editor", pid: 102)

        reporter.establishBaseline(firstProcess)
        reporter.observe(relaunchedProcess)

        let events = try frontmostEvents(from: authority)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].payload, [
            "previous_bundle_identifier": .string("com.example.editor"),
            "previous_process_id": .integer(101),
            "current_bundle_identifier": .string("com.example.editor"),
            "current_process_id": .integer(102),
        ])
    }

    func testFrontmostObserverLifecycleFollowsDiagnosticsGateExactlyOnce() {
        final class ObserverSpy: FrontmostApplicationDiagnosticsObserving {
            private(set) var startCount = 0
            private(set) var stopCount = 0

            func start() {
                startCount += 1
            }

            func stop() {
                stopCount += 1
            }
        }

        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        let spy = ObserverSpy()
        let lifecycle = FrontmostApplicationDiagnosticsLifecycle { spy }
        DiagnosticsRuntimeGate.shared.observe { enabled in
            lifecycle.setEnabled(enabled)
        }

        XCTAssertFalse(lifecycle.isRunning)
        XCTAssertEqual(lifecycle.activeObserverCountForTesting, 0)
        XCTAssertEqual(spy.startCount, 0)

        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
        XCTAssertTrue(lifecycle.isRunning)
        XCTAssertEqual(lifecycle.activeObserverCountForTesting, 1)
        XCTAssertEqual(spy.startCount, 1)

        lifecycle.setEnabled(true)
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
        XCTAssertEqual(lifecycle.activeObserverCountForTesting, 1)
        XCTAssertEqual(spy.startCount, 1)
        XCTAssertEqual(spy.stopCount, 0)

        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        XCTAssertFalse(lifecycle.isRunning)
        XCTAssertEqual(lifecycle.activeObserverCountForTesting, 0)
        XCTAssertEqual(spy.stopCount, 1)

        lifecycle.setEnabled(false)
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        XCTAssertEqual(spy.startCount, 1)
        XCTAssertEqual(spy.stopCount, 1)
    }

    private func makeAuthority() throws -> (DiagnosticAuthorityService, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteOrbitFrontmostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let authority = DiagnosticAuthorityService(
            journal: JSONLinesDiagnosticJournal(
                fileURL: directory.appendingPathComponent("events.jsonl")
            ),
            runtimeContext: .current(),
            clock: SystemDiagnosticClock(),
            queueLabel: "com.remoteorbit.tests.frontmost.\(UUID().uuidString)"
        )
        return (authority, directory)
    }

    private func frontmostEvents(
        from authority: DiagnosticAuthorityService
    ) throws -> [DiagnosticEvent] {
        try authority.query(
            DiagnosticQueryFilter(eventTypes: ["application.frontmost.transition"])
        ).events
    }

    private func identity(
        _ bundleIdentifier: String,
        pid: Int32
    ) throws -> FrontmostApplicationIdentity {
        try XCTUnwrap(
            FrontmostApplicationIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: pid
            )
        )
    }
}
