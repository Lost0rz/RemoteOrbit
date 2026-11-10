import Foundation
import RemoteOrbitHIDBridge

@objc public protocol RemoteOrbitHIDXPCProtocol {
    func beginModifierSession(
        _ sessionID: NSUUID,
        modifierKeyCodes: [NSNumber],
        protocolVersion: Int,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        withReply reply: @escaping (UInt64, UInt64, Int) -> Void
    )

    func releaseModifierSession(
        _ sessionID: NSUUID,
        protocolVersion: Int,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        withReply reply: @escaping (UInt64, UInt64, Int) -> Void
    )

    func recoverModifierSession(
        _ sessionID: NSUUID,
        protocolVersion: Int,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        withReply reply: @escaping (UInt64, UInt64, Int) -> Void
    )

    func getModifierStatus(withReply reply: @escaping (String, Int, UInt64, Bool) -> Void)
}

public enum RemoteOrbitHIDHelperOutcome: Int, Equatable {
    case queued = 0
    case rejected = 1
    case outcomeUnknown = 2
}

public struct RemoteOrbitHIDHelperTransportState: Equatable {
    public let packageVersion: String
    public let clientProtocolVersion: Int
    public let connectionGeneration: UInt64
    public let keyboardReady: Bool

    public init(
        packageVersion: String,
        clientProtocolVersion: Int,
        connectionGeneration: UInt64,
        keyboardReady: Bool
    ) {
        self.packageVersion = packageVersion
        self.clientProtocolVersion = clientProtocolVersion
        self.connectionGeneration = connectionGeneration
        self.keyboardReady = keyboardReady
    }
}

public protocol RemoteOrbitHIDHelperTransport: AnyObject {
    var state: RemoteOrbitHIDHelperTransportState? { get }
    func submitModifierBitmap(
        _ modifierBitmap: UInt8,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    )
}

/// Thin adapter over the pinned pqrs `client.hpp`. Construction does not start
/// the dispatcher or connect to the privileged driver service. The caller has
/// to opt in to `start()` explicitly; this repository never does so at runtime.
public final class KarabinerVirtualHIDTransport: RemoteOrbitHIDHelperTransport {
    private let queue = DispatchQueue(label: "com.lost0rz.RemoteOrbitHIDHelper.karabiner-client")
    private var client: OpaquePointer?

    public init() {}

    public var state: RemoteOrbitHIDHelperTransportState? {
        queue.sync {
            guard let client else { return nil }
            let generation = rohid_client_connection_generation(client)
            guard rohid_client_keyboard_ready(client) else { return nil }
            return RemoteOrbitHIDHelperTransportState(
                packageVersion: "8.6.0",
                clientProtocolVersion: Int(rohid_client_protocol_version()),
                connectionGeneration: generation,
                keyboardReady: true
            )
        }
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, self.client == nil else { return }
            guard let client = rohid_client_create() else { return }
            self.client = client
            rohid_client_start(client)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self, let client = self.client else { return }
            rohid_client_destroy(client)
            self.client = nil
        }
    }

    public func submitModifierBitmap(
        _ modifierBitmap: UInt8,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let client = self.client,
                  rohid_client_keyboard_ready(client),
                  rohid_client_post_modifier_bitmap(client, modifierBitmap) else {
                completion(.rejected)
                return
            }
            // The upstream API returns void. This reply records that its async
            // report method was invoked, never DriverKit or IME acknowledgement.
            completion(.queued)
        }
    }
}

public struct RemoteOrbitHIDHelperSigningPolicy {
    private let applicationRequirement: String?
    private let productionEligible: Bool

    private init(applicationRequirement: String?, productionEligible: Bool) {
        self.applicationRequirement = applicationRequirement
        self.productionEligible = productionEligible
    }

    /// The current RemoteOrbit app/helper signing identities are not verified.
    public static let production = RemoteOrbitHIDHelperSigningPolicy(
        applicationRequirement: nil,
        productionEligible: false
    )

    #if DEBUG
    public static func testOnlyFixture() -> RemoteOrbitHIDHelperSigningPolicy {
        RemoteOrbitHIDHelperSigningPolicy(
            applicationRequirement: "anchor apple generic and certificate leaf[subject.OU] = \"TESTTEAM01\" and identifier \"com.example.RemoteOrbit.TestHarness\"",
            productionEligible: false
        )
    }
    #endif

    public func installIncomingApplicationRequirement(on listener: NSXPCListener) -> Bool {
        guard productionEligible, let applicationRequirement else { return false }
        listener.setConnectionCodeSigningRequirement(applicationRequirement)
        return true
    }

    public func productionApplicationRequirement() -> String? {
        productionEligible ? applicationRequirement : nil
    }
}

public struct RemoteOrbitHIDHelperRequest: Equatable {
    public enum Operation: Equatable {
        case begin([UInt16])
        case release
        case recover
    }

    public let connectionID: UUID
    public let sessionID: UUID
    public let protocolVersion: Int
    public let connectionGeneration: UInt64
    public let requestSequence: UInt64
    public let operation: Operation

    public init(
        connectionID: UUID,
        sessionID: UUID,
        protocolVersion: Int,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        operation: Operation
    ) {
        self.connectionID = connectionID
        self.sessionID = sessionID
        self.protocolVersion = protocolVersion
        self.connectionGeneration = connectionGeneration
        self.requestSequence = requestSequence
        self.operation = operation
    }
}

public struct RemoteOrbitHIDHelperReply: Equatable {
    public let connectionGeneration: UInt64
    public let requestSequence: UInt64
    public let outcome: RemoteOrbitHIDHelperOutcome

    public init(
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        outcome: RemoteOrbitHIDHelperOutcome
    ) {
        self.connectionGeneration = connectionGeneration
        self.requestSequence = requestSequence
        self.outcome = outcome
    }
}

/// Serial helper-side session owner. It accepts only a narrow modifier set,
/// caches exact duplicates, rejects sequence replay, and retains ownership
/// whenever a neutral request was rejected or has an unknown outcome.
public final class RemoteOrbitHIDHelperSessionManager {
    private struct Owner {
        let identity: UUID
        var connectionID: UUID
        let sessionID: UUID
        let generation: UInt64
        let modifierKeyCodes: [UInt16]
        var releasePending: Bool
    }

    private struct NeutralWaiter {
        let request: RemoteOrbitHIDHelperRequest
        let completion: (RemoteOrbitHIDHelperReply) -> Void
    }

    private struct NeutralFlight {
        let identity: UUID
        let ownerIdentity: UUID
        let sessionID: UUID
        let generation: UInt64
        var waiters: [NeutralWaiter]
    }

    private struct RequestKey: Hashable {
        let generation: UInt64
        let sequence: UInt64
    }

    private struct CachedReply {
        let fingerprint: String
        let reply: RemoteOrbitHIDHelperReply
    }

    private let transport: RemoteOrbitHIDHelperTransport
    private let physicalModifierKeyCodesProvider: () -> Set<UInt16>?
    private let queue = DispatchQueue(label: "com.lost0rz.RemoteOrbitHIDHelper.session-owner")
    private var owner: Owner?
    private var neutralFlight: NeutralFlight?
    private var lastSequenceByGeneration: [UInt64: UInt64] = [:]
    private var generationOrder: [UInt64] = []
    private var cache: [RequestKey: CachedReply] = [:]
    private var cacheOrder: [RequestKey] = []
    private var releasedSessions = Set<String>()
    private var releasedSessionOrder: [String] = []

    public init(
        transport: RemoteOrbitHIDHelperTransport,
        physicalModifierKeyCodesProvider: @escaping () -> Set<UInt16>?
    ) {
        self.transport = transport
        self.physicalModifierKeyCodesProvider = physicalModifierKeyCodesProvider
    }

    public var hasUnresolvedOwnership: Bool {
        queue.sync { owner != nil }
    }

    public func submit(
        _ request: RemoteOrbitHIDHelperRequest,
        completion: @escaping (RemoteOrbitHIDHelperReply) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let replay = self.replayOrAccept(request) else {
                completion(self.reply(for: request, outcome: .rejected))
                return
            }
            if case let .replay(cached) = replay {
                completion(cached)
                return
            }
            self.handleNewRequest(request, completion: completion)
        }
    }

    public func disconnect(connectionID: UUID) {
        queue.async { [weak self] in
            guard let self, var current = self.owner,
                  current.connectionID == connectionID else { return }
            current.releasePending = true
            self.owner = current
            self.submitNeutral(for: current)
        }
    }

    public func status() -> RemoteOrbitHIDHelperTransportState? {
        transport.state
    }

    public func status(completion: @escaping (RemoteOrbitHIDHelperTransportState?) -> Void) {
        queue.async { [weak self] in completion(self?.transport.state) }
    }

    private enum ReplayDecision {
        case proceed
        case replay(RemoteOrbitHIDHelperReply)
    }

    private func replayOrAccept(_ request: RemoteOrbitHIDHelperRequest) -> ReplayDecision? {
        let key = RequestKey(generation: request.connectionGeneration, sequence: request.requestSequence)
        let fingerprint = requestFingerprint(request)
        if let cached = cache[key] {
            return cached.fingerprint == fingerprint ? .replay(cached.reply) : nil
        }
        if lastSequenceByGeneration[request.connectionGeneration] == nil {
            generationOrder.append(request.connectionGeneration)
            if generationOrder.count > 4 {
                let expiredGeneration = generationOrder.removeFirst()
                lastSequenceByGeneration.removeValue(forKey: expiredGeneration)
            }
        }
        let previous = lastSequenceByGeneration[request.connectionGeneration, default: 0]
        guard request.requestSequence > previous else { return nil }
        lastSequenceByGeneration[request.connectionGeneration] = request.requestSequence
        return .proceed
    }

    private func handleNewRequest(
        _ request: RemoteOrbitHIDHelperRequest,
        completion: @escaping (RemoteOrbitHIDHelperReply) -> Void
    ) {
        guard request.protocolVersion == 7,
              let state = transport.state,
              state.packageVersion == "8.6.0",
              state.clientProtocolVersion == request.protocolVersion,
              state.connectionGeneration == request.connectionGeneration,
              state.keyboardReady else {
            finish(request, .rejected, completion)
            return
        }

        switch request.operation {
        case let .begin(rawKeyCodes):
            guard let bitmap = modifierBitmap(for: rawKeyCodes),
                  let physical = physicalModifierKeyCodesProvider() else {
                finish(request, .rejected, completion)
                return
            }
            let requestedFamilies = Set(rawKeyCodes.compactMap(Self.modifierFamily))
            let physicalFamilies = Set(physical.compactMap(Self.modifierFamily))
            guard requestedFamilies.count == rawKeyCodes.count,
                  requestedFamilies.isDisjoint(with: physicalFamilies) else {
                finish(request, .rejected, completion)
                return
            }
            if let current = owner {
                if current.connectionID == request.connectionID,
                   current.sessionID == request.sessionID,
                   current.modifierKeyCodes == rawKeyCodes.sorted(),
                   !current.releasePending {
                    finish(request, .queued, completion)
                } else {
                    finish(request, .rejected, completion)
                }
                return
            }
            var candidate = Owner(
                identity: UUID(),
                connectionID: request.connectionID,
                sessionID: request.sessionID,
                generation: request.connectionGeneration,
                modifierKeyCodes: rawKeyCodes.sorted(),
                releasePending: false
            )
            owner = candidate
            transport.submitModifierBitmap(bitmap) { [weak self] outcome in
                guard let self else { return }
                self.queue.async {
                    if self.owner?.identity == candidate.identity {
                        if outcome == .rejected {
                            self.owner = nil
                        } else if outcome == .outcomeUnknown {
                            candidate.releasePending = true
                            self.owner = candidate
                        }
                    }
                    self.finish(request, outcome, completion)
                }
            }
        case .release, .recover:
            guard let current = owner else {
                let key = releaseKey(request.sessionID, request.connectionGeneration)
                if releasedSessions.contains(key) {
                    finish(request, .queued, completion)
                } else {
                    finish(request, .rejected, completion)
                }
                return
            }
            let sameConnectionOwner = current.connectionID == request.connectionID
                && current.sessionID == request.sessionID
                && current.generation == request.connectionGeneration
            let safeReconnectRecovery = request.operation == .recover
                && current.releasePending
                && current.sessionID == request.sessionID
                && current.generation == request.connectionGeneration
            guard sameConnectionOwner || safeReconnectRecovery else {
                finish(request, .rejected, completion)
                return
            }
            owner?.connectionID = request.connectionID
            owner?.releasePending = true
            guard let reboundOwner = owner else {
                finish(request, .outcomeUnknown, completion)
                return
            }
            submitNeutral(
                for: reboundOwner,
                waiter: NeutralWaiter(request: request, completion: completion)
            )
        }
    }

    private func submitNeutral(for current: Owner, waiter: NeutralWaiter? = nil) {
        if var currentFlight = neutralFlight {
            guard currentFlight.ownerIdentity == current.identity else {
                if let waiter { finish(waiter.request, .outcomeUnknown, waiter.completion) }
                return
            }
            if let waiter { currentFlight.waiters.append(waiter) }
            neutralFlight = currentFlight
            return
        }

        let flight = NeutralFlight(
            identity: UUID(),
            ownerIdentity: current.identity,
            sessionID: current.sessionID,
            generation: current.generation,
            waiters: waiter.map { [$0] } ?? []
        )
        neutralFlight = flight
        transport.submitModifierBitmap(0) { [weak self] outcome in
            guard let self else { return }
            self.queue.async {
                guard let activeFlight = self.neutralFlight,
                      activeFlight.identity == flight.identity else { return }
                self.neutralFlight = nil

                let stillOwnsSession = self.owner?.identity == activeFlight.ownerIdentity
                if outcome == .queued {
                    self.rememberReleasedSession(self.releaseKey(activeFlight.sessionID, activeFlight.generation))
                    if stillOwnsSession { self.owner = nil }
                } else if stillOwnsSession {
                    self.owner?.releasePending = true
                }

                for pending in activeFlight.waiters {
                    self.finish(pending.request, outcome, pending.completion)
                }
            }
        }
    }

    private func finish(
        _ request: RemoteOrbitHIDHelperRequest,
        _ outcome: RemoteOrbitHIDHelperOutcome,
        _ completion: @escaping (RemoteOrbitHIDHelperReply) -> Void
    ) {
        let reply = reply(for: request, outcome: outcome)
        let key = RequestKey(generation: request.connectionGeneration, sequence: request.requestSequence)
        cache[key] = CachedReply(fingerprint: requestFingerprint(request), reply: reply)
        cacheOrder.append(key)
        if cacheOrder.count > 256 {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
        completion(reply)
    }

    private func rememberReleasedSession(_ key: String) {
        guard releasedSessions.insert(key).inserted else { return }
        releasedSessionOrder.append(key)
        if releasedSessionOrder.count > 128 {
            releasedSessions.remove(releasedSessionOrder.removeFirst())
        }
    }

    private func reply(
        for request: RemoteOrbitHIDHelperRequest,
        outcome: RemoteOrbitHIDHelperOutcome
    ) -> RemoteOrbitHIDHelperReply {
        RemoteOrbitHIDHelperReply(
            connectionGeneration: request.connectionGeneration,
            requestSequence: request.requestSequence,
            outcome: outcome
        )
    }

    private func requestFingerprint(_ request: RemoteOrbitHIDHelperRequest) -> String {
        let operation: String
        switch request.operation {
        case let .begin(keyCodes): operation = "begin:" + keyCodes.map(String.init).joined(separator: ",")
        case .release: operation = "release"
        case .recover: operation = "recover"
        }
        return "\(request.connectionID.uuidString)|\(request.sessionID.uuidString)|\(request.protocolVersion)|\(operation)"
    }

    private func releaseKey(_ sessionID: UUID, _ generation: UInt64) -> String {
        "\(sessionID.uuidString)|\(generation)"
    }

    private func modifierBitmap(for rawKeyCodes: [UInt16]) -> UInt8? {
        guard rawKeyCodes.count >= 2, Set(rawKeyCodes).count == rawKeyCodes.count else { return nil }
        let bits: [UInt16: UInt8] = [59: 0x01, 56: 0x02, 58: 0x04, 55: 0x08,
                                     62: 0x10, 60: 0x20, 61: 0x40, 54: 0x80]
        var result: UInt8 = 0
        for keyCode in rawKeyCodes {
            guard let bit = bits[keyCode] else { return nil }
            result |= bit
        }
        return result
    }

    private static func modifierFamily(_ keyCode: UInt16) -> UInt16? {
        switch keyCode {
        case 54, 55: 1
        case 59, 62: 2
        case 58, 61: 3
        case 56, 60: 4
        default: nil
        }
    }
}

public final class RemoteOrbitHIDHelperXPCService: NSObject, RemoteOrbitHIDXPCProtocol {
    private let connectionID: UUID
    private let manager: RemoteOrbitHIDHelperSessionManager

    public init(connectionID: UUID, manager: RemoteOrbitHIDHelperSessionManager) {
        self.connectionID = connectionID
        self.manager = manager
    }

    public func beginModifierSession(
        _ sessionID: NSUUID,
        modifierKeyCodes: [NSNumber],
        protocolVersion: Int,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        withReply reply: @escaping (UInt64, UInt64, Int) -> Void
    ) {
        guard let decodedKeyCodes = decodeModifierKeyCodes(modifierKeyCodes) else {
            reply(connectionGeneration, requestSequence, RemoteOrbitHIDHelperOutcome.rejected.rawValue)
            return
        }
        submit(
            sessionID: sessionID,
            protocolVersion: protocolVersion,
            connectionGeneration: connectionGeneration,
            requestSequence: requestSequence,
            operation: .begin(decodedKeyCodes),
            reply: reply
        )
    }

    public func releaseModifierSession(
        _ sessionID: NSUUID,
        protocolVersion: Int,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        withReply reply: @escaping (UInt64, UInt64, Int) -> Void
    ) {
        submit(sessionID: sessionID, protocolVersion: protocolVersion,
               connectionGeneration: connectionGeneration, requestSequence: requestSequence,
               operation: .release, reply: reply)
    }

    public func recoverModifierSession(
        _ sessionID: NSUUID,
        protocolVersion: Int,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        withReply reply: @escaping (UInt64, UInt64, Int) -> Void
    ) {
        submit(sessionID: sessionID, protocolVersion: protocolVersion,
               connectionGeneration: connectionGeneration, requestSequence: requestSequence,
               operation: .recover, reply: reply)
    }

    public func getModifierStatus(withReply reply: @escaping (String, Int, UInt64, Bool) -> Void) {
        manager.status { state in
            guard let state else {
                reply("8.6.0", 7, 0, false)
                return
            }
            reply(state.packageVersion, state.clientProtocolVersion, state.connectionGeneration, state.keyboardReady)
        }
    }

    private func submit(
        sessionID: NSUUID,
        protocolVersion: Int,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        operation: RemoteOrbitHIDHelperRequest.Operation,
        reply: @escaping (UInt64, UInt64, Int) -> Void
    ) {
        let request = RemoteOrbitHIDHelperRequest(
            connectionID: connectionID,
            sessionID: sessionID as UUID,
            protocolVersion: protocolVersion,
            connectionGeneration: connectionGeneration,
            requestSequence: requestSequence,
            operation: operation
        )
        manager.submit(request) { result in
            reply(result.connectionGeneration, result.requestSequence, result.outcome.rawValue)
        }
    }

    private func decodeModifierKeyCodes(_ values: [NSNumber]) -> [UInt16]? {
        guard values.count <= 8 else { return nil }
        var result: [UInt16] = []
        result.reserveCapacity(values.count)
        for value in values {
            let raw = value.int64Value
            guard value.doubleValue.isFinite,
                  value.doubleValue == Double(raw),
                  raw >= 0,
                  raw <= Int64(UInt16.max) else {
                return nil
            }
            result.append(UInt16(raw))
        }
        return result
    }
}

public final class RemoteOrbitHIDHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let policy: RemoteOrbitHIDHelperSigningPolicy
    private let manager: RemoteOrbitHIDHelperSessionManager
    private var configured = false

    public init(policy: RemoteOrbitHIDHelperSigningPolicy = .production,
                manager: RemoteOrbitHIDHelperSessionManager) {
        self.policy = policy
        self.manager = manager
    }

    /// Configures peer verification only. It does not resume or launch a listener.
    @discardableResult
    public func configure(_ listener: NSXPCListener) -> Bool {
        guard policy.installIncomingApplicationRequirement(on: listener) else { return false }
        listener.delegate = self
        configured = true
        return true
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard configured, policy.productionApplicationRequirement() != nil else { return false }
        let connectionID = UUID()
        let service = RemoteOrbitHIDHelperXPCService(connectionID: connectionID, manager: manager)
        connection.exportedInterface = NSXPCInterface(with: RemoteOrbitHIDXPCProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak manager] in manager?.disconnect(connectionID: connectionID) }
        connection.interruptionHandler = { [weak manager] in manager?.disconnect(connectionID: connectionID) }
        connection.resume()
        return true
    }
}
