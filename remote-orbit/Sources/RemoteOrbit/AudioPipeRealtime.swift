import AudioToolbox
import Darwin

/// Write result. The ring is remote-only: remote-attributed depth fields
/// equal their total-depth counterparts.
struct AudioPipePCMWriteResult: Equatable {
    let acceptedFrames: Int
    let droppedFrames: Int
    let queueDepthAfterFrames: Int
    let remoteQueueDepthAfterFrames: Int
}

/// Read result. The ring is remote-only: remote-attributed depth/consumed
/// fields equal their total-depth counterparts.
struct AudioPipePCMReadResult: Equatable {
    let requestedFrames: Int
    let filledFrames: Int
    let unfilledFrames: Int
    let remoteFramesConsumed: Int
    let queueDepthBeforeFrames: Int
    let remoteQueueDepthBeforeFrames: Int
    let queueDepthAfterFrames: Int
    let remoteQueueDepthAfterFrames: Int
    let peak: Float
}

/// A preallocated single-producer/single-consumer PCM transport ring.
///
/// The producer owns write publication and the CoreAudio callback owns read
/// publication. The existing AudioPipe producer-side state ownership keeps
/// remote submissions serialized; the callback never takes that ordinary
/// state lock. Monotonic Int64 indices make exact full and empty states
/// distinct without reserving a slot.
final class FixedCapacityPCMFrameRing: @unchecked Sendable {
    let capacity: Int

    private let storage: UnsafeMutablePointer<Float>
    private var readIndex: Int64 = 0
    private var writeIndex: Int64 = 0
    /// 0 = idle, 1 = render read in progress, 2 = producer reset in progress.
    /// Reset is producer-side and may wait; the realtime reader never waits.
    private var readerGate: Int32 = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    var queuedFrames: Int {
        let write = OSAtomicAdd64Barrier(0, &writeIndex)
        let read = OSAtomicAdd64Barrier(0, &readIndex)
        return Self.boundedDepth(write - read, capacity: capacity)
    }

    func write(_ samples: [Float]) -> AudioPipePCMWriteResult {
        samples.withUnsafeBufferPointer { buffer in
            write(buffer)
        }
    }

    func write(_ samples: UnsafeBufferPointer<Float>) -> AudioPipePCMWriteResult {
        let requested = samples.count
        guard requested > 0 else {
            let depth = queuedFrames
            return AudioPipePCMWriteResult(
                acceptedFrames: 0,
                droppedFrames: 0,
                queueDepthAfterFrames: depth,
                remoteQueueDepthAfterFrames: depth
            )
        }

        let write = OSAtomicAdd64Barrier(0, &writeIndex)
        let read = OSAtomicAdd64Barrier(0, &readIndex)
        let depth = Self.boundedDepth(write - read, capacity: capacity)
        let accepted = min(requested, capacity - depth)
        let dropped = requested - accepted

        if accepted > 0, let baseAddress = samples.baseAddress {
            copyIntoStorage(
                source: baseAddress,
                count: accepted,
                startingAt: write
            )
            publishWriteIndex(write + Int64(accepted))
        }

        let afterWrite = OSAtomicAdd64Barrier(0, &writeIndex)
        let afterRead = OSAtomicAdd64Barrier(0, &readIndex)
        let depthAfter = Self.boundedDepth(
            afterWrite - afterRead,
            capacity: capacity
        )
        return AudioPipePCMWriteResult(
            acceptedFrames: accepted,
            droppedFrames: dropped,
            queueDepthAfterFrames: depthAfter,
            remoteQueueDepthAfterFrames: depthAfter
        )
    }

    /// Reads into caller-owned storage. This is used by deterministic ring
    /// tests; the production callback uses the AudioBufferList overload below.
    func read(into destination: UnsafeMutableBufferPointer<Float>) -> AudioPipePCMReadResult {
        let requested = destination.count
        guard requested > 0 else {
            let depth = queuedFrames
            return AudioPipePCMReadResult(
                requestedFrames: 0,
                filledFrames: 0,
                unfilledFrames: 0,
                remoteFramesConsumed: 0,
                queueDepthBeforeFrames: depth,
                remoteQueueDepthBeforeFrames: depth,
                queueDepthAfterFrames: depth,
                remoteQueueDepthAfterFrames: depth,
                peak: 0
            )
        }

        guard acquireReaderGate() else {
            for index in destination.indices {
                destination[index] = 0
            }
            let depth = queuedFrames
            return AudioPipePCMReadResult(
                requestedFrames: requested,
                filledFrames: 0,
                unfilledFrames: requested,
                remoteFramesConsumed: 0,
                queueDepthBeforeFrames: depth,
                remoteQueueDepthBeforeFrames: depth,
                queueDepthAfterFrames: depth,
                remoteQueueDepthAfterFrames: depth,
                peak: 0
            )
        }

        let result = readSamples(requested: requested) { index, sample in
            destination[index] = sample
        }
        return result
    }

    /// Reads directly into CoreAudio's caller-owned output memory. No sample
    /// array, temporary buffer, lock, formatting, or dispatch occurs here.
    func read(
        into outputData: UnsafeMutablePointer<AudioBufferList>,
        requestedFrames: Int
    ) -> AudioPipePCMReadResult {
        let requested = max(0, requestedFrames)
        guard requested > 0 else {
            let depth = queuedFrames
            return AudioPipePCMReadResult(
                requestedFrames: 0,
                filledFrames: 0,
                unfilledFrames: 0,
                remoteFramesConsumed: 0,
                queueDepthBeforeFrames: depth,
                remoteQueueDepthBeforeFrames: depth,
                queueDepthAfterFrames: depth,
                remoteQueueDepthAfterFrames: depth,
                peak: 0
            )
        }

        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard acquireReaderGate() else {
            zeroFill(buffers, requestedFrames: requested)
            let depth = queuedFrames
            return AudioPipePCMReadResult(
                requestedFrames: requested,
                filledFrames: 0,
                unfilledFrames: requested,
                remoteFramesConsumed: 0,
                queueDepthBeforeFrames: depth,
                remoteQueueDepthBeforeFrames: depth,
                queueDepthAfterFrames: depth,
                remoteQueueDepthAfterFrames: depth,
                peak: 0
            )
        }

        let write = OSAtomicAdd64Barrier(0, &writeIndex)
        let read = OSAtomicAdd64Barrier(0, &readIndex)
        let queueDepthBefore = Self.boundedDepth(
            write - read,
            capacity: capacity
        )
        let filled = min(requested, queueDepthBefore)
        var peak: Float = 0

        for frame in 0..<requested {
            let sample: Float
            if frame < filled {
                let storageIndex = Int((read + Int64(frame)) % Int64(capacity))
                sample = storage[storageIndex]
                peak = max(peak, abs(sample))
            } else {
                sample = 0
            }
            for bufferIndex in 0..<buffers.count {
                let buffer = buffers[bufferIndex]
                guard let data = buffer.mData else { continue }
                let channelCount = max(1, Int(buffer.mNumberChannels))
                let writableFrames = Int(buffer.mDataByteSize) /
                    MemoryLayout<Float>.size /
                    channelCount
                guard frame < writableFrames else { continue }
                let output = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<channelCount {
                    output[frame * channelCount + channel] = sample
                }
            }
        }

        publishReadIndex(read + Int64(filled))
        let afterWrite = OSAtomicAdd64Barrier(0, &writeIndex)
        let afterRead = OSAtomicAdd64Barrier(0, &readIndex)
        let queueDepthAfter = Self.boundedDepth(
            afterWrite - afterRead,
            capacity: capacity
        )
        let result = AudioPipePCMReadResult(
            requestedFrames: requested,
            filledFrames: filled,
            unfilledFrames: requested - filled,
            remoteFramesConsumed: filled,
            queueDepthBeforeFrames: queueDepthBefore,
            remoteQueueDepthBeforeFrames: queueDepthBefore,
            queueDepthAfterFrames: queueDepthAfter,
            remoteQueueDepthAfterFrames: queueDepthAfter,
            peak: peak
        )
        releaseReaderGate()
        return result
    }

    /// Emits intentional reserve silence without advancing either ring index.
    /// The result deliberately reports no unfilled frames: reserve silence is
    /// not a true output underflow.
    func writeReserveSilence(
        into outputData: UnsafeMutablePointer<AudioBufferList>,
        requestedFrames: Int
    ) -> AudioPipePCMReadResult {
        let requested = max(0, requestedFrames)
        let queueDepth = queuedFrames
        zeroFill(
            UnsafeMutableAudioBufferListPointer(outputData),
            requestedFrames: requested
        )
        return AudioPipePCMReadResult(
            requestedFrames: requested,
            filledFrames: 0,
            unfilledFrames: 0,
            remoteFramesConsumed: 0,
            queueDepthBeforeFrames: queueDepth,
            remoteQueueDepthBeforeFrames: queueDepth,
            queueDepthAfterFrames: queueDepth,
            remoteQueueDepthAfterFrames: queueDepth,
            peak: 0
        )
    }

    /// Explicit session/device reset. It waits off the realtime callback for
    /// an in-flight reader, then resets both indices.
    func reset() {
        acquireResetGate()
        let currentWrite = OSAtomicAdd64Barrier(0, &writeIndex)
        let currentRead = OSAtomicAdd64Barrier(0, &readIndex)
        _ = OSAtomicCompareAndSwap64Barrier(currentWrite, 0, &writeIndex)
        _ = OSAtomicCompareAndSwap64Barrier(currentRead, 0, &readIndex)
        _ = OSAtomicCompareAndSwap32Barrier(2, 0, &readerGate)
    }

    private func readSamples(
        requested: Int,
        _ writeSample: (Int, Float) -> Void
    ) -> AudioPipePCMReadResult {
        let write = OSAtomicAdd64Barrier(0, &writeIndex)
        let read = OSAtomicAdd64Barrier(0, &readIndex)
        let queueDepthBefore = Self.boundedDepth(
            write - read,
            capacity: capacity
        )
        let filled = min(requested, queueDepthBefore)
        var peak: Float = 0

        for frame in 0..<requested {
            let sample: Float
            if frame < filled {
                let storageIndex = Int((read + Int64(frame)) % Int64(capacity))
                sample = storage[storageIndex]
                peak = max(peak, abs(sample))
            } else {
                sample = 0
            }
            writeSample(frame, sample)
        }

        publishReadIndex(read + Int64(filled))

        let afterWrite = OSAtomicAdd64Barrier(0, &writeIndex)
        let afterRead = OSAtomicAdd64Barrier(0, &readIndex)
        let queueDepthAfter = Self.boundedDepth(
            afterWrite - afterRead,
            capacity: capacity
        )
        releaseReaderGate()
        return AudioPipePCMReadResult(
            requestedFrames: requested,
            filledFrames: filled,
            unfilledFrames: requested - filled,
            remoteFramesConsumed: filled,
            queueDepthBeforeFrames: queueDepthBefore,
            remoteQueueDepthBeforeFrames: queueDepthBefore,
            queueDepthAfterFrames: queueDepthAfter,
            remoteQueueDepthAfterFrames: queueDepthAfter,
            peak: peak
        )
    }

    private func copyIntoStorage(
        source: UnsafePointer<Float>,
        count: Int,
        startingAt index: Int64
    ) {
        let firstIndex = Int(index % Int64(capacity))
        let firstCount = min(count, capacity - firstIndex)
        memcpy(storage.advanced(by: firstIndex), source, firstCount * MemoryLayout<Float>.size)
        let remaining = count - firstCount
        if remaining > 0 {
            memcpy(storage, source.advanced(by: firstCount), remaining * MemoryLayout<Float>.size)
        }
    }

    private func zeroFill(
        _ buffers: UnsafeMutableAudioBufferListPointer,
        requestedFrames: Int
    ) {
        for bufferIndex in 0..<buffers.count {
            let buffer = buffers[bufferIndex]
            guard let data = buffer.mData else { continue }
            let channelCount = max(1, Int(buffer.mNumberChannels))
            let writableFrames = min(
                requestedFrames,
                Int(buffer.mDataByteSize) /
                    MemoryLayout<Float>.size /
                    channelCount
            )
            memset(
                data,
                0,
                writableFrames * channelCount * MemoryLayout<Float>.size
            )
        }
    }

    private func acquireReaderGate() -> Bool {
        OSAtomicCompareAndSwap32Barrier(0, 1, &readerGate)
    }

    private func releaseReaderGate() {
        _ = OSAtomicCompareAndSwap32Barrier(1, 0, &readerGate)
    }

    private func acquireResetGate() {
        while true {
            let state = OSAtomicAdd32Barrier(0, &readerGate)
            if state == 0,
               OSAtomicCompareAndSwap32Barrier(0, 2, &readerGate) {
                return
            }
            sched_yield()
        }
    }

    private func publishWriteIndex(_ value: Int64) {
        let current = OSAtomicAdd64Barrier(0, &writeIndex)
        _ = OSAtomicCompareAndSwap64Barrier(current, value, &writeIndex)
    }

    private func publishReadIndex(_ value: Int64) {
        let current = OSAtomicAdd64Barrier(0, &readIndex)
        _ = OSAtomicCompareAndSwap64Barrier(current, value, &readIndex)
    }

    private static func boundedDepth(_ value: Int64, capacity: Int) -> Int {
        Int(max(0, min(value, Int64(capacity))))
    }
}

struct AudioPipeRealtimeObservation {
    enum Kind: Int32, Equatable {
        case render = 1
        case queueStarvation = 2
    }

    let kind: Kind
    let timestampNanoseconds: UInt64
    let requestedFrames: Int
    let filledFrames: Int
    let unfilledFrames: Int
    let queueDepthBeforeFrames: Int
    let queueDepthAfterFrames: Int
    let byteOrSampleCount: Int
    let marker: Int32

    init(
        kind: Kind = .render,
        timestampNanoseconds: UInt64 = 0,
        requestedFrames: Int = 0,
        filledFrames: Int = 0,
        unfilledFrames: Int = 0,
        queueDepthBeforeFrames: Int = 0,
        queueDepthAfterFrames: Int = 0,
        byteOrSampleCount: Int = 0,
        marker: Int32 = 0
    ) {
        self.kind = kind
        self.timestampNanoseconds = timestampNanoseconds
        self.requestedFrames = requestedFrames
        self.filledFrames = filledFrames
        self.unfilledFrames = unfilledFrames
        self.queueDepthBeforeFrames = queueDepthBeforeFrames
        self.queueDepthAfterFrames = queueDepthAfterFrames
        self.byteOrSampleCount = byteOrSampleCount
        self.marker = marker
    }
}

struct AudioPipeRealtimeCounterSnapshot {
    let renderCallbackCount: Int
    let renderRequestedFrames: Int
    let renderFilledFrames: Int
    let renderUnfilledFrames: Int
    let underrunCallbackCount: Int
    let maxUnderrunFrames: Int
    let renderedRemoteFrames: Int
    let minQueueDepthFrames: Int?
    let maxQueueDepthFrames: Int
    let tailRenderedFrames: Int
    let tailEmptyCallbackCount: Int
    let idleRenderCallbackCount: Int
    let lastRemoteRenderedMonotonicNanoseconds: UInt64?
}

struct AudioPipeRealtimeMarkerSnapshot {
    let firstRemoteRenderedMonotonicNanoseconds: UInt64?
    let playoutStableMonotonicNanoseconds: UInt64?
    let droppedObservationCount: Int
}

struct AudioPipeRealtimeMeterSnapshot {
    let renderCallbackCount: Int
    let renderedFrames: Int
    let renderedPeak: Float
}

/// Lock-free scalar render accounting and a bounded off-path observation
/// mailbox. The CoreAudio callback publishes only fixed-size values here;
/// AudioPipe consumes them later while it owns its ordinary state lock.
final class AudioPipeRealtimeDiagnostics: @unchecked Sendable {
    private static let observationCapacity = 4_096

    private let observations: UnsafeMutablePointer<AudioPipeRealtimeObservation>
    private var observationReadIndex: Int64 = 0
    private var observationWriteIndex: Int64 = 0
    private var droppedObservationCount: Int64 = 0

    private var diagnosticsActive: Int32 = 0
    private var diagnosticsRenderInFlight: Int32 = 0
    private var remoteActive: Int32 = 0
    private var remoteWasActive: Int32 = 0
    private var drainWaiterRequested: Int32 = 0

    private var renderCallbackCount: Int64 = 0
    private var renderRequestedFrames: Int64 = 0
    private var renderFilledFrames: Int64 = 0
    private var renderUnfilledFrames: Int64 = 0
    private var underrunCallbackCount: Int64 = 0
    private var maxUnderrunFrames: Int64 = 0
    private var renderedRemoteFrames: Int64 = 0
    private var minQueueDepthFrames: Int64 = Int64.max
    private var maxQueueDepthFrames: Int64 = 0
    private var tailRenderedFrames: Int64 = 0
    private var tailEmptyCallbackCount: Int64 = 0
    private var idleRenderCallbackCount: Int64 = 0
    private var lastRemoteRenderedMonotonicNanoseconds: Int64 = 0
    private var firstRemoteRenderedMonotonicNanoseconds: Int64 = 0
    private var playoutStableMonotonicNanoseconds: Int64 = 0
    private var stableRenderIntervals: Int32 = 0
    private var meterRenderCallbackCount: Int64 = 0
    private var meterRenderedFrames: Int64 = 0
    private var meterRenderedPeakBits: Int32 = 0

    init() {
        observations = UnsafeMutablePointer<AudioPipeRealtimeObservation>
            .allocate(capacity: Self.observationCapacity)
        observations.initialize(
            repeating: AudioPipeRealtimeObservation(),
            count: Self.observationCapacity
        )
    }

    deinit {
        observations.deinitialize(count: Self.observationCapacity)
        observations.deallocate()
    }

    func setRemoteActive(_ active: Bool) {
        atomicStore32(active ? 1 : 0, to: &remoteActive)
        if active, atomicLoad32(&diagnosticsActive) != 0 {
            atomicStore32(1, to: &remoteWasActive)
        }
    }

    func currentRemoteActive() -> Bool {
        atomicLoad32(&remoteActive) != 0
    }

    func currentRemoteWasActive() -> Bool {
        atomicLoad32(&remoteWasActive) != 0
    }

    func setDrainWaiterRequested(_ requested: Bool) {
        atomicStore32(requested ? 1 : 0, to: &drainWaiterRequested)
    }

    func hasDrainWaiterRequested() -> Bool {
        atomicLoad32(&drainWaiterRequested) != 0
    }

    func beginDiagnostics(remoteActive: Bool) {
        endDiagnosticsAndWait()
        let write = atomicLoad64(&observationWriteIndex)
        atomicStore64(write, to: &observationReadIndex)
        atomicStore64(0, to: &droppedObservationCount)
        resetCounters()
        atomicStore32(remoteActive ? 1 : 0, to: &remoteWasActive)
        atomicStore32(1, to: &diagnosticsActive)
    }

    func endDiagnosticsAndWait() {
        atomicStore32(0, to: &diagnosticsActive)
        while atomicLoad32(&diagnosticsRenderInFlight) != 0 {
            sched_yield()
        }
    }

    func beginRenderDiagnosticsIfActive() -> Bool {
        guard atomicLoad32(&diagnosticsActive) != 0 else { return false }
        _ = OSAtomicAdd32Barrier(1, &diagnosticsRenderInFlight)
        guard atomicLoad32(&diagnosticsActive) != 0 else {
            _ = OSAtomicAdd32Barrier(-1, &diagnosticsRenderInFlight)
            return false
        }
        return true
    }

    func endRenderDiagnostics() {
        _ = OSAtomicAdd32Barrier(-1, &diagnosticsRenderInFlight)
    }

    func recordRender(
        _ accounting: AudioPipeRenderAccounting,
        requestedFrames: Int,
        readResult: AudioPipePCMReadResult,
        remoteWasActive: Bool,
        timestampNanoseconds: UInt64
    ) {
        let marker = marker(for: accounting.state)
        switch accounting.state {
        case .reserveWait:
            break
        case .activeRemote:
            atomicAdd64(
                Int64(accounting.activeRequestedFrames),
                to: &renderRequestedFrames
            )
            atomicAdd64(
                Int64(accounting.activeFilledFrames),
                to: &renderFilledFrames
            )
            atomicAdd64(
                Int64(accounting.activeUnderrunFrames),
                to: &renderUnfilledFrames
            )
            if accounting.activeUnderrunCallbacks > 0 {
                atomicAdd64(
                    Int64(accounting.activeUnderrunCallbacks),
                    to: &underrunCallbackCount
                )
                atomicMax64(
                    Int64(accounting.activeUnderrunFrames),
                    to: &maxUnderrunFrames
                )
            }
            _ = OSAtomicAdd64Barrier(1, &renderCallbackCount)
        case .tailDrain:
            atomicAdd64(
                Int64(accounting.tailRenderedFrames),
                to: &tailRenderedFrames
            )
            atomicAdd64(
                Int64(accounting.tailEmptyCallbacks),
                to: &tailEmptyCallbackCount
            )
        case .idle:
            atomicAdd64(
                Int64(accounting.idleRenderCallbacks),
                to: &idleRenderCallbackCount
            )
        }

        if remoteWasActive, readResult.remoteFramesConsumed > 0 {
            atomicAdd64(
                Int64(readResult.remoteFramesConsumed),
                to: &renderedRemoteFrames
            )
            let timestamp = Int64(
                min(timestampNanoseconds, UInt64(Int64.max))
            )
            atomicStoreFirstTimestamp(
                timestamp,
                to: &firstRemoteRenderedMonotonicNanoseconds
            )
            atomicStore64(
                timestamp,
                to: &lastRemoteRenderedMonotonicNanoseconds
            )
            _ = OSAtomicAdd64Barrier(0, &firstRemoteRenderedMonotonicNanoseconds)
        }

        recordQueueDepth(readResult.remoteQueueDepthAfterFrames)
        let observation = AudioPipeRealtimeObservation(
            kind: .render,
            timestampNanoseconds: timestampNanoseconds,
            requestedFrames: requestedFrames,
            filledFrames: readResult.filledFrames,
            unfilledFrames: readResult.unfilledFrames,
            queueDepthBeforeFrames: readResult.remoteQueueDepthBeforeFrames,
            queueDepthAfterFrames: readResult.remoteQueueDepthAfterFrames,
            byteOrSampleCount: readResult.filledFrames,
            marker: marker
        )
        enqueue(observation)

        if accounting.activeUnderrunFrames > 0 || accounting.tailEmptyCallbacks > 0 {
            enqueue(
                AudioPipeRealtimeObservation(
                    kind: .queueStarvation,
                    timestampNanoseconds: timestampNanoseconds,
                    requestedFrames: requestedFrames,
                    filledFrames: readResult.filledFrames,
                    unfilledFrames: readResult.unfilledFrames,
                    queueDepthBeforeFrames: readResult.remoteQueueDepthBeforeFrames,
                    queueDepthAfterFrames: readResult.remoteQueueDepthAfterFrames,
                    byteOrSampleCount: accounting.activeUnderrunFrames,
                    marker: marker
                )
            )
        }

        let remoteIsActive = atomicLoad32(&remoteActive) != 0
        if remoteIsActive {
            if accounting.activeUnderrunFrames > 0 {
                atomicStore32(0, to: &stableRenderIntervals)
            } else if atomicLoad64(&firstRemoteRenderedMonotonicNanoseconds) > 0,
                      atomicLoad64(&playoutStableMonotonicNanoseconds) == 0 {
                let intervals = OSAtomicAdd32Barrier(1, &stableRenderIntervals)
                if intervals >= 3 {
                    atomicStoreFirstTimestamp(
                        Int64(min(timestampNanoseconds, UInt64(Int64.max))),
                        to: &playoutStableMonotonicNanoseconds
                    )
                }
            }
        }
    }

    func recordMeter(filledFrames: Int, peak: Float) {
        _ = OSAtomicAdd64Barrier(1, &meterRenderCallbackCount)
        _ = OSAtomicAdd64Barrier(Int64(max(0, filledFrames)), &meterRenderedFrames)
        let bits = Int32(bitPattern: peak.bitPattern)
        while true {
            let oldBits = OSAtomicAdd32Barrier(0, &meterRenderedPeakBits)
            guard bits > oldBits else { return }
            if OSAtomicCompareAndSwap32Barrier(oldBits, bits, &meterRenderedPeakBits) {
                return
            }
        }
    }

    func takeMeterSnapshot(reset: Bool) -> AudioPipeRealtimeMeterSnapshot {
        let callbacks = reset
            ? atomicSwap64(0, at: &meterRenderCallbackCount)
            : atomicLoad64(&meterRenderCallbackCount)
        let frames = reset
            ? atomicSwap64(0, at: &meterRenderedFrames)
            : atomicLoad64(&meterRenderedFrames)
        let peakBits: Int32
        if reset {
            peakBits = atomicSwap32(0, at: &meterRenderedPeakBits)
        } else {
            peakBits = atomicLoad32(&meterRenderedPeakBits)
        }
        return AudioPipeRealtimeMeterSnapshot(
            renderCallbackCount: safeInt(callbacks),
            renderedFrames: safeInt(frames),
            renderedPeak: Float(bitPattern: UInt32(bitPattern: peakBits))
        )
    }

    func snapshot(reset: Bool) -> AudioPipeRealtimeCounterSnapshot {
        let result = AudioPipeRealtimeCounterSnapshot(
            renderCallbackCount: safeInt(atomicLoad64(&renderCallbackCount)),
            renderRequestedFrames: safeInt(atomicLoad64(&renderRequestedFrames)),
            renderFilledFrames: safeInt(atomicLoad64(&renderFilledFrames)),
            renderUnfilledFrames: safeInt(atomicLoad64(&renderUnfilledFrames)),
            underrunCallbackCount: safeInt(atomicLoad64(&underrunCallbackCount)),
            maxUnderrunFrames: safeInt(atomicLoad64(&maxUnderrunFrames)),
            renderedRemoteFrames: safeInt(atomicLoad64(&renderedRemoteFrames)),
            minQueueDepthFrames: optionalSafeInt(atomicLoad64(&minQueueDepthFrames)),
            maxQueueDepthFrames: safeInt(atomicLoad64(&maxQueueDepthFrames)),
            tailRenderedFrames: safeInt(atomicLoad64(&tailRenderedFrames)),
            tailEmptyCallbackCount: safeInt(atomicLoad64(&tailEmptyCallbackCount)),
            idleRenderCallbackCount: safeInt(atomicLoad64(&idleRenderCallbackCount)),
            lastRemoteRenderedMonotonicNanoseconds: optionalTimestamp(
                atomicLoad64(&lastRemoteRenderedMonotonicNanoseconds)
            )
        )
        if reset {
            resetCounters()
        }
        return result
    }

    func markers(reset: Bool = true) -> AudioPipeRealtimeMarkerSnapshot {
        let result = AudioPipeRealtimeMarkerSnapshot(
            firstRemoteRenderedMonotonicNanoseconds: optionalTimestamp(
                reset
                    ? atomicSwap64(0, at: &firstRemoteRenderedMonotonicNanoseconds)
                    : atomicLoad64(&firstRemoteRenderedMonotonicNanoseconds)
            ),
            playoutStableMonotonicNanoseconds: optionalTimestamp(
                reset
                    ? atomicSwap64(0, at: &playoutStableMonotonicNanoseconds)
                    : atomicLoad64(&playoutStableMonotonicNanoseconds)
            ),
            droppedObservationCount: safeInt(
                reset
                    ? atomicSwap64(0, at: &droppedObservationCount)
                    : atomicLoad64(&droppedObservationCount)
            )
        )
        if reset {
            atomicStore32(0, to: &stableRenderIntervals)
        }
        return result
    }

    func drainObservations(_ consume: (AudioPipeRealtimeObservation) -> Void) {
        var read = atomicLoad64(&observationReadIndex)
        let write = atomicLoad64(&observationWriteIndex)
        while read < write {
            consume(observations[Int(read % Int64(Self.observationCapacity))])
            read += 1
        }
        atomicStore64(read, to: &observationReadIndex)
    }

    private func enqueue(_ observation: AudioPipeRealtimeObservation) {
        let write = atomicLoad64(&observationWriteIndex)
        let read = atomicLoad64(&observationReadIndex)
        guard write - read < Int64(Self.observationCapacity) else {
            _ = OSAtomicAdd64Barrier(1, &droppedObservationCount)
            return
        }
        observations[Int(write % Int64(Self.observationCapacity))] = observation
        atomicStore64(write + 1, to: &observationWriteIndex)
    }

    private func recordQueueDepth(_ depth: Int) {
        atomicMin64(Int64(max(0, depth)), to: &minQueueDepthFrames)
        atomicMax64(Int64(max(0, depth)), to: &maxQueueDepthFrames)
    }

    private func resetCounters() {
        atomicStore64(0, to: &renderCallbackCount)
        atomicStore64(0, to: &renderRequestedFrames)
        atomicStore64(0, to: &renderFilledFrames)
        atomicStore64(0, to: &renderUnfilledFrames)
        atomicStore64(0, to: &underrunCallbackCount)
        atomicStore64(0, to: &maxUnderrunFrames)
        atomicStore64(0, to: &renderedRemoteFrames)
        atomicStore64(Int64.max, to: &minQueueDepthFrames)
        atomicStore64(0, to: &maxQueueDepthFrames)
        atomicStore64(0, to: &tailRenderedFrames)
        atomicStore64(0, to: &tailEmptyCallbackCount)
        atomicStore64(0, to: &idleRenderCallbackCount)
        atomicStore64(0, to: &lastRemoteRenderedMonotonicNanoseconds)
        atomicStore64(0, to: &firstRemoteRenderedMonotonicNanoseconds)
        atomicStore64(0, to: &playoutStableMonotonicNanoseconds)
        atomicStore32(0, to: &stableRenderIntervals)
        atomicStore64(0, to: &meterRenderCallbackCount)
        atomicStore64(0, to: &meterRenderedFrames)
        atomicStore32(0, to: &meterRenderedPeakBits)
    }

    private func marker(for state: AudioPipeRenderState) -> Int32 {
        switch state {
        case .reserveWait: return 4
        case .activeRemote: return 0
        case .tailDrain: return 1
        case .idle: return 2
        }
    }

    private func atomicLoad32(_ value: UnsafeMutablePointer<Int32>) -> Int32 {
        OSAtomicAdd32Barrier(0, value)
    }

    private func atomicLoad64(_ value: UnsafeMutablePointer<Int64>) -> Int64 {
        OSAtomicAdd64Barrier(0, value)
    }

    private func atomicStore32(_ newValue: Int32, to value: UnsafeMutablePointer<Int32>) {
        while true {
            let oldValue = atomicLoad32(value)
            if OSAtomicCompareAndSwap32Barrier(oldValue, newValue, value) { return }
        }
    }

    private func atomicStore64(_ newValue: Int64, to value: UnsafeMutablePointer<Int64>) {
        while true {
            let oldValue = atomicLoad64(value)
            if OSAtomicCompareAndSwap64Barrier(oldValue, newValue, value) { return }
        }
    }

    private func atomicSwap64(
        _ newValue: Int64,
        at value: UnsafeMutablePointer<Int64>
    ) -> Int64 {
        while true {
            let oldValue = atomicLoad64(value)
            if OSAtomicCompareAndSwap64Barrier(oldValue, newValue, value) {
                return oldValue
            }
        }
    }

    private func atomicSwap32(
        _ newValue: Int32,
        at value: UnsafeMutablePointer<Int32>
    ) -> Int32 {
        while true {
            let oldValue = atomicLoad32(value)
            if OSAtomicCompareAndSwap32Barrier(oldValue, newValue, value) {
                return oldValue
            }
        }
    }

    private func atomicAdd64(_ delta: Int64, to value: UnsafeMutablePointer<Int64>) {
        _ = OSAtomicAdd64Barrier(delta, value)
    }

    private func atomicMax64(_ candidate: Int64, to value: UnsafeMutablePointer<Int64>) {
        while true {
            let oldValue = atomicLoad64(value)
            guard candidate > oldValue else { return }
            if OSAtomicCompareAndSwap64Barrier(oldValue, candidate, value) { return }
        }
    }

    private func atomicMin64(_ candidate: Int64, to value: UnsafeMutablePointer<Int64>) {
        while true {
            let oldValue = atomicLoad64(value)
            guard candidate < oldValue else { return }
            if OSAtomicCompareAndSwap64Barrier(oldValue, candidate, value) { return }
        }
    }

    private func atomicStoreFirstTimestamp(
        _ timestamp: Int64,
        to value: UnsafeMutablePointer<Int64>
    ) {
        _ = OSAtomicCompareAndSwap64Barrier(0, timestamp, value)
    }

    private func optionalTimestamp(_ value: Int64) -> UInt64? {
        value > 0 ? UInt64(value) : nil
    }

    private func safeInt(_ value: Int64) -> Int {
        Int(max(0, min(value, Int64(Int.max))))
    }

    private func optionalSafeInt(_ value: Int64) -> Int? {
        value == Int64.max ? nil : safeInt(value)
    }
}
