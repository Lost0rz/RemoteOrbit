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
