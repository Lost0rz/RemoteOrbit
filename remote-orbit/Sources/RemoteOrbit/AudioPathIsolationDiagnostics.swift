import Foundation

struct MainQueueStallEvent: Equatable {
    let sessionID: String
    let elapsedMilliseconds: Double
    let expectedFireMilliseconds: Double
    let actualFireMilliseconds: Double
    let lagMilliseconds: Double
}

struct MainQueueStallSummary: Equatable {
    let stallCount: Int
    let maxLagMilliseconds: Double
    let p95LagMilliseconds: Double
}

struct MainQueueStallMonitor {
    let interval: TimeInterval
    let threshold: TimeInterval

    private(set) var sessionID = "NA"
    private(set) var startedAt: TimeInterval?
    private var nextExpectedUptime: TimeInterval?
    private var lagSamples: [Double] = []

    init(interval: TimeInterval, threshold: TimeInterval) {
        self.interval = max(0.001, interval)
        self.threshold = max(0, threshold)
    }

    var isActive: Bool {
        startedAt != nil && nextExpectedUptime != nil
    }

    var summary: MainQueueStallSummary {
        MainQueueStallSummary(
            stallCount: lagSamples.count,
            maxLagMilliseconds: lagSamples.max() ?? 0,
            p95LagMilliseconds: Self.percentile95(lagSamples)
        )
    }

    mutating func start(sessionID: String, at uptime: TimeInterval) {
        self.sessionID = sessionID
        startedAt = uptime
        nextExpectedUptime = uptime + interval
        lagSamples.removeAll(keepingCapacity: true)
    }

    mutating func record(actualUptime: TimeInterval) -> MainQueueStallEvent? {
        guard let startedAt, let expected = nextExpectedUptime else { return nil }
        let actual = max(expected, actualUptime)
        let lag = max(0, actualUptime - expected)
        nextExpectedUptime = actual + interval
        guard lag > threshold else { return nil }

        let event = MainQueueStallEvent(
            sessionID: sessionID,
            elapsedMilliseconds: max(0, actualUptime - startedAt) * 1_000,
            expectedFireMilliseconds: max(0, expected - startedAt) * 1_000,
            actualFireMilliseconds: max(0, actualUptime - startedAt) * 1_000,
            lagMilliseconds: lag * 1_000
        )
        lagSamples.append(event.lagMilliseconds)
        return event
    }

    mutating func stop() {
        startedAt = nil
        nextExpectedUptime = nil
    }

    private static func percentile95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(
            sorted.count - 1,
            max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        )
        return sorted[index]
    }
}

enum AudioPathProcessingStage: String, CaseIterable, Hashable {
    case handleAudio = "handle_audio"
    case decodeAudioFrames = "decode_audio_frames"
    case processDecodedFrame = "process_decoded_frame"
    case audioPipeFeed = "audio_pipe_feed"
}

struct AudioPathTimingSummary: Equatable {
    let count: Int
    let averageMilliseconds: Double
    let p95Milliseconds: Double
    let maxMilliseconds: Double
}

struct AudioPathProcessingTimingAccumulator {
    private var samples: [AudioPathProcessingStage: [Double]] =
        Dictionary(uniqueKeysWithValues: AudioPathProcessingStage.allCases.map { ($0, []) })

    mutating func record(
        stage: AudioPathProcessingStage,
        milliseconds: Double
    ) {
        samples[stage, default: []].append(max(0, milliseconds))
    }

    func summary(for stage: AudioPathProcessingStage) -> AudioPathTimingSummary {
        let values = samples[stage] ?? []
        guard !values.isEmpty else {
            return AudioPathTimingSummary(
                count: 0,
                averageMilliseconds: 0,
                p95Milliseconds: 0,
                maxMilliseconds: 0
            )
        }
        let sorted = values.sorted()
        let p95Index = min(
            sorted.count - 1,
            max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        )
        return AudioPathTimingSummary(
            count: values.count,
            averageMilliseconds: values.reduce(0, +) / Double(values.count),
            p95Milliseconds: sorted[p95Index],
            maxMilliseconds: sorted.last ?? 0
        )
    }

    mutating func reset() {
        samples = Dictionary(
            uniqueKeysWithValues: AudioPathProcessingStage.allCases.map { ($0, []) }
        )
    }
}

struct AudioPathIsolationWindowSnapshot: Equatable {
    let sessionID: String
    let windowStartMilliseconds: Double
    let windowEndMilliseconds: Double
    let notificationCount: Int
    let notificationBytes: Int
    let completeFramesFromBytes: Int
    let decodedFrames: Int
    let decodedSamples: Int
    let frameAccumulatorBufferedBytes: Int
    let frameAccumulatorMaxBufferedBytes: Int
    let maxCallbackGapMilliseconds: Double
    let callbacksWithGapOver20: Int
    let callbacksWithGapOver50: Int
    let callbacksWithGapOver100: Int
    let callbacksWithGapOver250: Int
    let callbacksWithGapOver500: Int
    let burstCallbacksUnder2Milliseconds: Int
    let burstBytesUnder2Milliseconds: Int
    let decodeRejects: Int
    let maxHandleAudioMilliseconds: Double
    let maxDecodeAudioFramesMilliseconds: Double
    let maxProcessDecodedFrameMilliseconds: Double
    let maxAudioPipeFeedMilliseconds: Double

    func byteToFrameRatio(frameSize: Int) -> Double {
        guard frameSize > 0, notificationBytes > 0 else { return 0 }
        let theoreticalFrames = Double(notificationBytes) / Double(frameSize)
        return Double(completeFramesFromBytes) / theoreticalFrames
    }

    var frameToDecodeRatio: Double {
        guard completeFramesFromBytes > 0 else { return 0 }
        return Double(decodedFrames) / Double(completeFramesFromBytes)
    }

    var callbackBurstAfterGap: Bool {
        callbacksWithGapOver500 > 0 && burstCallbacksUnder2Milliseconds >= 2
    }
}

struct AudioPathIsolationWindowAccumulator {
    private(set) var sessionID: String
    private(set) var startedAt: TimeInterval
    private var windowStartedAt: TimeInterval
    private(set) var isOpen = true

    private var notificationCount = 0
    private var notificationBytes = 0
    private var completeFramesFromBytes = 0
    private var decodedFrames = 0
    private var decodedSamples = 0
    private var frameAccumulatorBufferedBytes = 0
    private var frameAccumulatorMaxBufferedBytes = 0
    private var maxCallbackGapMilliseconds = 0.0
    private var callbacksWithGapOver20 = 0
    private var callbacksWithGapOver50 = 0
    private var callbacksWithGapOver100 = 0
    private var callbacksWithGapOver250 = 0
    private var callbacksWithGapOver500 = 0
    private var burstCallbacksUnder2Milliseconds = 0
    private var burstBytesUnder2Milliseconds = 0
    private var decodeRejects = 0
    private var processingMaxMilliseconds: [AudioPathProcessingStage: Double] =
        Dictionary(uniqueKeysWithValues: AudioPathProcessingStage.allCases.map { ($0, 0) })

    init(sessionID: String, startedAt: TimeInterval) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.windowStartedAt = startedAt
    }

    mutating func recordNotification(
        size: Int,
        gapMilliseconds: Double?,
        completeFramesFromBytes: Int,
        frameAccumulatorBufferedBytes: Int,
        at _: TimeInterval
    ) {
        guard isOpen else { return }
        let safeSize = max(0, size)
        notificationCount += 1
        notificationBytes += safeSize
        self.completeFramesFromBytes += max(0, completeFramesFromBytes)
        self.frameAccumulatorBufferedBytes = max(0, frameAccumulatorBufferedBytes)
        self.frameAccumulatorMaxBufferedBytes = max(
            self.frameAccumulatorMaxBufferedBytes,
            self.frameAccumulatorBufferedBytes
        )

        guard let gapMilliseconds else { return }
        let gap = max(0, gapMilliseconds)
        maxCallbackGapMilliseconds = max(maxCallbackGapMilliseconds, gap)
        if gap > 20 { callbacksWithGapOver20 += 1 }
        if gap > 50 { callbacksWithGapOver50 += 1 }
        if gap > 100 { callbacksWithGapOver100 += 1 }
        if gap > 250 { callbacksWithGapOver250 += 1 }
        if gap > 500 { callbacksWithGapOver500 += 1 }
        if gap < 2 {
            burstCallbacksUnder2Milliseconds += 1
            burstBytesUnder2Milliseconds += safeSize
        }
    }

    mutating func recordDecoded(
        frameCount: Int,
        sampleCount: Int,
        rejected: Bool
    ) {
        guard isOpen else { return }
        if rejected { decodeRejects += 1 }
        decodedFrames += max(0, frameCount)
        decodedSamples += max(0, sampleCount)
    }

    mutating func recordProcessing(
        stage: AudioPathProcessingStage,
        milliseconds: Double
    ) {
        guard isOpen else { return }
        processingMaxMilliseconds[stage] = max(
            processingMaxMilliseconds[stage] ?? 0,
            max(0, milliseconds)
        )
    }

    mutating func roll(at now: TimeInterval) -> AudioPathIsolationWindowSnapshot? {
        guard isOpen else { return nil }
        let snapshot = makeSnapshot(at: now)
        resetWindow(
            startedAt: max(windowStartedAt, now),
            carryingBufferedBytes: frameAccumulatorBufferedBytes
        )
        return snapshot
    }

    mutating func close(at now: TimeInterval) -> AudioPathIsolationWindowSnapshot? {
        guard isOpen else { return nil }
        let snapshot = makeSnapshot(at: now)
        isOpen = false
        return snapshot
    }

    private func makeSnapshot(at now: TimeInterval) -> AudioPathIsolationWindowSnapshot {
        AudioPathIsolationWindowSnapshot(
            sessionID: sessionID,
            windowStartMilliseconds: max(0, windowStartedAt - startedAt) * 1_000,
            windowEndMilliseconds: max(0, now - startedAt) * 1_000,
            notificationCount: notificationCount,
            notificationBytes: notificationBytes,
            completeFramesFromBytes: completeFramesFromBytes,
            decodedFrames: decodedFrames,
            decodedSamples: decodedSamples,
            frameAccumulatorBufferedBytes: frameAccumulatorBufferedBytes,
            frameAccumulatorMaxBufferedBytes: frameAccumulatorMaxBufferedBytes,
            maxCallbackGapMilliseconds: maxCallbackGapMilliseconds,
            callbacksWithGapOver20: callbacksWithGapOver20,
            callbacksWithGapOver50: callbacksWithGapOver50,
            callbacksWithGapOver100: callbacksWithGapOver100,
            callbacksWithGapOver250: callbacksWithGapOver250,
            callbacksWithGapOver500: callbacksWithGapOver500,
            burstCallbacksUnder2Milliseconds: burstCallbacksUnder2Milliseconds,
            burstBytesUnder2Milliseconds: burstBytesUnder2Milliseconds,
            decodeRejects: decodeRejects,
            maxHandleAudioMilliseconds:
                processingMaxMilliseconds[.handleAudio] ?? 0,
            maxDecodeAudioFramesMilliseconds:
                processingMaxMilliseconds[.decodeAudioFrames] ?? 0,
            maxProcessDecodedFrameMilliseconds:
                processingMaxMilliseconds[.processDecodedFrame] ?? 0,
            maxAudioPipeFeedMilliseconds:
                processingMaxMilliseconds[.audioPipeFeed] ?? 0
        )
    }

    private mutating func resetWindow(
        startedAt: TimeInterval,
        carryingBufferedBytes: Int = 0
    ) {
        windowStartedAt = startedAt
        notificationCount = 0
        notificationBytes = 0
        completeFramesFromBytes = 0
        decodedFrames = 0
        decodedSamples = 0
        frameAccumulatorBufferedBytes = max(0, carryingBufferedBytes)
        frameAccumulatorMaxBufferedBytes = frameAccumulatorBufferedBytes
        maxCallbackGapMilliseconds = 0
        callbacksWithGapOver20 = 0
        callbacksWithGapOver50 = 0
        callbacksWithGapOver100 = 0
        callbacksWithGapOver250 = 0
        callbacksWithGapOver500 = 0
        burstCallbacksUnder2Milliseconds = 0
        burstBytesUnder2Milliseconds = 0
        decodeRejects = 0
        processingMaxMilliseconds = Dictionary(
            uniqueKeysWithValues: AudioPathProcessingStage.allCases.map { ($0, 0) }
        )
    }
}
