import XCTest
@testable import RemoteOrbit

final class VoiceShortcutHIDTests: XCTestCase {
    func testRequestedModifierCombinationsEncodeCompleteUpstreamReportAndNeutralRelease() throws {
        let left = try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [55, 58])
        XCTAssertEqual(left.modifierBitmap, 0x0C, "E3 + E2 must be held in one report")
        XCTAssertEqual(left.reportID, 1)
        XCTAssertEqual(left.reservedByte, 0)
        XCTAssertEqual(left.ordinaryKeyUsages.count, 32)
        XCTAssertTrue(left.ordinaryKeyUsages.allSatisfy { $0 == 0 })
        XCTAssertTrue(left.hasValidModifierOnlyLayout)

        let right = try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [54, 58])
        XCTAssertEqual(right.modifierBitmap, 0x84, "E7 + E2 must retain physical sides")
        XCTAssertTrue(right.hasValidModifierOnlyLayout)

        XCTAssertEqual(VoiceShortcutHIDModifierReport.neutral.modifierBitmap, 0x00)
        XCTAssertTrue(VoiceShortcutHIDModifierReport.neutral.hasValidModifierOnlyLayout)
    }

    func testEncoderCoversAllUSBHIDModifierUsages() throws {
        let report = try VoiceShortcutHIDReportEncoder.encode(
            modifierKeyCodes: [59, 56, 58, 55, 62, 60, 61, 54]
        )

        XCTAssertEqual(report.modifierBitmap, 0xFF)
        XCTAssertTrue(report.hasValidModifierOnlyLayout)
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

    func testSessionUsesSerializedGenerationScopedSequencesAndOwnsNeutralRelease() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(
            provider: provider,
            physicalModifierKeyCodesProvider: { [] }
        )
        let sessionID = UUID()
        let otherSessionID = UUID()

        XCTAssertEqual(owner.begin(sessionID: sessionID, modifierKeyCodes: [55, 58]), .accepted)
        XCTAssertEqual(
            provider.requests.map { $0.report?.modifierBitmap },
            [0x0C]
        )
        XCTAssertEqual(provider.requests.first?.operation, .begin)
        XCTAssertEqual(provider.requests.first?.sessionID, sessionID)
        XCTAssertEqual(provider.requests.first?.requestSequence, 1)

        XCTAssertEqual(
            owner.begin(sessionID: sessionID, modifierKeyCodes: [55, 58]),
            .accepted,
            "repeated begin for the same immutable session is idempotent"
        )
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(
            owner.begin(sessionID: sessionID, modifierKeyCodes: [54, 58]),
            .rejected(.sessionBindingChanged)
        )
        XCTAssertEqual(
            owner.begin(sessionID: otherSessionID, modifierKeyCodes: [54, 58]),
            .rejected(.ownerBusy)
        )

        XCTAssertFalse(owner.end(sessionID: otherSessionID), "a stale release must not emit a report")
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertTrue(owner.end(sessionID: sessionID))
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C, 0x00])
        XCTAssertEqual(provider.requests.map(\.requestSequence), [1, 2])
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .release])
        XCTAssertTrue(provider.requests.allSatisfy { $0.connectionGeneration == 41 })
        XCTAssertEqual(provider.requests.last?.sessionID, sessionID)
        XCTAssertNil(owner.activeSessionID)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testUnavailableMismatchNotReadyAndMissingPhysicalStateFailClosed() {
        let unavailable = FakeVoiceShortcutHIDProvider(state: .unavailable)
        let unavailableOwner = VoiceShortcutHIDSessionOwner(
            provider: unavailable,
            physicalModifierKeyCodesProvider: { [] }
        )
        XCTAssertEqual(
            unavailableOwner.begin(sessionID: UUID(), modifierKeyCodes: [55, 58]),
            .rejected(.providerUnavailable)
        )
        XCTAssertTrue(unavailable.requests.isEmpty)

        let mismatched = FakeVoiceShortcutHIDProvider(
            state: .ready(
                packageVersion: "8.0.0",
                clientProtocolVersion: 7,
                connectionGeneration: 41,
                keyboardReady: true
            )
        )
        let mismatchedOwner = VoiceShortcutHIDSessionOwner(
            provider: mismatched,
            physicalModifierKeyCodesProvider: { [] }
        )
        XCTAssertEqual(
            mismatchedOwner.begin(sessionID: UUID(), modifierKeyCodes: [55, 58]),
            .rejected(.providerProtocolMismatch)
        )
        XCTAssertTrue(mismatched.requests.isEmpty)

        let notReady = FakeVoiceShortcutHIDProvider(
            state: .ready(
                packageVersion: VoiceShortcutHIDProviderContract.packageVersion,
                clientProtocolVersion: VoiceShortcutHIDProviderContract.clientProtocolVersion,
                connectionGeneration: 41,
                keyboardReady: false
            )
        )
        let notReadyOwner = VoiceShortcutHIDSessionOwner(
            provider: notReady,
            physicalModifierKeyCodesProvider: { [] }
        )
        XCTAssertEqual(
            notReadyOwner.begin(sessionID: UUID(), modifierKeyCodes: [55, 58]),
            .rejected(.providerKeyboardNotReady)
        )
        XCTAssertTrue(notReady.requests.isEmpty)

        let missingPhysicalState = VoiceShortcutHIDSessionOwner(
            provider: FakeVoiceShortcutHIDProvider()
        )
        XCTAssertEqual(
            missingPhysicalState.begin(sessionID: UUID(), modifierKeyCodes: [55, 58]),
            .rejected(.physicalModifierStateUnavailable)
        )
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
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testFailedNeutralReleaseRetainsOwnerAndRecoversBeforeRapidRepress() {
        let provider = FakeVoiceShortcutHIDProvider(outcomes: [
            .queued, .rejected, .queued, .queued, .queued,
        ])
        let owner = VoiceShortcutHIDSessionOwner(
            provider: provider,
            physicalModifierKeyCodesProvider: { [] }
        )
        let firstSessionID = UUID()
        let secondSessionID = UUID()

        XCTAssertEqual(owner.begin(sessionID: firstSessionID, modifierKeyCodes: [55, 58]), .accepted)
        XCTAssertFalse(owner.end(sessionID: firstSessionID))
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        XCTAssertEqual(owner.activeSessionID, firstSessionID)

        XCTAssertEqual(
            owner.begin(sessionID: secondSessionID, modifierKeyCodes: [54, 58]),
            .accepted,
            "a repress is admitted only after the prior neutral report is queued"
        )
        XCTAssertEqual(
            provider.requests.map { $0.report?.modifierBitmap },
            [0x0C, 0x00, 0x00, 0x84]
        )
        XCTAssertEqual(
            provider.requests.map(\.operation),
            [.begin, .release, .recover, .begin]
        )
        XCTAssertEqual(owner.activeSessionID, secondSessionID)

        let requestCount = provider.requests.count
        XCTAssertFalse(owner.end(sessionID: firstSessionID), "a late release cannot clear a new owner")
        XCTAssertEqual(provider.requests.count, requestCount)
        XCTAssertTrue(owner.end(sessionID: secondSessionID))
        XCTAssertEqual(provider.requests.last?.report, .neutral)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testAmbiguousDownAndFailedRecoveryKeepSessionUntilScopedNeutralQueues() {
        let provider = FakeVoiceShortcutHIDProvider(outcomes: [
            .outcomeUnknown, .rejected, .queued,
        ])
        let owner = VoiceShortcutHIDSessionOwner(
            provider: provider,
            physicalModifierKeyCodesProvider: { [] }
        )
        let sessionID = UUID()

        XCTAssertEqual(
            owner.begin(sessionID: sessionID, modifierKeyCodes: [55, 58]),
            .rejected(.ownershipUnresolved)
        )
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        XCTAssertEqual(owner.activeSessionID, sessionID)
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C, 0x00])
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .recover])

        XCTAssertTrue(owner.recoverPendingRelease())
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .recover, .recover])
        XCTAssertEqual(provider.requests.map(\.requestSequence), [1, 2, 3])
        XCTAssertNil(owner.activeSessionID)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testConnectionGenerationChangeNeverReleasesOrTransfersAnotherOwner() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(
            provider: provider,
            physicalModifierKeyCodesProvider: { [] }
        )
        let first = UUID()

        XCTAssertEqual(owner.begin(sessionID: first, modifierKeyCodes: [55, 58]), .accepted)
        provider.state = .ready(
            packageVersion: VoiceShortcutHIDProviderContract.packageVersion,
            clientProtocolVersion: VoiceShortcutHIDProviderContract.clientProtocolVersion,
            connectionGeneration: 42,
            keyboardReady: true
        )

        XCTAssertFalse(owner.end(sessionID: first))
        XCTAssertFalse(owner.recoverPendingRelease())
        XCTAssertEqual(
            owner.begin(sessionID: first, modifierKeyCodes: [55, 58]),
            .rejected(.ownershipUnresolved)
        )
        XCTAssertEqual(
            owner.begin(sessionID: UUID(), modifierKeyCodes: [54, 58]),
            .rejected(.ownershipUnresolved)
        )
        XCTAssertEqual(provider.requests.map(\.operation), [.begin])
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        XCTAssertEqual(owner.activeSessionID, first)
    }

    func testMismatchedLateReplyCannotClearOwnershipOrReleaseANewerSession() {
        let provider = FakeVoiceShortcutHIDProvider()
        provider.replyTransform = { _, reply in
            VoiceShortcutHIDProviderReply(
                connectionGeneration: reply.connectionGeneration,
                requestSequence: reply.requestSequence + 1,
                outcome: reply.outcome
            )
        }
        let owner = VoiceShortcutHIDSessionOwner(
            provider: provider,
            physicalModifierKeyCodesProvider: { [] }
        )
        let sessionID = UUID()

        XCTAssertEqual(
            owner.begin(sessionID: sessionID, modifierKeyCodes: [55, 58]),
            .rejected(.ownershipUnresolved)
        )
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .recover])

        provider.replyTransform = nil
        XCTAssertTrue(owner.recoverPendingRelease())
        XCTAssertNil(owner.activeSessionID)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
        XCTAssertEqual(provider.requests.map(\.requestSequence), [1, 2, 3])
    }

    func testABASessionsRemainIsolatedAndSequencesStayMonotonic() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(
            provider: provider,
            physicalModifierKeyCodesProvider: { [] }
        )
        let bitmapBySession: [(UUID, [UInt16])] = [
            (UUID(), [55, 58]),
            (UUID(), [54, 58]),
            (UUID(), [55, 58]),
        ]

        for (sessionID, keyCodes) in bitmapBySession {
            XCTAssertEqual(owner.begin(sessionID: sessionID, modifierKeyCodes: keyCodes), .accepted)
            XCTAssertTrue(owner.end(sessionID: sessionID))
        }

        XCTAssertEqual(
            provider.requests.map { $0.report?.modifierBitmap },
            [0x0C, 0x00, 0x84, 0x00, 0x0C, 0x00]
        )
        XCTAssertEqual(provider.requests.map(\.requestSequence), [1, 2, 3, 4, 5, 6])
        for pair in stride(from: 0, to: provider.requests.count, by: 2) {
            XCTAssertEqual(provider.requests[pair].operation, .begin)
            XCTAssertEqual(provider.requests[pair + 1].operation, .release)
            XCTAssertEqual(provider.requests[pair].sessionID, provider.requests[pair + 1].sessionID)
        }
    }

    func testConcurrentBeginsHaveOneSerializedSessionOwner() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(
            provider: provider,
            physicalModifierKeyCodesProvider: { [] }
        )
        let sessionIDs = (0..<16).map { _ in UUID() }
        let lock = NSLock()
        var accepted: [UUID] = []

        DispatchQueue.concurrentPerform(iterations: sessionIDs.count) { index in
            let sessionID = sessionIDs[index]
            if owner.begin(sessionID: sessionID, modifierKeyCodes: [55, 58]) == .accepted {
                lock.lock()
                accepted.append(sessionID)
                lock.unlock()
            }
        }

        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertTrue(owner.end(sessionID: accepted[0]))
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }
}

final class VoiceShortcutHIDSecurityTests: XCTestCase {
    func testProductionXPCTrustRejectsUntilBothRealIdentitiesAreVerified() {
        let mock = MockPeerRequirementInstaller()

        XCTAssertFalse(VoiceShortcutHIDSigningPolicy.production.productionEligible)
        XCTAssertFalse(VoiceShortcutHIDXPCTrustGate.installRequirement(
            for: .privilegedHelper,
            on: mock
        ))
        XCTAssertFalse(VoiceShortcutHIDXPCTrustGate.installRequirement(
            for: .remoteOrbitApp,
            on: mock
        ))
        XCTAssertTrue(mock.requirements.isEmpty)
        XCTAssertNil(VoiceShortcutHIDSigningPolicy.production.requirement(for: .privilegedHelper))
        XCTAssertNil(VoiceShortcutHIDSigningPolicy.production.requirement(for: .remoteOrbitApp))
    }

    func testTestOnlySignerFixtureCannotProduceProductionConnectionRequirement() {
        let fixture = VoiceShortcutHIDSigningPolicy.testOnlyFixture()
        let mock = MockPeerRequirementInstaller()

        XCTAssertFalse(fixture.productionEligible)
        XCTAssertNil(fixture.requirement(for: .privilegedHelper))
        XCTAssertNil(fixture.requirement(for: .remoteOrbitApp))
        XCTAssertEqual(
            fixture.testRequirement(for: .privilegedHelper),
            "anchor apple generic and certificate leaf[subject.OU] = \"TESTTEAM01\" and identifier \"com.example.RemoteOrbitHIDHelper.TestHarness\""
        )
        XCTAssertEqual(
            fixture.testRequirement(for: .remoteOrbitApp),
            "anchor apple generic and certificate leaf[subject.OU] = \"TESTTEAM01\" and identifier \"com.example.RemoteOrbit.TestHarness\""
        )
        XCTAssertFalse(VoiceShortcutHIDXPCTrustGate.installRequirement(
            for: .privilegedHelper,
            policy: fixture,
            on: mock
        ))
        XCTAssertTrue(mock.requirements.isEmpty)
    }

}

private final class FakeVoiceShortcutHIDProvider: VoiceShortcutHIDReportProvider {
    var state: VoiceShortcutHIDProviderState
    private var plannedOutcomes: [VoiceShortcutHIDSubmissionOutcome]
    private(set) var requests: [VoiceShortcutHIDRequest] = []
    var replyTransform: ((VoiceShortcutHIDRequest, VoiceShortcutHIDProviderReply) -> VoiceShortcutHIDProviderReply)?

    init(
        state: VoiceShortcutHIDProviderState = .ready(
            packageVersion: VoiceShortcutHIDProviderContract.packageVersion,
            clientProtocolVersion: VoiceShortcutHIDProviderContract.clientProtocolVersion,
            connectionGeneration: 41,
            keyboardReady: true
        ),
        outcomes: [VoiceShortcutHIDSubmissionOutcome] = []
    ) {
        self.state = state
        plannedOutcomes = outcomes
    }

    func perform(_ request: VoiceShortcutHIDRequest) -> VoiceShortcutHIDProviderReply {
        requests.append(request)
        let outcome = plannedOutcomes.isEmpty ? .queued : plannedOutcomes.removeFirst()
        let reply = VoiceShortcutHIDProviderReply(
            connectionGeneration: request.connectionGeneration,
            requestSequence: request.requestSequence,
            outcome: outcome
        )
        return replyTransform?(request, reply) ?? reply
    }
}

private final class MockPeerRequirementInstaller: VoiceShortcutHIDPeerRequirementInstalling {
    private(set) var requirements: [String] = []

    func installPeerCodeSigningRequirement(_ requirement: String) {
        requirements.append(requirement)
    }
}
