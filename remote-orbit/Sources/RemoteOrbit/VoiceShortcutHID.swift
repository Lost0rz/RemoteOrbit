import Dispatch
import Foundation
import RemoteOrbitHIDHelper

/// Source identity for the pinned client and report ABI.
enum VoiceShortcutHIDProviderContract {
    static let packageVersion = "8.6.0"
    static let clientProtocolVersion = 7
    static let sourceCommit = "9036bc771259ff8d61341f4d1b7072b954fdb2fa"
    static let sourceURL = "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/9036bc771259ff8d61341f4d1b7072b954fdb2fa"
}

/// Modifier-only view of the upstream packed `keyboard_input` report.
struct VoiceShortcutHIDModifierReport: Equatable {
    static let expectedReportID: UInt8 = 1
    static let ordinaryKeySlotCount = 32

    let reportID: UInt8
    let modifierBitmap: UInt8
    let reservedByte: UInt8
    let ordinaryKeyUsages: [UInt16]

    fileprivate init(modifierBitmap: UInt8) {
        reportID = Self.expectedReportID
        self.modifierBitmap = modifierBitmap
        reservedByte = 0
        ordinaryKeyUsages = Array(repeating: 0, count: Self.ordinaryKeySlotCount)
    }

    static let neutral = VoiceShortcutHIDModifierReport(modifierBitmap: 0)

    var hasValidModifierOnlyLayout: Bool {
        reportID == Self.expectedReportID
            && reservedByte == 0
            && ordinaryKeyUsages.count == Self.ordinaryKeySlotCount
            && ordinaryKeyUsages.allSatisfy { $0 == 0 }
    }
}

enum VoiceShortcutHIDReportEncodingError: Error, Equatable {
    case emptyModifierSet
    case duplicateKeyCode(UInt16)
    case unsupportedKeyCode(UInt16)
}

enum VoiceShortcutHIDReportEncoder {
    /// Encodes macOS modifier keyCodes into the upstream USB HID E0-E7 bitmap.
    static func encode(modifierKeyCodes: [UInt16]) throws -> VoiceShortcutHIDModifierReport {
        guard !modifierKeyCodes.isEmpty else {
            throw VoiceShortcutHIDReportEncodingError.emptyModifierSet
        }
        var seen = Set<UInt16>()
        var bitmap: UInt8 = 0
        for keyCode in modifierKeyCodes {
            guard seen.insert(keyCode).inserted else {
                throw VoiceShortcutHIDReportEncodingError.duplicateKeyCode(keyCode)
            }
            guard let bit = bitByMacKeyCode[keyCode] else {
                throw VoiceShortcutHIDReportEncodingError.unsupportedKeyCode(keyCode)
            }
            bitmap |= bit
        }
        return VoiceShortcutHIDModifierReport(modifierBitmap: bitmap)
    }

    private static let bitByMacKeyCode: [UInt16: UInt8] = [
        59: 0x01, // Left Control — E0
        56: 0x02, // Left Shift — E1
        58: 0x04, // Left Option — E2
        55: 0x08, // Left Command — E3
        62: 0x10, // Right Control — E4
        60: 0x20, // Right Shift — E5
        61: 0x40, // Right Option — E6
        54: 0x80, // Right Command — E7
    ]
}

enum VoiceShortcutHIDProviderState: Equatable {
    case unavailable
    case ready(
        packageVersion: String,
        clientProtocolVersion: Int,
        connectionGeneration: UInt64,
        keyboardReady: Bool
    )
}

enum VoiceShortcutHIDOperation: String, Equatable {
    case begin
    case release
    case recover
    case status
}

struct VoiceShortcutHIDRequest: Equatable {
    let protocolVersion: Int
    let connectionGeneration: UInt64
    let sessionID: UUID
    let requestSequence: UInt64
    let operation: VoiceShortcutHIDOperation
    let modifierKeyCodes: [UInt16]
    let report: VoiceShortcutHIDModifierReport?
}

enum VoiceShortcutHIDSubmissionOutcome: Equatable {
    /// The helper invoked the pinned client's async report method. This is not
    /// DriverKit delivery or target input-method acknowledgement.
    case queued
    /// The helper rejected the request before invoking the upstream client.
    case rejected
    /// The caller cannot determine whether the request reached the upstream queue.
    case outcomeUnknown
}

struct VoiceShortcutHIDProviderReply: Equatable {
    let connectionGeneration: UInt64
    let requestSequence: UInt64
    let outcome: VoiceShortcutHIDSubmissionOutcome
}

/// Provider requests complete asynchronously. `state` is a nonblocking,
/// lock-protected snapshot; it must never wait on XPC or DriverKit.
protocol VoiceShortcutHIDReportProvider: AnyObject {
    var state: VoiceShortcutHIDProviderState { get }
    func perform(
        _ request: VoiceShortcutHIDRequest,
        completion: @escaping (VoiceShortcutHIDProviderReply) -> Void
    )
}

enum VoiceShortcutHIDSessionError: Equatable {
    case invalidBinding
    case providerUnavailable
    case providerProtocolMismatch
    case providerKeyboardNotReady
    case physicalModifierConflict
    case physicalModifierStateUnavailable
    case ownerBusy
    case sessionBindingChanged
    case sessionAlreadyReleased
    case providerRejected
    case ownershipUnresolved
    case connectionGenerationChanged
    case requestSequenceExhausted
}

enum VoiceShortcutHIDSessionAdmission: Equatable {
    case accepted
    case rejected(VoiceShortcutHIDSessionError)
}

/// Owns one serialized virtual keyboard session without blocking the caller.
/// A matching same-generation neutral queue reply retires logical ownership;
/// timeouts, mismatched replies, rejection, and disconnect retain it.
final class VoiceShortcutHIDSessionOwner {
    private enum Phase: Equatable {
        case beginPending
        case active
        case releasePending
    }

    private struct Session {
        let id: UUID
        let modifierKeyCodes: [UInt16]
        let connectionGeneration: UInt64
        var phase: Phase
        var releaseRequested = false
        var pendingRequestID: UUID?
        var beginWaiters: [(VoiceShortcutHIDSessionAdmission) -> Void] = []
        var releaseWaiters: [(Bool) -> Void] = []
    }

    private let provider: VoiceShortcutHIDReportProvider
    private let physicalModifierKeyCodesProvider: (() -> Set<UInt16>?)?
    private let ownerQueue = DispatchQueue(label: "com.lost0rz.RemoteOrbit.voice-shortcut-hid-owner")
    private let snapshotLock = NSLock()
    private var session: Session?
    private var activeSessionIDSnapshot: UUID?
    private var unresolvedOwnershipSnapshot = false
    private var sequenceGeneration: UInt64?
    private var lastRequestSequence: UInt64 = 0
    private let requestTimeout: TimeInterval

    init(
        provider: VoiceShortcutHIDReportProvider,
        physicalModifierKeyCodesProvider: (() -> Set<UInt16>?)? = nil,
        requestTimeout: TimeInterval = 1.5
    ) {
        self.provider = provider
        self.physicalModifierKeyCodesProvider = physicalModifierKeyCodesProvider
        self.requestTimeout = max(0.05, requestTimeout)
    }

    var activeSessionID: UUID? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return activeSessionIDSnapshot
    }

    var hasUnresolvedOwnership: Bool {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return unresolvedOwnershipSnapshot
    }

    func begin(
        sessionID: UUID,
        modifierKeyCodes rawKeyCodes: [UInt16],
        completion: @escaping (VoiceShortcutHIDSessionAdmission) -> Void
    ) {
        ownerQueue.async { [weak self] in
            self?.beginLocked(
                sessionID: sessionID,
                rawKeyCodes: rawKeyCodes,
                completion: completion
            )
        }
    }

    func end(sessionID: UUID, completion: @escaping (Bool) -> Void) {
        ownerQueue.async { [weak self] in
            guard let self, var current = self.session, current.id == sessionID else {
                completion(false)
                return
            }
            current.releaseRequested = true
            current.releaseWaiters.append(completion)
            self.session = current
            self.publishSnapshot()
            if case .beginPending = current.phase {
                return
            }
            self.sendNeutralLocked(operation: .release)
        }
    }

    func abort(sessionID: UUID, completion: @escaping (Bool) -> Void) {
        end(sessionID: sessionID, completion: completion)
    }

    func recoverPendingRelease(completion: @escaping (Bool) -> Void) {
        ownerQueue.async { [weak self] in
            guard let self, let current = self.session else {
                completion(true)
                return
            }
            guard current.releaseRequested || Self.isReleasePending(current.phase) else {
                completion(false)
                return
            }
            self.session?.releaseRequested = true
            self.sendNeutralLocked(operation: .recover, additionalWaiter: completion)
        }
    }

    private func beginLocked(
        sessionID: UUID,
        rawKeyCodes: [UInt16],
        completion: @escaping (VoiceShortcutHIDSessionAdmission) -> Void
    ) {
        guard (try? VoiceShortcutStore.validate(
            binding: .modifierChord(modifierKeyCodes: rawKeyCodes)
        )) != nil,
        let report = try? VoiceShortcutHIDReportEncoder.encode(
            modifierKeyCodes: rawKeyCodes
        ) else {
            completion(.rejected(.invalidBinding))
            return
        }

        let keyCodes = rawKeyCodes.sorted()
        if let current = session {
            if current.id == sessionID, current.modifierKeyCodes != keyCodes {
                completion(.rejected(.sessionBindingChanged))
                return
            }
            if current.id == sessionID, case .active = current.phase,
               !current.releaseRequested {
                completion(.accepted)
                return
            }
            if current.id == sessionID, case .beginPending = current.phase {
                session?.beginWaiters.append(completion)
                return
            }
            if Self.isReleasePending(current.phase) || current.releaseRequested {
                let wasSameSession = current.id == sessionID
                recoverBeforeNewBeginLocked { [weak self] recovered in
                    guard let self else { return }
                    if wasSameSession {
                        completion(.rejected(.sessionAlreadyReleased))
                    } else if recovered {
                        self.beginLocked(
                            sessionID: sessionID,
                            rawKeyCodes: rawKeyCodes,
                            completion: completion
                        )
                    } else {
                        completion(.rejected(.ownershipUnresolved))
                    }
                }
                return
            }
            completion(.rejected(.ownerBusy))
            return
        }

        guard let state = readyState() else {
            switch provider.state {
            case .unavailable:
                completion(.rejected(.providerUnavailable))
            case .ready:
                completion(.rejected(.providerProtocolMismatch))
            }
            return
        }
        guard state.keyboardReady else {
            completion(.rejected(.providerKeyboardNotReady))
            return
        }
        guard let physicalKeyCodes = physicalModifierKeyCodesProvider?() else {
            completion(.rejected(.physicalModifierStateUnavailable))
            return
        }

        let requestedFamilies = Set(keyCodes.compactMap(Self.modifierFamily))
        let physicalFamilies = Set(physicalKeyCodes.compactMap(Self.modifierFamily))
        guard requestedFamilies.isDisjoint(with: physicalFamilies) else {
            completion(.rejected(.physicalModifierConflict))
            return
        }
        guard let sequence = nextSequence(for: state.connectionGeneration) else {
            completion(.rejected(.requestSequenceExhausted))
            return
        }

        let request = VoiceShortcutHIDRequest(
            protocolVersion: VoiceShortcutHIDProviderContract.clientProtocolVersion,
            connectionGeneration: state.connectionGeneration,
            sessionID: sessionID,
            requestSequence: sequence,
            operation: .begin,
            modifierKeyCodes: keyCodes,
            report: report
        )
        session = Session(
            id: sessionID,
            modifierKeyCodes: keyCodes,
            connectionGeneration: state.connectionGeneration,
            phase: .beginPending,
            beginWaiters: [completion]
        )
        publishSnapshot()
        submitLocked(request) { [weak self] reply in
            self?.handleBeginReplyLocked(reply, request: request)
        }
    }

    private func handleBeginReplyLocked(
        _ reply: VoiceShortcutHIDProviderReply,
        request: VoiceShortcutHIDRequest
    ) {
        guard let current = session, current.id == request.sessionID else { return }
        guard replyMatches(reply, request: request) else {
            session?.releaseRequested = true
            session?.phase = .releasePending
            completeBeginWaiters(.rejected(.ownershipUnresolved))
            publishSnapshot()
            sendNeutralLocked(operation: .recover)
            return
        }
        switch reply.outcome {
        case .queued:
            session?.phase = .active
            completeBeginWaiters(.accepted)
            if session?.releaseRequested == true {
                session?.phase = .releasePending
                sendNeutralLocked(operation: .release)
            } else {
                publishSnapshot()
            }
        case .rejected:
            let beginWaiters = takeBeginWaiters()
            let releaseWaiters = takeReleaseWaiters()
            clearSession()
            beginWaiters.forEach { $0(.rejected(.providerRejected)) }
            releaseWaiters.forEach { $0(false) }
        case .outcomeUnknown:
            session?.releaseRequested = true
            session?.phase = .releasePending
            completeBeginWaiters(.rejected(.ownershipUnresolved))
            publishSnapshot()
            sendNeutralLocked(operation: .recover)
        }
    }

    private func recoverBeforeNewBeginLocked(completion: @escaping (Bool) -> Void) {
        sendNeutralLocked(operation: .recover, additionalWaiter: completion)
    }

    private func sendNeutralLocked(
        operation: VoiceShortcutHIDOperation,
        additionalWaiter: ((Bool) -> Void)? = nil
    ) {
        guard var current = session else {
            additionalWaiter?(true)
            return
        }
        guard current.phase != .beginPending else {
            current.releaseRequested = true
            if let additionalWaiter { current.releaseWaiters.append(additionalWaiter) }
            session = current
            publishSnapshot()
            return
        }
        guard let state = readyState() else {
            current.releaseRequested = true
            current.phase = .releasePending
            if let additionalWaiter { current.releaseWaiters.append(additionalWaiter) }
            session = current
            publishSnapshot()
            completeReleaseWaiters(false)
            return
        }
        guard state.connectionGeneration == current.connectionGeneration else {
            current.releaseRequested = true
            current.phase = .releasePending
            if let additionalWaiter { current.releaseWaiters.append(additionalWaiter) }
            session = current
            publishSnapshot()
            completeReleaseWaiters(false)
            return
        }
        guard state.keyboardReady else {
            current.releaseRequested = true
            current.phase = .releasePending
            if let additionalWaiter { current.releaseWaiters.append(additionalWaiter) }
            session = current
            publishSnapshot()
            completeReleaseWaiters(false)
            return
        }
        guard let sequence = nextSequence(for: current.connectionGeneration) else {
            current.releaseRequested = true
            current.phase = .releasePending
            if let additionalWaiter { current.releaseWaiters.append(additionalWaiter) }
            session = current
            publishSnapshot()
            completeReleaseWaiters(false)
            return
        }

        current.releaseRequested = true
        current.phase = .releasePending
        if let additionalWaiter { current.releaseWaiters.append(additionalWaiter) }
        session = current
        publishSnapshot()
        let request = VoiceShortcutHIDRequest(
            protocolVersion: VoiceShortcutHIDProviderContract.clientProtocolVersion,
            connectionGeneration: current.connectionGeneration,
            sessionID: current.id,
            requestSequence: sequence,
            operation: operation,
            modifierKeyCodes: [],
            report: .neutral
        )
        submitLocked(request) { [weak self] reply in
            guard let self, let owner = self.session, owner.id == request.sessionID else { return }
            guard self.replyMatches(reply, request: request), reply.outcome == .queued else {
                self.session?.phase = .releasePending
                self.publishSnapshot()
                self.completeReleaseWaiters(false)
                return
            }
            let releaseWaiters = self.takeReleaseWaiters()
            self.clearSession()
            releaseWaiters.forEach { $0(true) }
        }
    }

    private func submitLocked(
        _ request: VoiceShortcutHIDRequest,
        completion: @escaping (VoiceShortcutHIDProviderReply) -> Void
    ) {
        let requestID = UUID()
        session?.pendingRequestID = requestID
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.session?.pendingRequestID == requestID else { return }
            self.session?.pendingRequestID = nil
            completion(VoiceShortcutHIDProviderReply(
                connectionGeneration: request.connectionGeneration,
                requestSequence: request.requestSequence,
                outcome: .outcomeUnknown
            ))
        }
        ownerQueue.asyncAfter(deadline: .now() + requestTimeout, execute: timeout)
        provider.perform(request) { [weak self] reply in
            guard let self else { return }
            self.ownerQueue.async {
                guard self.session?.pendingRequestID == requestID else { return }
                timeout.cancel()
                self.session?.pendingRequestID = nil
                completion(reply)
            }
        }
    }

    private func readyState() -> (connectionGeneration: UInt64, keyboardReady: Bool)? {
        guard case let .ready(packageVersion, clientProtocolVersion, generation, keyboardReady) = provider.state,
              packageVersion == VoiceShortcutHIDProviderContract.packageVersion,
              clientProtocolVersion == VoiceShortcutHIDProviderContract.clientProtocolVersion else {
            return nil
        }
        return (generation, keyboardReady)
    }

    private func nextSequence(for generation: UInt64) -> UInt64? {
        if sequenceGeneration != generation {
            guard session == nil else { return nil }
            sequenceGeneration = generation
            lastRequestSequence = 0
        }
        guard lastRequestSequence < UInt64.max else { return nil }
        lastRequestSequence += 1
        return lastRequestSequence
    }

    private func replyMatches(
        _ reply: VoiceShortcutHIDProviderReply,
        request: VoiceShortcutHIDRequest
    ) -> Bool {
        reply.connectionGeneration == request.connectionGeneration
            && reply.requestSequence == request.requestSequence
    }

    private func completeBeginWaiters(_ result: VoiceShortcutHIDSessionAdmission) {
        let waiters = takeBeginWaiters()
        waiters.forEach { $0(result) }
    }

    private func takeBeginWaiters() -> [(VoiceShortcutHIDSessionAdmission) -> Void] {
        let waiters = session?.beginWaiters ?? []
        session?.beginWaiters.removeAll()
        return waiters
    }

    private func completeReleaseWaiters(_ result: Bool) {
        let waiters = takeReleaseWaiters()
        waiters.forEach { $0(result) }
    }

    private func takeReleaseWaiters() -> [(Bool) -> Void] {
        let waiters = session?.releaseWaiters ?? []
        session?.releaseWaiters.removeAll()
        return waiters
    }

    private func clearSession() {
        session = nil
        publishSnapshot()
    }

    private func publishSnapshot() {
        snapshotLock.lock()
        activeSessionIDSnapshot = session?.id
        unresolvedOwnershipSnapshot = session != nil
        snapshotLock.unlock()
    }

    private static func isReleasePending(_ phase: Phase) -> Bool {
        if case .releasePending = phase { return true }
        return false
    }

    private static func modifierFamily(_ keyCode: UInt16) -> UInt16? {
        switch keyCode {
        case 54, 55: return 1 // Command
        case 59, 62: return 2 // Control
        case 58, 61: return 3 // Option
        case 56, 60: return 4 // Shift
        default: return nil
        }
    }
}

/// An explicit, opt-in XPC client. Its initializer is inert. Production cannot
/// connect until the verified helper signing requirement exists in project
/// policy, and the coordinator's default backend remains disabled.
final class VoiceShortcutHIDXPCProvider: VoiceShortcutHIDReportProvider {
    static let serviceName = "com.lost0rz.RemoteOrbitHIDHelper"

    private let lock = NSLock()
    private let signingPolicy: VoiceShortcutHIDSigningPolicy
    private var connection: NSXPCConnection?
    private var connecting = false
    private var stateSnapshot: VoiceShortcutHIDProviderState = .unavailable

    init(signingPolicy: VoiceShortcutHIDSigningPolicy = .production) {
        self.signingPolicy = signingPolicy
    }

    var state: VoiceShortcutHIDProviderState {
        lock.lock()
        defer { lock.unlock() }
        return stateSnapshot
    }

    @discardableResult
    func connectIfTrusted() -> Bool {
        guard signingPolicy.requirement(for: .privilegedHelper) != nil else {
            return false
        }
        lock.lock()
        if connection != nil {
            lock.unlock()
            return true
        }
        guard !connecting else {
            lock.unlock()
            return false
        }
        connecting = true
        lock.unlock()

        let next = NSXPCConnection(machServiceName: Self.serviceName, options: [])
        guard VoiceShortcutHIDXPCTrustGate.installRequirement(
            for: .privilegedHelper,
            policy: signingPolicy,
            on: next
        ) else {
            lock.lock()
            connecting = false
            lock.unlock()
            next.invalidate()
            return false
        }
        next.remoteObjectInterface = NSXPCInterface(with: RemoteOrbitHIDXPCProtocol.self)
        next.interruptionHandler = { [weak self] in self?.markUnavailable(connection: next) }
        next.invalidationHandler = { [weak self] in self?.markUnavailable(connection: next) }
        lock.lock()
        guard connection == nil else {
            connecting = false
            lock.unlock()
            next.invalidate()
            return true
        }
        connection = next
        connecting = false
        lock.unlock()
        next.resume()

        guard let proxy = next.remoteObjectProxyWithErrorHandler({ [weak self] _ in
            self?.markUnavailable(connection: next)
        }) as? RemoteOrbitHIDXPCProtocol else {
            markUnavailable(connection: next)
            return false
        }
        proxy.getModifierStatus { [weak self] packageVersion, clientProtocolVersion, generation, keyboardReady in
            guard let self else { return }
            self.lock.lock()
            guard self.connection === next else {
                self.lock.unlock()
                return
            }
            self.stateSnapshot = .ready(
                packageVersion: packageVersion,
                clientProtocolVersion: clientProtocolVersion,
                connectionGeneration: generation,
                keyboardReady: keyboardReady
            )
            self.lock.unlock()
        }
        return true
    }

    func perform(
        _ request: VoiceShortcutHIDRequest,
        completion: @escaping (VoiceShortcutHIDProviderReply) -> Void
    ) {
        lock.lock()
        let next = connection
        let currentState = stateSnapshot
        lock.unlock()
        guard let next,
              case let .ready(_, protocolVersion, generation, keyboardReady) = currentState,
              protocolVersion == request.protocolVersion,
              generation == request.connectionGeneration,
              keyboardReady else {
            completion(VoiceShortcutHIDProviderReply(
                connectionGeneration: request.connectionGeneration,
                requestSequence: request.requestSequence,
                outcome: .outcomeUnknown
            ))
            return
        }
        let once = VoiceShortcutHIDProviderOneShot { reply in completion(reply) }
        guard let proxy = next.remoteObjectProxyWithErrorHandler({ [weak self] _ in
            self?.markUnavailable(connection: next)
            once.finish(VoiceShortcutHIDProviderReply(
                connectionGeneration: request.connectionGeneration,
                requestSequence: request.requestSequence,
                outcome: .outcomeUnknown
            ))
        }) as? RemoteOrbitHIDXPCProtocol else {
            once.finish(VoiceShortcutHIDProviderReply(
                connectionGeneration: request.connectionGeneration,
                requestSequence: request.requestSequence,
                outcome: .outcomeUnknown
            ))
            return
        }

        let receive: (UInt64, UInt64, Int) -> Void = { replyGeneration, sequence, rawOutcome in
            let outcome: VoiceShortcutHIDSubmissionOutcome
            switch RemoteOrbitHIDHelperOutcome(rawValue: rawOutcome) {
            case .queued: outcome = .queued
            case .rejected: outcome = .rejected
            case .outcomeUnknown, .none: outcome = .outcomeUnknown
            }
            once.finish(VoiceShortcutHIDProviderReply(
                connectionGeneration: replyGeneration,
                requestSequence: sequence,
                outcome: outcome
            ))
        }
        switch request.operation {
        case .begin:
            proxy.beginModifierSession(
                request.sessionID as NSUUID,
                modifierKeyCodes: request.modifierKeyCodes.map { NSNumber(value: $0) },
                protocolVersion: request.protocolVersion,
                connectionGeneration: request.connectionGeneration,
                requestSequence: request.requestSequence,
                withReply: receive
            )
        case .release:
            proxy.releaseModifierSession(
                request.sessionID as NSUUID,
                protocolVersion: request.protocolVersion,
                connectionGeneration: request.connectionGeneration,
                requestSequence: request.requestSequence,
                withReply: receive
            )
        case .recover:
            proxy.recoverModifierSession(
                request.sessionID as NSUUID,
                protocolVersion: request.protocolVersion,
                connectionGeneration: request.connectionGeneration,
                requestSequence: request.requestSequence,
                withReply: receive
            )
        case .status:
            once.finish(VoiceShortcutHIDProviderReply(
                connectionGeneration: request.connectionGeneration,
                requestSequence: request.requestSequence,
                outcome: .rejected
            ))
        }
    }

    private func markUnavailable(connection expected: NSXPCConnection) {
        lock.lock()
        if connection === expected {
            connection = nil
            stateSnapshot = .unavailable
        }
        lock.unlock()
    }
}

private final class VoiceShortcutHIDProviderOneShot {
    private let lock = NSLock()
    private var didFinish = false
    private let completion: (VoiceShortcutHIDProviderReply) -> Void

    init(completion: @escaping (VoiceShortcutHIDProviderReply) -> Void) {
        self.completion = completion
    }

    func finish(_ reply: VoiceShortcutHIDProviderReply) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        completion(reply)
    }
}
