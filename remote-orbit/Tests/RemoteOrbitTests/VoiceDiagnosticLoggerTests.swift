import CoreGraphics
import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceDiagnosticLoggerTests: XCTestCase {
    func testEventIsImmediatelyReadableAsOneDurableJSONLRecord() throws {
        let fileURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let logger = makeLogger(fileURL: fileURL)

        logger.startRun(fields: ["persistent_config": "left_option"])
        logger.log(
            category: "voice",
            event: "physical_down",
            gestureID: UUID()
        )

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 2)
        let event = try XCTUnwrap(parseRecord(String(lines[1])))
        XCTAssertEqual(event["category"] as? String, "voice")
        XCTAssertEqual(event["event"] as? String, "physical_down")
        XCTAssertEqual(event["uptime"] as? Double, 42.5)
        XCTAssertNotNil(event["ts"] as? String)
        XCTAssertNotNil(event["gesture_id"] as? String)
    }

    func testKeyIdentityIncludesRawDisplayCGAndHIDValues() throws {
        let fileURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let logger = makeLogger(fileURL: fileURL)
        logger.startRun()

        logger.log(category: "voice", event: "key_identity", key: .rightOption)
        logger.log(category: "voice", event: "key_identity", key: .leftOption)

        let events = try records(at: fileURL).filter {
            $0["event"] as? String == "key_identity"
        }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0]["key"] as? String, "right_option")
        XCTAssertEqual(events[0]["key_display_name"] as? String, "Right Option")
        XCTAssertEqual(events[0]["cg_key_code"] as? Int, 61)
        XCTAssertEqual(events[0]["hid_destination"] as? String, "0x7000000E6")
        XCTAssertEqual(events[1]["key"] as? String, "left_option")
        XCTAssertEqual(events[1]["cg_key_code"] as? Int, 58)
        XCTAssertEqual(events[1]["hid_destination"] as? String, "0x7000000E2")
    }

    func testHIDReadbackParserDistinguishesMatchMismatchEmptyAndInvalid() {
        let rightMapping = """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":"0x70000003E","HIDKeyboardModifierMappingDst":"0x7000000E6"}]}
        """
        let leftMapping = """
        UserKeyMapping: ({ HIDKeyboardModifierMappingSrc = 30064771134; HIDKeyboardModifierMappingDst = 30064771298; })
        """

        XCTAssertEqual(
            VoiceDiagnosticHIDMappingParser.verify(
                stdout: rightMapping,
                stderr: "",
                exitStatus: 0,
                requested: .rightOption
            ),
            .match
        )
        XCTAssertEqual(
            VoiceDiagnosticHIDMappingParser.verify(
                stdout: leftMapping,
                stderr: "",
                exitStatus: 0,
                requested: .rightOption
            ),
            .mismatch
        )
        XCTAssertEqual(
            VoiceDiagnosticHIDMappingParser.verify(
                stdout: "",
                stderr: "",
                exitStatus: 0,
                requested: .rightOption
            ),
            .empty
        )
        XCTAssertEqual(
            VoiceDiagnosticHIDMappingParser.verify(
                stdout: "not a hid mapping",
                stderr: "",
                exitStatus: 0,
                requested: .rightOption
            ),
            .unparseable
        )
    }

    func testPersistentCloseDiagnosticUsesFrozenOpenOwnerAfterReconfiguration() throws {
        let fileURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let logger = makeLogger(fileURL: fileURL)
        logger.startRun()
        let trigger = VoiceOptionTrigger(
            keyedEventSink: { _, _ in },
            diagnosticLogger: logger
        )
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            diagnosticLogger: logger
        )

        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.rightOption))
        shortPersistentToggle(press)
        XCTAssertEqual(press.persistentSessionTriggerOwnerKeyForTesting, .rightOption)
        XCTAssertTrue(press.configurePersistentSessionTriggerKey(.leftOption))
        shortPersistentToggle(press)

        let changes = try records(at: fileURL).filter {
            $0["event"] as? String == "PERSISTENT_STATE_CHANGE"
        }
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0]["to"] as? String, "persistent_open")
        XCTAssertEqual(changes[0]["owner_key"] as? String, "right_option")
        XCTAssertEqual(changes[1]["closing_key"] as? String, "right_option")
        XCTAssertEqual(changes[1]["to"] as? String, "idle")
    }

    func testMappedTriggerMismatchIsLoggedWithObservedAndConfiguredKeys() throws {
        let fileURL = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let logger = makeLogger(fileURL: fileURL)
        logger.startRun()
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(
            syntheticOptionTrigger: trigger,
            diagnosticLogger: logger
        )
        XCTAssertTrue(filter.configureVoiceTriggerKey(.leftOption))

        filter.recordMappedTriggerEventForTesting(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode,
            eventType: .keyDown,
            flags: [],
            syntheticMarker: false,
            action: "unmatched_pass"
        )

        let events = try records(at: fileURL)
        let mismatch = try XCTUnwrap(events.first {
            $0["event"] as? String == "MAPPED_TRIGGER_MISMATCH"
        })
        XCTAssertEqual(mismatch["observed"] as? String, "right_option")
        XCTAssertEqual(mismatch["configured"] as? String, "left_option")
        XCTAssertEqual(mismatch["event_type"] as? String, "key_down")
    }

    func testOldHardCodedLeftOptionHoldMessagesAreRemoved() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/RemoteOrbit/main.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("LONG uses hardware-held left Option"))
        XCTAssertFalse(source.contains("LONG uses synthetic left Option"))
    }

    private func shortPersistentToggle(_ press: VoicePressCoordinator) {
        XCTAssertTrue(press.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true
        ))
        XCTAssertTrue(press.keyUp())
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))
    }

    private func makeLogger(fileURL: URL) -> VoiceDiagnosticLogger {
        VoiceDiagnosticLogger(
            fileURL: fileURL,
            dateProvider: { Date(timeIntervalSince1970: 1_790_774_201.123) },
            uptimeProvider: { 42.5 },
            processIdentifierProvider: { 123 }
        )
    }

    private func temporaryLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-diagnostic-\(UUID().uuidString).jsonl")
    }

    private func records(at fileURL: URL) throws -> [[String: Any]] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents
            .split(whereSeparator: \.isNewline)
            .map { line in
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
                return try XCTUnwrap(object as? [String: Any])
            }
    }

    private func parseRecord(_ line: String) throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        return object as? [String: Any]
    }
}
