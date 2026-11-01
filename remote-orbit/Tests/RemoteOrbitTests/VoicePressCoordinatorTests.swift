import XCTest
@testable import RemoteOrbit

final class VoicePressCoordinatorTests: XCTestCase {
    func testLongOnlyCandidateShortReleaseIsPrivateAndUsesBoundedDiscard() {
        var fireCandidateTimer: (() -> Void)?
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { events.append(($0, $1)) })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        var prewarmCount = 0
        var cancelCount = 0
        press.onHardwareOptionGateBeginResult = {
            filter.beginOptionDeferral(gestureID: $0)
        }
        press.onHardwareOptionGateShortDiscard = {
            filter.discardDeferredHardwareTrigger(
                gestureID: $0,
                reason: "short-candidate-test"
            )
        }
        press.onRemoteTransportPreparation = { prewarmCount += 1 }
        press.onRemoteTransportCancellation = { cancelCount += 1 }

        let sessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionID,
                usesHardwareOption: true,
                preparesRemoteTransport: true,
                directSession: true,
                longOnlyAdmission: true
            )
        )
        XCTAssertNotNil(fireCandidateTimer)
        XCTAssertTrue(press.hasLongOnlyCandidateForTesting)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(prewarmCount, 1)

        XCTAssertTrue(press.keyUp())
        XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionID)
        XCTAssertTrue(
            filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: .keyDown
            )
        )
        _ = filter.resetSuppressedHardwareTrigger(
            gestureID: sessionID,
            reason: "short-candidate-test-cleanup"
        )
        press.stop()
    }

    func testLongOnlyPromotionConfirmsBeforeLateMappedDownWithoutNoOptionResolution() {
        var fireCandidateTimer: (() -> Void)?
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { events.append(($0, $1)) })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        press.onHardwareOptionGateBeginResult = {
            filter.beginOptionDeferral(gestureID: $0)
        }
        press.onHardwareOptionGateLongConfirmed = {
            XCTAssertTrue(filter.confirmLongOption(gestureID: $0))
        }

        let sessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionID,
                usesHardwareOption: true,
                directSession: true,
                longOnlyAdmission: true
            )
        )
        fireCandidateTimer?()

        XCTAssertEqual(press.currentStateForTesting, .opening)
        XCTAssertTrue(filter.isOptionDeferralActive(for: sessionID))
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            filter.captureDeferredHardwareOptionEdgeForTesting(.down, copied: false)
        )
        XCTAssertFalse(filter.isOptionDeferralActive(for: sessionID))
        XCTAssertEqual(events.map { $0.1 }, [true])
        press.stop()
    }

    func testLongOnlyCandidateStressKeepsCandidateAndTimerOwnershipBounded() {
        var outstandingTimers = 0
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, _ in
            XCTFail("short-only stress must not deliver a trigger")
        })
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, _ in
                outstandingTimers += 1
                return VoicePressCandidateTimer {
                    outstandingTimers -= 1
                }
            }
        )
        _ = VoiceAttemptDiagnostics.shared.beginPhysicalAttempt()

        for _ in 0..<100_000 {
            XCTAssertTrue(
                press.keyDown(
                    sessionID: UUID(),
                    usesHardwareOption: false,
                    directSession: true,
                    longOnlyAdmission: true
                )
            )
            XCTAssertTrue(press.keyUp())
        }

        XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
        XCTAssertFalse(press.longOnlyCandidateTimerActiveForTesting)
        XCTAssertEqual(outstandingTimers, 0)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertNil(VoiceAttemptDiagnostics.shared.currentID)
        press.stop()
    }

    func testOverlapShortDoesNotPrepareOrCancelPriorTransportGrace() {
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        var fireCandidateTimer: (() -> Void)?
        var transportPreparations = 0
        var transportCancellations = 0
        var completeADrain: (() -> Void)?
        let trigger = VoiceOptionTrigger { _ in }
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        press.hasLivePhysicalCandidate = { true }
        press.onRemoteTransportPreparation = { transportPreparations += 1 }
        press.onRemoteTransportCancellation = { transportCancellations += 1 }
        press.onRemoteOutputDrain = { _, completion in completeADrain = completion }

        let sessionA = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionA,
            preparesRemoteTransport: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        fireCandidateTimer?()
        let attemptA = try! XCTUnwrap(VoiceAttemptDiagnostics.shared.currentID)
        let aTriggerDown = trigger.isOptionDown
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertNotNil(completeADrain, "A must retain terminal drain/grace ownership")

        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionB,
            preparesRemoteTransport: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertFalse(press.longOnlyCandidateOwnsTransportPrewarmForTesting)
        XCTAssertTrue(press.keyUp())

        XCTAssertEqual(transportPreparations, 1, "B must not prewarm through A's grace")
        XCTAssertEqual(transportCancellations, 0, "B SHORT must not cancel A's grace")
        XCTAssertEqual(VoiceAttemptDiagnostics.shared.currentID, attemptA)
        XCTAssertEqual(trigger.isOptionDown, aTriggerDown, "B SHORT must not mutate A's trigger owner")
        XCTAssertTrue(press.hasPendingTailForTesting || press.currentStateForTesting == .draining)
        completeADrain?()
        press.stop()
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
    }

    func testOverlapCandidateShortDoesNotEndInheritedDiagnosticAttempt() {
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        var fireCandidateTimer: (() -> Void)?
        var completeADrain: (() -> Void)?
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in },
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        press.hasLivePhysicalCandidate = { true }
        press.onRemoteOutputDrain = { _, completion in completeADrain = completion }

        let sessionA = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionA,
            directSession: true,
            longOnlyAdmission: true
        ))
        fireCandidateTimer?()
        let attemptA = try! XCTUnwrap(VoiceAttemptDiagnostics.shared.currentID)
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)

        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionB,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertFalse(press.longOnlyCandidateOwnsPhysicalAttemptForTesting)
        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(VoiceAttemptDiagnostics.shared.currentID, attemptA)

        completeADrain?()
        press.stop()
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)

        var idleFire: (() -> Void)?
        let idlePress = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _, _ in },
            candidateTimerFactory: { _, fire in
                idleFire = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        XCTAssertTrue(idlePress.keyDown(
            sessionID: UUID(),
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(idlePress.longOnlyCandidateOwnsPhysicalAttemptForTesting)
        XCTAssertTrue(idlePress.keyUp())
        idleFire?()
        XCTAssertNil(VoiceAttemptDiagnostics.shared.currentID)
        idlePress.stop()
    }

    func testShortTombstoneConsumesImmediateBDownAndPromotesSyntheticWithoutSecondDown() {
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        var fireCandidateTimer: (() -> Void)?
        var events: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { events.append(($0, $1)) })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        press.onHardwareOptionGateBeginResult = {
            filter.beginLongOnlyOptionDeferral(gestureID: $0)
        }
        press.onHardwareOptionGateBeginDeferredBehindShortDiscard = { _ in
            filter.hasShortTapDiscardOwnership
        }
        press.onHardwareOptionGateShortHandoffBegin = {
            filter.beginLongOnlySuppressionHandoff(gestureID: $0)
        }
        press.onHardwareOptionGateShortHandoffReleased = {
            filter.releaseLongOnlySuppressionHandoff(gestureID: $0)
        }
        press.onHardwareOptionGateShortDiscard = {
            filter.discardDeferredHardwareTrigger(
                gestureID: $0,
                reason: "tombstone-isolation-test"
            )
        }
        filter.onLongOnlySuppressionHandoffReady = { [weak press] gestureID in
            press?.longOnlyTriggerHandoffDidBecomeReady(sessionID: gestureID)
        }
        filter.onLongOnlySuppressionHandoffInvalidated = { [weak press] gestureID, reason in
            press?.longOnlyTriggerHandoffWasInvalidated(
                sessionID: gestureID,
                reason: reason
            )
        }
        press.onHardwareOptionGatePhysicalUp = {
            _ = filter.armSuppressedHardwareTriggerRelease(gestureID: $0)
        }
        press.onHardwareOptionGateOutputDrained = {
            filter.releaseHeldHardwareOption(
                gestureID: $0,
                reason: "synthetic-handoff-output-drained"
            )
        }
        filter.onSuppressedHardwareTriggerInvalidated = { [weak press] ownerID, reason in
            press?.suppressedHardwareGateWasInvalidated(ownerID: ownerID, reason: reason)
        }

        let sessionA = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionA,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionA)

        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionB,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(press.longOnlyCandidateUsesSyntheticHandoffForTesting)
        XCTAssertFalse(press.longOnlyCandidateTriggerOwnershipReadyForTesting)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionA)

        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyDown
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .flagsChanged
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyUp
        ))
        XCTAssertTrue(events.isEmpty)

        XCTAssertFalse(press.keyDown(
            sessionID: UUID(),
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ), "a third gesture must not steal B's one handoff slot")

        fireCandidateTimer?()
        XCTAssertTrue(press.longOnlyCandidateLongConfirmedForTesting)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionA)

        XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: sessionA
        ))
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionB)
        XCTAssertEqual(events.map(\.1), [true], "handoff must synthesize exactly one DOWN")
        XCTAssertFalse(filter.isOptionDeferralActive(for: sessionB))

        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyDown
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .flagsChanged,
            eventFlags: []
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyUp
        ))
        XCTAssertEqual(events.map(\.1), [true], "late B physical edges must stay suppressed")

        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: sessionB
        ))
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        press.stop()
        XCTAssertNil(VoiceAttemptDiagnostics.shared.currentID)
    }

    func testRepeatedShortPrefixAllowsLatestHeldGestureToPromote() {
        for shortPrefixCount in 2...4 {
            VoiceAttemptDiagnostics.shared.end(sessionID: nil)
            var fireCandidateTimer: (() -> Void)?
            var events: [(VoiceTriggerKey, Bool)] = []
            let trigger = VoiceOptionTrigger(keyedEventSink: { events.append(($0, $1)) })
            let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
            let press = VoicePressCoordinator(
                optionTrigger: trigger,
                candidateTimerFactory: { _, fire in
                    fireCandidateTimer = fire
                    return VoicePressCandidateTimer(cancelAction: {})
                }
            )
            press.onHardwareOptionGateBeginResult = {
                filter.beginLongOnlyOptionDeferral(gestureID: $0)
            }
            press.onHardwareOptionGateBeginDeferredBehindShortDiscard = { _ in
                filter.hasShortTapDiscardOwnership
            }
            press.onHardwareOptionGateShortHandoffBegin = {
                filter.beginLongOnlySuppressionHandoff(gestureID: $0)
            }
            press.onHardwareOptionGateShortHandoffReleased = {
                filter.releaseLongOnlySuppressionHandoff(gestureID: $0)
            }
            press.onHardwareOptionGateShortDiscard = {
                filter.discardDeferredHardwareTrigger(
                    gestureID: $0,
                    reason: "multi-short-prefix-test"
                )
            }
            filter.onLongOnlySuppressionHandoffReady = { [weak press] gestureID in
                press?.longOnlyTriggerHandoffDidBecomeReady(sessionID: gestureID)
            }
            filter.onLongOnlySuppressionHandoffInvalidated = { [weak press] gestureID, reason in
                press?.longOnlyTriggerHandoffWasInvalidated(
                    sessionID: gestureID,
                    reason: reason
                )
            }
            press.onHardwareOptionGatePhysicalUp = {
                _ = filter.armSuppressedHardwareTriggerRelease(gestureID: $0)
            }
            press.onHardwareOptionGateOutputDrained = {
                filter.releaseHeldHardwareOption(
                    gestureID: $0,
                    reason: "multi-short-prefix-output-drained"
                )
            }
            filter.onSuppressedHardwareTriggerInvalidated = { [weak press] ownerID, reason in
                press?.suppressedHardwareGateWasInvalidated(ownerID: ownerID, reason: reason)
            }

            let firstShort = UUID()
            XCTAssertTrue(press.keyDown(
                sessionID: firstShort,
                usesHardwareOption: true,
                directSession: true,
                longOnlyAdmission: true
            ))
            XCTAssertTrue(press.keyUp())
            XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, firstShort)
            XCTAssertTrue(events.isEmpty)

            for _ in 1..<shortPrefixCount {
                let additionalShort = UUID()
                XCTAssertTrue(press.keyDown(
                    sessionID: additionalShort,
                    usesHardwareOption: true,
                    directSession: true,
                    longOnlyAdmission: true
                ), "SHORT prefix count \(shortPrefixCount) must keep accepting released bounded handoffs")
                XCTAssertTrue(press.longOnlyCandidateUsesSyntheticHandoffForTesting)
                XCTAssertTrue(press.keyUp())
                XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
                XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, firstShort)
                XCTAssertTrue(events.isEmpty)
            }

            let finalLong = UUID()
            XCTAssertTrue(press.keyDown(
                sessionID: finalLong,
                usesHardwareOption: true,
                directSession: true,
                longOnlyAdmission: true
            ), "final LONG after \(shortPrefixCount) SHORT taps must be admitted")
            XCTAssertTrue(press.longOnlyCandidateUsesSyntheticHandoffForTesting)
            fireCandidateTimer?()
            XCTAssertTrue(press.longOnlyCandidateLongConfirmedForTesting)
            XCTAssertTrue(events.isEmpty)

            XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
                gestureID: firstShort
            ))
            XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, finalLong)
            XCTAssertEqual(events.map(\.1), [true])
            XCTAssertEqual(press.currentGestureIDForDiagnostics, finalLong)

            press.setRemoteStreaming(true)
            XCTAssertTrue(press.keyUp())
            press.setRemoteStreaming(false)
            XCTAssertEqual(events.map(\.1), [true, false])
            XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
                gestureID: finalLong
            ))
            XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
            press.stop()
            VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        }
    }

    func testCandidateReleasedWhileWaitingForShortTombstoneNeverPromotes() {
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        var fireCandidateTimer: (() -> Void)?
        var activations = 0
        let trigger = VoiceOptionTrigger(keyedEventSink: { _, isDown in
            if isDown { activations += 1 }
        })
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        press.onHardwareOptionGateBeginResult = {
            filter.beginLongOnlyOptionDeferral(gestureID: $0)
        }
        press.onHardwareOptionGateBeginDeferredBehindShortDiscard = { _ in
            filter.hasShortTapDiscardOwnership
        }
        press.onHardwareOptionGateShortHandoffBegin = {
            filter.beginLongOnlySuppressionHandoff(gestureID: $0)
        }
        press.onHardwareOptionGateShortHandoffReleased = {
            filter.releaseLongOnlySuppressionHandoff(gestureID: $0)
        }
        press.onHardwareOptionGateShortDiscard = {
            filter.discardDeferredHardwareTrigger(
                gestureID: $0,
                reason: "waiting-tombstone-test"
            )
        }
        filter.onLongOnlySuppressionHandoffReady = { [weak press] gestureID in
            press?.longOnlyTriggerHandoffDidBecomeReady(sessionID: gestureID)
        }
        filter.onLongOnlySuppressionHandoffInvalidated = { [weak press] gestureID, reason in
            press?.longOnlyTriggerHandoffWasInvalidated(
                sessionID: gestureID,
                reason: reason
            )
        }

        let sessionA = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionA,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(press.keyUp())

        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionB,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        fireCandidateTimer?()
        XCTAssertTrue(press.longOnlyCandidateLongConfirmedForTesting)
        XCTAssertTrue(press.keyUp())
        XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
        XCTAssertFalse(press.longOnlyCandidateTimerActiveForTesting)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionA)

        XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: sessionA
        ))
        XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionB)
        XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: sessionB
        ))
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertNil(VoiceAttemptDiagnostics.shared.currentID)
        press.stop()
    }

    func testOverlapHandoffStressLeavesNoCandidateOrSuppressionOwnership() {
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        var outstandingTimers = 0
        let operationCount = 64

        for iteration in 0..<operationCount {
            var events: [Bool] = []
            let trigger = VoiceOptionTrigger { events.append($0) }
            let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
            let press = VoicePressCoordinator(
                optionTrigger: trigger,
                candidateTimerFactory: { _, _ in
                    outstandingTimers += 1
                    return VoicePressCandidateTimer {
                        outstandingTimers -= 1
                    }
                }
            )
            wireLongOnlyHandoff(press: press, filter: filter)

            let sessionA = UUID()
            XCTAssertTrue(press.keyDown(
                sessionID: sessionA,
                usesHardwareOption: true,
                directSession: true,
                longOnlyAdmission: true
            ), "cancel iteration \(iteration) A down")
            XCTAssertTrue(press.keyUp(), "cancel iteration \(iteration) A up")

            let sessionB = UUID()
            XCTAssertTrue(press.keyDown(
                sessionID: sessionB,
                usesHardwareOption: true,
                directSession: true,
                longOnlyAdmission: true
            ), "cancel iteration \(iteration) B down")
            XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: .keyDown
            ))
            XCTAssertTrue(press.keyUp(), "cancel iteration \(iteration) B up")
            XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
                gestureID: sessionA
            ))
            XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
                gestureID: sessionB
            ))
            XCTAssertTrue(events.isEmpty, "cancel iteration \(iteration) emitted a trigger")
            XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
            XCTAssertFalse(press.longOnlyCandidateTimerActiveForTesting)
            XCTAssertNil(filter.pendingLongOnlySuppressionHandoffGestureIDForTesting)
            XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
            press.stop()
        }

        for iteration in 0..<operationCount {
            var events: [Bool] = []
            var fireCandidateTimer: (() -> Void)?
            let trigger = VoiceOptionTrigger { events.append($0) }
            let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
            let press = VoicePressCoordinator(
                optionTrigger: trigger,
                candidateTimerFactory: { _, fire in
                    outstandingTimers += 1
                    var finished = false
                    let finish = {
                        if !finished {
                            finished = true
                            outstandingTimers -= 1
                        }
                    }
                    fireCandidateTimer = {
                        finish()
                        fire()
                    }
                    return VoicePressCandidateTimer {
                        finish()
                    }
                }
            )
            wireLongOnlyHandoff(press: press, filter: filter)

            let sessionA = UUID()
            XCTAssertTrue(press.keyDown(
                sessionID: sessionA,
                usesHardwareOption: true,
                directSession: true,
                longOnlyAdmission: true
            ), "promote iteration \(iteration) A down")
            XCTAssertTrue(press.keyUp(), "promote iteration \(iteration) A up")

            let sessionB = UUID()
            XCTAssertTrue(press.keyDown(
                sessionID: sessionB,
                usesHardwareOption: true,
                directSession: true,
                longOnlyAdmission: true
            ), "promote iteration \(iteration) B down")
            XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
                type: .keyDown
            ))
            fireCandidateTimer?()
            XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
                gestureID: sessionA
            ))
            XCTAssertEqual(events, [true], "promote iteration \(iteration) must synthesize one DOWN")

            press.setRemoteStreaming(true)
            XCTAssertTrue(press.keyUp(), "promote iteration \(iteration) B up")
            press.setRemoteStreaming(false)
            XCTAssertEqual(events, [true, false])
            XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
                gestureID: sessionB
            ))
            XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
            XCTAssertFalse(press.longOnlyCandidateTimerActiveForTesting)
            XCTAssertNil(filter.pendingLongOnlySuppressionHandoffGestureIDForTesting)
            XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
            press.stop()
        }

        XCTAssertEqual(outstandingTimers, 0)
        XCTAssertNil(VoiceAttemptDiagnostics.shared.currentID)
    }

    func testShortTombstoneHandsOffBeforeThresholdWithoutEarlyPromotion() {
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        var fireCandidateTimer: (() -> Void)?
        var events: [Bool] = []
        let trigger = VoiceOptionTrigger { events.append($0) }
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        wireLongOnlyHandoff(press: press, filter: filter)

        let sessionA = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionA,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(press.keyUp())

        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionB,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyDown
        ))

        XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: sessionA
        ))
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionB)
        XCTAssertTrue(press.hasLongOnlyCandidateForTesting)
        XCTAssertTrue(press.longOnlyCandidateTriggerOwnershipReadyForTesting)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(press.currentStateForTesting, .idle)

        fireCandidateTimer?()
        XCTAssertEqual(events, [true])
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionB)
        XCTAssertFalse(press.hasLongOnlyCandidateForTesting)

        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(events, [true, false])
        XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: sessionB
        ))
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        press.stop()
    }

    func testHandoffShortAfterSuppressionTransferRetiresWithoutSyntheticTrigger() {
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        var fireCandidateTimer: (() -> Void)?
        var events: [Bool] = []
        let trigger = VoiceOptionTrigger { events.append($0) }
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        wireLongOnlyHandoff(press: press, filter: filter)

        let sessionA = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionA,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(press.keyUp())

        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionB,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyDown
        ))
        XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: sessionA
        ))
        XCTAssertTrue(press.keyUp())
        XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
        XCTAssertFalse(press.longOnlyCandidateTimerActiveForTesting)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(filter.suppressedHardwareTriggerSessionID, sessionB)

        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .flagsChanged,
            eventFlags: []
        ))
        XCTAssertTrue(filter.shouldSuppressDiscardedHardwareTriggerEvent(
            keyCode: VoiceTriggerKey.leftOption.cgKeyCode,
            type: .keyUp
        ))
        XCTAssertTrue(filter.completeSuppressedHardwareTriggerQuietPeriod(
            gestureID: sessionB
        ))
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        XCTAssertNil(filter.pendingLongOnlySuppressionHandoffGestureIDForTesting)
        fireCandidateTimer?()
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(VoiceAttemptDiagnostics.shared.currentID)
        press.stop()
    }

    func testHandoffDisconnectCancelsCandidateAndLeavesNoSuppressionOwner() {
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
        var fireCandidateTimer: (() -> Void)?
        let trigger = VoiceOptionTrigger { _ in }
        let filter = VoiceKeyFilter(syntheticOptionTrigger: trigger)
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            candidateTimerFactory: { _, fire in
                fireCandidateTimer = fire
                return VoicePressCandidateTimer(cancelAction: {})
            }
        )
        wireLongOnlyHandoff(press: press, filter: filter)
        filter.onSuppressedHardwareTriggerInvalidated = { [weak press] ownerID, reason in
            press?.suppressedHardwareGateWasInvalidated(ownerID: ownerID, reason: reason)
        }

        let sessionA = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionA,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertTrue(press.keyUp())

        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(
            sessionID: sessionB,
            usesHardwareOption: true,
            directSession: true,
            longOnlyAdmission: true
        ))
        XCTAssertEqual(filter.pendingLongOnlySuppressionHandoffGestureIDForTesting, sessionB)
        press.cancelLongOnlyCandidateForHIDRemoval()
        XCTAssertFalse(press.hasLongOnlyCandidateForTesting)
        XCTAssertFalse(press.longOnlyCandidateTimerActiveForTesting)
        XCTAssertEqual(
            filter.pendingLongOnlySuppressionHandoffGestureIDForTesting,
            sessionB
        )

        XCTAssertTrue(filter.resetSuppressedHardwareTrigger(
            gestureID: sessionA,
            reason: "disconnect"
        ))
        XCTAssertNil(filter.pendingLongOnlySuppressionHandoffGestureIDForTesting)
        XCTAssertNil(filter.suppressedHardwareTriggerSessionID)
        fireCandidateTimer?()
        XCTAssertNil(VoiceAttemptDiagnostics.shared.currentID)
        press.stop()
    }

    func testDisabledShortStartsTransportPreparationWithoutSkippingClassifier() {
        var events: [String] = []
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        press.onRemoteTransportPreparation = {
            events.append("BLE_PREPARE_REQUEST")
        }
        press.onRemoteRoutePreparation = {
            events.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                preparesRemoteTransport: true
            )
        )

        XCTAssertEqual(events, ["BLE_PREPARE_REQUEST"])
        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertFalse(press.shouldShowPendingVoiceUI)
        press.keyUp()
        press.stop()
    }

    func testDisabledShortWithPendingAudioHasNoVisibleOptionAction() {
        var optionEvents: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { optionEvents.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                preparesRemoteTransport: true
            )
        )
        AudioPipe.shared.feed(samples: Array(repeating: Int16(9), count: 64))
        press.setRemoteAudioAvailable()

        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertFalse(press.shouldShowPendingVoiceUI)
        XCTAssertTrue(optionEvents.isEmpty)
        XCTAssertTrue(press.keyUp())
        press.stop()
    }

    func testPendingRemoteAudioIsQueuedBeforeLongOptionActivation() {
        var order: [String] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { _ in
                order.append("OPTION_DOWN_RELEASE")
            }
        )
        press.onStateChanged = { state in
            if state == .holding {
                order.append("HOLD_CONFIRMED")
            }
        }
        press.onRemoteRoutePreparation = {
            order.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                preparesRemoteTransport: true
            )
        )
        AudioPipe.shared.feed(samples: Array(repeating: Int16(7), count: 320))
        press.setRemoteAudioAvailable()
        waitForCoordinatorTiming(0.35)

        XCTAssertEqual(
            order,
            ["HOLD_CONFIRMED", "REMOTE_ROUTE_PREPARATION", "OPTION_DOWN_RELEASE"]
        )
        press.keyUp()
        press.stop()
    }

    func testHardwareOptionUpWaitsForOutputDrain() {
        var order: [String] = []
        var completeOutputDrain: (() -> Void)?
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in
            XCTFail("hardware replay must not use synthetic Option")
        })
        press.onHardwareOptionGateBegin = { _ in
            order.append("OPTION_GATE_BEGIN")
        }
        press.onHardwareOptionGateLongReady = { _ in
            order.append("OPTION_DOWN_RELEASE")
        }
        press.onHardwareOptionGatePhysicalUp = { _ in
            order.append("PHYSICAL_UP")
        }
        press.onHardwareOptionGateOutputDrained = { _ in
            order.append("OPTION_UP_RELEASE")
        }
        press.onRemoteOutputDrain = { _, completion in
            order.append("WAIT_OUTPUT_DRAIN")
            completeOutputDrain = completion
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: true
            )
        )
        press.setRemoteStreaming(true)
        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)

        XCTAssertEqual(
            order,
            [
                "OPTION_GATE_BEGIN",
                "OPTION_DOWN_RELEASE",
                "PHYSICAL_UP",
                "WAIT_OUTPUT_DRAIN",
            ]
        )
        XCTAssertNotNil(completeOutputDrain)
        XCTAssertNotEqual(order.last, "OPTION_UP_RELEASE")

        completeOutputDrain?()

        XCTAssertEqual(order.last, "OPTION_UP_RELEASE")
        press.stop()
    }

    func testSyntheticOptionUpAlsoWaitsForOutputDrain() {
        var events: [Bool] = []
        var completeOutputDrain: (() -> Void)?
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        press.onRemoteOutputDrain = { _, completion in
            completeOutputDrain = completion
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteStreaming(true)
        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)

        XCTAssertEqual(events, [true])
        completeOutputDrain?()
        XCTAssertEqual(events, [true, false])
        press.stop()
    }

    func testHardwareLongReleasesOnlyThePhysicalGate() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var gateBegan = false
        var gateReleased = false
        press.onHardwareOptionGateBegin = { _ in gateBegan = true }
        press.onHardwareOptionGateLongReady = { _ in gateReleased = true }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true,
                usesHardwareOption: true
            )
        )
        press.setRemoteAudioAvailable()

        XCTAssertTrue(gateBegan)
        XCTAssertTrue(gateReleased)
        XCTAssertTrue(events.isEmpty)
        press.stop()
    }

    func testHardwareShortReplaysPhysicalGateWithoutSyntheticEvents() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var replayedSessionID: UUID?
        press.onHardwareOptionGateShortReplay = { sessionID in
            replayedSessionID = sessionID
        }

        let sessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionID,
                usesHardwareOption: true
            )
        )
        press.keyUp()

        XCTAssertEqual(replayedSessionID, sessionID)
        XCTAssertTrue(events.isEmpty)
        press.stop()
    }

    func testMappingUnavailableLongUsesBalancedSyntheticOwner() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        let sessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: sessionID,
                bypassesShortClassification: true,
                usesHardwareOption: false
            )
        )
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true])

        press.stop()
        XCTAssertEqual(events, [true, false])
    }

    func testShortShortLongStillPromotesTheFinalLongPress() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        press.keyUp()
        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        press.keyUp()
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testFourShortPressesDoNotPoisonTheNextLongPress() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        for _ in 0..<4 {
            XCTAssertTrue(press.keyDown(sessionID: UUID()))
            press.keyUp()
        }
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testLongStartRequestsBLEBeforeRemoteRoutePreparation() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var order: [String] = []
        press.onStateChanged = { state in
            if state == .holding {
                order.append("BLE_START_REQUEST")
            }
        }
        press.onRemoteRoutePreparation = {
            order.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        XCTAssertEqual(order, ["BLE_START_REQUEST", "REMOTE_ROUTE_PREPARATION"])
        press.stop()
    }

    func testRepressAfterPreviousRouteFinishesIsNotBlockedByOldTailWindow() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        let firstSessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID()
            )
        )
        XCTAssertEqual(
            press.lastRepressDecisionForTesting,
            "accepted-after-route-finished"
        )
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testRepressWithinHardwareBounceWindowIsRejected() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.05)

        XCTAssertFalse(press.keyDown(sessionID: UUID()))
        XCTAssertEqual(press.lastRepressDecisionForTesting, "release-bounce")
        press.stop()
    }

    func testRepressAfterHardwareDebounceButBeforeOldRouteFinishDoesNotStartSecondLongSession() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        XCTAssertEqual(
            press.lastRepressDecisionForTesting,
            "deferred-previous-tail-active"
        )
        XCTAssertNotNil(press.pendingRepressSessionID)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        press.stop()
    }

    func testNormalLongTimingUnchanged() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var order: [String] = []
        press.onStateChanged = { state in
            if state == .holding {
                order.append("HOLD_CONFIRMED")
            }
        }
        press.onRemoteRoutePreparation = {
            order.append("REMOTE_ROUTE_PREPARATION")
        }

        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        waitForCoordinatorTiming(0.35)

        XCTAssertEqual(order, ["HOLD_CONFIRMED", "REMOTE_ROUTE_PREPARATION"])
        press.stop()
    }

    func testRapidRepressDuringBLEAudioDrainIsDeferredAndReplayed() {
        var events: [Bool] = []
        var audioDrainPending = false
        var transportPreparations = 0
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        press.onRemoteTransportPreparation = {
            transportPreparations += 1
        }
        press.isVoiceSessionAdmissionBlocked = {
            audioDrainPending
        }

        let firstSessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(events, [true, false])
        waitForCoordinatorTiming(0.20)
        audioDrainPending = true

        let nextSessionID = UUID()
        XCTAssertTrue(
            press.keyDown(
                sessionID: nextSessionID,
                preparesRemoteTransport: true
            )
        )
        XCTAssertEqual(
            press.lastRepressDecisionForTesting,
            "deferred-audio-drain"
        )
        XCTAssertEqual(press.pendingRepressSessionID, nextSessionID)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertEqual(transportPreparations, 0)

        audioDrainPending = false
        press.voiceSessionAdmissionBecameAvailable()
        waitForCoordinatorTiming(0.02)

        XCTAssertNil(press.pendingRepressSessionID)
        XCTAssertEqual(press.currentStateForTesting, .pending)
        XCTAssertEqual(transportPreparations, 1)
        waitForCoordinatorTiming(0.35)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])

        // A late completion from Session A must not terminate Session B.
        press.invokeTailCompletionForTesting(sessionID: firstSessionID)
        XCTAssertEqual(press.currentGestureIDForDiagnostics, nextSessionID)
        XCTAssertEqual(events, [true, false, true])

        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(events, [true, false, true, false])
        press.stop()
    }

    func testNormalTailTimingUnchanged() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertEqual(press.tailDrainDelayForTesting, 0.80, accuracy: 0.001)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        XCTAssertTrue(press.hasPendingTailForTesting)
        press.stop()
    }

    func testOldTailCompletionCannotClearNewGesture() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        let firstSessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])

        press.invokeTailCompletionForTesting(sessionID: firstSessionID)

        XCTAssertEqual(events, [true, false, true])
        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertTrue(press.hasRemoteAudio)
        press.stop()
    }

    func testRepressDuringPreviousTailIsDeferredNotDropped() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)

        let deferredSessionID = UUID()
        XCTAssertTrue(press.keyDown(sessionID: deferredSessionID))
        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)
        XCTAssertEqual(states.last, .idle)
        press.stop()
    }

    func testDeferredRepressStartsWhenPreviousRouteFinishes() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.22)

        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        XCTAssertNotNil(press.pendingRepressSessionID)
        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.40)

        XCTAssertNil(press.pendingRepressSessionID)
        XCTAssertEqual(states.last, .holding)
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])
        press.stop()
    }

    func testDeferredRepressUsesOriginalPhysicalDownForHoldThreshold() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        waitForCoordinatorTiming(0.35)
        XCTAssertNotNil(press.pendingRepressSessionID)
        XCTAssertEqual(states.last, .idle)

        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testDeferredRepressReleasedBeforeTailFinishIsCancelled() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(press.keyDown(sessionID: UUID()))
        XCTAssertNotNil(press.pendingRepressSessionID)

        XCTAssertFalse(press.keyUp())
        XCTAssertNil(press.pendingRepressSessionID)
        press.setRemoteStreaming(false)
        XCTAssertEqual(events, [true, false])
        press.stop()
    }

    func testDeferredRepressDoesNotStartBleBeforePreviousRouteOff() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        var states: [VoicePressCoordinator.State] = []
        press.onStateChanged = { states.append($0) }

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        XCTAssertEqual(states.last, .idle)

        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(states.last, .holding)
        press.stop()
    }

    func testDeferredRepressStaleTailCompletionCannotClearActivatedGesture() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )
        let firstSessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: firstSessionID,
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        XCTAssertNotNil(press.pendingRepressSessionID)

        press.setRemoteStreaming(false)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])

        press.invokeTailCompletionForTesting(sessionID: firstSessionID)

        XCTAssertEqual(press.currentStateForTesting, .holding)
        XCTAssertTrue(press.hasRemoteAudio)
        XCTAssertEqual(events, [true, false, true])
        press.stop()
    }

    func testDeferredRepressWaitsUntilOldTransportCallbackStackFinishes() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        let deferredSessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)

        XCTAssertTrue(
            press.keyDown(
                sessionID: deferredSessionID,
                bypassesShortClassification: true
            )
        )
        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)

        // STREAMING_FALSE(A): A finishes logically, but B must not activate
        // inside the old BLE callback stack.
        press.setRemoteStreaming(false)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)
        XCTAssertTrue(press.hasDeferredRepressAwaitingActivationForTesting)

        // CONNECTION_FALSE(A): old teardown cleanup must preserve B.
        press.stopCurrentVoiceStatePreservingDeferredRepress()
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)

        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.stop()
    }

    func testOldConnectionFalseCannotCancelDeferredNextGesture() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })
        let deferredSessionID = UUID()

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: deferredSessionID,
                bypassesShortClassification: true
            )
        )

        press.setRemoteStreaming(false)
        press.stopCurrentVoiceStatePreservingDeferredRepress()

        XCTAssertEqual(press.pendingRepressSessionID, deferredSessionID)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.stop()
    }

    func testDeferredRepressActivatesAfterTeardownBarrier() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        press.setRemoteStreaming(false)
        XCTAssertEqual(events, [true, false])
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(events, [true, false])
        press.setRemoteAudioAvailable()
        XCTAssertEqual(events, [true, false, true])
        press.stop()
    }

    func testDeferredRepressReleasedDuringTeardownBarrierIsCancelled() {
        var events: [Bool] = []
        let press = VoicePressCoordinator(
            optionTrigger: VoiceOptionTrigger { events.append($0) }
        )

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteStreaming(false)

        XCTAssertFalse(press.keyUp())
        XCTAssertNil(press.pendingRepressSessionID)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertEqual(events, [true, false])
        press.stop()
    }

    func testNormalAudioStopPathUsesTheSameTeardownBarrier() {
        let press = VoicePressCoordinator(optionTrigger: VoiceOptionTrigger { _ in })

        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )
        press.setRemoteAudioAvailable()
        press.keyUp()
        waitForCoordinatorTiming(0.20)
        XCTAssertTrue(
            press.keyDown(
                sessionID: UUID(),
                bypassesShortClassification: true
            )
        )

        press.setRemoteStreaming(false)
        XCTAssertEqual(press.currentStateForTesting, .idle)
        XCTAssertTrue(press.hasDeferredRepressAwaitingActivationForTesting)
        waitForCoordinatorTiming(0.02)
        XCTAssertEqual(press.currentStateForTesting, .holding)
        press.stop()
    }

    private func wireLongOnlyHandoff(
        press: VoicePressCoordinator,
        filter: VoiceKeyFilter
    ) {
        press.onHardwareOptionGateBeginResult = {
            filter.beginLongOnlyOptionDeferral(gestureID: $0)
        }
        press.onHardwareOptionGateBeginDeferredBehindShortDiscard = { _ in
            filter.hasShortTapDiscardOwnership
        }
        press.onHardwareOptionGateShortHandoffBegin = {
            filter.beginLongOnlySuppressionHandoff(gestureID: $0)
        }
        press.onHardwareOptionGateShortHandoffReleased = {
            filter.releaseLongOnlySuppressionHandoff(gestureID: $0)
        }
        press.onHardwareOptionGateShortDiscard = {
            filter.discardDeferredHardwareTrigger(
                gestureID: $0,
                reason: "test-short-discard"
            )
        }
        press.onHardwareOptionGatePhysicalUp = {
            _ = filter.armSuppressedHardwareTriggerRelease(gestureID: $0)
        }
        press.onHardwareOptionGateOutputDrained = {
            filter.releaseHeldHardwareOption(
                gestureID: $0,
                reason: "test-output-drained"
            )
        }
        filter.onLongOnlySuppressionHandoffReady = { [weak press] gestureID in
            press?.longOnlyTriggerHandoffDidBecomeReady(sessionID: gestureID)
        }
        filter.onLongOnlySuppressionHandoffInvalidated = { [weak press] gestureID, reason in
            press?.longOnlyTriggerHandoffWasInvalidated(
                sessionID: gestureID,
                reason: reason
            )
        }
        filter.onSuppressedHardwareTriggerSafelyClosed = { [weak press] ownerID in
            press?.suppressedHardwareGateDidClose(ownerID: ownerID)
        }
        filter.onSuppressedHardwareTriggerInvalidated = { [weak press] ownerID, reason in
            press?.suppressedHardwareGateWasInvalidated(
                ownerID: ownerID,
                reason: reason
            )
        }
    }

    private func waitForCoordinatorTiming(_ interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }
}
