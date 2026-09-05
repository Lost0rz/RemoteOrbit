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

    func testLeakedNativeKeyDownMustAllowItsKeyUpThrough() {
        XCTAssertFalse(
            EventSuppressor.shouldSuppressRemoteKeyUp(
                hasPendingRelease: true,
                nativeKeyDownWasSuppressed: false
            )
        )
        XCTAssertTrue(
            EventSuppressor.shouldSuppressRemoteKeyUp(
                hasPendingRelease: true,
                nativeKeyDownWasSuppressed: true
            )
        )
        XCTAssertFalse(
            EventSuppressor.shouldSuppressRemoteKeyUp(
                hasPendingRelease: false,
                nativeKeyDownWasSuppressed: true
            )
        )
    }

    func testFloatTabsTabActionsAreSingleShot() {
        XCTAssertFalse(ButtonAction.floatTabsNextTab.repeatsWhenHeld)
        XCTAssertFalse(ButtonAction.floatTabsPreviousTab.repeatsWhenHeld)
    }

    func testActionFeedbackDistinguishesQueuedAndSynchronousBindings() {
        let commandR = ButtonBinding.shortcut(
            KeyChord(keyCode: 15, keyLabel: "R", modifiers: .command),
            trigger: .single
        )
        let optionR = ButtonBinding.shortcut(
            KeyChord(keyCode: 15, keyLabel: "R", modifiers: .option),
            trigger: .single
        )

        XCTAssertTrue(KeyInjector.isAsynchronous(commandR))
        XCTAssertFalse(KeyInjector.isAsynchronous(optionR))
        XCTAssertTrue(KeyInjector.isAsynchronous(.preset(.floatTabsNextTab)))
        XCTAssertTrue(KeyInjector.isAsynchronous(.preset(.obsidianOpenDailyNote)))
        XCTAssertFalse(KeyInjector.isAsynchronous(.preset(.chatGPTToggleSidebar)))
    }

    func testCodexConversationFocusIsAnAtomicInputAction() {
        XCTAssertEqual(
            ButtonAction.chatGPTFocusConversationInput.category,
            .chatGPTInputModes
        )
        XCTAssertFalse(ButtonAction.chatGPTFocusConversationInput.repeatsWhenHeld)
        XCTAssertTrue(
            ButtonAction.chatGPTFocusConversationInput.displayName.contains("聚焦对话输入框")
        )
    }

    func testRemovedCodexCopyActionDoesNotDiscardExistingConfiguration() throws {
        let data = Data(#"{"type":"preset","action":"codexCopyLatestResponse"}"#.utf8)
        let binding = try JSONDecoder().decode(ButtonBinding.self, from: data)

        XCTAssertEqual(binding, .preset(.disabled))
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
            .obsidianFocusEditor,
            .obsidianFocusTabGroupLeft,
            .obsidianFocusTabGroupRight,
            .obsidianFocusTabGroupAbove,
            .obsidianFocusTabGroupBelow,
            .obsidianPreviousTab,
            .obsidianNextTab,
            .obsidianGoToTab1,
            .obsidianGoToTab9,
            .obsidianNewNote,
            .obsidianNewNoteToRight,
            .obsidianSearchCurrentFile,
            .obsidianSearch,
            .obsidianIncreaseFontSize,
            .obsidianDecreaseFontSize,
            .obsidianResetFontSize,
            .obsidianOpenGraphView,
            .obsidianOpenSettings,
            .obsidianCloseOtherTabs,
            .obsidianSplitRight,
            .obsidianSplitDown,
            .obsidianToggleStackedTabs,
            .obsidianShowBacklinks,
            .obsidianShowOutgoingLinks,
            .obsidianShowTags,
            .obsidianShowOutline,
            .obsidianShowBookmarks,
            .obsidianOpenDailyNote,
            .obsidianInsertTemplate,
            .obsidianOpenFileExplorer,
            .obsidianCreateNewCanvas,
            .obsidianCommandPalette,
        ]

        XCTAssertTrue(actions.allSatisfy { $0.category == .obsidian })
        XCTAssertTrue(actions.allSatisfy { !$0.repeatsWhenHeld })
        XCTAssertTrue(actions.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(actions.allSatisfy { $0.obsidianGroup != nil })
        XCTAssertTrue([
            ButtonAction.obsidianFocusEditor,
            .obsidianFocusTabGroupLeft,
            .obsidianFocusTabGroupRight,
            .obsidianFocusTabGroupAbove,
            .obsidianFocusTabGroupBelow,
        ].allSatisfy { $0.obsidianGroup == .cliWorkspace })
        XCTAssertEqual(
            Set(actions.compactMap(\.obsidianGroup)),
            Set(ObsidianActionGroup.allCases)
        )
    }

    func testSystemCaretAndSelectionActionsStayAtomicAndScoped() {
        let actions: [ButtonAction] = [
            .moveToLineStart,
            .moveToLineEnd,
            .moveToDocumentStart,
            .moveToDocumentEnd,
            .extendSelectionLeft,
            .extendSelectionRight,
            .extendSelectionUp,
            .extendSelectionDown,
            .extendSelectionToLineStart,
            .extendSelectionToLineEnd,
            .extendSelectionToDocumentStart,
            .extendSelectionToDocumentEnd,
        ]

        XCTAssertTrue(actions.allSatisfy { $0.category == .selection })
        XCTAssertTrue(actions.allSatisfy { !$0.repeatsWhenHeld })
        XCTAssertTrue(actions.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(AppTemplatePresetLibrary.categories(for: "md.obsidian").contains(.selection))
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

    func testOpenAIPresetLibraryExposesCodexOnly() {
        let presets = AppTemplatePresetLibrary.presets(for: "com.openai.codex")

        XCTAssertEqual(presets.map(\.id), ["codex.default"])
        XCTAssertTrue(presets.allSatisfy { $0.appName == "Codex" })
        XCTAssertEqual(
            AppTemplatePresetLibrary.knownApps.first(where: {
                $0.bundleIdentifier == "com.openai.codex"
            })?.displayName,
            "Codex"
        )
    }

    func testCodexAndFloatTabsBuiltInPresetsUseTheCurrentDefaultLayout() {
        guard let codex = AppTemplatePresetLibrary.preset(id: "codex.default"),
              let floatTabs = AppTemplatePresetLibrary.preset(id: "floatTabs.default")
        else {
            return XCTFail("Codex and FloatTabs default presets must be provisioned")
        }

        XCTAssertEqual(Set(codex.bindings.keys), Set(RemoteButton.allCases))
        XCTAssertEqual(Set(floatTabs.bindings.keys), Set(RemoteButton.allCases))

        assertPreset(codex, button: .up, equals: .pageUp)
        assertPreset(codex, button: .down, equals: .pageDown)
        assertPreset(codex, button: .left, equals: .arrowLeft)
        assertPreset(codex, button: .right, equals: .arrowRight)
        assertPreset(codex, button: .back, equals: .deleteBackward)
        assertPreset(codex, button: .volumeUp, equals: .chatGPTPreviousChat)
        assertPreset(codex, button: .volumeDown, equals: .chatGPTNextChat)
        assertPreset(codex, button: .menu, equals: .chatGPTToggleSidebar)

        assertPreset(floatTabs, button: .up, equals: .pageUp)
        assertPreset(floatTabs, button: .down, equals: .pageDown)
        assertPreset(floatTabs, button: .left, equals: .arrowLeft)
        assertPreset(floatTabs, button: .right, equals: .arrowRight)
        assertPreset(floatTabs, button: .back, equals: .deleteBackward)
        assertPreset(floatTabs, button: .home, equals: .floatTabsToggleVisibility)
        assertPreset(floatTabs, button: .menu, equals: .floatTabsToggleAlwaysOnTop)
        assertPreset(floatTabs, button: .volumeUp, equals: .floatTabsPreviousTab)
        assertPreset(floatTabs, button: .volumeDown, equals: .floatTabsNextTab)

        XCTAssertEqual(
            codex.gestureProfiles?[.ok]?.longPress,
            .preset(.paste)
        )
        XCTAssertEqual(
            codex.gestureProfiles?[.back]?.longPressBehavior,
            .repeatWhileHeld
        )
        XCTAssertEqual(
            floatTabs.gestureProfiles?[.menu]?.longPress,
            .preset(.reloadPage)
        )
    }

    func testObsidianBuiltInPresetUsesFocusAndScrollLayout() {
        guard let obsidian = AppTemplatePresetLibrary.preset(id: "obsidian.default")
        else {
            return XCTFail("Obsidian default preset must be provisioned")
        }

        XCTAssertEqual(Set(obsidian.bindings.keys), Set(RemoteButton.allCases))
        assertPreset(obsidian, button: .up, equals: .pageUp)
        assertPreset(obsidian, button: .down, equals: .pageDown)
        assertPreset(obsidian, button: .left, equals: .obsidianFocusTabGroupLeft)
        assertPreset(obsidian, button: .right, equals: .obsidianFocusTabGroupRight)
        assertPreset(obsidian, button: .back, equals: .deleteBackward)
        assertPreset(obsidian, button: .volumeUp, equals: .obsidianPreviousTab)
        assertPreset(obsidian, button: .volumeDown, equals: .obsidianNextTab)
    }

    func testNeteaseBuiltInPresetUsesSystemVolumeForDedicatedVolumeButtons() {
        guard let netease = AppTemplatePresetLibrary.preset(id: "netease.default")
        else {
            return XCTFail("Netease default preset must be provisioned")
        }

        XCTAssertEqual(Set(netease.bindings.keys), Set(RemoteButton.allCases))
        assertPreset(netease, button: .up, equals: .volumeUp)
        assertPreset(netease, button: .down, equals: .volumeDown)
        assertPreset(netease, button: .left, equals: .neteasePreviousTrack)
        assertPreset(netease, button: .right, equals: .neteaseNextTrack)
        assertPreset(netease, button: .volumeUp, equals: .volumeUp)
        assertPreset(netease, button: .volumeDown, equals: .volumeDown)
        XCTAssertEqual(
            netease.bindings[.volumeUp]?.hudDisplayName,
            "系统音量 +"
        )
        XCTAssertEqual(
            netease.bindings[.volumeDown]?.hudDisplayName,
            "系统音量 -"
        )
    }

    func testRecordingHUDStateUsesAnExplicitPersistentState() {
        XCTAssertEqual(RemoteActionHUDState.recording.title, "正在语音中")
        XCTAssertEqual(RemoteActionHUDState.recording.color, .systemGreen)
    }

    func testHUDActionNameRemovesShortcutDescriptionButKeepsRecordedShortcut() {
        XCTAssertEqual(
            ButtonBinding.preset(.reloadPage).hudDisplayName,
            "刷新当前页面"
        )
        XCTAssertEqual(
            ButtonBinding.preset(.copy).hudDisplayName,
            "复制"
        )
        XCTAssertEqual(
            ButtonBinding.shortcut(
                KeyChord(keyCode: 15, keyLabel: "R", modifiers: .command),
                trigger: .single
            ).hudDisplayName,
            "⌘R"
        )
    }

    func testFloatTabsDirectScrollCommandUsesTheSameVisibleDirectionAsCodex() {
        XCTAssertEqual(
            KeyInjector.directFloatTabsScrollCommand(for: .up),
            .scrollDown
        )
        XCTAssertEqual(
            KeyInjector.directFloatTabsScrollCommand(for: .down),
            .scrollUp
        )
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
