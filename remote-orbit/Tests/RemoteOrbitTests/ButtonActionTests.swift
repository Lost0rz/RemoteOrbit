import XCTest
@testable import RemoteOrbit

final class ButtonActionTests: XCTestCase {
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
}
