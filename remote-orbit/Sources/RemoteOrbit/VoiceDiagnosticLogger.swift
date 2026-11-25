import Darwin
import Foundation

enum VoiceDiagnosticHIDVerification: String, Equatable {
    case match = "MATCH"
    case mismatch = "MISMATCH"
    case empty = "EMPTY"
    case unparseable = "UNPARSEABLE"
}

struct VoiceDiagnosticHIDMappingEntry: Equatable {
    let source: UInt64
    let destination: UInt64
}

enum VoiceDiagnosticHIDMappingParser {
    static let voiceSource: UInt64 = 0x70000003E
    static let noOpDestination: UInt64 = 0x0

    static func verify(
        stdout: String,
        stderr: String,
        exitStatus: Int32,
        requested: VoiceTriggerKey?
    ) -> VoiceDiagnosticHIDVerification {
        let output = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard exitStatus == 0 else { return .unparseable }
        guard !output.isEmpty else { return .empty }
        guard let mappings = parse(output: output) else {
            return .unparseable
        }
        guard let mapping = mappings.first(where: { $0.source == voiceSource }) else {
            return requested == nil ? .match : .mismatch
        }
        guard let requested else {
            return mapping.destination == noOpDestination ? .match : .mismatch
        }
        return mapping.destination == requested.hidutilDestination ? .match : .mismatch
    }

    static func observedVoiceDestination(in output: String) -> UInt64? {
        parse(output: output)?.first(where: { $0.source == voiceSource })?.destination
    }

    static func parse(output: String) -> [VoiceDiagnosticHIDMappingEntry]? {
        if let data = output.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let root = object as? [String: Any],
           let rawMappings = root["UserKeyMapping"] as? [[String: Any]] {
            let mappings = rawMappings.compactMap(mapping(from:))
            return mappings.count == rawMappings.count ? mappings : nil
        }

        guard output.range(of: "UserKeyMapping", options: .caseInsensitive) != nil else {
            return nil
        }

        let blocks = captureGroups(
            in: output,
            pattern: #"\{([^{}]*)\}"#
        )
        if blocks.isEmpty {
            let lowercased = output.lowercased()
            if lowercased.contains("userkeymapping")
                && (output.contains("()") || output.contains("[]")) {
                return []
            }
            return nil
        }

        let mappings: [VoiceDiagnosticHIDMappingEntry] = blocks.compactMap { block in
            guard let source = numericValue(
                in: block,
                for: "HIDKeyboardModifierMappingSrc"
            ), let destination = numericValue(
                in: block,
                for: "HIDKeyboardModifierMappingDst"
            ) else {
                return nil
            }
            return VoiceDiagnosticHIDMappingEntry(
                source: source,
                destination: destination
            )
        }
        return mappings.count == blocks.count ? mappings : nil
    }

    private static func mapping(from dictionary: [String: Any]) -> VoiceDiagnosticHIDMappingEntry? {
        guard let source = number(dictionary["HIDKeyboardModifierMappingSrc"]),
              let destination = number(dictionary["HIDKeyboardModifierMappingDst"]) else {
            return nil
        }
        return VoiceDiagnosticHIDMappingEntry(source: source, destination: destination)
    }

    private static func number(_ value: Any?) -> UInt64? {
        if let value = value as? NSNumber {
            return value.uint64Value
        }
        if let value = value as? String {
            return parseNumber(value)
        }
        return nil
    }

    private static func numericValue(in block: String, for key: String) -> UInt64? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "\\\"?\(escapedKey)\\\"?\\s*[:=]\\s*\\\"?(0[xX][0-9a-fA-F]+|[0-9]+)"
        return captureGroups(in: block, pattern: pattern)
            .first
            .flatMap(parseNumber)
    }

    private static func parseNumber(_ value: String) -> UInt64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt64(trimmed.dropFirst(2), radix: 16)
        }
        return UInt64(trimmed, radix: 10)
    }

    private static func captureGroups(in value: String, pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[range])
        }
    }
}

/// Appends one JSON object per line. Calls to `log` only enqueue immutable event
/// inputs; the serial writer queue owns formatting, serialization, and disk I/O.
final class VoiceDiagnosticLogger {
    static let currentLogURL = AppStorage.logsDirectory
        .appendingPathComponent("voice-diagnostic-current.jsonl")
    static let shared = VoiceDiagnosticLogger(fileURL: currentLogURL)

    private let fileURL: URL
    private let writerQueue = DispatchQueue(
        label: "com.remoteorbit.voice-diagnostic-writer",
        qos: .utility
    )
    private let dateProvider: () -> Date
    private let uptimeProvider: () -> TimeInterval
    private let processIdentifierProvider: () -> Int32
    private let binaryPathProvider: () -> String
    private let beforeQueuedEventWriteForTesting: (() -> Void)?
    private static let maxInFlightRecords: Int32 = 2_048

    private var fileHandle: FileHandle?
    private var isActive = false
    private var timestampFormatter: ISO8601DateFormatter?
    private var sequenceNumber: UInt64 = 0
    private var queuedRecordCount = 0
    private var inFlightRecordCount: Int32 = 0
    private var pendingUnsynchronizedWrites = false
    private var coalescedSyncWorkItem: DispatchWorkItem?
    private var jsonSerializationCount = 0
    private var writeCount = 0
    private var synchronizeCount = 0

    init(
        fileURL: URL,
        dateProvider: @escaping () -> Date = { Date() },
        uptimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        processIdentifierProvider: @escaping () -> Int32 = {
            ProcessInfo.processInfo.processIdentifier
        },
        binaryPathProvider: @escaping () -> String = {
            CommandLine.arguments.first ?? "unknown"
        },
        beforeQueuedEventWriteForTesting: (() -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.dateProvider = dateProvider
        self.uptimeProvider = uptimeProvider
        self.processIdentifierProvider = processIdentifierProvider
        self.binaryPathProvider = binaryPathProvider
        self.beforeQueuedEventWriteForTesting = beforeQueuedEventWriteForTesting
        DiagnosticsRuntimeGate.shared.observe { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.startRun()
            } else {
                self.close()
            }
        }
    }

    func startRun(fields: [String: Any] = [:]) {
        guard DiagnosticsRuntimeGate.shared.isEnabled else { return }
        let timestamp = dateProvider()
        let uptime = uptimeProvider()
        var runFields = fields
        runFields["pid"] = Int(processIdentifierProvider())
        runFields["binary_path"] = binaryPathProvider()

        writerQueue.sync {
            coalescedSyncWorkItem?.cancel()
            coalescedSyncWorkItem = nil
            pendingUnsynchronizedWrites = false
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.truncate(atOffset: 0)
                try handle.seekToEnd()
                try fileHandle?.close()
                fileHandle = handle
                isActive = true
                sequenceNumber = 0
                queuedRecordCount = 0
                append(category: "app", event: "RUN_START", fields: runFields,
                       timestamp: timestamp, uptime: uptime)
            } catch {
                try? fileHandle?.close()
                fileHandle = nil
                isActive = false
            }
        }
    }

    func log(
        category: String,
        event: String,
        gestureID: UUID? = nil,
        key: VoiceTriggerKey? = nil,
        fields: [String: Any] = [:]
    ) {
        guard DiagnosticsRuntimeGate.shared.isEnabled else { return }
        let inFlight = OSAtomicIncrement32Barrier(&inFlightRecordCount)
        guard inFlight <= Self.maxInFlightRecords else {
            _ = OSAtomicDecrement32Barrier(&inFlightRecordCount)
            return
        }
        // Capture event occurrence time before queue delay, but leave all
        // formatting, serialization, and file operations to the writer queue.
        let timestamp = dateProvider()
        let uptime = uptimeProvider()
        let capturedFields = fields

        writerQueue.async { [weak self] in
            guard let self else { return }
            defer { _ = OSAtomicDecrement32Barrier(&self.inFlightRecordCount) }
            self.queuedRecordCount += 1
            self.beforeQueuedEventWriteForTesting?()
            guard self.isActive, self.fileHandle != nil else { return }
            var eventFields = capturedFields
            if let gestureID {
                eventFields["gesture_id"] = gestureID.uuidString
            }
            if let key {
                eventFields.merge(Self.keyFields(for: key)) { _, new in new }
            }
            self.append(
                category: category,
                event: event,
                fields: eventFields,
                timestamp: timestamp,
                uptime: uptime
            )
        }
    }

    /// Waits for previously enqueued records and makes them durable.
    func flush() {
        guard DiagnosticsRuntimeGate.shared.isEnabled else { return }
        writerQueue.sync {
            coalescedSyncWorkItem?.cancel()
            coalescedSyncWorkItem = nil
            pendingUnsynchronizedWrites = false
            if fileHandle != nil {
                synchronizeCount += 1
            }
            try? fileHandle?.synchronize()
        }
    }

    var isActiveForTesting: Bool {
        writerQueue.sync { isActive && fileHandle != nil }
    }

    var workMetricsForTesting: (
        queuedRecordCount: Int,
        jsonSerializationCount: Int,
        writeCount: Int,
        synchronizeCount: Int
    ) {
        writerQueue.sync {
            (
                queuedRecordCount,
                jsonSerializationCount,
                writeCount,
                synchronizeCount
            )
        }
    }

    /// Waits for queued records, makes them durable, and closes the log file.
    func close() {
        writerQueue.sync {
            coalescedSyncWorkItem?.cancel()
            coalescedSyncWorkItem = nil
            if pendingUnsynchronizedWrites, fileHandle != nil {
                synchronizeCount += 1
            }
            try? fileHandle?.synchronize()
            pendingUnsynchronizedWrites = false
            try? fileHandle?.close()
            fileHandle = nil
            isActive = false
            queuedRecordCount = 0
        }
    }

    static func keyFields(for key: VoiceTriggerKey, prefix: String? = nil) -> [String: Any] {
        let base = prefix.map { "\($0)_" } ?? ""
        return [
            "\(base)key": key.rawValue,
            "\(base)key_display_name": key.diagnosticDisplayName,
            "\(base)cg_key_code": Int(key.cgKeyCode),
            "\(base)hid_destination": String(
                format: "0x%llX",
                key.hidutilDestination
            ),
        ]
    }

    private func append(
        category: String,
        event: String,
        fields: [String: Any],
        timestamp: Date,
        uptime: TimeInterval
    ) {
        guard let fileHandle else { return }
        sequenceNumber += 1
        var record: [String: Any] = [
            "seq": sequenceNumber,
            "ts": formatter().string(from: timestamp),
            "uptime": uptime,
            "category": category,
            "event": event,
        ]
        for (key, value) in fields {
            guard !["ts", "uptime", "category", "event"].contains(key) else { continue }
            record[key] = value
        }
        do {
            jsonSerializationCount += 1
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            data.append(0x0A)
            try fileHandle.write(contentsOf: data)
            writeCount += 1
            if event == "RUN_START" {
                coalescedSyncWorkItem?.cancel()
                coalescedSyncWorkItem = nil
                synchronizeCount += 1
                try fileHandle.synchronize()
                pendingUnsynchronizedWrites = false
            } else {
                pendingUnsynchronizedWrites = true
                if coalescedSyncWorkItem == nil {
                    let work = DispatchWorkItem { [weak self] in
                        self?.synchronizeIfPendingOnQueue()
                    }
                    coalescedSyncWorkItem = work
                    writerQueue.asyncAfter(deadline: .now() + 0.15, execute: work)
                }
            }
        } catch {
            // Diagnostics are best-effort and must never alter input behavior.
        }
    }

    private func synchronizeIfPendingOnQueue() {
        coalescedSyncWorkItem = nil
        guard pendingUnsynchronizedWrites, let fileHandle else {
            pendingUnsynchronizedWrites = false
            return
        }
        synchronizeCount += 1
        try? fileHandle.synchronize()
        pendingUnsynchronizedWrites = false
    }

    private func formatter() -> ISO8601DateFormatter {
        if let timestampFormatter {
            return timestampFormatter
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        timestampFormatter = formatter
        return formatter
    }
}
