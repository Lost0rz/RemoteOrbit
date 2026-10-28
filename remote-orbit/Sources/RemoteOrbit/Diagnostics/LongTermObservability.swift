import Foundation

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

    init(
        timestampNanoseconds: UInt64,
        kind: LongTermObservationKind,
        requestedFrames: UInt64,
        filledFrames: UInt64,
        unfilledFrames: UInt64,
        queueDepthFrames: UInt64,
        byteOrSampleCount: UInt64,
        marker: LongTermObservationSemanticMarker
    ) {
        self.timestampNanoseconds = timestampNanoseconds
        self.kind = kind
        self.requestedFrames = requestedFrames
        self.filledFrames = filledFrames
        self.unfilledFrames = unfilledFrames
        self.queueDepthFrames = queueDepthFrames
        self.byteOrSampleCount = byteOrSampleCount
        self.marker = marker
    }
}

struct FixedCapacityObservationTraceSnapshot: Equatable, Sendable {
    let front: [LongTermObservationPoint]
    let recent: [LongTermObservationPoint]
    let droppedObservationCount: UInt64
    let overwrittenObservationCount: UInt64

    var all: [LongTermObservationPoint] { front + recent }
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

    private(set) var droppedObservationCount: UInt64 = 0
    private(set) var overwrittenObservationCount: UInt64 = 0

    init(frontCapacity: Int, recentCapacity: Int) {
        precondition(frontCapacity >= 0)
        precondition(recentCapacity >= 0)
        precondition(frontCapacity + recentCapacity > 0)
        front = Array(repeating: nil, count: frontCapacity)
        recent = Array(repeating: nil, count: recentCapacity)
    }

    mutating func reset() {
        for index in front.indices { front[index] = nil }
        for index in recent.indices { recent[index] = nil }
        frontCount = 0
        recentCount = 0
        recentWriteIndex = 0
        lastTimestampNanoseconds = nil
        droppedObservationCount = 0
        overwrittenObservationCount = 0
    }

    mutating func append(_ point: LongTermObservationPoint) {
        if let lastTimestampNanoseconds,
           point.timestampNanoseconds < lastTimestampNanoseconds {
            droppedObservationCount &+= 1
            return
        }
        lastTimestampNanoseconds = point.timestampNanoseconds

        if frontCount < front.count {
            front[frontCount] = point
            frontCount += 1
            return
        }

        guard !recent.isEmpty else {
            droppedObservationCount &+= 1
            return
        }

        if recentCount == recent.count {
            overwrittenObservationCount &+= 1
        } else {
            recentCount += 1
        }
        recent[recentWriteIndex] = point
        recentWriteIndex = (recentWriteIndex + 1) % recent.count
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
            droppedObservationCount: droppedObservationCount,
            overwrittenObservationCount: overwrittenObservationCount
        )
    }
}

struct MainQueueLagSummary: Equatable, Sendable {
    let sampleCount: UInt64
    let maxLagNanoseconds: UInt64
    let p95LagNanoseconds: UInt64
    let histogram: [UInt64]

    static let empty = MainQueueLagSummary(
        sampleCount: 0,
        maxLagNanoseconds: 0,
        p95LagNanoseconds: 0,
        histogram: []
    )
}

struct MainQueueLagAccumulator: Sendable {
    private let bucketUpperBoundsNanoseconds: [UInt64]
    private var bucketCounts: [UInt64]
    private let maxSampleCount: Int
    private var samples: [UInt64]
    private var sampleCount = 0
    private var sampleWriteIndex = 0
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
        maxSampleCount: Int = 512
    ) {
        precondition(!bucketUpperBoundsNanoseconds.isEmpty)
        precondition(bucketUpperBoundsNanoseconds == bucketUpperBoundsNanoseconds.sorted())
        precondition(maxSampleCount > 0)
        self.bucketUpperBoundsNanoseconds = bucketUpperBoundsNanoseconds
        bucketCounts = Array(repeating: 0, count: bucketUpperBoundsNanoseconds.count)
        self.maxSampleCount = maxSampleCount
        samples = Array(repeating: 0, count: maxSampleCount)
    }

    mutating func record(lagNanoseconds: UInt64) {
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
    }

    var summary: MainQueueLagSummary {
        guard sampleCount > 0 else {
            return MainQueueLagSummary(
                sampleCount: totalSampleCount,
                maxLagNanoseconds: 0,
                p95LagNanoseconds: 0,
                histogram: bucketCounts
            )
        }
        var values = Array(samples.prefix(sampleCount))
        values.sort()
        let rank = max(0, Int(ceil(Double(sampleCount) * 0.95)) - 1)
        return MainQueueLagSummary(
            sampleCount: totalSampleCount,
            maxLagNanoseconds: values.last ?? 0,
            p95LagNanoseconds: values[rank],
            histogram: bucketCounts
        )
    }
}

final class MainQueueResponsivenessProbe: @unchecked Sendable {
    private let sampleIntervalNanoseconds: UInt64
    private let lock = NSLock()
    private var accumulator = MainQueueLagAccumulator()
    private var timer: DispatchSourceTimer?
    private var running = false
    private var stoppedSummary: MainQueueLagSummary?

    init(sampleIntervalNanoseconds: UInt64) {
        precondition(sampleIntervalNanoseconds > 0)
        self.sampleIntervalNanoseconds = sampleIntervalNanoseconds
    }

    func start() {
        lock.lock()
        guard !running else {
            lock.unlock()
            return
        }
        running = true
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
                self.record(lagNanoseconds: now >= scheduled ? now - scheduled : 0)
            }
        }
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    func record(lagNanoseconds: UInt64) {
        lock.lock()
        accumulator.record(lagNanoseconds: lagNanoseconds)
        lock.unlock()
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
    case mainQueueLag = "main_queue_lag"
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
    var expectedFrames: UInt64 = 0
    var deliveredFrames: UInt64 = 0
    var activeExpectedFrames: UInt64 = 0
    var activeDeliveredFrames: UInt64 = 0
    var tailExpectedFrames: UInt64 = 0
    var tailDeliveredFrames: UInt64 = 0
    var notificationGapCount: UInt64 = 0
    var decodeGapCount: UInt64 = 0
    var queueStarvationCount: UInt64 = 0
    var mainQueueLag: MainQueueLagSummary = .empty
    var traceDroppedObservationCount: UInt64 = 0
    var authorityDroppedEventCount: UInt64 = 0
    var authorityWriteFailureCount: UInt64 = 0
    var anomalyFlags: [LongTermAnomalyFlag] = []
    var tracePersisted = false
    var receiverEvidenceStatus = "unavailable"
    var physicalDownTimestampNanoseconds: UInt64?
    var holdConfirmedTimestampNanoseconds: UInt64?
    var physicalUpTimestampNanoseconds: UInt64?
    var micOpenTimestampNanoseconds: UInt64?
    var audioStartTimestampNanoseconds: UInt64?
    var audioFirstTimestampNanoseconds: UInt64?
    var micCloseTimestampNanoseconds: UInt64?
    var audioStopTimestampNanoseconds: UInt64?
    var drainBeginTimestampNanoseconds: UInt64?
    var drainFinishTimestampNanoseconds: UInt64?
    var outputCompleteTimestampNanoseconds: UInt64?
    var controlPolicy = "unavailable"
    var classification = "unavailable"
    var triggerSource = "unavailable"
    var atvvProtocolVersion = "unavailable"
    var atvvMode = "unavailable"
    var atvvCodec = "unavailable"
    var atvvSampleRate: UInt64?
    var notificationCount: UInt64 = 0
    var notificationBytes: UInt64 = 0
    var decodedFrameCount: UInt64 = 0
    var decodedSampleCount: UInt64 = 0
    var submittedFrames: UInt64 = 0
    var renderedFrames: UInt64 = 0
    var queueStarvationFrames: UInt64 = 0
    var runtimeIdentity: LongTermRuntimeIdentity?

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
        if gapNanoseconds ?? 0 > 20_000_000 { notificationGapCount &+= 1 }
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
            "main_queue_sample_count": .unsignedInteger(mainQueueLag.sampleCount),
            "main_queue_max_lag_nanoseconds": .unsignedInteger(mainQueueLag.maxLagNanoseconds),
            "main_queue_p95_lag_nanoseconds": .unsignedInteger(mainQueueLag.p95LagNanoseconds),
            "trace_dropped_observations": .unsignedInteger(traceDroppedObservationCount),
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
            "audio_first_timestamp_nanoseconds": optionalUInt(audioFirstTimestampNanoseconds),
            "mic_close_timestamp_nanoseconds": optionalUInt(micCloseTimestampNanoseconds),
            "audio_stop_timestamp_nanoseconds": optionalUInt(audioStopTimestampNanoseconds),
            "drain_begin_timestamp_nanoseconds": optionalUInt(drainBeginTimestampNanoseconds),
            "drain_finish_timestamp_nanoseconds": optionalUInt(drainFinishTimestampNanoseconds),
            "output_complete_timestamp_nanoseconds": optionalUInt(outputCompleteTimestampNanoseconds),
            "control_policy": .string(controlPolicy),
            "classification": .string(classification),
            "trigger_source": .string(triggerSource),
            "atvv_protocol_version": .string(atvvProtocolVersion),
            "atvv_mode": .string(atvvMode),
            "atvv_codec": .string(atvvCodec),
            "atvv_sample_rate": optionalUInt(atvvSampleRate),
            "notification_count": .unsignedInteger(notificationCount),
            "notification_bytes": .unsignedInteger(notificationBytes),
            "decoded_frame_count": .unsignedInteger(decodedFrameCount),
            "decoded_sample_count": .unsignedInteger(decodedSampleCount),
            "submitted_frames": .unsignedInteger(submittedFrames),
            "rendered_frames": .unsignedInteger(renderedFrames),
            "queue_starvation_frames": .unsignedInteger(queueStarvationFrames),
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
}

struct LongTermObservabilityThresholds: Equatable, Sendable {
    let maxNotificationGapCount: UInt64
    let maxDecodeGapCount: UInt64
    let maxActiveDeficitFrames: UInt64
    let maxTailDeficitFrames: UInt64
    let maxQueueStarvationCount: UInt64
    let maxMainQueueP95LagNanoseconds: UInt64
    let maxTraceDroppedObservations: UInt64
    let maxAuthorityWriteFailures: UInt64

    init(
        maxNotificationGapCount: UInt64 = 0,
        maxDecodeGapCount: UInt64 = 0,
        maxActiveDeficitFrames: UInt64 = 0,
        maxTailDeficitFrames: UInt64 = 0,
        maxQueueStarvationCount: UInt64 = 0,
        maxMainQueueP95LagNanoseconds: UInt64 = 50_000_000,
        maxTraceDroppedObservations: UInt64 = 0,
        maxAuthorityWriteFailures: UInt64 = 0
    ) {
        self.maxNotificationGapCount = maxNotificationGapCount
        self.maxDecodeGapCount = maxDecodeGapCount
        self.maxActiveDeficitFrames = maxActiveDeficitFrames
        self.maxTailDeficitFrames = maxTailDeficitFrames
        self.maxQueueStarvationCount = maxQueueStarvationCount
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
        if summary.decodeGapCount > maxDecodeGapCount { flags.append(.decodeGap) }
        if summary.activeDeficitFrames > maxActiveDeficitFrames { flags.append(.activeDeficit) }
        if summary.tailDeficitFrames > maxTailDeficitFrames { flags.append(.tailDeficit) }
        if summary.queueStarvationCount > maxQueueStarvationCount { flags.append(.queueStarvation) }
        if summary.mainQueueLag.p95LagNanoseconds > maxMainQueueP95LagNanoseconds {
            flags.append(.mainQueueLag)
        }
        if trace.droppedObservationCount > maxTraceDroppedObservations
            || trace.overwrittenObservationCount > maxTraceDroppedObservations {
            flags.append(.traceOverwritten)
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
        var trace = FixedCapacityObservationTrace(frontCapacity: 64, recentCapacity: 256)
        var detachedTraceSnapshot: FixedCapacityObservationTraceSnapshot? = nil
    }

    private let authority: any DiagnosticAuthority
    private let runtimeIdentity: LongTermRuntimeIdentity
    private let thresholds: LongTermObservabilityThresholds
    private let lock = NSLock()
    private var activeSession: ActiveSession?

    init(
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared,
        runtimeIdentity: LongTermRuntimeIdentity = .current(),
        thresholds: LongTermObservabilityThresholds = LongTermObservabilityThresholds()
    ) {
        self.authority = authority
        self.runtimeIdentity = runtimeIdentity
        self.thresholds = thresholds
    }

    @discardableResult
    func observeTransportStart(
        protocolVersion: String,
        mode: String,
        codec: String,
        sampleRate: UInt64,
        timestampNanoseconds: UInt64
    ) -> UUID {
        lock.lock()
        if activeSession == nil {
            activeSession = ActiveSession(
                summary: makeSummary(sessionID: "unavailable", captureID: UUID().uuidString)
            )
        }
        let captureID = UUID(uuidString: activeSession!.summary.captureID) ?? UUID()
        activeSession!.summary.captureID = captureID.uuidString
        activeSession!.summary.audioStartTimestampNanoseconds = timestampNanoseconds
        activeSession!.summary.atvvProtocolVersion = protocolVersion
        activeSession!.summary.atvvMode = mode
        activeSession!.summary.atvvCodec = codec
        activeSession!.summary.atvvSampleRate = sampleRate
        lock.unlock()
        return captureID
    }

    func begin(sessionID: UUID, timestampNanoseconds: UInt64 = P1A4MonotonicClock.nowNanoseconds()) {
        lock.lock()
        if activeSession == nil {
            activeSession = ActiveSession(
                summary: makeSummary(sessionID: sessionID.uuidString, captureID: UUID().uuidString)
            )
        } else {
            activeSession!.summary.sessionID = sessionID.uuidString
        }
        activeSession!.summary.physicalDownTimestampNanoseconds = timestampNanoseconds
        lock.unlock()
    }

    func observeControl(policy: String, classification: String, triggerSource: String) {
        lock.lock()
        guard activeSession != nil else {
            lock.unlock()
            return
        }
        activeSession!.summary.controlPolicy = policy
        activeSession!.summary.classification = classification
        activeSession!.summary.triggerSource = triggerSource
        lock.unlock()
    }

    func mark(_ event: String, timestampNanoseconds: UInt64, sessionID: UUID? = nil) {
        lock.lock()
        guard activeSession != nil,
              sessionID == nil || activeSession!.summary.sessionID == sessionID!.uuidString else {
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

    func observeNotification(bytes: UInt64, gapNanoseconds: UInt64?) {
        lock.lock()
        activeSession?.summary.recordNotification(bytes: bytes, gapNanoseconds: gapNanoseconds)
        lock.unlock()
    }

    func observeDecode(frameCount: UInt64, sampleCount: UInt64) {
        lock.lock()
        activeSession?.summary.recordDecode(frameCount: frameCount, sampleCount: sampleCount)
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
        activeSession!.summary.recordDelivery(
            expectedFrames: UInt64(max(0, snapshot.renderRequestedFrames)),
            deliveredFrames: UInt64(max(0, snapshot.renderFilledFrames)),
            marker: .active
        )
        activeSession!.summary.tailExpectedFrames = UInt64(max(0, snapshot.tailRenderedFrames))
        activeSession!.summary.tailDeliveredFrames = UInt64(max(0, snapshot.tailRenderedFrames))
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
        self.activeSession = nil
        activeSession.summary.runtimeIdentity = runtimeIdentity
        activeSession.summary.authorityDroppedEventCount = authority.droppedEventCount
        activeSession.summary.authorityWriteFailureCount = authority.writeFailureCount
        let traceSnapshot = activeSession.detachedTraceSnapshot ?? activeSession.trace.snapshot()
        activeSession.summary.traceDroppedObservationCount =
            traceSnapshot.droppedObservationCount + traceSnapshot.overwrittenObservationCount
        activeSession.summary.anomalyFlags = thresholds.classify(
            summary: activeSession.summary,
            trace: traceSnapshot
        )
        let summary = activeSession.summary
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
        return summary
    }

    private func makeSummary(sessionID: String, captureID: String) -> LongTermVoiceSessionSummary {
        var summary = LongTermVoiceSessionSummary(sessionID: sessionID, captureID: captureID)
        summary.runtimeIdentity = runtimeIdentity
        return summary
    }
}
