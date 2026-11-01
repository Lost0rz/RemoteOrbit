import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceBoundaryOrderingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
    }

    override func tearDown() {
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        super.tearDown()
    }

    func testPressEntryIsEnqueuedAfterKeyDownGateAndKeepsEntryUptime() throws {
        let harness = makeHarness(uptimes: [123.456])
        defer { harness.close() }

        harness.controller.beginVoicePress(
            targetApplicationBundleIdentifier: "org.example.RemoteOrbitTests",
            source: .hidMonitor
        )
        XCTAssertTrue(harness.voicePress.promoteLongOnlyCandidateForTesting())

        let records = try harness.records()
        _ = try XCTUnwrap(records.firstIndex { $0["event"] as? String == "OPTION_GATE_BEGIN" })
        let opening = try XCTUnwrap(records.firstIndex { $0["event"] as? String == "VOICE_SESSION_OPENING" })
        let pressIndex = try XCTUnwrap(records.firstIndex { $0["event"] as? String == "VOICE_PRESS_ENTRY" })
        let press = records[pressIndex]

        XCTAssertEqual(press["source"] as? String, "hid_monitor")
        XCTAssertEqual(press["observer_uptime"] as? Double, 123.456)
        XCTAssertEqual(
            press["gesture_id"] as? String,
            records[opening]["gesture_id"] as? String
        )
        XCTAssertFalse(records.contains { $0["event"] as? String == "HOLD_CONFIRMED" })
    }

    func testReleaseEntryIsEnqueuedAfterKeyUpAndStopWithCapturedIdentityAndUptime() throws {
        let harness = makeHarness(uptimes: [10.25, 20.5])
        defer { harness.close() }
        var observedStates: [VoicePressCoordinator.State] = []
        harness.voicePress.onStateChanged = { observedStates.append($0) }

        harness.controller.beginVoicePress(
            targetApplicationBundleIdentifier: "org.example.RemoteOrbitTests",
            source: .voiceKeyFilterFallback
        )
        XCTAssertTrue(harness.voicePress.promoteLongOnlyCandidateForTesting())
        let pressRecords = try harness.records()
        let press = try XCTUnwrap(pressRecords.first { $0["event"] as? String == "VOICE_PRESS_ENTRY" })
        let gestureID = try XCTUnwrap(press["gesture_id"] as? String)

        var stopObservedDrainingState = false
        var stopObservedActiveRoute = false
        harness.controller.finishVoicePressRelease(source: .voiceKeyFilterFallback) {
            stopObservedDrainingState = observedStates.last == .draining
            stopObservedActiveRoute =
                harness.voicePress.diagnosticStateFields["remote_routed"] as? Bool == true
            harness.voicePress.setRemoteStreaming(false)
            harness.logger.log(category: "test", event: "TEST_VOICE_STOP_MARKER")
        }

        let records = try harness.records()
        let stop = try XCTUnwrap(records.firstIndex { $0["event"] as? String == "TEST_VOICE_STOP_MARKER" })
        let releaseIndex = try XCTUnwrap(records.firstIndex { $0["event"] as? String == "VOICE_RELEASE_ENTRY" })
        let release = records[releaseIndex]

        XCTAssertTrue(
            stopObservedDrainingState,
            "keyUp must enter draining before the stop callback"
        )
        XCTAssertTrue(
            stopObservedActiveRoute,
            "the remote route must remain active until the stop callback completes"
        )
        XCTAssertLessThan(stop, releaseIndex)
        XCTAssertEqual(release["source"] as? String, "voice_key_filter_fallback")
        XCTAssertEqual(release["gesture_id"] as? String, gestureID)
        XCTAssertEqual(release["observer_uptime"] as? Double, 20.5)
        XCTAssertNil(harness.voicePress.currentGestureIDForDiagnostics)
    }

    func testHIDAndFallbackSourcesRemainTaggedForPressAndRelease() throws {
        for source in [VoicePressInputSource.hidMonitor, .voiceKeyFilterFallback] {
            let harness = makeHarness(uptimes: [1, 2])
            defer { harness.close() }
            harness.controller.beginVoicePress(
                targetApplicationBundleIdentifier: "org.example.RemoteOrbitTests",
                source: source
            )
            XCTAssertTrue(harness.voicePress.promoteLongOnlyCandidateForTesting())
            harness.controller.finishVoicePressRelease(source: source, stopVoiceInput: {})

            let records = try harness.records()
            let press = try XCTUnwrap(records.first { $0["event"] as? String == "VOICE_PRESS_ENTRY" })
            let release = try XCTUnwrap(records.first { $0["event"] as? String == "VOICE_RELEASE_ENTRY" })
            XCTAssertEqual(press["source"] as? String, source.rawValue)
            XCTAssertEqual(release["source"] as? String, source.rawValue)
            XCTAssertEqual(release["gesture_id"] as? String, press["gesture_id"] as? String)
        }
    }

    private func makeHarness(uptimes: [TimeInterval]) -> Harness {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-boundary-order-\(UUID().uuidString).jsonl")
        let logger = VoiceDiagnosticLogger(fileURL: fileURL)
        logger.startRun()
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in }, diagnosticLogger: logger)
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger, diagnosticLogger: logger)
        let voicePress = VoicePressCoordinator(optionTrigger: trigger, diagnosticLogger: logger)
        var uptimeIndex = 0
        let controller = AppController(
            filter: filter,
            voicePress: voicePress,
            initiallyHIDConnected: true,
            isVoiceHIDMappingEnabled: { true },
            diagnosticLogger: logger,
            uptimeProvider: {
                defer { uptimeIndex += 1 }
                return uptimes[min(uptimeIndex, uptimes.count - 1)]
            }
        )
        voicePress.onHardwareOptionGateBegin = { [weak filter] gestureID in
            filter?.beginOptionDeferral(gestureID: gestureID)
        }
        return Harness(
            fileURL: fileURL,
            logger: logger,
            filter: filter,
            voicePress: voicePress,
            controller: controller
        )
    }

    private struct Harness {
        let fileURL: URL
        let logger: VoiceDiagnosticLogger
        let filter: VoiceKeyFilter
        let voicePress: VoicePressCoordinator
        let controller: AppController

        func records() throws -> [[String: Any]] {
            logger.flush()
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            return try contents.split(separator: "\n").map { line in
                let data = String(line).data(using: .utf8)!
                return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            }
        }

        func close() {
            voicePress.stop()
            filter.stop()
            logger.close()
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
