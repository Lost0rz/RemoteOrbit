import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceShortcutSettingsContractTests: XCTestCase {
    func testVoiceEditorHasCRUDRecordingAndNoTriggerModeSelector() throws {
        let source = try settingsSource()
        let editorStart = try XCTUnwrap(source.range(of: "private struct VoiceShortcutEditorSheet"))
        let recorderStart = try XCTUnwrap(source.range(of: "private struct VoiceShortcutRecorderSheet"))
        let editor = String(source[editorStart.lowerBound..<recorderStart.lowerBound])

        XCTAssertTrue(editor.contains("TextField(\"名称\""))
        XCTAssertTrue(editor.contains("录制快捷键…"))
        XCTAssertTrue(editor.contains("Button(\"保存\")"))
        XCTAssertFalse(editor.contains("触发方式"))
        XCTAssertFalse(editor.contains("ShortcutTriggerMode"))
    }

    func testSettingsAndMenuExposeLongOnlyContractAndSingleActiveSnapshot() throws {
        let settings = try settingsSource()
        XCTAssertTrue(settings.contains("按住达到约 300ms 开始直接远程语音；松开后等待输出收尾，再释放语音快捷键"))
        XCTAssertTrue(settings.contains("voiceShortcutPresentation.snapshot.entries"))
        XCTAssertTrue(settings.contains("voiceShortcutPresentation.snapshot.activeEntryID"))

        let main = try source("Sources/RemoteOrbit/main.swift")
        let menuStart = try XCTUnwrap(main.range(of: "private func rebuildVoiceInputProfileMenu()"))
        let menuEnd = try XCTUnwrap(main.range(of: "@objc private func selectVoiceInputProfile", range: menuStart.lowerBound..<main.endIndex))
        let menu = String(main[menuStart.lowerBound..<menuEnd.lowerBound])
        XCTAssertTrue(menu.contains("currentVoiceShortcutSnapshot.entries"))
        XCTAssertTrue(menu.contains("item.state = profile.id == currentVoiceInputProfile.id ? .on : .off"))
        XCTAssertTrue(menu.contains("管理语音快捷键"))
    }

    func testChordConfigurationDiagnosticsCoverBusyAndRollbackWithoutLabels() throws {
        let main = try source("Sources/RemoteOrbit/main.swift")
        for event in [
            "VOICE_SHORTCUT_CONFIG_BUSY",
            "VOICE_SHORTCUT_ROLLBACK_BEGIN",
            "VOICE_SHORTCUT_ROLLBACK_COMPLETE",
            "VOICE_SHORTCUT_ROLLBACK_FAILED",
        ] {
            XCTAssertTrue(main.contains(event), "missing configuration diagnostic \(event)")
        }

        let helperStart = try XCTUnwrap(main.range(of: "private func logVoiceShortcutConfiguration("))
        let helperEnd = try XCTUnwrap(main.range(of: "private func rollbackVoiceShortcutRuntime(", range: helperStart.lowerBound..<main.endIndex))
        let helper = String(main[helperStart.lowerBound..<helperEnd.lowerBound])
        XCTAssertTrue(helper.contains("entry?.diagnosticFields"))
        XCTAssertFalse(helper.contains("displayName"))
        XCTAssertFalse(helper.contains("transcription"))
        XCTAssertFalse(helper.contains("typed_text"))
    }

    private func settingsSource() throws -> String {
        try source("Sources/RemoteOrbit/KeyMapping/SettingsView.swift")
    }

    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
