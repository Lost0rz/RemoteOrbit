import XCTest
import Darwin
@testable import RemoteOrbit

final class AudioPipeRealtimeTests: XCTestCase {
    func testEmptyReadZeroFillsRequestedFrames() {
        let ring = FixedCapacityPCMFrameRing(capacity: 4)

        let result = read(ring, count: 3)

        XCTAssertEqual(result.result.filledFrames, 0)
        XCTAssertEqual(result.result.unfilledFrames, 3)
        XCTAssertEqual(result.result.queueDepthBeforeFrames, 0)
        XCTAssertEqual(result.result.queueDepthAfterFrames, 0)
        XCTAssertEqual(result.result.remoteFramesConsumed, 0)
        XCTAssertEqual(result.samples, [0, 0, 0])
    }

    func testWriteReadPreservesFIFOAndSupportsPartialOperations() {
        let ring = FixedCapacityPCMFrameRing(capacity: 8)

        XCTAssertEqual(
            ring.write([1, 2, 3]).acceptedFrames,
            3
        )
        let first = read(ring, count: 2)
        XCTAssertEqual(first.samples, [1, 2])
        XCTAssertEqual(first.result.filledFrames, 2)
        XCTAssertEqual(first.result.unfilledFrames, 0)

        XCTAssertEqual(
            ring.write([4, 5]).acceptedFrames,
            2
        )
        let second = read(ring, count: 3)
        XCTAssertEqual(second.samples, [3, 4, 5])
        XCTAssertEqual(second.result.queueDepthAfterFrames, 0)
    }

    func testPartialReadZeroFillsOnlyTheMissingSuffix() {
        let ring = FixedCapacityPCMFrameRing(capacity: 8)
        _ = ring.write([7, 8])

        let result = read(ring, count: 4)

        XCTAssertEqual(result.samples, [7, 8, 0, 0])
        XCTAssertEqual(result.result.filledFrames, 2)
        XCTAssertEqual(result.result.unfilledFrames, 2)
        XCTAssertEqual(result.result.remoteFramesConsumed, 2)
    }

    func testExactFullAndExactEmptyStatesRemainDistinct() {
        let ring = FixedCapacityPCMFrameRing(capacity: 4)

        let write = ring.write([1, 2, 3, 4])
        XCTAssertEqual(write.acceptedFrames, 4)
        XCTAssertEqual(write.droppedFrames, 0)
        XCTAssertEqual(write.queueDepthAfterFrames, 4)

        let rejected = ring.write([5])
        XCTAssertEqual(rejected.acceptedFrames, 0)
        XCTAssertEqual(rejected.droppedFrames, 1)
        XCTAssertEqual(rejected.queueDepthAfterFrames, 4)

        let readResult = read(ring, count: 4)
        XCTAssertEqual(readResult.samples, [1, 2, 3, 4])
        XCTAssertEqual(readResult.result.queueDepthAfterFrames, 0)
        XCTAssertEqual(read(ring, count: 1).samples, [0])
    }

    func testWraparoundPreservesFIFOAcrossRepeatedCycles() {
        let ring = FixedCapacityPCMFrameRing(capacity: 4)

        for cycle in 0..<20 {
            let base = Float(cycle * 4)
            XCTAssertEqual(
                ring.write([base, base + 1, base + 2]).acceptedFrames,
                3
            )
            XCTAssertEqual(read(ring, count: 2).samples, [base, base + 1])
            XCTAssertEqual(
                ring.write([base + 3, base + 4]).acceptedFrames,
                2
            )
            XCTAssertEqual(
                read(ring, count: 3).samples,
                [base + 2, base + 3, base + 4]
            )
        }
    }

    func testFullRingRejectsNewestSamplesWithoutOverwritingUnreadPCM() {
        let ring = FixedCapacityPCMFrameRing(capacity: 3)

        XCTAssertEqual(
            ring.write([10, 11, 12]).acceptedFrames,
            3
        )
        let overflow = ring.write([13, 14])

        XCTAssertEqual(overflow.acceptedFrames, 0)
        XCTAssertEqual(overflow.droppedFrames, 2)
        XCTAssertEqual(read(ring, count: 3).samples, [10, 11, 12])
    }

    func testRemoteQueueDepthFieldsEqualTotalQueueDepth() {
        let ring = FixedCapacityPCMFrameRing(capacity: 8)

        let write = ring.write([1, 2, 3])
        XCTAssertEqual(write.remoteQueueDepthAfterFrames, 3)
        XCTAssertEqual(write.remoteQueueDepthAfterFrames, write.queueDepthAfterFrames)
        XCTAssertEqual(ring.queuedFrames, 3)

        let result = read(ring, count: 2)

        XCTAssertEqual(result.result.remoteFramesConsumed, result.result.filledFrames)
        XCTAssertEqual(result.result.remoteQueueDepthBeforeFrames, 3)
        XCTAssertEqual(result.result.remoteQueueDepthBeforeFrames, result.result.queueDepthBeforeFrames)
        XCTAssertEqual(result.result.remoteQueueDepthAfterFrames, 1)
        XCTAssertEqual(result.result.remoteQueueDepthAfterFrames, result.result.queueDepthAfterFrames)

        let overflow = ring.write([4, 5, 6, 7, 8, 9, 10, 11, 12])
        XCTAssertEqual(overflow.acceptedFrames, 7)
        XCTAssertEqual(overflow.droppedFrames, 2)
        XCTAssertEqual(overflow.remoteQueueDepthAfterFrames, overflow.queueDepthAfterFrames)
        XCTAssertEqual(overflow.remoteQueueDepthAfterFrames, 8)
    }

    func testResetClearsQueuedPCM() {
        let ring = FixedCapacityPCMFrameRing(capacity: 4)
        _ = ring.write([1, 2, 3])

        ring.reset()

        XCTAssertEqual(ring.queuedFrames, 0)
        XCTAssertEqual(read(ring, count: 2).samples, [0, 0])
    }

    func testSingleProducerConsumerStressPreservesOrderAndBoundedIndices() {
        let ring = FixedCapacityPCMFrameRing(capacity: 32)
        let sampleCount = 20_000
        let completion = DispatchGroup()
        let producerQueue = DispatchQueue(
            label: "remoteorbit.test.pcm-producer",
            qos: .userInitiated
        )
        let consumerQueue = DispatchQueue(
            label: "remoteorbit.test.pcm-consumer",
            qos: .userInitiated
        )
        var consumed = [Float]()
        consumed.reserveCapacity(sampleCount)

        completion.enter()
        producerQueue.async {
            var next = 0
            while next < sampleCount {
                let end = min(sampleCount, next + 11)
                let chunk = (next..<end).map(Float.init)
                let result = ring.write(chunk)
                next += result.acceptedFrames
                if result.acceptedFrames == 0 {
                    sched_yield()
                }
            }
            completion.leave()
        }

        completion.enter()
        consumerQueue.async {
            var output = [Float](repeating: 0, count: 17)
            while consumed.count < sampleCount {
                let result = output.withUnsafeMutableBufferPointer {
                    ring.read(into: $0)
                }
                if result.filledFrames == 0 {
                    sched_yield()
                    continue
                }
                consumed.append(contentsOf: output.prefix(result.filledFrames))
            }
            completion.leave()
        }

        XCTAssertEqual(
            completion.wait(timeout: .now() + 5),
            .success
        )
        XCTAssertEqual(consumed, (0..<sampleCount).map(Float.init))
        XCTAssertEqual(ring.queuedFrames, 0)
    }

    func testRealtimeDiagnosticsPublishesCountersAndBoundedObservations() {
        let diagnostics = AudioPipeRealtimeDiagnostics()
        diagnostics.setRemoteActive(true)
        diagnostics.beginDiagnostics(remoteActive: true)
        let accounting = AudioPipeRenderAccounting.measure(
            requestedFrames: 4,
            availableRemoteFrames: 2,
            pendingRemoteFrames: 2,
            remoteActive: true,
            remoteWasActive: true
        )
        let readResult = AudioPipePCMReadResult(
            requestedFrames: 4,
            filledFrames: 2,
            unfilledFrames: 2,
            remoteFramesConsumed: 2,
            queueDepthBeforeFrames: 2,
            remoteQueueDepthBeforeFrames: 2,
            queueDepthAfterFrames: 0,
            remoteQueueDepthAfterFrames: 0,
            peak: 0.5
        )

        XCTAssertTrue(diagnostics.beginRenderDiagnosticsIfActive())
        diagnostics.recordRender(
            accounting,
            requestedFrames: 4,
            readResult: readResult,
            remoteWasActive: true,
            timestampNanoseconds: 1_000
        )
        diagnostics.endRenderDiagnostics()

        let snapshot = diagnostics.snapshot(reset: false)
        XCTAssertEqual(snapshot.renderCallbackCount, 1)
        XCTAssertEqual(snapshot.renderRequestedFrames, 4)
        XCTAssertEqual(snapshot.renderFilledFrames, 2)
        XCTAssertEqual(snapshot.renderUnfilledFrames, 2)
        XCTAssertEqual(snapshot.underrunCallbackCount, 1)
        XCTAssertEqual(snapshot.maxUnderrunFrames, 2)
        XCTAssertEqual(snapshot.renderedRemoteFrames, 2)
        XCTAssertEqual(snapshot.minQueueDepthFrames, 0)
        XCTAssertEqual(snapshot.maxQueueDepthFrames, 0)

        var observations = [AudioPipeRealtimeObservation]()
        diagnostics.drainObservations { observations.append($0) }
        XCTAssertEqual(
            observations.map(\.kind),
            [.render, .queueStarvation]
        )
        XCTAssertNotNil(diagnostics.markers().firstRemoteRenderedMonotonicNanoseconds)
    }

    func testReserveWaitIsIntentionalSilenceNotAnActiveUnderrun() {
        let diagnostics = AudioPipeRealtimeDiagnostics()
        diagnostics.setRemoteActive(true)
        diagnostics.beginDiagnostics(remoteActive: true)
        let accounting = AudioPipeRenderAccounting.measure(
            requestedFrames: 480,
            availableRemoteFrames: 480,
            pendingRemoteFrames: 480,
            remoteActive: true,
            remoteWasActive: true,
            reserveWaiting: true
        )
        let readResult = AudioPipePCMReadResult(
            requestedFrames: 480,
            filledFrames: 0,
            unfilledFrames: 0,
            remoteFramesConsumed: 0,
            queueDepthBeforeFrames: 480,
            remoteQueueDepthBeforeFrames: 480,
            queueDepthAfterFrames: 480,
            remoteQueueDepthAfterFrames: 480,
            peak: 0
        )

        XCTAssertEqual(accounting.state, .reserveWait)
        XCTAssertEqual(accounting.activeUnderrunCallbacks, 0)
        XCTAssertEqual(accounting.activeUnderrunFrames, 0)

        XCTAssertTrue(diagnostics.beginRenderDiagnosticsIfActive())
        diagnostics.recordRender(
            accounting,
            requestedFrames: 480,
            readResult: readResult,
            remoteWasActive: true,
            timestampNanoseconds: 1_000
        )
        diagnostics.endRenderDiagnostics()

        let snapshot = diagnostics.snapshot(reset: false)
        XCTAssertEqual(snapshot.underrunCallbackCount, 0)
        XCTAssertEqual(snapshot.renderedRemoteFrames, 0)

        var observations = [AudioPipeRealtimeObservation]()
        diagnostics.drainObservations { observations.append($0) }
        XCTAssertEqual(observations.map(\.kind), [.render])
        XCTAssertNil(diagnostics.markers(reset: false).firstRemoteRenderedMonotonicNanoseconds)
    }

    func testRenderCallbackSourceHasNoDynamicBufferLockOrDispatch() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RemoteOrbit/AudioPipe.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let renderStart = try XCTUnwrap(source.range(of: "func render("))
        let renderEnd = try XCTUnwrap(
            source.range(of: "private func recordQueueDepthLocked", range: renderStart.upperBound..<source.endIndex)
        )
        let renderBody = String(source[renderStart.lowerBound..<renderEnd.lowerBound])

        XCTAssertFalse(renderBody.contains("stateLock.lock()"))
        XCTAssertFalse(renderBody.contains("[Float]"))
        XCTAssertFalse(renderBody.contains("append("))
        XCTAssertFalse(renderBody.contains("removeFirst"))
        XCTAssertFalse(renderBody.contains("DispatchQueue"))
        XCTAssertFalse(renderBody.contains("VoiceTimingLogger."))
    }

    private func read(
        _ ring: FixedCapacityPCMFrameRing,
        count: Int
    ) -> (samples: [Float], result: AudioPipePCMReadResult) {
        var samples = [Float](repeating: -1, count: count)
        let result = samples.withUnsafeMutableBufferPointer {
            ring.read(into: $0)
        }
        return (samples, result)
    }
}
