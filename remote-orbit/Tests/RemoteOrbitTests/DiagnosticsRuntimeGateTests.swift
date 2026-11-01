import Foundation
import XCTest
@testable import RemoteOrbit

final class DiagnosticsRuntimeGateTests: XCTestCase {
    override func tearDown() {
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        super.tearDown()
    }

    func testEffectiveStateUsesLoggingPreferenceOrEnvironmentOverride() {
        let gate = DiagnosticsRuntimeGate.shared

        gate.configureForTesting(loggingEnabled: false)
        XCTAssertFalse(gate.isEnabled)

        gate.configureForTesting(loggingEnabled: true)
        XCTAssertTrue(gate.isEnabled)

        gate.configureForTesting(
            loggingEnabled: false,
            environmentOverrideEnabled: true
        )
        XCTAssertTrue(gate.isEnabled)
        XCTAssertTrue(gate.isEnvironmentOverrideEnabled)
    }

    func testDisabledVoiceLoggerDoesNoFileOrWriterWorkAndEnabledStillWritesJSONL() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-diagnostics-gate-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let gate = DiagnosticsRuntimeGate.shared
        gate.configureForTesting(loggingEnabled: false)
        let logger = VoiceDiagnosticLogger(fileURL: fileURL)

        logger.startRun(fields: ["should_not": "write"])
        logger.log(category: "test", event: "disabled")
        logger.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(logger.isActiveForTesting)
        XCTAssertEqual(logger.workMetricsForTesting.queuedRecordCount, 0)
        XCTAssertEqual(logger.workMetricsForTesting.jsonSerializationCount, 0)
        XCTAssertEqual(logger.workMetricsForTesting.writeCount, 0)

        gate.configureForTesting(loggingEnabled: true)
        logger.startRun()
        logger.log(category: "test", event: "enabled")
        logger.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 2)
        let record = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(String(lines[1]).utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(record["event"] as? String, "enabled")
        XCTAssertGreaterThan(logger.workMetricsForTesting.jsonSerializationCount, 0)
        logger.close()
    }

    func testDisabledAuthorityStopsBeforeAdmissionEnqueueAndJournalAppend() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "remoteorbit-diagnostics-authority-" + UUID().uuidString
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let journal = JSONLinesDiagnosticJournal(
            fileURL: directory.appendingPathComponent("events.jsonl")
        )
        let authority = DiagnosticAuthorityService(
            journal: journal,
            runtimeContext: .current(),
            clock: SystemDiagnosticClock()
        )
        let input = try DiagnosticEventInput(
            eventType: "audio.capture.recording_started",
            subsystem: "audio.capture",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "wav_recorder",
            correlationID: "recording-1",
            payload: [
                "sample_rate": .unsignedInteger(16_000),
                "channels": .unsignedInteger(1),
                "bits_per_sample": .unsignedInteger(16),
            ]
        )

        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        authority.emit(input)
        XCTAssertEqual(
            authority.workMetricsForTesting,
            DiagnosticAuthorityWorkMetrics()
        )

        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
        authority.emit(input)
        _ = try authority.query(DiagnosticQueryFilter())
        XCTAssertEqual(authority.workMetricsForTesting.admissionAttempts, 1)
        XCTAssertEqual(authority.workMetricsForTesting.enqueuedEvents, 1)
        XCTAssertEqual(authority.workMetricsForTesting.journalAppends, 1)
    }

    func testHealthAndWatchdogTimersFollowTheEffectiveGateAndStopCleanly() {
        let authority = GateCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        let health = DiagnosticRuntimeHealthService(
            authority: authority,
            registry: registry
        )
        let watchdog = VoiceStartWatchdog(
            authority: authority,
            registry: registry,
            automaticallySchedule: true
        )

        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        health.start()
        watchdog.begin(attemptID: "attempt-1", timestampNanoseconds: 1)
        watchdog.holdConfirmed(
            attemptID: "attempt-1",
            sessionID: "session-1",
            timestampNanoseconds: 1,
            state: [:]
        )
        XCTAssertEqual(health.timerCountForTesting, 0)
        XCTAssertEqual(watchdog.timerCountForTesting, 0)

        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
        health.start()
        XCTAssertEqual(health.timerCountForTesting, 1)
        XCTAssertEqual(watchdog.timerCountForTesting, 1)

        watchdog.end(attemptID: "attempt-1")
        health.stop()
        XCTAssertEqual(health.timerCountForTesting, 0)
        XCTAssertEqual(watchdog.timerCountForTesting, 0)
    }

    func testDisabledLongTermObservabilityAndAudioPipeDoNotStartDiagnosticLifecycle() {
        let authority = GateCapturingAuthority()
        let service = LongTermObservabilityService(
            authority: authority,
            runtimeIdentity: .current()
        )
        let sessionID = UUID()

        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        service.begin(sessionID: sessionID)
        service.observeTracePoint(
            LongTermObservationPoint(
                timestampNanoseconds: 1,
                kind: .decodeComplete,
                requestedFrames: 0,
                filledFrames: 0,
                unfilledFrames: 0,
                queueDepthFrames: 0,
                byteOrSampleCount: 0,
                marker: .unclassified,
                streamIdentity: 0
            )
        )
        XCTAssertNil(service.end(sessionID: sessionID))
        XCTAssertTrue(authority.inputs.isEmpty)

        let pipe = AudioPipe.shared
        pipe.beginRemoteAudioDiagnostics()
        XCTAssertFalse(pipe.diagnosticLifecycleActiveForTesting)
        XCTAssertFalse(pipe.mainQueueProbeActiveForTesting)

        let previousRecording = AppStorage.recordingEnabled
        AppStorage.recordingEnabled = true
        XCTAssertFalse(DiagnosticsRuntimeGate.shared.isEnabled)
        AppStorage.recordingEnabled = previousRecording
    }
}

private final class GateCapturingAuthority: DiagnosticAuthority, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var inputs: [DiagnosticEventInput] = []

    var droppedEventCount: UInt64 { 0 }

    func emit(_ input: DiagnosticEventInput) {
        lock.lock()
        inputs.append(input)
        lock.unlock()
    }

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: [],
            nextCursor: nil
        )
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data { Data() }
}
