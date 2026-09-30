import XCTest
@testable import RemoteOrbit

final class VoiceTriggerRuntimeTests: XCTestCase {
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

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busy)

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

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busy)

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        harness.controller.voicePress.stop()
    }

    func testPersistentVoiceSessionRejectsTriggerReconfigurationWithoutMutation() {
        let harness = VoiceTriggerRuntimeHarness(persistedKey: .leftOption)
        XCTAssertTrue(
            harness.controller.voicePress.keyDown(
                sessionID: UUID(),
                togglesPersistentVoiceSession: true
            )
        )
        XCTAssertTrue(harness.controller.voicePress.keyUp())
        XCTAssertTrue(harness.controller.voicePress.persistentSessionActiveForTesting)

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busy)

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.trigger.voiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        harness.controller.voicePress.stop()
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
    private var plannedResults: [Bool]
    private let applyDelay: TimeInterval
    private var mappingCallsStorage: [HIDMappingCall] = []
    private var mappingObservationsStorage: [HIDMappingObservation] = []
    private var persistenceWritesStorage: [VoiceTriggerKey] = []

    let trigger: VoiceOptionTrigger
    let filter: VoiceKeyFilter
    private(set) var controller: AppController!

    init(
        connected: Bool = false,
        mappingEnabled: Bool = false,
        persistedKey: VoiceTriggerKey,
        applyResults: [Bool] = [],
        applyDelay: TimeInterval = 0
    ) {
        mappingEnabledStorage = mappingEnabled
        persistedKeyStorage = persistedKey
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
}
