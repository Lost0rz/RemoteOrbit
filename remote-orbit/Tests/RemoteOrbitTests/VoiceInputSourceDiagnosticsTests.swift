import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceInputSourceDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
    }

    override func tearDown() {
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        super.tearDown()
    }

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
            source: .hidMonitor
        )
        XCTAssertTrue(voicePress.promoteLongOnlyCandidateForTesting())
        controller.finishVoicePressRelease(source: .hidMonitor, stopVoiceInput: {})

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
        let opening = try XCTUnwrap(records.first {
            $0["event"] as? String == "VOICE_SESSION_OPENING"
        })
        let release = try XCTUnwrap(records.first {
            $0["event"] as? String == "VOICE_RELEASE_ENTRY"
        })

        XCTAssertEqual(press["source"] as? String, "hid_monitor")
        XCTAssertEqual(release["source"] as? String, "hid_monitor")
        XCTAssertEqual(press["gesture_id"] as? String, opening["gesture_id"] as? String)
        XCTAssertEqual(release["gesture_id"] as? String, opening["gesture_id"] as? String)
        XCTAssertNotNil(press["observer_uptime"])
        XCTAssertNotNil(release["observer_uptime"])

        voicePress.stop()
    }
}
