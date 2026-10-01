import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceInputSourceDiagnosticsTests: XCTestCase {
    func testPressAndReleaseEntriesRetainInputSourceAndJoinGestureBegin() throws {
        for source in [VoicePressInputSource.hidMonitor, .voiceKeyFilterFallback] {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("remoteorbit-source-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let logger = VoiceDiagnosticLogger(fileURL: fileURL)
            logger.startRun()

            let trigger = VoiceOptionTrigger(
                keyedEventSink: { _, _ in },
                diagnosticLogger: logger
            )
            let voicePress = VoicePressCoordinator(
                optionTrigger: trigger,
                diagnosticLogger: logger
            )
            let filter = VoiceKeyFilter(
                syntheticOptionTrigger: trigger,
                diagnosticLogger: logger
            )
            let isHIDSource = source.rawValue == VoicePressInputSource.hidMonitor.rawValue
            filter.skipVoiceKey = isHIDSource
            let controller = AppController(
                filter: filter,
                voicePress: voicePress,
                initiallyHIDConnected: isHIDSource,
                diagnosticLogger: logger
            )

            controller.beginVoicePress(
                targetApplicationBundleIdentifier: "org.example.RemoteOrbitTests",
                shortBinding: .voiceKeyDefault,
                source: source
            )
            controller.recordVoiceReleaseEntry(source: source)
            logger.flush()

            let records = try readRecords(at: fileURL)
            let pressEntry = try XCTUnwrap(records.first {
                $0["event"] as? String == "VOICE_PRESS_ENTRY"
            })
            let gestureBegin = try XCTUnwrap(records.first {
                $0["event"] as? String == "GESTURE_BEGIN"
            })
            let releaseEntry = try XCTUnwrap(records.first {
                $0["event"] as? String == "VOICE_RELEASE_ENTRY"
            })

            XCTAssertEqual(pressEntry["source"] as? String, source.rawValue)
            XCTAssertEqual(pressEntry["hid_connected"] as? Bool, isHIDSource)
            XCTAssertEqual(pressEntry["filter_skip_voice_key"] as? Bool, isHIDSource)
            XCTAssertEqual(pressEntry["momentary_key"] as? String, "left_option")
            XCTAssertEqual(pressEntry["persistent_key"] as? String, "left_option")
            XCTAssertEqual(pressEntry["gesture_id"] as? String, gestureBegin["gesture_id"] as? String)
            XCTAssertEqual(releaseEntry["source"] as? String, source.rawValue)
            XCTAssertEqual(releaseEntry["gesture_id"] as? String, gestureBegin["gesture_id"] as? String)

            voicePress.stop()
            logger.close()
        }
    }

    private func readRecords(at fileURL: URL) throws -> [[String: Any]] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(whereSeparator: \.isNewline).map { line in
            let data = Data(line.utf8)
            return try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
        }
    }
}
