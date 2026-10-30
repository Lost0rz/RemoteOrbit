import XCTest
@testable import RemoteOrbit

final class VoicePipelineSimplificationTests: XCTestCase {
    func testPhysicalAudioStartBeforeHIDIsAdmissible() {
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in }
        )
        press.setPreHIDPhysicalStreaming(true)

        XCTAssertFalse(press.hasReleaseOrTailOwnershipForReconfiguration)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(press.currentStateForTesting, .opening)
    }

    func testPreHIDAudioIsCandidateNotSessionOwnership() {
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in }
        )

        press.setPreHIDPhysicalStreaming(true)

        XCTAssertTrue(press.preHIDPhysicalStreamingForTesting)
        XCTAssertFalse(press.hasActiveVoiceOwnershipForTriggerReconfiguration)
        XCTAssertFalse(press.diagnosticStateFields["remote_streaming"] as? Bool ?? true)
    }

    func testHardwareDirectRepressCapturesNewDownBeforeOldUpRetires() throws {
        let trigger = VoiceOptionTrigger { _, _ in }
        let filter = VoiceKeyFilter(
            syntheticOptionTrigger: trigger,
            replayEventPoster: { _ in },
            emitEmergencyHardwareOptionUp: { _ in }
        )
        let press = VoicePressCoordinator(optionTrigger: trigger)
        var completeDrain: (() -> Void)?
        press.onHardwareOptionGateBegin = { gestureID in
            filter.beginOptionDeferral(gestureID: gestureID)
        }
        // Keep A's gate open so this test can deterministically copy the
        // mapped down into the canonical long-press replay path.
        press.onHardwareOptionGateLongReady = { _ in }
        press.onHardwareOptionGatePhysicalUp = { gestureID in
            filter.armHardwareOptionRelease(gestureID: gestureID)
        }
        press.onHardwareOptionGateOutputDrained = { gestureID in
            filter.releaseHeldHardwareOption(
                gestureID: gestureID,
                reason: "test-output-drained"
            )
        }
        press.onHardwareOptionGatePendingRepressBegin = { gestureID in
            _ = filter.beginPendingHardwareOptionRepress(gestureID: gestureID)
        }
        press.onRemoteOutputDrain = { _, completion in
            completeDrain = completion
        }

        let sessionA = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionA,
                usesHardwareOption: true,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertTrue(
            filter.captureDeferredHardwareOptionEdgeForTesting(
                .down,
                copied: true
            )
        )
        filter.releaseDeferredOption(
            gestureID: sessionA,
            reason: "test-long-ready"
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertNotNil(completeDrain)

        let sessionB = UUID()
        press.setPreHIDPhysicalStreaming(true)
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionB,
                usesHardwareOption: true,
                profile: .defaultProfile,
                directSession: true
            )
        )

        guard let mappedDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: filter.momentaryVoiceTriggerKey.cgKeyCode,
            keyDown: true
        ) else {
            XCTFail("could not create mapped hardware Option down")
            return
        }
        mappedDown.flags = .maskAlternate
        XCTAssertEqual(
            filter.capturePendingHardwareOptionRepressEvent(
                mappedDown,
                type: mappedDown.type
            ),
            .captured,
            "the pending hardware re-press must own B's mapped DOWN before A retires"
        )
    }

    func testDirectRepressWithLiveCandidateDefersBeforeOutputDrainIsRequested() {
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in }
        )
        press.hasLivePhysicalCandidate = { true }
        let sessionA = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionA,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertTrue(press.keyUp())

        let sessionB = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionB,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(press.pendingRepressSessionID, sessionB)
        XCTAssertEqual(press.currentGestureIDForDiagnostics, sessionA)
    }

    func testHardwareOldUpAcknowledgedBeforePendingNewDownRelease() throws {
        let harness = try HardwareRapidRepressHarness()
        let sessionB = try harness.preparePendingHardwareRepress()
        harness.completeOldOutputDrain()

        XCTAssertEqual(harness.filter.pendingReplayedHardwareOptionUpGestureID,
                       harness.sessionA)
        XCTAssertEqual(harness.press.pendingRepressSessionID, sessionB)
        XCTAssertEqual(
            harness.replayEventTypeRawValues,
            [CGEventType.flagsChanged.rawValue]
        )

        let oldUp = try XCTUnwrap(harness.replayedEvents.first)
        XCTAssertTrue(
            harness.filter.acknowledgeReplayedHardwareOptionUpIfExpected(
                oldUp,
                type: oldUp.type
            )
        )
        XCTAssertEqual(harness.press.pendingRepressSessionID, sessionB)

        let activated = expectation(description: "pending hardware repress activates")
        harness.press.onStateChanged = { state in
            if state == .opening {
                activated.fulfill()
            }
        }
        wait(for: [activated], timeout: 1)

        XCTAssertEqual(
            harness.replayEventTypeRawValues,
            [CGEventType.flagsChanged.rawValue, CGEventType.flagsChanged.rawValue]
        )
        XCTAssertNil(harness.filter.pendingHardwareOptionRepressGestureID)
        XCTAssertEqual(harness.press.currentGestureIDForDiagnostics, sessionB)
    }

    func testPromotedHardwareRepressOwnsMappedUpThroughOutputDrain() throws {
        let harness = try HardwareRapidRepressHarness()
        let sessionB = try harness.preparePendingHardwareRepress()
        harness.completeOldOutputDrain()

        let oldUp = try XCTUnwrap(harness.replayedEvents.first)
        XCTAssertTrue(
            harness.filter.acknowledgeReplayedHardwareOptionUpIfExpected(
                oldUp,
                type: oldUp.type
            )
        )

        let activated = expectation(description: "promoted hardware repress activates")
        harness.press.onStateChanged = { state in
            if state == .opening {
                activated.fulfill()
            }
        }
        wait(for: [activated], timeout: 1)

        harness.press.setRemoteStreaming(true)
        XCTAssertTrue(harness.press.keyUp())
        let mappedUp = try XCTUnwrap(harness.makeMappedEvent(keyDown: false))
        XCTAssertEqual(
            harness.filter.captureHeldHardwareOptionUpEvent(
                mappedUp,
                type: mappedUp.type
            ),
            .captured,
            "promoted B must own its mapped UP after physical UP"
        )

        harness.press.setRemoteStreaming(false)
        XCTAssertNotNil(harness.completeDrain)
        harness.completeDrain?()

        XCTAssertEqual(
            harness.filter.pendingReplayedHardwareOptionUpGestureID,
            sessionB
        )
        let promotedBUp = try XCTUnwrap(harness.replayedEvents.last)
        XCTAssertTrue(
            harness.filter.acknowledgeReplayedHardwareOptionUpIfExpected(
                promotedBUp,
                type: promotedBUp.type
            )
        )
        XCTAssertNil(harness.filter.pendingReplayedHardwareOptionUpGestureID)
        XCTAssertEqual(harness.press.currentStateForTesting, .idle)
    }

    func testTransportSupersessionRetiresAThenPromotesBWithCandidatePreserved() throws {
        let harness = try HardwareRapidRepressHarness()
        let candidateSamples: [Int16] = [101, 202, 303, 404]
        _ = AudioPipe.shared.setRemoteActive(false)
        AudioPipe.shared.endRemoteCandidate()
        defer {
            _ = AudioPipe.shared.setRemoteActive(false)
            AudioPipe.shared.endRemoteCandidate()
        }

        XCTAssertTrue(
            harness.press.keyDown(
                sessionID: harness.sessionA,
                usesHardwareOption: true,
                profile: .defaultProfile,
                directSession: true
            )
        )
        let oldDown = try XCTUnwrap(harness.makeMappedEvent(keyDown: true))
        XCTAssertTrue(
            harness.filter.captureDeferredHardwareOptionEdge(
                .down,
                copiedEvent: oldDown
            )
        )
        harness.filter.releaseDeferredOption(
            gestureID: harness.sessionA,
            reason: "test-long-ready"
        )
        harness.press.setRemoteStreaming(true)
        XCTAssertTrue(harness.press.keyUp())
        let oldUp = try XCTUnwrap(harness.makeMappedEvent(keyDown: false))
        XCTAssertEqual(
            harness.filter.captureHeldHardwareOptionUpEvent(oldUp, type: oldUp.type),
            .captured
        )

        // B's physical AUDIO_START has already established candidate ownership
        // before the coordinator receives A's terminal transport boundary.
        AudioPipe.shared.beginRemoteCandidate(replacingExisting: true)
        AudioPipe.shared.feedCandidate(samples: candidateSamples)
        harness.press.setPreHIDPhysicalStreaming(true)
        XCTAssertEqual(
            AudioPipe.shared.pendingRemoteCandidateSamplesForTesting,
            candidateSamples.count
        )
        harness.press.handlePhysicalTransportSupersession()
        XCTAssertNotNil(harness.completeDrain)

        let sessionB = UUID()
        XCTAssertTrue(
            harness.press.keyDown(
                sessionID: sessionB,
                usesHardwareOption: true,
                profile: .defaultProfile,
                directSession: true
            )
        )
        let newDown = try XCTUnwrap(harness.makeMappedEvent(keyDown: true))
        XCTAssertEqual(
            harness.filter.capturePendingHardwareOptionRepressEvent(
                newDown,
                type: newDown.type
            ),
            .captured
        )
        XCTAssertEqual(harness.press.currentGestureIDForDiagnostics, harness.sessionA)
        XCTAssertEqual(
            AudioPipe.shared.pendingRemoteCandidateSamplesForTesting,
            candidateSamples.count,
            "A terminal teardown must not clear B candidate PCM"
        )

        let promoted = expectation(description: "B promotes after A trigger ACK")
        harness.press.onStateChanged = { state in
            if state == .opening {
                promoted.fulfill()
            }
        }
        harness.completeOldOutputDrain()
        let replayedOldUp = try XCTUnwrap(harness.replayedEvents.first)
        XCTAssertTrue(
            harness.filter.acknowledgeReplayedHardwareOptionUpIfExpected(
                replayedOldUp,
                type: replayedOldUp.type
            )
        )
        wait(for: [promoted], timeout: 1)

        XCTAssertEqual(harness.press.currentGestureIDForDiagnostics, sessionB)
        XCTAssertEqual(
            AudioPipe.shared.pendingRemoteCandidateSamplesForTesting,
            0,
            "promoted B must adopt and flush its preserved candidate PCM"
        )
    }

    func testAdmissionBlockedPromotedHardwareRepressDoesNotReplayOrLeakOwnership() throws {
        let harness = try HardwareRapidRepressHarness()
        let sessionB = try harness.preparePendingHardwareRepress()
        harness.press.isVoiceSessionAdmissionBlocked = { true }
        harness.completeOldOutputDrain()

        let oldUp = try XCTUnwrap(harness.replayedEvents.first)
        XCTAssertTrue(
            harness.filter.acknowledgeReplayedHardwareOptionUpIfExpected(
                oldUp,
                type: oldUp.type
            )
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(
            harness.replayEventTypeRawValues,
            [CGEventType.flagsChanged.rawValue],
            "admission-blocked promotion must not replay B DOWN"
        )
        XCTAssertEqual(
            harness.filter.diagnosticStateFields["held_hardware_owner"] as? String,
            "none"
        )
        XCTAssertEqual(
            harness.filter.diagnosticStateFields["filter_active_gate"] as? String,
            "none"
        )
        XCTAssertEqual(harness.filter.pendingHardwareOptionRepressGestureID, sessionB)
        XCTAssertTrue(harness.filter.pendingHardwareOptionRepressIsCancelledForTesting)

        let mappedUp = try XCTUnwrap(harness.makeMappedEvent(keyDown: false))
        XCTAssertEqual(
            harness.filter.capturePendingHardwareOptionRepressEvent(
                mappedUp,
                type: mappedUp.type
            ),
            .suppressed
        )
        XCTAssertNil(harness.filter.pendingHardwareOptionRepressGestureID)
        XCTAssertFalse(harness.filter.hasActiveHardwareTriggerOwnership)
        XCTAssertNil(harness.press.pendingRepressSessionID)
        XCTAssertNil(harness.press.currentGestureIDForDiagnostics)
        XCTAssertEqual(harness.press.currentStateForTesting, .idle)
        XCTAssertFalse(harness.press.hasActiveVoiceOwnershipForTriggerReconfiguration)
    }

    func testHardwarePendingRepressReleaseBeforeActivationHasNoTriggerLeak() throws {
        let harness = try HardwareRapidRepressHarness()
        let sessionB = try harness.preparePendingHardwareRepress()

        XCTAssertFalse(harness.press.keyUp())
        XCTAssertNil(harness.press.pendingRepressSessionID)
        XCTAssertEqual(harness.filter.pendingHardwareOptionRepressGestureID, sessionB)
        XCTAssertTrue(harness.filter.pendingHardwareOptionRepressIsCancelledForTesting)

        let mappedUp = try XCTUnwrap(harness.makeMappedEvent(keyDown: false))
        XCTAssertEqual(
            harness.filter.capturePendingHardwareOptionRepressEvent(
                mappedUp,
                type: mappedUp.type
            ),
            .suppressed
        )
        XCTAssertNil(harness.filter.pendingHardwareOptionRepressGestureID)
        XCTAssertTrue(harness.replayedEvents.isEmpty)

        harness.completeOldOutputDrain()
        XCTAssertEqual(
            harness.replayEventTypeRawValues,
            [CGEventType.flagsChanged.rawValue]
        )
    }

    func testHardwareOnlyOnePendingDirectRepressOwner() throws {
        let harness = try HardwareRapidRepressHarness()
        let sessionB = try harness.preparePendingHardwareRepress()
        let sessionC = UUID()

        XCTAssertTrue(
            harness.press.keyDown(
                sessionID: sessionC,
                usesHardwareOption: true,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(harness.press.pendingRepressSessionID, sessionB)
        XCTAssertEqual(harness.filter.pendingHardwareOptionRepressGestureID, sessionB)
        XCTAssertEqual(harness.filter.pendingHardwareOptionRepressDownCountForTesting, 1)
    }

    func testHardwarePendingRepressPreservesNormalHardwareOutputOrdering() {
        var order: [String] = []
        var completeDrain: (() -> Void)?
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _, _ in
            XCTFail("normal hardware path must not use synthetic edges")
        })
        press.onHardwareOptionGateBegin = { _ in order.append("gate-begin") }
        press.onHardwareOptionGateLongReady = { _ in order.append("trigger-down-release") }
        press.onHardwareOptionGatePhysicalUp = { _ in order.append("physical-up") }
        press.onHardwareOptionGateOutputDrained = { _ in order.append("trigger-up") }
        press.onRemoteOutputDrain = { _, completion in
            order.append("output-drain")
            completeDrain = completion
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: true,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(
            order,
            ["gate-begin", "trigger-down-release", "physical-up", "output-drain"]
        )

        completeDrain?()
        XCTAssertEqual(order.last, "trigger-up")
    }

    func testUnownedPhysicalStreamStopClearsBusyState() {
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in }
        )
        press.setPreHIDPhysicalStreaming(true)
        press.setPreHIDPhysicalStreaming(false)

        XCTAssertFalse(press.preHIDPhysicalStreamingForTesting)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
    }

    func testVoiceDownStartsImmediatelyAndCapturesOneProfile() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        var states: [VoicePressCoordinator.State] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onStateChanged = { states.append($0) }
        let profile = VoiceInputProfile.supported.first { $0.triggerKey == .rightOption }!

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                preparesRemoteTransport: true,
                profile: profile,
                directSession: true
            )
        )
        XCTAssertEqual(events.map { ($0.key, $0.isDown) }.count, 1)
        XCTAssertEqual(events.first?.key, profile.triggerKey)
        XCTAssertEqual(events.first?.isDown, true)
        XCTAssertEqual(states, [.opening])
        XCTAssertEqual(press.capturedVoiceProfileForTesting, profile)
        XCTAssertEqual(press.capturedTriggerKeyForTesting, profile.triggerKey)
        XCTAssertEqual(press.diagnosticStateFields["voice_session_state"] as? String, "opening")
    }

    func testAdoptedStreamRetirementLeavesCoordinatorReadyForRapidNextSession() {
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in }
        )
        press.setPreHIDPhysicalStreaming(true)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setPreHIDPhysicalStreaming(false)
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
    }

    func testVoiceUpDrainsOutputBeforeSyntheticTriggerUp() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        var states: [VoicePressCoordinator.State] = []
        var completeDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onStateChanged = { states.append($0) }
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }
        let profile = VoiceInputProfile.supported.first { $0.triggerKey == .leftCommand }!

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: profile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(states, [.opening, .streaming, .draining])
        XCTAssertEqual(events.map { $0.isDown }, [true])
        XCTAssertNil(completeDrain)

        press.setRemoteStreaming(false)
        XCTAssertNotNil(completeDrain)

        completeDrain?()

        XCTAssertEqual(events.map { $0.isDown }, [true, false])
        XCTAssertEqual(events.map { $0.key }, [profile.triggerKey, profile.triggerKey])
        XCTAssertEqual(states.last, .idle)
        XCTAssertNil(press.capturedVoiceProfileForTesting)
    }

    func testDirectActiveReleaseTailOrderKeepsRemoteRouteUntilTransportStops() {
        var completeDrain: (() -> Void)?
        var drainRequests = 0
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _, _ in })
        press.onRemoteOutputDrain = { _, completion in
            drainRequests += 1
            completeDrain = completion
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)

        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(press.currentStateForTesting, .draining)
        XCTAssertEqual(press.diagnosticStateFields["remote_routed"] as? Bool, true)
        XCTAssertEqual(drainRequests, 0)

        press.setRemoteStreaming(false)
        XCTAssertEqual(press.diagnosticStateFields["remote_routed"] as? Bool, false)
        XCTAssertEqual(drainRequests, 1)
        XCTAssertNotNil(completeDrain)

        completeDrain?()
        XCTAssertEqual(press.currentStateForTesting, .idle)
    }

    func testDirectLateTailPCMRemainsEligibleUntilStreamingStops() {
        var completeDrain: (() -> Void)?
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _, _ in })
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())

        XCTAssertEqual(press.diagnosticStateFields["remote_routed"] as? Bool, true)
        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.hasRemoteAudio)
        XCTAssertNil(completeDrain)

        press.setRemoteStreaming(false)
        XCTAssertEqual(press.diagnosticStateFields["remote_routed"] as? Bool, false)
        XCTAssertNotNil(completeDrain)
        completeDrain?()
    }

    func testDirectStreamStopThenOutputDrainKeepsTriggerDownUntilOutputCompletes() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        var completeDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger { key, isDown in
            events.append((key, isDown))
        }
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }
        let profile = VoiceInputProfile.supported.first { $0.triggerKey == .leftCommand }!

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: profile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)

        XCTAssertEqual(events.map(\.isDown), [true])
        XCTAssertNotNil(completeDrain)
        XCTAssertEqual(press.currentStateForTesting, .draining)

        completeDrain?()
        XCTAssertEqual(events.map(\.key), [profile.triggerKey, profile.triggerKey])
        XCTAssertEqual(events.map(\.isDown), [true, false])
        XCTAssertEqual(press.currentStateForTesting, .idle)
    }

    func testNoAudioStartReleaseCannotRemainInDraining() {
        var completeDrain: (() -> Void)?
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _, _ in })
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(press.currentStateForTesting, .draining)
        XCTAssertEqual(press.diagnosticStateFields["remote_routed"] as? Bool, true)
        XCTAssertNil(completeDrain)

        press.setRemoteStreaming(false)
        XCTAssertNotNil(completeDrain)
        completeDrain?()

        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertNil(press.currentGestureIDForDiagnostics)
        XCTAssertEqual(press.diagnosticStateFields["remote_routed"] as? Bool, false)
    }

    func testNoAudioStartTransportCloseRetiresAfterPhysicalUp() {
        var completeDrain: (() -> Void)?
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _, _ in })
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(press.currentStateForTesting, .draining)

        // This is the callback emitted when post-release MIC_CLOSE retires an
        // opening attempt that never produced AUDIO_START.
        press.setRemoteStreaming(false)
        XCTAssertNotNil(completeDrain)
        completeDrain?()

        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertNil(press.currentGestureIDForDiagnostics)
    }

    func testOpeningTransportLossRetiresWithoutAudioStartOrPhysicalUp() {
        var events: [Bool] = []
        var completeDrain: (() -> Void)?
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.handleTransportLoss()

        XCTAssertEqual(press.currentStateForTesting, .draining)
        XCTAssertEqual(press.diagnosticStateFields["remote_routed"] as? Bool, false)
        XCTAssertNotNil(completeDrain)

        completeDrain?()

        XCTAssertEqual(events, [true, false])
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertNil(press.currentGestureIDForDiagnostics)
        XCTAssertNil(press.capturedVoiceProfileForTesting)
    }

    func testStreamingTransportLossRetiresWithoutWaitingForPhysicalUp() {
        var events: [Bool] = []
        var completeDrain: (() -> Void)?
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        press.handleTransportLoss()

        XCTAssertEqual(press.currentStateForTesting, .draining)
        XCTAssertEqual(press.diagnosticStateFields["remote_routed"] as? Bool, false)
        XCTAssertNotNil(completeDrain)

        completeDrain?()

        XCTAssertEqual(events, [true, false])
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertNil(press.currentGestureIDForDiagnostics)
    }

    func testStaleOutputDrainCompletionCannotReleaseNextDirectSession() {
        var events: [Bool] = []
        var firstDrain: (() -> Void)?
        var secondDrain: (() -> Void)?
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var drainCount = 0
        press.onRemoteOutputDrain = { _, completion in
            drainCount += 1
            if drainCount == 1 {
                firstDrain = completion
            } else {
                secondDrain = completion
            }
        }

        let firstSessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertNotNil(firstDrain)
        firstDrain?()

        let secondSessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: secondSessionID,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        firstDrain?()

        XCTAssertEqual(press.currentGestureIDForDiagnostics, secondSessionID)
        XCTAssertEqual(events, [true, false, true])

        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        secondDrain?()
        XCTAssertEqual(events, [true, false, true, false])
    }

    func testRapidNextSessionWaitsForTailAndOutputDrainThenStartsCleanly() {
        var completeDrain: (() -> Void)?
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _, _ in })

        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }
        let firstSessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())

        XCTAssertFalse(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(false)
        XCTAssertNotNil(completeDrain)
        XCTAssertFalse(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )

        completeDrain?()
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.stop()
    }

    func testHOST_NO_TERMINAL_STREAM_THEN_REASON03_DURING_RELEASE_GRACE_DEFERS_DIRECT_REPRESS() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        var completeDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }
        let firstSessionID = UUID()
        let nextSessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertNotNil(completeDrain)

        press.setPreHIDPhysicalStreaming(true)
        XCTAssertTrue(
            press.keyDown(
                sessionID: nextSessionID,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(press.pendingRepressSessionID, nextSessionID)
        XCTAssertEqual(events.map(\.isDown), [true])

        completeDrain?()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertNil(press.pendingRepressSessionID)
        XCTAssertEqual(press.currentGestureIDForDiagnostics, nextSessionID)
        XCTAssertEqual(events.map(\.isDown), [true, false, true])
        press.stop()
    }

    func testPENDING_DIRECT_REPRESS_RELEASE_BEFORE_ACTIVATION_CLEARS_WITHOUT_TRIGGER_LEAK() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        var completeDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)

        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        press.setPreHIDPhysicalStreaming(true)

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertFalse(press.keyUp())
        XCTAssertNil(press.pendingRepressSessionID)

        completeDrain?()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(events.map(\.isDown), [true, false])
        XCTAssertNil(press.currentGestureIDForDiagnostics)
        press.stop()
    }

    func testONLY_ONE_PENDING_DIRECT_REPRESS_ALLOWED() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        var completeDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        press.setPreHIDPhysicalStreaming(true)

        let firstPending = UUID()
        let secondPending = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: firstPending,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertTrue(
            press.keyDown(
                sessionID: secondPending,
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(press.pendingRepressSessionID, firstPending)
        XCTAssertEqual(events.map(\.isDown), [true])
        completeDrain?()
        press.stop()
    }

    func testPREVIOUS_DIRECT_OUTPUT_DRAIN_AND_TRIGGER_UP_COMPLETE_BEFORE_NEW_TRIGGER_DOWN() {
        var events: [(key: VoiceTriggerKey, isDown: Bool)] = []
        var completeDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger(keyedEventSink: { key, isDown in
            events.append((key, isDown))
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        press.setPreHIDPhysicalStreaming(true)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: false,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(events.map(\.isDown), [true])

        completeDrain?()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertEqual(events.map(\.isDown), [true, false, true])
        press.stop()
    }

    func testHardwareVoiceDownReleasesCapturedGateImmediatelyButUpWaitsForDrain() {
        var order: [String] = []
        var completeDrain: (() -> Void)?
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in
            XCTFail("hardware path must not emit synthetic trigger edges")
        })
        let press = VoicePressCoordinator(optionTrigger: trigger)
        press.onHardwareOptionGateBegin = { _ in order.append("gate-begin") }
        press.onHardwareOptionGateLongReady = { _ in order.append("gate-release") }
        press.onHardwareOptionGatePhysicalUp = { _ in order.append("physical-up") }
        press.onHardwareOptionGateOutputDrained = { _ in order.append("output-drained") }
        press.onRemoteOutputDrain = { _, completion in completeDrain = completion }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                usesHardwareOption: true,
                profile: .defaultProfile,
                directSession: true
            )
        )
        XCTAssertEqual(order, ["gate-begin", "gate-release"])

        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(order, ["gate-begin", "gate-release", "physical-up"])
        XCTAssertNil(completeDrain)

        press.setRemoteStreaming(false)
        completeDrain?()
        XCTAssertEqual(order, ["gate-begin", "gate-release", "physical-up", "output-drained"])
    }

    func testProfileMigrationUsesOnlyLegacyMomentaryTrigger() {
        let suiteName = "RemoteOrbit.VoicePipelineSimplificationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(VoiceTriggerKey.rightControl.rawValue, forKey: AppStorage.momentaryVoiceTriggerKeyKey)
        defaults.set(VoiceTriggerKey.leftCommand.rawValue, forKey: AppStorage.persistentSessionTriggerKeyKey)
        defaults.set(VoiceTriggerKey.rightCommand.rawValue, forKey: AppStorage.secondaryMomentaryVoiceTriggerKeyKey)

        let profile = VoiceInputProfileStore.selectedProfile(from: defaults)

        XCTAssertEqual(profile.triggerKey, .rightControl)
        XCTAssertEqual(defaults.string(forKey: VoiceInputProfileStore.selectedProfileIDKey), profile.id)
        XCTAssertEqual(
            AppStorage.readMomentaryVoiceTriggerKey(from: defaults),
            .rightControl
        )
    }
}

private final class HardwareRapidRepressHarness {
    private final class Recorder {
        var replayedEvents: [CGEvent] = []
        var triggerEdges: [(VoiceTriggerKey, Bool)] = []
    }

    private let recorder: Recorder
    let trigger: VoiceOptionTrigger
    let filter: VoiceKeyFilter
    let press: VoicePressCoordinator
    var completeDrain: (() -> Void)?
    let sessionA = UUID()

    var replayedEvents: [CGEvent] { recorder.replayedEvents }
    var replayEventTypeRawValues: [UInt32] {
        recorder.replayedEvents.map(\.type.rawValue)
    }

    init() throws {
        let recorder = Recorder()
        self.recorder = recorder
        let trigger = VoiceOptionTrigger(
            keyedEventSink: { key, isDown in
                recorder.triggerEdges.append((key, isDown))
            }
        )
        self.trigger = trigger
        self.filter = VoiceKeyFilter(
            syntheticOptionTrigger: trigger,
            replayEventPoster: { event in
                recorder.replayedEvents.append(event)
            },
            emitEmergencyHardwareOptionUp: { _ in }
        )
        self.press = VoicePressCoordinator(optionTrigger: trigger)

        press.onHardwareOptionGateBegin = { [unowned self] gestureID in
            self.filter.beginOptionDeferral(gestureID: gestureID)
        }
        // The harness copies/replays the physical DOWN explicitly so the
        // ordering boundary is asserted without depending on an event tap.
        press.onHardwareOptionGateLongReady = { _ in }
        press.onHardwareOptionGatePhysicalUp = { [unowned self] gestureID in
            self.filter.armHardwareOptionRelease(gestureID: gestureID)
        }
        press.onHardwareOptionGateOutputDrained = { [unowned self] gestureID in
            self.filter.releaseHeldHardwareOption(
                gestureID: gestureID,
                reason: "test-output-drained"
            )
            let awaiting = self.filter.pendingReplayedHardwareOptionUpGestureID
                == gestureID
            self.press.hardwareOptionGateOutputDrainCompleted(
                sessionID: gestureID,
                awaitingPassAcknowledgement: awaiting
            )
        }
        press.onHardwareOptionGatePendingRepressBegin = { [unowned self] gestureID in
            _ = self.filter.beginPendingHardwareOptionRepress(gestureID: gestureID)
        }
        press.onHardwareOptionGatePendingRepressPromote = { [unowned self] gestureID in
            self.filter.promotePendingHardwareOptionRepress(gestureID: gestureID)
        }
        press.onHardwareOptionGatePendingRepressCancel = { [unowned self] gestureID, reason in
            self.filter.cancelPendingHardwareOptionRepress(
                gestureID: gestureID,
                reason: reason
            )
        }
        press.onRemoteOutputDrain = { [unowned self] _, completion in
            self.completeDrain = completion
        }
        filter.onReplayedHardwareOptionUpPassAcknowledged = { [unowned self] gestureID in
            self.press.hardwareOptionUpPassAcknowledged(sessionID: gestureID)
        }
    }

    func makeMappedEvent(keyDown: Bool) -> CGEvent? {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: filter.momentaryVoiceTriggerKey.cgKeyCode,
            keyDown: keyDown
        )
        event?.flags = keyDown ? .maskAlternate : []
        return event
    }

    func preparePendingHardwareRepress() throws -> UUID {
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionA,
                usesHardwareOption: true,
                profile: .defaultProfile,
                directSession: true
            )
        )
        let oldDown = try XCTUnwrap(makeMappedEvent(keyDown: true))
        XCTAssertTrue(
            filter.captureDeferredHardwareOptionEdge(
                .down,
                copiedEvent: oldDown
            )
        )
        filter.releaseDeferredOption(
            gestureID: sessionA,
            reason: "test-long-ready"
        )
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        let oldUp = try XCTUnwrap(makeMappedEvent(keyDown: false))
        XCTAssertEqual(
            filter.captureHeldHardwareOptionUpEvent(oldUp, type: oldUp.type),
            .captured
        )
        press.setRemoteStreaming(false)

        let sessionB = UUID()
        press.setPreHIDPhysicalStreaming(true)
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionB,
                usesHardwareOption: true,
                profile: .defaultProfile,
                directSession: true
            )
        )
        let newDown = try XCTUnwrap(makeMappedEvent(keyDown: true))
        XCTAssertEqual(
            filter.capturePendingHardwareOptionRepressEvent(
                newDown,
                type: newDown.type
            ),
            .captured
        )
        recorder.replayedEvents.removeAll()
        return sessionB
    }

    func completeOldOutputDrain() {
        completeDrain?()
    }
}
