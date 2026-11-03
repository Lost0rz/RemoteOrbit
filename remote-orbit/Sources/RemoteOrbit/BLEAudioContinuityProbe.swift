import Foundation

struct BLEAudioHandlerLatencySummary: Equatable {
    let sampleCount: Int
    let p50Microseconds: Double
    let p95Microseconds: Double
    let p99Microseconds: Double
    let maxMicroseconds: Double
    let over5Milliseconds: Int
    let over10Milliseconds: Int
    let over15Milliseconds: Int

    func logLine(streamID: UInt8, sessionID: String) -> String {
        String(
            format: "[AUDIO-PATH] BLE_HANDLER_SUMMARY stream=%d session_id=%@ samples=%d p50_us=%.1f p95_us=%.1f p99_us=%.1f max_us=%.1f gt5ms=%d gt10ms=%d gt15ms=%d",
            streamID,
            sessionID,
            sampleCount,
            p50Microseconds,
            p95Microseconds,
            p99Microseconds,
            maxMicroseconds,
            over5Milliseconds,
            over10Milliseconds,
            over15Milliseconds
        )
    }
}

struct BLEAudioSupplyWindow: Equatable {
    let index: Int
    let elapsedNanoseconds: UInt64
    let decodedSamples: Int
    let notificationCount: Int
    let maxNotificationGapNanoseconds: UInt64
    let queueDepthStartFrames: Int
    let queueDepthEndFrames: Int

    var effectiveSourceHz: Double {
        guard elapsedNanoseconds > 0 else { return 0 }
        return Double(decodedSamples) * 1_000_000_000 / Double(elapsedNanoseconds)
    }

    var elapsedMilliseconds: Double {
        Double(elapsedNanoseconds) / 1_000_000
    }

    var maxNotificationGapMilliseconds: Double {
        Double(maxNotificationGapNanoseconds) / 1_000_000
    }

    func logLine(streamID: UInt8, sessionID: String) -> String {
        String(
            format: "[AUDIO-PATH] BLE_SUPPLY_WINDOW stream=%d session_id=%@ index=%d elapsed_ms=%.1f decoded_samples=%d effective_source_hz=%.1f notifications=%d max_notification_gap_ms=%.1f queue_start_frames=%d queue_end_frames=%d",
            streamID,
            sessionID,
            index,
            elapsedMilliseconds,
            decodedSamples,
            effectiveSourceHz,
            notificationCount,
            maxNotificationGapMilliseconds,
            queueDepthStartFrames,
            queueDepthEndFrames
        )
    }
}

/// Bounded observation-only accounting for Task 049. The production BLE queue
/// owns the mutable value, so no additional lock is required. Handler latency
/// is measured before the probe emits its own once-per-window log line.
struct BLEAudioContinuityProbe {
    static let targetWindowNanoseconds: UInt64 = 1_000_000_000

    private var handlerDurationsNanoseconds: [UInt64] = []
    private var windowIndex = 0
    private var windowStartNanoseconds: UInt64?
    private var lastNotificationNanoseconds: UInt64?
    private var previousNotificationNanoseconds: UInt64?
    private var windowDecodedSamples = 0
    private var windowNotificationCount = 0
    private var windowMaxNotificationGapNanoseconds: UInt64 = 0
    private var windowStartQueueDepthFrames = 0

    mutating func reset(
        startTimestampNanoseconds: UInt64,
        initialQueueDepthFrames: Int
    ) {
        handlerDurationsNanoseconds.removeAll(keepingCapacity: true)
        handlerDurationsNanoseconds.reserveCapacity(16_384)
        windowIndex = 0
        windowStartNanoseconds = startTimestampNanoseconds
        lastNotificationNanoseconds = nil
        previousNotificationNanoseconds = nil
        windowDecodedSamples = 0
        windowNotificationCount = 0
        windowMaxNotificationGapNanoseconds = 0
        windowStartQueueDepthFrames = max(0, initialQueueDepthFrames)
    }

    mutating func recordNotification(timestampNanoseconds: UInt64) {
        if let previousNotificationNanoseconds,
           timestampNanoseconds >= previousNotificationNanoseconds {
            windowMaxNotificationGapNanoseconds = max(
                windowMaxNotificationGapNanoseconds,
                timestampNanoseconds - previousNotificationNanoseconds
            )
        }
        previousNotificationNanoseconds = timestampNanoseconds
        lastNotificationNanoseconds = timestampNanoseconds
        windowNotificationCount += 1
    }

    mutating func recordDecodedSamples(_ sampleCount: Int) {
        windowDecodedSamples += max(0, sampleCount)
    }

    mutating func recordHandlerDuration(
        startTimestampNanoseconds: UInt64,
        endTimestampNanoseconds: UInt64
    ) {
        guard endTimestampNanoseconds >= startTimestampNanoseconds else { return }
        handlerDurationsNanoseconds.append(
            endTimestampNanoseconds - startTimestampNanoseconds
        )
    }

    mutating func closeWindowIfNeeded(
        at timestampNanoseconds: UInt64,
        queueDepthFrames: Int
    ) -> BLEAudioSupplyWindow? {
        guard let start = windowStartNanoseconds,
              timestampNanoseconds >= start,
              timestampNanoseconds - start >= Self.targetWindowNanoseconds,
              windowNotificationCount > 0 else {
            return nil
        }
        return closeWindow(queueDepthFrames: queueDepthFrames)
    }

    mutating func finish(queueDepthFrames: Int) -> BLEAudioSupplyWindow? {
        guard windowNotificationCount > 0 else { return nil }
        return closeWindow(queueDepthFrames: queueDepthFrames)
    }

    func handlerSummary() -> BLEAudioHandlerLatencySummary {
        let sorted = handlerDurationsNanoseconds.sorted()
        let sampleCount = sorted.count
        let p50 = percentile(sorted, quantile: 0.50)
        let p95 = percentile(sorted, quantile: 0.95)
        let p99 = percentile(sorted, quantile: 0.99)
        let maxValue = sorted.last ?? 0
        return BLEAudioHandlerLatencySummary(
            sampleCount: sampleCount,
            p50Microseconds: Double(p50) / 1_000,
            p95Microseconds: Double(p95) / 1_000,
            p99Microseconds: Double(p99) / 1_000,
            maxMicroseconds: Double(maxValue) / 1_000,
            over5Milliseconds: sorted.filter { $0 > 5_000_000 }.count,
            over10Milliseconds: sorted.filter { $0 > 10_000_000 }.count,
            over15Milliseconds: sorted.filter { $0 > 15_000_000 }.count
        )
    }

    private mutating func closeWindow(
        queueDepthFrames: Int
    ) -> BLEAudioSupplyWindow? {
        guard let start = windowStartNanoseconds,
              let end = lastNotificationNanoseconds,
              end > start else {
            return nil
        }
        let safeEndDepth = max(0, queueDepthFrames)
        let window = BLEAudioSupplyWindow(
            index: windowIndex,
            elapsedNanoseconds: end - start,
            decodedSamples: windowDecodedSamples,
            notificationCount: windowNotificationCount,
            maxNotificationGapNanoseconds: windowMaxNotificationGapNanoseconds,
            queueDepthStartFrames: windowStartQueueDepthFrames,
            queueDepthEndFrames: safeEndDepth
        )
        windowIndex += 1
        windowStartNanoseconds = end
        windowDecodedSamples = 0
        windowNotificationCount = 0
        windowMaxNotificationGapNanoseconds = 0
        windowStartQueueDepthFrames = safeEndDepth
        return window
    }

    private func percentile(_ sorted: [UInt64], quantile: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(1, max(0, quantile))
        let rank = max(1, Int(ceil(clamped * Double(sorted.count))))
        return sorted[min(sorted.count - 1, rank - 1)]
    }
}
