import Foundation

final class JSONLinesDiagnosticJournal: DiagnosticJournal, @unchecked Sendable {
    struct RetentionPolicy: Equatable, Sendable {
        let maxSegmentBytes: UInt64
        let maxSegmentCount: Int

        static let `default` = RetentionPolicy(
            maxSegmentBytes: 2 * 1024 * 1024,
            maxSegmentCount: 5
        )

        init(maxSegmentBytes: UInt64, maxSegmentCount: Int) {
            precondition(maxSegmentBytes > 0)
            precondition(maxSegmentCount > 0)
            self.maxSegmentBytes = maxSegmentBytes
            self.maxSegmentCount = maxSegmentCount
        }
    }

    private let fileURL: URL
    private let retentionPolicy: RetentionPolicy
    private let encoder: JSONEncoder
    private let lock = NSLock()
    private let syncQueue = DispatchQueue(
        label: "com.remoteorbit.diagnostic-journal-sync",
        qos: .utility
    )
    private var fileHandle: FileHandle?
    private var currentFileBytes: UInt64 = 0
    private var pendingUnsynchronizedWrites = false
    private var coalescedSyncWorkItem: DispatchWorkItem?

    init(
        fileURL: URL,
        retentionPolicy: RetentionPolicy = .default
    ) {
        self.fileURL = fileURL
        self.retentionPolicy = retentionPolicy
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    deinit {
        coalescedSyncWorkItem?.cancel()
        coalescedSyncWorkItem = nil
        if pendingUnsynchronizedWrites {
            try? fileHandle?.synchronize()
            pendingUnsynchronizedWrites = false
        }
        try? fileHandle?.close()
    }

    func append(_ event: DiagnosticEvent) throws {
        var data = try encoder.encode(event)
        data.append(0x0A)

        lock.lock()
        defer { lock.unlock() }
        do {
            if fileHandle != nil, !FileManager.default.fileExists(atPath: fileURL.path) {
                coalescedSyncWorkItem?.cancel()
                coalescedSyncWorkItem = nil
                pendingUnsynchronizedWrites = false
                try? fileHandle?.close()
                fileHandle = nil
                currentFileBytes = 0
            }
            try openForAppendIfNeeded()
            try rotateIfNeeded(incomingBytes: UInt64(data.count))
            guard let fileHandle else { throw DiagnosticQueryError.storageUnavailable }
            try fileHandle.write(contentsOf: data)
            currentFileBytes &+= UInt64(data.count)
            pendingUnsynchronizedWrites = true
            if event.severity == .error || event.severity == .critical {
                coalescedSyncWorkItem?.cancel()
                coalescedSyncWorkItem = nil
                try fileHandle.synchronize()
                pendingUnsynchronizedWrites = false
            } else if coalescedSyncWorkItem == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.flushPendingSynchronize()
                }
                coalescedSyncWorkItem = work
                syncQueue.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
        } catch let error as DiagnosticQueryError {
            throw error
        } catch {
            throw DiagnosticQueryError.storageUnavailable
        }
    }

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        lock.lock()
        defer { lock.unlock() }
        flushPendingSynchronizeLocked()

        let cursorID = filter.cursor.flatMap(UUID.init(uuidString:))
        var cursorFound = cursorID == nil
        var started = cursorID == nil
        var pageEvents: [DiagnosticEvent] = []
        var hasMore = false

        for segmentURL in segmentURLs() {
            try repairTrailingRecordIfNeeded(at: segmentURL)
            for event in try readEvents(from: segmentURL) {
                if !started {
                    if event.eventID == cursorID {
                        cursorFound = true
                        started = true
                    }
                    continue
                }

                guard filter.matches(event) else { continue }
                if pageEvents.count < filter.limit {
                    pageEvents.append(event)
                } else {
                    hasMore = true
                    break
                }
            }
            if hasMore { break }
        }

        guard cursorFound else { throw DiagnosticQueryError.invalidCursor }
        return DiagnosticQueryPage(
            schemaVersion: DiagnosticEvent.currentSchemaVersion,
            events: pageEvents,
            nextCursor: hasMore ? pageEvents.last?.eventID.uuidString : nil
        )
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        flushPendingSynchronizeLocked()
        try? fileHandle?.close()
        fileHandle = nil
        currentFileBytes = 0

        let fileManager = FileManager.default
        if retentionPolicy.maxSegmentCount > 1 {
            for index in 1..<retentionPolicy.maxSegmentCount {
                try? fileManager.removeItem(at: segmentURL(index: index))
            }
        }
        try? fileManager.removeItem(at: fileURL)
    }

    func segmentURLs() -> [URL] {
        let fileManager = FileManager.default
        var urls: [URL] = []
        if retentionPolicy.maxSegmentCount > 1 {
            for index in stride(from: retentionPolicy.maxSegmentCount - 1, through: 1, by: -1) {
                let url = segmentURL(index: index)
                if fileManager.fileExists(atPath: url.path) {
                    urls.append(url)
                }
            }
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            urls.append(fileURL)
        }
        return urls
    }

    private func openForAppendIfNeeded() throws {
        guard fileHandle == nil else { return }
        try repairTrailingRecordIfNeeded(at: fileURL)
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
            currentFileBytes = try handle.seekToEnd()
            fileHandle = handle
        } catch {
            throw DiagnosticQueryError.storageUnavailable
        }
    }

    private func repairTrailingRecordIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let readHandle = try FileHandle(forReadingFrom: url)
            defer { try? readHandle.close() }
            let endOffset = try readHandle.seekToEnd()
            guard endOffset > 0 else { return }
            try readHandle.seek(toOffset: endOffset - 1)
            let lastByte = try readHandle.read(upToCount: 1)
            if lastByte?.last == 0x0A {
                return
            }
        } catch {
            throw DiagnosticQueryError.storageUnavailable
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DiagnosticQueryError.storageUnavailable
        }
        guard !data.isEmpty, data.last != 0x0A else { return }

        let lastNewline = data.lastIndex(of: 0x0A)
        let tailStart = lastNewline.map { data.index(after: $0) } ?? data.startIndex
        let tail = Data(data[tailStart...])
        do {
            _ = try JSONDecoder().decode(DiagnosticEvent.self, from: tail)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0x0A]))
            try handle.synchronize()
        } catch DiagnosticSchemaError.unsupportedVersion(let version) {
            throw DiagnosticQueryError.unsupportedSchemaVersion(version)
        } catch {
            let validPrefixLength = lastNewline.map {
                data.distance(from: data.startIndex, to: data.index(after: $0))
            } ?? 0
            do {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.truncate(atOffset: UInt64(validPrefixLength))
                try handle.synchronize()
            } catch {
                throw DiagnosticQueryError.storageUnavailable
            }
        }
    }

    private func rotateIfNeeded(incomingBytes: UInt64) throws {
        guard let fileHandle else { throw DiagnosticQueryError.storageUnavailable }
        guard currentFileBytes > 0,
              currentFileBytes &+ incomingBytes > retentionPolicy.maxSegmentBytes else {
            return
        }

        flushPendingSynchronizeLocked()
        try fileHandle.close()
        self.fileHandle = nil
        currentFileBytes = 0

        let fileManager = FileManager.default
        if retentionPolicy.maxSegmentCount > 1 {
            let oldestIndex = retentionPolicy.maxSegmentCount - 1
            try? fileManager.removeItem(at: segmentURL(index: oldestIndex))
            if oldestIndex > 1 {
                for index in stride(from: oldestIndex - 1, through: 1, by: -1) {
                    let source = segmentURL(index: index)
                    guard fileManager.fileExists(atPath: source.path) else { continue }
                    try? fileManager.removeItem(at: segmentURL(index: index + 1))
                    try fileManager.moveItem(at: source, to: segmentURL(index: index + 1))
                }
            }
            try? fileManager.removeItem(at: segmentURL(index: 1))
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw DiagnosticQueryError.storageUnavailable
            }
            try fileManager.moveItem(at: fileURL, to: segmentURL(index: 1))
        } else {
            try? fileManager.removeItem(at: fileURL)
        }

        try openForAppendIfNeeded()
    }

    private func flushPendingSynchronize() {
        lock.lock()
        flushPendingSynchronizeLocked()
        lock.unlock()
    }

    private func flushPendingSynchronizeLocked() {
        coalescedSyncWorkItem?.cancel()
        coalescedSyncWorkItem = nil
        guard pendingUnsynchronizedWrites, let fileHandle else {
            pendingUnsynchronizedWrites = false
            return
        }
        try? fileHandle.synchronize()
        pendingUnsynchronizedWrites = false
    }

    private func segmentURL(index: Int) -> URL {
        fileURL.appendingPathExtension(String(index))
    }

    private func readEvents(from url: URL) throws -> [DiagnosticEvent] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DiagnosticQueryError.storageUnavailable
        }
        guard !data.isEmpty else { return [] }
        guard data.last == 0x0A else {
            let line = data.split(omittingEmptySubsequences: false, whereSeparator: { $0 == 0x0A }).count
            throw DiagnosticQueryError.corruptJournal(line)
        }

        var lines = data.split(omittingEmptySubsequences: false, whereSeparator: { $0 == 0x0A })
        _ = lines.popLast()
        var events: [DiagnosticEvent] = []
        events.reserveCapacity(lines.count)
        let decoder = JSONDecoder()
        for (index, line) in lines.enumerated() {
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
        return events
    }
}
