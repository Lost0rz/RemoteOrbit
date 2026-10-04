import Foundation

final class JSONLinesDiagnosticJournal: DiagnosticJournal, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private var cachedEvents: [DiagnosticEvent]?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        try? fileHandle?.close()
    }

    func append(_ event: DiagnosticEvent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(event)
        data.append(0x0A)

        lock.lock()
        defer { lock.unlock() }
        do {
            try openForAppendIfNeeded()
            guard let fileHandle else { throw DiagnosticQueryError.storageUnavailable }
            try fileHandle.write(contentsOf: data)
            cachedEvents?.append(event)
        } catch {
            throw DiagnosticQueryError.storageUnavailable
        }
    }

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        lock.lock()
        defer { lock.unlock() }

        let events = try readEventsIfNeeded()
        let cursorIndex: Int
        if let cursor = filter.cursor {
            guard let cursorID = UUID(uuidString: cursor),
                  let index = events.firstIndex(where: { $0.eventID == cursorID }) else {
                throw DiagnosticQueryError.invalidCursor
            }
            cursorIndex = index + 1
        } else {
            cursorIndex = 0
        }

        let matches = events.dropFirst(cursorIndex).filter(filter.matches)
        let pageEvents = Array(matches.prefix(filter.limit))
        let nextCursor = matches.count > filter.limit
            ? pageEvents.last?.eventID.uuidString
            : nil

        return DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: pageEvents,
            nextCursor: nextCursor
        )
    }

    private func openForAppendIfNeeded() throws {
        guard fileHandle == nil else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                    throw DiagnosticQueryError.storageUnavailable
                }
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            fileHandle = handle
        } catch {
            throw DiagnosticQueryError.storageUnavailable
        }
    }

    private func readEventsIfNeeded() throws -> [DiagnosticEvent] {
        if let cachedEvents {
            return cachedEvents
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cachedEvents = []
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw DiagnosticQueryError.storageUnavailable
        }

        guard !data.isEmpty else {
            cachedEvents = []
            return []
        }

        let decoder = JSONDecoder()
        let lines = data.split(omittingEmptySubsequences: false, whereSeparator: { $0 == 0x0A })
        let recordCount = lines.count - (data.last == 0x0A ? 1 : 0)
        var events: [DiagnosticEvent] = []
        events.reserveCapacity(recordCount)
        for index in 0..<recordCount {
            let line = lines[index]
            guard !line.isEmpty else {
                throw DiagnosticQueryError.corruptJournal(index + 1)
            }
            do {
                events.append(try decoder.decode(DiagnosticEvent.self, from: Data(line)))
            } catch DiagnosticSchemaError.unsupportedVersion(let version) {
                throw DiagnosticQueryError.unsupportedSchemaVersion(version)
            } catch {
                throw DiagnosticQueryError.corruptJournal(index + 1)
            }
        }
        cachedEvents = events
        return events
    }
}
