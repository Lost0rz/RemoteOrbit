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

    func testNavigationModelSwitchesBetweenGeneralAndVoiceShortcutsRoutes() {
        let navigation = SettingsNavigationModel()
        XCTAssertEqual(navigation.routeRequest.route, .general)

        navigation.navigate(to: .voiceShortcuts)
        let voiceRequest = navigation.routeRequest
        XCTAssertEqual(voiceRequest.route, .voiceShortcuts)

        navigation.navigate(to: .general)
        XCTAssertEqual(navigation.routeRequest.route, .general)
        XCTAssertNotEqual(navigation.routeRequest.id, voiceRequest.id)
    }

    func testInstalledApplicationsFilterExcludesBackgroundUninstallersAndRemoteOrbit() throws {
        let fm = FileManager.default
        let tempAppsDir = fm.temporaryDirectory
            .appendingPathComponent("RemoteOrbitApps-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempAppsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempAppsDir) }

        func writeApp(
            folderName: String,
            bundleID: String,
            displayName: String,
            backgroundOnly: Bool = false
        ) throws {
            let contents = tempAppsDir
                .appendingPathComponent(folderName, isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            var plist: [String: Any] = [
                "CFBundleIdentifier": bundleID,
                "CFBundleName": displayName,
            ]
            if backgroundOnly {
                plist["LSBackgroundOnly"] = true
            }
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }

        try writeApp(folderName: "Ghostty.app", bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")
        try writeApp(folderName: "ChatGPT.app", bundleID: "com.openai.codex", displayName: "ChatGPT")
        try writeApp(folderName: "BackgroundHelper.app", bundleID: "com.example.bg", displayName: "BG", backgroundOnly: true)
        try writeApp(folderName: "App Uninstaller.app", bundleID: "com.example.uninstaller", displayName: "Uninstaller")
        try writeApp(folderName: "RemoteOrbit.app", bundleID: "com.lost0rz.RemoteOrbit", displayName: "RemoteOrbit")
        try writeApp(folderName: "RemoteOrbit Test.app", bundleID: "com.lost0rz.RemoteOrbit.test", displayName: "RemoteOrbit Test")

        let choices = SettingsView.installedApplicationsChoices(applicationsDirectoryURL: tempAppsDir)
        XCTAssertEqual(choices.map(\.bundleIdentifier), ["com.openai.codex", "com.mitchellh.ghostty"])
        XCTAssertEqual(choices.map(\.displayName), ["Codex", "Ghostty"])
    }

    func testOrderedActionCategoriesKeepAppExclusiveShortcutsFirstAndIsolated() {
        let globalCategories = SettingsView.orderedActionCategories(for: .global)
        XCTAssertEqual(
            globalCategories,
            [.navigation, .editing, .selection, .media, .system, .applications]
        )

        let codexCategories = SettingsView.orderedActionCategories(for: .app("com.openai.codex"))
        XCTAssertEqual(
            Array(codexCategories.prefix(4)),
            [.chatGPTGeneral, .chatGPTChats, .chatGPTInputModes, .chatGPTWorkspaceBrowser]
        )
        XCTAssertFalse(codexCategories.contains(.ghostty))
        XCTAssertFalse(codexCategories.contains(.browser))
        XCTAssertFalse(codexCategories.contains(.applications))

        let ghosttyCategories = SettingsView.orderedActionCategories(for: .app("com.mitchellh.ghostty"))
        XCTAssertEqual(ghosttyCategories.first, .ghostty)
        XCTAssertFalse(ghosttyCategories.contains(.chatGPTGeneral))
        XCTAssertFalse(ghosttyCategories.contains(.obsidian))

        let chromeCategories = SettingsView.orderedActionCategories(for: .app("com.google.Chrome"))
        XCTAssertEqual(chromeCategories.first, .browser)
        XCTAssertFalse(chromeCategories.contains(.iina))

        let t3Categories = SettingsView.orderedActionCategories(for: .app("com.t3tools.t3code"))
        XCTAssertEqual(t3Categories.first, .t3Code)
        XCTAssertFalse(t3Categories.contains(.codeWorkspace))
        XCTAssertFalse(t3Categories.contains(.gemini))

        let antigravityCategories = SettingsView.orderedActionCategories(for: .app("com.google.antigravity"))
        XCTAssertEqual(antigravityCategories.first, .codeWorkspace)
        XCTAssertFalse(antigravityCategories.contains(.t3Code))

        let geminiCategories = SettingsView.orderedActionCategories(for: .app("com.google.GeminiMacOS"))
        XCTAssertEqual(geminiCategories.first, .gemini)
        XCTAssertFalse(geminiCategories.contains(.t3Code))
        XCTAssertFalse(geminiCategories.contains(.chatGPTChats))
    }
}
