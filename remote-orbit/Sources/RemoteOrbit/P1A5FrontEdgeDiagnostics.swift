import Foundation

/// Fixed, observation-only voice-onset rule for P1-A5.
///
/// A decoded 16 kHz frame is considered voiced when its RMS is at least 300
/// Int16 units. The candidate must remain above that threshold for three
/// consecutive decoder frames (22.5 ms at the current 120-sample frame size).
/// This rule is deliberately fixed for the experiment and never changes PCM.
struct P1A5VoiceOnsetCandidate {
    let timestampNanoseconds: UInt64
    let frameIndex: Int
    let rms: Double
    let peak: Int
    let threshold: Double
    let consecutiveVoicedFrames: Int
}

struct P1A5VoiceOnsetDetector {
    static let rmsThreshold: Double = 300
    static let requiredConsecutiveFrames = 3

    private(set) var consecutiveVoicedFrames = 0
    private var candidateTimestampNanoseconds: UInt64?
    private var candidateFrameIndex = 0
    private var candidateRMS = 0.0
    private var candidatePeak = 0
    private(set) var emitted = false

    mutating func reset() {
        consecutiveVoicedFrames = 0
        candidateTimestampNanoseconds = nil
        candidateFrameIndex = 0
        candidateRMS = 0
        candidatePeak = 0
        emitted = false
    }

    mutating func analyze(
        samples: [Int16],
        frameIndex: Int,
        timestampNanoseconds: UInt64
    ) -> P1A5VoiceOnsetCandidate? {
        guard !emitted, !samples.isEmpty else { return nil }

        let sumSquares = samples.reduce(into: Double(0)) { total, sample in
            let value = Double(sample)
            total += value * value
        }
        let rms = sqrt(sumSquares / Double(samples.count))
        let peak = samples.reduce(0) { max($0, abs(Int($1))) }

        guard rms >= Self.rmsThreshold else {
            consecutiveVoicedFrames = 0
            candidateTimestampNanoseconds = nil
            return nil
        }

        if consecutiveVoicedFrames == 0 {
            candidateTimestampNanoseconds = timestampNanoseconds
            candidateFrameIndex = frameIndex
            candidateRMS = rms
            candidatePeak = peak
        }
        consecutiveVoicedFrames += 1

        guard consecutiveVoicedFrames >= Self.requiredConsecutiveFrames,
              let candidateTimestampNanoseconds else {
            return nil
        }

        emitted = true
        return P1A5VoiceOnsetCandidate(
            timestampNanoseconds: candidateTimestampNanoseconds,
            frameIndex: candidateFrameIndex,
            rms: candidateRMS,
            peak: candidatePeak,
            threshold: Self.rmsThreshold,
            consecutiveVoicedFrames: consecutiveVoicedFrames
        )
    }
}

struct P1A5FrontEdgeUnderrunBucket {
    var count = 0
    var durationMilliseconds = 0.0
}

struct P1A5FrontEdgeUnderrunStats {
    var buckets = Array(repeating: P1A5FrontEdgeUnderrunBucket(), count: 4)

    mutating func record(distanceMilliseconds: Double, durationMilliseconds: Double) {
        let index: Int?
        switch distanceMilliseconds {
        case 0..<100: index = 0
        case 100..<250: index = 1
        case 250..<500: index = 2
        case 500...1000: index = 3
        default: index = nil
        }
        guard let index else { return }
        buckets[index].count += 1
        buckets[index].durationMilliseconds += durationMilliseconds
    }
}
