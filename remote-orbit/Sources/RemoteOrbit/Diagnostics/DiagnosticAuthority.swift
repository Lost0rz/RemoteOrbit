import Foundation

enum DiagnosticQueryError: Error, Equatable {
    case invalidFilter(String)
    case invalidCursor
    case unsupportedSchemaVersion(Int)
    case corruptJournal(Int)
    case storageUnavailable
}

struct DiagnosticQueryFilter: Equatable, Sendable {
    let eventTypes: Set<String>
    let subsystems: Set<String>
    let categories: Set<String>
    let severities: Set<DiagnosticSeverity>
    let processInstanceID: UUID?
    let sessionID: String?
    let incidentID: String?
    let correlationID: String?
    let cursor: String?
    let limit: Int

    init(
        eventTypes: Set<String> = [],
        subsystems: Set<String> = [],
        categories: Set<String> = [],
        severities: Set<DiagnosticSeverity> = [],
        processInstanceID: UUID? = nil,
        sessionID: String? = nil,
        incidentID: String? = nil,
        correlationID: String? = nil,
        cursor: String? = nil,
        limit: Int = 100
    ) throws {
        guard (1...500).contains(limit) else {
            throw DiagnosticQueryError.invalidFilter("limit must be between 1 and 500")
        }
        guard eventTypes.allSatisfy(DiagnosticQueryFilter.isToken),
              subsystems.allSatisfy(DiagnosticQueryFilter.isToken),
              categories.allSatisfy(DiagnosticQueryFilter.isToken) else {
            throw DiagnosticQueryError.invalidFilter("filter values must be stable tokens")
        }
        for identifier in [sessionID, incidentID, correlationID] {
            if let identifier,
               (identifier.isEmpty || identifier.utf8.count > 256) {
                throw DiagnosticQueryError.invalidFilter("invalid correlation identifier")
            }
        }
        if let cursor, UUID(uuidString: cursor) == nil {
            throw DiagnosticQueryError.invalidFilter("cursor must be an event id")
        }

        self.eventTypes = eventTypes
        self.subsystems = subsystems
        self.categories = categories
        self.severities = severities
        self.processInstanceID = processInstanceID
        self.sessionID = sessionID
        self.incidentID = incidentID
        self.correlationID = correlationID
        self.cursor = cursor
        self.limit = limit
    }

    func matches(_ event: DiagnosticEvent) -> Bool {
        (eventTypes.isEmpty || eventTypes.contains(event.eventType))
            && (subsystems.isEmpty || subsystems.contains(event.subsystem))
            && (categories.isEmpty || categories.contains(event.category))
            && (severities.isEmpty || severities.contains(event.severity))
            && (processInstanceID == nil || processInstanceID == event.processInstanceID)
            && (sessionID == nil || sessionID == event.sessionID)
            && (incidentID == nil || incidentID == event.incidentID)
            && (correlationID == nil || correlationID == event.correlationID)
    }

    private static func isToken(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 128,
              bytes[0] >= 97, bytes[0] <= 122 else { return false }
        return bytes.allSatisfy { byte in
            (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45 || byte == 46 || byte == 95
        }
    }
}

struct DiagnosticQueryPage: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let events: [DiagnosticEvent]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case events
        case nextCursor = "next_cursor"
    }
}

protocol DiagnosticJournal: Sendable {
    func append(_ event: DiagnosticEvent) throws
    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage
}

/// The only supported event boundary for new machine-readable diagnostics.
/// Producers submit typed observations; they do not know the journal path or
/// serialization format. Emit is non-blocking and best-effort.
protocol DiagnosticAuthority: AnyObject {
    var droppedEventCount: UInt64 { get }
    func emit(_ input: DiagnosticEventInput)
    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage
    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data
}

final class DiagnosticAuthorityService: DiagnosticAuthority, @unchecked Sendable {
    static let shared: any DiagnosticAuthority = DiagnosticAuthorityService(
        journal: JSONLinesDiagnosticJournal(
            fileURL: AppStorage.logsDirectory
                .appendingPathComponent("diagnostic-events-v1.jsonl")
        ),
        runtimeContext: .current(),
        clock: SystemDiagnosticClock()
    )

    private let journal: any DiagnosticJournal
    private let runtimeContext: DiagnosticRuntimeContext
    private let clock: any DiagnosticClock
    private let writerQueue: DispatchQueue
    private let pendingCapacity: DispatchSemaphore
    private let stateLock = NSLock()
    private var nextSequenceNumber: UInt64 = 1
    private var droppedCount: UInt64 = 0

    init(
        journal: any DiagnosticJournal,
        runtimeContext: DiagnosticRuntimeContext,
        clock: any DiagnosticClock,
        maximumPendingEvents: Int = 256,
        queueLabel: String = "com.remoteorbit.diagnostic-authority.writer"
    ) {
        precondition(maximumPendingEvents > 0)
        self.journal = journal
        self.runtimeContext = runtimeContext
        self.clock = clock
        self.pendingCapacity = DispatchSemaphore(value: maximumPendingEvents)
        self.writerQueue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    var droppedEventCount: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return droppedCount
    }

    func emit(_ input: DiagnosticEventInput) {
        guard pendingCapacity.wait(timeout: .now()) == .success else {
            incrementDroppedCount()
            return
        }

        let timestamp = clock.capture()
        writerQueue.async { [weak self] in
            guard let self else { return }
            defer { self.pendingCapacity.signal() }
            let event = DiagnosticEvent(
                input: input,
                context: self.runtimeContext,
                timestamp: timestamp,
                sequenceNumber: self.takeSequenceNumber()
            )
            do {
                try self.journal.append(event)
            } catch {
                self.incrementDroppedCount()
            }
        }
    }

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        try writerQueue.sync {
            try journal.query(filter)
        }
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data {
        let page = try query(filter)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(page)
    }

    private func takeSequenceNumber() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        let value = nextSequenceNumber
        nextSequenceNumber &+= 1
        return value
    }

    private func incrementDroppedCount() {
        stateLock.lock()
        droppedCount &+= 1
        stateLock.unlock()
    }
}
