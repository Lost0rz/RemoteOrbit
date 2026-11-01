import Foundation
import XCTest
@testable import RemoteOrbit

final class DualReceiverVoiceSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RemoteOrbitTests.DualReceiverVoiceSettings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDualModeRequiresDisabledShortAndDistinctReceiverKeys() {
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: false,
                receiverA: .leftOption,
                receiverB: .rightOption,
                rawHIDReady: true,
                eventSuppressorReady: true,
                primaryMappingSucceeded: true
            ),
            .legacy
        )
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: true,
                receiverA: .leftOption,
                receiverB: .leftOption,
                rawHIDReady: true,
                eventSuppressorReady: true,
                primaryMappingSucceeded: true
            ),
            .legacy
        )
    }
}
