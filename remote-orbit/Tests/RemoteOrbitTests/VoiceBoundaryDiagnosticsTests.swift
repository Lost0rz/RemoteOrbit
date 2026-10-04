import CoreGraphics
import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceBoundaryDiagnosticsTests: XCTestCase {
    func testMappedTriggerRecordPreservesOriginalCGEventTimestampWithoutChangingOwnership() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-boundary-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let logger = VoiceDiagnosticLogger(fileURL: fileURL)
        logger.startRun()
        let trigger = VoiceOptionTrigger(
            keyedEventSink: { _, _ in },
            diagnosticLogger: logger
        )
        let filter = VoiceKeyFilter(
            syntheticOptionTrigger: trigger,
            diagnosticLogger: logger
        )

        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertFalse(filter.hasSyntheticTriggerOwnership)
        filter.recordMappedTriggerEventForTesting(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            eventType: .flagsChanged,
            flags: .maskAlternate,
            eventTimestamp: 123_456_789,
            syntheticMarker: false,
            action: "pass"
        )
        filter.recordMappedTriggerEventForTesting(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            eventType: .keyDown,
            flags: [],
            eventTimestamp: 987_654_321,
            syntheticMarker: true,
            action: "pass"
        )
        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)
        XCTAssertFalse(filter.hasSyntheticTriggerOwnership)

        logger.flush()
        logger.close()

        let records = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
        let record = try XCTUnwrap(records.first {
            $0["event"] as? String == "MAPPED_TRIGGER_EVENT"
        })
        let syntheticRecord = try XCTUnwrap(records.last {
            $0["event"] as? String == "MAPPED_TRIGGER_EVENT"
        })

        XCTAssertEqual(
            (record["cg_event_timestamp_raw"] as? NSNumber)?.uint64Value,
            123_456_789
        )
        XCTAssertEqual(record["cg_event_timestamp_clock"] as? String, "quartz_event_timestamp_raw")
        XCTAssertNil(record["cg_event_timestamp_ns"])
        XCTAssertNil(record["cg_event_uptime_seconds"])
        XCTAssertNotNil(record["observer_uptime"])
        XCTAssertEqual(record["action"] as? String, "pass")
        XCTAssertEqual(record["gate_state"] as? String, "none")
        XCTAssertFalse(record["synthetic_marker"] as? Bool ?? true)
        XCTAssertEqual(
            (syntheticRecord["cg_event_timestamp_raw"] as? NSNumber)?.uint64Value,
            987_654_321
        )
        XCTAssertEqual(syntheticRecord["cg_event_timestamp_clock"] as? String, "quartz_event_timestamp_raw")
        XCTAssertNil(syntheticRecord["cg_event_timestamp_ns"])
        XCTAssertNil(syntheticRecord["cg_event_uptime_seconds"])
        XCTAssertEqual(syntheticRecord["action"] as? String, "pass")
        XCTAssertEqual(syntheticRecord["gate_state"] as? String, "none")
        XCTAssertTrue(syntheticRecord["synthetic_marker"] as? Bool ?? false)
    }

    func testRunStartRecordsValidMachTimebaseAndCalibrationAnchor() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-clock-anchor-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let logger = VoiceDiagnosticLogger(fileURL: fileURL)
        logger.startRun(fields: P1A4MonotonicClock.runStartCalibrationFields())
        logger.flush()
        logger.close()

        let records = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
        let runStart = try XCTUnwrap(records.first { $0["event"] as? String == "RUN_START" })

        let numerator = try XCTUnwrap((runStart["mach_timebase_numer"] as? NSNumber)?.uint32Value)
        let denominator = try XCTUnwrap((runStart["mach_timebase_denom"] as? NSNumber)?.uint32Value)
        let machAnchor = try XCTUnwrap((runStart["anchor_mach_absolute_raw"] as? NSNumber)?.uint64Value)
        let uptimeAnchor = try XCTUnwrap((runStart["anchor_process_uptime_seconds"] as? NSNumber)?.doubleValue)
        XCTAssertGreaterThan(numerator, 0)
        XCTAssertGreaterThan(denominator, 0)
        XCTAssertGreaterThan(machAnchor, 0)
        XCTAssertGreaterThan(uptimeAnchor, 0)
    }
}
