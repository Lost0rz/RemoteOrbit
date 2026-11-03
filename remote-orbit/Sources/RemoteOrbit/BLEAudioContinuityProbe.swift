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

    func logLine(streamID: UInt64?, sessionID: String) -> String {
        let streamText = streamID.map(String.init) ?? "NA"
        return String(
            format: "[AUDIO-PATH] BLE_HANDLER_SUMMARY stream=%@ session_id=%@ samples=%d p50_us=%.1f p95_us=%.1f p99_us=%.1f max_us=%.1f gt5ms=%d gt10ms=%d gt15ms=%d metric=handler_service_time",
            streamText,
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

/// Fixed-storage handler timing for the serial CoreBluetooth audio callback.
/// A packet pays only two monotonic-clock reads plus scalar/bucket updates.
/// Percentiles are approximated to 0.25 ms buckets and computed at session end.
struct BLEAudioHandlerTelemetry {
    static let bucketWidthNanoseconds: UInt64 = 250_000
    static let bucketCount = 128 // 0...32 ms, plus an overflow bucket

    private var buckets = [UInt32](repeating: 0, count: bucketCount)
    private var overflowBucket: UInt32 = 0
    private var sampleCount = 0
    private var maximumNanoseconds: UInt64 = 0
    private var over5Milliseconds = 0
    private var over10Milliseconds = 0
    private var over15Milliseconds = 0

    mutating func reset() {
        for index in buckets.indices {
            buckets[index] = 0
        }
        overflowBucket = 0
        sampleCount = 0
        maximumNanoseconds = 0
        over5Milliseconds = 0
        over10Milliseconds = 0
        over15Milliseconds = 0
    }

    mutating func record(durationNanoseconds: UInt64) {
        sampleCount += 1
        maximumNanoseconds = max(maximumNanoseconds, durationNanoseconds)
        if durationNanoseconds > 5_000_000 { over5Milliseconds += 1 }
        if durationNanoseconds > 10_000_000 { over10Milliseconds += 1 }
        if durationNanoseconds > 15_000_000 { over15Milliseconds += 1 }

        let rawIndex = Int(durationNanoseconds / Self.bucketWidthNanoseconds)
        if rawIndex < buckets.count {
            buckets[rawIndex] &+= 1
        } else {
            overflowBucket &+= 1
        }
    }

    func summary() -> BLEAudioHandlerLatencySummary {
        BLEAudioHandlerLatencySummary(
            sampleCount: sampleCount,
            p50Microseconds: percentileMicroseconds(0.50),
            p95Microseconds: percentileMicroseconds(0.95),
            p99Microseconds: percentileMicroseconds(0.99),
            maxMicroseconds: Double(maximumNanoseconds) / 1_000,
            over5Milliseconds: over5Milliseconds,
            over10Milliseconds: over10Milliseconds,
            over15Milliseconds: over15Milliseconds
        )
    }

    private func percentileMicroseconds(_ quantile: Double) -> Double {
        guard sampleCount > 0 else { return 0 }
        let target = max(1, Int(ceil(Double(sampleCount) * min(1, max(0, quantile)))))
        var cumulative = 0
        for (index, count) in buckets.enumerated() {
            cumulative += Int(count)
            if cumulative >= target {
                let upperBoundNanoseconds = UInt64(index + 1) * Self.bucketWidthNanoseconds
                return Double(upperBoundNanoseconds) / 1_000
            }
        }
        if overflowBucket > 0 {
            return Double(maximumNanoseconds) / 1_000
        }
        return 0
    }
}

struct BLEAudioSupplyWindow: Equatable {
    let index: Int
    let startNanoseconds: UInt64
    let elapsedNanoseconds: UInt64
    let decodedSamples: Int
    let notificationCount: Int
    let maxNotificationGapNanoseconds: UInt64
    let queueDepthStartFrames: Int?
    let queueDepthEndFrames: Int?
    let traceContiguous: Bool

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

    func logLine(streamID: UInt64?, sessionID: String) -> String {
        let streamText = streamID.map(String.init) ?? "NA"
        let sourceRateText = traceContiguous
            ? String(format: "%.1f", effectiveSourceHz)
            : "NA"
        return String(
            format: "[AUDIO-PATH] BLE_SUPPLY_WINDOW stream=%@ session_id=%@ index=%d start_ms=%.1f elapsed_ms=%.1f decoded_samples=%d effective_source_hz=%@ notifications=%d max_notification_gap_ms=%.1f queue_start_frames=%@ queue_end_frames=%@ trace_contiguous=%@",
            streamText,
            sessionID,
            index,
            Double(startNanoseconds) / 1_000_000,
            elapsedMilliseconds,
            decodedSamples,
            sourceRateText,
            notificationCount,
            maxNotificationGapMilliseconds,
            queueDepthStartFrames.map(String.init) ?? "NA",
            queueDepthEndFrames.map(String.init) ?? "NA",
            traceContiguous ? "YES" : "NO"
        )
    }
}

struct BLEAudioContinuityAnalysis: Equatable {
    static let windowNanoseconds: UInt64 = 1_000_000_000

    /// Supplemental retained-trace metric. The exact handler service time is
    /// measured independently by BLEAudioHandlerTelemetry in BLEBridge.
    let ingressToSubmitLatency: BLEAudioHandlerLatencySummary
    let supplyWindows: [BLEAudioSupplyWindow]

    static func analyze(
        points: [LongTermObservationPoint],
        audioStartNanoseconds: UInt64?,
        handlerStartNanoseconds: UInt64? = nil,
        streamID: UInt64?
    ) -> BLEAudioContinuityAnalysis {
        let sorted = points
            .filter { streamID == nil || $0.streamIdentity == 0 || $0.streamIdentity == streamID }
            .sorted {
                if $0.timestampNanoseconds == $1.timestampNanoseconds {
                    if $0.source == $1.source { return $0.sequence < $1.sequence }
                    return $0.source < $1.source
                }
                return $0.timestampNanoseconds < $1.timestampNanoseconds
            }

        let ingressToSubmitLatency = ingressToSubmitLatencySummary(
            points: sorted,
            startNanoseconds: handlerStartNanoseconds
        )
        let supplyWindows = supplyRateWindows(
            points: sorted,
            audioStartNanoseconds: audioStartNanoseconds
        )
        return BLEAudioContinuityAnalysis(
            ingressToSubmitLatency: ingressToSubmitLatency,
            supplyWindows: supplyWindows
        )
    }

    private static func ingressToSubmitLatencySummary(
        points: [LongTermObservationPoint],
        startNanoseconds: UInt64?
    ) -> BLEAudioHandlerLatencySummary {
        func isInActiveRange(_ point: LongTermObservationPoint) -> Bool {
            guard let startNanoseconds else { return true }
            return point.timestampNanoseconds >= startNanoseconds
        }

        let ble = points.filter {
            $0.kind == .bleArrival && isInActiveRange($0)
        }
        let submissions = points.filter {
            $0.kind == .pcmSubmitted && isInActiveRange($0)
        }
        var submissionIndex = 0
        var latencies: [UInt64] = []
        latencies.reserveCapacity(min(ble.count, submissions.count))

        for (index, arrival) in ble.enumerated() {
            while submissionIndex < submissions.count,
                  submissions[submissionIndex].timestampNanoseconds < arrival.timestampNanoseconds {
                submissionIndex += 1
            }
            guard submissionIndex < submissions.count else { break }
            let submission = submissions[submissionIndex]
            let nextArrival = index + 1 < ble.count
                ? ble[index + 1].timestampNanoseconds
                : UInt64.max
            guard submission.timestampNanoseconds < nextArrival else {
                continue
            }
            latencies.append(submission.timestampNanoseconds - arrival.timestampNanoseconds)
            submissionIndex += 1
        }

        latencies.sort()
        let p50 = percentile(latencies, quantile: 0.50)
        let p95 = percentile(latencies, quantile: 0.95)
        let p99 = percentile(latencies, quantile: 0.99)
        let maximum = latencies.last ?? 0
        return BLEAudioHandlerLatencySummary(
            sampleCount: latencies.count,
            p50Microseconds: Double(p50) / 1_000,
            p95Microseconds: Double(p95) / 1_000,
            p99Microseconds: Double(p99) / 1_000,
            maxMicroseconds: Double(maximum) / 1_000,
            over5Milliseconds: latencies.filter { $0 > 5_000_000 }.count,
            over10Milliseconds: latencies.filter { $0 > 10_000_000 }.count,
            over15Milliseconds: latencies.filter { $0 > 15_000_000 }.count
        )
    }

    private static func supplyRateWindows(
        points: [LongTermObservationPoint],
        audioStartNanoseconds: UInt64?
    ) -> [BLEAudioSupplyWindow] {
        let observed = points.filter {
            $0.kind == .bleArrival
                || $0.kind == .decodeComplete
                || $0.kind == .pcmSubmitted
                || $0.kind == .render
                || $0.kind == .queueStarvation
        }
        guard !observed.isEmpty else { return [] }
        let start = audioStartNanoseconds ?? observed[0].timestampNanoseconds
        let end = observed.map(\.timestampNanoseconds).max() ?? start
        guard end >= start else { return [] }
        // Use the complete retained per-source sequence, including lifecycle
        // points. Excluding lifecycle observations would manufacture sequence
        // gaps even when the bounded trace itself is complete.
        let traceGaps = sequenceGapIntervals(points: points)

        let finalIndex = Int((end - start) / windowNanoseconds)
        var windows: [BLEAudioSupplyWindow] = []
        windows.reserveCapacity(finalIndex + 1)
        var previousBLETimestamp: UInt64?

        for index in 0...finalIndex {
            let windowStart = start + UInt64(index) * windowNanoseconds
            let nominalEnd = windowStart + windowNanoseconds
            let windowEnd = min(nominalEnd, end)
            guard windowEnd > windowStart else { continue }
            let isLastWindow = index == finalIndex
            let members = observed.filter {
                $0.timestampNanoseconds >= windowStart
                    && (isLastWindow
                        ? $0.timestampNanoseconds <= windowEnd
                        : $0.timestampNanoseconds < windowEnd)
            }
            guard !members.isEmpty else {
                previousBLETimestamp = nil
                continue
            }

            let blePoints = members.filter { $0.kind == .bleArrival }
            var maxGap: UInt64 = 0
            for point in blePoints {
                if let previousBLETimestamp,
                   point.timestampNanoseconds >= previousBLETimestamp {
                    maxGap = max(maxGap, point.timestampNanoseconds - previousBLETimestamp)
                }
                previousBLETimestamp = point.timestampNanoseconds
            }

            let decodedSamples = members
                .filter { $0.kind == .decodeComplete }
                .reduce(0) { $0 + Int($1.byteOrSampleCount) }
            let queuePoints = members.filter {
                $0.source == "audio_pipe"
                    && ($0.kind == .pcmSubmitted
                        || $0.kind == .render
                        || $0.kind == .queueStarvation)
            }
            let queueStart = queuePoints.first.map { point in
                point.queueDepthBeforeFrames.map { Int($0) }
                    ?? Int(point.queueDepthAfterFrames)
            }
            let queueEnd = queuePoints.last.map { Int($0.queueDepthAfterFrames) }
            let traceContiguous = !traceGaps.contains { gap in
                gap.start < windowEnd && gap.end > windowStart
            }
            windows.append(
                BLEAudioSupplyWindow(
                    index: index,
                    startNanoseconds: windowStart - start,
                    elapsedNanoseconds: windowEnd - windowStart,
                    decodedSamples: decodedSamples,
                    notificationCount: blePoints.count,
                    maxNotificationGapNanoseconds: maxGap,
                    queueDepthStartFrames: queueStart,
                    queueDepthEndFrames: queueEnd,
                    traceContiguous: traceContiguous
                )
            )
        }
        return windows
    }

    private static func sequenceGapIntervals(
        points: [LongTermObservationPoint]
    ) -> [(start: UInt64, end: UInt64)] {
        var gaps: [(start: UInt64, end: UInt64)] = []
        for source in Set(points.map(\.source)) {
            let sourcePoints = points
                .filter { $0.source == source && $0.sequence > 0 }
                .sorted { $0.timestampNanoseconds < $1.timestampNanoseconds }
            guard sourcePoints.count > 1 else { continue }
            for index in 1..<sourcePoints.count {
                let previous = sourcePoints[index - 1]
                let current = sourcePoints[index]
                if current.sequence > previous.sequence + 1 {
                    gaps.append((
                        start: previous.timestampNanoseconds,
                        end: current.timestampNanoseconds
                    ))
                }
            }
        }
        return gaps
    }

    private static func percentile(_ sorted: [UInt64], quantile: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(1, max(0, quantile))
        let rank = max(1, Int(ceil(clamped * Double(sorted.count))))
        return sorted[min(sorted.count - 1, rank - 1)]
    }
}
