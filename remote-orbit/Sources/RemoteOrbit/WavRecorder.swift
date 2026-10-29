// Tiny WAV file writer for diagnostic audio capture.
// Saves 16-bit mono PCM at 16 kHz under Application Support only when the
// user explicitly enables diagnostic recording in the menu.

import Foundation

enum WavRecorderError: Error, Equatable, LocalizedError {
    case directoryCreationFailed(path: String, reason: String)
    case fileCreationFailed(path: String)
    case fileOpenFailed(path: String, reason: String)
    case writeFailed(path: String, operation: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .directoryCreationFailed(path, reason):
            return "创建录音目录失败（\(path)）：\(reason)"
        case let .fileCreationFailed(path):
            return "创建录音文件失败（\(path)）"
        case let .fileOpenFailed(path, reason):
            return "打开录音文件失败（\(path)）：\(reason)"
        case let .writeFailed(path, operation, reason):
            return "\(operation) 写入失败（\(path)）：\(reason)"
        }
    }
}

final class WavRecorder {
    static func createNext(
        prefix: String,
        directory: URL = AppStorage.recordingsDirectory,
        diagnosticAuthority: any DiagnosticAuthority = DiagnosticAuthorityService.shared
    ) throws -> WavRecorder {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        // The UUID keeps back-to-back sessions independent even within one
        // millisecond. Existing captures are never removed or overwritten.
        let base = "\(prefix)-\(formatter.string(from: Date()))-\(UUID().uuidString)"
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            Self.emitStructuredFailure(
                authority: diagnosticAuthority,
                eventType: "audio.capture.recording_create_failed",
                operation: "directory_create",
                failureCategory: "directory",
                reason: "directory_creation_failed"
            )
            throw WavRecorderError.directoryCreationFailed(
                path: directory.path,
                reason: error.localizedDescription
            )
        }
        let wavURL = directory.appendingPathComponent("\(base).wav")
        let rawURL = directory.appendingPathComponent("\(base).raw.bin")
        return try WavRecorder(
            wavURL: wavURL,
            rawURL: rawURL,
            basename: base,
            diagnosticAuthority: diagnosticAuthority
        )
    }

    let basename: String
    private let wavURL: URL
    private let rawURL: URL
    private var wavHandle: FileHandle?
    private var rawHandle: FileHandle?
    private var totalFrames: UInt64 = 0
    private var rawByteCount: UInt64 = 0
    private var isClosed = false
    private let ioQueue: DispatchQueue
    private let diagnosticAuthority: any DiagnosticAuthority
    private let recordingID: String
    private let sampleRate: UInt32 = 16_000
    private let channels: UInt16 = 1
    private let bitsPerSample: UInt16 = 16

    init(
        wavURL: URL,
        rawURL: URL,
        basename: String,
        diagnosticAuthority: any DiagnosticAuthority = DiagnosticAuthorityService.shared
    ) throws {
        self.wavURL = wavURL
        self.rawURL = rawURL
        self.basename = basename
        self.diagnosticAuthority = diagnosticAuthority
        self.recordingID = UUID().uuidString
        self.ioQueue = DispatchQueue(
            label: "com.lost0rz.RemoteOrbit.wav.\(basename)",
            qos: .utility
        )
        self.wavHandle = nil
        self.rawHandle = nil

        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: wavURL.path, contents: nil) else {
            Self.emitStructuredFailure(
                authority: diagnosticAuthority,
                eventType: "audio.capture.recording_create_failed",
                operation: "wav_create",
                failureCategory: "file",
                reason: "file_creation_failed",
                correlationID: recordingID
            )
            throw WavRecorderError.fileCreationFailed(path: wavURL.path)
        }

        let wh: FileHandle
        do {
            wh = try FileHandle(forWritingTo: wavURL)
        } catch {
            try? fileManager.removeItem(at: wavURL)
            Self.emitStructuredFailure(
                authority: diagnosticAuthority,
                eventType: "audio.capture.recording_create_failed",
                operation: "wav_open",
                failureCategory: "file",
                reason: "file_open_failed",
                correlationID: recordingID
            )
            throw WavRecorderError.fileOpenFailed(
                path: wavURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            try wh.write(contentsOf: Self.makeHeader(
                sampleRate: sampleRate,
                channels: channels,
                bitsPerSample: bitsPerSample,
                dataBytes: 0
            ))
        } catch {
            try? wh.close()
            try? fileManager.removeItem(at: wavURL)
            Self.emitStructuredFailure(
                authority: diagnosticAuthority,
                eventType: "audio.capture.recording_create_failed",
                operation: "wav_header_write",
                failureCategory: "write",
                reason: "header_write_failed",
                correlationID: recordingID
            )
            throw WavRecorderError.writeFailed(
                path: wavURL.path,
                operation: "WAV header",
                reason: error.localizedDescription
            )
        }

        guard fileManager.createFile(atPath: rawURL.path, contents: nil) else {
            try? wh.close()
            try? fileManager.removeItem(at: wavURL)
            Self.emitStructuredFailure(
                authority: diagnosticAuthority,
                eventType: "audio.capture.recording_create_failed",
                operation: "raw_create",
                failureCategory: "file",
                reason: "file_creation_failed",
                correlationID: recordingID
            )
            throw WavRecorderError.fileCreationFailed(path: rawURL.path)
        }

        let rh: FileHandle
        do {
            rh = try FileHandle(forWritingTo: rawURL)
        } catch {
            try? wh.close()
            try? fileManager.removeItem(at: wavURL)
            try? fileManager.removeItem(at: rawURL)
            Self.emitStructuredFailure(
                authority: diagnosticAuthority,
                eventType: "audio.capture.recording_create_failed",
                operation: "raw_open",
                failureCategory: "file",
                reason: "file_open_failed",
                correlationID: recordingID
            )
            throw WavRecorderError.fileOpenFailed(
                path: rawURL.path,
                reason: error.localizedDescription
            )
        }

        self.wavHandle = wh
        self.rawHandle = rh
        print("[WAV] created wav=\(wavURL.path) raw=\(rawURL.path)")
        emitRecordingStarted()
    }

    func appendSamples(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        ioQueue.async { [weak self] in
            guard let self, !self.isClosed, let h = self.wavHandle else { return }
            var pcm = [UInt8](repeating: 0, count: samples.count * 2)
            for (i, s) in samples.enumerated() {
                let u = UInt16(bitPattern: Int16(s))
                pcm[i * 2] = UInt8(u & 0xFF)
                pcm[i * 2 + 1] = UInt8((u >> 8) & 0xFF)
            }
            do {
                try h.write(contentsOf: Data(pcm))
                self.totalFrames += UInt64(samples.count)
            } catch {
                self.reportFailure(
                    eventType: "audio.capture.recording_write_failed",
                    path: self.wavURL.path,
                    operation: "pcm_samples_write",
                    failureCategory: "write",
                    reason: "write_failed",
                    error: error
                )
            }
        }
    }

    func appendRawBytes(_ data: Data) {
        guard !data.isEmpty else { return }
        ioQueue.async { [weak self] in
            guard let self, !self.isClosed, let h = self.rawHandle else { return }
            do {
                try h.write(contentsOf: data)
                self.rawByteCount += UInt64(data.count)
            } catch {
                self.reportFailure(
                    eventType: "audio.capture.recording_write_failed",
                    path: self.rawURL.path,
                    operation: "raw_bytes_write",
                    failureCategory: "write",
                    reason: "write_failed",
                    error: error
                )
            }
        }
    }

    func close() {
        var closedFrameCount: UInt64?
        var closedRawByteCount: UInt64 = 0
        ioQueue.sync {
            guard !isClosed else { return }
            isClosed = true
            closedFrameCount = totalFrames
            closedRawByteCount = rawByteCount

            if let h = wavHandle {
                wavHandle = nil
                let dataBytes = UInt32(totalFrames)
                    * UInt32(channels)
                    * UInt32(bitsPerSample / 8)
                let header = Self.makeHeader(
                    sampleRate: sampleRate,
                    channels: channels,
                    bitsPerSample: bitsPerSample,
                    dataBytes: dataBytes
                )
                do {
                    try h.seek(toOffset: 0)
                    try h.write(contentsOf: header)
                    try h.close()
                } catch {
                    reportFailure(
                        eventType: "audio.capture.recording_close_failed",
                        path: wavURL.path,
                        operation: "wav_close",
                        failureCategory: "close",
                        reason: "header_rewrite_or_close_failed",
                        error: error
                    )
                }
            }
            if let h = rawHandle {
                rawHandle = nil
                do {
                    try h.close()
                } catch {
                    reportFailure(
                        eventType: "audio.capture.recording_close_failed",
                        path: rawURL.path,
                        operation: "raw_close",
                        failureCategory: "close",
                        reason: "raw_close_failed",
                        error: error
                    )
                }
            }
        }
        if let closedFrameCount {
            emitRecordingClosed(frameCount: closedFrameCount)
            let wavBytes = fileSize(at: wavURL)
            let rawBytes = fileSize(at: rawURL)
            let wavDataBytes = closedFrameCount
                * UInt64(channels)
                * UInt64(bitsPerSample / 8)
            print(
                "[WAV] closed wav=\(wavURL.path) raw=\(rawURL.path) "
                    + "samples=\(closedFrameCount) wav_data_bytes=\(wavDataBytes) "
                    + "wav_file_bytes=\(wavBytes) raw_written_bytes=\(closedRawByteCount) "
                    + "raw_file_bytes=\(rawBytes)"
            )
        }
    }

    /// Convenience: returns the generated WAV basename.
    var filename: String { "\(basename).wav" }

    var wavPath: String { wavURL.path }

    var rawPath: String { rawURL.path }

    var totalSamples: UInt64 {
        ioQueue.sync { totalFrames }
    }

    var recordedSampleRate: UInt32 { sampleRate }

    // These seams exercise the same structured failure path used by the I/O
    // catches without making the normal recorder lifecycle artificial.
    func emitWriteFailureForTesting() {
        ioQueue.sync {
            reportFailure(
                eventType: "audio.capture.recording_write_failed",
                path: wavURL.path,
                operation: "test_write",
                failureCategory: "write",
                reason: "test_failure",
                error: nil
            )
        }
    }

    func emitCloseFailureForTesting() {
        ioQueue.sync {
            reportFailure(
                eventType: "audio.capture.recording_close_failed",
                path: wavURL.path,
                operation: "test_close",
                failureCategory: "close",
                reason: "test_failure",
                error: nil
            )
        }
    }

    private func reportFailure(
        eventType: String,
        path: String,
        operation: String,
        failureCategory: String,
        reason: String,
        error: Error?
    ) {
        Self.emitStructuredFailure(
            authority: diagnosticAuthority,
            eventType: eventType,
            operation: operation,
            failureCategory: failureCategory,
            reason: reason,
            correlationID: recordingID
        )
        print(
            "[WAV] failure operation=\(operation) path=\(path) "
                + "error=\(error?.localizedDescription ?? reason)"
        )
    }

    private static func emitStructuredFailure(
        authority: any DiagnosticAuthority,
        eventType: String,
        operation: String,
        failureCategory: String,
        reason: String,
        correlationID: String? = nil
    ) {
        guard let event = try? DiagnosticEventInput(
            eventType: eventType,
            subsystem: "audio.capture",
            category: "failure",
            severity: .error,
            sourceComponent: "wav_recorder",
            correlationID: correlationID,
            payload: [
                "operation": .string(operation),
                "failure_category": .string(failureCategory),
                "reason": .string(reason),
            ]
        ) else { return }
        authority.emit(event)
    }

    private func fileSize(at url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func emitRecordingStarted() {
        guard let event = try? DiagnosticEventInput(
            eventType: "audio.capture.recording_started",
            subsystem: "audio.capture",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "wav_recorder",
            correlationID: recordingID,
            payload: [
                "sample_rate": .unsignedInteger(UInt64(sampleRate)),
                "channels": .unsignedInteger(UInt64(channels)),
                "bits_per_sample": .unsignedInteger(UInt64(bitsPerSample)),
            ]
        ) else { return }
        diagnosticAuthority.emit(event)
    }

    private func emitRecordingClosed(frameCount: UInt64) {
        guard let event = try? DiagnosticEventInput(
            eventType: "audio.capture.recording_closed",
            subsystem: "audio.capture",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "wav_recorder",
            correlationID: recordingID,
            payload: [
                "sample_count": .unsignedInteger(frameCount),
                "recorded_duration_ms": .double(
                    Double(frameCount) / Double(sampleRate) * 1_000
                ),
            ]
        ) else { return }
        diagnosticAuthority.emit(event)
    }

    private static func makeHeader(
        sampleRate: UInt32,
        channels: UInt16,
        bitsPerSample: UInt16,
        dataBytes: UInt32
    ) -> Data {
        let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let chunkSize: UInt32 = 36 + dataBytes
        var d = Data()
        d.append(Data("RIFF".utf8))
        d.append(Self.u32(chunkSize))
        d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8))
        d.append(Self.u32(16))
        d.append(Self.u16(1))
        d.append(Self.u16(channels))
        d.append(Self.u32(sampleRate))
        d.append(Self.u32(byteRate))
        d.append(Self.u16(blockAlign))
        d.append(Self.u16(bitsPerSample))
        d.append(Data("data".utf8))
        d.append(Self.u32(dataBytes))
        return d
    }

    private static func u32(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 4)
    }

    private static func u16(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 2)
    }
}
