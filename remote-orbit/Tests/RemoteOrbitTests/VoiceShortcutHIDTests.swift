import CryptoKit
import XCTest
@testable import RemoteOrbit
import RemoteOrbitHIDBridge
import RemoteOrbitHIDHelper

final class VoiceShortcutHIDTests: XCTestCase {
    func testModifierCombinationsEncodeCompleteUpstreamReportAndNeutralRelease() throws {
        let left = try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [55, 58])
        XCTAssertEqual(left.modifierBitmap, 0x0C)
        XCTAssertEqual(left.reportID, 1)
        XCTAssertEqual(left.reservedByte, 0)
        XCTAssertEqual(left.ordinaryKeyUsages.count, 32)
        XCTAssertTrue(left.ordinaryKeyUsages.allSatisfy { $0 == 0 })
        XCTAssertTrue(left.hasValidModifierOnlyLayout)

        let right = try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [54, 58])
        XCTAssertEqual(right.modifierBitmap, 0x84)
        XCTAssertTrue(right.hasValidModifierOnlyLayout)
        XCTAssertEqual(VoiceShortcutHIDModifierReport.neutral.modifierBitmap, 0)
    }

    func testEncoderCoversEveryModifierAndRejectsInvalidKeys() throws {
        let all = try VoiceShortcutHIDReportEncoder.encode(
            modifierKeyCodes: [59, 56, 58, 55, 62, 60, 61, 54]
        )
        XCTAssertEqual(all.modifierBitmap, 0xFF)
        XCTAssertThrowsError(try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [55, 55]))
        XCTAssertThrowsError(try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: [55, 57]))
        XCTAssertThrowsError(try VoiceShortcutHIDReportEncoder.encode(modifierKeyCodes: []))
    }

    func testActualCxxClientAndPackedKeyboardReportABI() {
        var abi = ROHIDKeyboardReportABI()
        rohid_get_keyboard_report_abi(&abi)
        XCTAssertEqual(abi.size, 67)
        XCTAssertEqual(abi.alignment, 1)
        XCTAssertEqual(abi.modifier_offset, 1)
        XCTAssertEqual(abi.keys_offset, 3)
        XCTAssertEqual(abi.key_slot_count, 32)
        XCTAssertEqual(abi.client_protocol_version, 7)
        XCTAssertEqual(rohid_client_protocol_version(), 7)

        var report = [UInt8](repeating: 0xFF, count: 67)
        let didBuild = report.withUnsafeMutableBufferPointer {
            rohid_build_modifier_report(0x8C, $0.baseAddress, $0.count)
        }
        XCTAssertTrue(didBuild)
        XCTAssertEqual(report[0], 1)
        XCTAssertEqual(report[1], 0x8C)
        XCTAssertEqual(report[2], 0)
        XCTAssertTrue(report[3...].allSatisfy { $0 == 0 })

        let didBuildNeutral = report.withUnsafeMutableBufferPointer {
            rohid_build_modifier_report(0, $0.baseAddress, $0.count)
        }
        XCTAssertTrue(didBuildNeutral)
        XCTAssertTrue(report.dropFirst().allSatisfy { $0 == 0 })
        XCTAssertFalse(rohid_build_modifier_report(0, nil, 67))
        XCTAssertFalse(rohid_build_modifier_report(0, report.withUnsafeMutableBufferPointer { $0.baseAddress }, 66))
    }

    func testPinnedUpstreamManifestAndVendoredFilesMatchSha256() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let upstreamRoot = packageRoot.appendingPathComponent(
            "Sources/RemoteOrbitHIDBridge/vendor/upstream",
            isDirectory: true
        )
        let manifestURL = upstreamRoot.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(object["upstream_commit"] as? String, VoiceShortcutHIDProviderContract.sourceCommit)
        XCTAssertEqual(object["resolved_literal_include_closure_count"] as? Int, 620)
        let files = try XCTUnwrap(object["files"] as? [[String: Any]])
        XCTAssertEqual(files.count, 620)
        for entry in files {
            let path = try XCTUnwrap(entry["vendored_path"] as? String)
            let expected = try XCTUnwrap(entry["sha256"] as? String)
            let data = try Data(contentsOf: upstreamRoot.appendingPathComponent(path))
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actual, expected, "vendored file hash: \(path)")
        }
        let licenses = try XCTUnwrap(object["license_files"] as? [[String: Any]])
        XCTAssertEqual(licenses.count, 4)
        for entry in licenses {
            let path = try XCTUnwrap(entry["vendored_path"] as? String)
            let expected = try XCTUnwrap(entry["sha256"] as? String)
            let data = try Data(contentsOf: upstreamRoot.appendingPathComponent(path))
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actual, expected, "license hash: \(path)")
        }
        let asio = try XCTUnwrap(object["asio"] as? [String: Any])
        XCTAssertEqual(asio["version"] as? String, "1.38.2")
    }

    func testSessionUsesAsyncSerializedGenerationScopedRequestsAndNeutralRelease() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        let sessionID = UUID()
        let otherSessionID = UUID()

        XCTAssertEqual(begin(owner, sessionID, [55, 58]), .accepted)
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C])
        XCTAssertEqual(provider.requests.first?.operation, .begin)
        XCTAssertEqual(provider.requests.first?.sessionID, sessionID)
        XCTAssertEqual(provider.requests.first?.requestSequence, 1)
        XCTAssertEqual(begin(owner, sessionID, [55, 58]), .accepted)
        XCTAssertEqual(provider.requests.count, 1, "same immutable begin is idempotent")
        XCTAssertEqual(begin(owner, sessionID, [54, 58]), .rejected(.sessionBindingChanged))
        XCTAssertEqual(begin(owner, otherSessionID, [54, 58]), .rejected(.ownerBusy))
        XCTAssertFalse(end(owner, otherSessionID))
        XCTAssertTrue(end(owner, sessionID))
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C, 0])
        XCTAssertEqual(provider.requests.map(\.requestSequence), [1, 2])
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .release])
        XCTAssertTrue(provider.requests.allSatisfy { $0.connectionGeneration == 41 })
        XCTAssertNil(owner.activeSessionID)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testUnavailableMismatchNotReadyAndPhysicalStateFailClosed() {
        let unavailable = FakeVoiceShortcutHIDProvider(state: .unavailable)
        XCTAssertEqual(
            begin(VoiceShortcutHIDSessionOwner(provider: unavailable, physicalModifierKeyCodesProvider: { [] }), UUID(), [55, 58]),
            .rejected(.providerUnavailable)
        )
        XCTAssertTrue(unavailable.requests.isEmpty)

        let mismatch = FakeVoiceShortcutHIDProvider(state: .ready(
            packageVersion: "8.0.0", clientProtocolVersion: 7, connectionGeneration: 41, keyboardReady: true
        ))
        XCTAssertEqual(
            begin(VoiceShortcutHIDSessionOwner(provider: mismatch, physicalModifierKeyCodesProvider: { [] }), UUID(), [55, 58]),
            .rejected(.providerProtocolMismatch)
        )
        XCTAssertTrue(mismatch.requests.isEmpty)

        let notReady = FakeVoiceShortcutHIDProvider(state: .ready(
            packageVersion: VoiceShortcutHIDProviderContract.packageVersion,
            clientProtocolVersion: 7,
            connectionGeneration: 41,
            keyboardReady: false
        ))
        XCTAssertEqual(
            begin(VoiceShortcutHIDSessionOwner(provider: notReady, physicalModifierKeyCodesProvider: { [] }), UUID(), [55, 58]),
            .rejected(.providerKeyboardNotReady)
        )

        let missing = FakeVoiceShortcutHIDProvider()
        XCTAssertEqual(
            begin(VoiceShortcutHIDSessionOwner(provider: missing), UUID(), [55, 58]),
            .rejected(.physicalModifierStateUnavailable)
        )
        XCTAssertTrue(missing.requests.isEmpty)

        let conflict = FakeVoiceShortcutHIDProvider()
        let conflictOwner = VoiceShortcutHIDSessionOwner(provider: conflict, physicalModifierKeyCodesProvider: { [54] })
        XCTAssertEqual(begin(conflictOwner, UUID(), [55, 58]), .rejected(.physicalModifierConflict))
        XCTAssertTrue(conflict.requests.isEmpty)
    }

    func testFailedNeutralRetainsOwnershipAndRecoversBeforeRapidRepress() {
        let provider = FakeVoiceShortcutHIDProvider(outcomes: [.queued, .rejected, .queued, .queued, .queued])
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        let first = UUID()
        let second = UUID()
        XCTAssertEqual(begin(owner, first, [55, 58]), .accepted)
        XCTAssertFalse(end(owner, first))
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        XCTAssertEqual(owner.activeSessionID, first)
        XCTAssertEqual(begin(owner, second, [54, 58]), .accepted)
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C, 0, 0, 0x84])
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .release, .recover, .begin])
        XCTAssertEqual(owner.activeSessionID, second)
        XCTAssertFalse(end(owner, first))
        XCTAssertTrue(end(owner, second))
        XCTAssertEqual(provider.requests.last?.report, .neutral)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testUnknownBeginAndFailedRecoveryStayOwnedUntilScopedNeutralQueues() {
        let provider = FakeVoiceShortcutHIDProvider(outcomes: [.outcomeUnknown, .rejected, .queued])
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        let id = UUID()
        XCTAssertEqual(begin(owner, id, [55, 58]), .rejected(.ownershipUnresolved))
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        XCTAssertEqual(owner.activeSessionID, id)
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .recover])
        XCTAssertTrue(recover(owner))
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .recover, .recover])
        XCTAssertEqual(provider.requests.map(\.requestSequence), [1, 2, 3])
        XCTAssertNil(owner.activeSessionID)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
    }

    func testConnectionGenerationChangeBlocksNeutralReleaseAndOwnershipTransfer() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        let id = UUID()
        XCTAssertEqual(begin(owner, id, [55, 58]), .accepted)
        provider.state = .ready(
            packageVersion: VoiceShortcutHIDProviderContract.packageVersion,
            clientProtocolVersion: 7,
            connectionGeneration: 42,
            keyboardReady: true
        )
        XCTAssertFalse(end(owner, id))
        XCTAssertFalse(recover(owner))
        XCTAssertEqual(begin(owner, UUID(), [54, 58]), .rejected(.ownershipUnresolved))
        XCTAssertEqual(provider.requests.map(\.operation), [.begin])
        XCTAssertTrue(owner.hasUnresolvedOwnership)
    }

    func testMismatchedLateReplyCannotClearOwnership() {
        let provider = FakeVoiceShortcutHIDProvider()
        provider.replyTransform = { _, reply in
            VoiceShortcutHIDProviderReply(
                connectionGeneration: reply.connectionGeneration,
                requestSequence: reply.requestSequence + 1,
                outcome: reply.outcome
            )
        }
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        let id = UUID()
        XCTAssertEqual(begin(owner, id, [55, 58]), .rejected(.ownershipUnresolved))
        XCTAssertTrue(owner.hasUnresolvedOwnership)
        provider.replyTransform = nil
        XCTAssertTrue(recover(owner))
        XCTAssertNil(owner.activeSessionID)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
        XCTAssertEqual(provider.requests.map(\.requestSequence), [1, 2, 3])
    }

    func testABASessionsRemainIsolatedWithMonotonicSequences() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        let sessions: [(UUID, [UInt16])] = [(UUID(), [55, 58]), (UUID(), [54, 58]), (UUID(), [55, 58])]
        for (id, codes) in sessions {
            XCTAssertEqual(begin(owner, id, codes), .accepted)
            XCTAssertTrue(end(owner, id))
        }
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C, 0, 0x84, 0, 0x0C, 0])
        XCTAssertEqual(provider.requests.map(\.requestSequence), [1, 2, 3, 4, 5, 6])
        for index in stride(from: 0, to: provider.requests.count, by: 2) {
            XCTAssertEqual(provider.requests[index].operation, .begin)
            XCTAssertEqual(provider.requests[index + 1].operation, .release)
            XCTAssertEqual(provider.requests[index].sessionID, provider.requests[index + 1].sessionID)
        }
    }

    func testConcurrentBeginsRetainOneSerializedOwner() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        let ids = (0..<12).map { _ in UUID() }
        let done = expectation(description: "concurrent admissions")
        done.expectedFulfillmentCount = ids.count
        let lock = NSLock()
        var accepted: [UUID] = []
        for id in ids {
            owner.begin(sessionID: id, modifierKeyCodes: [55, 58]) { result in
                if result == .accepted {
                    lock.lock(); accepted.append(id); lock.unlock()
                }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertTrue(end(owner, accepted[0]))
    }

    private func begin(
        _ owner: VoiceShortcutHIDSessionOwner,
        _ id: UUID,
        _ keyCodes: [UInt16],
        timeout: TimeInterval = 3
    ) -> VoiceShortcutHIDSessionAdmission {
        let done = expectation(description: "async begin")
        var result: VoiceShortcutHIDSessionAdmission?
        owner.begin(sessionID: id, modifierKeyCodes: keyCodes) { value in result = value; done.fulfill() }
        wait(for: [done], timeout: timeout)
        return try! XCTUnwrap(result)
    }

    private func end(_ owner: VoiceShortcutHIDSessionOwner, _ id: UUID) -> Bool {
        let done = expectation(description: "async end")
        var result: Bool?
        owner.end(sessionID: id) { value in result = value; done.fulfill() }
        wait(for: [done], timeout: 3)
        return result ?? false
    }

    private func recover(_ owner: VoiceShortcutHIDSessionOwner) -> Bool {
        let done = expectation(description: "async recover")
        var result: Bool?
        owner.recoverPendingRelease { value in result = value; done.fulfill() }
        wait(for: [done], timeout: 3)
        return result ?? false
    }
}

final class VoiceShortcutHIDSecurityTests: XCTestCase {
    func testProductionXPCConnectionRefusesUnverifiedSigningIdentities() {
        XCTAssertFalse(VoiceShortcutHIDSigningPolicy.production.productionEligible)
        XCTAssertNil(VoiceShortcutHIDSigningPolicy.production.requirement(for: .remoteOrbitApp))
        XCTAssertNil(VoiceShortcutHIDSigningPolicy.production.requirement(for: .privilegedHelper))
        XCTAssertFalse(VoiceShortcutHIDXPCProvider().connectIfTrusted())
        XCTAssertNil(RemoteOrbitHIDHelperSigningPolicy.production.productionApplicationRequirement())
        XCTAssertFalse(RemoteOrbitHIDHelperSigningPolicy.production.installIncomingApplicationRequirement(on: .anonymous()))
    }

    func testTestFixtureRequirementsRemainUnavailableToProductionGate() {
        let fixture = VoiceShortcutHIDSigningPolicy.testOnlyFixture()
        XCTAssertFalse(fixture.productionEligible)
        XCTAssertNil(fixture.requirement(for: .privilegedHelper))
        XCTAssertNotNil(fixture.testRequirement(for: .remoteOrbitApp))
        XCTAssertNotNil(fixture.testRequirement(for: .privilegedHelper))
        XCTAssertFalse(RemoteOrbitHIDHelperSigningPolicy.testOnlyFixture().installIncomingApplicationRequirement(on: .anonymous()))
    }
}

final class RemoteOrbitHIDHelperSessionTests: XCTestCase {
    func testHelperValidatesProtocolIdentityAndPhysicalModifierConflicts() {
        let transport = FakeHelperTransport()
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [54] })
        let connection = UUID()
        XCTAssertEqual(submit(manager, request(connection, seq: 1, operation: .begin([55, 58]))).outcome, .rejected)
        XCTAssertEqual(submit(manager, request(connection, seq: 2, protocolVersion: 6, operation: .begin([55, 58]))).outcome, .rejected)
        XCTAssertEqual(submit(manager, request(connection, seq: 3, operation: .begin([55, 57]))).outcome, .rejected)
        XCTAssertTrue(transport.bitmaps.isEmpty)
        XCTAssertFalse(manager.hasUnresolvedOwnership)
    }

    func testXPCServiceRejectsOverflowFractionalAndOversizedModifierArrays() {
        let transport = FakeHelperTransport()
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [] })
        let service = RemoteOrbitHIDHelperXPCService(connectionID: UUID(), manager: manager)
        for values in [
            [NSNumber(value: 65_591), NSNumber(value: 58)],
            [NSNumber(value: 55.5), NSNumber(value: 58)],
            (0..<9).map { NSNumber(value: 55 + $0) },
        ] {
            let done = expectation(description: "malformed XPC modifier list rejected")
            service.beginModifierSession(
                UUID() as NSUUID,
                modifierKeyCodes: values,
                protocolVersion: 7,
                connectionGeneration: 41,
                requestSequence: UInt64(transport.bitmaps.count + 1)
            ) { generation, sequence, rawOutcome in
                XCTAssertEqual(generation, 41)
                XCTAssertGreaterThan(sequence, 0)
                XCTAssertEqual(RemoteOrbitHIDHelperOutcome(rawValue: rawOutcome), .rejected)
                done.fulfill()
            }
            wait(for: [done], timeout: 2)
        }
        XCTAssertTrue(transport.bitmaps.isEmpty)
        XCTAssertFalse(manager.hasUnresolvedOwnership)
    }

    func testHelperCachesExactDuplicateRejectsMutationAndReleasesNeutral() {
        let transport = FakeHelperTransport()
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [] })
        let connection = UUID()
        let id = UUID()
        let begin = request(connection, id: id, seq: 1, operation: .begin([55, 58]))
        XCTAssertEqual(submit(manager, begin).outcome, .queued)
        XCTAssertTrue(manager.hasUnresolvedOwnership)
        XCTAssertEqual(submit(manager, begin).outcome, .queued)
        XCTAssertEqual(transport.bitmaps, [0x0C], "an exact duplicate replays the cached result")
        XCTAssertEqual(submit(manager, request(connection, id: id, seq: 1, operation: .begin([54, 58]))).outcome, .rejected)
        XCTAssertEqual(submit(manager, request(connection, id: id, seq: 1, operation: .release)).outcome, .rejected)
        XCTAssertEqual(transport.bitmaps, [0x0C])
        XCTAssertEqual(submit(manager, request(connection, id: id, seq: 2, operation: .release)).outcome, .queued)
        XCTAssertEqual(transport.bitmaps, [0x0C, 0])
        XCTAssertFalse(manager.hasUnresolvedOwnership)
        XCTAssertEqual(submit(manager, request(connection, id: id, seq: 1, operation: .release)).outcome, .rejected)
    }

    func testHelperRetainsReleaseFailureThenRecoversAndDisconnectNeutralizes() {
        let transport = FakeHelperTransport(outcomes: [.queued, .outcomeUnknown, .queued, .queued, .queued])
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [] })
        let connection = UUID()
        let id = UUID()
        XCTAssertEqual(submit(manager, request(connection, id: id, seq: 1, operation: .begin([55, 58]))).outcome, .queued)
        XCTAssertEqual(submit(manager, request(connection, id: id, seq: 2, operation: .release)).outcome, .outcomeUnknown)
        XCTAssertTrue(manager.hasUnresolvedOwnership)
        XCTAssertEqual(submit(manager, request(connection, id: id, seq: 3, operation: .recover)).outcome, .queued)
        XCTAssertFalse(manager.hasUnresolvedOwnership)
        XCTAssertEqual(transport.bitmaps, [0x0C, 0, 0])

        let otherConnection = UUID()
        XCTAssertEqual(submit(manager, request(otherConnection, seq: 4, operation: .begin([54, 58]))).outcome, .queued)
        manager.disconnect(connectionID: otherConnection)
        let neutralized = expectation(description: "disconnect neutral release")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            if !manager.hasUnresolvedOwnership { neutralized.fulfill() }
        }
        wait(for: [neutralized], timeout: 2)
        XCTAssertEqual(transport.bitmaps.suffix(2), [0x84, 0])
    }

    func testHelperSessionOwnershipCannotBeTakenByAnotherConnection() {
        let transport = FakeHelperTransport()
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [] })
        let first = UUID(), second = UUID()
        let session = UUID()
        XCTAssertEqual(submit(manager, request(first, id: session, seq: 1, operation: .begin([55, 58]))).outcome, .queued)
        XCTAssertEqual(submit(manager, request(second, seq: 2, operation: .begin([54, 58]))).outcome, .rejected)
        XCTAssertTrue(manager.hasUnresolvedOwnership)
        XCTAssertEqual(transport.bitmaps, [0x0C])
        XCTAssertEqual(submit(manager, request(first, id: session, seq: 3, operation: .release)).outcome, .queued)
    }

    func testReconnectCanOnlyRecoverAReleasedOrReleasePendingSession() {
        let transport = FakeHelperTransport(outcomes: [.queued, .rejected, .queued])
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [] })
        let oldConnection = UUID()
        let newConnection = UUID()
        let id = UUID()
        XCTAssertEqual(submit(manager, request(oldConnection, id: id, seq: 1, operation: .begin([55, 58]))).outcome, .queued)
        manager.disconnect(connectionID: oldConnection)
        let disconnectProcessed = expectation(description: "disconnect release attempt")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            if manager.hasUnresolvedOwnership { disconnectProcessed.fulfill() }
        }
        wait(for: [disconnectProcessed], timeout: 2)
        XCTAssertEqual(transport.bitmaps, [0x0C, 0])

        XCTAssertEqual(submit(manager, request(newConnection, id: id, seq: 2, operation: .recover)).outcome, .queued)
        XCTAssertFalse(manager.hasUnresolvedOwnership)
        XCTAssertEqual(transport.bitmaps, [0x0C, 0, 0])
        XCTAssertEqual(submit(manager, request(UUID(), id: id, seq: 3, operation: .recover)).outcome, .queued)
        XCTAssertEqual(transport.bitmaps, [0x0C, 0, 0], "a released-session replay stays neutral and idempotent")
    }

    func testDelayedNeutralFromA_CannotClearBAndBCanRelease() {
        let transport = ControlledFakeHelperTransport()
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [] })
        let connectionA = UUID()
        let sessionA = UUID()
        let connectionB = UUID()
        let sessionB = UUID()

        let aBegan = expectation(description: "A begin acknowledged")
        manager.submit(request(connectionA, id: sessionA, seq: 1, operation: .begin([55, 58]))) { reply in
            XCTAssertEqual(reply.outcome, .queued)
            aBegan.fulfill()
        }
        guard transport.waitForSubmissionCount(1) else { return XCTFail("A begin was not submitted") }
        transport.complete(at: 0, outcome: .queued)
        wait(for: [aBegan], timeout: 2)

        var aReleaseReply: RemoteOrbitHIDHelperReply?
        var aRecoverReply: RemoteOrbitHIDHelperReply?
        let aReleased = expectation(description: "A release resolved")
        let aRecovered = expectation(description: "A concurrent recover resolved")
        manager.submit(request(connectionA, id: sessionA, seq: 2, operation: .release)) { reply in
            aReleaseReply = reply
            aReleased.fulfill()
        }
        guard transport.waitForSubmissionCount(2) else { return XCTFail("A release neutral was not submitted") }

        manager.submit(request(connectionA, id: sessionA, seq: 3, operation: .recover)) { reply in
            aRecoverReply = reply
            aRecovered.fulfill()
        }
        manager.disconnect(connectionID: connectionA)
        manager.disconnect(connectionID: connectionA)
        XCTAssertTrue(manager.hasUnresolvedOwnership, "the serial barrier observes recover and duplicate disconnect requests")

        let aNeutralIndices = transport.indices(for: 0)
        XCTAssertEqual(aNeutralIndices.count, 1, "concurrent release, recover, and duplicate disconnects share one neutral attempt")
        transport.complete(at: aNeutralIndices[0], outcome: .queued)
        wait(for: [aReleased], timeout: 2)

        let bBegan = expectation(description: "B begin acknowledged")
        let beforeBBegin = transport.submissionCount
        manager.submit(request(connectionB, id: sessionB, seq: 4, operation: .begin([54, 58]))) { reply in
            XCTAssertEqual(reply.outcome, .queued)
            bBegan.fulfill()
        }
        guard transport.waitForSubmissionCount(beforeBBegin + 1) else { return XCTFail("B begin was not submitted") }
        let bBeginIndex = transport.submissionCount - 1
        XCTAssertEqual(transport.bitmap(at: bBeginIndex), 0x84)
        transport.complete(at: bBeginIndex, outcome: .queued)
        wait(for: [bBegan], timeout: 2)

        let submissionsWithB = transport.submissionCount
        manager.disconnect(connectionID: connectionA)
        XCTAssertEqual(submit(manager, request(connectionA, id: sessionA, seq: 5, operation: .release)).outcome, .rejected)
        XCTAssertEqual(submit(manager, request(UUID(), id: sessionA, seq: 6, operation: .recover)).outcome, .rejected)
        XCTAssertTrue(manager.hasUnresolvedOwnership)
        XCTAssertEqual(transport.submissionCount, submissionsWithB, "stale A disconnect/release/recover cannot submit against B")

        // The delayed duplicate callback from A arrives after B owns the helper.
        // A fixed manager ignores it by neutral-attempt and owner identity.
        let delayedACompletionIndex = aNeutralIndices.count > 1 ? aNeutralIndices[1] : aNeutralIndices[0]
        transport.complete(at: delayedACompletionIndex, outcome: .queued)
        wait(for: [aRecovered], timeout: 2)
        XCTAssertEqual(aReleaseReply?.outcome, .queued)
        XCTAssertEqual(aRecoverReply?.outcome, .queued)
        XCTAssertTrue(manager.hasUnresolvedOwnership, "an old A neutral callback must not clear B's ownership")

        var bReleaseReply: RemoteOrbitHIDHelperReply?
        let bReleased = expectation(description: "B release acknowledged")
        let beforeBRelease = transport.submissionCount
        manager.submit(request(connectionB, id: sessionB, seq: 7, operation: .release)) { reply in
            bReleaseReply = reply
            bReleased.fulfill()
        }
        guard transport.waitForSubmissionCount(beforeBRelease + 1) else {
            wait(for: [bReleased], timeout: 2)
            XCTAssertEqual(bReleaseReply?.outcome, .queued, "B's release must not be rejected after A's delayed callback")
            return
        }
        let bNeutralIndex = transport.submissionCount - 1
        XCTAssertEqual(transport.bitmap(at: bNeutralIndex), 0)
        transport.complete(at: bNeutralIndex, outcome: .queued)
        wait(for: [bReleased], timeout: 2)
        XCTAssertEqual(bReleaseReply?.outcome, .queued)
        XCTAssertFalse(manager.hasUnresolvedOwnership)
    }

    func testConcurrentNeutralUnknownAndRejectedOutcomesKeepOwnerUntilQueuedRecovery() {
        let transport = ControlledFakeHelperTransport()
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [] })
        let connection = UUID()
        let session = UUID()

        let began = expectation(description: "session begin acknowledged")
        manager.submit(request(connection, id: session, seq: 1, operation: .begin([55, 58]))) { reply in
            XCTAssertEqual(reply.outcome, .queued)
            began.fulfill()
        }
        guard transport.waitForSubmissionCount(1) else { return XCTFail("begin was not submitted") }
        transport.complete(at: 0, outcome: .queued)
        wait(for: [began], timeout: 2)

        var releaseReply: RemoteOrbitHIDHelperReply?
        var firstRecoveryReply: RemoteOrbitHIDHelperReply?
        let released = expectation(description: "unknown release result returned")
        let firstRecovered = expectation(description: "coalesced unknown recovery result returned")
        manager.submit(request(connection, id: session, seq: 2, operation: .release)) { reply in
            releaseReply = reply
            released.fulfill()
        }
        guard transport.waitForSubmissionCount(2) else { return XCTFail("release neutral was not submitted") }
        manager.submit(request(connection, id: session, seq: 3, operation: .recover)) { reply in
            firstRecoveryReply = reply
            firstRecovered.fulfill()
        }
        XCTAssertTrue(manager.hasUnresolvedOwnership)
        XCTAssertEqual(transport.indices(for: 0).count, 1, "release and recover share one in-flight neutral")
        transport.complete(at: 1, outcome: .outcomeUnknown)
        wait(for: [released, firstRecovered], timeout: 2)
        XCTAssertEqual(releaseReply?.outcome, .outcomeUnknown)
        XCTAssertEqual(firstRecoveryReply?.outcome, .outcomeUnknown)
        XCTAssertTrue(manager.hasUnresolvedOwnership, "unknown neutral outcome must retain ownership")

        var rejectedRecoveryReply: RemoteOrbitHIDHelperReply?
        let rejectedRecovery = expectation(description: "rejected recovery result returned")
        manager.submit(request(connection, id: session, seq: 4, operation: .recover)) { reply in
            rejectedRecoveryReply = reply
            rejectedRecovery.fulfill()
        }
        guard transport.waitForSubmissionCount(3) else { return XCTFail("recovery retry was not submitted") }
        transport.complete(at: 2, outcome: .rejected)
        wait(for: [rejectedRecovery], timeout: 2)
        XCTAssertEqual(rejectedRecoveryReply?.outcome, .rejected)
        XCTAssertTrue(manager.hasUnresolvedOwnership, "rejected neutral outcome must retain ownership")

        var successfulRecoveryReply: RemoteOrbitHIDHelperReply?
        let successfulRecovery = expectation(description: "queued recovery result returned")
        manager.submit(request(connection, id: session, seq: 5, operation: .recover)) { reply in
            successfulRecoveryReply = reply
            successfulRecovery.fulfill()
        }
        guard transport.waitForSubmissionCount(4) else { return XCTFail("final recovery retry was not submitted") }
        transport.complete(at: 3, outcome: .queued)
        wait(for: [successfulRecovery], timeout: 2)
        XCTAssertEqual(successfulRecoveryReply?.outcome, .queued)
        XCTAssertFalse(manager.hasUnresolvedOwnership)
        XCTAssertEqual(transport.indices(for: 0).count, 3)
    }

    func testLateBeginCallbackForAStillRepliesWithoutChangingBOwnership() {
        let transport = ControlledFakeHelperTransport()
        let manager = RemoteOrbitHIDHelperSessionManager(transport: transport, physicalModifierKeyCodesProvider: { [] })
        let connectionA = UUID(), sessionA = UUID()
        let connectionB = UUID(), sessionB = UUID()
        var aBeginReply: RemoteOrbitHIDHelperReply?
        let aBegan = expectation(description: "late A begin result returned")
        manager.submit(request(connectionA, id: sessionA, seq: 1, operation: .begin([55, 58]))) { reply in
            aBeginReply = reply
            aBegan.fulfill()
        }
        guard transport.waitForSubmissionCount(1) else { return XCTFail("A begin was not submitted") }

        let aReleased = expectation(description: "A neutral completed before its begin callback")
        manager.submit(request(connectionA, id: sessionA, seq: 2, operation: .release)) { reply in
            XCTAssertEqual(reply.outcome, .queued)
            aReleased.fulfill()
        }
        guard transport.waitForSubmissionCount(2) else { return XCTFail("A release neutral was not submitted") }
        transport.complete(at: 1, outcome: .queued)
        wait(for: [aReleased], timeout: 2)
        XCTAssertFalse(manager.hasUnresolvedOwnership)

        let bBegan = expectation(description: "B begin acknowledged")
        manager.submit(request(connectionB, id: sessionB, seq: 3, operation: .begin([54, 58]))) { reply in
            XCTAssertEqual(reply.outcome, .queued)
            bBegan.fulfill()
        }
        guard transport.waitForSubmissionCount(3) else { return XCTFail("B begin was not submitted") }
        transport.complete(at: 2, outcome: .queued)
        wait(for: [bBegan], timeout: 2)

        transport.complete(at: 0, outcome: .rejected)
        wait(for: [aBegan], timeout: 2)
        XCTAssertEqual(aBeginReply?.outcome, .rejected)
        XCTAssertTrue(manager.hasUnresolvedOwnership, "A's late begin result must not clear B's owner")

        let bReleased = expectation(description: "B release acknowledged")
        var bReleaseReply: RemoteOrbitHIDHelperReply?
        manager.submit(request(connectionB, id: sessionB, seq: 4, operation: .release)) { reply in
            bReleaseReply = reply
            bReleased.fulfill()
        }
        guard transport.waitForSubmissionCount(4) else { return XCTFail("B release neutral was not submitted") }
        transport.complete(at: 3, outcome: .queued)
        wait(for: [bReleased], timeout: 2)
        XCTAssertEqual(bReleaseReply?.outcome, .queued)
        XCTAssertFalse(manager.hasUnresolvedOwnership)
    }

    private func request(
        _ connection: UUID,
        id: UUID = UUID(),
        seq: UInt64,
        protocolVersion: Int = 7,
        operation: RemoteOrbitHIDHelperRequest.Operation
    ) -> RemoteOrbitHIDHelperRequest {
        RemoteOrbitHIDHelperRequest(
            connectionID: connection,
            sessionID: id,
            protocolVersion: protocolVersion,
            connectionGeneration: 41,
            requestSequence: seq,
            operation: operation
        )
    }

    private func submit(
        _ manager: RemoteOrbitHIDHelperSessionManager,
        _ request: RemoteOrbitHIDHelperRequest
    ) -> RemoteOrbitHIDHelperReply {
        let done = expectation(description: "helper request")
        var result: RemoteOrbitHIDHelperReply?
        manager.submit(request) { value in result = value; done.fulfill() }
        wait(for: [done], timeout: 3)
        return try! XCTUnwrap(result)
    }
}

final class VoicePressCoordinatorVirtualHIDTests: XCTestCase {
    func testVirtualHIDKeepsTheAcceptedThreeHundredMillisecondLongOnlyBoundary() {
        XCTAssertEqual(VoicePressCoordinator.holdActivationThreshold, 0.30)
        XCTAssertFalse(VoicePressCoordinator.isLongPress(heldDuration: 0.299))
        XCTAssertTrue(VoicePressCoordinator.isLongPress(heldDuration: 0.30))
    }

    func testShortTapDoesNothingAndLongChordWaitsForAudioDrainAndNeutralRelease() {
        let shortProvider = FakeVoiceShortcutHIDProvider()
        let shortOwner = VoiceShortcutHIDSessionOwner(provider: shortProvider, physicalModifierKeyCodesProvider: { [] })
        let short = VoicePressCoordinator(virtualHIDSessionOwner: shortOwner)
        let profile = VoiceInputProfile(id: "chord-ab", displayName: "Command + Option", binding: .modifierChord(modifierKeyCodes: [55, 58]))
        let shortID = UUID()
        XCTAssertTrue(short.keyDown(sessionID: shortID, profile: profile))
        XCTAssertTrue(short.keyUp())
        XCTAssertTrue(shortProvider.requests.isEmpty)
        XCTAssertEqual(short.currentStateForTesting, .idle)
        short.stop()

        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        var fireTimer: (() -> Void)?
        var drain: (() -> Void)?
        var triggerEvents: [(VoiceTriggerKey, Bool)] = []
        let trigger = VoiceOptionTrigger(keyedEventSink: { triggerEvents.append(($0, $1)) })
        let press = VoicePressCoordinator(
            optionTrigger: trigger,
            virtualHIDSessionOwner: owner,
            candidateTimerFactory: { _, fire in fireTimer = fire; return VoicePressCandidateTimer(cancelAction: {}) }
        )
        press.onRemoteOutputDrain = { _, completion in drain = completion }
        let opened = expectation(description: "virtual modifier chord enters direct voice lifecycle")
        press.onStateChanged = { if $0 == .opening { opened.fulfill() } }
        let id = UUID()
        XCTAssertTrue(press.keyDown(sessionID: id, profile: profile))
        fireTimer?()
        wait(for: [opened], timeout: 3)
        XCTAssertEqual(press.capturedVoiceProfileForTesting, profile)
        XCTAssertEqual(provider.requests.map(\.operation), [.begin])
        XCTAssertTrue(triggerEvents.isEmpty, "modifier chord uses the report backend, not CGEvent")

        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(provider.requests.map(\.operation), [.begin], "neutral waits for audio output drain")
        XCTAssertNotNil(drain)
        let closed = expectation(description: "neutral HID release closes session")
        press.onStateChanged = { if $0 == .idle { closed.fulfill() } }
        drain?()
        wait(for: [closed], timeout: 3)
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .release])
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C, 0])
        XCTAssertFalse(owner.hasUnresolvedOwnership)
        XCTAssertTrue(triggerEvents.isEmpty)
        press.stop()
    }

    func testRapidRepressWaitsForOldNeutralThenUsesCapturedBProfile() {
        let provider = FakeVoiceShortcutHIDProvider()
        let owner = VoiceShortcutHIDSessionOwner(provider: provider, physicalModifierKeyCodesProvider: { [] })
        let a = VoiceInputProfile(id: "profile-a", displayName: "A", binding: .modifierChord(modifierKeyCodes: [55, 58]))
        let b = VoiceInputProfile(id: "profile-b", displayName: "B", binding: .modifierChord(modifierKeyCodes: [54, 58]))
        var fireTimer: (() -> Void)?
        var drains: [(UUID, () -> Void)] = []
        let press = VoicePressCoordinator(
            virtualHIDSessionOwner: owner,
            candidateTimerFactory: { _, fire in fireTimer = fire; return VoicePressCandidateTimer(cancelAction: {}) }
        )
        press.hasLivePhysicalCandidate = { true }
        press.onRemoteOutputDrain = { id, completion in drains.append((id, completion)) }
        let firstOpened = expectation(description: "A opened")
        press.onStateChanged = { if $0 == .opening, provider.requests.count == 1 { firstOpened.fulfill() } }
        let sessionA = UUID()
        XCTAssertTrue(press.keyDown(sessionID: sessionA, profile: a))
        fireTimer?()
        wait(for: [firstOpened], timeout: 3)
        XCTAssertEqual(press.capturedVoiceProfileForTesting, a)
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        XCTAssertEqual(drains.count, 1)

        let sessionB = UUID()
        XCTAssertTrue(press.keyDown(sessionID: sessionB, profile: b))
        XCTAssertTrue(press.promoteLongOnlyCandidateForTesting())
        XCTAssertEqual(provider.requests.map(\.operation), [.begin], "B cannot begin while A audio drain is outstanding")
        let bOpened = expectation(description: "B opened after A neutral")
        press.onStateChanged = { if $0 == .opening, provider.requests.count == 3 { bOpened.fulfill() } }
        drains[0].1()
        wait(for: [bOpened], timeout: 4)
        XCTAssertNil(press.pendingRepressSessionID, "pending B should clear when B begins")
        XCTAssertFalse(press.hasDeferredRepressAwaitingActivationForTesting)
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .release, .begin])
        guard provider.requests.count == 3 else { return }
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C, 0, 0x84])
        XCTAssertEqual(provider.requests.map(\.sessionID), [sessionA, sessionA, sessionB])
        XCTAssertEqual(press.capturedVoiceProfileForTesting, b)

        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        let c = VoiceInputProfile(id: "profile-a-again", displayName: "A again", binding: .modifierChord(modifierKeyCodes: [55, 58]))
        let sessionC = UUID()
        XCTAssertTrue(press.keyDown(sessionID: sessionC, profile: c))
        XCTAssertTrue(press.promoteLongOnlyCandidateForTesting())
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .release, .begin], "C waits for B's drain and release")
        let secondDrain = expectation(description: "B drain registered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if drains.count == 2 { secondDrain.fulfill() }
        }
        wait(for: [secondDrain], timeout: 2)
        drains[1].1()
        let cOpened = expectation(description: "A again opens after B release")
        press.onStateChanged = { if $0 == .opening, provider.requests.count == 5 { cOpened.fulfill() } }
        wait(for: [cOpened], timeout: 4)
        XCTAssertEqual(provider.requests.map(\.operation), [.begin, .release, .begin, .release, .begin])
        XCTAssertEqual(provider.requests.map { $0.report?.modifierBitmap }, [0x0C, 0, 0x84, 0, 0x0C])
        XCTAssertEqual(provider.requests.map(\.sessionID), [sessionA, sessionA, sessionB, sessionB, sessionC])
        XCTAssertEqual(press.capturedVoiceProfileForTesting, c)
        press.setRemoteStreaming(true)
        XCTAssertTrue(press.keyUp())
        press.setRemoteStreaming(false)
        let thirdDrain = expectation(description: "C drain registered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if drains.count == 3 { thirdDrain.fulfill() }
        }
        wait(for: [thirdDrain], timeout: 2)
        let finalIdle = expectation(description: "C neutral release completes")
        press.onStateChanged = { if $0 == .idle { finalIdle.fulfill() } }
        drains[2].1()
        wait(for: [finalIdle], timeout: 4)
        XCTAssertFalse(owner.hasUnresolvedOwnership)
        press.stop()
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
    }
}

private final class FakeVoiceShortcutHIDProvider: VoiceShortcutHIDReportProvider {
    private let lock = NSLock()
    private var storedState: VoiceShortcutHIDProviderState
    private var plannedOutcomes: [VoiceShortcutHIDSubmissionOutcome]
    private var storedRequests: [VoiceShortcutHIDRequest] = []
    var replyTransform: ((VoiceShortcutHIDRequest, VoiceShortcutHIDProviderReply) -> VoiceShortcutHIDProviderReply)?

    init(
        state: VoiceShortcutHIDProviderState = .ready(
            packageVersion: VoiceShortcutHIDProviderContract.packageVersion,
            clientProtocolVersion: 7,
            connectionGeneration: 41,
            keyboardReady: true
        ),
        outcomes: [VoiceShortcutHIDSubmissionOutcome] = []
    ) {
        storedState = state
        plannedOutcomes = outcomes
    }

    var state: VoiceShortcutHIDProviderState {
        get { lock.lock(); defer { lock.unlock() }; return storedState }
        set { lock.lock(); storedState = newValue; lock.unlock() }
    }

    var requests: [VoiceShortcutHIDRequest] {
        lock.lock(); defer { lock.unlock() }; return storedRequests
    }

    func perform(
        _ request: VoiceShortcutHIDRequest,
        completion: @escaping (VoiceShortcutHIDProviderReply) -> Void
    ) {
        lock.lock()
        storedRequests.append(request)
        let outcome = plannedOutcomes.isEmpty ? .queued : plannedOutcomes.removeFirst()
        let reply = VoiceShortcutHIDProviderReply(
            connectionGeneration: request.connectionGeneration,
            requestSequence: request.requestSequence,
            outcome: outcome
        )
        let transformed = replyTransform?(request, reply) ?? reply
        lock.unlock()
        completion(transformed)
    }
}

private final class FakeHelperTransport: RemoteOrbitHIDHelperTransport {
    private let lock = NSLock()
    private var plannedOutcomes: [RemoteOrbitHIDHelperOutcome]
    private var posted: [UInt8] = []

    init(outcomes: [RemoteOrbitHIDHelperOutcome] = []) { plannedOutcomes = outcomes }

    var state: RemoteOrbitHIDHelperTransportState? {
        RemoteOrbitHIDHelperTransportState(
            packageVersion: "8.6.0",
            clientProtocolVersion: 7,
            connectionGeneration: 41,
            keyboardReady: true
        )
    }

    var bitmaps: [UInt8] { lock.lock(); defer { lock.unlock() }; return posted }

    func submitModifierBitmap(_ modifierBitmap: UInt8, completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void) {
        lock.lock()
        posted.append(modifierBitmap)
        let outcome = plannedOutcomes.isEmpty ? .queued : plannedOutcomes.removeFirst()
        lock.unlock()
        completion(outcome)
    }
}

private final class ControlledFakeHelperTransport: RemoteOrbitHIDHelperTransport {
    private struct Submission {
        let bitmap: UInt8
        let completion: (RemoteOrbitHIDHelperOutcome) -> Void
    }

    private let condition = NSCondition()
    private var submissions: [Submission] = []

    var state: RemoteOrbitHIDHelperTransportState? {
        RemoteOrbitHIDHelperTransportState(
            packageVersion: "8.6.0",
            clientProtocolVersion: 7,
            connectionGeneration: 41,
            keyboardReady: true
        )
    }

    var submissionCount: Int {
        condition.lock(); defer { condition.unlock() }
        return submissions.count
    }

    func indices(for bitmap: UInt8) -> [Int] {
        condition.lock(); defer { condition.unlock() }
        return submissions.enumerated().compactMap { $0.element.bitmap == bitmap ? $0.offset : nil }
    }

    func bitmap(at index: Int) -> UInt8? {
        condition.lock(); defer { condition.unlock() }
        guard submissions.indices.contains(index) else { return nil }
        return submissions[index].bitmap
    }

    func waitForSubmissionCount(_ expected: Int, timeout: TimeInterval = 2) -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while submissions.count < expected {
            guard condition.wait(until: deadline) else { return submissions.count >= expected }
        }
        return true
    }

    func submitModifierBitmap(
        _ modifierBitmap: UInt8,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    ) {
        condition.lock()
        submissions.append(Submission(bitmap: modifierBitmap, completion: completion))
        condition.broadcast()
        condition.unlock()
    }

    func complete(at index: Int, outcome: RemoteOrbitHIDHelperOutcome) {
        condition.lock()
        let callback = submissions.indices.contains(index) ? submissions[index].completion : nil
        condition.unlock()
        callback?(outcome)
    }
}
