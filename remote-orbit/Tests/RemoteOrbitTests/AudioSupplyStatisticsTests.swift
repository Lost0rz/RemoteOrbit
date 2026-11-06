import XCTest
@testable import RemoteOrbit

final class AudioSupplyStatisticsTests: XCTestCase {
    private let start: UInt64 = 5_000_000_000

    func testThirtySecondSustainedSupplyHasCompletePerSecondStatistics() {
        var service = AudioSupplyStatisticsRing(producer: .voiceService, sessionStartNanoseconds: start)
        var audioPipe = AudioSupplyStatisticsRing(producer: .audioPipe, sessionStartNanoseconds: start)
        var serviceSequence: UInt64 = 0
        var pipeSequence: UInt64 = 0

        for second in UInt64(0)..<30 {
            recordServiceWindow(
                second,
                decodedSamples: 16_000,
                sequence: &serviceSequence,
                ring: &service
            )
            recordAudioPipeWindow(second, sequence: &pipeSequence, ring: &audioPipe)
        }

        let snapshot = joined(service, audioPipe, through: start + 30_000_000_000)

        XCTAssertEqual(snapshot.windows.count, 30)
        XCTAssertTrue(snapshot.windows.allSatisfy(\.invalidReasons.isEmpty))
        XCTAssertEqual(snapshot.effectiveSourceHzBySecond.count, 30)
        XCTAssertTrue(snapshot.effectiveSourceHzBySecond.values.allSatisfy { $0 == 16_000 })
        XCTAssertEqual(snapshot.windows[12].notificationCount, 1)
        XCTAssertEqual(snapshot.windows[12].notificationGapCount, 1)
        XCTAssertEqual(snapshot.windows[12].decodedPCMSamples, 16_000)
        XCTAssertEqual(snapshot.windows[12].queueStartDepthFrames, 240)
        XCTAssertEqual(snapshot.windows[12].queueEndDepthFrames, 120)
        XCTAssertEqual(snapshot.windows[12].activeUnderrunFrames, 80)
    }

    func testArtificialSupplyGapIsValidZeroSupplyInsteadOfMissingEvidence() {
        var service = AudioSupplyStatisticsRing(producer: .voiceService, sessionStartNanoseconds: start)
        var audioPipe = AudioSupplyStatisticsRing(producer: .audioPipe, sessionStartNanoseconds: start)
        var serviceSequence: UInt64 = 0
        var pipeSequence: UInt64 = 0

        for second in [UInt64(0), 1, 3] {
            recordServiceWindow(
                second,
                decodedSamples: 16_000,
                sequence: &serviceSequence,
                ring: &service,
                gapNanoseconds: second == 3 ? 1_050_000_000 : 20_000_000
            )
        }
        for second in UInt64(0)..<4 {
            recordAudioPipeWindow(second, sequence: &pipeSequence, ring: &audioPipe)
        }

        let snapshot = joined(service, audioPipe, through: start + 4_000_000_000)
        let gapWindow = try! XCTUnwrap(snapshot.windows.first { $0.second == 2 })

        XCTAssertTrue(gapWindow.invalidReasons.isEmpty)
        XCTAssertEqual(gapWindow.notificationCount, 0)
        XCTAssertEqual(gapWindow.decodedPCMSamples, 0)
        XCTAssertEqual(snapshot.effectiveSourceHzBySecond[2], 0)
    }

    func testIncompleteBoundaryWindowIsInvalidAndHasNullEffectiveSourceRate() {
        var service = AudioSupplyStatisticsRing(producer: .voiceService, sessionStartNanoseconds: start)
        var audioPipe = AudioSupplyStatisticsRing(producer: .audioPipe, sessionStartNanoseconds: start)
        var serviceSequence: UInt64 = 0
        var pipeSequence: UInt64 = 0
        for second in UInt64(0)...2 {
            recordServiceWindow(second, decodedSamples: 16_000, sequence: &serviceSequence, ring: &service)
            recordAudioPipeWindow(second, sequence: &pipeSequence, ring: &audioPipe)
        }

        let snapshot = joined(service, audioPipe, through: start + 2_500_000_000)
        let boundary = try! XCTUnwrap(snapshot.windows.first { $0.second == 2 })

        XCTAssertTrue(boundary.invalidReasons.contains("incomplete_boundary_window"))
        XCTAssertNil(snapshot.effectiveSourceHzBySecond[2])
        XCTAssertEqual(snapshot.effectiveSourceHzBySecond[1], 16_000)
    }

    func testSourceSequenceGapInvalidatesAffectedWindowsAndExcludesThemFromRate() {
        var service = AudioSupplyStatisticsRing(producer: .voiceService, sessionStartNanoseconds: start)
        var audioPipe = AudioSupplyStatisticsRing(producer: .audioPipe, sessionStartNanoseconds: start)
        var pipeSequence: UInt64 = 0
        let servicePoints: [(UInt64, UInt64, LongTermObservationKind, UInt64)] = [
            (0, 1, .bleArrival, 0), (0, 2, .decodeComplete, 16_000),
            (1, 3, .bleArrival, 0), (1, 4, .decodeComplete, 16_000),
            (2, 6, .bleArrival, 0), (2, 7, .decodeComplete, 16_000),
            (3, 8, .bleArrival, 0), (3, 9, .decodeComplete, 16_000),
        ]
        for (second, sequence, kind, samples) in servicePoints {
            service.record(
                point(
                    second: second,
                    offset: kind == .bleArrival ? 10_000_000 : 20_000_000,
                    kind: kind,
                    sampleCount: samples,
                    sequence: sequence,
                    source: "voice_service"
                ),
                gapNanoseconds: kind == .bleArrival ? 20_000_000 : nil
            )
        }
        for second in UInt64(0)...3 {
            recordAudioPipeWindow(second, sequence: &pipeSequence, ring: &audioPipe)
        }

        let snapshot = joined(service, audioPipe, through: start + 4_000_000_000)
        let secondOne = try! XCTUnwrap(snapshot.windows.first { $0.second == 1 })
        let secondTwo = try! XCTUnwrap(snapshot.windows.first { $0.second == 2 })

        XCTAssertEqual(snapshot.voiceServiceSequenceGapCount, 1)
        XCTAssertTrue(secondOne.invalidReasons.contains("voice_service_source_sequence_gap"))
        XCTAssertTrue(secondTwo.invalidReasons.contains("voice_service_source_sequence_gap"))
        XCTAssertNil(snapshot.effectiveSourceHzBySecond[1])
        XCTAssertNil(snapshot.effectiveSourceHzBySecond[2])
        XCTAssertEqual(snapshot.effectiveSourceHzBySecond[3], 16_000)
    }

    func testMailboxOverflowInvalidatesEveryAffectedWindowAndHidesItsRate() {
        var service = AudioSupplyStatisticsRing(producer: .voiceService, sessionStartNanoseconds: start)
        var audioPipe = AudioSupplyStatisticsRing(producer: .audioPipe, sessionStartNanoseconds: start)
        var serviceSequence: UInt64 = 0
        var pipeSequence: UInt64 = 0
        for second in UInt64(0)..<4 {
            recordServiceWindow(second, decodedSamples: 16_000, sequence: &serviceSequence, ring: &service)
            recordAudioPipeWindow(second, sequence: &pipeSequence, ring: &audioPipe)
        }
        audioPipe.invalidate(
            from: start + 1_100_000_000,
            through: start + 2_700_000_000,
            reason: .coreAudioMailboxOverflow
        )

        let snapshot = joined(service, audioPipe, through: start + 4_000_000_000)
        let secondOne = try! XCTUnwrap(snapshot.windows.first { $0.second == 1 })
        let secondTwo = try! XCTUnwrap(snapshot.windows.first { $0.second == 2 })

        XCTAssertTrue(secondOne.invalidReasons.contains("coreaudio_mailbox_overflow"))
        XCTAssertTrue(secondTwo.invalidReasons.contains("coreaudio_mailbox_overflow"))
        XCTAssertNil(snapshot.effectiveSourceHzBySecond[1])
        XCTAssertNil(snapshot.effectiveSourceHzBySecond[2])
        XCTAssertEqual(snapshot.effectiveSourceHzBySecond[0], 16_000)
        XCTAssertEqual(snapshot.effectiveSourceHzBySecond[3], 16_000)
    }

    func testStatisticsRingRolloverRecordsInvalidRangeAndRetainsLatest64Seconds() {
        var service = AudioSupplyStatisticsRing(producer: .voiceService, sessionStartNanoseconds: start)
        var audioPipe = AudioSupplyStatisticsRing(producer: .audioPipe, sessionStartNanoseconds: start)
        var serviceSequence: UInt64 = 0
        var pipeSequence: UInt64 = 0
        for second in UInt64(0)..<66 {
            recordServiceWindow(second, decodedSamples: 16_000, sequence: &serviceSequence, ring: &service)
            recordAudioPipeWindow(second, sequence: &pipeSequence, ring: &audioPipe)
        }

        let snapshot = joined(service, audioPipe, through: start + 66_000_000_000)

        XCTAssertEqual(snapshot.windows.count, 64)
        XCTAssertEqual(snapshot.windows.first?.second, 2)
        XCTAssertEqual(snapshot.windows.last?.second, 65)
        XCTAssertEqual(snapshot.ringOverwriteCount, 4)
        XCTAssertEqual(snapshot.invalidRanges.count, 2)
        XCTAssertTrue(snapshot.invalidRanges.allSatisfy { $0.firstSecond == 0 && $0.lastSecond == 1 })
        XCTAssertEqual(snapshot.effectiveSourceHzBySecond.count, 64)
    }

    func testProducerRecordPathUsesPreallocatedBoundedOperations() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RemoteOrbit/AudioSupplyStatistics.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let ringStart = try XCTUnwrap(source.range(of: "struct AudioSupplyStatisticsRing"))
        let snapshotStart = try XCTUnwrap(source.range(of: "mutating func snapshot(", range: ringStart.upperBound..<source.endIndex))
        let helpersStart = try XCTUnwrap(source.range(of: "private mutating func validateSequence(", range: snapshotStart.upperBound..<source.endIndex))
        let helpersEnd = try XCTUnwrap(source.range(of: "extension AudioSupplyStatisticsSnapshot", range: helpersStart.upperBound..<source.endIndex))
        let recordPath = String(source[ringStart.lowerBound..<snapshotStart.lowerBound])
            + String(source[helpersStart.lowerBound..<helpersEnd.lowerBound])

        for forbidden in ["Set<", "Dictionary<", "reserveCapacity", ".append(", "NSLock", "DispatchQueue", "wait(", "allocate(", "Data(", "print("] {
            XCTAssertFalse(recordPath.contains(forbidden), "unexpected producer-path operation: \(forbidden)")
        }
    }

    private func joined(
        _ service: AudioSupplyStatisticsRing,
        _ audioPipe: AudioSupplyStatisticsRing,
        through end: UInt64
    ) -> AudioSupplyStatisticsSnapshot {
        var service = service
        var audioPipe = audioPipe
        return AudioSupplyStatisticsSnapshot.join(
            voiceService: service.snapshot(through: end),
            audioPipe: audioPipe.snapshot(through: end),
            sessionEndNanoseconds: end
        )
    }

    private func recordServiceWindow(
        _ second: UInt64,
        decodedSamples: UInt64,
        sequence: inout UInt64,
        ring: inout AudioSupplyStatisticsRing,
        gapNanoseconds: UInt64 = 20_000_000
    ) {
        sequence &+= 1
        ring.record(
            point(second: second, offset: 10_000_000, kind: .bleArrival, sequence: sequence, source: "voice_service"),
            gapNanoseconds: gapNanoseconds
        )
        sequence &+= 1
        ring.record(
            point(second: second, offset: 20_000_000, kind: .decodeComplete, sampleCount: decodedSamples, sequence: sequence, source: "voice_service")
        )
    }

    private func recordAudioPipeWindow(
        _ second: UInt64,
        sequence: inout UInt64,
        ring: inout AudioSupplyStatisticsRing
    ) {
        sequence &+= 1
        ring.record(
            LongTermObservationPoint(
                timestampNanoseconds: start + second * AudioSupplyStatisticsRing.windowWidthNanoseconds + 500_000_000,
                kind: .render,
                requestedFrames: 480,
                filledFrames: 400,
                unfilledFrames: 80,
                queueDepthFrames: 120,
                byteOrSampleCount: 400,
                marker: .active,
                sequence: sequence,
                queueDepthBeforeFrames: 240,
                source: "audio_pipe"
            )
        )
    }

    private func point(
        second: UInt64,
        offset: UInt64,
        kind: LongTermObservationKind,
        sampleCount: UInt64 = 0,
        sequence: UInt64,
        source: String
    ) -> LongTermObservationPoint {
        LongTermObservationPoint(
            timestampNanoseconds: start + second * AudioSupplyStatisticsRing.windowWidthNanoseconds + offset,
            kind: kind,
            requestedFrames: 0,
            filledFrames: 0,
            unfilledFrames: 0,
            queueDepthFrames: 0,
            byteOrSampleCount: sampleCount,
            marker: .unclassified,
            sequence: sequence,
            source: source
        )
    }
}
