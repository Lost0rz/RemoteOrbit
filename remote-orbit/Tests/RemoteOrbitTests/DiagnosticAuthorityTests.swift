import Foundation
import XCTest
@testable import RemoteOrbit

final class DiagnosticAuthorityTests: XCTestCase {
    func testSnapshotHasVersionedEnvelopeAndClockProvenance() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = FixedDiagnosticClock(stamp: fixedStamp())
        let authority = makeAuthority(
            journal: JSONLinesDiagnosticJournal(
                fileURL: directory.appendingPathComponent("events.jsonl")
            ),
            clock: clock
        )

        authority.emit(try makeInput())
        let snapshot = try authority.snapshot(DiagnosticQueryFilter())
        let page = try XCTUnwrap(
            JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        )
        XCTAssertEqual(page["schema_version"] as? Int, 1)
        let events = try XCTUnwrap(page["events"] as? [[String: Any]])
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event["schema_version"] as? Int, 1)
        XCTAssertNotNil(event["event_id"] as? String)
        XCTAssertEqual(event["event_type"] as? String, "audio.capture.recording_started")
        XCTAssertEqual(event["subsystem"] as? String, "audio.capture")
        XCTAssertEqual(event["source_component"] as? String, "wav_recorder")
        XCTAssertEqual(event["process_instance_id"] as? String, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(event["process_id"] as? Int, 77)
        XCTAssertEqual(event["source_revision"] as? String, "abc123")
        XCTAssertNil(event["eventType"])

        let timestamp = try XCTUnwrap(event["timestamp"] as? [String: Any])
        XCTAssertEqual(timestamp["wall_timestamp_unix_ms"] as? Int64, 1_790_774_201_123)
        let monotonic = try XCTUnwrap(timestamp["monotonic"] as? [String: Any])
        XCTAssertEqual(monotonic["clock_domain"] as? String, "mach_continuous_time")
        XCTAssertEqual(monotonic["value_nanoseconds"] as? UInt64, 5_000)
        XCTAssertEqual(monotonic["raw_ticks"] as? UInt64, 120)
        XCTAssertEqual(monotonic["timebase_numerator"] as? UInt32, 125)
        XCTAssertEqual(monotonic["timebase_denominator"] as? UInt32, 3)
    }

    func testQueryFiltersPaginatesAndKeepsJournalOrder() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = makeAuthority(
            journal: JSONLinesDiagnosticJournal(
                fileURL: directory.appendingPathComponent("events.jsonl")
            ),
            maximumPendingEvents: 8
        )
        authority.emit(try makeInput(eventType: "audio.capture.recording_started"))
        authority.emit(try makeInput(eventType: "audio.capture.recording_closed"))
        authority.emit(try makeInput(eventType: "audio.capture.recording_started"))

        let filter = try DiagnosticQueryFilter(
            eventTypes: ["audio.capture.recording_started"],
            limit: 1
        )
        let firstPage = try authority.query(filter)
        XCTAssertEqual(firstPage.events.map(\.eventType), ["audio.capture.recording_started"])
        let cursor = try XCTUnwrap(firstPage.nextCursor)

        let secondPage = try authority.query(
            DiagnosticQueryFilter(
                eventTypes: ["audio.capture.recording_started"],
                cursor: cursor,
                limit: 1
            )
        )
        XCTAssertEqual(secondPage.events.map(\.eventType), ["audio.capture.recording_started"])
        XCTAssertNil(secondPage.nextCursor)
        XCTAssertNotEqual(firstPage.events[0].eventID, secondPage.events[0].eventID)
    }

    func testInvalidFiltersFailClosed() throws {
        XCTAssertThrowsError(try DiagnosticQueryFilter(limit: 0)) { error in
            XCTAssertEqual(
                error as? DiagnosticQueryError,
                .invalidFilter("limit must be between 1 and 500")
            )
        }
        XCTAssertThrowsError(try DiagnosticQueryFilter(eventTypes: ["NOT A TOKEN"]))
        XCTAssertThrowsError(try DiagnosticQueryFilter(cursor: "not-a-cursor"))
        XCTAssertThrowsError(try makeInput(eventType: "Invalid.Event"))
        XCTAssertThrowsError(try makeInput(eventType: "test.capture.started"))
        XCTAssertThrowsError(try DiagnosticEventInput(
            eventType: "audio.capture.recording_started",
            subsystem: "audio.capture",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "wav_recorder",
            payload: ["unexpected": .string("not allowed")]
        ))
        XCTAssertThrowsError(try DiagnosticEventInput(
            eventType: "audio.capture.recording_started",
            subsystem: "audio.capture",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "wav_recorder",
            payload: [
                "sample_rate": .string("16000"),
                "channels": .unsignedInteger(1),
                "bits_per_sample": .unsignedInteger(16),
            ]
        ))
        let validInput = try makeInput()
        XCTAssertThrowsError(try DiagnosticEventInput(
            eventType: validInput.eventType,
            subsystem: validInput.subsystem,
            category: validInput.category,
            severity: validInput.severity,
            sourceComponent: validInput.sourceComponent,
            sourceTimestamp: DiagnosticRawTimestamp(
                value: 120,
                unit: "ticks",
                clockDomain: "source_clock",
                timebaseNumerator: 0,
                timebaseDenominator: 1
            ),
            payload: validInput.payload
        ))
    }

    func testLongTermObservationPayloadsAreRegisteredAndMachineReadable() throws {
        let summary = try DiagnosticEventInput(
            eventType: "voice.session.summary",
            subsystem: "voice.session",
            category: "summary",
            severity: .info,
            sourceComponent: "long_term_observability",
            sessionID: "session-1",
            payload: [
                "summary": .object([
                    "observation_schema_version": .unsignedInteger(1),
                    "anomaly_flags": .array([]),
                ]),
            ]
        )
        let trace = try DiagnosticEventInput(
            eventType: "voice.session.trace",
            subsystem: "voice.session",
            category: "trace",
            severity: .warning,
            sourceComponent: "long_term_observability",
            sessionID: "session-1",
            incidentID: "incident-1",
            payload: [
                "capture_id": .string("capture-1"),
                "chunk_index": .unsignedInteger(0),
                "chunk_count": .unsignedInteger(1),
                "observation_schema_version": .unsignedInteger(1),
                "observations": .array([
                    .object(["kind": .string("render"), "timestamp_nanoseconds": .unsignedInteger(10)])
                ]),
                "dropped_observations": .unsignedInteger(0),
            ]
        )

        XCTAssertEqual(summary.eventType, "voice.session.summary")
        XCTAssertEqual(trace.eventType, "voice.session.trace")
    }

    func testQueryFiltersByWallClockWindow() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("events.jsonl")
        let journal = JSONLinesDiagnosticJournal(fileURL: fileURL)

        try journal.append(makeEvent(wallMilliseconds: 100, sequence: 1))
        try journal.append(makeEvent(wallMilliseconds: 200, sequence: 2))
        try journal.append(makeEvent(wallMilliseconds: 300, sequence: 3))

        let filter = try DiagnosticQueryFilter(
            startWallTimestampUnixMilliseconds: 150,
            endWallTimestampUnixMilliseconds: 250,
            limit: 10
        )
        let page = try journal.query(filter)
        XCTAssertEqual(page.events.map(\.sequenceNumber), [2])
    }

    func testRotatesRetainsAndQueriesAcrossBoundedSegments() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("events.jsonl")
        let journal = JSONLinesDiagnosticJournal(
            fileURL: fileURL,
            retentionPolicy: .init(maxSegmentBytes: 1, maxSegmentCount: 3)
        )

        for sequence in UInt64(1)...4 {
            try journal.append(makeEvent(wallMilliseconds: Int64(sequence), sequence: sequence))
        }

        XCTAssertEqual(journal.segmentURLs().count, 3)
        let page = try journal.query(DiagnosticQueryFilter(limit: 10))
        XCTAssertEqual(page.events.map(\.sequenceNumber), [2, 3, 4])

        let firstPage = try journal.query(DiagnosticQueryFilter(limit: 1))
        let cursor = try XCTUnwrap(firstPage.nextCursor)
        let secondPage = try journal.query(DiagnosticQueryFilter(cursor: cursor, limit: 1))
        XCTAssertEqual(secondPage.events.map(\.sequenceNumber), [3])
    }

    func testPartialTrailingRecordIsRepairedAndPreservesHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let validLine = try JSONEncoder().encode(makeEvent(wallMilliseconds: 100, sequence: 1))
        var data = validLine
        data.append(0x0A)
        data.append(contentsOf: Data("{\"schema_version\":1".utf8))
        try data.write(to: fileURL)

        let journal = JSONLinesDiagnosticJournal(fileURL: fileURL)
        try journal.append(makeEvent(wallMilliseconds: 200, sequence: 2))

        let page = try journal.query(DiagnosticQueryFilter(limit: 10))
        XCTAssertEqual(page.events.map(\.sequenceNumber), [1, 2])
        XCTAssertEqual(try Data(contentsOf: fileURL).last, 0x0A)
    }

    func testInteriorMalformedCompleteRecordStillFailsClosed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let validLine = try JSONEncoder().encode(makeEvent(wallMilliseconds: 100, sequence: 1))
        var data = validLine
        data.append(0x0A)
        data.append(contentsOf: Data("{\"malformed\":true}\n".utf8))
        data.append(contentsOf: validLine)
        data.append(0x0A)
        try data.write(to: fileURL)

        XCTAssertThrowsError(try JSONLinesDiagnosticJournal(fileURL: fileURL).query(
            DiagnosticQueryFilter()
        )) { error in
            XCTAssertEqual(error as? DiagnosticQueryError, .corruptJournal(2))
        }
    }

    func testUnknownSchemaVersionStopsTheWholeQuery() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("{\"schema_version\":2}\n".utf8).write(to: fileURL)

        let journal = JSONLinesDiagnosticJournal(fileURL: fileURL)
        XCTAssertThrowsError(try journal.query(DiagnosticQueryFilter())) { error in
            XCTAssertEqual(error as? DiagnosticQueryError, .unsupportedSchemaVersion(2))
        }
    }

    func testBlankJournalRecordFailsClosed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("events.jsonl")
        try Data("\n".utf8).write(to: fileURL)

        XCTAssertThrowsError(try JSONLinesDiagnosticJournal(fileURL: fileURL).query(
            DiagnosticQueryFilter()
        )) { error in
            XCTAssertEqual(error as? DiagnosticQueryError, .corruptJournal(1))
        }
    }

    func testInvalidClockProvenanceFailsClosed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let event = DiagnosticEvent(
            input: try makeInput(),
            context: DiagnosticRuntimeContext(
                processInstanceID: UUID(),
                processID: 77,
                binaryPath: "/tmp/test",
                appVersion: "1",
                buildVersion: "1",
                sourceRevision: nil
            ),
            timestamp: Self.fixedStamp(),
            sequenceNumber: 1
        )
        let validLine = try XCTUnwrap(
            String(data: JSONEncoder().encode(event), encoding: .utf8)
        )
        var invalidLines = [
            Data((validLine.replacingOccurrences(
                of: "\"timebase_denominator\":3",
                with: "\"timebase_denominator\":0"
            ) + "\n").utf8),
            Data((validLine.replacingOccurrences(
                of: "\"clock_domain\":\"mach_continuous_time\"",
                with: "\"clock_domain\":\"unknown_clock\""
            ) + "\n").utf8),
        ]

        let baseInput = try makeInput()
        let rawTimestamp = DiagnosticRawTimestamp(
            value: 120,
            unit: "ticks",
            clockDomain: "source_clock",
            timebaseNumerator: 1,
            timebaseDenominator: 1
        )
        let inputWithSourceClock = try DiagnosticEventInput(
            eventType: baseInput.eventType,
            subsystem: baseInput.subsystem,
            category: baseInput.category,
            severity: baseInput.severity,
            sourceComponent: baseInput.sourceComponent,
            correlationID: baseInput.correlationID,
            sourceTimestamp: rawTimestamp,
            payload: baseInput.payload
        )
        let sourceEvent = DiagnosticEvent(
            input: inputWithSourceClock,
            context: DiagnosticRuntimeContext(
                processInstanceID: UUID(),
                processID: 77,
                binaryPath: "/tmp/test",
                appVersion: "1",
                buildVersion: "1",
                sourceRevision: nil
            ),
            timestamp: Self.fixedStamp(),
            sequenceNumber: 1
        )
        var sourceEnvelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(sourceEvent)) as? [String: Any]
        )
        var invalidSourceTimestamp = try XCTUnwrap(
            sourceEnvelope["source_timestamp"] as? [String: Any]
        )
        invalidSourceTimestamp["clock_domain"] = ""
        invalidSourceTimestamp["timebase_denominator"] = 0
        sourceEnvelope["source_timestamp"] = invalidSourceTimestamp
        invalidLines.append(try JSONSerialization.data(withJSONObject: sourceEnvelope))

        for invalidLine in invalidLines {
            let fileURL = directory.appendingPathComponent("events-\(UUID().uuidString).jsonl")
            var record = invalidLine
            record.append(0x0A)
            try record.write(to: fileURL)
            XCTAssertThrowsError(try JSONLinesDiagnosticJournal(fileURL: fileURL).query(
                DiagnosticQueryFilter()
            )) { error in
                XCTAssertEqual(error as? DiagnosticQueryError, .corruptJournal(1))
            }
        }
    }

    func testEmitDoesNotWaitForJournalIOAndJournalFailureIsCounted() throws {
        let journal = BlockingDiagnosticJournal()
        let authority = makeAuthority(
            journal: journal,
            maximumPendingEvents: 4
        )

        authority.emit(try makeInput())
        XCTAssertEqual(journal.firstAppendEntered.wait(timeout: .now() + 2), .success)

        let startedAt = DispatchTime.now().uptimeNanoseconds
        authority.emit(try makeInput())
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
        XCTAssertLessThan(elapsed, 0.1)

        journal.releaseFirstAppend.signal()
        XCTAssertEqual(try authority.query(DiagnosticQueryFilter()).events.count, 2)

        let failingAuthority = makeAuthority(journal: FailingDiagnosticJournal())
        failingAuthority.emit(try makeInput())
        _ = try failingAuthority.query(DiagnosticQueryFilter())
        XCTAssertEqual(failingAuthority.droppedEventCount, 1)
        XCTAssertEqual(failingAuthority.writeFailureCount, 1)
    }

    func testQueueSaturationDropsEventWithoutBlockingProducerAndCountsDrop() throws {
        let journal = BlockingDiagnosticJournal()
        let authority = makeAuthority(
            journal: journal,
            maximumPendingEvents: 1
        )
        defer { journal.releaseFirstAppend.signal() }

        authority.emit(try makeInput())
        XCTAssertEqual(journal.firstAppendEntered.wait(timeout: .now() + 2), .success)

        let droppedInput = try makeInput(eventType: "audio.capture.recording_closed")
        let producerReturned = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            authority.emit(droppedInput)
            producerReturned.signal()
        }

        let returnedWhileJournalBlocked = producerReturned.wait(timeout: .now() + 1)
        XCTAssertEqual(returnedWhileJournalBlocked, .success)
        XCTAssertEqual(authority.droppedEventCount, 1)

        journal.releaseFirstAppend.signal()
        let events = try authority.query(DiagnosticQueryFilter(limit: 10)).events
        XCTAssertEqual(events.map(\.eventType), ["audio.capture.recording_started"])
        XCTAssertEqual(authority.droppedEventCount, 1)
    }

    func testConcurrentEmitsHaveUniqueIDsAndMonotonicJournalSequence() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = makeAuthority(
            journal: JSONLinesDiagnosticJournal(
                fileURL: directory.appendingPathComponent("events.jsonl")
            ),
            maximumPendingEvents: 256
        )
        let input = try makeInput()

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            authority.emit(input)
        }

        let events = try authority.query(DiagnosticQueryFilter(limit: 200)).events
        XCTAssertEqual(events.count, 100)
        XCTAssertEqual(Set(events.map(\.eventID)).count, 100)
        XCTAssertEqual(events.map(\.sequenceNumber), Array(1...100).map(UInt64.init))
    }

    private func makeAuthority(
        journal: any DiagnosticJournal,
        clock: any DiagnosticClock = FixedDiagnosticClock(stamp: fixedStamp()),
        maximumPendingEvents: Int = 256
    ) -> DiagnosticAuthorityService {
        DiagnosticAuthorityService(
            journal: journal,
            runtimeContext: DiagnosticRuntimeContext(
                processInstanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                processID: 77,
                binaryPath: "/tmp/RemoteOrbit-test",
                appVersion: "1.2.3",
                buildVersion: "45",
                sourceRevision: "abc123"
            ),
            clock: clock,
            maximumPendingEvents: maximumPendingEvents,
            queueLabel: "com.remoteorbit.test.diagnostic-authority.\(UUID().uuidString)"
        )
    }

    private func makeInput(
        eventType: String = "audio.capture.recording_started"
    ) throws -> DiagnosticEventInput {
        let payload: [String: DiagnosticJSONValue]
        if eventType == "audio.capture.recording_started" {
            payload = [
                "sample_rate": .unsignedInteger(16_000),
                "channels": .unsignedInteger(1),
                "bits_per_sample": .unsignedInteger(16),
            ]
        } else {
            payload = [
                "sample_count": .unsignedInteger(16),
                "recorded_duration_ms": .double(1),
            ]
        }
        return try DiagnosticEventInput(
            eventType: eventType,
            subsystem: "audio.capture",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "wav_recorder",
            correlationID: "recording-1",
            payload: payload
        )
    }

    private func makeEvent(wallMilliseconds: Int64, sequence: UInt64) -> DiagnosticEvent {
        DiagnosticEvent(
            input: try! makeInput(),
            context: DiagnosticRuntimeContext(
                processInstanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                processID: 77,
                binaryPath: "/tmp/RemoteOrbit-test",
                appVersion: "1.2.3",
                buildVersion: "45",
                sourceRevision: "abc123"
            ),
            timestamp: DiagnosticClockStamp(
                wallTimestampUnixMilliseconds: wallMilliseconds,
                monotonic: DiagnosticMonotonicTimestamp(
                    valueNanoseconds: UInt64(max(0, wallMilliseconds)) * 1_000_000,
                    clockDomain: "mach_continuous_time",
                rawTicks: UInt64(max(0, wallMilliseconds)) * 1_000_000,
                    timebaseNumerator: 1,
                    timebaseDenominator: 1
                )
            ),
            sequenceNumber: sequence
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-diagnostic-\(UUID().uuidString)", isDirectory: true)
    }

    private static func fixedStamp() -> DiagnosticClockStamp {
        DiagnosticClockStamp(
            wallTimestampUnixMilliseconds: 1_790_774_201_123,
            monotonic: DiagnosticMonotonicTimestamp(
                valueNanoseconds: 5_000,
                clockDomain: "mach_continuous_time",
                rawTicks: 120,
                timebaseNumerator: 125,
                timebaseDenominator: 3
            )
        )
    }

    private func fixedStamp() -> DiagnosticClockStamp {
        Self.fixedStamp()
    }
}

private struct FixedDiagnosticClock: DiagnosticClock {
    let stamp: DiagnosticClockStamp
    func capture() -> DiagnosticClockStamp { stamp }
}

private final class BlockingDiagnosticJournal: DiagnosticJournal, @unchecked Sendable {
    let firstAppendEntered = DispatchSemaphore(value: 0)
    let releaseFirstAppend = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var shouldBlock = true
    private var events: [DiagnosticEvent] = []

    func append(_ event: DiagnosticEvent) throws {
        lock.lock()
        let block = shouldBlock
        shouldBlock = false
        lock.unlock()

        if block {
            firstAppendEntered.signal()
            releaseFirstAppend.wait()
        }

        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        lock.lock()
        let matching = events.filter(filter.matches)
        lock.unlock()
        return DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: Array(matching.prefix(filter.limit)),
            nextCursor: nil
        )
    }
}

private struct FailingDiagnosticJournal: DiagnosticJournal {
    func append(_ event: DiagnosticEvent) throws {
        throw DiagnosticQueryError.storageUnavailable
    }

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: [],
            nextCursor: nil
        )
    }
}
