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
}
