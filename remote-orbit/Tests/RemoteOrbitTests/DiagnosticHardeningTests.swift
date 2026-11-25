import Foundation
import XCTest
@testable import RemoteOrbit

final class DiagnosticHardeningTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
    }

    override func tearDown() {
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
        super.tearDown()
    }

    func testAttemptCorrelationCoversStagesAndResetsForNextAttempt() throws {
        let authority = HardeningCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        let health = DiagnosticRuntimeHealthService(authority: authority, registry: registry)
        var now: UInt64 = 1_000
        let diagnostics = VoiceAttemptDiagnostics(
            authority: authority,
            registry: registry,
            health: health,
            clock: { now }
        )

        let first = diagnostics.beginPhysicalAttempt(timestampNanoseconds: now)
        now = 2_000
        _ = diagnostics.ensureSession(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        diagnostics.stage("MAPPING_RESOLVED", state: ["mapping_verified": .bool(true)])
        diagnostics.stage("HOLD_CONFIRMED")
        diagnostics.stage("AUDIO_START")
        diagnostics.end(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

        let second = diagnostics.beginPhysicalAttempt(timestampNanoseconds: 3_000)
        XCTAssertNotEqual(first, second)
        let stageIDs = authority.inputs
            .filter { $0.eventType == "voice.attempt.stage" }
            .compactMap { input -> String? in
                guard case .string(let id) = input.payload["voice_attempt_id"] else { return nil }
                return id
            }
        XCTAssertTrue(stageIDs.contains(first.uuidString))
        XCTAssertTrue(stageIDs.contains(second.uuidString))
        XCTAssertFalse(stageIDs.contains("/"))
    }

    func testWatchdogDoesNotFailBeforeLongClassificationAndHasNoRetrySideEffect() throws {
        let authority = HardeningCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        var now: UInt64 = 0
        let watchdog = VoiceStartWatchdog(
            authority: authority,
            registry: registry,
            clock: { now }
        )
        let attemptID = UUID().uuidString
        watchdog.begin(attemptID: attemptID, timestampNanoseconds: now)
        now = 299_000_000
        watchdog.evaluate(at: now)
        XCTAssertTrue(authority.inputs.isEmpty)
        now = 2_000_000_000
        watchdog.evaluate(at: now)
        XCTAssertTrue(authority.inputs.isEmpty)

        watchdog.holdConfirmed(
            attemptID: attemptID,
            sessionID: "session-1",
            timestampNanoseconds: now,
            state: ["mapping_verified": .bool(true)]
        )
        now += VoiceStartWatchdog.stallAfterNanoseconds
        watchdog.evaluate(at: now)
        now += VoiceStartWatchdog.failureAfterNanoseconds
        watchdog.evaluate(at: now)
        watchdog.evaluate(at: now)

        XCTAssertEqual(authority.inputs.map(\.eventType), [
            "voice.start.watchdog",
            "voice.start.watchdog",
            "voice.failure.classified",
        ])
        XCTAssertEqual(
            authority.inputs.filter { $0.eventType == "voice.failure.classified" }.count,
            1
        )
    }

    func testAUDIO_START_MISSINGProductionPathEmitsBoundedFailure() throws {
        let authority = HardeningCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        let health = DiagnosticRuntimeHealthService(authority: authority, registry: registry)
        var now: UInt64 = 1_000
        let diagnostics = VoiceAttemptDiagnostics(
            authority: authority,
            registry: registry,
            health: health,
            clock: { now }
        )
        let sessionID = UUID()
        let attemptID = diagnostics.ensureSession(sessionID)
        diagnostics.stage("HOLD_CONFIRMED", sessionID: sessionID)
        now += VoiceStartWatchdog.failureAfterNanoseconds
        diagnostics.evaluateWatchdogForTesting(at: now)

        let watchdog = try XCTUnwrap(authority.inputs.first { $0.eventType == "voice.start.watchdog" })
        XCTAssertEqual(watchdog.payload["missing_stage"], .string("AUDIO_START"))
        let failure = try XCTUnwrap(authority.inputs.first { $0.eventType == "voice.failure.classified" })
        XCTAssertEqual(failure.payload["reason"], .string("AUDIO_START_MISSING"))
        XCTAssertEqual(failure.correlationID, attemptID.uuidString)
    }

    func testAUDIO_FIRST_MISSINGAfterAUDIO_STARTEmitsDistinctFailure() throws {
        let authority = HardeningCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        let health = DiagnosticRuntimeHealthService(authority: authority, registry: registry)
        var now: UInt64 = 2_000
        let diagnostics = VoiceAttemptDiagnostics(
            authority: authority,
            registry: registry,
            health: health,
            clock: { now }
        )
        let sessionID = UUID()
        _ = diagnostics.ensureSession(sessionID)
        diagnostics.stage("HOLD_CONFIRMED", sessionID: sessionID)
        diagnostics.stage("AUDIO_START", sessionID: sessionID)
        now += VoiceStartWatchdog.stallAfterNanoseconds
        diagnostics.evaluateWatchdogForTesting(at: now)
        now += VoiceStartWatchdog.failureAfterNanoseconds
        diagnostics.evaluateWatchdogForTesting(at: now)

        let watchdogEvents = authority.inputs.filter { $0.eventType == "voice.start.watchdog" }
        XCTAssertEqual(watchdogEvents.count, 2)
        XCTAssertEqual(watchdogEvents.last?.payload["missing_stage"], .string("AUDIO_FIRST"))
        let failure = try XCTUnwrap(authority.inputs.last { $0.eventType == "voice.failure.classified" })
        XCTAssertEqual(failure.payload["reason"], .string("AUDIO_FIRST_MISSING"))
    }

    func testAUDIO_FIRSTArrivalCompletesWatchWithoutFailureOrRetry() throws {
        let authority = HardeningCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        let health = DiagnosticRuntimeHealthService(authority: authority, registry: registry)
        var now: UInt64 = 3_000
        let diagnostics = VoiceAttemptDiagnostics(
            authority: authority,
            registry: registry,
            health: health,
            clock: { now }
        )
        let sessionID = UUID()
        _ = diagnostics.ensureSession(sessionID)
        diagnostics.stage("HOLD_CONFIRMED", sessionID: sessionID)
        diagnostics.stage("AUDIO_START", sessionID: sessionID)
        diagnostics.stage("AUDIO_FIRST", sessionID: sessionID)
        now += VoiceStartWatchdog.failureAfterNanoseconds * 2
        diagnostics.evaluateWatchdogForTesting(at: now)

        XCTAssertFalse(authority.inputs.contains { $0.eventType == "voice.failure.classified" })
        XCTAssertFalse(authority.inputs.contains { $0.eventType == "voice.start.watchdog" })
    }

    func testRuntimeHealthIsStructuredAndIndependentOfOrdinaryLogging() throws {
        let authority = HardeningCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        registry.setBool("hid_manager_running", true)
        registry.setString("selected_input_identity", "uid:test-input")
        let service = DiagnosticRuntimeHealthService(authority: authority, registry: registry)
        let previous = AppStorage.loggingEnabled
        defer { AppStorage.loggingEnabled = previous }
        AppStorage.loggingEnabled = false
        DiagnosticsRuntimeGate.shared.configureForTesting(
            loggingEnabled: false,
            environmentOverrideEnabled: true
        )

        service.emitHeartbeat()

        let event = try XCTUnwrap(authority.inputs.first)
        XCTAssertEqual(event.eventType, "voice.runtime.health")
        XCTAssertEqual(event.payload["cadence"], .string("idle_30s"))
        guard case .object(let state) = event.payload["state"] else {
            return XCTFail("health state must be structured")
        }
        XCTAssertEqual(state["hid_manager_running"], .bool(true))
        XCTAssertEqual(state["selected_input_identity"], .string("uid:test-input"))
    }

    func testRemoteActiveRemainsTrueWhenRemoteQueueIsEmpty() {
        let registry = DiagnosticRuntimeHealthRegistry()
        let snapshot = AudioPipeDiagnosticsSnapshot(
            remoteActive: true,
            renderCallbackCount: 1,
            renderRequestedFrames: 480,
            renderFilledFrames: 0,
            renderUnfilledFrames: 480,
            underrunCallbackCount: 1,
            maxUnderrunFrames: 480,
            currentQueueDepthFrames: 0,
            audioQueueDepthFrames: 0,
            pendingRemoteFrames: 0,
            submittedRemoteFrames: 1,
            renderedRemoteFrames: 0,
            minQueueDepthFrames: 0,
            maxQueueDepthFrames: 0,
            overflowDroppedFrames: 0,
            compactionCount: 0,
            tailRenderedFrames: 0,
            tailEmptyCallbackCount: 0,
            idleRenderCallbackCount: 0,
            sampleRate: 48_000
        )
        registry.updateAudioPipe(snapshot)
        let state = registry.snapshot()
        XCTAssertEqual(state["audio_pipe_remote_active"], .bool(true))
        XCTAssertEqual(state["audio_pipe_queue_has_remote_frames"], .bool(false))
    }

    func testReserveEvidenceAppearsInExistingRuntimeHealthAuthority() {
        let registry = DiagnosticRuntimeHealthRegistry()
        let reserve = AudioPipePlayoutReserveSnapshot(
            candidate: .milliseconds45,
            configuredReserveFrames: 2_160,
            selectedDefaultCandidate: .milliseconds45,
            state: .started,
            startDepthFrames: 2_400,
            waitDurationNanoseconds: 45_000_000,
            startReason: .threshold
        )
        let snapshot = AudioPipeDiagnosticsSnapshot(
            renderCallbackCount: 0,
            renderRequestedFrames: 0,
            renderFilledFrames: 0,
            renderUnfilledFrames: 0,
            underrunCallbackCount: 0,
            maxUnderrunFrames: 0,
            currentQueueDepthFrames: 0,
            audioQueueDepthFrames: 0,
            pendingRemoteFrames: 0,
            submittedRemoteFrames: 0,
            renderedRemoteFrames: 0,
            minQueueDepthFrames: 0,
            maxQueueDepthFrames: 0,
            overflowDroppedFrames: 0,
            compactionCount: 0,
            tailRenderedFrames: 0,
            tailEmptyCallbackCount: 0,
            idleRenderCallbackCount: 0,
            sampleRate: 48_000,
            reserve: reserve
        )

        registry.updateAudioPipe(snapshot)

        let state = registry.snapshot()
        XCTAssertEqual(state["audio_pipe_reserve_ms"], .unsignedInteger(45))
        XCTAssertEqual(state["audio_pipe_reserve_frames"], .unsignedInteger(2_160))
        XCTAssertEqual(state["audio_pipe_reserve_state"], .string("started"))
        XCTAssertEqual(state["audio_pipe_reserve_start_depth_frames"], .unsignedInteger(2_400))
        XCTAssertEqual(state["audio_pipe_reserve_start_reason"], .string("threshold"))
    }

    func testSelectedInputIdentityIsRefreshedAfterRemoteVoiceSelection() {
        let registry = DiagnosticRuntimeHealthRegistry()
        registry.recordSelectedInputIdentity("uid:remoteorbit-after-selection")
        XCTAssertEqual(
            registry.snapshot()["selected_input_identity"],
            .string("uid:remoteorbit-after-selection")
        )
    }

    func testOutputBoundaryUsesOnlyTruthfulNonzeroCallbackEvidence() throws {
        let authority = HardeningCapturingAuthority()
        var summary = LongTermVoiceSessionSummary(sessionID: "session-1", captureID: "capture-1")
        summary.audioStartTimestampNanoseconds = 10
        summary.renderedFrames = 480
        let trace = FixedCapacityObservationTraceSnapshot(
            front: [LongTermObservationPoint(
                timestampNanoseconds: 20,
                kind: .render,
                requestedFrames: 480,
                filledFrames: 480,
                unfilledFrames: 0,
                queueDepthFrames: 0,
                byteOrSampleCount: 480,
                marker: .active
            )],
            recent: [],
            incident: [],
            incidentAnchor: nil,
            droppedObservationCount: 0,
            overwrittenObservationCount: 0
        )
        DiagnosticOutputBoundaryClock.shared.reset()
        DiagnosticHardeningSessionEmitter.emit(summary: summary, trace: trace, authority: authority)
        var output = try XCTUnwrap(authority.inputs.first { $0.eventType == "voice.output.boundary" })
        XCTAssertEqual(output.payload["first_render_timestamp_ns"], .unsignedInteger(20))
        XCTAssertEqual(output.payload["first_nonzero_output_timestamp_ns"], .unsignedInteger(0))
        XCTAssertEqual(output.payload["nonzero_output_observed"], .bool(false))

        authority.inputs.removeAll()
        DiagnosticOutputBoundaryClock.shared.record(timestampNanoseconds: 30)
        DiagnosticHardeningSessionEmitter.emit(summary: summary, trace: trace, authority: authority)
        output = try XCTUnwrap(authority.inputs.first { $0.eventType == "voice.output.boundary" })
        XCTAssertEqual(output.payload["first_nonzero_output_timestamp_ns"], .unsignedInteger(30))
        XCTAssertEqual(output.payload["nonzero_output_observed"], .bool(true))
    }

    func testDiagnosticMeterIsOneSecondActiveAndThirtySecondIdle() {
        XCTAssertTrue(
            DiagnosticAudioMeterCadence.shouldEmit(
                mode: "remote",
                now: 1,
                lastIdleEmission: 0
            )
        )
        XCTAssertFalse(
            DiagnosticAudioMeterCadence.shouldEmit(
                mode: "idle",
                now: 1,
                lastIdleEmission: 0
            )
        )
        XCTAssertTrue(
            DiagnosticAudioMeterCadence.shouldEmit(
                mode: "idle",
                now: 30,
                lastIdleEmission: 0
            )
        )
    }

    func testUnderrunEpisodesSeparateStartupActiveAndTail() {
        let points = [
            LongTermObservationPoint(timestampNanoseconds: 10, kind: .queueStarvation, requestedFrames: 10, filledFrames: 0, unfilledFrames: 10, queueDepthFrames: 0, byteOrSampleCount: 10, marker: .active),
            LongTermObservationPoint(timestampNanoseconds: 20, kind: .pcmSubmitted, requestedFrames: 0, filledFrames: 0, unfilledFrames: 0, queueDepthFrames: 4, byteOrSampleCount: 4, marker: .active),
            LongTermObservationPoint(timestampNanoseconds: 30, kind: .queueStarvation, requestedFrames: 10, filledFrames: 0, unfilledFrames: 10, queueDepthFrames: 0, byteOrSampleCount: 10, marker: .active),
            LongTermObservationPoint(timestampNanoseconds: 40, kind: .queueStarvation, requestedFrames: 10, filledFrames: 0, unfilledFrames: 10, queueDepthFrames: 0, byteOrSampleCount: 10, marker: .tail),
        ]

        let episodes = DiagnosticUnderrunEpisodeBuilder.build(points)

        XCTAssertEqual(episodes.map(\.lifecyclePhase), ["startup", "active", "tail"])
        XCTAssertEqual(episodes.map(\.missingFrames), [10, 10, 10])
        XCTAssertEqual(episodes[0].eventSpanDurationNanoseconds, 0)
        XCTAssertEqual(episodes[0].estimatedMissingAudioDurationNanoseconds, 208_333)
    }

    func testFrozenIncidentRetainsEpisodeAfterRecentRingOverwrite() {
        let coordinator = LongTermIncidentCoordinator()
        var trace = FixedCapacityObservationTrace(
            frontCapacity: 1,
            recentCapacity: 2,
            incidentCapacity: 8,
            incidentCoordinator: coordinator,
            incidentProducer: .service
        )
        coordinator.beginCaptureIfNeeded()
        trace.append(LongTermObservationPoint(
            timestampNanoseconds: 1,
            kind: .pcmSubmitted,
            requestedFrames: 10,
            filledFrames: 10,
            unfilledFrames: 0,
            queueDepthFrames: 10,
            byteOrSampleCount: 10,
            marker: .active,
            sequence: 1,
            source: "voice_service"
        ))
        trace.append(LongTermObservationPoint(
            timestampNanoseconds: 2,
            kind: .queueStarvation,
            requestedFrames: 10,
            filledFrames: 0,
            unfilledFrames: 10,
            queueDepthFrames: 0,
            byteOrSampleCount: 10,
            marker: .active,
            sequence: 2,
            source: "voice_service"
        ))
        coordinator.trigger(producer: .service, kind: .renderStarvation, timestampNanoseconds: 2)
        trace.synchronizeIncidentWithCoordinator()
        for sequence in 3...8 {
            trace.append(LongTermObservationPoint(
                timestampNanoseconds: UInt64(sequence),
                kind: .render,
                requestedFrames: 10,
                filledFrames: 10,
                unfilledFrames: 0,
                queueDepthFrames: 10,
                byteOrSampleCount: 10,
                marker: .active,
                sequence: UInt64(sequence),
                source: "voice_service"
            ))
        }
        let episodes = DiagnosticUnderrunEpisodeBuilder.build(trace.snapshot().allIncludingIncident)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.missingFrames, 10)
    }

    func testStructuredHardeningPayloadsDoNotContainTextAudioOrPaths() throws {
        let authority = HardeningCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        let health = DiagnosticRuntimeHealthService(authority: authority, registry: registry)
        let diagnostics = VoiceAttemptDiagnostics(authority: authority, registry: registry, health: health)
        _ = diagnostics.beginPhysicalAttempt(state: ["reason": .string("bounded_failure")])

        for input in authority.inputs {
            let data = try JSONEncoder().encode(input.payload)
            let json = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(json.contains("dictated"))
            XCTAssertFalse(json.contains("/tmp"))
            XCTAssertFalse(json.contains("pcm"))
        }
    }

    func testRollingTextLogWriterTracksUncachedSizeAndRotatesToSegmentOne() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteOrbitRollingLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("RemoteOrbit.log")
        let writer = RollingTextLogWriter(
            fileURL: logURL,
            maximumBytes: 120,
            queueLabel: "com.remoteorbit.test.rolling-log.\(UUID().uuidString)"
        )

        writer.write(String(repeating: "A", count: 60))
        writer.flush()
        let firstSize = writer.byteSize
        XCTAssertGreaterThan(firstSize, 60)

        writer.write(String(repeating: "B", count: 80))
        writer.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: writer.rotatedFileURL.path))
        let totalSize = writer.byteSize
        XCTAssertGreaterThan(totalSize, firstSize)

        writer.clear { false }
        XCTAssertEqual(writer.byteSize, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.rotatedFileURL.path))
    }
}

private final class HardeningCapturingAuthority: DiagnosticAuthority {
    var droppedEventCount: UInt64 = 0
    var writeFailureCount: UInt64 = 0
    var inputs: [DiagnosticEventInput] = []

    func emit(_ input: DiagnosticEventInput) { inputs.append(input) }

    func query(_ filter: DiagnosticQueryFilter) throws -> DiagnosticQueryPage {
        DiagnosticQueryPage(schemaVersion: DiagnosticEvent.currentSchemaVersion, events: [], nextCursor: nil)
    }

    func snapshot(_ filter: DiagnosticQueryFilter) throws -> Data {
        try JSONEncoder().encode(
            DiagnosticQueryPage(schemaVersion: DiagnosticEvent.currentSchemaVersion, events: [], nextCursor: nil)
        )
    }
}
