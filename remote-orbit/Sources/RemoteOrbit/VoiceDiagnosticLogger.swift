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
        guard let requested else { return .mismatch }
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

/// Appends one JSON object per line and synchronizes every write so voice-key
/// evidence survives an app crash or a normal/forced process termination.
final class VoiceDiagnosticLogger {
    static let currentLogURL = AppStorage.logsDirectory
        .appendingPathComponent("voice-diagnostic-current.jsonl")
    static let shared = VoiceDiagnosticLogger(fileURL: currentLogURL)

    private let fileURL: URL
    private let lock = NSLock()
    private let dateProvider: () -> Date
    private let uptimeProvider: () -> TimeInterval
    private let processIdentifierProvider: () -> Int32
    private let binaryPathProvider: () -> String
    private var fileHandle: FileHandle?
    private var isActive = false
    private let timestampFormatter: ISO8601DateFormatter

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
        }
    ) {
        self.fileURL = fileURL
        self.dateProvider = dateProvider
        self.uptimeProvider = uptimeProvider
        self.processIdentifierProvider = processIdentifierProvider
        self.binaryPathProvider = binaryPathProvider
        timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        timestampFormatter.timeZone = .current
    }

    func startRun(fields: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
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
            fileHandle?.closeFile()
            fileHandle = handle
            isActive = true

            var runFields = fields
            runFields["pid"] = Int(processIdentifierProvider())
            runFields["binary_path"] = binaryPathProvider()
            appendLocked(category: "app", event: "RUN_START", fields: runFields)
        } catch {
            fileHandle = nil
            isActive = false
        }
    }

    func log(
        category: String,
        event: String,
        gestureID: UUID? = nil,
        key: VoiceTriggerKey? = nil,
        fields: [String: Any] = [:]
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard isActive, fileHandle != nil else { return }

        var eventFields = fields
        if let gestureID {
            eventFields["gesture_id"] = gestureID.uuidString
        }
        if let key {
            eventFields.merge(Self.keyFields(for: key)) { _, new in new }
        }
        appendLocked(category: category, event: event, fields: eventFields)
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

    private func appendLocked(category: String, event: String, fields: [String: Any]) {
        guard let fileHandle else { return }
        var record: [String: Any] = [
            "ts": timestampFormatter.string(from: dateProvider()),
            "uptime": uptimeProvider(),
            "category": category,
            "event": event,
        ]
        for (key, value) in fields {
            guard !["ts", "uptime", "category", "event"].contains(key) else { continue }
            record[key] = value
        }
        do {
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            data.append(0x0A)
            try fileHandle.write(contentsOf: data)
            try fileHandle.synchronize()
        } catch {
            // Diagnostics are best-effort and must never alter input behavior.
        }
    }
}
