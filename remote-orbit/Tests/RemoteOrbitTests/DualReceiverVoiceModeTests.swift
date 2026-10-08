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
                mappingClearSucceeded: true
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
                mappingClearSucceeded: false
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
                    mappingClearSucceeded: true
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
                mappingClearSucceeded: true
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
                mappingClearSucceeded: true
            ),
            .unavailable(.eventSuppressorUnavailable)
        )
    }

    func testFailedMappingClearFailsClosedRegardlessOfCachedMappingState() {
        XCTAssertEqual(
            DualReceiverVoiceMode.evaluate(
                shortIsDisabled: true,
                receiverA: .leftOption,
                receiverB: .rightOption,
                rawHIDReady: true,
                eventSuppressorReady: true,
                mappingClearSucceeded: false
            ),
            .unavailable(.mappingClearFailed)
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
