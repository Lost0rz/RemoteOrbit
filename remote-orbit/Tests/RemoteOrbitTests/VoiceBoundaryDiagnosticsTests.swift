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
        filter.recordMappedTriggerEventForTesting(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            eventType: .flagsChanged,
            flags: .maskAlternate,
            eventTimestamp: 123_456_789,
            syntheticMarker: false,
            action: "pass"
        )
        XCTAssertFalse(filter.hasActiveHardwareTriggerOwnership)

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

        XCTAssertEqual(
            (record["cg_event_timestamp_ns"] as? NSNumber)?.uint64Value,
            123_456_789
        )
        XCTAssertEqual(
            (record["cg_event_uptime_seconds"] as? NSNumber)?.doubleValue ?? -1,
            0.123456789,
            accuracy: 0.000000001
        )
        XCTAssertNotNil(record["observer_uptime"])
        XCTAssertEqual(record["action"] as? String, "pass")
        XCTAssertEqual(record["gate_state"] as? String, "none")
    }
}
