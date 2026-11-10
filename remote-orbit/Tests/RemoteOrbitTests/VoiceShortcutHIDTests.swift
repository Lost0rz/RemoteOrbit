import XCTest
@testable import RemoteOrbit

final class VoiceShortcutHIDTests: XCTestCase {
    func testRequestedModifierCombinationsEncodeUSBHIDBitsAndNeutralRelease() throws {
        XCTAssertEqual(
            try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [55, 58]).modifierBitmap,
            0x0C,
            "Left Command E3 and left Option E2 must be held in one report"
        )
        XCTAssertEqual(
            try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [54, 58]).modifierBitmap,
            0x84,
            "Right Command E7 and left Option E2 must retain their physical sides"
        )
        XCTAssertEqual(VoiceShortcutHIDModifierReport.neutral.modifierBitmap, 0x00)
    }

    func testEncoderCoversAllUSBHIDModifierUsages() throws {
        let report = try VoiceShortcutHIDReportEncoder.encode(
            modifierKeyCodes: [59, 56, 58, 55, 62, 60, 61, 54]
        )

        XCTAssertEqual(report.modifierBitmap, 0xFF)
    }

    func testEncoderRejectsDuplicateAndUnsupportedKeyCodes() {
        XCTAssertThrowsError(
            try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [55, 55])
        ) { error in
            XCTAssertEqual(error as? VoiceShortcutHIDReportEncodingError, .duplicateKeyCode(55))
        }
        XCTAssertThrowsError(
            try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [55, 57])
        ) { error in
            XCTAssertEqual(error as? VoiceShortcutHIDReportEncodingError, .unsupportedKeyCode(57))
        }
        XCTAssertThrowsError(
            try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [58, 63])
        ) { error in
            XCTAssertEqual(error as? VoiceShortcutHIDReportEncodingError, .unsupportedKeyCode(63))
        }
        XCTAssertThrowsError(
            try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [])
        ) { error in
            XCTAssertEqual(error as? VoiceShortcutHIDReportEncodingError, .emptyModifierSet)
        }
    }

    func testSessionOwnsOneAtomicReportUntilNeutralRelease() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(provider: provider)
        let sessionID = UUID()
        let otherSessionID = UUID()

        XCTAssertEqual(
            owner.begin(sessionID: sessionID, modifierKeyCodes: [55, 58]),
            .accepted
        )
        XCTAssertEqual(provider.submissions.map(\.report.modifierBitmap), [0x0C])
        XCTAssertEqual(provider.submissions.first?.sessionID, sessionID)

        XCTAssertEqual(
            owner.begin(sessionID: sessionID, modifierKeyCodes: [55, 58]),
            .accepted,
            "repeated begin for the same immutable session is idempotent"
        )
        XCTAssertEqual(
            owner.begin(sessionID: sessionID, modifierKeyCodes: [54, 58]),
            .rejected(.sessionBindingChanged)
        )
        XCTAssertEqual(
            owner.begin(sessionID: otherSessionID, modifierKeyCodes: [54, 58]),
            .rejected(.ownerBusy)
        )

        XCTAssertFalse(owner.end(sessionID: otherSessionID), "a stale release must not emit a report")
        XCTAssertEqual(provider.submissions.count, 1)
        XCTAssertTrue(owner.end(sessionID: sessionID))
        XCTAssertEqual(provider.submissions.map(\.report.modifierBitmap), [0x0C, 0x00])
        XCTAssertEqual(provider.submissions.last?.sessionID, sessionID)
        XCTAssertNil(owner.activeSessionID)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testUnavailableOrMismatchedProviderFailsBeforeOwnershipOrReport() {
        let unavailable = FakeVoiceShortcutHIDProvider(state: .unavailable)
        let unavailableOwner = VoiceShortcutHIDSessionOwner(provider: unavailable)
        XCTAssertEqual(
            unavailableOwner.begin(sessionID: UUID(), modifierKeyCodes: [55, 58]),
            .rejected(.providerUnavailable)
        )
        XCTAssertFalse(unavailableOwner.hasUnresolvedOwnership)
        XCTAssertTrue(unavailable.submissions.isEmpty)

        let mismatched = FakeVoiceShortcutHIDProvider(
            state: .ready(packageVersion: "8.0.0", clientProtocolVersion: 6)
        )
        let mismatchedOwner = VoiceShortcutHIDSessionOwner(provider: mismatched)
        XCTAssertEqual(
            mismatchedOwner.begin(sessionID: UUID(), modifierKeyCodes: [55, 58]),
            .rejected(.providerProtocolMismatch)
        )
        XCTAssertFalse(mismatchedOwner.hasUnresolvedOwnership)
        XCTAssertTrue(mismatched.submissions.isEmpty)
    }

    func testPhysicalModifierFamilyConflictBlocksVirtualReport() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(
            provider: provider,
            physicalModifierKeyCodesProvider: { [54] }
        )

        XCTAssertEqual(
            owner.begin(sessionID: UUID(), modifierKeyCodes: [55, 58]),
            .rejected(.physicalModifierConflict),
            "a physical right Command conflicts with a requested virtual left Command"
        )
        XCTAssertTrue(provider.submissions.isEmpty)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testFailedNeutralReleaseRetainsOwnerAndRecoversBeforeRapidRepress() {
        let provider = FakeVoiceShortcutHIDProvider(
            submissions: [.accepted, .rejected, .accepted, .accepted]
        )
        let owner = VoiceShortcutHIDSessionOwner(provider: provider)
        let firstSessionID = UUID()
        let secondSessionID = UUID()

        XCTAssertEqual(
            owner.begin(sessionID: firstSessionID, modifierKeyCodes: [55, 58]),
            .accepted
        )
        XCTAssertFalse(owner.end(sessionID: firstSessionID))
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        XCTAssertEqual(owner.activeSessionID, firstSessionID)

        XCTAssertEqual(
            owner.begin(sessionID: secondSessionID, modifierKeyCodes: [54, 58]),
            .accepted,
            "a repress is admitted only after the prior neutral report is accepted"
        )
        XCTAssertEqual(provider.submissions.map(\.report.modifierBitmap), [0x0C, 0x00, 0x00, 0x84])
        XCTAssertEqual(owner.activeSessionID, secondSessionID)

        let submissionCount = provider.submissions.count
        XCTAssertFalse(owner.end(sessionID: firstSessionID), "a late release cannot clear a new owner")
        XCTAssertEqual(provider.submissions.count, submissionCount)
        XCTAssertTrue(owner.end(sessionID: secondSessionID))
        XCTAssertEqual(provider.submissions.last?.report, .neutral)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testAmbiguousPartialBeginRetainsOwnershipUntilAbortNeutralIsAccepted() {
        let provider = FakeVoiceShortcutHIDProvider(
            submissions: [.outcomeUnknown, .rejected, .accepted]
        )
        let owner = VoiceShortcutHIDSessionOwner(provider: provider)
        let sessionID = UUID()

        XCTAssertEqual(
            owner.begin(sessionID: sessionID, modifierKeyCodes: [55, 58]),
            .rejected(.ownershipUnresolved)
        )
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        XCTAssertEqual(owner.activeSessionID, sessionID)
        XCTAssertEqual(provider.submissions.map(\.report.modifierBitmap), [0x0C, 0x00])

        XCTAssertTrue(owner.abort(sessionID: sessionID))
        XCTAssertEqual(provider.submissions.map(\.report.modifierBitmap), [0x0C, 0x00, 0x00])
        XCTAssertNil(owner.activeSessionID)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testSessionValidationRejectsSameFamilyAndEmptyBindings() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(provider: provider)

        XCTAssertEqual(
            owner.begin(sessionID: UUID(), modifierKeyCodes: [54, 55]),
            .rejected(.invalidBinding)
        )
        XCTAssertEqual(
            owner.begin(sessionID: UUID(), modifierKeyCodes: []),
            .rejected(.invalidBinding)
        )
        XCTAssertTrue(provider.submissions.isEmpty)
    }
}

private final class FakeVoiceShortcutHIDProvider: VoiceShortcutHIDReportProvider {
    let state: VoiceShortcutHIDProviderState
    private var plannedSubmissions: [VoiceShortcutHIDReportSubmission]
    private(set) var submissions: [(report: VoiceShortcutHIDModifierReport, sessionID: UUID)] = []

    init(
        state: VoiceShortcutHIDProviderState = .ready(
            packageVersion: VoiceShortcutHIDProviderContract.packageVersion,
            clientProtocolVersion: VoiceShortcutHIDProviderContract.clientProtocolVersion
        ),
        submissions: [VoiceShortcutHIDReportSubmission] = []
    ) {
        self.state = state
        self.plannedSubmissions = submissions
    }

    func submit(
        _ report: VoiceShortcutHIDModifierReport,
        sessionID: UUID
    ) -> VoiceShortcutHIDReportSubmission {
        submissions.append((report, sessionID))
        return plannedSubmissions.isEmpty ? .accepted : plannedSubmissions.removeFirst()
    }
}
