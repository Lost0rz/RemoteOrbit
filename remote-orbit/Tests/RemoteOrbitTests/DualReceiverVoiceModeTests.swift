import XCTest
@testable import RemoteOrbit

final class DualReceiverVoiceModeTests: XCTestCase {
    func testValidConfigurationRequiresDisabledShortDistinctKeysAndBothRawInputCapabilities() {
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: true,
                receiverA: .leftOption,
                receiverB: .rightOption,
                rawHIDReady: true,
                eventSuppressorReady: true,
                primaryMappingSucceeded: true
            ),
            .active(receiverA: .leftOption, receiverB: .rightOption)
        )
    }

    func testSecondaryOffPreservesLegacyModeWithoutRequiringDualCapabilities() {
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: true,
                receiverA: .leftOption,
                receiverB: nil,
                rawHIDReady: false,
                eventSuppressorReady: false,
                primaryMappingSucceeded: false
            ),
            .legacy
        )
    }

    func testEachConfigurationMismatchLeavesLegacyMode() {
        let cases: [(Bool, VoiceTriggerKey, VoiceTriggerKey?)] = [
            (false, .leftOption, .rightOption),
            (true, .leftOption, nil),
            (true, .leftOption, .leftOption),
        ]

        for (shortIsDisabled, receiverA, receiverB) in cases {
            XCTAssertEqual(
                DualReceiverVoiceMode.evaluate(
                    shortIsDisabled: shortIsDisabled,
                    receiverA: receiverA,
                    receiverB: receiverB,
                    rawHIDReady: true,
                    eventSuppressorReady: true,
                    primaryMappingSucceeded: true
                ),
                .legacy
            )
        }
    }

    func testMissingRawHIDFailsClosed() {
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: true,
                receiverA: .leftOption,
                receiverB: .rightOption,
                rawHIDReady: false,
                eventSuppressorReady: true,
                primaryMappingSucceeded: true
            ),
            .unavailable(.rawHIDUnavailable)
        )
    }

    func testMissingEventSuppressorFailsClosed() {
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: true,
                receiverA: .leftOption,
                receiverB: .rightOption,
                rawHIDReady: true,
                eventSuppressorReady: false,
                primaryMappingSucceeded: true
            ),
            .unavailable(.eventSuppressorUnavailable)
        )
    }

    func testFailedPrimaryMappingFailsClosed() {
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: true,
                receiverA: .leftOption,
                receiverB: .rightOption,
                rawHIDReady: true,
                eventSuppressorReady: true,
                primaryMappingSucceeded: false
            ),
            .unavailable(.primaryMappingFailed)
        )
    }

    func testEveryVoiceOwnerBlocksModeChanges() {
        for ownership in DualReceiverVoiceOwnership.allCases where ownership != .idle {
            XCTAssertFalse(
                DualReceiverVoiceMode.canChangeConfiguration(while: ownership),
                "Expected \(ownership) to hold mode ownership"
            )
        }
        XCTAssertTrue(DualReceiverVoiceMode.canChangeConfiguration(while: .idle))
    }
}
