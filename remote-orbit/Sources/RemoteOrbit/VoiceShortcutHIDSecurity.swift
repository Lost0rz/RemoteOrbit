import Foundation

enum VoiceShortcutHIDXPCPeer: Equatable {
    case remoteOrbitApp
    case privilegedHelper
}

private struct VoiceShortcutHIDCodeIdentity: Equatable {
    let teamIdentifier: String
    let executableIdentifier: String
}

/// Carries both peer identities because each XPC endpoint must authenticate
/// the other. The accepted product currently has no verified production team
/// identity, so `.production` intentionally cannot create either requirement.
struct VoiceShortcutHIDSigningPolicy {
    private let appIdentity: VoiceShortcutHIDCodeIdentity?
    private let helperIdentity: VoiceShortcutHIDCodeIdentity?
    private let testOnlyFixture: Bool

    static let production = VoiceShortcutHIDSigningPolicy(
        appIdentity: nil,
        helperIdentity: nil,
        testOnlyFixture: false
    )

    private init(
        appIdentity: VoiceShortcutHIDCodeIdentity?,
        helperIdentity: VoiceShortcutHIDCodeIdentity?,
        testOnlyFixture: Bool
    ) {
        self.appIdentity = appIdentity
        self.helperIdentity = helperIdentity
        self.testOnlyFixture = testOnlyFixture
    }

    var productionEligible: Bool {
        !testOnlyFixture
            && requirement(for: .remoteOrbitApp) != nil
            && requirement(for: .privilegedHelper) != nil
    }

    func requirement(for peer: VoiceShortcutHIDXPCPeer) -> String? {
        guard !testOnlyFixture else { return nil }
        return makeRequirement(identity(for: peer))
    }

    #if DEBUG
    static func testOnlyFixture() -> VoiceShortcutHIDSigningPolicy {
        VoiceShortcutHIDSigningPolicy(
            appIdentity: VoiceShortcutHIDCodeIdentity(
                teamIdentifier: "TESTTEAM01",
                executableIdentifier: "com.example.RemoteOrbit.TestHarness"
            ),
            helperIdentity: VoiceShortcutHIDCodeIdentity(
                teamIdentifier: "TESTTEAM01",
                executableIdentifier: "com.example.RemoteOrbitHIDHelper.TestHarness"
            ),
            testOnlyFixture: true
        )
    }

    func testRequirement(for peer: VoiceShortcutHIDXPCPeer) -> String? {
        guard testOnlyFixture else { return nil }
        return makeRequirement(identity(for: peer))
    }
    #endif

    private func identity(for peer: VoiceShortcutHIDXPCPeer) -> VoiceShortcutHIDCodeIdentity? {
        switch peer {
        case .remoteOrbitApp: return appIdentity
        case .privilegedHelper: return helperIdentity
        }
    }

    private func makeRequirement(_ identity: VoiceShortcutHIDCodeIdentity?) -> String? {
        guard let identity,
              identity.teamIdentifier.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil,
              identity.executableIdentifier.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil,
              identity.executableIdentifier.contains(".") else {
            return nil
        }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(identity.teamIdentifier)\" and identifier \"\(identity.executableIdentifier)\""
    }
}

protocol VoiceShortcutHIDPeerRequirementInstalling {
    func installPeerCodeSigningRequirement(_ requirement: String)
}

enum VoiceShortcutHIDXPCTrustGate {
    /// Fails closed until an actual production signer/executable identity is
    /// verified and recorded for both sides of the connection.
    @discardableResult
    static func installRequirement(
        for peer: VoiceShortcutHIDXPCPeer,
        policy: VoiceShortcutHIDSigningPolicy = .production,
        on connection: VoiceShortcutHIDPeerRequirementInstalling
    ) -> Bool {
        guard let requirement = policy.requirement(for: peer) else { return false }
        connection.installPeerCodeSigningRequirement(requirement)
        return true
    }
}

extension NSXPCConnection: VoiceShortcutHIDPeerRequirementInstalling {
    func installPeerCodeSigningRequirement(_ requirement: String) {
        setCodeSigningRequirement(requirement)
    }
}
