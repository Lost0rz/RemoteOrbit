import Darwin
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

public struct RemoteOrbitHIDKeyboardCombo: Equatable, Codable {
    public let modifierBitmap: UInt8
    public let primaryKeyUsage: UInt16?

    public init(modifierBitmap: UInt8, primaryKeyUsage: UInt16? = nil) {
        self.modifierBitmap = modifierBitmap
        self.primaryKeyUsage = primaryKeyUsage
    }

    public static let neutral = RemoteOrbitHIDKeyboardCombo(modifierBitmap: 0, primaryKeyUsage: nil)
}

public struct RemoteOrbitHIDKeyboardStep: Equatable {
    public let modifierBitmap: UInt8
    public let keyUsages: [UInt16]

    public init(modifierBitmap: UInt8, keyUsages: [UInt16] = []) {
        self.modifierBitmap = modifierBitmap
        self.keyUsages = keyUsages
    }

    public static let neutral = RemoteOrbitHIDKeyboardStep(modifierBitmap: 0, keyUsages: [])
}

public enum RemoteOrbitHIDKeyboardReportSequencer {
    /// Emits cumulative modifier press steps followed by the optional primary
    /// key so macOS IOHIDEventSystem, AppKit, Carbon hotkeys, and external IMEs
    /// observe natural human key-down ordering.
    public static func beginSteps(for combo: RemoteOrbitHIDKeyboardCombo) -> [RemoteOrbitHIDKeyboardStep] {
        var steps: [RemoteOrbitHIDKeyboardStep] = []
        var cumulative: UInt8 = 0
        for bitIndex in 0..<8 {
            let mask = UInt8(1) << bitIndex
            if (combo.modifierBitmap & mask) != 0 {
                cumulative |= mask
                steps.append(RemoteOrbitHIDKeyboardStep(modifierBitmap: cumulative, keyUsages: []))
            }
        }
        if let usage = combo.primaryKeyUsage, usage != 0 {
            steps.append(RemoteOrbitHIDKeyboardStep(modifierBitmap: cumulative, keyUsages: [usage]))
        }
        if steps.isEmpty {
            steps.append(.neutral)
        }
        return steps
    }

    /// Releases the primary key while modifiers are still held, then peels
    /// modifiers in reverse order down to neutral `(0, [])`. Emergency recovery
    /// or disconnect jumps straight to neutral `(0, [])`.
    public static func releaseSteps(
        from previous: RemoteOrbitHIDKeyboardCombo?,
        graceful: Bool
    ) -> [RemoteOrbitHIDKeyboardStep] {
        guard graceful, let previous else {
            return [.neutral]
        }
        var steps: [RemoteOrbitHIDKeyboardStep] = []
        var remaining = previous.modifierBitmap
        if previous.primaryKeyUsage != nil, remaining != 0 {
            steps.append(RemoteOrbitHIDKeyboardStep(modifierBitmap: remaining, keyUsages: []))
        }
        for bitIndex in stride(from: 7, through: 0, by: -1) {
            let mask = UInt8(1) << bitIndex
            if (remaining & mask) != 0 {
                remaining &= ~mask
                steps.append(RemoteOrbitHIDKeyboardStep(modifierBitmap: remaining, keyUsages: []))
            }
        }
        if steps.last != .neutral {
            steps.append(.neutral)
        }
        return steps
    }
}

public struct RemoteOrbitHIDHelperTransportState: Equatable {
    public let packageVersion: String
    public let clientProtocolVersion: Int
    public let connectionGeneration: UInt64
    public let keyboardReady: Bool
    public let serviceConnected: Bool

    public init(
        packageVersion: String,
        clientProtocolVersion: Int,
        connectionGeneration: UInt64,
        keyboardReady: Bool,
        serviceConnected: Bool = true
    ) {
        self.packageVersion = packageVersion
        self.clientProtocolVersion = clientProtocolVersion
        self.connectionGeneration = connectionGeneration
        self.keyboardReady = keyboardReady
        self.serviceConnected = serviceConnected
    }
}

public protocol RemoteOrbitHIDHelperTransport: AnyObject {
    var state: RemoteOrbitHIDHelperTransportState? { get }
    var reportedStatus: RemoteOrbitHIDHelperTransportState { get }
    func submitModifierBitmap(
        _ modifierBitmap: UInt8,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    )
    func submitKeyboardCombo(
        _ combo: RemoteOrbitHIDKeyboardCombo,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    )
    func submitNeutralRelease(
        from previous: RemoteOrbitHIDKeyboardCombo?,
        graceful: Bool,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    )
}

public extension RemoteOrbitHIDHelperTransport {
    var reportedStatus: RemoteOrbitHIDHelperTransportState {
        if let state {
            return state
        }
        return RemoteOrbitHIDHelperTransportState(
            packageVersion: "8.6.0",
            clientProtocolVersion: 7,
            connectionGeneration: 0,
            keyboardReady: false,
            serviceConnected: false
        )
    }

    func submitKeyboardCombo(
        _ combo: RemoteOrbitHIDKeyboardCombo,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    ) {
        submitModifierBitmap(combo.modifierBitmap, completion: completion)
    }

    func submitNeutralRelease(
        from previous: RemoteOrbitHIDKeyboardCombo?,
        graceful: Bool,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    ) {
        submitModifierBitmap(0, completion: completion)
    }
}

/// Thin adapter over the pinned pqrs `client.hpp`. Construction does not start
/// the dispatcher or connect to the privileged driver service; only the root
/// helper daemon calls `start()` explicitly.
public final class KarabinerVirtualHIDTransport: RemoteOrbitHIDHelperTransport {
    private final class CallbackBox {
        weak var owner: KarabinerVirtualHIDTransport?
        init(owner: KarabinerVirtualHIDTransport) {
            self.owner = owner
        }
    }

    private let queue = DispatchQueue(label: "com.lost0rz.RemoteOrbitHIDHelper.karabiner-client")
    private let stateObserverLock = NSLock()
    private var stateObserver: ((RemoteOrbitHIDHelperTransportState) -> Void)?
    private var lastNotifiedState: RemoteOrbitHIDHelperTransportState?
    private var client: OpaquePointer?
    private var callbackBox: CallbackBox?

    public init() {}

    deinit {
        if let client {
            rohid_client_set_state_callback(client, nil, nil)
            rohid_client_destroy(client)
        }
    }

    public func setStateObserver(_ observer: ((RemoteOrbitHIDHelperTransportState) -> Void)?) {
        stateObserverLock.lock()
        stateObserver = observer
        lastNotifiedState = nil
        stateObserverLock.unlock()
    }

    public var state: RemoteOrbitHIDHelperTransportState? {
        queue.sync {
            guard let client else { return nil }
            let generation = rohid_client_connection_generation(client)
            guard rohid_client_keyboard_ready(client) else { return nil }
            return RemoteOrbitHIDHelperTransportState(
                packageVersion: "8.6.0",
                clientProtocolVersion: Int(rohid_client_protocol_version()),
                connectionGeneration: generation,
                keyboardReady: true,
                serviceConnected: rohid_client_service_connected(client)
            )
        }
    }

    public var reportedStatus: RemoteOrbitHIDHelperTransportState {
        queue.sync {
            guard let client else {
                return RemoteOrbitHIDHelperTransportState(
                    packageVersion: "8.6.0",
                    clientProtocolVersion: Int(rohid_client_protocol_version()),
                    connectionGeneration: 0,
                    keyboardReady: false,
                    serviceConnected: false
                )
            }
            return RemoteOrbitHIDHelperTransportState(
                packageVersion: "8.6.0",
                clientProtocolVersion: Int(rohid_client_protocol_version()),
                connectionGeneration: rohid_client_connection_generation(client),
                keyboardReady: rohid_client_keyboard_ready(client),
                serviceConnected: rohid_client_service_connected(client)
            )
        }
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, self.client == nil else { return }
            guard let client = rohid_client_create() else { return }
            let box = CallbackBox(owner: self)
            self.callbackBox = box
            self.client = client
            let rawBox = Unmanaged.passUnretained(box).toOpaque()
            rohid_client_set_state_callback(client, { context, generation, ready, connected in
                guard let context else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
                box.owner?.notifyStateChanged(
                    generation: generation,
                    keyboardReady: ready,
                    serviceConnected: connected
                )
            }, rawBox)
            rohid_client_start(client)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self, let client = self.client else { return }
            rohid_client_set_state_callback(client, nil, nil)
            rohid_client_destroy(client)
            self.client = nil
            self.callbackBox = nil
            self.stateObserverLock.lock()
            self.lastNotifiedState = nil
            self.stateObserverLock.unlock()
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
            completion(.queued)
        }
    }

    public func submitKeyboardCombo(
        _ combo: RemoteOrbitHIDKeyboardCombo,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let client = self.client,
                  rohid_client_keyboard_ready(client) else {
                completion(.rejected)
                return
            }
            let steps = RemoteOrbitHIDKeyboardReportSequencer.beginSteps(for: combo)
            for (index, step) in steps.enumerated() {
                if index > 0 {
                    // Yield 2 ms between multi-step HID reports so WindowServer
                    // and IMEs observe distinct key/modifier transitions.
                    Darwin.usleep(2_000)
                }
                let posted = step.keyUsages.withUnsafeBufferPointer { buffer in
                    rohid_client_post_keyboard_report(
                        client,
                        step.modifierBitmap,
                        buffer.baseAddress,
                        buffer.count
                    )
                }
                if !posted {
                    _ = rohid_client_post_modifier_bitmap(client, 0)
                    completion(.rejected)
                    return
                }
            }
            completion(.queued)
        }
    }

    public func submitNeutralRelease(
        from previous: RemoteOrbitHIDKeyboardCombo?,
        graceful: Bool,
        completion: @escaping (RemoteOrbitHIDHelperOutcome) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let client = self.client,
                  rohid_client_keyboard_ready(client) else {
                completion(.rejected)
                return
            }
            let steps = RemoteOrbitHIDKeyboardReportSequencer.releaseSteps(
                from: previous,
                graceful: graceful
            )
            for (index, step) in steps.enumerated() {
                if index > 0 {
                    Darwin.usleep(2_000)
                }
                let posted = step.keyUsages.withUnsafeBufferPointer { buffer in
                    rohid_client_post_keyboard_report(
                        client,
                        step.modifierBitmap,
                        buffer.baseAddress,
                        buffer.count
                    )
                }
                if !posted {
                    _ = rohid_client_post_modifier_bitmap(client, 0)
                    completion(.rejected)
                    return
                }
            }
            completion(.queued)
        }
    }

    private func notifyStateChanged(
        generation: UInt64,
        keyboardReady: Bool,
        serviceConnected: Bool
    ) {
        let snapshot = RemoteOrbitHIDHelperTransportState(
            packageVersion: "8.6.0",
            clientProtocolVersion: Int(rohid_client_protocol_version()),
            connectionGeneration: generation,
            keyboardReady: keyboardReady,
            serviceConnected: serviceConnected
        )
        stateObserverLock.lock()
        if lastNotifiedState == snapshot {
            stateObserverLock.unlock()
            return
        }
        lastNotifiedState = snapshot
        let observer = stateObserver
        stateObserverLock.unlock()
        observer?(snapshot)
    }

    public func emitStateChangeForTesting(
        generation: UInt64,
        keyboardReady: Bool,
        serviceConnected: Bool
    ) {
        notifyStateChanged(
            generation: generation,
            keyboardReady: keyboardReady,
            serviceConnected: serviceConnected
        )
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
        case beginCombo(modifierKeyCodes: [UInt16], primaryKeyUsage: UInt16?)
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

/// Serial helper-side session owner. It accepts validated modifier-only or
/// modifier+key combinations, caches exact duplicates, rejects sequence replay,
/// and retains ownership whenever a neutral request was rejected or unknown.
public final class RemoteOrbitHIDHelperSessionManager {
    private struct Owner {
        let identity: UUID
        var connectionID: UUID
        let sessionID: UUID
        let generation: UInt64
        let modifierKeyCodes: [UInt16]
        let primaryKeyUsage: UInt16?
        let combo: RemoteOrbitHIDKeyboardCombo
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

    private struct SequenceScopeKey: Hashable {
        let connectionID: UUID
        let generation: UInt64
    }

    private struct RequestKey: Hashable {
        let connectionID: UUID
        let generation: UInt64
        let sequence: UInt64
    }

    private struct CachedReply {
        let fingerprint: String
        let reply: RemoteOrbitHIDHelperReply
    }

    private static let allowedPrimaryUsages: Set<UInt16> = {
        var usages = Set<UInt16>(0x04...0x38)
        usages.formUnion(0x3A...0x45) // F1-F12
        usages.formUnion(0x4A...0x64) // Navigation, Keypad, ISO Section
        usages.insert(0x67)           // Keypad Equal
        usages.formUnion(0x68...0x6F) // F13-F20
        usages.insert(0x85)           // JIS Keypad Comma
        usages.insert(0x87)           // JIS Underscore
        usages.insert(0x89)           // JIS Yen
        return usages
    }()

    private let transport: RemoteOrbitHIDHelperTransport
    private let physicalModifierKeyCodesProvider: () -> Set<UInt16>?
    private let queue = DispatchQueue(label: "com.lost0rz.RemoteOrbitHIDHelper.session-owner")
    private var owner: Owner?
    private var neutralFlight: NeutralFlight?
    private var lastSequenceByScope: [SequenceScopeKey: UInt64] = [:]
    private var sequenceScopeOrder: [SequenceScopeKey] = []
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
            guard let self else { return }
            self.lastSequenceByScope = self.lastSequenceByScope.filter { $0.key.connectionID != connectionID }
            self.sequenceScopeOrder.removeAll { $0.connectionID == connectionID }
            let staleCacheKeys = self.cache.keys.filter { $0.connectionID == connectionID }
            for key in staleCacheKeys {
                self.cache.removeValue(forKey: key)
            }
            self.cacheOrder.removeAll { $0.connectionID == connectionID }
            guard var current = self.owner,
                  current.connectionID == connectionID else { return }
            current.releasePending = true
            self.owner = current
            self.submitNeutral(for: current, graceful: false)
        }
    }

    public func status() -> RemoteOrbitHIDHelperTransportState? {
        transport.state
    }

    public func reportedStatus() -> RemoteOrbitHIDHelperTransportState {
        transport.reportedStatus
    }

    public func status(completion: @escaping (RemoteOrbitHIDHelperTransportState?) -> Void) {
        queue.async { [weak self] in completion(self?.transport.state) }
    }

    public func reportedStatus(completion: @escaping (RemoteOrbitHIDHelperTransportState) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                completion(RemoteOrbitHIDHelperTransportState(
                    packageVersion: "8.6.0",
                    clientProtocolVersion: 7,
                    connectionGeneration: 0,
                    keyboardReady: false,
                    serviceConnected: false
                ))
                return
            }
            completion(self.transport.reportedStatus)
        }
    }

    private enum ReplayDecision {
        case proceed
        case replay(RemoteOrbitHIDHelperReply)
    }

    private func replayOrAccept(_ request: RemoteOrbitHIDHelperRequest) -> ReplayDecision? {
        let key = RequestKey(
            connectionID: request.connectionID,
            generation: request.connectionGeneration,
            sequence: request.requestSequence
        )
        let fingerprint = requestFingerprint(request)
        if let cached = cache[key] {
            return cached.fingerprint == fingerprint ? .replay(cached.reply) : nil
        }
        let scopeKey = SequenceScopeKey(
            connectionID: request.connectionID,
            generation: request.connectionGeneration
        )
        if lastSequenceByScope[scopeKey] == nil {
            sequenceScopeOrder.append(scopeKey)
            if sequenceScopeOrder.count > 16 {
                let expiredScope = sequenceScopeOrder.removeFirst()
                lastSequenceByScope.removeValue(forKey: expiredScope)
            }
        }
        let previous = lastSequenceByScope[scopeKey, default: 0]
        guard request.requestSequence > previous else { return nil }
        lastSequenceByScope[scopeKey] = request.requestSequence
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
            handleBeginRequest(
                request,
                rawKeyCodes: rawKeyCodes,
                primaryKeyUsage: nil,
                minimumModifiers: 2,
                completion: completion
            )
        case let .beginCombo(rawKeyCodes, primaryKeyUsage):
            if let primaryKeyUsage {
                guard Self.allowedPrimaryUsages.contains(primaryKeyUsage) else {
                    finish(request, .rejected, completion)
                    return
                }
            }
            handleBeginRequest(
                request,
                rawKeyCodes: rawKeyCodes,
                primaryKeyUsage: primaryKeyUsage,
                minimumModifiers: primaryKeyUsage == nil ? 2 : 1,
                completion: completion
            )
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
                graceful: request.operation == .release,
                waiter: NeutralWaiter(request: request, completion: completion)
            )
        }
    }

    private func handleBeginRequest(
        _ request: RemoteOrbitHIDHelperRequest,
        rawKeyCodes: [UInt16],
        primaryKeyUsage: UInt16?,
        minimumModifiers: Int,
        completion: @escaping (RemoteOrbitHIDHelperReply) -> Void
    ) {
        guard let bitmap = modifierBitmap(for: rawKeyCodes, minimumCount: minimumModifiers),
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
        let sortedKeyCodes = rawKeyCodes.sorted()
        if let current = owner {
            if current.connectionID == request.connectionID,
               current.sessionID == request.sessionID,
               current.modifierKeyCodes == sortedKeyCodes,
               current.primaryKeyUsage == primaryKeyUsage,
               !current.releasePending {
                finish(request, .queued, completion)
            } else {
                finish(request, .rejected, completion)
            }
            return
        }
        let combo = RemoteOrbitHIDKeyboardCombo(
            modifierBitmap: bitmap,
            primaryKeyUsage: primaryKeyUsage
        )
        let candidate = Owner(
            identity: UUID(),
            connectionID: request.connectionID,
            sessionID: request.sessionID,
            generation: request.connectionGeneration,
            modifierKeyCodes: sortedKeyCodes,
            primaryKeyUsage: primaryKeyUsage,
            combo: combo,
            releasePending: false
        )
        owner = candidate
        transport.submitKeyboardCombo(combo) { [weak self] outcome in
            guard let self else { return }
            self.queue.async {
                if self.owner?.identity == candidate.identity {
                    switch outcome {
                    case .rejected:
                        let neutralIsUnresolved = self.owner?.releasePending == true
                            || self.neutralFlight?.ownerIdentity == candidate.identity
                        if neutralIsUnresolved {
                            self.owner?.releasePending = true
                        } else {
                            self.owner = nil
                        }
                    case .outcomeUnknown:
                        self.owner?.releasePending = true
                    case .queued:
                        break
                    }
                }
                self.finish(request, outcome, completion)
            }
        }
    }

    private func submitNeutral(
        for current: Owner,
        graceful: Bool,
        waiter: NeutralWaiter? = nil
    ) {
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
        transport.submitNeutralRelease(from: current.combo, graceful: graceful) { [weak self] outcome in
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
        let key = RequestKey(
            connectionID: request.connectionID,
            generation: request.connectionGeneration,
            sequence: request.requestSequence
        )
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
        case let .begin(keyCodes):
            operation = "begin:" + keyCodes.map(String.init).joined(separator: ",")
        case let .beginCombo(keyCodes, primaryKeyUsage):
            let primaryPart = primaryKeyUsage.map(String.init) ?? "none"
            operation = "beginCombo:" + keyCodes.map(String.init).joined(separator: ",") + "|primary:" + primaryPart
        case .release:
            operation = "release"
        case .recover:
            operation = "recover"
        }
        return "\(request.connectionID.uuidString)|\(request.sessionID.uuidString)|\(request.protocolVersion)|\(operation)"
    }

    private func releaseKey(_ sessionID: UUID, _ generation: UInt64) -> String {
        "\(sessionID.uuidString)|\(generation)"
    }

    private func modifierBitmap(for rawKeyCodes: [UInt16], minimumCount: Int) -> UInt8? {
        guard rawKeyCodes.count >= minimumCount,
              Set(rawKeyCodes).count == rawKeyCodes.count else { return nil }
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
