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
            format: "[AUDIO-PATH] BLE_HANDLER_SUMMARY stream=%@ session_id=%@ samples=%d p50_us=%.1f p95_us=%.1f p99_us=%.1f max_us=%.1f gt5ms=%d gt10ms=%d gt15ms=%d metric=ble_arrival_to_pcm_submit",
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

struct BLEAudioSupplyWindow: Equatable {
    let index: Int
    let startNanoseconds: UInt64
    let elapsedNanoseconds: UInt64
    let decodedSamples: Int
    let notificationCount: Int
    let maxNotificationGapNanoseconds: UInt64
    let queueDepthStartFrames: Int?
    let queueDepthEndFrames: Int?

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
        return String(
            format: "[AUDIO-PATH] BLE_SUPPLY_WINDOW stream=%@ session_id=%@ index=%d start_ms=%.1f elapsed_ms=%.1f decoded_samples=%d effective_source_hz=%.1f notifications=%d max_notification_gap_ms=%.1f queue_start_frames=%@ queue_end_frames=%@",
            streamText,
            sessionID,
            index,
            Double(startNanoseconds) / 1_000_000,
            elapsedMilliseconds,
            decodedSamples,
            effectiveSourceHz,
            notificationCount,
            maxNotificationGapMilliseconds,
            queueDepthStartFrames.map(String.init) ?? "NA",
            queueDepthEndFrames.map(String.init) ?? "NA"
        )
    }
}

struct BLEAudioContinuityAnalysis: Equatable {
    static let windowNanoseconds: UInt64 = 1_000_000_000

    let handlerLatency: BLEAudioHandlerLatencySummary
    let supplyWindows: [BLEAudioSupplyWindow]

    static func analyze(
        points: [LongTermObservationPoint],
        audioStartNanoseconds: UInt64?,
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

        let handlerLatency = handlerLatencySummary(points: sorted)
        let supplyWindows = supplyRateWindows(
            points: sorted,
            audioStartNanoseconds: audioStartNanoseconds
        )
        return BLEAudioContinuityAnalysis(
            handlerLatency: handlerLatency,
            supplyWindows: supplyWindows
        )
    }

    func logLines(streamID: UInt64?, sessionID: String) -> [String] {
        var lines: [String] = []
        if handlerLatency.sampleCount > 0 {
            lines.append(handlerLatency.logLine(streamID: streamID, sessionID: sessionID))
        }
        lines.append(contentsOf: supplyWindows.map {
            $0.logLine(streamID: streamID, sessionID: sessionID)
        })
        return lines
    }

    private static func handlerLatencySummary(
        points: [LongTermObservationPoint]
    ) -> BLEAudioHandlerLatencySummary {
        let ble = points.filter { $0.kind == .bleArrival }
        let submissions = points.filter { $0.kind == .pcmSubmitted }
        var submissionIndex = 0
        var latencies: [UInt64] = []
        latencies.reserveCapacity(min(ble.count, submissions.count))

        for arrival in ble {
            while submissionIndex < submissions.count,
                  submissions[submissionIndex].timestampNanoseconds < arrival.timestampNanoseconds {
                submissionIndex += 1
            }
            guard submissionIndex < submissions.count else { break }
            let submission = submissions[submissionIndex]
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
            windows.append(
                BLEAudioSupplyWindow(
                    index: index,
                    startNanoseconds: windowStart - start,
                    elapsedNanoseconds: windowEnd - windowStart,
                    decodedSamples: decodedSamples,
                    notificationCount: blePoints.count,
                    maxNotificationGapNanoseconds: maxGap,
                    queueDepthStartFrames: queueStart,
                    queueDepthEndFrames: queueEnd
                )
            )
        }
        return windows
    }

    private static func percentile(_ sorted: [UInt64], quantile: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(1, max(0, quantile))
        let rank = max(1, Int(ceil(clamped * Double(sorted.count))))
        return sorted[min(sorted.count - 1, rank - 1)]
    }
}
