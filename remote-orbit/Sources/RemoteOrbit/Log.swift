import Foundation

/// Serialized, uncached-size rolling text logger used by `Log`.
/// Uses `FileManager.attributesOfItem` + an in-memory byte counter on its serial
/// writer queue so `NSURL` resourceValue caching never prevents 5 MB rotation.
final class RollingTextLogWriter: @unchecked Sendable {
    let fileURL: URL
    let rotatedFileURL: URL
    let maximumBytes: UInt64

    private let writerQueue: DispatchQueue
    private var handle: FileHandle?
    private var currentBytes: UInt64 = 0

    init(
        fileURL: URL,
        maximumBytes: UInt64 = 5 * 1_024 * 1_024,
        queueLabel: String = "com.lost0rz.RemoteOrbit.log-writer"
    ) {
        self.fileURL = fileURL
        self.rotatedFileURL = fileURL.appendingPathExtension("1")
        self.maximumBytes = max(1, maximumBytes)
        self.writerQueue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    func setEnabled(_ enabled: Bool) {
        writerQueue.async { [weak self] in
            guard let self else { return }
            if enabled {
                self.openHandleIfNeededLocked()
            } else {
                self.closeHandleLocked()
            }
        }
    }

    func write(_ message: String) {
        let timestamp = Date()
        writerQueue.async { [weak self] in
            guard let self else { return }
            let lineData = Data("[\(timestamp)] \(message)\n".utf8)
            self.openHandleIfNeededLocked()
            self.rotateIfNeededLocked(incomingBytes: UInt64(lineData.count))
            guard let handle = self.handle else { return }
            do {
                try handle.write(contentsOf: lineData)
                self.currentBytes &+= UInt64(lineData.count)
            } catch {
                // Best-effort text logging must never abort runtime behavior.
            }
        }
    }

    func flush() {
        writerQueue.sync {
            try? handle?.synchronize()
        }
    }

    func clear(reopenIfEnabled: @escaping () -> Bool) {
        writerQueue.sync {
            closeHandleLocked()
            let fm = FileManager.default
            try? fm.removeItem(at: fileURL)
            try? fm.removeItem(at: rotatedFileURL)
            currentBytes = 0
            if reopenIfEnabled() {
                openHandleIfNeededLocked()
            }
        }
    }

    var byteSize: UInt64 {
        writerQueue.sync {
            Self.uncachedFileSize(at: fileURL) &+ Self.uncachedFileSize(at: rotatedFileURL)
        }
    }

    private func openHandleIfNeededLocked() {
        if handle != nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                closeHandleLocked()
                currentBytes = 0
            } else {
                return
            }
        }

        let fm = FileManager.default
        try? fm.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        if let end = try? handle?.seekToEnd() {
            currentBytes = end
        } else {
            currentBytes = Self.uncachedFileSize(at: fileURL)
        }
    }

    private func rotateIfNeededLocked(incomingBytes: UInt64) {
        guard currentBytes > 0, currentBytes &+ incomingBytes > maximumBytes else {
            return
        }
        closeHandleLocked()
        let fm = FileManager.default
        try? fm.removeItem(at: rotatedFileURL)
        if fm.fileExists(atPath: fileURL.path) {
            do {
                try fm.moveItem(at: fileURL, to: rotatedFileURL)
            } catch {
                try? Data().write(to: fileURL)
            }
        }
        currentBytes = 0
        openHandleIfNeededLocked()
    }

    private func closeHandleLocked() {
        try? handle?.close()
        handle = nil
    }

    private static func uncachedFileSize(at url: URL) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attributes[.size] as? NSNumber else {
            return 0
        }
        return number.uint64Value
    }
}

enum Log {
    static let writer = RollingTextLogWriter(fileURL: AppStorage.logFile)

    static var isEnabled: Bool { AppStorage.loggingEnabled }

    static func setEnabled(_ enabled: Bool) {
        AppStorage.loggingEnabled = enabled
        writer.setEnabled(enabled)
    }

    static func write(_ message: String) {
        guard AppStorage.loggingEnabled else { return }
        writer.write(message)
    }

    static func flush() {
        writer.flush()
    }

    static func clear() {
        writer.clear { AppStorage.loggingEnabled }
    }

    static var byteSize: UInt64 {
        writer.byteSize
    }
}

func print(_ message: String) {
    Log.write(message)
}
