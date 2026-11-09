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

    func testVoiceShortcutSelectionRejectsActiveHoldWithoutPersisting() {
        let harness = PrimaryVoiceRuntimeHarness(persistedKey: .leftOption)
        let originalData = harness.voiceShortcutData
        let proposed = harness.snapshotSelectingChord()
        harness.controller.beginVoicePress()
        XCTAssertTrue(harness.controller.voicePress.promoteLongOnlyCandidateForTesting())

        XCTAssertEqual(update(proposed, on: harness.controller), .busyActiveHold)

        XCTAssertEqual(harness.controller.currentVoiceInputProfile.id, "system-left-option")
        XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot.activeEntryID, "system-left-option")
        XCTAssertEqual(harness.voiceShortcutData, originalData)
        XCTAssertTrue(harness.mappingCalls.isEmpty)
        harness.controller.voicePress.stop()
    }

    func testChordSelectionMappingFailureRestoresOldRuntimeAndSnapshot() {
        let harness = PrimaryVoiceRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption,
            applyResults: [false, true]
        )
        let originalData = harness.voiceShortcutData
        let proposed = harness.snapshotSelectingChord()

        XCTAssertEqual(update(proposed, on: harness.controller), .failed)

        XCTAssertEqual(harness.controller.currentVoiceInputProfile.id, "system-left-option")
        XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot.activeEntryID, "system-left-option")
        XCTAssertEqual(harness.voiceShortcutData, originalData)
        XCTAssertTrue(harness.mappingEnabled)
        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [false, true])
        XCTAssertEqual(harness.persistenceWriteCount, 0)
        XCTAssertFalse(harness.controller.voiceTriggerRuntimeLocked)
        XCTAssertFalse(harness.controller.voiceTriggerReconfigurationInProgress)
    }

    func testChordSelectionDisablesLegacyMappingBeforeSnapshotCommit() {
        let harness = PrimaryVoiceRuntimeHarness(
            connected: true,
            mappingEnabled: true,
            persistedKey: .leftOption
        )
        let proposed = harness.snapshotSelectingChord()

        XCTAssertEqual(update(proposed, on: harness.controller), .applied)

        XCTAssertNil(harness.controller.currentVoiceInputProfile.triggerKey)
        XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot.activeEntryID, "custom-chord")
        XCTAssertEqual(harness.voiceShortcutData, harness.voiceShortcutData(for: proposed))
        XCTAssertFalse(harness.mappingEnabled)
        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [false])
        XCTAssertEqual(harness.persistenceWriteCount, 0)
    }

    func testModifierChordActiveSwitchAtoBtoAWithoutRestartPreservesRuntimeAndDrain() {
        let sink = PrimaryVoiceChordEventSink()
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { _ in }
        )
        let harness = PrimaryVoiceRuntimeHarness(
            connected: true,
            mappingEnabled: false,
            persistedKey: .leftOption,
            voiceShortcutEmitter: emitter
        )
        let priorPresentationSnapshot = VoiceShortcutPresentation.shared.snapshot
        let priorPresentationReadOnlyReason = VoiceShortcutPresentation.shared.readOnlyReason

        var snapshotA = VoiceShortcutSnapshot.seeded()
        snapshotA.entries.append(contentsOf: [
            VoiceShortcutEntry(
                id: "modifier-a",
                displayName: "Left Option + Right Command",
                binding: .modifierChord(modifierKeyCodes: [54, 58])
            ),
            VoiceShortcutEntry(
                id: "modifier-b",
                displayName: "Left Option + Left Command",
                binding: .modifierChord(modifierKeyCodes: [55, 58])
            ),
        ])
        snapshotA.activeEntryID = "modifier-a"
        var snapshotB = snapshotA
        snapshotB.activeEntryID = "modifier-b"

        XCTAssertEqual(update(snapshotA, on: harness.controller), .applied)
        XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot, snapshotA)
        XCTAssertEqual(harness.controller.currentVoiceInputProfile.binding, snapshotA.activeEntry?.binding)
        XCTAssertEqual(VoiceShortcutPresentation.shared.snapshot, snapshotA)
        XCTAssertEqual(
            harness.voiceShortcutData,
            harness.voiceShortcutData(for: snapshotA)
        )
        XCTAssertFalse(harness.mappingEnabled)
        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [false])
        let mappingCallCount = harness.mappingCalls.count
        let filterConfigurationCount = harness.filter.configureVoiceTriggerKeyCallCountForTesting

        func assertActiveSnapshot(_ snapshot: VoiceShortcutSnapshot, entryID: String) {
            XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot, snapshot)
            XCTAssertEqual(harness.controller.currentVoiceInputProfile.id, entryID)
            XCTAssertEqual(harness.controller.currentVoiceInputProfile.binding, snapshot.activeEntry?.binding)
            XCTAssertEqual(VoiceShortcutPresentation.shared.snapshot, snapshot)
            XCTAssertEqual(
                harness.voiceShortcutData,
                harness.voiceShortcutData(for: snapshot)
            )
            XCTAssertEqual(
                harness.voiceShortcutDefaults.string(forKey: VoiceInputProfileStore.selectedProfileIDKey),
                entryID
            )
            XCTAssertFalse(harness.mappingEnabled)
            XCTAssertFalse(harness.controller.voiceTriggerReconfigurationInProgress)
            XCTAssertFalse(harness.filter.shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: VK.voiceKey))
            XCTAssertEqual(harness.controller.currentVoiceTriggerKey, .leftOption)
            XCTAssertEqual(harness.filter.momentaryVoiceTriggerKey, .leftOption)
            XCTAssertEqual(harness.trigger.voiceTriggerKey, .leftOption)
        }

        let coordinator = harness.controller.voicePress
        defer {
            coordinator.stop()
            VoiceShortcutPresentation.shared.replace(
                snapshot: priorPresentationSnapshot,
                readOnlyReason: priorPresentationReadOnlyReason
            )
        }
        var heldASessionDrain: (() -> Void)?
        coordinator.onRemoteOutputDrain = { _, completion in
            heldASessionDrain = completion
        }
        let heldASessionID = UUID()
        let heldAEventStart = sink.successfullyPostedEvents.count
        XCTAssertTrue(coordinator.keyDown(
            sessionID: heldASessionID,
            profile: harness.controller.currentVoiceInputProfile
        ))
        XCTAssertTrue(coordinator.promoteLongOnlyCandidateForTesting())
        XCTAssertEqual(coordinator.currentGestureIDForDiagnostics, heldASessionID)
        XCTAssertEqual(
            Array(sink.successfullyPostedEvents.suffix(2).map(\.keyCode)),
            [54, 58]
        )
        XCTAssertTrue(emitter.hasUnresolvedOwnership)
        coordinator.setRemoteStreaming(true)
        XCTAssertTrue(coordinator.keyUp())
        coordinator.setRemoteStreaming(false)
        XCTAssertEqual(coordinator.currentStateForTesting, .draining)
        XCTAssertNotNil(heldASessionDrain)
        XCTAssertEqual(sink.successfullyPostedEvents.count, heldAEventStart + 2)

        XCTAssertEqual(update(snapshotB, on: harness.controller), .busyActiveHold)
        assertActiveSnapshot(snapshotA, entryID: "modifier-a")
        XCTAssertEqual(sink.successfullyPostedEvents.count, heldAEventStart + 2)
        XCTAssertTrue(emitter.hasUnresolvedOwnership)

        heldASessionDrain?()
        XCTAssertEqual(
            Array(sink.successfullyPostedEvents.suffix(2).map(\.keyCode)),
            [58, 54],
            "owned modifier UP edges must follow output drain in reverse order"
        )
        XCTAssertFalse(emitter.hasUnresolvedOwnership)
        XCTAssertFalse(coordinator.hasUnresolvedVoiceShortcutOwnership)
        XCTAssertEqual(coordinator.currentStateForTesting, .idle)

        XCTAssertEqual(update(snapshotB, on: harness.controller), .applied)
        assertActiveSnapshot(snapshotB, entryID: "modifier-b")
        XCTAssertEqual(harness.mappingCalls.count, mappingCallCount)
        XCTAssertEqual(harness.filter.configureVoiceTriggerKeyCallCountForTesting, filterConfigurationCount)

        func exerciseActiveModifierChord(_ entryID: String, expectedDown: [UInt16], expectedUp: [UInt16]) {
            let eventStart = sink.successfullyPostedEvents.count
            var outputDrain: (() -> Void)?
            coordinator.onRemoteOutputDrain = { _, completion in outputDrain = completion }
            let sessionID = UUID()
            XCTAssertTrue(coordinator.keyDown(
                sessionID: sessionID,
                profile: harness.controller.currentVoiceInputProfile
            ))
            XCTAssertTrue(coordinator.promoteLongOnlyCandidateForTesting())
            XCTAssertEqual(coordinator.currentGestureIDForDiagnostics, sessionID)
            XCTAssertEqual(
                Array(sink.successfullyPostedEvents.suffix(2).map(\.keyCode)),
                expectedDown
            )
            XCTAssertEqual(
                Array(sink.successfullyPostedEvents.suffix(2).map(\.kind)),
                [.flagsChanged, .flagsChanged]
            )
            XCTAssertTrue(emitter.hasUnresolvedOwnership)
            coordinator.setRemoteStreaming(true)
            XCTAssertTrue(coordinator.keyUp())
            coordinator.setRemoteStreaming(false)
            XCTAssertNotNil(outputDrain)
            XCTAssertEqual(sink.successfullyPostedEvents.count, eventStart + 2)
            XCTAssertTrue(emitter.hasUnresolvedOwnership)

            outputDrain?()
            XCTAssertEqual(sink.successfullyPostedEvents.count, eventStart + 4)
            XCTAssertEqual(
                Array(sink.successfullyPostedEvents.suffix(2).map(\.keyCode)),
                expectedUp
            )
            XCTAssertEqual(
                Array(sink.successfullyPostedEvents.suffix(2).map(\.kind)),
                [.flagsChanged, .flagsChanged]
            )
            XCTAssertFalse(emitter.hasUnresolvedOwnership)
            XCTAssertFalse(coordinator.hasUnresolvedVoiceShortcutOwnership)
            XCTAssertEqual(coordinator.currentStateForTesting, .idle)
            XCTAssertEqual(harness.controller.currentVoiceInputProfile.id, entryID)
        }

        exerciseActiveModifierChord("modifier-b", expectedDown: [55, 58], expectedUp: [58, 55])

        XCTAssertEqual(update(snapshotA, on: harness.controller), .applied)
        assertActiveSnapshot(snapshotA, entryID: "modifier-a")
        XCTAssertEqual(harness.mappingCalls.count, mappingCallCount)
        XCTAssertEqual(harness.filter.configureVoiceTriggerKeyCallCountForTesting, filterConfigurationCount)
        exerciseActiveModifierChord("modifier-a", expectedDown: [54, 58], expectedUp: [58, 54])
        assertActiveSnapshot(snapshotA, entryID: "modifier-a")
        XCTAssertEqual(harness.mappingCalls.count, mappingCallCount)
        XCTAssertEqual(harness.filter.configureVoiceTriggerKeyCallCountForTesting, filterConfigurationCount)
    }

    func testModifierOnlyShortcutReleasesItsModifierEdgesAfterOutputDrain() {
        let sink = PrimaryVoiceChordEventSink()
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { _ in }
        )
        let harness = PrimaryVoiceRuntimeHarness(
            persistedKey: .leftOption,
            voiceShortcutEmitter: emitter
        )
        var snapshot = harness.snapshotSelectingChord()
        snapshot.entries[snapshot.entries.count - 1].binding =
            .modifierChord(modifierKeyCodes: [58, 55])
        XCTAssertEqual(update(snapshot, on: harness.controller), .applied)

        let coordinator = harness.controller.voicePress
        var outputDrain: (() -> Void)?
        coordinator.onRemoteOutputDrain = { _, completion in outputDrain = completion }
        XCTAssertTrue(coordinator.keyDownForTesting(
            sessionID: UUID(),
            profile: harness.controller.currentVoiceInputProfile
        ))
        XCTAssertEqual(sink.successfullyPostedEvents.map(\.kind), [.flagsChanged, .flagsChanged])
        XCTAssertEqual(sink.successfullyPostedEvents.map(\.keyCode), [55, 58])

        coordinator.setRemoteStreaming(true)
        XCTAssertTrue(coordinator.keyUp())
        coordinator.setRemoteStreaming(false)
        XCTAssertEqual(sink.successfullyPostedEvents.count, 2, "modifier release must wait for output drain")

        outputDrain?()
        XCTAssertEqual(
            sink.successfullyPostedEvents.map(\.kind),
            [.flagsChanged, .flagsChanged, .flagsChanged, .flagsChanged]
        )
        XCTAssertEqual(sink.successfullyPostedEvents.map(\.keyCode), [55, 58, 58, 55])
        XCTAssertFalse(sink.successfullyPostedEvents.contains { $0.kind == .keyDown || $0.kind == .keyUp })
        XCTAssertFalse(emitter.hasUnresolvedOwnership)
        coordinator.stop()
    }

    func testResidualChordOwnershipBlocksProfileSwitchUntilCoordinatorRecovery() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteOrbitTests.PrimaryVoiceRuntime.\(UUID().uuidString).jsonl")
        DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: true)
        let diagnosticLogger = VoiceDiagnosticLogger(fileURL: fileURL)
        diagnosticLogger.startRun()
        defer {
            diagnosticLogger.close()
            DiagnosticsRuntimeGate.shared.configureForTesting(loggingEnabled: false)
            try? FileManager.default.removeItem(at: fileURL)
        }

        let sink = PrimaryVoiceChordEventSink()
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { _ in }
        )
        let harness = PrimaryVoiceRuntimeHarness(
            persistedKey: .leftOption,
            voiceShortcutEmitter: emitter,
            diagnosticLogger: diagnosticLogger
        )
        let chordSnapshot = harness.snapshotSelectingChord()
        XCTAssertEqual(update(chordSnapshot, on: harness.controller), .applied)
        let committedChordBytes = try XCTUnwrap(harness.voiceShortcutData)
        let coordinator = harness.controller.voicePress
        coordinator.onRemoteOutputDrain = { _, completion in completion() }

        XCTAssertTrue(coordinator.keyDownForTesting(
            sessionID: UUID(),
            profile: harness.controller.currentVoiceInputProfile
        ))
        coordinator.setRemoteStreaming(true)
        XCTAssertTrue(coordinator.keyUp())
        coordinator.setRemoteStreaming(false)

        XCTAssertEqual(coordinator.currentStateForTesting, .idle)
        XCTAssertTrue(emitter.hasUnresolvedOwnership)
        XCTAssertTrue(coordinator.hasUnresolvedVoiceShortcutOwnership)
        XCTAssertTrue(emitter.hasPendingReleaseOwnership)

        var pureModifierSnapshot = chordSnapshot
        pureModifierSnapshot.activeEntryID = "system-left-option"
        XCTAssertEqual(
            update(pureModifierSnapshot, on: harness.controller),
            .busyReleaseDrain
        )
        XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot.activeEntryID, "custom-chord")
        XCTAssertEqual(harness.controller.currentVoiceInputProfile.id, "custom-chord")
        XCTAssertEqual(harness.voiceShortcutData, committedChordBytes)

        var secondChordSnapshot = chordSnapshot
        secondChordSnapshot.entries.append(VoiceShortcutEntry(
            id: "custom-chord-2",
            displayName: "Command H",
            binding: .chord(primaryKeyCode: 4, preview: "⌘H", modifierKeyCodes: [54])
        ))
        secondChordSnapshot.activeEntryID = "custom-chord-2"
        XCTAssertEqual(
            update(secondChordSnapshot, on: harness.controller),
            .busyReleaseDrain
        )
        XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot.activeEntryID, "custom-chord")
        XCTAssertEqual(harness.voiceShortcutData, committedChordBytes)
        XCTAssertEqual(harness.mappingCalls.map(\.enabled), [false])

        sink.failPrimaryKeyUps = false
        XCTAssertEqual(
            update(secondChordSnapshot, on: harness.controller),
            .applied,
            "the next configuration attempt retries and resolves the pending owner before switching"
        )
        XCTAssertFalse(emitter.hasUnresolvedOwnership)
        XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot.activeEntryID, "custom-chord-2")

        XCTAssertEqual(update(pureModifierSnapshot, on: harness.controller), .applied)
        XCTAssertEqual(harness.controller.currentVoiceShortcutSnapshot.activeEntryID, "system-left-option")
        XCTAssertEqual(
            harness.voiceShortcutData,
            harness.voiceShortcutData(for: pureModifierSnapshot)
        )

        diagnosticLogger.flush()
        let records = try String(contentsOf: fileURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        XCTAssertGreaterThanOrEqual(
            records.filter { $0["event"] as? String == "VOICE_SHORTCUT_PRIMARY_UP_FAILED" }.count,
            2,
            "drain and abort retry failures must be visible"
        )
        let busyRecords = records.filter {
            $0["event"] as? String == "VOICE_SHORTCUT_CONFIG_BUSY"
                && $0["reason"] as? String == "unresolved_voice_shortcut_synthetic_ownership"
        }
        XCTAssertTrue(busyRecords.contains { $0["entry_id"] as? String == "system-left-option" })
        XCTAssertTrue(busyRecords.contains { $0["entry_id"] as? String == "custom-chord-2" })
        for record in busyRecords {
            XCTAssertNil(record["display_name"])
            XCTAssertNil(record["preview"])
            XCTAssertNil(record["typed_text"])
            XCTAssertNil(record["transcription"])
        }
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

    private func update(
        _ snapshot: VoiceShortcutSnapshot,
        on controller: AppController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VoiceTriggerApplyResult {
        let expectation = expectation(description: "update voice shortcut snapshot")
        var result: VoiceTriggerApplyResult?
        controller.updateVoiceShortcutSnapshot(snapshot) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        guard let result else {
            XCTFail("voice shortcut snapshot completion was not received", file: file, line: line)
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
    private let defaultsSuiteName: String

    let trigger: VoiceOptionTrigger
    let filter: VoiceKeyFilter
    private(set) var controller: AppController!
    let voiceShortcutDefaults: UserDefaults

    init(
        connected: Bool = false,
        mappingEnabled: Bool = false,
        persistedKey: VoiceTriggerKey,
        applyResults: [Bool] = [],
        applyDelay: TimeInterval = 0,
        voiceShortcutEmitter: VoiceShortcutEmitter = VoiceShortcutEmitter(),
        diagnosticLogger: VoiceDiagnosticLogger? = nil
    ) {
        mappingEnabledStorage = mappingEnabled
        persistedKeyStorage = persistedKey
        plannedResults = applyResults
        self.applyDelay = applyDelay
        let defaultsSuiteName = "RemoteOrbitTests.PrimaryVoiceRuntime.\(UUID().uuidString)"
        self.defaultsSuiteName = defaultsSuiteName
        voiceShortcutDefaults = UserDefaults(suiteName: defaultsSuiteName)!
        voiceShortcutDefaults.removePersistentDomain(forName: defaultsSuiteName)
        let snapshotEncoder = JSONEncoder()
        snapshotEncoder.outputFormatting = [.sortedKeys]
        voiceShortcutDefaults.set(
            try? snapshotEncoder.encode(VoiceShortcutSnapshot.seeded()),
            forKey: VoiceShortcutStore.snapshotKey
        )
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

        let voicePress = VoicePressCoordinator(
            optionTrigger: trigger,
            voiceShortcutEmitter: voiceShortcutEmitter,
            diagnosticLogger: diagnosticLogger
        )
        controller = AppController(
            filter: filter,
            voicePress: voicePress,
            initiallyHIDConnected: connected,
            isVoiceHIDMappingEnabled: { [self] in
                lock.lock()
                defer { lock.unlock() }
                return mappingEnabledStorage
            },
            applyVoiceHIDMapping: mappingApply,
            usePersistedVoiceProfile: false,
            voiceShortcutDefaults: voiceShortcutDefaults,
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
            diagnosticLogger: diagnosticLogger ?? .shared
        )
    }

    deinit {
        voiceShortcutDefaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    var voiceShortcutData: Data? {
        voiceShortcutDefaults.data(forKey: VoiceShortcutStore.snapshotKey)
    }

    func snapshotSelectingChord() -> VoiceShortcutSnapshot {
        var snapshot = VoiceShortcutSnapshot.seeded()
        snapshot.entries.append(VoiceShortcutEntry(
            id: "custom-chord",
            displayName: "Command F",
            binding: .chord(primaryKeyCode: 3, preview: "⌘F", modifierKeyCodes: [55])
        ))
        snapshot.activeEntryID = "custom-chord"
        return snapshot
    }

    func voiceShortcutData(for snapshot: VoiceShortcutSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
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

private final class PrimaryVoiceChordEventSink: VoiceShortcutEventSink {
    var failPrimaryKeyUps = true
    private(set) var successfullyPostedEvents: [VoiceShortcutSyntheticEvent] = []

    func post(_ event: VoiceShortcutSyntheticEvent) -> VoiceShortcutEventPostResult {
        if failPrimaryKeyUps && event.kind == .keyUp {
            return .postFailed
        }
        successfullyPostedEvents.append(event)
        return .posted
    }
}
