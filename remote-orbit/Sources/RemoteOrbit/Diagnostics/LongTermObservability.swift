import Darwin
import Foundation

enum LongTermIncidentProducer: Int64, Sendable {
    case service = 1
    case audioPipe = 2

    var diagnosticName: String {
        switch self {
        case .service: return "long_term_service"
        case .audioPipe: return "audio_pipe"
        }
    }
}

enum LongTermIncidentTriggerKind: Int64, Sendable {
    case bleGap = 1
    case renderStarvation = 2
    case mainQueueLag = 3
    case traceDrop = 4
    case manual = 5

    var diagnosticName: String {
        switch self {
        case .bleGap: return "ble_gap"
        case .renderStarvation: return "render_starvation"
        case .mainQueueLag: return "main_queue_lag"
        case .traceDrop: return "trace_drop"
        case .manual: return "manual"
        }
    }
}

struct LongTermIncidentAnchor: Equatable, Sendable {
    let identity: UInt64
    let timestampNanoseconds: UInt64
    let producer: LongTermIncidentProducer
    let trigger: LongTermIncidentTriggerKind
}

/// A bounded, lock-free first-writer-wins incident identity shared by the
/// service and AudioPipe traces. Producers publish only fixed scalar metadata;
/// all formatting and serialization stays on the detached/off-path consumer.
final class LongTermIncidentCoordinator: @unchecked Sendable {
    static let shared = LongTermIncidentCoordinator()

    private var nextIdentity: Int64 = 0
    /// A positive value means a logical voice capture owns the coordinator;
    /// a negative value is the short initialization state used while a new
    /// generation clears the previous incident scalars.
    private var nextCaptureToken: Int64 = 0
    private var activeCaptureToken: Int64 = 0
    private var activeToken: Int64 = 0
    private var serviceReservation: Int64 = 0
    private var audioPipeReservation: Int64 = 0
    private var serviceTimestamp: UInt64 = 0
    private var serviceTrigger: Int64 = 0
    private var audioPipeTimestamp: UInt64 = 0
    private var audioPipeTrigger: Int64 = 0

    @discardableResult
    func beginCaptureIfNeeded() -> Bool {
        let token = OSAtomicIncrement64Barrier(&nextCaptureToken)
        let initializingToken = -token
        guard OSAtomicCompareAndSwap64Barrier(0, initializingToken, &activeCaptureToken) else {
            return false
        }
        clear(&activeToken)
        clear(&serviceReservation)
        clear(&audioPipeReservation)
        serviceTimestamp = 0
        serviceTrigger = 0
        audioPipeTimestamp = 0
        audioPipeTrigger = 0
        _ = OSAtomicCompareAndSwap64Barrier(
            initializingToken,
            token,
            &activeCaptureToken
        )
        return true
    }

    /// Ends ownership after all producer snapshots for the logical capture
    /// have been detached. The next capture performs the scalar reset before
    /// publishing its active generation.
    func endCapture() {
        let token = OSAtomicAdd64Barrier(0, &activeCaptureToken)
        guard token > 0 else { return }
        _ = OSAtomicCompareAndSwap64Barrier(token, 0, &activeCaptureToken)
    }

    func trigger(
        producer: LongTermIncidentProducer,
        kind: LongTermIncidentTriggerKind,
        timestampNanoseconds: UInt64
    ) {
        guard OSAtomicAdd64Barrier(0, &activeCaptureToken) > 0 else { return }
        guard OSAtomicAdd64Barrier(0, &activeToken) == 0 else { return }
        let identity = OSAtomicIncrement64Barrier(&nextIdentity)
        let encoded = (identity << 2) | producer.rawValue
        let reserved: Bool
        switch producer {
        case .service:
            reserved = withUnsafeMutablePointer(to: &serviceReservation) {
                OSAtomicCompareAndSwap64Barrier(0, encoded, $0)
            }
        case .audioPipe:
            reserved = withUnsafeMutablePointer(to: &audioPipeReservation) {
                OSAtomicCompareAndSwap64Barrier(0, encoded, $0)
            }
        }
        guard reserved else { return }
        switch producer {
        case .service:
            serviceTimestamp = timestampNanoseconds
            serviceTrigger = kind.rawValue
        case .audioPipe:
            audioPipeTimestamp = timestampNanoseconds
            audioPipeTrigger = kind.rawValue
        }
        _ = OSAtomicCompareAndSwap64Barrier(0, encoded, &activeToken)
    }

    func currentAnchor() -> LongTermIncidentAnchor? {
        guard OSAtomicAdd64Barrier(0, &activeCaptureToken) > 0 else { return nil }
        let encoded = OSAtomicAdd64Barrier(0, &activeToken)
        guard encoded != 0 else { return nil }
        let producerRaw = encoded & 3
        let producer = LongTermIncidentProducer(rawValue: producerRaw) ?? .service
        let identity = UInt64(encoded >> 2)
        switch producer {
        case .service:
            return LongTermIncidentAnchor(
                identity: identity,
                timestampNanoseconds: serviceTimestamp,
                producer: producer,
                trigger: LongTermIncidentTriggerKind(rawValue: serviceTrigger) ?? .manual
            )
        case .audioPipe:
            return LongTermIncidentAnchor(
                identity: identity,
                timestampNanoseconds: audioPipeTimestamp,
                producer: producer,
                trigger: LongTermIncidentTriggerKind(rawValue: audioPipeTrigger) ?? .manual
            )
        }
    }

    private func clear(_ value: UnsafeMutablePointer<Int64>) {
        while true {
            let oldValue = OSAtomicAdd64Barrier(0, value)
            guard oldValue != 0 else { return }
            if OSAtomicCompareAndSwap64Barrier(oldValue, 0, value) { return }
        }
    }
}

enum LongTermObservationKind: String, Codable, CaseIterable, Sendable {
    case bleArrival = "ble_arrival"
    case decodeComplete = "decode_complete"
    case pcmSubmitted = "pcm_submitted"
    case render
    case queueStarvation = "queue_starvation"
    case lifecycle
}

enum LongTermObservationSemanticMarker: String, Codable, Sendable {
    case active
    case tail
    case unclassified
}

struct LongTermObservationPoint: Equatable, Sendable {
    let timestampNanoseconds: UInt64
    let kind: LongTermObservationKind
    let requestedFrames: UInt64
    let filledFrames: UInt64
    let unfilledFrames: UInt64
    let queueDepthFrames: UInt64
    let byteOrSampleCount: UInt64
    let marker: LongTermObservationSemanticMarker
    let streamIdentity: UInt64
    let sequence: UInt64

    init(
        timestampNanoseconds: UInt64,
        kind: LongTermObservationKind,
        requestedFrames: UInt64,
        filledFrames: UInt64,
        unfilledFrames: UInt64,
        queueDepthFrames: UInt64,
        byteOrSampleCount: UInt64,
        marker: LongTermObservationSemanticMarker,
        streamIdentity: UInt64 = 0,
        sequence: UInt64 = 0
    ) {
        self.timestampNanoseconds = timestampNanoseconds
        self.kind = kind
        self.requestedFrames = requestedFrames
        self.filledFrames = filledFrames
        self.unfilledFrames = unfilledFrames
        self.queueDepthFrames = queueDepthFrames
        self.byteOrSampleCount = byteOrSampleCount
        self.marker = marker
        self.streamIdentity = streamIdentity
        self.sequence = sequence
    }

    func toDiagnosticJSONValue() -> DiagnosticJSONValue {
        .object([
            "timestamp_nanoseconds": .unsignedInteger(timestampNanoseconds),
            "kind": .string(kind.rawValue),
            "requested_frames": .unsignedInteger(requestedFrames),
            "filled_frames": .unsignedInteger(filledFrames),
            "unfilled_frames": .unsignedInteger(unfilledFrames),
            "queue_depth_frames": .unsignedInteger(queueDepthFrames),
            "byte_or_sample_count": .unsignedInteger(byteOrSampleCount),
            "marker": .string(marker.rawValue),
            "stream_identity": .unsignedInteger(streamIdentity),
            "sequence": .unsignedInteger(sequence),
        ])
    }
}

struct FixedCapacityObservationTraceSnapshot: Equatable, Sendable {
    let front: [LongTermObservationPoint]
    let recent: [LongTermObservationPoint]
    let incident: [LongTermObservationPoint]
    let incidentAnchor: LongTermIncidentAnchor?
    let droppedObservationCount: UInt64
    let overwrittenObservationCount: UInt64

    var all: [LongTermObservationPoint] { front + recent }

    func merged(with other: FixedCapacityObservationTraceSnapshot) -> FixedCapacityObservationTraceSnapshot {
        let mergedAll = (all + other.all).sorted {
            if $0.timestampNanoseconds == $1.timestampNanoseconds {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.timestampNanoseconds < $1.timestampNanoseconds
        }
        let hasIncident = !incident.isEmpty || !other.incident.isEmpty
        let leftIncident = incident.isEmpty && hasIncident ? all : incident
        let rightIncident = other.incident.isEmpty && hasIncident ? other.all : other.incident
        let mergedIncident = (leftIncident + rightIncident).sorted {
            if $0.timestampNanoseconds == $1.timestampNanoseconds {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.timestampNanoseconds < $1.timestampNanoseconds
        }
        let anchors = [incidentAnchor, other.incidentAnchor].compactMap { $0 }
        let mergedAnchor = anchors.min {
            if $0.identity == $1.identity { return $0.timestampNanoseconds < $1.timestampNanoseconds }
            return $0.identity < $1.identity
        }
        return FixedCapacityObservationTraceSnapshot(
            front: mergedAll,
            recent: [],
            incident: mergedIncident,
            incidentAnchor: mergedAnchor,
            droppedObservationCount: droppedObservationCount &+ other.droppedObservationCount,
            overwrittenObservationCount: overwrittenObservationCount &+ other.overwrittenObservationCount
        )
    }
}

struct LongTermAudioObservationSnapshot: Equatable, Sendable {
    let trace: FixedCapacityObservationTraceSnapshot
    let mainQueueLag: MainQueueLagSummary
}

/// A bounded trace for the timing path. Append only writes into preallocated
/// slots and does not call the DiagnosticAuthority or perform I/O.
struct FixedCapacityObservationTrace: Sendable {
    private var front: [LongTermObservationPoint?]
    private var recent: [LongTermObservationPoint?]
    private var frontCount = 0
    private var recentCount = 0
    private var recentWriteIndex = 0
    private var lastTimestampNanoseconds: UInt64?
    private var incident: [LongTermObservationPoint?]
    private var incidentCount = 0
    private var incidentWriteIndex = 0
    private var incidentFrozen = false
    private var incidentFollowup: [LongTermObservationPoint?]
    private var incidentFollowupCount = 0
    private var incidentFollowupWriteIndex = 0
    private var incidentFollowupActive = false
    private var incidentHardFrozen = false
    private var incidentAnchor: LongTermIncidentAnchor?
    private let incidentCoordinator: LongTermIncidentCoordinator
    private let incidentProducer: LongTermIncidentProducer

    private(set) var droppedObservationCount: UInt64 = 0
    private(set) var overwrittenObservationCount: UInt64 = 0

    init(
        frontCapacity: Int,
        recentCapacity: Int,
        incidentCapacity: Int = 128,
        incidentCoordinator: LongTermIncidentCoordinator = .shared,
        incidentProducer: LongTermIncidentProducer = .service
    ) {
        precondition(frontCapacity >= 0)
        precondition(recentCapacity >= 0)
        precondition(incidentCapacity > 0)
        precondition(frontCapacity + recentCapacity > 0)
        front = Array(repeating: nil, count: frontCapacity)
        recent = Array(repeating: nil, count: recentCapacity)
        incident = Array(repeating: nil, count: incidentCapacity)
        incidentFollowup = Array(repeating: nil, count: incidentCapacity)
        self.incidentCoordinator = incidentCoordinator
        self.incidentProducer = incidentProducer
    }

    mutating func reset() {
        for index in front.indices { front[index] = nil }
        for index in recent.indices { recent[index] = nil }
        frontCount = 0
        recentCount = 0
        recentWriteIndex = 0
        lastTimestampNanoseconds = nil
        for index in incident.indices { incident[index] = nil }
        incidentCount = 0
        incidentWriteIndex = 0
        incidentFrozen = false
        for index in incidentFollowup.indices { incidentFollowup[index] = nil }
        incidentFollowupCount = 0
        incidentFollowupWriteIndex = 0
        incidentFollowupActive = false
        incidentHardFrozen = false
        incidentAnchor = nil
        droppedObservationCount = 0
        overwrittenObservationCount = 0
    }

    @discardableResult
    mutating func append(_ point: LongTermObservationPoint) -> Bool {
        synchronizeIncidentWithCoordinator()
        if let lastTimestampNanoseconds,
           point.timestampNanoseconds < lastTimestampNanoseconds {
            droppedObservationCount &+= 1
            incidentCoordinator.trigger(
                producer: incidentProducer,
                kind: .traceDrop,
                timestampNanoseconds: lastTimestampNanoseconds
            )
            synchronizeIncidentWithCoordinator()
            return false
        }
        lastTimestampNanoseconds = point.timestampNanoseconds

        if !incidentFrozen {
            if incidentCount < incident.count { incidentCount += 1 }
            incident[incidentWriteIndex] = point
            incidentWriteIndex = (incidentWriteIndex + 1) % incident.count
        } else if incidentFollowupActive,
                  incidentFollowupCount < incidentFollowup.count {
            incidentFollowup[incidentFollowupWriteIndex] = point
            incidentFollowupCount += 1
            incidentFollowupWriteIndex = (incidentFollowupWriteIndex + 1) % incidentFollowup.count
        }

        if frontCount < front.count {
            front[frontCount] = point
            frontCount += 1
            return true
        }

        guard !recent.isEmpty else {
            droppedObservationCount &+= 1
            incidentCoordinator.trigger(
                producer: incidentProducer,
                kind: .traceDrop,
                timestampNanoseconds: point.timestampNanoseconds
            )
            synchronizeIncidentWithCoordinator()
            return false
        }

        if recentCount == recent.count {
            overwrittenObservationCount &+= 1
        } else {
            recentCount += 1
        }
        recent[recentWriteIndex] = point
        recentWriteIndex = (recentWriteIndex + 1) % recent.count
        return true
    }

    /// Stops the preallocated incident ring at the first material anomaly.
    /// This only flips a bounded in-memory bit; copying/serialization happens
    /// later when the detached snapshot is consumed off the hot path.
    mutating func freezeIncidentWindow() {
        incidentFrozen = true
        incidentHardFrozen = true
        incidentFollowupActive = false
    }

    mutating func synchronizeIncidentWithCoordinator() {
        guard !incidentHardFrozen,
              let anchor = incidentCoordinator.currentAnchor() else { return }
        incidentAnchor = anchor
        incidentFrozen = true
        incidentFollowupActive = true
    }

    func snapshot() -> FixedCapacityObservationTraceSnapshot {
        var frontSnapshot: [LongTermObservationPoint] = []
        frontSnapshot.reserveCapacity(frontCount)
        for index in 0..<frontCount {
            if let point = front[index] { frontSnapshot.append(point) }
        }

        var recentSnapshot: [LongTermObservationPoint] = []
        recentSnapshot.reserveCapacity(recentCount)
        guard !recent.isEmpty else {
            return FixedCapacityObservationTraceSnapshot(
                front: frontSnapshot,
                recent: recentSnapshot,
                incident: incidentSnapshot(),
                incidentAnchor: incidentAnchor,
                droppedObservationCount: droppedObservationCount,
                overwrittenObservationCount: overwrittenObservationCount
            )
        }

        let start = recentCount == recent.count ? recentWriteIndex : 0
        for offset in 0..<recentCount {
            let index = (start + offset) % recent.count
            if let point = recent[index] { recentSnapshot.append(point) }
        }
        return FixedCapacityObservationTraceSnapshot(
            front: frontSnapshot,
            recent: recentSnapshot,
            incident: incidentSnapshot(),
            incidentAnchor: incidentAnchor,
            droppedObservationCount: droppedObservationCount,
            overwrittenObservationCount: overwrittenObservationCount
        )
    }

    private func incidentSnapshot() -> [LongTermObservationPoint] {
        var snapshot: [LongTermObservationPoint] = []
        snapshot.reserveCapacity(incidentCount)
        guard incidentFrozen, !incident.isEmpty else { return snapshot }
        let start = incidentCount == incident.count ? incidentWriteIndex : 0
        for offset in 0..<incidentCount {
            let index = (start + offset) % incident.count
            if let point = incident[index] { snapshot.append(point) }
        }
        if incidentFollowupActive {
            snapshot.append(contentsOf: incidentFollowup.prefix(incidentFollowupCount).compactMap { $0 })
            snapshot.sort {
                if $0.timestampNanoseconds == $1.timestampNanoseconds {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                return $0.timestampNanoseconds < $1.timestampNanoseconds
            }
        }
        return snapshot
    }
}

struct MainQueueLagOccurrence: Equatable, Sendable {
    let timestampNanoseconds: UInt64
    let lagNanoseconds: UInt64
}

struct MainQueueLagSummary: Equatable, Sendable {
    let sampleCount: UInt64
    let maxLagNanoseconds: UInt64
    let p95LagNanoseconds: UInt64
    let histogram: [UInt64]
    let incidentOccurrences: [MainQueueLagOccurrence]

    init(
        sampleCount: UInt64,
        maxLagNanoseconds: UInt64,
        p95LagNanoseconds: UInt64,
        histogram: [UInt64],
        incidentOccurrences: [MainQueueLagOccurrence] = []
    ) {
        self.sampleCount = sampleCount
        self.maxLagNanoseconds = maxLagNanoseconds
        self.p95LagNanoseconds = p95LagNanoseconds
        self.histogram = histogram
        self.incidentOccurrences = incidentOccurrences
    }

    static let empty = MainQueueLagSummary(
        sampleCount: 0,
        maxLagNanoseconds: 0,
        p95LagNanoseconds: 0,
        histogram: [],
        incidentOccurrences: []
    )
}

struct MainQueueLagAccumulator: Sendable {
    private let bucketUpperBoundsNanoseconds: [UInt64]
    private var bucketCounts: [UInt64]
    private let maxSampleCount: Int
    private var samples: [UInt64]
    private var sampleCount = 0
    private var sampleWriteIndex = 0
    private let maxIncidentSampleCount: Int
    private let incidentLagThresholdNanoseconds: UInt64
    private var incidentOccurrences: [MainQueueLagOccurrence] = []
    private(set) var totalSampleCount: UInt64 = 0

    init(
        bucketUpperBoundsNanoseconds: [UInt64] = [
            1_000_000,
            5_000_000,
            10_000_000,
            25_000_000,
            50_000_000,
            100_000_000,
            UInt64.max,
        ],
        maxSampleCount: Int = 512,
        maxIncidentSampleCount: Int = 32,
        incidentLagThresholdNanoseconds: UInt64 = 50_000_000
    ) {
        precondition(!bucketUpperBoundsNanoseconds.isEmpty)
        precondition(bucketUpperBoundsNanoseconds == bucketUpperBoundsNanoseconds.sorted())
        precondition(maxSampleCount > 0)
        precondition(maxIncidentSampleCount > 0)
        self.bucketUpperBoundsNanoseconds = bucketUpperBoundsNanoseconds
        bucketCounts = Array(repeating: 0, count: bucketUpperBoundsNanoseconds.count)
        self.maxSampleCount = maxSampleCount
        self.maxIncidentSampleCount = maxIncidentSampleCount
        self.incidentLagThresholdNanoseconds = incidentLagThresholdNanoseconds
        samples = Array(repeating: 0, count: maxSampleCount)
    }

    mutating func record(lagNanoseconds: UInt64, timestampNanoseconds: UInt64? = nil) {
        let bucket = bucketUpperBoundsNanoseconds.firstIndex { lagNanoseconds <= $0 }!
        if sampleCount == maxSampleCount {
            let oldValue = samples[sampleWriteIndex]
            let oldBucket = bucketUpperBoundsNanoseconds.firstIndex { oldValue <= $0 }!
            bucketCounts[oldBucket] &-= 1
        } else {
            sampleCount += 1
        }

        samples[sampleWriteIndex] = lagNanoseconds
        sampleWriteIndex = (sampleWriteIndex + 1) % maxSampleCount
        bucketCounts[bucket] &+= 1
        totalSampleCount &+= 1
        if lagNanoseconds >= incidentLagThresholdNanoseconds,
           let timestampNanoseconds,
           incidentOccurrences.count < maxIncidentSampleCount {
            incidentOccurrences.append(
                MainQueueLagOccurrence(
                    timestampNanoseconds: timestampNanoseconds,
                    lagNanoseconds: lagNanoseconds
                )
            )
        }
    }

    var summary: MainQueueLagSummary {
        guard sampleCount > 0 else {
            return MainQueueLagSummary(
                sampleCount: totalSampleCount,
                maxLagNanoseconds: 0,
                p95LagNanoseconds: 0,
                histogram: bucketCounts,
                incidentOccurrences: incidentOccurrences
            )
        }
        var values = Array(samples.prefix(sampleCount))
        values.sort()
        let rank = max(0, Int(ceil(Double(sampleCount) * 0.95)) - 1)
        return MainQueueLagSummary(
            sampleCount: totalSampleCount,
            maxLagNanoseconds: values.last ?? 0,
            p95LagNanoseconds: values[rank],
            histogram: bucketCounts,
            incidentOccurrences: incidentOccurrences
        )
    }
}

final class MainQueueResponsivenessProbe: @unchecked Sendable {
    private let sampleIntervalNanoseconds: UInt64
    private let incidentLagThresholdNanoseconds: UInt64
    private let onMaterialLag: (() -> Void)?
    private let lock = NSLock()
    private var accumulator = MainQueueLagAccumulator()
    private var timer: DispatchSourceTimer?
    private var running = false
    private var incidentSignaled = false
    private var stoppedSummary: MainQueueLagSummary?

    init(
        sampleIntervalNanoseconds: UInt64,
        incidentLagThresholdNanoseconds: UInt64 = 50_000_000,
        onMaterialLag: (() -> Void)? = nil
    ) {
        precondition(sampleIntervalNanoseconds > 0)
        self.sampleIntervalNanoseconds = sampleIntervalNanoseconds
        self.incidentLagThresholdNanoseconds = incidentLagThresholdNanoseconds
        self.onMaterialLag = onMaterialLag
        self.accumulator = MainQueueLagAccumulator(
            incidentLagThresholdNanoseconds: incidentLagThresholdNanoseconds
        )
    }

    func start() {
        lock.lock()
        guard !running else {
            lock.unlock()
            return
        }
        running = true
        incidentSignaled = false
        stoppedSummary = nil
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(
            deadline: .now() + .nanoseconds(Int(sampleIntervalNanoseconds)),
            repeating: .nanoseconds(Int(sampleIntervalNanoseconds))
        )
        timer.setEventHandler { [weak self] in
            let scheduled = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let now = DispatchTime.now().uptimeNanoseconds
                self.record(
                    lagNanoseconds: now >= scheduled ? now - scheduled : 0,
                    timestampNanoseconds: scheduled
                )
            }
        }
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    func record(lagNanoseconds: UInt64) {
        record(lagNanoseconds: lagNanoseconds, timestampNanoseconds: nil)
    }

    func record(lagNanoseconds: UInt64, timestampNanoseconds: UInt64) {
        record(lagNanoseconds: lagNanoseconds, timestampNanoseconds: Optional(timestampNanoseconds))
    }

    private func record(lagNanoseconds: UInt64, timestampNanoseconds: UInt64?) {
        lock.lock()
        accumulator.record(
            lagNanoseconds: lagNanoseconds,
            timestampNanoseconds: timestampNanoseconds
        )
        let shouldSignal = lagNanoseconds > incidentLagThresholdNanoseconds && !incidentSignaled
        if shouldSignal { incidentSignaled = true }
        lock.unlock()
        if shouldSignal { onMaterialLag?() }
    }

    func stop() -> MainQueueLagSummary {
        lock.lock()
        if let stoppedSummary {
            lock.unlock()
            return stoppedSummary
        }
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        running = false
        let summary = accumulator.summary
        stoppedSummary = summary
        lock.unlock()
        return summary
    }
}

enum LongTermAnomalyFlag: String, Codable, CaseIterable, Hashable, Sendable {
    case notificationGap = "notification_gap"
    case decodeGap = "decode_gap"
    case activeDeficit = "active_deficit"
    case tailDeficit = "tail_deficit"
    case queueStarvation = "queue_starvation"
    case lifecycleInconsistency = "lifecycle_inconsistency"
    case mainQueueLag = "main_queue_lag"
    case deliveryDeficit = "delivery_deficit"
    case traceDropped = "trace_dropped"
    case traceOverwritten = "trace_overwritten"
    case authorityWriteFailure = "authority_write_failure"
}

struct LongTermRuntimeIdentity: Equatable, Sendable {
    let processInstanceID: UUID
    let processID: Int32
    let binaryPath: String
    let appVersion: String
    let buildVersion: String
    let sourceRevision: String?

    init(
        processInstanceID: UUID,
        processID: Int32,
        binaryPath: String,
        appVersion: String,
        buildVersion: String,
        sourceRevision: String?
    ) {
        self.processInstanceID = processInstanceID
        self.processID = processID
        self.binaryPath = binaryPath
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.sourceRevision = sourceRevision
    }

    static func current() -> LongTermRuntimeIdentity {
        let context = DiagnosticRuntimeContext.current()
        return LongTermRuntimeIdentity(
            processInstanceID: context.processInstanceID,
            processID: context.processID,
            binaryPath: context.binaryPath,
            appVersion: context.appVersion,
            buildVersion: context.buildVersion,
            sourceRevision: context.sourceRevision
        )
    }
}

struct LongTermVoiceSessionSummary: Equatable, Sendable {
    static let schemaVersion: UInt64 = 1

    var sessionID: String
    var captureID: String
    var voiceAttemptID = "unavailable"
    var expectedFrames: UInt64 = 0
    var deliveredFrames: UInt64 = 0
    var activeExpectedFrames: UInt64 = 0
    var activeDeliveredFrames: UInt64 = 0
    var tailExpectedFrames: UInt64 = 0
    var tailDeliveredFrames: UInt64 = 0
    var notificationGapCount: UInt64 = 0
    var decodeGapCount: UInt64 = 0
    var queueStarvationCount: UInt64 = 0
    var lifecycleInconsistencyCount: UInt64 = 0
    var mainQueueLag: MainQueueLagSummary = .empty
    var traceDroppedObservationCount: UInt64 = 0
    var authorityDroppedEventCount: UInt64 = 0
    var authorityWriteFailureCount: UInt64 = 0
    var traceOverwrittenObservationCount: UInt64 = 0
    var incidentIdentity: UInt64?
    var incidentAnchorTimestampNanoseconds: UInt64?
    var incidentTriggerSource = "unavailable"
    var incidentTrigger = "unavailable"
    var anomalyFlags: [LongTermAnomalyFlag] = []
    var tracePersisted = false
    var receiverEvidenceStatus = "unavailable"
    var physicalDownTimestampNanoseconds: UInt64?
    var holdConfirmedTimestampNanoseconds: UInt64?
    var physicalUpTimestampNanoseconds: UInt64?
    var micOpenTimestampNanoseconds: UInt64?
    var audioStartTimestampNanoseconds: UInt64?
    var audioStartReason: UInt64?
    var audioStreamID: UInt64?
    var audioFirstTimestampNanoseconds: UInt64?
    var micCloseTimestampNanoseconds: UInt64?
    var audioStopTimestampNanoseconds: UInt64?
    var drainBeginTimestampNanoseconds: UInt64?
    var drainFinishTimestampNanoseconds: UInt64?
    var outputCompleteTimestampNanoseconds: UInt64?
    var controlPolicy = "unavailable"
    var classification = "unavailable"
    var triggerSource = "unavailable"
    var triggerKey = "unavailable"
    var atvvProtocolVersion = "unavailable"
    var atvvMode = "unavailable"
    var atvvCodec = "unavailable"
    var atvvSampleRate: UInt64?
    var notificationCount: UInt64 = 0
    var notificationBytes: UInt64 = 0
    var notificationSizeMin: UInt64?
    var notificationSizeMax: UInt64?
    var notificationSizeDistribution = "unavailable"
    var notificationFrameSizeDistribution = "unavailable"
    var notificationMaxGapMilliseconds: Double?
    var notificationP95GapMilliseconds: Double?
    var notificationGapOver20Milliseconds: UInt64 = 0
    var notificationGapOver30Milliseconds: UInt64 = 0
    var notificationGapOver50Milliseconds: UInt64 = 0
    var notificationGapOver100Milliseconds: UInt64 = 0
    var decodedFrameCount: UInt64 = 0
    var decodedSampleCount: UInt64 = 0
    var decodedAudioDurationMilliseconds: Double?
    var decodeRejectCount: UInt64 = 0
    var zeroSampleDecodeCount: UInt64 = 0
    var audioSyncCount: UInt64 = 0
    var measurementElapsedMilliseconds: Double?
    var expectedSamples: UInt64?
    var deliveredSamples: UInt64?
    var deliveryRatio: Double?
    var deficitSamples: UInt64?
    var deficitMilliseconds: Double?
    var submittedFrames: UInt64 = 0
    var renderedFrames: UInt64 = 0
    var queueStarvationFrames: UInt64 = 0
    var activeRequestedFrames: UInt64 = 0
    var activeFilledFrames: UInt64 = 0
    var activeUnfilledFrames: UInt64 = 0
    var activeUnderrunCallbackCount: UInt64 = 0
    var activeUnderrunFrames: UInt64 = 0
    var tailRenderedFrames: UInt64 = 0
    var tailEmptyCallbackCount: UInt64 = 0
    var queueDepthMinFrames: UInt64?
    var queueDepthMaxFrames: UInt64?
    var queueDepthEndFrames: UInt64?
    var overflowDroppedFrames: UInt64 = 0
    var runtimeIdentity: LongTermRuntimeIdentity?
    var underrunEpisodes: [DiagnosticUnderrunEpisode] = []

    init(sessionID: String, captureID: String) {
        self.sessionID = sessionID
        self.captureID = captureID
    }

    var deficitFrames: UInt64 { expectedFrames > deliveredFrames ? expectedFrames - deliveredFrames : 0 }
    var activeDeficitFrames: UInt64 {
        activeExpectedFrames > activeDeliveredFrames ? activeExpectedFrames - activeDeliveredFrames : 0
    }
    var tailDeficitFrames: UInt64 {
        tailExpectedFrames > tailDeliveredFrames ? tailExpectedFrames - tailDeliveredFrames : 0
    }

    mutating func recordDelivery(
        expectedFrames: UInt64,
        deliveredFrames: UInt64,
        marker: LongTermObservationSemanticMarker
    ) {
        self.expectedFrames &+= expectedFrames
        self.deliveredFrames &+= deliveredFrames
        switch marker {
        case .active:
            activeExpectedFrames &+= expectedFrames
            activeDeliveredFrames &+= deliveredFrames
        case .tail:
            tailExpectedFrames &+= expectedFrames
            tailDeliveredFrames &+= deliveredFrames
        case .unclassified:
            break
        }
    }

    mutating func recordNotification(bytes: UInt64, gapNanoseconds: UInt64?) {
        notificationCount &+= 1
        notificationBytes &+= bytes
        let gap = gapNanoseconds ?? 0
        if gap > 20_000_000 { notificationGapCount &+= 1 }
        if gap > 100_000_000 { notificationGapOver100Milliseconds &+= 1 }
    }

    mutating func recordDecode(frameCount: UInt64, sampleCount: UInt64) {
        decodedFrameCount &+= frameCount
        decodedSampleCount &+= sampleCount
    }

    mutating func recordSupply(submittedFrames: UInt64) {
        self.submittedFrames &+= submittedFrames
    }

    mutating func recordPlayout(
        expectedFrames: UInt64,
        deliveredFrames: UInt64,
        marker: LongTermObservationSemanticMarker
    ) {
        self.renderedFrames &+= deliveredFrames
        recordDelivery(
            expectedFrames: expectedFrames,
            deliveredFrames: deliveredFrames,
            marker: marker
        )
    }

    func toDiagnosticJSONValue() -> DiagnosticJSONValue {
        .object([
            "schema_version": .unsignedInteger(Self.schemaVersion),
            "session_id": .string(sessionID),
            "capture_id": .string(captureID),
            "voice_attempt_id": .string(voiceAttemptID),
            "expected_frames": .unsignedInteger(expectedFrames),
            "delivered_frames": .unsignedInteger(deliveredFrames),
            "deficit_frames": .unsignedInteger(deficitFrames),
            "active_expected_frames": .unsignedInteger(activeExpectedFrames),
            "active_delivered_frames": .unsignedInteger(activeDeliveredFrames),
            "active_deficit_frames": .unsignedInteger(activeDeficitFrames),
            "tail_expected_frames": .unsignedInteger(tailExpectedFrames),
            "tail_delivered_frames": .unsignedInteger(tailDeliveredFrames),
            "tail_deficit_frames": .unsignedInteger(tailDeficitFrames),
            "notification_gap_count": .unsignedInteger(notificationGapCount),
            "decode_gap_count": .unsignedInteger(decodeGapCount),
            "queue_starvation_count": .unsignedInteger(queueStarvationCount),
            "lifecycle_inconsistency_count": .unsignedInteger(lifecycleInconsistencyCount),
            "main_queue_sample_count": .unsignedInteger(mainQueueLag.sampleCount),
            "main_queue_max_lag_nanoseconds": .unsignedInteger(mainQueueLag.maxLagNanoseconds),
            "main_queue_p95_lag_nanoseconds": .unsignedInteger(mainQueueLag.p95LagNanoseconds),
            "main_queue_incident_occurrences": .array(mainQueueLag.incidentOccurrences.map {
                .object([
                    "timestamp_nanoseconds": .unsignedInteger($0.timestampNanoseconds),
                    "lag_nanoseconds": .unsignedInteger($0.lagNanoseconds),
                ])
            }),
            "trace_dropped_observations": .unsignedInteger(traceDroppedObservationCount),
            "trace_overwritten_observations": .unsignedInteger(traceOverwrittenObservationCount),
            "incident_identity": optionalUInt(incidentIdentity),
            "incident_anchor_timestamp_nanoseconds": optionalUInt(incidentAnchorTimestampNanoseconds),
            "incident_trigger_source": .string(incidentTriggerSource),
            "incident_trigger": .string(incidentTrigger),
            "authority_dropped_events": .unsignedInteger(authorityDroppedEventCount),
            "authority_write_failures": .unsignedInteger(authorityWriteFailureCount),
            "anomaly_flags": .array(anomalyFlags.map { .string($0.rawValue) }),
            "trace_persisted": .bool(tracePersisted),
            "receiver_evidence_status": .string(receiverEvidenceStatus),
            "physical_down_timestamp_nanoseconds": optionalUInt(physicalDownTimestampNanoseconds),
            "hold_confirmed_timestamp_nanoseconds": optionalUInt(holdConfirmedTimestampNanoseconds),
            "physical_up_timestamp_nanoseconds": optionalUInt(physicalUpTimestampNanoseconds),
            "mic_open_timestamp_nanoseconds": optionalUInt(micOpenTimestampNanoseconds),
            "audio_start_timestamp_nanoseconds": optionalUInt(audioStartTimestampNanoseconds),
            "audio_start_reason": optionalUInt(audioStartReason),
            "audio_stream_id": optionalUInt(audioStreamID),
            "audio_first_timestamp_nanoseconds": optionalUInt(audioFirstTimestampNanoseconds),
            "mic_close_timestamp_nanoseconds": optionalUInt(micCloseTimestampNanoseconds),
            "audio_stop_timestamp_nanoseconds": optionalUInt(audioStopTimestampNanoseconds),
            "drain_begin_timestamp_nanoseconds": optionalUInt(drainBeginTimestampNanoseconds),
            "drain_finish_timestamp_nanoseconds": optionalUInt(drainFinishTimestampNanoseconds),
            "output_complete_timestamp_nanoseconds": optionalUInt(outputCompleteTimestampNanoseconds),
            "control_policy": .string(controlPolicy),
            "classification": .string(classification),
            "trigger_source": .string(triggerSource),
            "trigger_key": .string(triggerKey),
            "atvv_protocol_version": .string(atvvProtocolVersion),
            "atvv_mode": .string(atvvMode),
            "atvv_codec": .string(atvvCodec),
            "atvv_sample_rate": optionalUInt(atvvSampleRate),
            "notification_count": .unsignedInteger(notificationCount),
            "notification_bytes": .unsignedInteger(notificationBytes),
            "notification_size_min": optionalUInt(notificationSizeMin),
            "notification_size_max": optionalUInt(notificationSizeMax),
            "notification_size_distribution": .string(notificationSizeDistribution),
            "notification_frame_size_distribution": .string(notificationFrameSizeDistribution),
            "notification_max_gap_milliseconds": optionalDouble(notificationMaxGapMilliseconds),
            "notification_p95_gap_milliseconds": optionalDouble(notificationP95GapMilliseconds),
            "notification_gap_over_20_milliseconds": .unsignedInteger(notificationGapOver20Milliseconds),
            "notification_gap_over_30_milliseconds": .unsignedInteger(notificationGapOver30Milliseconds),
            "notification_gap_over_50_milliseconds": .unsignedInteger(notificationGapOver50Milliseconds),
            "notification_gap_over_100_milliseconds": .unsignedInteger(notificationGapOver100Milliseconds),
            "decoded_frame_count": .unsignedInteger(decodedFrameCount),
            "decoded_sample_count": .unsignedInteger(decodedSampleCount),
            "decoded_audio_duration_milliseconds": optionalDouble(decodedAudioDurationMilliseconds),
            "decode_reject_count": .unsignedInteger(decodeRejectCount),
            "zero_sample_decode_count": .unsignedInteger(zeroSampleDecodeCount),
            "audio_sync_count": .unsignedInteger(audioSyncCount),
            "measurement_elapsed_milliseconds": optionalDouble(measurementElapsedMilliseconds),
            "expected_samples": optionalUInt(expectedSamples),
            "delivered_samples": optionalUInt(deliveredSamples),
            "delivery_ratio": optionalDouble(deliveryRatio),
            "deficit_samples": optionalUInt(deficitSamples),
            "deficit_milliseconds": optionalDouble(deficitMilliseconds),
            "submitted_frames": .unsignedInteger(submittedFrames),
            "rendered_frames": .unsignedInteger(renderedFrames),
            "queue_starvation_frames": .unsignedInteger(queueStarvationFrames),
            "active_requested_frames": .unsignedInteger(activeRequestedFrames),
            "active_filled_frames": .unsignedInteger(activeFilledFrames),
            "active_unfilled_frames": .unsignedInteger(activeUnfilledFrames),
            "active_underrun_callback_count": .unsignedInteger(activeUnderrunCallbackCount),
            "active_underrun_frames": .unsignedInteger(activeUnderrunFrames),
            "tail_rendered_frames": .unsignedInteger(tailRenderedFrames),
            "tail_empty_callback_count": .unsignedInteger(tailEmptyCallbackCount),
            "queue_depth_min_frames": optionalUInt(queueDepthMinFrames),
            "queue_depth_max_frames": optionalUInt(queueDepthMaxFrames),
            "queue_depth_end_frames": optionalUInt(queueDepthEndFrames),
            "overflow_dropped_frames": .unsignedInteger(overflowDroppedFrames),
            "underrun_episodes": .array(underrunEpisodes.map { $0.toDiagnosticJSONValue() }),
            "runtime_process_instance_id": runtimeIdentity.map { .string($0.processInstanceID.uuidString) } ?? .null,
            "runtime_process_id": runtimeIdentity.map { .integer(Int64($0.processID)) } ?? .null,
            "runtime_binary_path": runtimeIdentity.map { .string($0.binaryPath) } ?? .null,
            "runtime_app_version": runtimeIdentity.map { .string($0.appVersion) } ?? .null,
            "runtime_build_version": runtimeIdentity.map { .string($0.buildVersion) } ?? .null,
            "runtime_source_revision": runtimeIdentity.flatMap { $0.sourceRevision }.map { .string($0) } ?? .null,
        ])
    }

    private func optionalUInt(_ value: UInt64?) -> DiagnosticJSONValue {
        value.map(DiagnosticJSONValue.unsignedInteger) ?? .null
    }

    private func optionalDouble(_ value: Double?) -> DiagnosticJSONValue {
        value.map(DiagnosticJSONValue.double) ?? .null
    }

    func calculatedLifecycleInconsistencyCount() -> UInt64 {
        let orderedPairs: [(UInt64?, UInt64?)] = [
            (physicalDownTimestampNanoseconds, holdConfirmedTimestampNanoseconds),
            (physicalDownTimestampNanoseconds, micOpenTimestampNanoseconds),
            (micOpenTimestampNanoseconds, audioStartTimestampNanoseconds),
            (audioStartTimestampNanoseconds, audioFirstTimestampNanoseconds),
            (audioFirstTimestampNanoseconds, physicalUpTimestampNanoseconds),
            (physicalUpTimestampNanoseconds, micCloseTimestampNanoseconds),
            (audioStopTimestampNanoseconds, drainBeginTimestampNanoseconds),
            (drainBeginTimestampNanoseconds, drainFinishTimestampNanoseconds),
            (drainFinishTimestampNanoseconds, outputCompleteTimestampNanoseconds),
        ]
        return UInt64(orderedPairs.reduce(into: 0) { count, pair in
            if let first = pair.0, let second = pair.1, first > second {
                count += 1
            }
        })
    }
}

struct LongTermObservabilityThresholds: Equatable, Sendable {
    let maxNotificationGapCount: UInt64
    let maxNotificationGapOver100Count: UInt64
    let maxDecodeGapCount: UInt64
    let maxDeliveryDeficitSamples: UInt64
    let maxDeliveryDeficitMilliseconds: Double
    let maxActiveDeficitFrames: UInt64
    let maxTailDeficitFrames: UInt64
    let maxQueueStarvationCount: UInt64
    let maxLifecycleInconsistencyCount: UInt64
    let maxMainQueueP95LagNanoseconds: UInt64
    let maxTraceDroppedObservations: UInt64
    let maxAuthorityWriteFailures: UInt64

    init(
        maxNotificationGapCount: UInt64 = .max,
        maxNotificationGapOver100Count: UInt64 = 0,
        maxDecodeGapCount: UInt64 = 0,
        maxDeliveryDeficitSamples: UInt64 = 0,
        maxDeliveryDeficitMilliseconds: Double = 50,
        maxActiveDeficitFrames: UInt64 = 0,
        maxTailDeficitFrames: UInt64 = 0,
        maxQueueStarvationCount: UInt64 = 0,
        maxLifecycleInconsistencyCount: UInt64 = 0,
        maxMainQueueP95LagNanoseconds: UInt64 = 50_000_000,
        maxTraceDroppedObservations: UInt64 = 0,
        maxAuthorityWriteFailures: UInt64 = 0
    ) {
        self.maxNotificationGapCount = maxNotificationGapCount
        self.maxNotificationGapOver100Count = maxNotificationGapOver100Count
        self.maxDecodeGapCount = maxDecodeGapCount
        self.maxDeliveryDeficitSamples = maxDeliveryDeficitSamples
        self.maxDeliveryDeficitMilliseconds = maxDeliveryDeficitMilliseconds
        self.maxActiveDeficitFrames = maxActiveDeficitFrames
        self.maxTailDeficitFrames = maxTailDeficitFrames
        self.maxQueueStarvationCount = maxQueueStarvationCount
        self.maxLifecycleInconsistencyCount = maxLifecycleInconsistencyCount
        self.maxMainQueueP95LagNanoseconds = maxMainQueueP95LagNanoseconds
        self.maxTraceDroppedObservations = maxTraceDroppedObservations
        self.maxAuthorityWriteFailures = maxAuthorityWriteFailures
    }

    func classify(
        summary: LongTermVoiceSessionSummary,
        trace: FixedCapacityObservationTraceSnapshot
    ) -> [LongTermAnomalyFlag] {
        var flags: [LongTermAnomalyFlag] = []
        if summary.notificationGapCount > maxNotificationGapCount { flags.append(.notificationGap) }
        if summary.notificationGapOver100Milliseconds > maxNotificationGapOver100Count {
            flags.append(.notificationGap)
        }
        if summary.decodeGapCount > maxDecodeGapCount { flags.append(.decodeGap) }
        if (summary.deficitSamples ?? 0) > maxDeliveryDeficitSamples,
           (summary.deficitMilliseconds ?? 0) > maxDeliveryDeficitMilliseconds {
            flags.append(.deliveryDeficit)
        }
        if summary.activeDeficitFrames > maxActiveDeficitFrames { flags.append(.activeDeficit) }
        if summary.tailDeficitFrames > maxTailDeficitFrames { flags.append(.tailDeficit) }
        if summary.queueStarvationCount > maxQueueStarvationCount { flags.append(.queueStarvation) }
        if summary.lifecycleInconsistencyCount > maxLifecycleInconsistencyCount {
            flags.append(.lifecycleInconsistency)
        }
        if summary.mainQueueLag.p95LagNanoseconds > maxMainQueueP95LagNanoseconds {
            flags.append(.mainQueueLag)
        }
        if trace.droppedObservationCount > maxTraceDroppedObservations {
            flags.append(.traceDropped)
        }
        if summary.authorityWriteFailureCount > maxAuthorityWriteFailures {
            flags.append(.authorityWriteFailure)
        }
        return flags
    }
}

final class LongTermObservabilityService: @unchecked Sendable {
    static let shared = LongTermObservabilityService()

    private struct ActiveSession {
        var summary: LongTermVoiceSessionSummary
        var trace: FixedCapacityObservationTrace
        var detachedTraceSnapshot: FixedCapacityObservationTraceSnapshot? = nil

        init(summary: LongTermVoiceSessionSummary, coordinator: LongTermIncidentCoordinator) {
            self.summary = summary
            trace = FixedCapacityObservationTrace(
                frontCapacity: 64,
                recentCapacity: 256,
                incidentCoordinator: coordinator,
                incidentProducer: .service
            )
        }
    }

    private struct FinalizedSession {
        let sessionID: String
        let captureID: String
    }

    private let authority: any DiagnosticAuthority
    private let runtimeIdentity: LongTermRuntimeIdentity
    private let thresholds: LongTermObservabilityThresholds
    private let incidentCoordinator: LongTermIncidentCoordinator
    private let lock = NSLock()
    private var activeSession: ActiveSession?
    /// Keep one bounded post-end identity so a transport close that arrives
    /// after the gesture can be emitted as a correlated follow-up event.
    private var finalizedSession: FinalizedSession?

    init(
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared,
        runtimeIdentity: LongTermRuntimeIdentity = .current(),
        thresholds: LongTermObservabilityThresholds = LongTermObservabilityThresholds(),
        incidentCoordinator: LongTermIncidentCoordinator = .shared
    ) {
        self.authority = authority
        self.runtimeIdentity = runtimeIdentity
        self.thresholds = thresholds
        self.incidentCoordinator = incidentCoordinator
    }

    @discardableResult
    func observeTransportStart(
        protocolVersion: String,
        mode: String,
        codec: String,
        sampleRate: UInt64,
        reason: UInt64? = nil,
        streamID: UInt64? = nil,
        timestampNanoseconds: UInt64
    ) -> UUID {
        lock.lock()
        if activeSession == nil {
            incidentCoordinator.beginCaptureIfNeeded()
            activeSession = ActiveSession(
                summary: makeSummary(sessionID: "unavailable", captureID: UUID().uuidString),
                coordinator: incidentCoordinator
            )
        }
        let captureID = UUID(uuidString: activeSession!.summary.captureID) ?? UUID()
        activeSession!.summary.captureID = captureID.uuidString
        activeSession!.summary.audioStartTimestampNanoseconds = timestampNanoseconds
        activeSession!.summary.atvvProtocolVersion = protocolVersion
        activeSession!.summary.atvvMode = mode
        activeSession!.summary.atvvCodec = codec
        activeSession!.summary.atvvSampleRate = sampleRate
        activeSession!.summary.audioStartReason = reason
        activeSession!.summary.audioStreamID = streamID
        lock.unlock()
        return captureID
    }

    func begin(
        sessionID: UUID,
        attemptID: String? = nil,
        timestampNanoseconds: UInt64 = P1A4MonotonicClock.nowNanoseconds()
    ) {
        lock.lock()
        finalizedSession = nil
        if activeSession == nil {
            incidentCoordinator.beginCaptureIfNeeded()
            activeSession = ActiveSession(
                summary: makeSummary(sessionID: sessionID.uuidString, captureID: UUID().uuidString),
                coordinator: incidentCoordinator
            )
        } else {
            activeSession!.summary.sessionID = sessionID.uuidString
        }
        activeSession!.summary.physicalDownTimestampNanoseconds = timestampNanoseconds
        if let attemptID {
            activeSession!.summary.voiceAttemptID = attemptID
        }
        lock.unlock()
    }

    func observeControl(
        policy: String,
        classification: String,
        triggerSource: String,
        triggerKey: String = "unavailable"
    ) {
        lock.lock()
        guard activeSession != nil else {
            lock.unlock()
            return
        }
        activeSession!.summary.controlPolicy = policy
        activeSession!.summary.classification = classification
        activeSession!.summary.triggerSource = triggerSource
        activeSession!.summary.triggerKey = triggerKey
        lock.unlock()
    }

    func mark(_ event: String, timestampNanoseconds: UInt64, sessionID: UUID? = nil) {
        lock.lock()
        guard let currentSession = activeSession,
              sessionID == nil || currentSession.summary.sessionID == sessionID!.uuidString else {
            if let sessionID,
               let finalizedSession,
               finalizedSession.sessionID == sessionID.uuidString {
                let captureID = finalizedSession.captureID
                lock.unlock()
                emitLifecycleFollowup(
                    event: event,
                    timestampNanoseconds: timestampNanoseconds,
                    sessionID: sessionID,
                    captureID: captureID
                )
                return
            }
            lock.unlock()
            return
        }
        switch event {
        case "VOICE_DOWN": activeSession!.summary.physicalDownTimestampNanoseconds = timestampNanoseconds
        case "HOLD_CONFIRMED": activeSession!.summary.holdConfirmedTimestampNanoseconds = timestampNanoseconds
        case "PHYSICAL_UP": activeSession!.summary.physicalUpTimestampNanoseconds = timestampNanoseconds
        case "MIC_OPEN_TX": activeSession!.summary.micOpenTimestampNanoseconds = timestampNanoseconds
        case "AUDIO_START": activeSession!.summary.audioStartTimestampNanoseconds = timestampNanoseconds
        case "AUDIO_FIRST": activeSession!.summary.audioFirstTimestampNanoseconds = timestampNanoseconds
        case "MIC_CLOSE_TX": activeSession!.summary.micCloseTimestampNanoseconds = timestampNanoseconds
        case "AUDIO_STOP": activeSession!.summary.audioStopTimestampNanoseconds = timestampNanoseconds
        case "AUDIO_DRAIN_BEGIN", "OUTPUT_DRAIN_BEGIN": activeSession!.summary.drainBeginTimestampNanoseconds = timestampNanoseconds
        case "DRAIN_FINISH": activeSession!.summary.drainFinishTimestampNanoseconds = timestampNanoseconds
        case "AUDIO_PIPELINE_CLOSED", "OUTPUT_DRAIN_COMPLETE": activeSession!.summary.outputCompleteTimestampNanoseconds = timestampNanoseconds
        default: break
        }
        lock.unlock()
    }

    func observeNotification(
        bytes: UInt64,
        gapNanoseconds: UInt64?,
        timestampNanoseconds: UInt64? = nil
    ) {
        lock.lock()
        activeSession?.summary.recordNotification(bytes: bytes, gapNanoseconds: gapNanoseconds)
        if let timestampNanoseconds {
            let streamIdentity = activeSession?.summary.audioStreamID ?? 0
            activeSession?.trace.append(
                LongTermObservationPoint(
                    timestampNanoseconds: timestampNanoseconds,
                    kind: .bleArrival,
                    requestedFrames: 0,
                    filledFrames: 0,
                    unfilledFrames: 0,
                    queueDepthFrames: 0,
                    byteOrSampleCount: bytes,
                    marker: .unclassified,
                    streamIdentity: streamIdentity
                )
            )
        }
        if let gapNanoseconds, gapNanoseconds > 100_000_000 {
            incidentCoordinator.trigger(
                producer: .service,
                kind: .bleGap,
                timestampNanoseconds: timestampNanoseconds ?? P1A4MonotonicClock.nowNanoseconds()
            )
            activeSession?.trace.synchronizeIncidentWithCoordinator()
        }
        lock.unlock()
    }

    func observeTransportMetrics(
        notificationCount: UInt64,
        notificationBytes: UInt64,
        notificationSizeMin: UInt64?,
        notificationSizeMax: UInt64?,
        notificationSizeDistribution: String,
        notificationFrameSizeDistribution: String,
        notificationMaxGapMilliseconds: Double,
        notificationP95GapMilliseconds: Double,
        gapOver20Milliseconds: UInt64,
        gapOver30Milliseconds: UInt64,
        gapOver50Milliseconds: UInt64,
        gapOver100Milliseconds: UInt64,
        decodeRejectCount: UInt64,
        zeroSampleDecodeCount: UInt64,
        audioSyncCount: UInt64,
        decodedAudioDurationMilliseconds: Double,
        measurementElapsedMilliseconds: Double,
        expectedSamples: UInt64,
        deliveredSamples: UInt64,
        deliveryRatio: Double,
        deficitSamples: UInt64,
        deficitMilliseconds: Double
    ) {
        lock.lock()
        guard activeSession != nil else {
            lock.unlock()
            return
        }
        activeSession!.summary.notificationCount = notificationCount
        activeSession!.summary.notificationBytes = notificationBytes
        activeSession!.summary.notificationSizeMin = notificationSizeMin
        activeSession!.summary.notificationSizeMax = notificationSizeMax
        activeSession!.summary.notificationSizeDistribution = notificationSizeDistribution
        activeSession!.summary.notificationFrameSizeDistribution = notificationFrameSizeDistribution
        activeSession!.summary.notificationMaxGapMilliseconds = notificationMaxGapMilliseconds
        activeSession!.summary.notificationP95GapMilliseconds = notificationP95GapMilliseconds
        activeSession!.summary.notificationGapOver20Milliseconds = gapOver20Milliseconds
        activeSession!.summary.notificationGapOver30Milliseconds = gapOver30Milliseconds
        activeSession!.summary.notificationGapOver50Milliseconds = gapOver50Milliseconds
        activeSession!.summary.notificationGapOver100Milliseconds = gapOver100Milliseconds
        activeSession!.summary.decodeRejectCount = decodeRejectCount
        activeSession!.summary.zeroSampleDecodeCount = zeroSampleDecodeCount
        activeSession!.summary.decodeGapCount = decodeRejectCount &+ zeroSampleDecodeCount
        activeSession!.summary.audioSyncCount = audioSyncCount
        activeSession!.summary.decodedAudioDurationMilliseconds = decodedAudioDurationMilliseconds
        activeSession!.summary.measurementElapsedMilliseconds = measurementElapsedMilliseconds
        activeSession!.summary.expectedSamples = expectedSamples
        activeSession!.summary.deliveredSamples = deliveredSamples
        activeSession!.summary.deliveryRatio = deliveryRatio
        activeSession!.summary.deficitSamples = deficitSamples
        activeSession!.summary.deficitMilliseconds = deficitMilliseconds
        lock.unlock()
    }

    func observeDecode(
        frameCount: UInt64,
        sampleCount: UInt64,
        timestampNanoseconds: UInt64? = nil
    ) {
        lock.lock()
        activeSession?.summary.recordDecode(frameCount: frameCount, sampleCount: sampleCount)
        if let timestampNanoseconds {
            let streamIdentity = activeSession?.summary.audioStreamID ?? 0
            activeSession?.trace.append(
                LongTermObservationPoint(
                    timestampNanoseconds: timestampNanoseconds,
                    kind: .decodeComplete,
                    requestedFrames: 0,
                    filledFrames: 0,
                    unfilledFrames: 0,
                    queueDepthFrames: 0,
                    byteOrSampleCount: sampleCount,
                    marker: .unclassified,
                    streamIdentity: streamIdentity
                )
            )
            activeSession?.trace.synchronizeIncidentWithCoordinator()
        }
        lock.unlock()
    }

    func observeTracePoint(_ point: LongTermObservationPoint) {
        lock.lock()
        activeSession?.trace.append(point)
        activeSession?.trace.synchronizeIncidentWithCoordinator()
        lock.unlock()
    }

    func markMaterialAnomaly(
        trigger: LongTermIncidentTriggerKind = .manual
    ) {
        lock.lock()
        incidentCoordinator.trigger(
            producer: .service,
            kind: trigger,
            timestampNanoseconds: P1A4MonotonicClock.nowNanoseconds()
        )
        activeSession?.trace.synchronizeIncidentWithCoordinator()
        lock.unlock()
    }

    func observeSupply(submittedFrames: UInt64) {
        lock.lock()
        activeSession?.summary.recordSupply(submittedFrames: submittedFrames)
        lock.unlock()
    }

    func observePlayout(
        expectedFrames: UInt64,
        deliveredFrames: UInt64,
        marker: LongTermObservationSemanticMarker
    ) {
        lock.lock()
        activeSession?.summary.recordPlayout(
            expectedFrames: expectedFrames,
            deliveredFrames: deliveredFrames,
            marker: marker
        )
        lock.unlock()
    }

    func observeAudioPipe(_ snapshot: AudioPipeDiagnosticsSnapshot) {
        lock.lock()
        guard activeSession != nil else {
            lock.unlock()
            return
        }
        activeSession!.summary.submittedFrames = UInt64(max(0, snapshot.submittedRemoteFrames))
        activeSession!.summary.renderedFrames = UInt64(max(0, snapshot.renderedRemoteFrames))
        activeSession!.summary.queueStarvationFrames = UInt64(max(0, snapshot.renderUnfilledFrames))
        activeSession!.summary.queueStarvationCount = UInt64(max(0, snapshot.underrunCallbackCount))
        activeSession!.summary.activeRequestedFrames = UInt64(max(0, snapshot.renderRequestedFrames))
        activeSession!.summary.activeFilledFrames = UInt64(max(0, snapshot.renderFilledFrames))
        activeSession!.summary.activeUnfilledFrames = UInt64(max(0, snapshot.renderUnfilledFrames))
        activeSession!.summary.activeUnderrunCallbackCount = UInt64(max(0, snapshot.underrunCallbackCount))
        activeSession!.summary.activeUnderrunFrames = UInt64(max(0, snapshot.renderUnfilledFrames))
        activeSession!.summary.tailRenderedFrames = UInt64(max(0, snapshot.tailRenderedFrames))
        activeSession!.summary.tailEmptyCallbackCount = UInt64(max(0, snapshot.tailEmptyCallbackCount))
        activeSession!.summary.queueDepthMinFrames = UInt64(max(0, snapshot.minQueueDepthFrames))
        activeSession!.summary.queueDepthMaxFrames = UInt64(max(0, snapshot.maxQueueDepthFrames))
        activeSession!.summary.queueDepthEndFrames = UInt64(max(0, snapshot.currentQueueDepthFrames))
        activeSession!.summary.overflowDroppedFrames = UInt64(max(0, snapshot.overflowDroppedFrames))
        activeSession!.summary.activeExpectedFrames = UInt64(max(0, snapshot.renderRequestedFrames))
        activeSession!.summary.activeDeliveredFrames = UInt64(max(0, snapshot.renderFilledFrames))
        activeSession!.summary.tailExpectedFrames = UInt64(max(0, snapshot.tailRenderedFrames))
        activeSession!.summary.tailDeliveredFrames = UInt64(max(0, snapshot.tailRenderedFrames))
        activeSession!.summary.expectedFrames =
            activeSession!.summary.activeExpectedFrames + activeSession!.summary.tailExpectedFrames
        activeSession!.summary.deliveredFrames =
            activeSession!.summary.activeDeliveredFrames + activeSession!.summary.tailDeliveredFrames
        lock.unlock()
    }

    func observeLongTermAudioSnapshot(_ snapshot: LongTermAudioObservationSnapshot) {
        lock.lock()
        guard activeSession != nil else {
            lock.unlock()
            return
        }
        activeSession!.detachedTraceSnapshot = snapshot.trace
        activeSession!.summary.mainQueueLag = snapshot.mainQueueLag
        lock.unlock()
    }

    @discardableResult
    func end(sessionID: UUID) -> LongTermVoiceSessionSummary? {
        lock.lock()
        guard var activeSession,
              activeSession.summary.sessionID == sessionID.uuidString else {
            lock.unlock()
            return nil
        }
        self.finalizedSession = FinalizedSession(
            sessionID: activeSession.summary.sessionID,
            captureID: activeSession.summary.captureID
        )
        self.activeSession = nil
        activeSession.summary.runtimeIdentity = runtimeIdentity
        activeSession.summary.lifecycleInconsistencyCount =
            activeSession.summary.calculatedLifecycleInconsistencyCount()
        activeSession.summary.authorityDroppedEventCount = authority.droppedEventCount
        activeSession.summary.authorityWriteFailureCount = authority.writeFailureCount
        activeSession.trace.synchronizeIncidentWithCoordinator()
        let serviceTraceSnapshot = activeSession.trace.snapshot()
        let traceSnapshot = activeSession.detachedTraceSnapshot.map {
            serviceTraceSnapshot.merged(with: $0)
        } ?? serviceTraceSnapshot
        activeSession.summary.traceDroppedObservationCount =
            traceSnapshot.droppedObservationCount
        activeSession.summary.traceOverwrittenObservationCount =
            traceSnapshot.overwrittenObservationCount
        activeSession.summary.underrunEpisodes = DiagnosticUnderrunEpisodeBuilder.build(traceSnapshot.all)
        if let attemptID = VoiceAttemptDiagnostics.shared.attemptID(for: sessionID.uuidString) {
            activeSession.summary.voiceAttemptID = attemptID
        }
        if let anchor = traceSnapshot.incidentAnchor {
            activeSession.summary.incidentIdentity = anchor.identity
            activeSession.summary.incidentAnchorTimestampNanoseconds = anchor.timestampNanoseconds
            activeSession.summary.incidentTriggerSource = anchor.producer.diagnosticName
            activeSession.summary.incidentTrigger = anchor.trigger.diagnosticName
        }
        activeSession.summary.anomalyFlags = thresholds.classify(
            summary: activeSession.summary,
            trace: traceSnapshot
        )
        var summary = activeSession.summary
        if !summary.anomalyFlags.isEmpty {
            summary.tracePersisted = true
        }
        incidentCoordinator.endCapture()
        lock.unlock()

        guard let input = try? DiagnosticEventInput(
            eventType: "voice.session.summary",
            subsystem: "voice.session",
            category: "summary",
            severity: .info,
            sourceComponent: "long_term_observability",
            sessionID: sessionID.uuidString,
            payload: ["summary": summary.toDiagnosticJSONValue()]
        ) else { return summary }
        authority.emit(input)
        DiagnosticHardeningSessionEmitter.emit(
            summary: summary,
            trace: traceSnapshot,
            authority: authority
        )
        guard !summary.anomalyFlags.isEmpty else { return summary }

        let observations = traceSnapshot.incident.isEmpty
            ? traceSnapshot.all
            : traceSnapshot.incident
        let chunkSize = 128
        let chunkCount = max(1, (observations.count + chunkSize - 1) / chunkSize)
        for chunkIndex in 0..<chunkCount {
            let start = chunkIndex * chunkSize
            let end = min(start + chunkSize, observations.count)
            let chunk = Array(observations[start..<end])
            guard let traceInput = try? DiagnosticEventInput(
                eventType: "voice.session.trace",
                subsystem: "voice.session",
                category: "trace",
                severity: .warning,
                sourceComponent: "long_term_observability",
                sessionID: sessionID.uuidString,
                incidentID: summary.incidentIdentity.map(String.init),
                payload: [
                    "capture_id": .string(summary.captureID),
                    "chunk_index": .unsignedInteger(UInt64(chunkIndex)),
                    "chunk_count": .unsignedInteger(UInt64(chunkCount)),
                    "observation_schema_version": .unsignedInteger(LongTermVoiceSessionSummary.schemaVersion),
                    "observations": .array(chunk.map { $0.toDiagnosticJSONValue() }),
                    "dropped_observations": .unsignedInteger(summary.traceDroppedObservationCount),
                ]
            ) else { continue }
            authority.emit(traceInput)
        }
        return summary
    }

    private func emitLifecycleFollowup(
        event: String,
        timestampNanoseconds: UInt64,
        sessionID: UUID,
        captureID: String
    ) {
        guard let input = try? DiagnosticEventInput(
            eventType: "voice.session.lifecycle_followup",
            subsystem: "voice.session",
            category: "lifecycle",
            severity: .info,
            sourceComponent: "long_term_observability",
            sessionID: sessionID.uuidString,
            correlationID: captureID,
            payload: [
                "event": .string(event),
                "timestamp_nanoseconds": .unsignedInteger(timestampNanoseconds),
            ]
        ) else { return }
        authority.emit(input)
    }

    private func makeSummary(sessionID: String, captureID: String) -> LongTermVoiceSessionSummary {
        var summary = LongTermVoiceSessionSummary(sessionID: sessionID, captureID: captureID)
        summary.runtimeIdentity = runtimeIdentity
        return summary
    }
}
