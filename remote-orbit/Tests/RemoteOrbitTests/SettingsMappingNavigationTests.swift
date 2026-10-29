import Foundation
import XCTest
@testable import RemoteOrbit

final class SettingsMappingNavigationTests: XCTestCase {
    func testMappingEntryResetsToGlobalMicrophoneAndGlobalTemplateSelection() {
        var scope = SettingsView.MappingScope.app("com.example.target")
        var selectedButton = RemoteButton.back
        var selectedTemplateTarget = SettingsView.TemplateTarget.template(UUID())

        SettingsView.resetMappingEditorEntry(
            scope: &scope,
            selectedButton: &selectedButton,
            selectedTemplateTarget: &selectedTemplateTarget
        )

        XCTAssertEqual(scope, .global)
        XCTAssertEqual(selectedButton, .microphone)
        XCTAssertEqual(selectedTemplateTarget, .none)
    }

    func testLeaveAndReenterResetsEditorSelectionAgain() {
        var scope = SettingsView.MappingScope.app("com.example.target")
        var selectedButton = RemoteButton.volumeUp
        var selectedTemplateTarget = SettingsView.TemplateTarget.template(UUID())

        // The first entry establishes the deterministic baseline.
        SettingsView.resetMappingEditorEntry(
            scope: &scope,
            selectedButton: &selectedButton,
            selectedTemplateTarget: &selectedTemplateTarget
        )

        // User edits within the mapping page are allowed to select an App/template.
        scope = .app("com.example.target")
        selectedButton = .home
        selectedTemplateTarget = .template(UUID())

        // Leaving and entering the section applies the same baseline again.
        SettingsView.resetMappingEditorEntry(
            scope: &scope,
            selectedButton: &selectedButton,
            selectedTemplateTarget: &selectedTemplateTarget
        )

        XCTAssertEqual(scope, .global)
        XCTAssertEqual(selectedButton, .microphone)
        XCTAssertEqual(selectedTemplateTarget, .none)
    }

    func testEntryResetDoesNotChangeAppTemplateRuntimeState() throws {
        let configurationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoteorbit-mapping-entry-(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configurationURL) }

        let store = MappingStore(configurationFileURL: configurationURL)
        let templateID = store.addTemplate(
            appBundleIdentifier: "com.example.target",
            appName: "Target",
            templateName: "Active"
        )
        let templatesBefore = store.templates(for: "com.example.target")
        let activeBefore = store.activeTemplate(for: "com.example.target")

        var scope = SettingsView.MappingScope.app("com.example.target")
        var selectedButton = RemoteButton.menu
        var selectedTemplateTarget = SettingsView.TemplateTarget.template(templateID)
        SettingsView.resetMappingEditorEntry(
            scope: &scope,
            selectedButton: &selectedButton,
            selectedTemplateTarget: &selectedTemplateTarget
        )

        XCTAssertEqual(store.templates(for: "com.example.target"), templatesBefore)
        XCTAssertEqual(store.activeTemplate(for: "com.example.target"), activeBefore)
        XCTAssertEqual(scope, .global)
        XCTAssertEqual(selectedButton, .microphone)
        XCTAssertEqual(selectedTemplateTarget, .none)
    }
}
