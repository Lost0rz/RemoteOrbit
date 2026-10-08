import XCTest
@testable import RemoteOrbit

final class VoiceTriggerRuntimeTests: XCTestCase {
    func testDualRawInputMappingClearRequestsEmptyMappingBeforeTriggerEdges() {
        let harness = VoiceTriggerRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [true]
        )

        XCTAssertTrue(harness.controller.clearRemoteVoiceHIDMappingForDualMode())

        XCTAssertEqual(
            harness.mappingCalls,
            [HIDMappingCall(enabled: false, key: .leftOption)]
        )
        XCTAssertFalse(harness.trigger.isOptionDown)
        XCTAssertNil(harness.trigger.activeSessionID)
    }

    func testStartupRestoreConfiguresFilterAndSyntheticTarget() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .rightCommand)

        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.trigger.voiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
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

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
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
    private var plannedResults: [Bool]
    private let applyDelay: TimeInterval
    private var mappingCallsStorage: [HIDMappingCall] = []
    private var mappingObservationsStorage: [HIDMappingObservation] = []
    private var persistenceWritesStorage: [VoiceTriggerKey] = []
    private var persistentPersistenceWritesStorage: [VoiceTriggerKey] = []

    let trigger: VoiceOptionTrigger
    let filter: VoiceKeyFilter
    private(set) var controller: AppController!

    init(
        connected: Bool = false,
        mappingEnabled: Bool = false,
        persistedKey: VoiceTriggerKey,
        persistedPersistentKey: VoiceTriggerKey = .leftOption,
        applyResults: [Bool] = [],
        applyDelay: TimeInterval = 0
    ) {
        mappingEnabledStorage = mappingEnabled
        persistedKeyStorage = persistedKey
        persistedPersistentKeyStorage = persistedPersistentKey
        plannedResults = applyResults
        self.applyDelay = applyDelay
        trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in })
        filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        controller = nil
        controller = AppController(
            filter: filter,
            voicePress: VoicePressCoordinator(optionTrigger: trigger),
            initiallyHIDConnected: connected,
            isVoiceHIDMappingEnabled: { [self] in
                lock.lock()
                defer { lock.unlock() }
                return mappingEnabledStorage
            },
            applyVoiceHIDMapping: { [self] enabled, key in
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
            },
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
            }
        )
    }

    var mappingEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return mappingEnabledStorage
    }

    var persistedKey: VoiceTriggerKey {
        lock.lock()
        defer { lock.unlock() }
        return persistedKeyStorage
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
}
