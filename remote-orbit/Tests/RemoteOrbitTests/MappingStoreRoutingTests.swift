import XCTest
@testable import RemoteOrbit

final class MappingStoreRoutingTests: XCTestCase {
    private let ownBundleIdentifier = "com.lost0rz.RemoteOrbit"

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
}
