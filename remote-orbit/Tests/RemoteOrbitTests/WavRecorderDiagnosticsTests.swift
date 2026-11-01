import Foundation
import XCTest
@testable import RemoteOrbit

final class WavRecorderDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
    }

    override func tearDown() {
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        super.tearDown()
    }

    func testOptInRecorderEmitsLifecycleMetadataWithoutFilePathsOrAudioContent() throws {
        let directory = try makeTemporaryDirectory()
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
        let recorder = try WavRecorder(
            wavURL: directory.appendingPathComponent("capture.wav"),
            rawURL: directory.appendingPathComponent("capture.raw.bin"),
            basename: "capture",
            diagnosticAuthority: authority
        )

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
        XCTAssertFalse(events.contains { $0.category == "failure" })
    }

    func testRecordingWritesRawAndValidFinalizedPCMHeader() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let wavURL = directory.appendingPathComponent("capture.wav")
        let rawURL = directory.appendingPathComponent("capture.raw.bin")
        let recorder = try WavRecorder(
            wavURL: wavURL,
            rawURL: rawURL,
            basename: "capture"
        )
        let samples: [Int16] = [1, -1, 42, -300]
        let raw = Data([0x01, 0x02, 0x03, 0x04])

        recorder.appendSamples(samples)
        recorder.appendRawBytes(raw)
        recorder.close()

        let wav = try Data(contentsOf: wavURL)
        XCTAssertEqual(try Data(contentsOf: rawURL), raw)
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wav[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")

        let dataBytes = readUInt32LE(wav, offset: 40)
        XCTAssertEqual(dataBytes, UInt32(samples.count * 2))
        XCTAssertEqual(readUInt32LE(wav, offset: 4), UInt32(wav.count - 8))
        XCTAssertEqual(wav.count, 44 + samples.count * 2)
    }

    func testBackToBackSessionsUseIndependentFilesAndPreserveExistingCapture() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try WavRecorder.createNext(prefix: "remote-orbit", directory: directory)
        first.appendSamples([1, 2])
        first.appendRawBytes(Data([0x10]))
        first.close()
        let firstWav = try Data(contentsOf: URL(fileURLWithPath: first.wavPath))
        let firstRaw = try Data(contentsOf: URL(fileURLWithPath: first.rawPath))

        let second = try WavRecorder.createNext(prefix: "remote-orbit", directory: directory)
        second.appendSamples([3, 4])
        second.appendRawBytes(Data([0x20, 0x21]))
        second.close()

        XCTAssertNotEqual(first.wavPath, second.wavPath)
        XCTAssertNotEqual(first.rawPath, second.rawPath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: first.wavPath)), firstWav)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: first.rawPath)), firstRaw)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).count,
            4
        )
    }

    func testRecorderCreationFailureIsObservable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blockedDirectory = root.appendingPathComponent("not-a-directory")
        XCTAssertTrue(FileManager.default.createFile(atPath: blockedDirectory.path, contents: Data([1])))

        let authority = makeDiagnosticAuthority(in: root)
        let previousLogging = AppStorage.loggingEnabled
        defer { AppStorage.loggingEnabled = previousLogging }
        AppStorage.loggingEnabled = false
        DiagnosticsRuntimeGate.shared.configureForTesting(
            loggingEnabled: false,
            environmentOverrideEnabled: true
        )

        XCTAssertThrowsError(
            try WavRecorder.createNext(
                prefix: "remote-orbit",
                directory: blockedDirectory,
                diagnosticAuthority: authority
            )
        ) { error in
            guard case let WavRecorderError.directoryCreationFailed(path, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, blockedDirectory.path)
        }

        let events = try authority.query(DiagnosticQueryFilter(
            eventTypes: ["audio.capture.recording_create_failed"],
            limit: 10
        )).events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].payload["operation"], .string("directory_create"))
        XCTAssertEqual(events[0].payload["failure_category"], .string("directory"))
        XCTAssertEqual(events[0].payload["reason"], .string("directory_creation_failed"))
        XCTAssertFalse(String(describing: events[0].payload).contains(blockedDirectory.path))
        XCTAssertFalse(String(describing: events[0].payload).contains("dictated"))
        XCTAssertFalse(String(describing: events[0].payload).contains("audio"))
    }

    func testWriteAndCloseFailuresEmitStructuredEvidence() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let authority = makeDiagnosticAuthority(in: directory)
        let recorder = try WavRecorder(
            wavURL: directory.appendingPathComponent("capture.wav"),
            rawURL: directory.appendingPathComponent("capture.raw.bin"),
            basename: "capture",
            diagnosticAuthority: authority
        )
        defer { recorder.close() }

        recorder.emitWriteFailureForTesting()
        recorder.emitCloseFailureForTesting()

        let events = try authority.query(DiagnosticQueryFilter(
            subsystems: ["audio.capture"],
            limit: 10
        )).events
        XCTAssertEqual(events.map(\.eventType), [
            "audio.capture.recording_started",
            "audio.capture.recording_write_failed",
            "audio.capture.recording_close_failed",
        ])
        XCTAssertEqual(events[1].payload["failure_category"], .string("write"))
        XCTAssertEqual(events[2].payload["failure_category"], .string("close"))
        XCTAssertFalse(events.dropFirst().contains {
            String(describing: $0.payload).contains(directory.path)
        })
    }

    func testBridgeRecordingToggleCoversDisabledEnabledAndSecondSession() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let previous = AppStorage.recordingEnabled
        defer { AppStorage.recordingEnabled = previous }

        let bridge = BLEBridge()
        bridge.recordingDirectoryOverrideForTesting = directory
        bridge.setRecordingEnabled(false)
        bridge.beginAudioStartForTesting()
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        bridge.closeRecordingForTesting()

        bridge.setRecordingEnabled(true)
        bridge.beginAudioStartForTesting()
        bridge.appendRecordingDataForTesting(
            rawData: Data([0x01, 0x02]),
            samples: [1, -1, 2]
        )
        bridge.closeRecordingForTesting()
        let firstFiles = try recordingFiles(in: directory)
        XCTAssertEqual(firstFiles.wav.count, 1)
        XCTAssertEqual(firstFiles.raw.count, 1)

        bridge.beginAudioStartForTesting()
        bridge.appendRecordingDataForTesting(
            rawData: Data([0x03]),
            samples: [3, -3]
        )
        bridge.closeRecordingForTesting()
        let secondFiles = try recordingFiles(in: directory)
        XCTAssertEqual(secondFiles.wav.count, 2)
        XCTAssertEqual(secondFiles.raw.count, 2)

        bridge.setRecordingEnabled(false)
        bridge.beginAudioStartForTesting()
        XCTAssertEqual(try recordingFiles(in: directory).wav.count, 2)
        XCTAssertEqual(try recordingFiles(in: directory).raw.count, 2)

        bridge.stop()
    }

    func testDiagnosticsOffRecordingLifecycleWritesFilesButSuppressesMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let previousRecording = AppStorage.recordingEnabled
        let previousLogging = AppStorage.loggingEnabled
        defer {
            AppStorage.recordingEnabled = previousRecording
            AppStorage.loggingEnabled = previousLogging
        }

        AppStorage.loggingEnabled = false
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)

        let authority = try XCTUnwrap(
            DiagnosticAuthorityService.shared as? DiagnosticAuthorityService
        )
        let bridge = BLEBridge()
        bridge.recordingDirectoryOverrideForTesting = directory

        AppStorage.recordingEnabled = false
        bridge.beginAudioStartForTesting()
        bridge.closeRecordingForTesting()
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )

        let metricsBeforeRecording = authority.workMetricsForTesting
        AppStorage.recordingEnabled = true
        bridge.beginAudioStartForTesting()
        bridge.appendRecordingDataForTesting(
            rawData: Data([0x01, 0x02, 0x03]),
            samples: [1, -1, 42, -300]
        )
        bridge.closeRecordingForTesting()

        let files = try recordingFiles(in: directory)
        XCTAssertEqual(files.wav.count, 1)
        XCTAssertEqual(files.raw.count, 1)
        let wav = try Data(contentsOf: files.wav[0])
        XCTAssertEqual(try Data(contentsOf: files.raw[0]), Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wav[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(readUInt32LE(wav, offset: 40), UInt32(4 * 2))
        XCTAssertEqual(readUInt32LE(wav, offset: 4), UInt32(wav.count - 8))
        XCTAssertEqual(wav.count, 44 + 4 * 2)

        XCTAssertEqual(authority.workMetricsForTesting, metricsBeforeRecording)
        bridge.stop()
    }

    func testBridgeReportsRecorderCreationFailureInsteadOfSilentNil() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blockedDirectory = root.appendingPathComponent("not-a-directory")
        XCTAssertTrue(FileManager.default.createFile(atPath: blockedDirectory.path, contents: Data([1])))

        let previous = AppStorage.recordingEnabled
        defer { AppStorage.recordingEnabled = previous }

        let bridge = BLEBridge()
        bridge.recordingDirectoryOverrideForTesting = blockedDirectory
        bridge.setRecordingEnabled(true)
        bridge.beginAudioStartForTesting()

        XCTAssertNotNil(bridge.lastRecordingFailureForTesting)
        bridge.stop()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-wav-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeDiagnosticAuthority(in directory: URL) -> DiagnosticAuthorityService {
        DiagnosticAuthorityService(
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
    }

    private func recordingFiles(in directory: URL) throws -> (wav: [URL], raw: [URL]) {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return (
            wav: files.filter { $0.pathExtension == "wav" },
            raw: files.filter { $0.pathExtension == "bin" }
        )
    }

    private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
