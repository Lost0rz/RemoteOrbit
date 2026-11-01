import XCTest
@testable import RemoteOrbit

final class PrimaryVoiceRuntimeTests: XCTestCase {
    func testStartupRestoreConfiguresControllerFilterAndSyntheticTarget() {
        let harness = PrimaryVoiceRuntimeHarness(persistedKey: .rightCommand)

        XCTAssertTrue(harness.controller.restoreVoiceTriggerRuntime())

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.controller.filter.voiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.trigger.voiceTriggerKey, .rightCommand)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
    }

    func testConnectedApplyCommitsFilterHIDMappingAndPersistence() {
        let harness = PrimaryVoiceRuntimeHarness(
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
        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [true])
        XCTAssertEqual(harness.persistenceWriteCount, 1)
        XCTAssertFalse(harness.controller.voiceTriggerReconfigurationInProgress)
    }

    func testConnectedHIDFailureRollsBackWithoutInventingAbsentMapping() {
        let harness = PrimaryVoiceRuntimeHarness(
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

    func testConnectedHIDFailureReappliesPreviousHardwareMapping() {
        let harness = PrimaryVoiceRuntimeHarness(
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

    func testRollbackFailureLocksRuntimeAndRejectsNewPresses() {
        let harness = PrimaryVoiceRuntimeHarness(
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
        let harness = PrimaryVoiceRuntimeHarness(
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

    func testDisconnectedApplyUpdatesLocalAndProfileCompatibleAuthorityWithoutHID() {
        let harness = PrimaryVoiceRuntimeHarness(
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
        let harness = PrimaryVoiceRuntimeHarness(persistedKey: .leftOption)
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

    func testActiveVoiceHoldRejectsChangeWithoutPersistence() {
        let harness = PrimaryVoiceRuntimeHarness(persistedKey: .leftOption)
        harness.controller.beginVoicePress()
        XCTAssertTrue(harness.controller.voicePress.promoteLongOnlyCandidateForTesting())
        XCTAssertEqual(harness.controller.voicePress.currentStateForTesting, .opening)

        XCTAssertEqual(apply(.rightCommand, to: harness.controller), .busyActiveHold)

        XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        harness.controller.voicePress.stop()
    }

    func testActiveHardwareSuppressionOwnershipRejectsChangeWithoutPersistence() {
        let harness = PrimaryVoiceRuntimeHarness(persistedKey: .leftOption)
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

    func testSameKeyIsNoOpEvenWhenAnExistingGestureOwnsTheTrigger() {
        let harness = PrimaryVoiceRuntimeHarness(persistedKey: .leftOption)
        let sessionID = UUID()
        XCTAssertTrue(harness.trigger.begin(sessionID: sessionID))

        XCTAssertEqual(apply(.leftOption, to: harness.controller), .unchanged)

        XCTAssertEqual(harness.persistedKey, .leftOption)
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        _ = harness.trigger.abort(sessionID: sessionID)
    }

    func testAllSixKeysCanBeDisconnectedPrimaryRuntimeTargets() {
        let harness = PrimaryVoiceRuntimeHarness(persistedKey: .leftOption)

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

private struct PrimaryVoiceMappingCall: Equatable {
    let enabled: Bool
    let key: VoiceTriggerKey
}

private final class PrimaryVoiceRuntimeHarness {
    private let lock = NSLock()
    private var mappingEnabledStorage: Bool
    private var persistedKeyStorage: VoiceTriggerKey
    private var plannedResults: [Bool]
    private let applyDelay: TimeInterval
    private var mappingCallsStorage: [PrimaryVoiceMappingCall] = []
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

        let mappingApply: (Bool, VoiceTriggerKey) -> Bool = { [self] enabled, key in
            if applyDelay > 0 {
                Thread.sleep(forTimeInterval: applyDelay)
            }
            lock.lock()
            let succeeded = plannedResults.isEmpty ? true : plannedResults.removeFirst()
            mappingEnabledStorage = succeeded && enabled
            mappingCallsStorage.append(PrimaryVoiceMappingCall(enabled: enabled, key: key))
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
            usePersistedVoiceProfile: false,
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

    var mappingCalls: [PrimaryVoiceMappingCall] {
        lock.lock()
        defer { lock.unlock() }
        return mappingCallsStorage
    }

    var persistenceWriteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return persistenceWritesStorage.count
    }
}
