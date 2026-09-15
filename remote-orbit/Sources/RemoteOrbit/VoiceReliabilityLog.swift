import Foundation

/// Always-on, metadata-only sink for diagnosing rare voice failures.
///
/// `write` only builds a small line and enqueues it. Rotation and all file
/// operations happen on the dedicated serial writer queue so BLE, HID, audio,
/// and CGEvent callbacks never wait for disk I/O.
final class VoiceReliabilityLog {
    typealias Writer = (_ file: URL, _ data: Data) throws -> Void

    static let shared = VoiceReliabilityLog(directory: AppStorage.logsDirectory)

    private let directory: URL
    private let maximumBytes: UInt64
    private let writer: Writer
    private let queue: DispatchQueue
    private let failureLock = NSLock()
    private var failures = 0

    init(
        directory: URL,
        maximumBytes: UInt64 = 2 * 1_024 * 1_024,
        writer: @escaping Writer = VoiceReliabilityLog.appendData
    ) {
        self.directory = directory
        self.maximumBytes = max(1, maximumBytes)
        self.writer = writer
        self.queue = DispatchQueue(
            label: "com.lost0rz.RemoteOrbit.voice-reliability-log",
            qos: .utility
        )
    }

    static func write(_ message: String) {
        shared.write(message)
    }

    func write(_ message: String) {
        let line = Data((message + "\n").utf8)
        queue.async { [weak self] in
            self?.writeOnQueue(line)
        }
    }

    static func clear() {
        shared.clear()
    }

    func clear() {
        queue.sync {
            for url in Self.logURLs(in: directory) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Test-only synchronization seam. Production callers must never wait on
    /// this queue from a timing-critical voice callback.
    func flushForTesting() {
        queue.sync {}
    }

    var failureCount: Int {
        failureLock.lock()
        defer { failureLock.unlock() }
        return failures
    }

    static var byteSize: UInt64 {
        AppStorage.byteSize(of: AppStorage.logsDirectory)
    }

    private var currentURL: URL {
        directory.appendingPathComponent("VoiceReliability.log")
    }

    private func writeOnQueue(_ data: Data) {
        do {
            AppStorage.ensureDirectory(directory)
            if fileSize(currentURL) + UInt64(data.count) > maximumBytes {
                try rotateOnQueue()
            }
            try writer(currentURL, data)
        } catch {
            failureLock.lock()
            failures += 1
            failureLock.unlock()
        }
    }

    private func rotateOnQueue() throws {
        let fm = FileManager.default
        let first = directory.appendingPathComponent("VoiceReliability.log.1")
        let second = directory.appendingPathComponent("VoiceReliability.log.2")

        if fm.fileExists(atPath: second.path) {
            try fm.removeItem(at: second)
        }
        if fm.fileExists(atPath: first.path) {
            try fm.moveItem(at: first, to: second)
        }
        if fm.fileExists(atPath: currentURL.path) {
            try fm.moveItem(at: currentURL, to: first)
        }
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values?.fileSize ?? 0)
    }

    private static func appendData(_ file: URL, _ data: Data) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) {
            guard fm.createFile(atPath: file.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private static func logURLs(in directory: URL) -> [URL] {
        [
            directory.appendingPathComponent("VoiceReliability.log"),
            directory.appendingPathComponent("VoiceReliability.log.1"),
            directory.appendingPathComponent("VoiceReliability.log.2"),
        ]
    }
}
