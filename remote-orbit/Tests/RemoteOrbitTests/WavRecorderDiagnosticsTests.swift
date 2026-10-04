import Foundation
import XCTest
@testable import RemoteOrbit

final class WavRecorderDiagnosticsTests: XCTestCase {
    func testOptInRecorderEmitsLifecycleMetadataWithoutFilePathsOrAudioContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-wav-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let authority = DiagnosticAuthorityService(
            journal: JSONLinesDiagnosticJournal(
                fileURL: directory.appendingPathComponent("diagnostics.jsonl")
            ),
            runtimeContext: DiagnosticRuntimeContext(
                processInstanceID: UUID(),
                processID: 123,
                binaryPath: "/tmp/RemoteOrbit-test",
                appVersion: "test",
                buildVersion: "test",
                sourceRevision: nil
            ),
            clock: SystemDiagnosticClock()
        )
        let recorder = try XCTUnwrap(WavRecorder(
            wavURL: directory.appendingPathComponent("capture.wav"),
            rawURL: directory.appendingPathComponent("capture.raw.bin"),
            basename: "capture",
            diagnosticAuthority: authority
        ))

        recorder.appendSamples([1, -1, 42])
        recorder.appendRawBytes(Data([0x01, 0x02, 0x03]))
        recorder.close()

        let events = try authority.query(DiagnosticQueryFilter(
            subsystems: ["audio.capture"],
            limit: 10
        )).events
        XCTAssertEqual(events.map(\.eventType), [
            "audio.capture.recording_started",
            "audio.capture.recording_closed",
        ])
        XCTAssertEqual(events[0].correlationID, events[1].correlationID)
        XCTAssertEqual(events[0].payload["sample_rate"], .integer(16_000))
        XCTAssertEqual(events[1].payload["sample_count"], .integer(3))
        XCTAssertNil(events[0].payload["path"])
        XCTAssertNil(events[0].payload["filename"])
        XCTAssertNil(events[1].payload["audio"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("capture.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("capture.raw.bin").path))
    }
}
