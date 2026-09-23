import Foundation

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
    let minQueueDepthFrames: Int
    let maxQueueDepthFrames: Int
    let overflowDroppedFrames: Int
    let overflowDroppedMilliseconds: Double
    let compactionCount: Int

    init(
        renderCallbackCount: Int,
        renderRequestedFrames: Int,
        renderFilledFrames: Int,
        renderUnfilledFrames: Int,
        underrunCallbackCount: Int,
        maxUnderrunFrames: Int,
        currentQueueDepthFrames: Int,
        minQueueDepthFrames: Int,
        maxQueueDepthFrames: Int,
        overflowDroppedFrames: Int,
        compactionCount: Int,
        sampleRate: Double
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
        self.minQueueDepthFrames = max(0, minQueueDepthFrames)
        self.maxQueueDepthFrames = max(0, maxQueueDepthFrames)
        self.overflowDroppedFrames = overflowDroppedFrames
        self.overflowDroppedMilliseconds = sampleRate > 0
            ? Double(overflowDroppedFrames) / sampleRate * 1_000
            : 0
        self.compactionCount = compactionCount
    }
}

struct AudioPipeDiagnosticsCounters {
    var renderCallbackCount = 0
    var renderRequestedFrames = 0
    var renderFilledFrames = 0
    var renderUnfilledFrames = 0
    var underrunCallbackCount = 0
    var maxUnderrunFrames = 0
    var minQueueDepthFrames: Int?
    var maxQueueDepthFrames = 0
    var overflowDroppedFrames = 0
    var compactionCount = 0

    mutating func reset(currentQueueDepthFrames: Int) {
        renderCallbackCount = 0
        renderRequestedFrames = 0
        renderFilledFrames = 0
        renderUnfilledFrames = 0
        underrunCallbackCount = 0
        maxUnderrunFrames = 0
        minQueueDepthFrames = max(0, currentQueueDepthFrames)
        maxQueueDepthFrames = max(0, currentQueueDepthFrames)
        overflowDroppedFrames = 0
        compactionCount = 0
    }

    mutating func recordRender(
        requestedFrames: Int,
        filledFrames: Int,
        unfilledFrames: Int
    ) {
        renderCallbackCount += 1
        renderRequestedFrames += max(0, requestedFrames)
        renderFilledFrames += max(0, filledFrames)
        renderUnfilledFrames += max(0, unfilledFrames)
        if unfilledFrames > 0 {
            underrunCallbackCount += 1
            maxUnderrunFrames = max(maxUnderrunFrames, unfilledFrames)
        }
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

    func snapshot(currentQueueDepthFrames: Int, sampleRate: Double) -> AudioPipeDiagnosticsSnapshot {
        AudioPipeDiagnosticsSnapshot(
            renderCallbackCount: renderCallbackCount,
            renderRequestedFrames: renderRequestedFrames,
            renderFilledFrames: renderFilledFrames,
            renderUnfilledFrames: renderUnfilledFrames,
            underrunCallbackCount: underrunCallbackCount,
            maxUnderrunFrames: maxUnderrunFrames,
            currentQueueDepthFrames: currentQueueDepthFrames,
            minQueueDepthFrames: minQueueDepthFrames ?? currentQueueDepthFrames,
            maxQueueDepthFrames: maxQueueDepthFrames,
            overflowDroppedFrames: overflowDroppedFrames,
            compactionCount: compactionCount,
            sampleRate: sampleRate
        )
    }
}
