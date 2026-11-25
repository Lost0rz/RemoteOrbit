import XCTest
@testable import RemoteOrbit

final class MappingStoreRoutingTests: XCTestCase {
    private let ownBundleIdentifier = "com.lost0rz.RemoteOrbit"

    func testManualConfigurationRoundTripPreservesMappingsWithoutExtraFiles() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("RemoteOrbitMappingStoreTests-\(UUID().uuidString)", isDirectory: true)
        let configurationURL = directory.appendingPathComponent("mapping-v3.json")
        let exportURL = directory.appendingPathComponent("exported.json")
        let suiteName = "RemoteOrbitMappingStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? fileManager.removeItem(at: directory)
        }

        let store = MappingStore(
            configurationFileURL: configurationURL,
            userDefaults: defaults
        )
        store.setBinding(.preset(.copy), for: .ok)
        store.setGestureProfile(
            ButtonGestureProfile(
                isEnabled: true,
                doubleTap: .preset(.paste),
                longPress: .preset(.deleteBackward),
                longPressBehavior: .repeatWhileHeld
            ),
            for: .ok
        )
        store.setGlobalPinning(false, for: .home, slot: .single)
        store.scrollLinesPerStep = 12
        let templateID = store.addTemplate(
            appBundleIdentifier: "com.example.MappingStoreTests",
            appName: "Mapping Store Tests",
            templateName: "Imported"
        )
        store.setBinding(.preset(.paste), for: .home, templateID: templateID)

        try store.exportCurrentConfiguration(to: exportURL)
        let exportedData = try Data(contentsOf: exportURL)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: exportedData))

        store.setBinding(.preset(.deleteBackward), for: .ok)
        store.scrollLinesPerStep = 2
        try store.importConfiguration(from: exportURL)

        XCTAssertEqual(store.binding(for: .ok), .preset(.copy))
        XCTAssertEqual(store.gestureProfile(for: .ok).doubleTap, .preset(.paste))
        XCTAssertFalse(store.isGloballyPinned(.home, slot: .single))
        XCTAssertEqual(store.scrollLinesPerStep, 12)
        XCTAssertEqual(store.template(withID: templateID)?.bindings[.home], .preset(.paste))
        XCTAssertEqual(
            store.activeTemplate(for: "com.example.MappingStoreTests")?.id,
            templateID
        )

        let storedFiles = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).map(\.lastPathComponent).sorted()
        XCTAssertEqual(storedFiles, ["exported.json", "mapping-v3.json"])
    }

    func testExternalFocusWinsOverFrontmostBridge() {
        let resolved = MappingStore.resolvedApplicationBundleIdentifier(
            focused: "com.openai.codex",
            frontmost: ownBundleIdentifier,
            cachedExternal: "com.mitchellh.ghostty",
            ownBundleIdentifier: ownBundleIdentifier
        )

        XCTAssertEqual(resolved, "com.openai.codex")
    }

    func testCachedExternalAppSurvivesBridgeMenuActivation() {
        let resolved = MappingStore.resolvedApplicationBundleIdentifier(
            focused: ownBundleIdentifier,
            frontmost: ownBundleIdentifier,
            cachedExternal: "com.openai.codex",
            ownBundleIdentifier: ownBundleIdentifier
        )

        XCTAssertEqual(resolved, "com.openai.codex")
    }

    func testNoExternalTargetFallsBackToGlobalMapping() {
        let resolved = MappingStore.resolvedApplicationBundleIdentifier(
            focused: ownBundleIdentifier,
            frontmost: ownBundleIdentifier,
            cachedExternal: nil,
            ownBundleIdentifier: ownBundleIdentifier
        )

        XCTAssertNil(resolved)
    }

    func testFrontmostExternalAppIsUsedWhenFocusIsUnavailable() {
        let resolved = MappingStore.resolvedApplicationBundleIdentifier(
            focused: nil,
            frontmost: "com.mitchellh.ghostty",
            cachedExternal: "com.openai.codex",
            ownBundleIdentifier: ownBundleIdentifier
        )

        XCTAssertEqual(resolved, "com.mitchellh.ghostty")
    }

    func testFrontmostExternalAppWinsOverStaleAccessibilityFocus() {
        let resolved = MappingStore.resolvedApplicationBundleIdentifier(
            focused: MappingStore.floatTabsBundleIdentifier,
            frontmost: MappingStore.codexBundleIdentifier,
            cachedExternal: "com.mitchellh.ghostty",
            ownBundleIdentifier: ownBundleIdentifier
        )

        XCTAssertEqual(resolved, MappingStore.codexBundleIdentifier)
    }

    func testFloatTabsFrontmostWinsOverWebKitChildFocus() {
        let resolved = MappingStore.resolvedApplicationBundleIdentifier(
            focused: "com.apple.WebKit.WebContent",
            frontmost: MappingStore.floatTabsBundleIdentifier,
            cachedExternal: "com.openai.codex",
            ownBundleIdentifier: ownBundleIdentifier
        )

        XCTAssertEqual(resolved, MappingStore.floatTabsBundleIdentifier)
    }

    func testFloatTabsSummonOnlyTogglesWhenFloatTabsIsFrontmost() {
        XCTAssertTrue(
            FloatTabsCommandClient.shouldToggleVisibility(
                frontmostBundleIdentifier: FloatTabsCommandClient.bundleIdentifier
            )
        )
        XCTAssertFalse(
            FloatTabsCommandClient.shouldToggleVisibility(
                frontmostBundleIdentifier: "com.apple.WebKit.WebContent"
            )
        )
        XCTAssertFalse(
            FloatTabsCommandClient.shouldToggleVisibility(
                frontmostBundleIdentifier: "com.apple.Safari"
            )
        )
    }

    func testMissingActiveTemplateIsRepairedToFirstTemplateForThatApp() {
        let firstID = UUID()
        let secondID = UUID()
        let templates = [
            AppMappingTemplate(
                id: firstID,
                appBundleIdentifier: MappingStore.codexBundleIdentifier,
                appName: "Codex",
                templateName: "默认"
            ),
            AppMappingTemplate(
                id: secondID,
                appBundleIdentifier: MappingStore.codexBundleIdentifier,
                appName: "Codex",
                templateName: "编辑"
            )
        ]

        let repaired = MappingStore.repairedActiveTemplateIDs(
            ["com.example.deleted": UUID()],
            templates: templates
        )

        XCTAssertEqual(repaired[MappingStore.codexBundleIdentifier], firstID)
        XCTAssertNil(repaired["com.example.deleted"])
    }

    func testValidActiveTemplateIsPreservedDuringRepair() {
        let activeID = UUID()
        let templates = [
            AppMappingTemplate(
                id: activeID,
                appBundleIdentifier: MappingStore.floatTabsBundleIdentifier,
                appName: "FloatTabs",
                templateName: "浏览"
            )
        ]

        let repaired = MappingStore.repairedActiveTemplateIDs(
            [MappingStore.floatTabsBundleIdentifier: activeID],
            templates: templates
        )

        XCTAssertEqual(repaired[MappingStore.floatTabsBundleIdentifier], activeID)
    }

    func testGlobalGesturePinningOnlyOverridesTheSelectedBehavior() {
        let global = ButtonGestureProfile(
            isEnabled: true,
            doubleTap: .preset(.copy),
            longPress: .preset(.deleteBackward),
            longPressBehavior: .repeatWhileHeld
        )
        let template = ButtonGestureProfile(
            isEnabled: true,
            doubleTap: .preset(.paste),
            longPress: .preset(.reloadPage),
            longPressBehavior: .triggerOnce
        )

        let merged = MappingStore.mergedGestureProfile(
            global: global,
            template: template,
            button: .ok,
            globallyPinnedSlots: [
                GlobalMappingKey(button: .ok, slot: .longPress)
            ]
        )

        XCTAssertEqual(merged.doubleTap, .preset(.paste))
        XCTAssertEqual(merged.longPress, .preset(.deleteBackward))
        XCTAssertEqual(merged.longPressBehavior, .repeatWhileHeld)
    }

    func testResetAllClearsGlobalPinningAndRestoresDefaultVolume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteOrbitResetAllTests-\(UUID().uuidString)", isDirectory: true)
        let configurationURL = directory.appendingPathComponent("mapping-v3.json")
        let suiteName = "RemoteOrbitResetAllTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = MappingStore(configurationFileURL: configurationURL, userDefaults: defaults)
        XCTAssertFalse(store.isGloballyPinned(.home))
        store.setGlobalPinning(true, for: .home)
        XCTAssertTrue(store.isGloballyPinned(.home))

        store.resetAll()
        XCTAssertFalse(store.isGloballyPinned(.home))
        XCTAssertEqual(store.binding(for: .volumeUp), .preset(.volumeUp))
        XCTAssertEqual(store.binding(for: .volumeDown), .preset(.volumeDown))
    }

    func testApplyTemplatePresetUpdatesExistingNamedPresetAndPreservesCodexGestures() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteOrbitApplyPresetTests-\(UUID().uuidString)", isDirectory: true)
        let configurationURL = directory.appendingPathComponent("mapping-v3.json")
        let suiteName = "RemoteOrbitApplyPresetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = MappingStore(configurationFileURL: configurationURL, userDefaults: defaults)
        let codexTemplate = try XCTUnwrap(
            store.templates(for: MappingStore.codexBundleIdentifier).first {
                $0.templateName == "Codex 默认"
            }
        )
        XCTAssertEqual(codexTemplate.gestureProfiles?[.ok]?.longPress, .preset(.paste))

        let importedID = try XCTUnwrap(
            store.importTemplatePreset(
                "t3code.default",
                for: "com.t3tools.t3code",
                appName: "T3 Code"
            )
        )
        store.setBinding(.preset(.disabled), for: .home, templateID: importedID)
        XCTAssertEqual(
            store.importTemplatePreset("t3code.default", for: "com.t3tools.t3code", appName: "T3 Code"),
            importedID
        )
        XCTAssertEqual(store.binding(for: .home, templateID: importedID), .preset(.disabled))

        let appliedID = try XCTUnwrap(
            store.applyTemplatePreset(
                "t3code.default",
                for: "com.t3tools.t3code",
                appName: "T3 Code"
            )
        )
        XCTAssertEqual(appliedID, importedID)
        XCTAssertEqual(store.binding(for: .home, templateID: appliedID), .preset(.t3NewChat))
        XCTAssertEqual(
            store.gestureProfile(for: .menu, templateID: appliedID).longPress,
            .preset(.t3ToggleSidebar)
        )
    }
}
