import XCTest
@testable import RemoteOrbit

final class VoiceTriggerRuntimeTests: XCTestCase {
    func testDualReceiverMappedTriggerStateTracksPrimarySecondaryAndRestoreOwnership() {
        var state = DualReceiverMappedTriggerState(initialPhase: .primaryReady)
        let gestureID = UUID()

        XCTAssertEqual(state.phase, .primaryReady)

        let armGeneration = state.beginSecondaryArming(gestureID: gestureID)
        XCTAssertNotNil(armGeneration)
        XCTAssertEqual(
            state.phase,
            .armingSecondary(gestureID: gestureID, generation: armGeneration!)
        )
        XCTAssertFalse(
            state.completeSecondaryArming(
                gestureID: gestureID,
                generation: armGeneration! &- 1
            )
        )
        XCTAssertTrue(
            state.completeSecondaryArming(
                gestureID: gestureID,
                generation: armGeneration!
            )
        )
        XCTAssertEqual(state.phase, .secondaryReady(gestureID: gestureID))
        XCTAssertTrue(state.admitSecondaryPress(gestureID: gestureID))
        XCTAssertEqual(state.phase, .secondaryActive(gestureID: gestureID))

        let restoreGeneration = state.beginPrimaryRestore()
        XCTAssertEqual(state.phase, .restoringPrimary(generation: restoreGeneration))
        XCTAssertFalse(
            state.completePrimaryRestore(
                generation: restoreGeneration &- 1,
                succeeded: true
            )
        )
        XCTAssertEqual(state.phase, .restoringPrimary(generation: restoreGeneration))
        XCTAssertTrue(
            state.completePrimaryRestore(
                generation: restoreGeneration,
                succeeded: true
            )
        )
        XCTAssertEqual(state.phase, .primaryReady)
    }

    func testEarlySecondPressBlocksLateSecondaryArmCompletion() {
        var state = DualReceiverMappedTriggerState(initialPhase: .primaryReady)
        let gestureID = UUID()
        let armGeneration = state.beginSecondaryArming(gestureID: gestureID)!

        XCTAssertTrue(state.blockPressUntilRelease(gestureID: gestureID))
        XCTAssertEqual(state.phase, .blockedUntilRelease(gestureID: gestureID))
        XCTAssertFalse(
            state.completeSecondaryArming(
                gestureID: gestureID,
                generation: armGeneration
            )
        )
        XCTAssertEqual(state.phase, .blockedUntilRelease(gestureID: gestureID))
    }

    func testFailedPrimaryRestoreLeavesMappedTriggerStateUnavailable() {
        var state = DualReceiverMappedTriggerState(initialPhase: .secondaryReady(gestureID: UUID()))
        let restoreGeneration = state.beginPrimaryRestore()

        XCTAssertTrue(
            state.completePrimaryRestore(
                generation: restoreGeneration,
                succeeded: false
            )
        )
        XCTAssertEqual(
            state.phase,
            .unavailable(reason: .primaryRestoreFailed)
        )
    }

    func testFirstQuickReleaseArmsSecondaryOnlyAfterMappingFilterCommit() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, true],
            applyDelay: 0.08
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )

        let gestureID = firstQuickRelease(on: harness.controller)

        XCTAssertEqual(
            harness.controller.dualReceiverMappedTriggerState.phase,
            .armingSecondary(
                gestureID: gestureID,
                generation: harness.controller.dualReceiverMappedTriggerState.generation
            )
        )
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode
        ))
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode
        ))
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertTrue(harness.triggerEvents.isEmpty)

        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.dualReceiverMappedTriggerState.phase
                == .secondaryReady(gestureID: gestureID)
        })
        XCTAssertEqual(harness.mappingCalls.map(\.key), [.leftOption, .rightOption])
        XCTAssertEqual(harness.mappingObservations.last?.filterKey, .leftOption)
        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .rightOption)
        XCTAssertNotNil(harness.controller.lastAToBApplyMillisecondsForTesting)
        XCTAssertGreaterThanOrEqual(
            harness.controller.lastAToBApplyMillisecondsForTesting ?? -1,
            0
        )
        XCTAssertGreaterThanOrEqual(
            harness.controller.lastFirstUpToSecondaryReadyMillisecondsForTesting ?? -1,
            0
        )
        XCTAssertFalse(harness.controller.voiceTriggerReconfigurationInProgress)
        XCTAssertFalse(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode
        ))
        XCTAssertTrue(harness.triggerEvents.isEmpty)
    }

    func testSecondDownBeforeSecondaryReadyIsDiscardedAndRestoresPrimaryAfterUp() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, true, true],
            applyDelay: 0.16
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )

        let firstDownAt = ProcessInfo.processInfo.systemUptime
        harness.controller.handleDualReceiverMicrophoneEdge(isDown: true, at: firstDownAt)
        harness.controller.handleDualReceiverMicrophoneEdge(
            isDown: false,
            at: firstDownAt + 0.05
        )
        let gestureID = harness.controller.dualReceiverVoiceGestureRecognizer.currentGestureID!
        let secondDownAt = firstDownAt + 0.10
        harness.controller.handleDualReceiverMicrophoneEdge(
            isDown: true,
            at: secondDownAt
        )

        XCTAssertEqual(
            harness.controller.dualReceiverMappedTriggerState.phase,
            .blockedUntilRelease(gestureID: gestureID)
        )
        XCTAssertEqual(harness.voicePrewarmCount, 1)
        XCTAssertEqual(harness.voiceCancelCount, 1)
        XCTAssertEqual(harness.voiceActivationCount, 0)
        XCTAssertTrue(harness.triggerEvents.isEmpty)

        XCTAssertTrue(waitUntil(timeout: 2) { harness.mappingCalls.count == 2 })
        XCTAssertTrue(harness.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VK.voiceKey
        ))
        XCTAssertTrue(harness.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode
        ))
        XCTAssertTrue(harness.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode
        ))
        RunLoop.current.run(until: Date().addingTimeInterval(0.40))
        harness.controller.voicePress.setRemoteAudioAvailable()
        XCTAssertEqual(harness.voiceActivationCount, 0)
        XCTAssertTrue(harness.triggerEvents.isEmpty)
        XCTAssertEqual(
            harness.controller.dualReceiverMappedTriggerState.phase,
            .blockedUntilRelease(gestureID: gestureID)
        )

        harness.controller.handleDualReceiverMicrophoneEdge(
            isDown: false,
            at: secondDownAt + 0.41
        )
        guard case .restoringPrimary = harness.controller.dualReceiverMappedTriggerState.phase else {
            XCTFail("blocked second UP must begin restoring A")
            return
        }
        harness.controller.handleDualReceiverMicrophoneEdge(
            isDown: true,
            at: secondDownAt + 0.42
        )
        XCTAssertEqual(harness.voicePrewarmCount, 1)
        XCTAssertEqual(harness.voiceActivationCount, 0)
        XCTAssertTrue(harness.triggerEvents.isEmpty)

        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.dualReceiverMappedTriggerState.phase == .primaryReady
                && !harness.controller.voiceTriggerReconfigurationInProgress
                && harness.mappingCalls.count == 3
        })
        XCTAssertEqual(harness.mappingCalls.map(\.key), [.leftOption, .rightOption, .leftOption])
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertFalse(harness.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VK.voiceKey
        ))
        XCTAssertTrue(harness.triggerEvents.isEmpty)
    }

    func testFailedSecondaryMappingRestoresPrimaryWithoutAdmittingB() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, false, true]
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )

        _ = firstQuickRelease(on: harness.controller)

        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.dualReceiverMappedTriggerState.phase == .primaryReady
                && !harness.controller.voiceTriggerReconfigurationInProgress
        })
        XCTAssertEqual(harness.mappingCalls.map(\.key), [.leftOption, .rightOption, .leftOption])
        XCTAssertTrue(harness.mappingCalls.allSatisfy(\.enabled))
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertFalse(harness.controller.voiceTriggerRuntimeLocked)
        XCTAssertNotNil(harness.controller.lastBToAApplyMillisecondsForTesting)
        XCTAssertTrue(harness.triggerEvents.isEmpty)
    }

    func testConcurrentTriggerSettingChangeIsRejectedWhileSecondaryMappingArms() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, true],
            applyDelay: 0.2
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        let gestureID = firstQuickRelease(on: harness.controller)

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busy)
        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.dualReceiverMappedTriggerState.phase,
            .armingSecondary(
                gestureID: gestureID,
                generation: harness.controller.dualReceiverMappedTriggerState.generation
            )
        )
        XCTAssertTrue(harness.triggerEvents.isEmpty)
        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.dualReceiverMappedTriggerState.phase
                == .secondaryReady(gestureID: gestureID)
        })
    }

    func testTimedOutSecondaryArmIgnoresLateBCompletionAndRestoresA() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, true, true],
            applyDelay: 0.42
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        let gestureID = firstQuickRelease(on: harness.controller)

        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.dualReceiverMappedTriggerState.phase == .primaryReady
                && !harness.controller.voiceTriggerReconfigurationInProgress
        })
        XCTAssertNotEqual(
            harness.controller.dualReceiverMappedTriggerState.phase,
            .secondaryReady(gestureID: gestureID)
        )
        XCTAssertEqual(harness.mappingCalls.map(\.key), [.leftOption, .rightOption, .leftOption])
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertNotNil(harness.controller.lastBToAApplyMillisecondsForTesting)
        XCTAssertTrue(harness.triggerEvents.isEmpty)
    }

    func testStaleSecondaryReadbackCannotOverrideTimedOutPrimaryRestore() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, true, true],
            applyDelay: 0.42,
            readbackResults: [.mismatch],
            readbackDelay: 0.55
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        _ = firstQuickRelease(on: harness.controller)

        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.dualReceiverMappedTriggerState.phase == .primaryReady
                && !harness.controller.voiceTriggerReconfigurationInProgress
        })
        XCTAssertTrue(waitUntil(timeout: 1) {
            harness.mappingCalls.count == 3
        })
        XCTAssertEqual(harness.controller.dualReceiverMappedTriggerState.phase, .primaryReady)
        XCTAssertFalse(harness.controller.voiceTriggerRuntimeLocked)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertTrue(harness.triggerEvents.isEmpty)
    }

    func testSecondaryFilterConfigurationFailureKeepsReconfigurationLocked() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, true, true],
            applyDelay: 0.08
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        _ = firstQuickRelease(on: harness.controller)
        let unexpectedSyntheticOwner = UUID()
        XCTAssertTrue(harness.trigger.begin(sessionID: unexpectedSyntheticOwner))

        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.voiceTriggerRuntimeLocked
                && harness.controller.dualReceiverMappedTriggerState.phase
                    == .unavailable(reason: .primaryRestoreFailed)
        })
        XCTAssertTrue(harness.controller.voiceTriggerReconfigurationInProgress)
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.rightOption.cgKeyCode
        ))
        XCTAssertTrue(harness.triggerEvents.isEmpty)
        _ = harness.trigger.abort(sessionID: unexpectedSyntheticOwner)
    }

    func testSecondaryReadbackMismatchConvergesToLockedPrimary() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, true, true],
            applyDelay: 0.01,
            readbackResults: [.mismatch],
            readbackDelay: 0.18
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        let gestureID = firstQuickRelease(on: harness.controller)

        XCTAssertTrue(waitUntil(timeout: 1) {
            harness.controller.dualReceiverMappedTriggerState.phase
                == .secondaryReady(gestureID: gestureID)
        })
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .rightOption)
        XCTAssertTrue(waitUntil(timeout: 2) {
            harness.controller.voiceTriggerRuntimeLocked
                && harness.controller.dualReceiverMappedTriggerState.phase
                    == .unavailable(reason: .mappingApplyFailed)
                && !harness.controller.voiceTriggerReconfigurationInProgress
        })
        XCTAssertEqual(harness.mappingCalls.map(\.key), [.leftOption, .rightOption, .leftOption])
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(
            harness.controller.dualReceiverVoiceMode,
            .unavailable(.primaryMappingFailed)
        )
        XCTAssertTrue(harness.triggerEvents.isEmpty)
    }

    func testControllerTracksPrimaryMappingOwnershipOnlyWhenDualModeIsActive() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [true]
        )

        XCTAssertEqual(
            harness.controller.dualReceiverMappedTriggerState.phase,
            .unavailable(reason: .dualModeInactive)
        )
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        XCTAssertEqual(harness.controller.dualReceiverMappedTriggerState.phase, .primaryReady)
    }

    func testDualModeUnavailableWithoutRawHIDDoesNotUseVoiceKeyFallback() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            rawHIDReady: false,
            eventSuppressorReady: true
        )
        var prewarmCount = 0
        var routeCount = 0
        harness.controller.voicePress.onRemoteTransportPreparation = { prewarmCount += 1 }
        harness.controller.voicePress.onRemoteRoutePreparation = { routeCount += 1 }

        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .unavailable(.rawHIDUnavailable)
        )
        harness.controller.beginVoicePress(
            shortBinding: .voiceKeyDefault,
            source: .voiceKeyFilterFallback
        )

        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(prewarmCount, 0)
        XCTAssertEqual(routeCount, 0)
        XCTAssertTrue(harness.triggerEvents.isEmpty)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
    }

    func testDualModeUnavailableWithoutEventSuppressorDoesNotUseVoiceKeyFallback() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            rawHIDReady: true,
            eventSuppressorReady: false
        )
        var prewarmCount = 0
        var routeCount = 0
        harness.controller.voicePress.onRemoteTransportPreparation = { prewarmCount += 1 }
        harness.controller.voicePress.onRemoteRoutePreparation = { routeCount += 1 }

        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .unavailable(.eventSuppressorUnavailable)
        )
        harness.controller.beginVoicePress(
            shortBinding: .voiceKeyDefault,
            source: .voiceKeyFilterFallback
        )

        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(prewarmCount, 0)
        XCTAssertEqual(routeCount, 0)
        XCTAssertTrue(harness.triggerEvents.isEmpty)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
    }

    func testDualModePrimaryMappingFailureFailsClosedDespiteCachedState() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            applyResults: [false],
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        var prewarmCount = 0
        var routeCount = 0
        harness.controller.voicePress.onRemoteTransportPreparation = { prewarmCount += 1 }
        harness.controller.voicePress.onRemoteRoutePreparation = { routeCount += 1 }

        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .unavailable(.primaryMappingFailed)
        )
        XCTAssertFalse(harness.mappingEnabled)
        XCTAssertEqual(
            harness.mappingCalls,
            [HIDMappingCall(enabled: true, key: .leftOption)],
            "dual mode must establish Receiver A's mapping before becoming active"
        )
        harness.controller.beginVoicePress(
            shortBinding: .voiceKeyDefault,
            source: .voiceKeyFilterFallback
        )

        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(prewarmCount, 0)
        XCTAssertEqual(routeCount, 0)
        XCTAssertTrue(harness.triggerEvents.isEmpty)
    }

    func testSecondaryOffLeavesLegacyMappingPathUntouched() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption
        )

        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: nil
            ),
            .applied(.legacy)
        )
        XCTAssertEqual(harness.controller.dualReceiverVoiceMode, .legacy)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        XCTAssertTrue(harness.mappingEnabled)
    }

    func testDisablingSecondaryRestoresSingleReceiverMapping() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [true, true],
            rawHIDReady: true,
            eventSuppressorReady: true
        )

        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: nil
            ),
            .applied(.legacy)
        )

        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [true, true])
        XCTAssertTrue(harness.mappingEnabled)
        XCTAssertEqual(harness.controller.dualReceiverVoiceMode, .legacy)
    }

    func testFailedLegacyMappingRestoreRemainsUnavailable() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [true, false],
            rawHIDReady: true,
            eventSuppressorReady: true
        )

        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: nil
            ),
            .unavailable(.legacyMappingRestoreFailed)
        )
        harness.controller.beginVoicePress(source: .voiceKeyFilterFallback)

        XCTAssertEqual(harness.controller.dualReceiverVoiceMode, .unavailable(.legacyMappingRestoreFailed))
        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [true, true])
    }

    func testSuccessfulDualModeKeepsPrimaryMappingBeforeBecomingActive() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [true],
            rawHIDReady: true,
            eventSuppressorReady: true
        )

        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )
        XCTAssertEqual(
            harness.mappingCalls,
            [HIDMappingCall(enabled: true, key: .leftOption)]
        )
        XCTAssertTrue(harness.mappingEnabled)
    }

    func testDualModeChangeRejectsFirstTapAndSecondTapOwnership() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        let recognizer = harness.controller.dualReceiverVoiceGestureRecognizer

        _ = recognizer.handleDown(at: ProcessInfo.processInfo.systemUptime)
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .busy
        )
        XCTAssertTrue(harness.mappingCalls.isEmpty)

        recognizer.cancel()
        let downAt = ProcessInfo.processInfo.systemUptime
        _ = recognizer.handleDown(at: downAt)
        _ = recognizer.handleUp(at: downAt + 0.1)
        XCTAssertEqual(recognizer.stateForTesting, .awaitingSecondPress)
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .busy
        )
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        recognizer.cancel()
    }

    func testDualModeChangeRejectsVoiceTransactionAndReleaseDrainOwnership() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        harness.controller.beginVoicePress()
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .busy
        )
        harness.controller.voicePress.stop()

        harness.controller.voicePress.setRemoteStreaming(true)
        harness.controller.voicePress.keyDown(sessionID: UUID())
        waitForCoordinatorTiming(0.35)
        harness.controller.voicePress.setRemoteAudioAvailable()
        XCTAssertTrue(harness.controller.voicePress.keyUp())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .busy
        )
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        harness.controller.voicePress.stop()
    }

    func testDualModeChangeRejectsPhysicalReleaseOwnership() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        let gestureID = UUID()
        harness.filter.beginOptionDeferral(gestureID: gestureID)
        XCTAssertTrue(harness.filter.captureDeferredHardwareOptionEdge(.down, copiedEvent: nil))
        XCTAssertTrue(harness.filter.suppressDeferredHardwareTrigger(
            gestureID: gestureID,
            reason: "dual-mode-release-owner-test"
        ))

        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .busy
        )
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        XCTAssertTrue(harness.filter.resetSuppressedHardwareTrigger(
            gestureID: gestureID,
            reason: "dual-mode-release-owner-test-cleanup"
        ))
    }

    func testDualModeChangeRejectsRuntimeTriggerReconfiguration() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyDelay: 0.15,
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        let expectation = expectation(description: "trigger reconfiguration completes")
        harness.controller.applyVoiceTriggerKey(.rightCommand) { _ in expectation.fulfill() }

        XCTAssertTrue(harness.controller.voiceTriggerReconfigurationInProgress)
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .busy
        )
        XCTAssertEqual(
            applySecondary(.rightOption, shortBinding: .preset(.disabled), to: harness.controller),
            .busy
        )
        XCTAssertNil(harness.persistedSecondaryKey)
        wait(for: [expectation], timeout: 5)
    }

    func testDualRawInputMappingAppliesPrimaryKeyBeforeTriggerEdges() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [true]
        )

        XCTAssertTrue(harness.controller.applyPrimaryRemoteVoiceHIDMappingForDualMode())

        XCTAssertEqual(
            harness.mappingCalls,
            [HIDMappingCall(enabled: true, key: .leftOption)]
        )
        XCTAssertFalse(harness.trigger.isOptionDown)
        XCTAssertNil(harness.trigger.activeSessionID)
    }

    func testStartupRestoreConfiguresFilterAndSyntheticTarget() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .rightCommand,
            persistedSecondaryKey: .leftControl
        )

        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.trigger.voiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.controller.currentSecondaryMomentaryVoiceTriggerKey, .leftControl)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
    }

    func testReceiverAChangeKeepsDeviceMappingOnPrimaryWhileDualModeIsActive() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            persistedSecondaryKey: .rightOption,
            applyResults: [true, true],
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            harness.controller.configureDualReceiverVoiceMode(
                shortBinding: .preset(.disabled),
                receiverB: .rightOption
            ),
            .applied(.active(receiverA: .leftOption, receiverB: .rightOption))
        )

        XCTAssertEqual(apply(.leftControl, to: harness.controller), .applied)

        XCTAssertEqual(
            harness.mappingCalls.map(\.enabled),
            [true, true],
            "dual mode must keep the F5 mapping enabled for the current Receiver A key"
        )
        XCTAssertEqual(
            harness.controller.dualReceiverVoiceMode,
            .active(receiverA: .leftControl, receiverB: .rightOption)
        )
        XCTAssertEqual(harness.controller.currentMomentaryVoiceTriggerKey, .leftControl)
        XCTAssertTrue(harness.mappingEnabled)
    }

    func testReceiverAChangingToReceiverBDisablesDualModeAndRestoresLegacyMapping() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [true, true],
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        XCTAssertEqual(
            applySecondary(.rightOption, shortBinding: .preset(.disabled), to: harness.controller),
            .applied
        )

        XCTAssertEqual(apply(.rightOption, to: harness.controller), .applied)

        XCTAssertEqual(
            harness.controller.dualReceiverVoiceMode,
            .legacy,
            "equal A/B keys must not retain dual-mode authority"
        )
        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [true, true])
        XCTAssertTrue(harness.mappingEnabled)
    }

    func testSecondaryTriggerChangePersistsIndependentlyAndActivatesEligibleMode() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            persistedPersistentKey: .leftCommand,
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())

        XCTAssertEqual(
            applySecondary(.rightOption, shortBinding: .preset(.disabled), to: harness.controller),
            .applied
        )

        XCTAssertEqual(harness.controller.currentMomentaryVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.currentPersistentSessionTriggerKey, .leftCommand)
        XCTAssertEqual(harness.controller.currentSecondaryMomentaryVoiceTriggerKey, .rightOption)
        XCTAssertEqual(harness.persistedSecondaryKey, .rightOption)
        XCTAssertEqual(
            harness.controller.dualReceiverVoiceMode,
            .active(receiverA: .leftOption, receiverB: .rightOption)
        )
        XCTAssertEqual(harness.secondaryPersistenceWriteCount, 1)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertEqual(harness.persistentPersistenceWriteCount, 0)
    }

    func testSecondaryTriggerChangeIsRejectedWhileTapOrVoiceOwnerIsPending() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        let recognizer = harness.controller.dualReceiverVoiceGestureRecognizer
        _ = recognizer.handleDown(at: ProcessInfo.processInfo.systemUptime)

        XCTAssertEqual(
            applySecondary(.rightOption, shortBinding: .preset(.disabled), to: harness.controller),
            .busy
        )
        XCTAssertNil(harness.persistedSecondaryKey)
        XCTAssertNil(harness.controller.currentSecondaryMomentaryVoiceTriggerKey)
        XCTAssertEqual(harness.secondaryPersistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        recognizer.cancel()

        let firstDownAt = ProcessInfo.processInfo.systemUptime
        _ = recognizer.handleDown(at: firstDownAt)
        _ = recognizer.handleUp(at: firstDownAt + 0.1)
        XCTAssertEqual(recognizer.stateForTesting, .awaitingSecondPress)
        XCTAssertEqual(
            applySecondary(.rightControl, shortBinding: .preset(.disabled), to: harness.controller),
            .busy
        )
        XCTAssertNil(harness.persistedSecondaryKey)
        recognizer.cancel()

        harness.controller.voicePress.setRemoteStreaming(true)
        harness.controller.voicePress.keyDown(sessionID: UUID())
        XCTAssertEqual(
            applySecondary(.rightControl, shortBinding: .preset(.disabled), to: harness.controller),
            .busyActiveHold
        )
        XCTAssertNil(harness.persistedSecondaryKey)
        XCTAssertEqual(harness.secondaryPersistenceWriteCount, 0)
        harness.controller.voicePress.stop()
    }

    func testSecondaryTriggerChangeIsRejectedDuringReleaseDrain() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            rawHIDReady: true,
            eventSuppressorReady: true
        )
        harness.controller.voicePress.setRemoteStreaming(true)
        harness.controller.voicePress.keyDown(sessionID: UUID())
        waitForCoordinatorTiming(0.35)
        harness.controller.voicePress.setRemoteAudioAvailable()
        XCTAssertTrue(harness.controller.voicePress.keyUp())

        XCTAssertEqual(
            applySecondary(.rightOption, shortBinding: .preset(.disabled), to: harness.controller),
            .busyReleaseDrain
        )
        XCTAssertNil(harness.persistedSecondaryKey)
        XCTAssertEqual(harness.secondaryPersistenceWriteCount, 0)
        harness.controller.voicePress.stop()
    }

    func testConnectedApplyConfiguresLocallyBeforeHIDAndPersistsAfterSuccess() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption
        )

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .applied)

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.trigger.voiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.persistedKey, .rightCommand)
        XCTAssertEqual(harness.mappingCalls.map(\.key), [.rightCommand])
        XCTAssertTrue(harness.mappingCalls[0].enabled)
        XCTAssertEqual(harness.mappingObservations[0].filterKey, .rightCommand)
        XCTAssertEqual(harness.mappingObservations[0].authorityKey, .leftOption)
        XCTAssertEqual(harness.mappingObservations[0].persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 1)
        XCTAssertFalse(harness.controller.voiceTriggerReconfigurationInProgress)
    }

    func testConnectedHIDFailureRollsBackWithoutInventingAbsentMapping() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: false,
            persistedKey: .leftOption,
            applyResults: [false]
        )

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .failed)

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.trigger.voiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.mappingCalls.map(\.key), [.rightCommand])
        XCTAssertFalse(harness.mappingEnabled)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertFalse(harness.controller.voiceTriggerRuntimeLocked)
        XCTAssertFalse(harness.controller.voiceTriggerReconfigurationInProgress)
        XCTAssertFalse(
            harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
                keyCode: VoiceTriggerKey.rightCommand.cgKeyCode
            )
        )
    }

    func testConnectedHIDFailureExplicitlyReappliesPreviousHardwareMapping() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [false, true]
        )

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .failed)

        XCTAssertEqual(harness.mappingCalls.map(\.key), [.rightCommand, .leftOption])
        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [true, true])
        XCTAssertTrue(harness.mappingEnabled)
        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
    }

    func testRollbackFailureLeavesRuntimeLockedAndRejectsNewPresses() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [false, false]
        )

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .locked)

        XCTAssertTrue(harness.controller.voiceTriggerRuntimeLocked)
        XCTAssertTrue(harness.controller.voiceTriggerReconfigurationInProgress)
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VK.voiceKey
        ))
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode
        ))
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.rightCommand.cgKeyCode
        ))
        harness.controller.beginVoicePress()
        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .idle)
        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
    }

    func testNewVoicePressIsRejectedWhileConnectedApplyIsInProgress() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyDelay: 0.15
        )
        let expectation = expectation(description: "connected apply completes")
        var result: VoiceTriggerApplyResult?

        harness.controller.applyVoiceTriggerKey(.rightCommand) {
            result = $0
            expectation.fulfill()
        }

        XCTAssertTrue(harness.controller.voiceTriggerReconfigurationInProgress)
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VK.voiceKey
        ))
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode
        ))
        XCTAssertTrue(harness.controller.filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.rightCommand.cgKeyCode
        ))
        harness.controller.beginVoicePress()
        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .idle)

        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .applied)
    }

    func testDisconnectedApplyUpdatesLocalAndPersistedTargetsWithoutHID() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: false,
            mappingEnabled: false,
            persistedKey: .leftOption
        )

        XCTAssertEqual(apply(.rightControl, to: harness.controller), .applied)

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .rightControl)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .rightControl)
        XCTAssertEqual(harness.trigger.voiceTriggerKey, .rightControl)
        XCTAssertEqual(harness.persistedKey, .rightControl)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        XCTAssertEqual(harness.persistenceWriteCount, 1)
        XCTAssertFalse(harness.controller.voiceTriggerReconfigurationInProgress)
    }

    func testActiveSyntheticOwnershipRejectsChangeWithoutPersistence() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .leftOption)
        let sessionID = UUID()
        XCTAssertTrue(harness.trigger.begin(sessionID: sessionID))

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busyReleaseDrain)

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        _ = harness.trigger.abort(sessionID: sessionID)
    }

    func testActiveControllerVoicePressRejectsChangeWithoutPersistence() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .leftOption)
        harness.controller.beginVoicePress()
        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .pending)

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busyActiveHold)

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        harness.controller.voicePress.stop()
    }

    func testPersistentVoiceSessionAllowsMomentaryKeyReconfigurationWhileIdle() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .leftOption)
        XCTAssertTrue(
            harness.controller.voicePress.keyDown(
                sessionID: UUID(),
                togglesPersistentVoiceSession: true
            )
        )
        XCTAssertTrue(harness.controller.voicePress.keyUp())
        XCTAssertTrue(harness.controller.voicePress.persistentSessionActiveForTesting)
        waitForCoordinatorTiming(0.08)

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .applied)

        XCTAssertEqual(harness.controller.currentMomentaryVoiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.controller.filter.momentaryVoiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.trigger.momentaryVoiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.persistedKey, .rightCommand)
        XCTAssertEqual(harness.persistenceWriteCount, 1)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        XCTAssertEqual(harness.controller.currentPersistentSessionTriggerKey, .leftOption)
        harness.controller.voicePress.stop()
    }

    func testPersistentKeyCanChangeWhileOpenAndMomentaryKeyStaysIndependent() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            persistedPersistentKey: .rightCommand
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())
        harness.controller.voicePress.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true
        )
        XCTAssertTrue(harness.controller.voicePress.keyUp())
        XCTAssertTrue(harness.controller.voicePress.persistentSessionActiveForTesting)
        waitForCoordinatorTiming(0.08)

        XCTAssertEqual(applyPersistent(.leftControl, to: harness.controller), .applied)
        XCTAssertEqual(harness.controller.currentPersistentSessionTriggerKey, .leftControl)
        XCTAssertEqual(harness.controller.voicePress.persistentSessionTriggerOwnerKeyForTesting, .rightCommand)
        XCTAssertEqual(harness.controller.currentMomentaryVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.momentaryPersistenceWriteCount, 0)
        XCTAssertEqual(harness.persistentPersistenceWriteCount, 1)
        harness.controller.voicePress.stop()
    }

    func testMomentaryReconfigurationIsBusyDuringActivePersistentHoldAndTail() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .leftOption)
        harness.controller.voicePress.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true
        )
        XCTAssertTrue(harness.controller.voicePress.keyUp())
        harness.controller.voicePress.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        )

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busyActiveHold)
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .holding)
        harness.controller.voicePress.setRemoteAudioAvailable()
        XCTAssertTrue(harness.controller.voicePress.keyUp())
        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busyReleaseDrain)
        harness.controller.voicePress.stop()
    }

    func testMomentaryReconfigurationRemainsBusyWhileFilterOwnsDiscardedMappedEdges() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .leftOption)
        let gestureID = UUID()
        harness.filter.beginOptionDeferral(gestureID: gestureID)
        XCTAssertTrue(harness.filter.captureDeferredHardwareOptionEdge(.down, copiedEvent: nil))
        XCTAssertTrue(harness.filter.suppressDeferredHardwareTrigger(
            gestureID: gestureID,
            reason: "test-discard-owner"
        ))

        XCTAssertTrue(harness.filter.hasActiveHardwareTriggerOwnership)
        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busyReleaseDrain)
        XCTAssertTrue(harness.filter.resetSuppressedHardwareTrigger(
            gestureID: gestureID,
            reason: "test-cleanup"
        ))
    }

    func testBothTriggerReconfigurationsAreBusyWhilePersistentCloseIsDeferred() {
        let harness = VoiceTriggerRuntimeHarness(
            persistedKey: .leftOption,
            persistedPersistentKey: .rightOption
        )
        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())

        let press = harness.controller.voicePress
        let filter = harness.filter
        press.onHardwareOptionGateBegin = { filter.beginOptionDeferral(gestureID: $0) }
        press.onPersistentSessionTriggerTap = { gestureID, key, purpose in
            filter.emitPersistentShortTap(
                gestureID: gestureID,
                reason: "runtime-pending-toggle-test",
                triggerKey: key,
                purpose: purpose
            )
        }
        press.onDeferredPersistentSessionTriggerTap = { gestureID, key, purpose in
            filter.emitDeferredPersistentShortTap(
                gestureID: gestureID,
                triggerKey: key,
                purpose: purpose
            )
        }
        filter.onSuppressedHardwareTriggerSafelyClosed = { [weak press] ownerID in
            press?.suppressedHardwareGateDidClose(ownerID: ownerID)
        }
        filter.onSuppressedHardwareTriggerInvalidated = { [weak press] ownerID, reason in
            press?.suppressedHardwareGateWasInvalidated(ownerID: ownerID, reason: reason)
        }

        let openGestureID = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: openGestureID,
            togglesPersistentVoiceSession: true
        ))
        XCTAssertTrue(press.keyUp())
        waitForCoordinatorTiming(0.08)
        XCTAssertTrue(press.persistentSessionActiveForTesting)

        let oldOwner = UUID()
        filter.beginOptionDeferral(gestureID: oldOwner)
        guard let mappedDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: VoiceTriggerKey.leftOption.cgKeyCode,
            keyDown: true
        ) else {
            XCTFail("could not create mapped trigger-down event")
            press.stop()
            return
        }
        XCTAssertTrue(filter.captureDeferredHardwareOptionEdge(.down, copiedEvent: mappedDown))
        XCTAssertTrue(filter.suppressDeferredHardwareTrigger(
            gestureID: oldOwner,
            reason: "runtime-pending-toggle-test"
        ))
        XCTAssertTrue(filter.armSuppressedHardwareTriggerRelease(gestureID: oldOwner))
        XCTAssertTrue(filter.completeSuppressedHardwareTrigger(
            gestureID: oldOwner,
            reason: "runtime-pending-toggle-test"
        ))

        XCTAssertTrue(press.keyDown(
            sessionID: UUID(),
            togglesPersistentVoiceSession: true,
            usesHardwareOption: true
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyDown
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyUp
        ))
        waitForCoordinatorTiming(0.13)
        XCTAssertTrue(press.keyUp())
        XCTAssertTrue(press.hasPendingPersistentToggleForTesting)

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busyReleaseDrain)
        XCTAssertEqual(applyPersistent(.leftControl, to: harness.controller), .busyReleaseDrain)
        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.currentPersistentSessionTriggerKey, .rightOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertEqual(harness.persistentPersistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)

        XCTAssertTrue(filter.resetSuppressedHardwareTrigger(
            gestureID: oldOwner,
            reason: "test-cleanup"
        ))
        press.stop()
    }

    func testSameKeyIsNoOpEvenWhenAnExistingGestureOwnsTheTrigger() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .leftOption)
        let sessionID = UUID()
        XCTAssertTrue(harness.trigger.begin(sessionID: sessionID))

        XCTAssertEqual(apply(.leftOption, to: harness.controller), .unchanged)

        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        _ = harness.trigger.abort(sessionID: sessionID)
    }

    func testAllSixKeysCanBeDisconnectedRuntimeTargets() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .leftOption)

        for key in VoiceTriggerKey.allCases {
            let expected: VoiceTriggerApplyResult = key == .leftOption ? .unchanged : .applied
            XCTAssertEqual(apply(key, to: harness.controller), expected)
            XCTAssertEqual(harness.controller.currentVoiceTriggerKey, key)
            XCTAssertEqual(harness.controller.filter.voiceTriggerKey, key)
            XCTAssertEqual(harness.trigger.voiceTriggerKey, key)
        }

        XCTAssertTrue(harness.mappingCalls.isEmpty)
        XCTAssertEqual(harness.persistedKey, .rightCommand)
    }

    func testReconfigurationGateSuppressesRawOldAndNewKeysOnlyUntilEnded() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)

        XCTAssertTrue(filter.beginVoiceTriggerReconfiguration(from: .leftOption, to: .rightCommand))
        XCTAssertTrue(filter.shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: VK.voiceKey))
        XCTAssertTrue(filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode
        ))
        XCTAssertTrue(filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.rightCommand.cgKeyCode
        ))
        XCTAssertFalse(filter.shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: 49))

        filter.endVoiceTriggerReconfiguration()

        XCTAssertFalse(filter.shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: VK.voiceKey))
        XCTAssertFalse(filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode
        ))
        XCTAssertFalse(filter.shouldSuppressDuringVoiceTriggerReconfiguration(
            keyCode: VoiceTriggerKey.rightCommand.cgKeyCode
        ))
    }

    func testReconfigurationGateRejectsActiveFilterOwnership() {
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let sessionID = UUID()
        filter.beginOptionDeferral(gestureID: sessionID)

        XCTAssertFalse(filter.beginVoiceTriggerReconfiguration(from: .leftOption, to: .rightCommand))

        filter.cancelDeferredOption(gestureID: sessionID, reason: "test-cleanup")
    }

    func testRightSideModifiersAreIncludedInReleaseAllSet() {
        XCTAssertTrue(KeyInjector.releaseAllModifierKeyCodes.contains(54))
        XCTAssertTrue(KeyInjector.releaseAllModifierKeyCodes.contains(61))
        XCTAssertTrue(KeyInjector.releaseAllModifierKeyCodes.contains(62))
        XCTAssertEqual(KeyInjector.releaseAllModifierKeyCodes, [55, 54, 59, 62, 58, 61, 56])
    }

    private func apply(
        _ key: VoiceTriggerKey,
        to controller: AppController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VoiceTriggerApplyResult {
        let expectation = expectation(description: "apply \(key.rawValue)")
        var result: VoiceTriggerApplyResult?
        controller.applyVoiceTriggerKey(key) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        guard let result else {
            XCTFail("apply completion was not received", file: file, line: line)
            return .locked
        }
        return result
    }

    private func applyPersistent(
        _ key: VoiceTriggerKey,
        to controller: AppController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VoiceTriggerApplyResult {
        let expectation = expectation(description: "apply persistent key \(key.rawValue)")
        var result: VoiceTriggerApplyResult?
        controller.applyPersistentSessionTriggerKey(key) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        guard let result else {
            XCTFail("persistent-key apply completion was not received", file: file, line: line)
            return .locked
        }
        return result
    }

    private func applySecondary(
        _ key: VoiceTriggerKey?,
        shortBinding: ButtonBinding,
        to controller: AppController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VoiceTriggerApplyResult {
        let expectation = expectation(description: "apply secondary key \(key?.rawValue ?? "off")")
        var result: VoiceTriggerApplyResult?
        controller.applySecondaryVoiceTriggerKey(key, shortBinding: shortBinding) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        guard let result else {
            XCTFail("secondary-key completion was not received", file: file, line: line)
            return .locked
        }
        return result
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    private func firstQuickRelease(on controller: AppController) -> UUID {
        let downAt = ProcessInfo.processInfo.systemUptime
        controller.handleDualReceiverMicrophoneEdge(isDown: true, at: downAt)
        controller.handleDualReceiverMicrophoneEdge(isDown: false, at: downAt + 0.05)
        return controller.dualReceiverVoiceGestureRecognizer.currentGestureID!
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}

private struct HIDMappingCall: Equatable {
    let enabled: Bool
    let key: VoiceTriggerKey
}

private struct HIDMappingObservation {
    let filterKey: VoiceTriggerKey
    let authorityKey: VoiceTriggerKey
    let persistedKey: VoiceTriggerKey
}

private final class VoiceTriggerRuntimeHarness {
    private let lock = NSLock()
    private var mappingEnabledStorage: Bool
    private var persistedKeyStorage: VoiceTriggerKey
    private var persistedPersistentKeyStorage: VoiceTriggerKey
    private var persistedSecondaryKeyStorage: VoiceTriggerKey?
    private var plannedResults: [Bool]
    private var plannedReadbacks: [VoiceDiagnosticHIDVerification]
    private let applyDelay: TimeInterval
    private let readbackDelay: TimeInterval
    private let rawHIDReady: Bool
    private let eventSuppressorReady: Bool
    private let triggerEventRecorder = TriggerEventRecorder()
    private var mappingCallsStorage: [HIDMappingCall] = []
    private var mappingObservationsStorage: [HIDMappingObservation] = []
    private var persistenceWritesStorage: [VoiceTriggerKey] = []
    private var persistentPersistenceWritesStorage: [VoiceTriggerKey] = []
    private var secondaryPersistenceWritesStorage: [VoiceTriggerKey?] = []

    let trigger: VoiceOptionTrigger
    let filter: VoiceKeyFilter
    private(set) var controller: AppController!
    private(set) var voicePrewarmCount = 0
    private(set) var voiceActivationCount = 0
    private(set) var voiceCancelCount = 0

    init(
        connected: Bool = false,
        mappingEnabled: Bool = false,
        persistedKey: VoiceTriggerKey,
        persistedPersistentKey: VoiceTriggerKey = .leftOption,
        persistedSecondaryKey: VoiceTriggerKey? = nil,
        applyResults: [Bool] = [],
        applyDelay: TimeInterval = 0,
        readbackResults: [VoiceDiagnosticHIDVerification] = [.match],
        readbackDelay: TimeInterval = 0.02,
        rawHIDReady: Bool = true,
        eventSuppressorReady: Bool = true
    ) {
        mappingEnabledStorage = mappingEnabled
        persistedKeyStorage = persistedKey
        persistedPersistentKeyStorage = persistedPersistentKey
        persistedSecondaryKeyStorage = persistedSecondaryKey
        plannedResults = applyResults
        plannedReadbacks = readbackResults
        self.applyDelay = applyDelay
        self.readbackDelay = readbackDelay
        self.rawHIDReady = rawHIDReady
        self.eventSuppressorReady = eventSuppressorReady
        trigger = VoiceOptionTrigger(keyedEventSink: { [triggerEventRecorder] key, isDown in
            triggerEventRecorder.append(TriggerEdge(key: key, isDown: isDown))
        })
        filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        controller = nil
        let mappingApply: (Bool, VoiceTriggerKey) -> Bool = { [self] enabled, key in
            if applyDelay > 0 {
                Thread.sleep(forTimeInterval: applyDelay)
            }
            let appController = controller
            let filterKey = appController?.filter.voiceTriggerKey ?? .leftOption
            let authorityKey = appController?.currentVoiceTriggerKey ?? .leftOption
            lock.lock()
            let succeeded = plannedResults.isEmpty ? true : plannedResults.removeFirst()
            mappingEnabledStorage = succeeded && enabled
            mappingCallsStorage.append(HIDMappingCall(enabled: enabled, key: key))
            mappingObservationsStorage.append(
                HIDMappingObservation(
                    filterKey: filterKey,
                    authorityKey: authorityKey,
                    persistedKey: persistedKeyStorage
                )
            )
            lock.unlock()
            return succeeded
        }
        controller = AppController(
            filter: filter,
            voicePress: VoicePressCoordinator(optionTrigger: trigger),
            initiallyHIDConnected: connected,
            isVoiceHIDMappingEnabled: { [self] in
                lock.lock()
                defer { lock.unlock() }
                return mappingEnabledStorage
            },
            applyVoiceHIDMapping: mappingApply,
            applyVoiceHIDMappingWithReadback: { [self] enabled, key, completion in
                let succeeded = mappingApply(enabled, key)
                lock.lock()
                let verification = plannedReadbacks.isEmpty
                    ? .match
                    : plannedReadbacks.removeFirst()
                lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + readbackDelay) {
                    completion(verification)
                }
                return succeeded
            },
            rawHIDReadiness: { rawHIDReady },
            eventSuppressorReadiness: { eventSuppressorReady },
            prepareVoiceTransport: { [unowned self] in voicePrewarmCount += 1 },
            activateVoiceInput: { [unowned self] in voiceActivationCount += 1 },
            cancelVoiceTransportPreparation: { [unowned self] in voiceCancelCount += 1 },
            readPersistedVoiceTriggerKey: { [self] in
                lock.lock()
                defer { lock.unlock() }
                return persistedKeyStorage
            },
            persistVoiceTriggerKey: { [self] key in
                lock.lock()
                persistedKeyStorage = key
                persistenceWritesStorage.append(key)
                lock.unlock()
            },
            readPersistedPersistentSessionTriggerKey: { [self] in
                lock.lock()
                defer { lock.unlock() }
                return persistedPersistentKeyStorage
            },
            persistPersistentSessionTriggerKey: { [self] key in
                lock.lock()
                persistedPersistentKeyStorage = key
                persistentPersistenceWritesStorage.append(key)
                lock.unlock()
            },
            readPersistedSecondaryMomentaryVoiceTriggerKey: { [self] in
                lock.lock()
                defer { lock.unlock() }
                return persistedSecondaryKeyStorage
            },
            persistSecondaryMomentaryVoiceTriggerKey: { [self] key in
                lock.lock()
                persistedSecondaryKeyStorage = key
                secondaryPersistenceWritesStorage.append(key)
                lock.unlock()
            }
        )
    }

    var mappingEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return mappingEnabledStorage
    }

    var triggerEvents: [TriggerEdge] {
        triggerEventRecorder.events
    }

    var persistedKey: VoiceTriggerKey {
        lock.lock()
        defer { lock.unlock() }
        return persistedKeyStorage
    }

    var persistedSecondaryKey: VoiceTriggerKey? {
        lock.lock()
        defer { lock.unlock() }
        return persistedSecondaryKeyStorage
    }

    var mappingCalls: [HIDMappingCall] {
        lock.lock()
        defer { lock.unlock() }
        return mappingCallsStorage
    }

    var mappingObservations: [HIDMappingObservation] {
        lock.lock()
        defer { lock.unlock() }
        return mappingObservationsStorage
    }

    var persistenceWriteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return persistenceWritesStorage.count
    }

    var momentaryPersistenceWriteCount: Int { persistenceWriteCount }

    var persistentPersistenceWriteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return persistentPersistenceWritesStorage.count
    }

    var secondaryPersistenceWriteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return secondaryPersistenceWritesStorage.count
    }
}

private struct TriggerEdge: Equatable {
    let key: VoiceTriggerKey
    let isDown: Bool
}

private final class TriggerEventRecorder {
    private let lock = NSLock()
    private var storage: [TriggerEdge] = []

    func append(_ edge: TriggerEdge) {
        lock.lock()
        storage.append(edge)
        lock.unlock()
    }

    var events: [TriggerEdge] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
