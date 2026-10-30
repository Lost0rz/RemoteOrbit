import XCTest
@testable import RemoteOrbit

final class VoicePipelineSimplificationTests: XCTestCase {
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
        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(states, [.opening, .draining])
        XCTAssertEqual(events.map { $0.isDown }, [true])
        XCTAssertNotNil(completeDrain)

        completeDrain?()

        XCTAssertEqual(events.map { $0.isDown }, [true, false])
        XCTAssertEqual(events.map { $0.key }, [profile.triggerKey, profile.triggerKey])
        XCTAssertEqual(states.last, .idle)
        XCTAssertNil(press.capturedVoiceProfileForTesting)
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

        XCTAssertTrue(press.keyUp())
        XCTAssertEqual(order, ["gate-begin", "gate-release", "physical-up"])

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
