import Foundation

/// USB HID keyboard modifier bits used by the virtual keyboard report. The
/// values are pinned to Karabiner-DriverKit-VirtualHIDDevice v8.0.0, whose
/// `hid_report::modifier` enum assigns E0-E7 to bits 0-7.
enum VoiceShortcutHIDProviderContract {
    static let packageVersion = "8.0.0"
    static let clientProtocolVersion = 7
    static let sourceCommit = "ba649ef9cbbdc453cc384838496ef03eab3e3c87"
    static let sourceURL = "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/v8.0.0"
}

struct VoiceShortcutHIDModifierReport: Equatable {
    let modifierBitmap: UInt8

    static let neutral = VoiceShortcutHIDModifierReport(modifierBitmap: 0)
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
    case ready(packageVersion: String, clientProtocolVersion: Int)
}

enum VoiceShortcutHIDReportSubmission: Equatable {
    /// The provider accepted this report for the named session.
    case accepted
    /// The provider confirms it did not accept this report.
    case rejected
    /// The provider cannot determine whether the report was accepted.
    case outcomeUnknown
}

/// Narrow provider surface: one modifier bitmap tied to one immutable session.
/// It cannot submit ordinary key usages or arbitrary keyboard reports.
protocol VoiceShortcutHIDReportProvider: AnyObject {
    var state: VoiceShortcutHIDProviderState { get }
    func submit(
        _ report: VoiceShortcutHIDModifierReport,
        sessionID: UUID
    ) -> VoiceShortcutHIDReportSubmission
}

enum VoiceShortcutHIDSessionError: Equatable {
    case invalidBinding
    case providerUnavailable
    case providerProtocolMismatch
    case physicalModifierConflict
    case ownerBusy
    case sessionBindingChanged
    case sessionAlreadyReleased
    case providerRejected
    case ownershipUnresolved
}

enum VoiceShortcutHIDSessionAdmission: Equatable {
    case accepted
    case rejected(VoiceShortcutHIDSessionError)
}

/// Owns the virtual keyboard's modifier state for one voice session at a time.
/// A failed or ambiguous neutral report keeps ownership and therefore keeps
/// later sessions Busy until recovery succeeds.
final class VoiceShortcutHIDSessionOwner {
    private struct Session {
        let id: UUID
        let modifierKeyCodes: [UInt16]
        var releasePending: Bool
    }

    private let provider: VoiceShortcutHIDReportProvider
    private let physicalModifierKeyCodesProvider: () -> Set<UInt16>
    private var session: Session?

    init(
        provider: VoiceShortcutHIDReportProvider,
        physicalModifierKeyCodesProvider: @escaping () -> Set<UInt16> = { [] }
    ) {
        self.provider = provider
        self.physicalModifierKeyCodesProvider = physicalModifierKeyCodesProvider
    }

    var activeSessionID: UUID? { session?.id }
    var hasUnresolvedOwnership: Bool { session != nil }

    @discardableResult
    func begin(
        sessionID: UUID,
        modifierKeyCodes rawKeyCodes: [UInt16]
    ) -> VoiceShortcutHIDSessionAdmission {
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
                return .accepted
            }
            if current.id == sessionID, current.modifierKeyCodes != keyCodes {
                return .rejected(.sessionBindingChanged)
            }
            if current.releasePending {
                let releasedID = current.id
                guard recoverPendingRelease() else {
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

        switch provider.state {
        case .unavailable:
            return .rejected(.providerUnavailable)
        case let .ready(packageVersion, clientProtocolVersion):
            guard packageVersion == VoiceShortcutHIDProviderContract.packageVersion,
                  clientProtocolVersion == VoiceShortcutHIDProviderContract.clientProtocolVersion
            else {
                return .rejected(.providerProtocolMismatch)
            }
        }

        let requestedFamilies = Set(keyCodes.compactMap(Self.modifierFamily))
        let physicalFamilies = Set(physicalModifierKeyCodesProvider().compactMap(Self.modifierFamily))
        guard requestedFamilies.isDisjoint(with: physicalFamilies) else {
            return .rejected(.physicalModifierConflict)
        }

        // Record ownership before submission so an ambiguous provider result
        // cannot admit another session or silently lose a possibly-held report.
        session = Session(id: sessionID, modifierKeyCodes: keyCodes, releasePending: false)
        switch provider.submit(report, sessionID: sessionID) {
        case .accepted:
            return .accepted
        case .rejected:
            session = nil
            return .rejected(.providerRejected)
        case .outcomeUnknown:
            session?.releasePending = true
            guard releaseOwnedSession(sessionID: sessionID) else {
                return .rejected(.ownershipUnresolved)
            }
            return .rejected(.providerRejected)
        }
    }

    @discardableResult
    func end(sessionID: UUID) -> Bool {
        releaseOwnedSession(sessionID: sessionID)
    }

    @discardableResult
    func abort(sessionID: UUID) -> Bool {
        releaseOwnedSession(sessionID: sessionID)
    }

    @discardableResult
    func recoverPendingRelease() -> Bool {
        guard let current = session else { return true }
        guard current.releasePending else { return false }
        return releaseOwnedSession(sessionID: current.id)
    }

    private func releaseOwnedSession(sessionID: UUID) -> Bool {
        guard var current = session, current.id == sessionID else { return false }
        current.releasePending = true
        session = current

        switch provider.submit(.neutral, sessionID: sessionID) {
        case .accepted:
            session = nil
            return true
        case .rejected, .outcomeUnknown:
            return false
        }
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
