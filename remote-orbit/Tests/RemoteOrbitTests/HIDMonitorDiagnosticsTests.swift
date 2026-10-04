import Foundation
import XCTest
@testable import RemoteOrbit

final class HIDMonitorDiagnosticsTests: XCTestCase {
    func testMicrophoneDownTransitionCapturesRawReportAndSequence() throws {
        let usage = RemoteButton.microphone.hidUsage
        let data = Data([UInt8(usage & 0xff), UInt8(usage >> 8)])
        let parsed = try XCTUnwrap(HIDMonitor.parseUsages(reportID: 1, data: data))

        let fields = try XCTUnwrap(HIDMonitor.microphoneTransitionDiagnosticFields(
            reportID: 1,
            data: data,
            parsedUsages: parsed,
            activeUsages: [],
            pendingReconnectUsages: [],
            deviceActive: true,
            sequence: 42,
            uptime: 123.5
        ))

        XCTAssertEqual(fields["report_id"] as? Int, 1)
        XCTAssertEqual(fields["report_length"] as? Int, data.count)
        XCTAssertEqual(fields["raw_hex"] as? String,
                       data.map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(fields["parsed_usages"] as? [Int], [Int(usage)])
        XCTAssertEqual(fields["previous_mic_down"] as? Bool, false)
        XCTAssertEqual(fields["current_mic_down"] as? Bool, true)
        XCTAssertEqual(fields["computed_edge"] as? String, "down")
        XCTAssertEqual(fields["event_uptime"] as? TimeInterval, 123.5)
        XCTAssertEqual(fields["hid_report_sequence"] as? UInt64, 42)
        XCTAssertEqual(fields["source"] as? String, "iohid_report")
    }

    func testPendingReconnectMicrophoneReleaseIsReported() throws {
        let usage = RemoteButton.microphone.hidUsage
        let data = Data([0, 0])
        let parsed = try XCTUnwrap(HIDMonitor.parseUsages(reportID: 1, data: data))

        let fields = try XCTUnwrap(HIDMonitor.microphoneTransitionDiagnosticFields(
            reportID: 1,
            data: data,
            parsedUsages: parsed,
            activeUsages: [],
            pendingReconnectUsages: [usage],
            deviceActive: true,
            sequence: 43,
            uptime: 124.0
        ))

        XCTAssertEqual(fields["previous_mic_down"] as? Bool, true)
        XCTAssertEqual(fields["current_mic_down"] as? Bool, false)
        XCTAssertEqual(fields["computed_edge"] as? String, "up")
        XCTAssertEqual(fields["hid_report_sequence"] as? UInt64, 43)
    }

    func testStableMicrophoneStateCreatesNoTransitionRecord() throws {
        let usage = RemoteButton.microphone.hidUsage
        let data = Data([UInt8(usage & 0xff), UInt8(usage >> 8)])
        let parsed = try XCTUnwrap(HIDMonitor.parseUsages(reportID: 1, data: data))

        XCTAssertNil(HIDMonitor.microphoneTransitionDiagnosticFields(
            reportID: 1,
            data: data,
            parsedUsages: parsed,
            activeUsages: [usage],
            pendingReconnectUsages: [],
            deviceActive: true,
            sequence: 44,
            uptime: 125.0
        ))
    }
}
