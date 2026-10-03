import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceInputSourceDiagnosticsTests: XCTestCase {
    func testPressAndReleaseEntriesRetainHIDInputSourceAndGestureIdentity() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-source-\(UUID().uuidString).jsonl")
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
        let voicePress = VoicePressCoordinator(
            optionTrigger: trigger,
            diagnosticLogger: logger
        )
        let controller = AppController(
            filter: filter,
            voicePress: voicePress,
            initiallyHIDConnected: true,
            diagnosticLogger: logger
        )

        controller.beginVoicePress(
            targetApplicationBundleIdentifier: "org.example.RemoteOrbitTests",
            shortBinding: .voiceKeyDefault,
            source: .hidMonitor
        )
        controller.recordVoiceReleaseEntry(source: .hidMonitor)

        logger.flush()
        logger.close()

        let records = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }

        let press = try XCTUnwrap(records.first {
            $0["event"] as? String == "VOICE_PRESS_ENTRY"
        })
        let gesture = try XCTUnwrap(records.first {
            $0["event"] as? String == "GESTURE_BEGIN"
        })
        let release = try XCTUnwrap(records.first {
            $0["event"] as? String == "VOICE_RELEASE_ENTRY"
        })

        XCTAssertEqual(press["source"] as? String, "hid_monitor")
        XCTAssertEqual(release["source"] as? String, "hid_monitor")
        XCTAssertEqual(press["gesture_id"] as? String, gesture["gesture_id"] as? String)
        XCTAssertEqual(release["gesture_id"] as? String, gesture["gesture_id"] as? String)
        XCTAssertNotNil(press["observer_uptime"])
        XCTAssertNotNil(release["observer_uptime"])

        voicePress.stop()
    }
}
