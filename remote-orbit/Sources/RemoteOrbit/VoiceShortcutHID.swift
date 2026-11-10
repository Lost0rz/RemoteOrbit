import Dispatch
import Foundation

/// Source identity for the upstream client API used by the future Helper.
/// v8.6.0 retains protocol 7; the exact client/report headers must still be
/// built and reviewed before a production adapter can be enabled.
enum VoiceShortcutHIDProviderContract {
    static let packageVersion = "8.6.0"
    static let clientProtocolVersion = 7
    static let sourceCommit = "9036bc771259ff8d61341f4d1b7072b954fdb2fa"
    static let sourceURL = "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/9036bc771259ff8d61341f4d1b7072b954fdb2fa"
}

/// The upstream `keyboard_input` C++ report contains a report ID, a modifier
/// bitmap, one reserved byte, and 32 ordinary-key usage slots. Modifier-only
/// voice shortcuts always leave every ordinary-key slot empty.
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
    /// Encodes macOS modifier keyCodes into the USB HID E0-E7 report bitmap.
    /// The neutral release report is explicit so an empty binding cannot be
    /// mistaken for a valid DOWN report.
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
    let report: VoiceShortcutHIDModifierReport?
}

enum VoiceShortcutHIDSubmissionOutcome: Equatable {
    /// The Helper forwarded the request to the upstream client's queue. This
    /// is not DriverKit delivery or target-IME acknowledgement.
    case queued
    /// The Helper confirms it rejected the request before queueing it.
    case rejected
    /// The caller cannot establish whether the request reached the queue.
    case outcomeUnknown
}

struct VoiceShortcutHIDProviderReply: Equatable {
    let connectionGeneration: UInt64
    let requestSequence: UInt64
    let outcome: VoiceShortcutHIDSubmissionOutcome
}

/// A provider must preserve request ordering for one connection generation.
/// `queued` means only that `async_post_report` was invoked by the upstream
/// client; it never claims an OS, DriverKit, or input-method acknowledgement.
protocol VoiceShortcutHIDReportProvider: AnyObject {
    var state: VoiceShortcutHIDProviderState { get }
    func perform(_ request: VoiceShortcutHIDRequest) -> VoiceShortcutHIDProviderReply
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

/// Serializes each provider operation and retains session ownership until a
/// matching, generation-scoped neutral report is confirmed queued. It never
/// emits a global reset or clears another session's state.
final class VoiceShortcutHIDSessionOwner {
    private struct Session {
        let id: UUID
        let modifierKeyCodes: [UInt16]
        let connectionGeneration: UInt64
        var releasePending: Bool
    }

    private let provider: VoiceShortcutHIDReportProvider
    private let physicalModifierKeyCodesProvider: (() -> Set<UInt16>?)?
    private let ownerQueue = DispatchQueue(label: "com.lost0rz.RemoteOrbit.voice-shortcut-hid-owner")
    private let queueKey = DispatchSpecificKey<UUID>()
    private let queueIdentity = UUID()
    private var session: Session?
    private var sequenceGeneration: UInt64?
    private var lastRequestSequence: UInt64 = 0

    init(
        provider: VoiceShortcutHIDReportProvider,
        physicalModifierKeyCodesProvider: (() -> Set<UInt16>?)? = nil
    ) {
        self.provider = provider
        self.physicalModifierKeyCodesProvider = physicalModifierKeyCodesProvider
        ownerQueue.setSpecific(key: queueKey, value: queueIdentity)
    }

    var activeSessionID: UUID? {
        serialized { session?.id }
    }

    var hasUnresolvedOwnership: Bool {
        serialized { session != nil }
    }

    @discardableResult
    func begin(
        sessionID: UUID,
        modifierKeyCodes rawKeyCodes: [UInt16]
    ) -> VoiceShortcutHIDSessionAdmission {
        serialized {
            guard (try? VoiceShortcutStore.validate(
                binding: .modifierChord(modifierKeyCodes: rawKeyCodes)
            )) != nil,
            let report = try? VoiceShortcutHIDReportEncoder.encode(
                modifierKeyCodes: rawKeyCodes
            ) else {
                return .rejected(.invalidBinding)
            }

            let keyCodes = rawKeyCodes.sorted()
            if let current = session {
                if current.id == sessionID, current.modifierKeyCodes == keyCodes,
                   !current.releasePending {
                    guard let state = readyState(),
                          state.connectionGeneration == current.connectionGeneration,
                          state.keyboardReady else {
                        session?.releasePending = true
                        return .rejected(.ownershipUnresolved)
                    }
                    return .accepted
                }
                if current.id == sessionID, current.modifierKeyCodes != keyCodes {
                    return .rejected(.sessionBindingChanged)
                }
                if current.releasePending {
                    let releasedID = current.id
                    guard recoverPendingReleaseLocked() else {
                        return .rejected(.ownershipUnresolved)
                    }
                    if releasedID == sessionID {
                        return .rejected(.sessionAlreadyReleased)
                    }
                }
                if session != nil {
                    return .rejected(.ownerBusy)
                }
            }

            guard let state = readyState() else {
                switch provider.state {
                case .unavailable:
                    return .rejected(.providerUnavailable)
                case .ready:
                    return .rejected(.providerProtocolMismatch)
                }
            }
            guard state.keyboardReady else {
                return .rejected(.providerKeyboardNotReady)
            }
            guard let physicalKeyCodes = physicalModifierKeyCodesProvider?() else {
                return .rejected(.physicalModifierStateUnavailable)
            }

            let requestedFamilies = Set(keyCodes.compactMap(Self.modifierFamily))
            let physicalFamilies = Set(physicalKeyCodes.compactMap(Self.modifierFamily))
            guard requestedFamilies.isDisjoint(with: physicalFamilies) else {
                return .rejected(.physicalModifierConflict)
            }

            guard let sequence = nextSequence(for: state.connectionGeneration) else {
                return .rejected(.requestSequenceExhausted)
            }
            session = Session(
                id: sessionID,
                modifierKeyCodes: keyCodes,
                connectionGeneration: state.connectionGeneration,
                releasePending: false
            )
            let request = VoiceShortcutHIDRequest(
                protocolVersion: VoiceShortcutHIDProviderContract.clientProtocolVersion,
                connectionGeneration: state.connectionGeneration,
                sessionID: sessionID,
                requestSequence: sequence,
                operation: .begin,
                report: report
            )
            let reply = provider.perform(request)
            if replyMatches(reply, request: request), reply.outcome == .queued {
                return .accepted
            }
            guard replyMatches(reply, request: request), reply.outcome == .rejected else {
                session?.releasePending = true
                if recoverPendingReleaseLocked() {
                    return .rejected(.providerRejected)
                }
                return .rejected(.ownershipUnresolved)
            }
            session = nil
            return .rejected(.providerRejected)
        }
    }

    @discardableResult
    func end(sessionID: UUID) -> Bool {
        serialized {
            guard var current = session, current.id == sessionID else { return false }
            current.releasePending = true
            session = current
            return sendNeutral(for: current, operation: .release)
        }
    }

    @discardableResult
    func abort(sessionID: UUID) -> Bool {
        end(sessionID: sessionID)
    }

    @discardableResult
    func recoverPendingRelease() -> Bool {
        serialized { recoverPendingReleaseLocked() }
    }

    private func recoverPendingReleaseLocked() -> Bool {
        guard let current = session else { return true }
        guard current.releasePending else { return false }
        return sendNeutral(for: current, operation: .recover)
    }

    private func sendNeutral(for current: Session, operation: VoiceShortcutHIDOperation) -> Bool {
        guard let state = readyState() else { return false }
        guard state.connectionGeneration == current.connectionGeneration else {
            return false
        }
        guard state.keyboardReady else { return false }
        guard let sequence = nextSequence(for: current.connectionGeneration) else {
            return false
        }
        let request = VoiceShortcutHIDRequest(
            protocolVersion: VoiceShortcutHIDProviderContract.clientProtocolVersion,
            connectionGeneration: current.connectionGeneration,
            sessionID: current.id,
            requestSequence: sequence,
            operation: operation,
            report: .neutral
        )
        let reply = provider.perform(request)
        guard replyMatches(reply, request: request), reply.outcome == .queued else {
            return false
        }
        session = nil
        return true
    }

    private func readyState() -> (
        connectionGeneration: UInt64,
        keyboardReady: Bool
    )? {
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

    private func serialized<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == queueIdentity {
            return body()
        }
        return ownerQueue.sync(execute: body)
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
