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
}
