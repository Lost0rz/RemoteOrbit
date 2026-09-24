import Foundation

struct AudioDeliveryTiming: Equatable {
    let measurementElapsedSeconds: TimeInterval
    let lifecycleElapsedSeconds: TimeInterval
    let audioStopAtMilliseconds: Double?
    let lastAudioAtMilliseconds: Double?
    let stopToLastAudioMilliseconds: Double?
    let drainFinishAtMilliseconds: Double?
    let postLastAudioDrainMilliseconds: Double?

    static func measure(
        streamStartedAt: TimeInterval,
        audioStopReceivedAt: TimeInterval?,
        lastAudioAt: TimeInterval?,
        drainFinishedAt: TimeInterval?
    ) -> AudioDeliveryTiming {
        let measurementEnd = lastAudioAt
            ?? audioStopReceivedAt
            ?? drainFinishedAt
            ?? streamStartedAt
        let lifecycleEnd = drainFinishedAt
            ?? audioStopReceivedAt
            ?? lastAudioAt
            ?? streamStartedAt
        let measurementElapsed = max(0, measurementEnd - streamStartedAt)
        let lifecycleElapsed = max(0, lifecycleEnd - streamStartedAt)
        let stopToLastAudio: Double? = if let audioStopReceivedAt, let lastAudioAt {
            (lastAudioAt - audioStopReceivedAt) * 1_000
        } else {
            nil
        }
        let postLastAudioDrain: Double? = if let lastAudioAt, let drainFinishedAt {
            max(0, drainFinishedAt - lastAudioAt) * 1_000
        } else {
            nil
        }

        return AudioDeliveryTiming(
            measurementElapsedSeconds: measurementElapsed,
            lifecycleElapsedSeconds: lifecycleElapsed,
            audioStopAtMilliseconds: audioStopReceivedAt.map {
                max(0, $0 - streamStartedAt) * 1_000
            },
            lastAudioAtMilliseconds: lastAudioAt.map {
                max(0, $0 - streamStartedAt) * 1_000
            },
            stopToLastAudioMilliseconds: stopToLastAudio,
            drainFinishAtMilliseconds: drainFinishedAt.map {
                max(0, $0 - streamStartedAt) * 1_000
            },
            postLastAudioDrainMilliseconds: postLastAudioDrain
        )
    }
}

struct AudioHealthWindowAccumulator {
    struct Snapshot: Equatable {
        let elapsedMilliseconds: Double
        let decodedSamples: Int
    }

    private(set) var startedAt: TimeInterval
    private(set) var decodedSamples = 0
    private(set) var isOpen = true

    init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    @discardableResult
    mutating func recordDecodedSamples(_ count: Int) -> Bool {
        guard isOpen else { return false }
        decodedSamples += max(0, count)
        return true
    }

    mutating func roll(at now: TimeInterval) -> Snapshot? {
        guard isOpen else { return nil }
        let snapshot = makeSnapshot(at: now)
        startedAt = max(startedAt, now)
        decodedSamples = 0
        return snapshot
    }

    mutating func close(at now: TimeInterval) -> Snapshot? {
        guard isOpen else { return nil }
        let snapshot = makeSnapshot(at: now)
        isOpen = false
        return snapshot
    }

    private func makeSnapshot(at now: TimeInterval) -> Snapshot {
        Snapshot(
            elapsedMilliseconds: max(0, now - startedAt) * 1_000,
            decodedSamples: decodedSamples
        )
    }
}

struct AudioDeliveryAccounting {
    struct Result: Equatable {
        let expectedSamples: Int
        let deliveryRatio: Double
        let deficitSamples: Int
        let deficitMilliseconds: Double
    }

    static func measure(
        decodedSamples: Int,
        sampleRate: Int,
        elapsedSeconds: TimeInterval
    ) -> Result {
        let safeSampleRate = max(0, sampleRate)
        let safeElapsed = max(0, elapsedSeconds)
        let expected = safeSampleRate > 0
            ? max(0, Int((Double(safeSampleRate) * safeElapsed).rounded()))
            : 0
        guard expected > 0 else {
            return Result(
                expectedSamples: expected,
                deliveryRatio: 0,
                deficitSamples: 0,
                deficitMilliseconds: 0
            )
        }

        let safeDecoded = max(0, decodedSamples)
        let deficit = max(0, expected - safeDecoded)
        return Result(
            expectedSamples: expected,
            deliveryRatio: Double(safeDecoded) / Double(expected),
            deficitSamples: deficit,
            deficitMilliseconds: Double(deficit) / Double(safeSampleRate) * 1_000
        )
    }
}

enum AudioPipeRenderState: Equatable {
    case activeRemote
    case tailDrain
    case idle
    case localMicrophone
}

struct AudioPipeRenderAccounting: Equatable {
    let state: AudioPipeRenderState
    let accounted: Bool
    let activeRequestedFrames: Int
    let activeFilledFrames: Int
    let activeUnderrunFrames: Int
    let activeUnderrunCallbacks: Int
    let tailRenderedFrames: Int
    let tailEmptyCallbacks: Int
    let idleRenderCallbacks: Int

    static func measure(
        requestedFrames: Int,
        availableRemoteFrames: Int,
        pendingRemoteFrames: Int,
        remoteActive: Bool,
        remoteWasActive: Bool,
        localMicrophoneActive: Bool = false
    ) -> AudioPipeRenderAccounting {
        let requested = max(0, requestedFrames)
        let pending = max(0, pendingRemoteFrames)
        let available = min(max(0, availableRemoteFrames), pending)
        let filled = min(requested, available)
        let state: AudioPipeRenderState = if remoteActive {
            .activeRemote
        } else if pending > 0 {
            .tailDrain
        } else if localMicrophoneActive {
            .localMicrophone
        } else if remoteWasActive {
            .tailDrain
        } else {
            .idle
        }
        let accounted = remoteActive || pending > 0
        let underrunFrames = state == .activeRemote ? requested - filled : 0

        return AudioPipeRenderAccounting(
            state: state,
            accounted: accounted,
            activeRequestedFrames: state == .activeRemote ? requested : 0,
            activeFilledFrames: state == .activeRemote ? filled : 0,
            activeUnderrunFrames: underrunFrames,
            activeUnderrunCallbacks: underrunFrames > 0 ? 1 : 0,
            tailRenderedFrames: state == .tailDrain ? filled : 0,
            tailEmptyCallbacks: state == .tailDrain && filled == 0 ? 1 : 0,
            idleRenderCallbacks: state == .idle ? 1 : 0
        )
    }
}

enum AudioRemoteQueueAttribution {
    static func remoteQueueDepth(
        totalQueueFrames: Int,
        pendingRemoteFrames: Int
    ) -> Int {
        min(max(0, totalQueueFrames), max(0, pendingRemoteFrames))
    }

    static func remoteDroppedFrames(
        totalDroppedFrames: Int,
        pendingRemoteFrames: Int,
        sourceIsRemote: Bool = true
    ) -> Int {
        guard sourceIsRemote else { return 0 }
        return min(max(0, totalDroppedFrames), max(0, pendingRemoteFrames))
    }

    static func shouldRecordCompaction(
        remoteActive: Bool,
        pendingRemoteFrames: Int
    ) -> Bool {
        remoteActive || pendingRemoteFrames > 0
    }
}

struct AudioRenderFillAccounting {
    struct Result: Equatable {
        let filledFrames: Int
        let unfilledFrames: Int
        let underrun: Bool
    }

    static func measure(requestedFrames: Int, availableFrames: Int) -> Result {
        let requested = max(0, requestedFrames)
        let available = max(0, availableFrames)
        let filled = min(requested, available)
        let unfilled = requested - filled
        return Result(
            filledFrames: filled,
            unfilledFrames: unfilled,
            underrun: unfilled > 0
        )
    }
}

struct AudioQueueOverflowAccounting {
    struct Result: Equatable {
        let availableBefore: Int
        let maximumQueuedFrames: Int
        let droppedFrames: Int
        let droppedMilliseconds: Double
    }

    static func measure(
        availableBefore: Int,
        maximumQueuedFrames: Int,
        sampleRate: Int
    ) -> Result {
        let available = max(0, availableBefore)
        let maximum = max(0, maximumQueuedFrames)
        let dropped = max(0, available - maximum)
        let droppedMilliseconds = sampleRate > 0
            ? Double(dropped) / Double(sampleRate) * 1_000
            : 0
        return Result(
            availableBefore: available,
            maximumQueuedFrames: maximum,
            droppedFrames: dropped,
            droppedMilliseconds: droppedMilliseconds
        )
    }
}

struct ATVVFrameAccumulator {
    let frameSize: Int
    private var buffer = Data()

    init(frameSize: Int) {
        self.frameSize = max(0, frameSize)
    }

    var bufferedByteCount: Int { buffer.count }

    mutating func append(_ data: Data) -> [Data] {
        guard frameSize > 0, !data.isEmpty else { return [] }
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= frameSize {
            frames.append(Data(buffer.prefix(frameSize)))
            buffer.removeFirst(frameSize)
        }
        return frames
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}

struct BLENotificationTelemetry {
    private static let fixedBucketLabels = [
        "<60", "60-119", "120", "121-239", "240", ">240"
    ]
    private static let frameBucketLabels = [
        "<frameSize", "==frameSize", "==2xFrameSize", "other"
    ]
    private static let gapUpperBoundsMs: [Double] = [
        5, 10, 20, 30, 50, 100, 250, 500, 1_000
    ]

    private(set) var notificationCount = 0
    private(set) var notificationBytesTotal = 0
    private(set) var notificationSizeMin = 0
    private(set) var notificationSizeMax = 0
    private(set) var fixedSizeHistogram = [Int](repeating: 0, count: 6)
    private(set) var frameSizeHistogram = [Int](repeating: 0, count: 4)
    private(set) var maxNotificationGapMilliseconds: Double = 0
    private(set) var lastNotificationGapMilliseconds: Double = 0
    private(set) var gapOver20Milliseconds = 0
    private(set) var gapOver30Milliseconds = 0
    private(set) var gapOver50Milliseconds = 0
    private(set) var gapOver100Milliseconds = 0
    private var lastNotificationAt: TimeInterval?
    private var gapHistogram = [Int](repeating: 0, count: 10)

    mutating func reset() {
        self = BLENotificationTelemetry()
    }

    mutating func record(size: Int, frameSize: Int, at timestamp: TimeInterval) {
        let safeSize = max(0, size)
        notificationCount += 1
        notificationBytesTotal += safeSize
        if notificationSizeMin == 0 || safeSize < notificationSizeMin {
            notificationSizeMin = safeSize
        }
        notificationSizeMax = max(notificationSizeMax, safeSize)
        fixedSizeHistogram[fixedBucket(for: safeSize)] += 1
        frameSizeHistogram[frameBucket(for: safeSize, frameSize: frameSize)] += 1

        if let lastNotificationAt {
            let gapMs = max(0, timestamp - lastNotificationAt) * 1_000
            lastNotificationGapMilliseconds = gapMs
            maxNotificationGapMilliseconds = max(maxNotificationGapMilliseconds, gapMs)
            if gapMs > 20 { gapOver20Milliseconds += 1 }
            if gapMs > 30 { gapOver30Milliseconds += 1 }
            if gapMs > 50 { gapOver50Milliseconds += 1 }
            if gapMs > 100 { gapOver100Milliseconds += 1 }
            let bucket = Self.gapUpperBoundsMs.firstIndex(where: { gapMs <= $0 }) ?? Self.gapUpperBoundsMs.count
            gapHistogram[bucket] += 1
        }
        self.lastNotificationAt = timestamp
    }

    var p95NotificationGapMilliseconds: Double {
        let total = gapHistogram.reduce(0, +)
        guard total > 0 else { return 0 }
        let target = Int(ceil(Double(total) * 0.95))
        var cumulative = 0
        for (index, count) in gapHistogram.enumerated() {
            cumulative += count
            if cumulative >= target {
                return index < Self.gapUpperBoundsMs.count
                    ? Self.gapUpperBoundsMs[index]
                    : Self.gapUpperBoundsMs.last ?? 0
            }
        }
        return maxNotificationGapMilliseconds
    }

    var fixedSizeHistogramDescription: String {
        zip(Self.fixedBucketLabels, fixedSizeHistogram)
            .map { "\($0)=\($1)" }
            .joined(separator: ",")
    }

    var frameSizeHistogramDescription: String {
        zip(Self.frameBucketLabels, frameSizeHistogram)
            .map { "\($0)=\($1)" }
            .joined(separator: ",")
    }

    private func fixedBucket(for size: Int) -> Int {
        switch size {
        case ..<60: return 0
        case 60..<120: return 1
        case 120: return 2
        case 121..<240: return 3
        case 240: return 4
        default: return 5
        }
    }

    private func frameBucket(for size: Int, frameSize: Int) -> Int {
        guard frameSize > 0 else { return 3 }
        if size < frameSize { return 0 }
        if size == frameSize { return 1 }
        if size == frameSize * 2 { return 2 }
        return 3
    }
}

struct AudioPipeDiagnosticsSnapshot {
    let renderCallbackCount: Int
    let renderRequestedFrames: Int
    let renderFilledFrames: Int
    let renderUnfilledFrames: Int
    let underrunCallbackCount: Int
    let maxUnderrunFrames: Int
    let totalUnderrunMilliseconds: Double
    let currentQueueDepthFrames: Int
    let audioQueueDepthFrames: Int
    let pendingRemoteFrames: Int
    let submittedRemoteFrames: Int
    let renderedRemoteFrames: Int
    let minQueueDepthFrames: Int
    let maxQueueDepthFrames: Int
    let overflowDroppedFrames: Int
    let overflowDroppedMilliseconds: Double
    let compactionCount: Int
    let tailRenderedFrames: Int
    let tailEmptyCallbackCount: Int
    let idleRenderCallbackCount: Int
    let lastRemoteSubmittedMonotonicNanoseconds: UInt64?
    let lastRemoteRenderedMonotonicNanoseconds: UInt64?

    init(
        renderCallbackCount: Int,
        renderRequestedFrames: Int,
        renderFilledFrames: Int,
        renderUnfilledFrames: Int,
        underrunCallbackCount: Int,
        maxUnderrunFrames: Int,
        currentQueueDepthFrames: Int,
        audioQueueDepthFrames: Int,
        pendingRemoteFrames: Int,
        submittedRemoteFrames: Int,
        renderedRemoteFrames: Int,
        minQueueDepthFrames: Int,
        maxQueueDepthFrames: Int,
        overflowDroppedFrames: Int,
        compactionCount: Int,
        tailRenderedFrames: Int,
        tailEmptyCallbackCount: Int,
        idleRenderCallbackCount: Int,
        sampleRate: Double,
        lastRemoteSubmittedMonotonicNanoseconds: UInt64? = nil,
        lastRemoteRenderedMonotonicNanoseconds: UInt64? = nil
    ) {
        self.renderCallbackCount = renderCallbackCount
        self.renderRequestedFrames = renderRequestedFrames
        self.renderFilledFrames = renderFilledFrames
        self.renderUnfilledFrames = renderUnfilledFrames
        self.underrunCallbackCount = underrunCallbackCount
        self.maxUnderrunFrames = maxUnderrunFrames
        self.totalUnderrunMilliseconds = sampleRate > 0
            ? Double(renderUnfilledFrames) / sampleRate * 1_000
            : 0
        self.currentQueueDepthFrames = max(0, currentQueueDepthFrames)
        self.audioQueueDepthFrames = max(0, audioQueueDepthFrames)
        self.pendingRemoteFrames = max(0, pendingRemoteFrames)
        self.submittedRemoteFrames = max(0, submittedRemoteFrames)
        self.renderedRemoteFrames = max(0, renderedRemoteFrames)
        self.minQueueDepthFrames = max(0, minQueueDepthFrames)
        self.maxQueueDepthFrames = max(0, maxQueueDepthFrames)
        self.overflowDroppedFrames = overflowDroppedFrames
        self.overflowDroppedMilliseconds = sampleRate > 0
            ? Double(overflowDroppedFrames) / sampleRate * 1_000
            : 0
        self.compactionCount = compactionCount
        self.tailRenderedFrames = tailRenderedFrames
        self.tailEmptyCallbackCount = tailEmptyCallbackCount
        self.idleRenderCallbackCount = idleRenderCallbackCount
        self.lastRemoteSubmittedMonotonicNanoseconds =
            lastRemoteSubmittedMonotonicNanoseconds
        self.lastRemoteRenderedMonotonicNanoseconds =
            lastRemoteRenderedMonotonicNanoseconds
    }
}

struct AudioPipeDiagnosticsCounters {
    var renderCallbackCount = 0
    var renderRequestedFrames = 0
    var renderFilledFrames = 0
    var renderUnfilledFrames = 0
    var underrunCallbackCount = 0
    var maxUnderrunFrames = 0
    var submittedRemoteFrames = 0
    var renderedRemoteFrames = 0
    var minQueueDepthFrames: Int?
    var maxQueueDepthFrames = 0
    var overflowDroppedFrames = 0
    var compactionCount = 0
    var tailRenderedFrames = 0
    var tailEmptyCallbackCount = 0
    var idleRenderCallbackCount = 0

    mutating func reset(currentQueueDepthFrames: Int) {
        renderCallbackCount = 0
        renderRequestedFrames = 0
        renderFilledFrames = 0
        renderUnfilledFrames = 0
        underrunCallbackCount = 0
        maxUnderrunFrames = 0
        submittedRemoteFrames = 0
        renderedRemoteFrames = 0
        minQueueDepthFrames = max(0, currentQueueDepthFrames)
        maxQueueDepthFrames = max(0, currentQueueDepthFrames)
        overflowDroppedFrames = 0
        compactionCount = 0
        tailRenderedFrames = 0
        tailEmptyCallbackCount = 0
        idleRenderCallbackCount = 0
    }

    mutating func recordRender(_ accounting: AudioPipeRenderAccounting) {
        switch accounting.state {
        case .activeRemote:
            renderCallbackCount += 1
            renderRequestedFrames += accounting.activeRequestedFrames
            renderFilledFrames += accounting.activeFilledFrames
            renderUnfilledFrames += accounting.activeUnderrunFrames
            if accounting.activeUnderrunCallbacks > 0 {
                underrunCallbackCount += accounting.activeUnderrunCallbacks
                maxUnderrunFrames = max(
                    maxUnderrunFrames,
                    accounting.activeUnderrunFrames
                )
            }
        case .tailDrain:
            tailRenderedFrames += accounting.tailRenderedFrames
            tailEmptyCallbackCount += accounting.tailEmptyCallbacks
        case .idle:
            idleRenderCallbackCount += accounting.idleRenderCallbacks
        case .localMicrophone:
            break
        }
    }

    mutating func recordSubmittedRemoteFrames(_ frames: Int) {
        submittedRemoteFrames += max(0, frames)
    }

    mutating func recordRenderedRemoteFrames(_ frames: Int) {
        renderedRemoteFrames += max(0, frames)
    }

    mutating func recordQueueDepth(_ frames: Int) {
        let depth = max(0, frames)
        minQueueDepthFrames = min(minQueueDepthFrames ?? depth, depth)
        maxQueueDepthFrames = max(maxQueueDepthFrames, depth)
    }

    mutating func recordOverflow(_ frames: Int) {
        overflowDroppedFrames += max(0, frames)
    }

    mutating func recordCompaction() {
        compactionCount += 1
    }

    func snapshot(
        currentQueueDepthFrames: Int,
        audioQueueDepthFrames: Int,
        pendingRemoteFrames: Int,
        sampleRate: Double,
        lastRemoteSubmittedMonotonicNanoseconds: UInt64? = nil,
        lastRemoteRenderedMonotonicNanoseconds: UInt64? = nil
    ) -> AudioPipeDiagnosticsSnapshot {
        AudioPipeDiagnosticsSnapshot(
            renderCallbackCount: renderCallbackCount,
            renderRequestedFrames: renderRequestedFrames,
            renderFilledFrames: renderFilledFrames,
            renderUnfilledFrames: renderUnfilledFrames,
            underrunCallbackCount: underrunCallbackCount,
            maxUnderrunFrames: maxUnderrunFrames,
            currentQueueDepthFrames: currentQueueDepthFrames,
            audioQueueDepthFrames: audioQueueDepthFrames,
            pendingRemoteFrames: pendingRemoteFrames,
            submittedRemoteFrames: submittedRemoteFrames,
            renderedRemoteFrames: renderedRemoteFrames,
            minQueueDepthFrames: minQueueDepthFrames ?? currentQueueDepthFrames,
            maxQueueDepthFrames: maxQueueDepthFrames,
            overflowDroppedFrames: overflowDroppedFrames,
            compactionCount: compactionCount,
            tailRenderedFrames: tailRenderedFrames,
            tailEmptyCallbackCount: tailEmptyCallbackCount,
            idleRenderCallbackCount: idleRenderCallbackCount,
            sampleRate: sampleRate,
            lastRemoteSubmittedMonotonicNanoseconds:
                lastRemoteSubmittedMonotonicNanoseconds,
            lastRemoteRenderedMonotonicNanoseconds:
                lastRemoteRenderedMonotonicNanoseconds
        )
    }
}
