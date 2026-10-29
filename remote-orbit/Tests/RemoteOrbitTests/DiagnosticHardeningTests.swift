import Foundation
import XCTest
@testable import RemoteOrbit

final class DiagnosticHardeningTests: XCTestCase {
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

    func testRuntimeHealthIsStructuredAndIndependentOfOrdinaryLogging() throws {
        let authority = HardeningCapturingAuthority()
        let registry = DiagnosticRuntimeHealthRegistry()
        registry.setBool("hid_manager_running", true)
        registry.setString("selected_input_identity", "uid:test-input")
        let service = DiagnosticRuntimeHealthService(authority: authority, registry: registry)
        let previous = AppStorage.loggingEnabled
        defer { AppStorage.loggingEnabled = previous }
        AppStorage.loggingEnabled = false

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
