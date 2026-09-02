import XCTest
@testable import RemoteOrbit

final class ButtonActionTests: XCTestCase {
    func testSingleShotBounceIsSuppressedUntilTheFenceExpires() {
        var debouncer = ButtonEdgeDebouncer()

        XCTAssertTrue(
            debouncer.shouldEmit(
                button: .home,
                isDown: true,
                at: 10.0,
                debouncing: true
            )
        )
        XCTAssertTrue(
            debouncer.shouldEmit(
                button: .home,
                isDown: false,
                at: 10.05,
                debouncing: true
            )
        )

        XCTAssertFalse(
            debouncer.shouldEmit(
                button: .home,
                isDown: true,
                at: 10.10,
                debouncing: true
            )
        )
        XCTAssertFalse(
            debouncer.shouldEmit(
                button: .home,
                isDown: false,
                at: 10.15,
                debouncing: true
            )
        )
        XCTAssertTrue(
            debouncer.shouldEmit(
                button: .home,
                isDown: true,
                at: 10.30,
                debouncing: true
            )
        )
    }

    func testRepeatableMappingBypassesSingleShotFence() {
        var debouncer = ButtonEdgeDebouncer()

        XCTAssertTrue(
            debouncer.shouldEmit(
                button: .down,
                isDown: true,
                at: 10.0,
                debouncing: false
            )
        )
        XCTAssertTrue(
            debouncer.shouldEmit(
                button: .down,
                isDown: false,
                at: 10.05,
                debouncing: false
            )
        )
        XCTAssertTrue(
            debouncer.shouldEmit(
                button: .down,
                isDown: true,
                at: 10.10,
                debouncing: false
            )
        )
    }

    func testReloadPageIsAReusableNavigationPreset() {
        XCTAssertEqual(ButtonAction.reloadPage.category, .navigation)
        XCTAssertFalse(ButtonAction.reloadPage.repeatsWhenHeld)
        XCTAssertTrue(ButtonAction.reloadPage.displayName.contains("刷新"))
    }

    func testPowerEventGuardOnlyMatchesNativePowerEventsWhenEnabled() {
        let powerEvent = RemoteNativeEvent.systemKey(type: 6)
        let volumeEvent = RemoteNativeEvent.systemKey(type: 0)
        let keyboardEvent = RemoteNativeEvent.keyboard(keyCode: 15)

        XCTAssertTrue(
            EventSuppressor.shouldSuppressRemotePowerEvent(
                powerEvent,
                remotePowerSuppressionEnabled: true
            )
        )
        XCTAssertFalse(
            EventSuppressor.shouldSuppressRemotePowerEvent(
                powerEvent,
                remotePowerSuppressionEnabled: false
            )
        )
        XCTAssertFalse(
            EventSuppressor.shouldSuppressRemotePowerEvent(
                volumeEvent,
                remotePowerSuppressionEnabled: true
            )
        )
        XCTAssertFalse(
            EventSuppressor.shouldSuppressRemotePowerEvent(
                keyboardEvent,
                remotePowerSuppressionEnabled: true
            )
        )
    }

    func testRemoteMediaSuppressionOnlyMatchesNativeVolumeEvents() {
        XCTAssertTrue(
            EventSuppressor.shouldSuppressRemoteMediaEvent(
                .systemKey(type: 0),
                remoteMediaSuppressionEnabled: true
            )
        )
        XCTAssertTrue(
            EventSuppressor.shouldSuppressRemoteMediaEvent(
                .systemKey(type: 1),
                remoteMediaSuppressionEnabled: true
            )
        )
        XCTAssertFalse(
            EventSuppressor.shouldSuppressRemoteMediaEvent(
                .systemKey(type: 7),
                remoteMediaSuppressionEnabled: true
            )
        )
        XCTAssertFalse(
            EventSuppressor.shouldSuppressRemoteMediaEvent(
                .systemKey(type: 0),
                remoteMediaSuppressionEnabled: false
            )
        )
    }

    func testFloatTabsTabActionsAreSingleShot() {
        XCTAssertFalse(ButtonAction.floatTabsNextTab.repeatsWhenHeld)
        XCTAssertFalse(ButtonAction.floatTabsPreviousTab.repeatsWhenHeld)
    }

    func testFloatTabsFullCatalogIsAvailableAsSemanticActions() {
        let actions: [ButtonAction] = [
            .floatTabsSelectSlot1,
            .floatTabsSelectSlot9,
            .floatTabsNextTab,
            .floatTabsPreviousTab,
            .floatTabsAddWebApp,
            .floatTabsZoomIn,
            .floatTabsZoomOut,
            .floatTabsResetZoom,
            .floatTabsAddressBar,
            .floatTabsReturnHome,
            .reloadPage,
            .floatTabsToggleFocus,
            .floatTabsTogglePin,
            .floatTabsSetHotResidency,
            .floatTabsSetWarmResidency,
            .floatTabsSetColdResidency,
            .floatTabsSettings,
        ]

        XCTAssertEqual(actions.count, 17)
        XCTAssertTrue(actions.allSatisfy { $0.category == .floatTabs || $0 == .reloadPage })
        XCTAssertTrue(actions.allSatisfy { !$0.displayName.isEmpty })
    }

    func testObsidianCatalogCoversCoreTabsSidebarsAndWorkspaceActions() {
        let actions: [ButtonAction] = [
            .obsidianToggleLeftSidebar,
            .obsidianToggleRightSidebar,
            .obsidianPreviousTab,
            .obsidianNextTab,
            .obsidianGoToTab1,
            .obsidianGoToTab9,
            .obsidianNewNote,
            .obsidianNewNoteToRight,
            .obsidianSearchCurrentFile,
            .obsidianSearch,
            .obsidianOpenGraphView,
            .obsidianOpenSettings,
            .obsidianCloseOtherTabs,
            .obsidianShowBacklinks,
            .obsidianShowOutgoingLinks,
            .obsidianShowTags,
            .obsidianOpenDailyNote,
            .obsidianInsertTemplate,
            .obsidianOpenFileExplorer,
            .obsidianCreateNewCanvas,
            .obsidianCommandPalette,
        ]

        XCTAssertTrue(actions.allSatisfy { $0.category == .obsidian })
        XCTAssertTrue(actions.allSatisfy { !$0.repeatsWhenHeld })
        XCTAssertTrue(actions.allSatisfy { !$0.displayName.isEmpty })
    }

    func testAppPresetCategoriesStayScopedToTheSelectedApplication() {
        let floatTabsCategories = AppTemplatePresetLibrary.categories(
            for: "com.lost0rz.FloatTabs"
        )
        let obsidianCategories = AppTemplatePresetLibrary.categories(for: "md.obsidian")

        XCTAssertTrue(floatTabsCategories.contains(.floatTabs))
        XCTAssertFalse(floatTabsCategories.contains(.obsidian))
        XCTAssertTrue(obsidianCategories.contains(.obsidian))
        XCTAssertFalse(obsidianCategories.contains(.floatTabs))
        XCTAssertFalse(obsidianCategories.contains(.chatGPTChats))
    }

    func testCodexAndFloatTabsBuiltInPresetsUseTheCurrentDefaultLayout() {
        guard let codex = AppTemplatePresetLibrary.preset(id: "codex.default"),
              let floatTabs = AppTemplatePresetLibrary.preset(id: "floatTabs.default")
        else {
            return XCTFail("Codex and FloatTabs default presets must be provisioned")
        }

        XCTAssertEqual(Set(codex.bindings.keys), Set(RemoteButton.allCases))
        XCTAssertEqual(Set(floatTabs.bindings.keys), Set(RemoteButton.allCases))

        assertPreset(codex, button: .up, equals: .pageDown)
        assertPreset(codex, button: .down, equals: .pageUp)
        assertPreset(codex, button: .left, equals: .arrowLeft)
        assertPreset(codex, button: .right, equals: .arrowRight)
        assertPreset(codex, button: .back, equals: .deleteBackward)
        assertPreset(codex, button: .volumeUp, equals: .chatGPTPreviousChat)
        assertPreset(codex, button: .volumeDown, equals: .chatGPTNextChat)
        assertPreset(codex, button: .menu, equals: .chatGPTToggleSidebar)

        assertPreset(floatTabs, button: .up, equals: .pageDown)
        assertPreset(floatTabs, button: .down, equals: .pageUp)
        assertPreset(floatTabs, button: .left, equals: .floatTabsToggleFocus)
        assertPreset(floatTabs, button: .right, equals: .paste)
        assertPreset(floatTabs, button: .home, equals: .floatTabsToggleVisibility)
        assertPreset(floatTabs, button: .menu, equals: .floatTabsToggleAlwaysOnTop)
        assertPreset(floatTabs, button: .volumeUp, equals: .floatTabsPreviousTab)
        assertPreset(floatTabs, button: .volumeDown, equals: .floatTabsNextTab)
    }

    private func assertPreset(
        _ preset: AppTemplatePreset,
        button: RemoteButton,
        equals expected: ButtonAction,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let binding = preset.bindings[button] else {
            return XCTFail("Missing \(button.rawValue) in \(preset.id)", file: file, line: line)
        }
        guard case let .preset(actual) = binding else {
            return XCTFail("Expected preset binding for \(button.rawValue) in \(preset.id)", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, "Unexpected \(button.rawValue) in \(preset.id)", file: file, line: line)
    }
}
