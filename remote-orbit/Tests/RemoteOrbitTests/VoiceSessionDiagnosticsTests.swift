import XCTest
@testable import RemoteOrbit

final class VoiceSessionDiagnosticsTests: XCTestCase {
    func testEventsUseStrictPerSessionSequenceAndMonotonicTiming() {
        var lines: [String] = []
        let diagnostics = VoiceSessionDiagnostics(
            eventSink: { lines.append($0) },
            summaryGrace: 0
        )
        let session = UUID()

        XCTAssertTrue(
            diagnostics.begin(
                sessionID: session,
                legacySafe: true,
                shortBindingMode: "default",
                bypassShortClassification: false,
                targetBundleID: "com.example.target"
            )
        )
        diagnostics.record(sessionID: session, category: .session, event: "HOLD_CONFIRMED")
        diagnostics.markFirstPCM(sessionID: session, stage: .decode)
        diagnostics.markFirstPCM(sessionID: session, stage: .feed)

        let events = diagnostics.events(for: session)
        XCTAssertEqual(events.map(\.sequence), Array(1...events.count))
        XCTAssertTrue(zip(events, events.dropFirst()).allSatisfy { $0.0.uptime <= $0.1.uptime })
        XCTAssertTrue(events.allSatisfy { $0.elapsedMilliseconds >= 0 })
        XCTAssertTrue(lines.allSatisfy { $0.contains("session=\(session.uuidString)") })
    }

    func testOptionDownBeforeFirstPCMRecordsInvariantViolation() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.record(sessionID: session, category: .session, event: "HOLD_CONFIRMED")

        diagnostics.recordOptionRequest(sessionID: session, direction: .down)

        XCTAssertTrue(
            diagnostics.events(for: session).contains {
                $0.event == "INVARIANT_VIOLATION"
                    && $0.fields["type"] == "option-down-before-first-pcm"
            }
        )
    }

    func testBalancedLongSessionProducesCompleteSummary() throws {
        var lines: [String] = []
        let diagnostics = VoiceSessionDiagnostics(
            eventSink: { lines.append($0) },
            summaryGrace: 0
        )
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: session, stage: .decode)
        diagnostics.markFirstPCM(sessionID: session, stage: .feed)
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        diagnostics.recordOptionRequest(sessionID: session, direction: .down)
        diagnostics.recordOptionRequest(sessionID: session, direction: .up)
        diagnostics.end(
            sessionID: session,
            completion: .normalDrain,
            lifecycle: .balanced
        )

        let summary = try XCTUnwrap(diagnostics.summary(for: session))
        XCTAssertEqual(summary.lifecycle, .balanced)
        XCTAssertEqual(summary.completion, .normalDrain)
        XCTAssertTrue(summary.firstPCM)
        XCTAssertEqual(summary.optionDownRequests, 1)
        XCTAssertEqual(summary.optionUpRequests, 1)
        XCTAssertEqual(summary.invariantViolations, 0)
        XCTAssertTrue(lines.contains { $0.contains("[SUMMARY]") && $0.contains("session=\(session.uuidString)") })
    }

    func testDuplicateDownAndUpWithoutDownAreRecordedAsInvariantViolations() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.record(sessionID: session, category: .session, event: "HOLD_CONFIRMED")

        diagnostics.recordOptionRequest(sessionID: session, direction: .down)
        diagnostics.recordOptionRequest(sessionID: session, direction: .down)
        diagnostics.recordOptionRequest(sessionID: session, direction: .up)
        diagnostics.recordOptionRequest(sessionID: session, direction: .up)

        let violations = diagnostics.events(for: session)
            .compactMap { $0.fields["type"] }
        XCTAssertTrue(violations.contains("option-down-before-first-pcm"))
        XCTAssertTrue(violations.contains("duplicate-option-down"))
        XCTAssertTrue(violations.contains("option-up-without-down"))
    }

    func testEndingWithOptionDownRecordsInvariantViolation() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        diagnostics.recordOptionRequest(sessionID: session, direction: .down)
        diagnostics.end(sessionID: session, completion: .abort, lifecycle: .aborted)

        XCTAssertTrue(
            diagnostics.events(for: session).contains {
                $0.fields["type"] == "session-ended-option-down"
            }
        )
    }

    func testUnsafeLegacyMappingBlocksWithoutStartingASession() {
        var lines: [String] = []
        let diagnostics = VoiceSessionDiagnostics(
            eventSink: { lines.append($0) },
            summaryGrace: 0
        )
        let attempted = UUID()

        XCTAssertFalse(diagnostics.begin(sessionID: attempted, legacySafe: false))
        XCTAssertTrue(lines.contains { $0.contains("event=VOICE_BLOCKED") })
        XCTAssertTrue(diagnostics.events(for: attempted).isEmpty)
    }

    func testStaleCallbackCannotMutateCurrentSession() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let first = UUID()
        let current = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: first, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: first, stage: .audioCallback)
        diagnostics.end(sessionID: first, completion: .normalDrain, lifecycle: .balanced)
        XCTAssertTrue(diagnostics.begin(sessionID: current, legacySafe: true))

        let before = diagnostics.events(for: current)
        diagnostics.recordStaleCallback(
            callback: "tail-completion",
            callbackSession: first,
            activeSession: current
        )
        let after = diagnostics.events(for: current)

        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(
            diagnostics.summary(for: current)?.optionDownRequests,
            before.filter { $0.event == "OPTION_DOWN_REQUEST" }.count
        )
        XCTAssertTrue(
            diagnostics.events(for: first).contains {
                $0.event == "STALE_CALLBACK_REJECTED"
                    && $0.fields["activeSession"] == current.uuidString
            }
        )
    }

    func testObservedOptionComponentsCorrelateToOneLogicalEdge() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        diagnostics.recordOptionRequest(sessionID: session, direction: .down)

        XCTAssertEqual(
            diagnostics.observeSyntheticOption(direction: .down, component: .flags),
            session
        )
        XCTAssertEqual(
            diagnostics.observeSyntheticOption(direction: .down, component: .key),
            session
        )
        XCTAssertEqual(diagnostics.summary(for: session)?.downFlagsObserved, 1)
        XCTAssertEqual(diagnostics.summary(for: session)?.downKeyObserved, 1)
        XCTAssertEqual(diagnostics.summary(for: session)?.optionDownRequests, 1)
    }

    func testExpiredOptionObservationIsUncorrelated() {
        var now: TimeInterval = 100
        var lines: [String] = []
        let diagnostics = VoiceSessionDiagnostics(
            eventSink: { lines.append($0) },
            summaryGrace: 0,
            clock: { now }
        )
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        diagnostics.recordOptionRequest(sessionID: session, direction: .down)

        now += 1.1
        XCTAssertNil(
            diagnostics.observeSyntheticOption(direction: .down, component: .flags)
        )
        XCTAssertTrue(lines.contains { $0.contains("uncorrelated=true") })
        XCTAssertEqual(diagnostics.summary(for: session)?.downFlagsObserved, 0)
    }

    func testObserverUnavailableIsReportedWithoutInvariantViolation() {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        diagnostics.setObserverAvailable(false)
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        diagnostics.recordOptionRequest(sessionID: session, direction: .down)
        diagnostics.recordOptionRequest(sessionID: session, direction: .up)
        diagnostics.end(sessionID: session, completion: .normalDrain, lifecycle: .balanced)

        XCTAssertEqual(
            diagnostics.summary(for: session)?.deliveryEvidence,
            "observer-unavailable"
        )
        XCTAssertEqual(diagnostics.summary(for: session)?.invariantViolations, 0)
    }

    func testHardwareOwnerSummaryDoesNotRequireSyntheticObserver() throws {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        diagnostics.recordOptionOwnerSelected(sessionID: session, owner: .hardware)
        diagnostics.recordHardwareOptionEdge(sessionID: session, direction: .down)
        diagnostics.recordHardwareOptionEdge(sessionID: session, direction: .up)
        diagnostics.recordHardwareOptionReplay(
            sessionID: session,
            downCount: 2,
            upCount: 2
        )
        diagnostics.end(
            sessionID: session,
            completion: .normalDrain,
            lifecycle: .balanced
        )

        let summary = try XCTUnwrap(diagnostics.summary(for: session))
        XCTAssertEqual(summary.optionOwner, .hardware)
        XCTAssertTrue(summary.hardwareDownSeen)
        XCTAssertTrue(summary.hardwareUpSeen)
        XCTAssertTrue(summary.hardwareReplayPerformed)
        XCTAssertEqual(summary.syntheticDownRequests, 0)
        XCTAssertEqual(summary.syntheticUpRequests, 0)
        XCTAssertEqual(summary.deliveryEvidence, "hardware-replay")
        XCTAssertEqual(summary.invariantViolations, 0)
    }

    func testSyntheticFallbackSummaryIncludesOwnerAndReason() throws {
        let diagnostics = VoiceSessionDiagnostics(summaryGrace: 0)
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        diagnostics.recordOptionOwnerSelected(
            sessionID: session,
            owner: .syntheticFallback,
            fallbackReason: "physical-option-copy-failed"
        )
        diagnostics.recordOptionRequest(sessionID: session, direction: .down)
        diagnostics.recordOptionRequest(sessionID: session, direction: .up)
        diagnostics.recordLateHardwareOptionSuppressed(
            sessionID: session,
            direction: .down
        )
        diagnostics.end(
            sessionID: session,
            completion: .shortTap,
            lifecycle: .balanced
        )

        let summary = try XCTUnwrap(diagnostics.summary(for: session))
        XCTAssertEqual(summary.optionOwner, .syntheticFallback)
        XCTAssertEqual(summary.fallbackReason, "physical-option-copy-failed")
        XCTAssertEqual(summary.syntheticDownRequests, 1)
        XCTAssertEqual(summary.syntheticUpRequests, 1)
        XCTAssertTrue(summary.lateHardwareSuppressed)
    }

    func testRemoteF5MappingDiagnosticRecordsOwnerSelection() {
        var lines: [String] = []
        let diagnostics = VoiceSessionDiagnostics(
            eventSink: { lines.append($0) },
            summaryGrace: 0
        )

        diagnostics.recordRemoteF5Mapping(enabled: true, success: true)
        diagnostics.recordRemoteF5Mapping(enabled: true, success: false)

        XCTAssertTrue(lines.contains {
            $0.contains("event=REMOTE_F5_HID_MAPPING")
                && $0.contains("enabled=true")
                && $0.contains("owner=hardware")
        })
        XCTAssertTrue(lines.contains {
            $0.contains("event=REMOTE_F5_HID_MAPPING")
                && $0.contains("enabled=true")
                && $0.contains("owner=synthetic_fallback")
        })
    }

    func testCanonicalLongSessionProducesAnAuditableSampleTimeline() {
        var lines: [String] = []
        let diagnostics = VoiceSessionDiagnostics(
            eventSink: { lines.append($0) },
            summaryGrace: 0
        )
        let session = UUID()
        XCTAssertTrue(diagnostics.begin(sessionID: session, legacySafe: true))
        diagnostics.record(sessionID: session, category: .hid, event: "VOICE_DOWN_PHYSICAL", fields: ["source": "raw-hid"])
        diagnostics.record(sessionID: session, category: .session, event: "HOLD_CONFIRMED")
        diagnostics.record(sessionID: session, category: .ble, event: "BLE_START_REQUEST")
        diagnostics.markFirstPCM(sessionID: session, stage: .decode)
        diagnostics.markFirstPCM(sessionID: session, stage: .feed)
        diagnostics.markFirstPCM(sessionID: session, stage: .audioCallback)
        diagnostics.recordOptionRequest(sessionID: session, direction: .down)
        diagnostics.recordOptionPost(sessionID: session, direction: .down, component: .flags)
        diagnostics.recordOptionPost(sessionID: session, direction: .down, component: .key)
        _ = diagnostics.observeSyntheticOption(direction: .down, component: .flags)
        _ = diagnostics.observeSyntheticOption(direction: .down, component: .key)
        diagnostics.record(sessionID: session, category: .hid, event: "PHYSICAL_UP")
        diagnostics.record(sessionID: session, category: .ble, event: "DRAIN_FINISH")
        diagnostics.recordOptionRequest(sessionID: session, direction: .up)
        diagnostics.recordOptionPost(sessionID: session, direction: .up, component: .flags)
        diagnostics.recordOptionPost(sessionID: session, direction: .up, component: .key)
        _ = diagnostics.observeSyntheticOption(direction: .up, component: .flags)
        _ = diagnostics.observeSyntheticOption(direction: .up, component: .key)
        diagnostics.record(sessionID: session, category: .route, event: "ROUTE_OFF")
        diagnostics.end(sessionID: session, completion: .normalDrain, lifecycle: .balanced)

        let requiredEvents = [
            "SESSION_BEGIN", "VOICE_DOWN_PHYSICAL", "HOLD_CONFIRMED",
            "BLE_START_REQUEST", "PCM_DECODE_FIRST", "PCM_FEED_FIRST",
            "AUDIO_FIRST_CALLBACK", "OPTION_DOWN_REQUEST",
            "OPTION_DOWN_FLAGS_POST", "OPTION_DOWN_KEY_POST",
            "OPTION_DOWN_FLAGS_OBSERVED", "OPTION_DOWN_KEY_OBSERVED",
            "PHYSICAL_UP", "DRAIN_FINISH", "OPTION_UP_REQUEST",
            "OPTION_UP_FLAGS_POST", "OPTION_UP_KEY_POST",
            "OPTION_UP_FLAGS_OBSERVED", "OPTION_UP_KEY_OBSERVED",
            "ROUTE_OFF", "SESSION_END", "SUMMARY",
        ]
        for event in requiredEvents {
            XCTAssertTrue(
                lines.contains { $0.contains("event=\(event)") || $0.contains("[\(event)]") },
                "missing sample event \\(event)"
            )
        }
    }
}
