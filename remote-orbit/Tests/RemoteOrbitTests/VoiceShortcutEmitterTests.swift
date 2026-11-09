import CoreGraphics
import IOKit.hidsystem
import XCTest
@testable import RemoteOrbit

final class VoiceShortcutEmitterTests: XCTestCase {
    func testCoordinatorWaitsForLongPromotionAndOutputDrainBeforeChordRelease() {
        let sink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(sink: sink, physicalModifierKeyCodesProvider: { [] })
        var syntheticOptionEvents: [(VoiceTriggerKey, Bool)] = []
        let optionTrigger = VoiceOptionTrigger(
            keyedEventSink: { syntheticOptionEvents.append(($0, $1)) }
        )
        var promoteCandidate: (() -> Void)?
        var drainOutput: (() -> Void)?
        let press = VoicePressCoordinator(
            optionTrigger: optionTrigger,
            voiceShortcutEmitter: emitter,
            candidateTimerFactory: { _, fire in
                promoteCandidate = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        let profile = VoiceInputProfile(
            id: "custom-option-f",
            displayName: "Option + F",
            binding: .chord(primaryKeyCode: 3, preview: "⌥F", modifierKeyCodes: [61])
        )

        XCTAssertTrue(press.keyDown(sessionID: UUID(), profile: profile))
        XCTAssertTrue(press.keyUp())
        XCTAssertTrue(sink.events.isEmpty)
        XCTAssertTrue(syntheticOptionEvents.isEmpty)

        XCTAssertTrue(press.keyDown(sessionID: UUID(), usesHardwareOption: true, profile: profile))
        promoteCandidate?()
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .keyDown])
        XCTAssertTrue(syntheticOptionEvents.isEmpty)
        press.onRemoteOutputDrain = { _, completion in drainOutput = completion }
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)

        XCTAssertEqual(sink.events.count, 2, "release must wait for the output-drain callback")
        drainOutput?()
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(sink.events.map(\.keyCode), [61, 3, 3, 61])
        XCTAssertTrue(syntheticOptionEvents.isEmpty)
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)
        press.stop()
    }

    func testCoordinatorRecordsStaleOutputDrainCallbackWithoutReleasingNewOwner() throws {
        let sink = RecordingVoiceShortcutSink()
        var diagnostics: [VoiceShortcutEmitterDiagnostic] = []
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { diagnostics.append($0) }
        )
        let press = VoicePressCoordinator(voiceShortcutEmitter: emitter)
        let profile = VoiceInputProfile(
            id: "entry-late-drain",
            displayName: "Private display label",
            binding: .chord(primaryKeyCode: 3, preview: "⌥F", modifierKeyCodes: [61])
        )
        var drain: (() -> Void)?
        press.onRemoteOutputDrain = { _, completion in drain = completion }

        XCTAssertTrue(press.keyDownForTesting(sessionID: UUID(), profile: profile))
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertNotNil(drain)
        drain?()
        let eventCountAfterDrain = sink.events.count
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)

        drain?()

        XCTAssertEqual(sink.events.count, eventCountAfterDrain)
        XCTAssertTrue(diagnostics.contains { $0.kind == .lateDrainCallbackIgnored })
        let late = try XCTUnwrap(diagnostics.first { $0.kind == .lateDrainCallbackIgnored })
        XCTAssertEqual(late.entryID, "entry-late-drain")
        XCTAssertEqual(late.fields["modifier_key_codes"] as? [Int], [61])
        XCTAssertNil(late.fields["display_name"])
        press.stop()
    }

    func testChordEdgesUseFixedModifierOrderAndReverseReleaseAfterPrimary() {
        let sink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(sink: sink, physicalModifierKeyCodesProvider: { [] })
        let sessionID = UUID()
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3,
            preview: "右 Command + 右 Option + F",
            modifierKeyCodes: [61, 54]
        )

        XCTAssertEqual(emitter.begin(sessionID: sessionID, binding: binding), .accepted)
        XCTAssertEqual(sink.events.map(\.keyCode), [61, 54, 3])
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .flagsChanged, .keyDown])
        XCTAssertTrue(sink.events[0].flags & CGEventFlags.maskAlternate.rawValue != 0)
        XCTAssertTrue(sink.events[1].flags & CGEventFlags.maskCommand.rawValue != 0)

        XCTAssertTrue(emitter.end(sessionID: sessionID))
        XCTAssertEqual(sink.events.map(\.keyCode), [61, 54, 3, 3, 54, 61])
        XCTAssertEqual(sink.events.map(\.kind), [
            .flagsChanged, .flagsChanged, .keyDown,
            .keyUp, .flagsChanged, .flagsChanged,
        ])
        XCTAssertEqual(sink.events[3].flags, sink.events[2].flags)
        XCTAssertFalse(sink.events[4].flags & CGEventFlags.maskCommand.rawValue != 0)
        XCTAssertTrue(sink.events[4].flags & CGEventFlags.maskAlternate.rawValue != 0)
        XCTAssertEqual(sink.events[5].flags, 0)
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)
    }

    func testModifierOnlyChordUsesFlagsChangedEdgesAndNoPrimaryKey() throws {
        let sink = RecordingVoiceShortcutSink()
        var diagnostics: [VoiceShortcutEmitterDiagnostic] = []
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { diagnostics.append($0) }
        )
        let sessionID = UUID()
        let binding = VoiceShortcutBinding.modifierChord(modifierKeyCodes: [58, 54])

        XCTAssertEqual(emitter.begin(sessionID: sessionID, entryID: "modifier-entry", binding: binding), .accepted)
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .flagsChanged])
        XCTAssertEqual(sink.events.map(\.keyCode), [54, 58])
        XCTAssertTrue(sink.events[0].flags & CGEventFlags.maskCommand.rawValue != 0)
        XCTAssertTrue(sink.events[1].flags & CGEventFlags.maskAlternate.rawValue != 0)

        XCTAssertTrue(emitter.end(sessionID: sessionID))
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .flagsChanged, .flagsChanged, .flagsChanged])
        XCTAssertEqual(sink.events.map(\.keyCode), [54, 58, 58, 54])
        XCTAssertEqual(sink.events.last?.flags, 0)
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)

        let diagnostic = try XCTUnwrap(diagnostics.first { $0.kind == .modifierDownPosted })
        XCTAssertEqual(diagnostic.fields["binding_kind"] as? String, "modifier_chord")
        XCTAssertEqual(diagnostic.fields["modifier_key_codes"] as? [Int], [54, 58])
        XCTAssertNil(diagnostic.fields["primary_key_code"])
        XCTAssertNil(diagnostic.fields["display_name"])
    }

    func testProductionCGEventConstructionPreservesModifierDirectionAndPhysicalSide() throws {
        let command = CGEventFlags.maskCommand.rawValue
        let option = CGEventFlags.maskAlternate.rawValue
        let rightCommand = UInt64(NX_DEVICERCMDKEYMASK)
        let leftCommand = UInt64(NX_DEVICELCMDKEYMASK)
        let leftOption = UInt64(NX_DEVICELALTKEYMASK)
        let cases: [(VoiceShortcutBinding, [UInt16], [UInt64])] = [
            (
                .modifierChord(modifierKeyCodes: [54, 58]),
                [54, 58],
                [command | rightCommand, command | option | rightCommand | leftOption,
                 command | rightCommand, 0]
            ),
            (
                .modifierChord(modifierKeyCodes: [55, 58]),
                [55, 58],
                [command | leftCommand, command | option | leftCommand | leftOption,
                 command | leftCommand, 0]
            ),
        ]

        for (binding, expectedDownKeyCodes, expectedFlags) in cases {
            let recordingSink = RecordingVoiceShortcutSink()
            let emitter = VoiceShortcutEmitter(
                sink: recordingSink,
                physicalModifierKeyCodesProvider: { [] }
            )
            let sessionID = UUID()

            XCTAssertEqual(emitter.begin(sessionID: sessionID, binding: binding), .accepted)
            XCTAssertTrue(emitter.end(sessionID: sessionID))

            let events = recordingSink.events
            XCTAssertEqual(
                events.map(\.keyCode),
                expectedDownKeyCodes + Array(expectedDownKeyCodes.reversed())
            )
            XCTAssertEqual(events.map(\.kind), Array(repeating: .flagsChanged, count: 4))
            XCTAssertEqual(events.map(\.flags), expectedFlags)

            for event in events {
                let construction = try XCTUnwrap(CGEventVoiceShortcutSink.makeEvent(event))
                XCTAssertEqual(
                    construction.constructorType,
                    CGEventType.flagsChanged,
                    "CoreGraphics constructs a modifier keycode as flagsChanged"
                )
                XCTAssertEqual(construction.event.type, CGEventType.flagsChanged)
                XCTAssertEqual(
                    construction.event.getIntegerValueField(.keyboardEventKeycode),
                    Int64(event.keyCode)
                )
                XCTAssertEqual(construction.event.flags.rawValue, event.flags)
                XCTAssertEqual(
                    construction.event.getIntegerValueField(.eventSourceUserData),
                    Key.syntheticMarker
                )
            }
        }

        var physicalKeyCodes: Set<UInt16> = []
        let recordingSink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(
            sink: recordingSink,
            physicalModifierKeyCodesProvider: { physicalKeyCodes }
        )
        let sessionID = UUID()
        let binding = VoiceShortcutBinding.modifierChord(modifierKeyCodes: [54, 58])

        XCTAssertEqual(emitter.begin(sessionID: sessionID, binding: binding), .accepted)
        physicalKeyCodes.insert(55)
        XCTAssertTrue(emitter.end(sessionID: sessionID))

        let releaseEvents = Array(recordingSink.events.suffix(2))
        XCTAssertEqual(releaseEvents.map(\.keyCode), [58, 54])
        XCTAssertTrue(releaseEvents.allSatisfy { $0.flags & command != 0 })
        XCTAssertEqual(
            releaseEvents.map(\.flags),
            [command | rightCommand | leftCommand, command | leftCommand]
        )
        XCTAssertFalse(recordingSink.events.contains { $0.keyCode == 55 })
        for event in releaseEvents {
            let construction = try XCTUnwrap(CGEventVoiceShortcutSink.makeEvent(event))
            XCTAssertEqual(construction.constructorType, CGEventType.flagsChanged)
            XCTAssertEqual(construction.event.flags.rawValue, event.flags)
        }
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)

        let primaryDown = try XCTUnwrap(CGEventVoiceShortcutSink.makeEvent(
            VoiceShortcutSyntheticEvent(kind: .keyDown, keyCode: 3, flags: command)
        ))
        let primaryUp = try XCTUnwrap(CGEventVoiceShortcutSink.makeEvent(
            VoiceShortcutSyntheticEvent(kind: .keyUp, keyCode: 3, flags: command)
        ))
        XCTAssertEqual(primaryDown.constructorType, CGEventType.keyDown)
        XCTAssertEqual(primaryDown.event.type, CGEventType.keyDown)
        XCTAssertEqual(primaryUp.constructorType, CGEventType.keyUp)
        XCTAssertEqual(primaryUp.event.type, CGEventType.keyUp)
    }

    func testModifierOnlyChordConflictAndFailedReleaseRetainOwnership() {
        let conflictSink = RecordingVoiceShortcutSink()
        let conflicting = VoiceShortcutEmitter(
            sink: conflictSink,
            physicalModifierKeyCodesProvider: { [58] }
        )
        let binding = VoiceShortcutBinding.modifierChord(modifierKeyCodes: [54, 58])
        XCTAssertEqual(
            conflicting.begin(sessionID: UUID(), binding: binding),
            .rejected(.physicalModifierConflict)
        )
        XCTAssertTrue(conflictSink.events.isEmpty)

        var failRightCommandRelease = true
        let sink = RecordingVoiceShortcutSink { event, _ in
            failRightCommandRelease
                && event.kind == .flagsChanged
                && event.keyCode == 54
                && event.flags & CGEventFlags.maskCommand.rawValue == 0
        }
        let emitter = VoiceShortcutEmitter(sink: sink, physicalModifierKeyCodesProvider: { [] })
        let first = UUID()
        let second = UUID()
        XCTAssertEqual(emitter.begin(sessionID: first, binding: binding), .accepted)
        XCTAssertFalse(emitter.end(sessionID: first))
        XCTAssertTrue(emitter.hasUnresolvedOwnership)
        XCTAssertTrue(emitter.hasPendingReleaseOwnership)
        XCTAssertFalse(sink.events.contains { $0.kind == .keyDown || $0.kind == .keyUp })

        XCTAssertEqual(
            emitter.begin(sessionID: second, binding: binding),
            .rejected(.unresolvedOwnership)
        )
        failRightCommandRelease = false
        XCTAssertEqual(emitter.begin(sessionID: second, binding: binding), .accepted)
        XCTAssertTrue(emitter.hasUnresolvedOwnership, "the new modifier-only session owns its down edges")
        XCTAssertEqual(sink.events.filter { $0.kind == .keyDown || $0.kind == .keyUp }, [])
        XCTAssertTrue(emitter.end(sessionID: second))
        XCTAssertFalse(emitter.hasUnresolvedOwnership)
    }

    func testPartialPrimaryConstructionFailureCompensatesOwnedModifier() {
        let sink = RecordingVoiceShortcutSink(eventConstructionFailureCallIndexes: [1])
        let emitter = VoiceShortcutEmitter(sink: sink, physicalModifierKeyCodesProvider: { [] })
        let sessionID = UUID()

        XCTAssertEqual(emitter.begin(
            sessionID: sessionID,
            binding: .chord(primaryKeyCode: 3, preview: "⌘F", modifierKeyCodes: [55])
        ), .rejected(.eventConstructionFailed))
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .flagsChanged])
        XCTAssertEqual(sink.events.map(\.keyCode), [55, 55])
        XCTAssertEqual(sink.events.last?.flags, 0)
        XCTAssertTrue(emitter.ownedSessionIDs.isEmpty)
    }

    func testLateDrainForRetiredSessionCannotReleaseNewOwner() {
        let sink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(sink: sink, physicalModifierKeyCodesProvider: { [] })
        let first = UUID()
        let second = UUID()
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3,
            preview: "⌥F",
            modifierKeyCodes: [58]
        )

        XCTAssertEqual(emitter.begin(sessionID: first, binding: binding), .accepted)
        XCTAssertTrue(emitter.end(sessionID: first))
        XCTAssertEqual(emitter.begin(sessionID: second, binding: binding), .accepted)
        let beforeLateEnd = sink.events

        XCTAssertFalse(emitter.end(sessionID: first))
        XCTAssertEqual(sink.events, beforeLateEnd)
        XCTAssertEqual(emitter.ownedSessionIDs, [second])
        XCTAssertTrue(emitter.abort(sessionID: second))
    }

    func testRepeatedPrimaryKeyUpFailureRetainsOwnershipAndBlocksNewSessions() {
        var failKeyUps = true
        var diagnostics: [VoiceShortcutEmitterDiagnostic] = []
        let sink = RecordingVoiceShortcutSink { event, _ in
            failKeyUps && event.kind == .keyUp
        }
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { diagnostics.append($0) }
        )
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3, preview: "⌥F", modifierKeyCodes: [58]
        )
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(emitter.begin(sessionID: first, binding: binding), .accepted)
        // Two release attempts fail on the primary keyUp: ownership is retained,
        // never silently dropped.
        XCTAssertFalse(emitter.end(sessionID: first))
        XCTAssertFalse(emitter.end(sessionID: first))
        XCTAssertTrue(emitter.hasUnresolvedOwnership)
        XCTAssertEqual(emitter.ownedSessionIDs, [first])
        XCTAssertTrue(diagnostics.contains { $0.kind == .primaryUpFailed })
        XCTAssertTrue(diagnostics.contains { $0.kind == .drainPending })
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .keyDown])

        // Unresolved ownership blocks a new chord session without posting edges.
        let eventsWhileStuck = sink.events
        XCTAssertEqual(
            emitter.begin(sessionID: second, binding: binding),
            .rejected(.unresolvedOwnership)
        )
        XCTAssertEqual(sink.events, eventsWhileStuck)

        // Recovery is bounded: once posts succeed again, the next begin attempt
        // finishes the pending release before admitting the new session.
        failKeyUps = false
        XCTAssertEqual(emitter.begin(sessionID: second, binding: binding), .accepted)
        XCTAssertFalse(emitter.hasPendingReleaseOwnership)
        XCTAssertTrue(emitter.hasUnresolvedOwnership, "the newly accepted session owns synthetic edges")
        XCTAssertTrue(diagnostics.contains { $0.kind == .releaseRecoveryAttempt })
        XCTAssertTrue(diagnostics.contains { $0.kind == .releaseRecovered })
        XCTAssertEqual(emitter.ownedSessionIDs, [second])
        XCTAssertEqual(sink.events.map(\.kind), [
            .flagsChanged, .keyDown,
            .keyUp, .flagsChanged,
            .flagsChanged, .keyDown,
        ])
        XCTAssertTrue(emitter.end(sessionID:second))
    }

    func testRepeatedModifierKeyUpFailureRetainsOwnershipAndRecoversOnRetry() {
        var failFinalRelease = true
        var diagnostics: [VoiceShortcutEmitterDiagnostic] = []
        let sink = RecordingVoiceShortcutSink { event, _ in
            failFinalRelease && event.kind == .flagsChanged && event.flags == 0
        }
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { diagnostics.append($0) }
        )
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3, preview: "⌥F", modifierKeyCodes: [58]
        )
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(emitter.begin(sessionID: first, binding: binding), .accepted)
        // Primary keyUp succeeds; the final modifier-up event is rejected twice.
        XCTAssertFalse(emitter.end(sessionID: first))
        XCTAssertFalse(emitter.end(sessionID: first))
        XCTAssertTrue(emitter.hasUnresolvedOwnership)
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged, .keyDown, .keyUp])
        XCTAssertTrue(diagnostics.contains { $0.kind == .modifierUpFailed })
        XCTAssertTrue(diagnostics.contains { $0.kind == .drainPending })

        let eventsWhileStuck = sink.events
        XCTAssertEqual(
            emitter.begin(sessionID: second, binding: binding),
            .rejected(.unresolvedOwnership)
        )
        XCTAssertEqual(sink.events, eventsWhileStuck)

        failFinalRelease = false
        XCTAssertEqual(emitter.begin(sessionID: second, binding: binding), .accepted)
        XCTAssertFalse(emitter.hasPendingReleaseOwnership)
        XCTAssertTrue(emitter.hasUnresolvedOwnership, "the newly accepted session owns synthetic edges")
        XCTAssertTrue(diagnostics.contains { $0.kind == .releaseRecovered })
        // The recovered release precedes the new session's edges.
        XCTAssertEqual(sink.events.map(\.kind), [
            .flagsChanged, .keyDown, .keyUp,
            .flagsChanged,
            .flagsChanged, .keyDown,
        ])
    }

    func testBeginCompensationFailureRetainsOwnershipUntilRecovered() {
        var failDownAndFinalRelease = true
        let sink = RecordingVoiceShortcutSink { event, _ in
            failDownAndFinalRelease
                && (event.kind == .keyDown || (event.kind == .flagsChanged && event.flags == 0))
        }
        let emitter = VoiceShortcutEmitter(sink: sink, physicalModifierKeyCodesProvider: { [] })
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3, preview: "⌥F", modifierKeyCodes: [58]
        )
        let first = UUID()
        let second = UUID()

        // Primary keyDown fails and the compensating modifier-up fails too:
        // the posted modifier-down must stay owned.
        XCTAssertEqual(
            emitter.begin(sessionID: first, binding: binding),
            .rejected(.postFailed)
        )
        XCTAssertTrue(emitter.hasUnresolvedOwnership)
        XCTAssertEqual(sink.events.map(\.kind), [.flagsChanged])

        let eventsWhileStuck = sink.events
        XCTAssertEqual(
            emitter.begin(sessionID: second, binding: binding),
            .rejected(.unresolvedOwnership)
        )
        XCTAssertEqual(sink.events, eventsWhileStuck)

        failDownAndFinalRelease = false
        XCTAssertEqual(emitter.begin(sessionID: second, binding: binding), .accepted)
        XCTAssertFalse(emitter.hasPendingReleaseOwnership)
        XCTAssertTrue(emitter.hasUnresolvedOwnership, "the newly accepted session owns synthetic edges")
        XCTAssertEqual(sink.events.map(\.kind), [
            .flagsChanged,
            .flagsChanged,
            .flagsChanged, .keyDown,
        ])
    }

    func testSameSidePhysicalModifierRejectsChordBeforePostingAnyEdge() {
        let sink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [61] }
        )
        let result = emitter.begin(
            sessionID: UUID(),
            entryID: "voice-shortcut-entry-1",
            binding: .chord(primaryKeyCode: 3, preview: "右 Option + F", modifierKeyCodes: [61])
        )

        XCTAssertEqual(result, .rejected(.physicalModifierConflict))
        XCTAssertTrue(sink.events.isEmpty)
        XCTAssertFalse(emitter.hasUnresolvedOwnership)
    }

    func testUnrelatedPhysicalModifierIsPreservedInSyntheticChordFlags() {
        let sink = RecordingVoiceShortcutSink()
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [55] },
            physicalModifierFlagsProvider: {
                CGEventFlags.maskCommand.rawValue
                    | CGEventFlags.maskAlphaShift.rawValue
                    | CGEventFlags.maskSecondaryFn.rawValue
            }
        )
        let sessionID = UUID()
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3,
            preview: "右 Option + F",
            modifierKeyCodes: [61]
        )

        XCTAssertEqual(
            emitter.begin(sessionID: sessionID, entryID: "entry-2", binding: binding),
            .accepted
        )
        XCTAssertTrue(sink.events[0].flags & CGEventFlags.maskCommand.rawValue != 0)
        XCTAssertTrue(sink.events[0].flags & CGEventFlags.maskAlphaShift.rawValue != 0)
        XCTAssertTrue(sink.events[0].flags & CGEventFlags.maskSecondaryFn.rawValue != 0)
        XCTAssertTrue(sink.events[0].flags & CGEventFlags.maskAlternate.rawValue != 0)
        XCTAssertTrue(sink.events[1].flags & CGEventFlags.maskCommand.rawValue != 0)
        XCTAssertTrue(sink.events[1].flags & CGEventFlags.maskAlphaShift.rawValue != 0)
        XCTAssertTrue(sink.events[1].flags & CGEventFlags.maskSecondaryFn.rawValue != 0)
        XCTAssertTrue(sink.events[1].flags & CGEventFlags.maskAlternate.rawValue != 0)
        XCTAssertTrue(emitter.end(sessionID: sessionID))
        XCTAssertTrue((sink.events.last?.flags ?? 0) & CGEventFlags.maskCommand.rawValue != 0)
        XCTAssertTrue((sink.events.last?.flags ?? 0) & CGEventFlags.maskAlphaShift.rawValue != 0)
    }

    func testRepeatedAbortReleaseFailureRemainsOwnedAndAbortAllReportsFailure() {
        var failKeyUps = true
        var diagnostics: [VoiceShortcutEmitterDiagnostic] = []
        let sink = RecordingVoiceShortcutSink { event, _ in
            failKeyUps && event.kind == .keyUp
        }
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { diagnostics.append($0) }
        )
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3, preview: "⌥F", modifierKeyCodes: [58]
        )
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(emitter.begin(sessionID: first, binding: binding), .accepted)
        XCTAssertFalse(emitter.abort(sessionID: first))
        XCTAssertFalse(emitter.abort(sessionID: first))
        XCTAssertFalse(emitter.abortAll(maxAttemptsPerSession: 2))
        XCTAssertEqual(emitter.ownedSessionIDs, [first])
        XCTAssertTrue(diagnostics.contains { $0.kind == .abortPending })
        XCTAssertEqual(
            emitter.begin(sessionID: second, binding: binding),
            .rejected(.unresolvedOwnership)
        )

        failKeyUps = false
        XCTAssertTrue(emitter.abortAll(maxAttemptsPerSession: 2))
        XCTAssertFalse(emitter.hasUnresolvedOwnership)
        XCTAssertTrue(diagnostics.contains { $0.kind == .abortReleased })
    }

    func testDiagnosticsRecordSafeChordIdentityOwnershipAndLifecycleOutcomes() throws {
        let sink = RecordingVoiceShortcutSink()
        var diagnostics: [VoiceShortcutEmitterDiagnostic] = []
        let emitter = VoiceShortcutEmitter(
            sink: sink,
            physicalModifierKeyCodesProvider: { [] },
            diagnosticSink: { diagnostics.append($0) }
        )
        let binding = VoiceShortcutBinding.chord(
            primaryKeyCode: 3,
            preview: "⌘⌥F",
            modifierKeyCodes: [54, 61]
        )
        let drainedSession = UUID()
        let abortedSession = UUID()

        XCTAssertEqual(
            emitter.begin(sessionID: drainedSession, entryID: "entry-safe-1", binding: binding),
            .accepted
        )
        XCTAssertTrue(emitter.end(sessionID: drainedSession))
        XCTAssertEqual(
            emitter.begin(sessionID: abortedSession, entryID: "entry-safe-1", binding: binding),
            .accepted
        )
        XCTAssertTrue(emitter.abort(sessionID: abortedSession))
        emitter.recordLateDrainCallback(
            sessionID: drainedSession,
            entryID: "entry-safe-1",
            binding: binding
        )

        let kinds = diagnostics.map(\.kind)
        XCTAssertTrue(kinds.contains(.primaryDownPosted))
        XCTAssertTrue(kinds.contains(.primaryUpPosted))
        XCTAssertTrue(kinds.contains(.drainReleased))
        XCTAssertTrue(kinds.contains(.abortRequested))
        XCTAssertTrue(kinds.contains(.abortReleased))
        XCTAssertTrue(kinds.contains(.lateDrainCallbackIgnored))

        let primaryDown = try XCTUnwrap(diagnostics.first { $0.kind == .primaryDownPosted })
        XCTAssertEqual(primaryDown.sessionID, drainedSession)
        XCTAssertEqual(primaryDown.entryID, "entry-safe-1")
        XCTAssertEqual(primaryDown.fields["binding_kind"] as? String, "chord")
        XCTAssertEqual(primaryDown.fields["primary_key_code"] as? Int, 3)
        XCTAssertEqual(primaryDown.fields["modifier_key_codes"] as? [Int], [61, 54])
        XCTAssertEqual(primaryDown.fields["session_ownership"] as? String, "owned")

        for diagnostic in diagnostics {
            XCTAssertNil(diagnostic.fields["display_name"])
            XCTAssertNil(diagnostic.fields["preview"])
            XCTAssertNil(diagnostic.fields["typed_text"])
            XCTAssertNil(diagnostic.fields["transcription"])
        }
    }
}

private final class RecordingVoiceShortcutSink: VoiceShortcutEventSink {
    private(set) var events: [VoiceShortcutSyntheticEvent] = []
    private let failingCallIndexes: Set<Int>
    private let eventConstructionFailureCallIndexes: Set<Int>
    private let failurePredicate: ((VoiceShortcutSyntheticEvent, Int) -> Bool)?
    private var callIndex = 0

    init(
        failingCallIndexes: Set<Int> = [],
        eventConstructionFailureCallIndexes: Set<Int> = [],
        failurePredicate: ((VoiceShortcutSyntheticEvent, Int) -> Bool)? = nil
    ) {
        self.failingCallIndexes = failingCallIndexes
        self.eventConstructionFailureCallIndexes = eventConstructionFailureCallIndexes
        self.failurePredicate = failurePredicate
    }

    func post(_ event: VoiceShortcutSyntheticEvent) -> VoiceShortcutEventPostResult {
        defer { callIndex += 1 }
        guard !eventConstructionFailureCallIndexes.contains(callIndex) else {
            return .eventConstructionFailed
        }
        guard !failingCallIndexes.contains(callIndex) else { return .postFailed }
        guard failurePredicate?(event, callIndex) != true else { return .postFailed }
        events.append(event)
        return .posted
    }
}
