import XCTest
@testable import RemoteOrbit

final class KeymapOverlayTests: XCTestCase {
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

    func testVoiceKeyDefaultShowsDoubaoShortAndRemoteLong() {
        let lines = KeymapPresentation.actionLines(
            for: .microphone,
            binding: .voiceKeyDefault,
            profile: MappingStore.defaultMicrophoneGestureProfile
        )

        XCTAssertEqual(lines.map(\.gesture), ["单击", "长按"])
        XCTAssertEqual(
            lines.map(\.action),
            ["豆包输入（电脑/外部麦克风）", "遥控器语音输入"]
        )
    }

    func testCodexVoiceChoiceShowsComputerVoiceChatAndRemoteLong() {
        let lines = KeymapPresentation.actionLines(
            for: .microphone,
            binding: .preset(.chatGPTStartVoiceChat),
            profile: MappingStore.defaultMicrophoneGestureProfile
        )

        XCTAssertEqual(lines.map(\.gesture), ["单击", "长按"])
        XCTAssertEqual(
            lines.map(\.action),
            ["Codex：开始语音对话", "遥控器语音输入"]
        )
    }

    func testDisabledMicrophoneShortInputKeepsRemoteLongInput() {
        let lines = KeymapPresentation.actionLines(
            for: .microphone,
            binding: .preset(.disabled),
            profile: MappingStore.defaultMicrophoneGestureProfile
        )

        XCTAssertEqual(lines.map(\.gesture), ["单击", "长按"])
        XCTAssertEqual(lines.map(\.action), ["禁用", "遥控器语音输入"])
    }

    func testTVLongPressDefaultsToCurrentKeymapInspection() {
        let profile = AppTemplatePresetLibrary.defaultKeymapInspectionProfile

        XCTAssertTrue(profile.isEnabled)
        XCTAssertEqual(profile.longPress, .preset(.inspectCurrentKeymap))
        XCTAssertEqual(profile.longPressBehavior, .triggerOnce)
    }
}
