import XCTest
@testable import RemoteOrbit

final class KeymapOverlayTests: XCTestCase {
    func testVoicePressUsesTheOriginalTapClassificationWindow() {
        XCTAssertEqual(VoicePressCoordinator.holdActivationThreshold, 0.30)
    }

    func testInspectCurrentKeymapIsSystemAction() {
        let action = ButtonAction.inspectCurrentKeymap

        XCTAssertEqual(action.displayName, "检查当前快捷映射")
        XCTAssertEqual(action.category, .system)
        XCTAssertTrue(ButtonBinding.preset(action).isUsableGestureAction)
    }

    func testActionLinesExposeSingleDoubleAndLongPress() {
        let profile = ButtonGestureProfile(
            isEnabled: true,
            doubleTap: .preset(.paste),
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld
        )

        let lines = KeymapPresentation.actionLines(
            for: .ok,
            binding: .preset(.returnKey),
            profile: profile
        )

        XCTAssertEqual(lines.map(\.gesture), ["单击", "双击", "长按 · 重复"])
        XCTAssertEqual(lines.map(\.action), ["Return", "粘贴", "Delete"])
    }

    func testGestureSlotsCanBeDisabledIndependently() {
        let profile = ButtonGestureProfile(
            isEnabled: true,
            doubleTap: .preset(.paste),
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld,
            doubleTapEnabled: false,
            longPressEnabled: true
        )

        let lines = KeymapPresentation.actionLines(
            for: .ok,
            binding: .preset(.returnKey),
            profile: profile
        )

        XCTAssertEqual(lines.map(\.gesture), ["单击", "长按 · 重复"])
        XCTAssertTrue(profile.usesAdvancedGestures)
    }

    func testMicrophonePresentationShowsOnlyRetainedRemoteLongVoice() {
        let lines = KeymapPresentation.actionLines(
            for: .microphone,
            binding: .voiceKeyDefault,
            profile: MappingStore.defaultMicrophoneGestureProfile
        )

        XCTAssertEqual(lines.map(\.gesture), ["长按"])
        XCTAssertEqual(lines.map(\.action), ["遥控器语音输入"])
    }

    func testMicrophonePresentationIgnoresLegacyCodexShortBinding() {
        let lines = KeymapPresentation.actionLines(
            for: .microphone,
            binding: .preset(.chatGPTStartVoiceChat),
            profile: MappingStore.defaultMicrophoneGestureProfile
        )

        XCTAssertEqual(lines.map(\.gesture), ["长按"])
        XCTAssertEqual(lines.map(\.action), ["遥控器语音输入"])
    }

    func testDisabledMicrophoneShortInputKeepsRemoteLongInput() {
        let lines = KeymapPresentation.actionLines(
            for: .microphone,
            binding: .preset(.disabled),
            profile: MappingStore.defaultMicrophoneGestureProfile
        )

        XCTAssertEqual(lines.map(\.gesture), ["长按"])
        XCTAssertEqual(lines.map(\.action), ["遥控器语音输入"])
    }

    func testVoiceKeyDefaultRoundTripsWithoutPersistentUserWording() throws {
        let encoded = try JSONEncoder().encode(ButtonBinding.voiceKeyDefault)
        let decoded = try JSONDecoder().decode(ButtonBinding.self, from: encoded)

        XCTAssertEqual(decoded, .voiceKeyDefault)
        XCTAssertEqual(decoded.displayName, "语音键默认（长按遥控器语音输入）")
        XCTAssertFalse(decoded.displayName.contains("持续会话"))
        XCTAssertFalse(decoded.displayName.contains("短按"))
    }

    func testOnlyShortVoiceInputsRequestTheLocalMicrophone() {
        XCTAssertFalse(
            VoicePressCoordinator.usesLocalMicrophone(forShortBinding: .voiceKeyDefault)
        )
        XCTAssertTrue(
            VoicePressCoordinator.usesLocalMicrophone(
                forShortBinding: .preset(.chatGPTStartVoiceChat)
            )
        )
        XCTAssertTrue(
            VoicePressCoordinator.usesLocalMicrophone(
                forShortBinding: .preset(.chatGPTStartDictation)
            )
        )
        XCTAssertFalse(
            VoicePressCoordinator.usesLocalMicrophone(
                forShortBinding: .preset(.disabled)
            )
        )
        XCTAssertFalse(
            VoicePressCoordinator.usesLocalMicrophone(
                forShortBinding: .preset(.returnKey)
            )
        )
    }

    func testOnlyDefaultVoiceBindingTogglesPersistentSession() {
        XCTAssertTrue(
            VoicePressCoordinator.togglesPersistentVoiceSession(
                forShortBinding: .voiceKeyDefault
            )
        )
        XCTAssertFalse(
            VoicePressCoordinator.togglesPersistentVoiceSession(
                forShortBinding: .preset(.chatGPTStartVoiceChat)
            )
        )
        XCTAssertFalse(
            VoicePressCoordinator.togglesPersistentVoiceSession(
                forShortBinding: .preset(.disabled)
            )
        )
    }

    func testTVLongPressDefaultsToCurrentKeymapInspection() {
        let profile = AppTemplatePresetLibrary.defaultKeymapInspectionProfile

        XCTAssertTrue(profile.isEnabled)
        XCTAssertEqual(profile.longPress, .preset(.inspectCurrentKeymap))
        XCTAssertEqual(profile.longPressBehavior, .triggerOnce)
    }
}
