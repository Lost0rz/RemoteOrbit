import CoreGraphics
import Foundation
import IOKit.hidsystem

enum VoiceShortcutEventKind: Equatable, Hashable {
    case flagsChanged
    case keyDown
    case keyUp
}

struct VoiceShortcutSyntheticEvent: Equatable {
    let kind: VoiceShortcutEventKind
    let keyCode: UInt16
    let flags: UInt64
}

protocol VoiceShortcutEventSink {
    /// `.posted` means CGEvent construction and the post call completed. It is
    /// not an OS or input-method acknowledgement.
    func post(_ event: VoiceShortcutSyntheticEvent) -> VoiceShortcutEventPostResult
}

enum VoiceShortcutEventPostResult: Equatable {
    case posted
    case eventConstructionFailed
    case postFailed
}

enum VoiceShortcutEmitterRejection: Equatable {
    case invalidBinding
    case unresolvedOwnership
    case physicalModifierConflict
    case eventConstructionFailed
    case postFailed
}

enum VoiceShortcutEmitResult: Equatable {
    case accepted
    case rejected(VoiceShortcutEmitterRejection)

    var wasAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }
}

struct CGEventVoiceShortcutSink: VoiceShortcutEventSink {
    func post(_ event: VoiceShortcutSyntheticEvent) -> VoiceShortcutEventPostResult {
        guard let cgEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(event.keyCode),
            keyDown: event.kind != .keyUp
        ) else { return .eventConstructionFailed }
        switch event.kind {
        case .flagsChanged: cgEvent.type = .flagsChanged
        case .keyDown: cgEvent.type = .keyDown
        case .keyUp: cgEvent.type = .keyUp
        }
        cgEvent.flags = CGEventFlags(rawValue: event.flags)
        cgEvent.setIntegerValueField(.eventSourceUserData, value: Key.syntheticMarker)
        cgEvent.post(tap: .cghidEventTap)
        return .posted
    }
}

enum VoiceShortcutEmitterDiagnosticKind: String, Equatable {
    case modifierDownPosted = "VOICE_SHORTCUT_MODIFIER_DOWN_POSTED"
    case primaryDownPosted = "VOICE_SHORTCUT_DOWN_POSTED"
    case beginEdgeFailed = "VOICE_SHORTCUT_BEGIN_EDGE_FAILED"
    case physicalModifierConflict = "VOICE_SHORTCUT_PHYSICAL_MODIFIER_CONFLICT"
    case primaryUpPosted = "VOICE_SHORTCUT_PRIMARY_UP_POSTED"
    case primaryUpFailed = "VOICE_SHORTCUT_PRIMARY_UP_FAILED"
    case modifierUpPosted = "VOICE_SHORTCUT_MODIFIER_UP_POSTED"
    case modifierUpFailed = "VOICE_SHORTCUT_MODIFIER_UP_FAILED"
    case physicalModifierReleaseDeferred = "VOICE_SHORTCUT_PHYSICAL_RELEASE_DEFERRED"
    case drainReleased = "VOICE_SHORTCUT_DRAIN_RELEASED"
    case drainPending = "VOICE_SHORTCUT_DRAIN_PENDING"
    case abortRequested = "VOICE_SHORTCUT_ABORT_REQUESTED"
    case abortReleased = "VOICE_SHORTCUT_ABORT_RELEASED"
    case abortPending = "VOICE_SHORTCUT_ABORT_PENDING"
    case releaseRecoveryAttempt = "VOICE_SHORTCUT_RELEASE_RECOVERY_ATTEMPT"
    case releaseRecovered = "VOICE_SHORTCUT_RELEASE_RECOVERED"
    case newSessionBlocked = "VOICE_SHORTCUT_SESSION_BLOCKED_UNRESOLVED_OWNER"
    case lateDrainCallbackIgnored = "VOICE_SHORTCUT_LATE_DRAIN_CALLBACK_IGNORED"
}

/// The diagnostic record intentionally contains only stable IDs, binding kind,
/// key codes, session ownership and outcome. It has no display name or input text.
struct VoiceShortcutEmitterDiagnostic: Equatable {
    let kind: VoiceShortcutEmitterDiagnosticKind
    let sessionID: UUID
    let relatedSessionID: UUID?
    let entryID: String
    let bindingKind: String
    let primaryKeyCode: UInt16?
    let modifierKeyCodes: [UInt16]
    let ownedModifierKeyCodes: [UInt16]
    let primaryIsDown: Bool
    let outcome: String

    var fields: [String: Any] {
        var result: [String: Any] = [
            "entry_id": entryID,
            "binding_kind": bindingKind,
            "modifier_key_codes": modifierKeyCodes.map { Int($0) },
            "owned_modifier_key_codes": ownedModifierKeyCodes.map { Int($0) },
            "primary_is_down": primaryIsDown,
            "session_ownership": primaryIsDown || !ownedModifierKeyCodes.isEmpty
                ? "owned" : "released",
            "outcome": outcome,
        ]
        if let primaryKeyCode {
            result["primary_key_code"] = Int(primaryKeyCode)
        }
        if let relatedSessionID {
            result["related_session_id"] = relatedSessionID.uuidString
        }
        return result
    }
}

/// Owns only the CGEvent edges it successfully posted for one promoted voice
/// session. Physical modifier state is read from the HID system state; a chord
/// never claims a physical modifier edge or releases a modifier held by a user.
final class VoiceShortcutEmitter {
    private struct Session {
        let entryID: String
        let bindingKind: String
        let primaryKeyCode: UInt16?
        let modifierKeyCodes: [UInt16]
        var ownedModifierKeyCodes: [UInt16] = []
        var flags: UInt64 = 0
        var primaryIsDown = false
        var releasePending = false
    }

    private enum ReleaseCause {
        case drain
        case abort
        case recovery
    }

    private let sink: VoiceShortcutEventSink
    private let physicalModifierKeyCodesProvider: () -> Set<UInt16>
    private let physicalModifierFlagsProvider: () -> UInt64
    var diagnosticSink: (VoiceShortcutEmitterDiagnostic) -> Void
    private var sessions: [UUID: Session] = [:]

    init(
        sink: VoiceShortcutEventSink = CGEventVoiceShortcutSink(),
        physicalModifierKeyCodesProvider: (() -> Set<UInt16>)? = nil,
        physicalModifierFlagsProvider: (() -> UInt64)? = nil,
        diagnosticSink: @escaping (VoiceShortcutEmitterDiagnostic) -> Void = { _ in }
    ) {
        self.sink = sink
        if let physicalModifierKeyCodesProvider {
            self.physicalModifierKeyCodesProvider = physicalModifierKeyCodesProvider
            self.physicalModifierFlagsProvider = physicalModifierFlagsProvider ?? { 0 }
        } else {
            self.physicalModifierKeyCodesProvider = Self.currentPhysicalModifierKeyCodes
            self.physicalModifierFlagsProvider =
                physicalModifierFlagsProvider ?? Self.currentPhysicalModifierFlags
        }
        self.diagnosticSink = diagnosticSink
    }

    @discardableResult
    func begin(
        sessionID: UUID,
        entryID: String = "unknown",
        binding: VoiceShortcutBinding
    ) -> VoiceShortcutEmitResult {
        guard (try? VoiceShortcutStore.validate(binding: binding)) != nil else {
            return .rejected(.invalidBinding)
        }

        let primaryKeyCode: UInt16?
        let rawModifiers: [UInt16]
        let bindingKind: String
        switch binding {
        case let .chord(primary, _, modifiers):
            primaryKeyCode = primary
            rawModifiers = modifiers
            bindingKind = "chord"
        case let .modifierChord(modifiers):
            primaryKeyCode = nil
            rawModifiers = modifiers
            bindingKind = "modifier_chord"
        case .pureModifier:
            return .rejected(.invalidBinding)
        }

        if let current = sessions[sessionID], !current.releasePending {
            return .accepted
        }

        guard recoverPendingReleases() else {
            let ownerID = sessions.keys.sorted { $0.uuidString < $1.uuidString }.first
            let owner = ownerID.flatMap { sessions[$0] }
            emit(
                .newSessionBlocked,
                sessionID: sessionID,
                relatedSessionID: ownerID,
                entryID: entryID,
                bindingKind: bindingKind,
                primaryKeyCode: primaryKeyCode,
                modifierKeyCodes: rawModifiers,
                ownedModifierKeyCodes: owner?.ownedModifierKeyCodes ?? [],
                primaryIsDown: owner?.primaryIsDown ?? false,
                outcome: "unresolved_owner"
            )
            return .rejected(.unresolvedOwnership)
        }
        guard sessions.isEmpty else {
            let ownerID = sessions.keys.sorted { $0.uuidString < $1.uuidString }.first
            let owner = ownerID.flatMap { sessions[$0] }
            emit(
                .newSessionBlocked,
                sessionID: sessionID,
                relatedSessionID: ownerID,
                entryID: entryID,
                bindingKind: bindingKind,
                primaryKeyCode: primaryKeyCode,
                modifierKeyCodes: rawModifiers,
                ownedModifierKeyCodes: owner?.ownedModifierKeyCodes ?? [],
                primaryIsDown: owner?.primaryIsDown ?? false,
                outcome: "another_session_owns_edges"
            )
            return .rejected(.unresolvedOwnership)
        }

        let modifierKeyCodes = bindingKind == "modifier_chord"
            ? rawModifiers.sorted()
            : ordered(rawModifiers)
        let physicalAtStart = physicalModifierKeyCodesProvider()
        let overlap = Set(modifierKeyCodes).intersection(physicalAtStart)
        guard overlap.isEmpty else {
            emit(
                .physicalModifierConflict,
                sessionID: sessionID,
                entryID: entryID,
                bindingKind: bindingKind,
                primaryKeyCode: primaryKeyCode,
                modifierKeyCodes: modifierKeyCodes,
                outcome: "same_side_physical_modifier_held"
            )
            return .rejected(.physicalModifierConflict)
        }

        var session = Session(
            entryID: entryID,
            bindingKind: bindingKind,
            primaryKeyCode: primaryKeyCode,
            modifierKeyCodes: modifierKeyCodes,
            flags: Self.flags(for: physicalAtStart)
        )

        for keyCode in modifierKeyCodes {
            let physicalNow = physicalModifierKeyCodesProvider()
            guard !physicalNow.contains(keyCode),
                  let mask = Self.modifierFlagMask(for: keyCode) else {
                emit(
                    .physicalModifierConflict,
                    sessionID: sessionID,
                    entryID: entryID,
                    bindingKind: bindingKind,
                    primaryKeyCode: primaryKeyCode,
                    modifierKeyCodes: modifierKeyCodes,
                    ownedModifierKeyCodes: session.ownedModifierKeyCodes,
                    outcome: "same_side_physical_modifier_started_during_begin"
                )
                _ = retainOrReleasePartial(session, sessionID: sessionID)
                return .rejected(.physicalModifierConflict)
            }
            let nextFlags = combinedFlags(
                owned: Set(session.ownedModifierKeyCodes),
                physical: physicalNow
            ) | mask
            let event = VoiceShortcutSyntheticEvent(
                kind: .flagsChanged,
                keyCode: keyCode,
                flags: nextFlags
            )
            switch sink.post(event) {
            case .posted:
                break
            case .eventConstructionFailed:
                emit(
                    .beginEdgeFailed,
                    sessionID: sessionID,
                    entryID: entryID,
                    bindingKind: bindingKind,
                    primaryKeyCode: primaryKeyCode,
                    modifierKeyCodes: modifierKeyCodes,
                    ownedModifierKeyCodes: session.ownedModifierKeyCodes,
                    outcome: "modifier_down_event_construction_failed"
                )
                _ = retainOrReleasePartial(session, sessionID: sessionID)
                return .rejected(.eventConstructionFailed)
            case .postFailed:
                emit(
                    .beginEdgeFailed,
                    sessionID: sessionID,
                    entryID: entryID,
                    bindingKind: bindingKind,
                    primaryKeyCode: primaryKeyCode,
                    modifierKeyCodes: modifierKeyCodes,
                    ownedModifierKeyCodes: session.ownedModifierKeyCodes,
                    outcome: "modifier_down_post_failed"
                )
                _ = retainOrReleasePartial(session, sessionID: sessionID)
                return .rejected(.postFailed)
            }
            session.flags = nextFlags
            session.ownedModifierKeyCodes.append(keyCode)
            sessions[sessionID] = session
            emit(.modifierDownPosted, sessionID: sessionID, session: session, outcome: "posted")
        }

        if let primaryKeyCode {
            let physicalBeforePrimary = physicalModifierKeyCodesProvider()
            let primaryConflict = Set(session.ownedModifierKeyCodes).intersection(physicalBeforePrimary)
            guard primaryConflict.isEmpty else {
                emit(
                    .physicalModifierConflict,
                    sessionID: sessionID,
                    session: session,
                    outcome: "same_side_physical_modifier_started_before_primary_down"
                )
                _ = retainOrReleasePartial(session, sessionID: sessionID)
                return .rejected(.physicalModifierConflict)
            }

            let primaryDown = VoiceShortcutSyntheticEvent(
                kind: .keyDown,
                keyCode: primaryKeyCode,
                flags: combinedFlags(
                    owned: Set(session.ownedModifierKeyCodes),
                    physical: physicalBeforePrimary
                )
            )
            switch sink.post(primaryDown) {
            case .posted:
                break
            case .eventConstructionFailed:
                emit(
                    .beginEdgeFailed,
                    sessionID: sessionID,
                    session: session,
                    outcome: "primary_down_event_construction_failed"
                )
                _ = retainOrReleasePartial(session, sessionID: sessionID)
                return .rejected(.eventConstructionFailed)
            case .postFailed:
                emit(
                    .beginEdgeFailed,
                    sessionID: sessionID,
                    session: session,
                    outcome: "primary_down_post_failed"
                )
                _ = retainOrReleasePartial(session, sessionID: sessionID)
                return .rejected(.postFailed)
            }
            session.flags = primaryDown.flags
            session.primaryIsDown = true
            sessions[sessionID] = session
            emit(.primaryDownPosted, sessionID: sessionID, session: session, outcome: "posted")
        }
        return .accepted
    }

    @discardableResult
    func end(sessionID: UUID) -> Bool {
        release(sessionID: sessionID, cause: .drain)
    }

    @discardableResult
    func abort(sessionID: UUID) -> Bool {
        guard let session = sessions[sessionID] else { return true }
        emit(.abortRequested, sessionID: sessionID, session: session, outcome: "requested")
        return release(sessionID: sessionID, cause: .abort)
    }

    /// Retries only terminal releases already marked pending. Active sessions
    /// stay owned; a caller cannot use recovery as an implicit release request.
    @discardableResult
    func recoverPendingReleases() -> Bool {
        let pendingIDs = sessions.compactMap { $0.value.releasePending ? $0.key : nil }
        for sessionID in pendingIDs {
            guard let session = sessions[sessionID] else { continue }
            emit(.releaseRecoveryAttempt, sessionID: sessionID, session: session, outcome: "retry")
            _ = release(sessionID: sessionID, cause: .recovery)
        }
        return !sessions.values.contains(where: \.releasePending)
    }

    /// Attempts bounded terminal cleanup. Failed ownership remains recorded
    /// and the false result is visible to the coordinator's diagnostics.
    @discardableResult
    func abortAll(maxAttemptsPerSession: Int = 3) -> Bool {
        for sessionID in Array(sessions.keys) {
            for _ in 0..<max(1, maxAttemptsPerSession) {
                guard sessions[sessionID] != nil else { break }
                _ = abort(sessionID: sessionID)
            }
        }
        return sessions.isEmpty
    }

    func recordLateDrainCallback(
        sessionID: UUID,
        entryID: String,
        binding: VoiceShortcutBinding
    ) {
        let bindingKind = binding.diagnosticFields["binding_kind"] as? String ?? "unknown"
        let primary = binding.diagnosticPrimaryKeyCode
        let modifiers = binding.diagnosticModifierKeyCodes
        emit(
            .lateDrainCallbackIgnored,
            sessionID: sessionID,
            entryID: entryID,
            bindingKind: bindingKind,
            primaryKeyCode: primary,
            modifierKeyCodes: modifiers,
            outcome: "stale_callback_ignored"
        )
    }

    var ownedSessionIDs: Set<UUID> { Set(sessions.keys) }
    var hasUnresolvedOwnership: Bool { !sessions.isEmpty }
    var hasPendingReleaseOwnership: Bool { sessions.values.contains(where: \.releasePending) }

    private func release(sessionID: UUID, cause: ReleaseCause) -> Bool {
        guard var session = sessions[sessionID] else {
            if case .drain = cause {
                emit(
                    .lateDrainCallbackIgnored,
                    sessionID: sessionID,
                    entryID: "unknown",
                    bindingKind: "unknown",
                    modifierKeyCodes: [],
                    outcome: "no_owner"
                )
            }
            return false
        }

        let wasPending = session.releasePending
        if session.primaryIsDown, let primaryKeyCode = session.primaryKeyCode {
            let physicalNow = physicalModifierKeyCodesProvider()
            let event = VoiceShortcutSyntheticEvent(
                kind: .keyUp,
                keyCode: primaryKeyCode,
                flags: combinedFlags(
                    owned: Set(session.ownedModifierKeyCodes),
                    physical: physicalNow
                )
            )
            switch sink.post(event) {
            case .posted:
                break
            case .eventConstructionFailed:
                session.releasePending = true
                sessions[sessionID] = session
                emit(.primaryUpFailed, sessionID: sessionID, session: session,
                     outcome: "primary_up_event_construction_failed")
                emitPending(sessionID: sessionID, session: session, cause: cause)
                return false
            case .postFailed:
                session.releasePending = true
                sessions[sessionID] = session
                emit(.primaryUpFailed, sessionID: sessionID, session: session,
                     outcome: "primary_up_post_failed")
                emitPending(sessionID: sessionID, session: session, cause: cause)
                return false
            }
            session.primaryIsDown = false
            session.flags = event.flags
            emit(.primaryUpPosted, sessionID: sessionID, session: session, outcome: "posted")
        }

        releaseModifiers(&session, sessionID: sessionID)
        guard !session.primaryIsDown, session.ownedModifierKeyCodes.isEmpty else {
            session.releasePending = true
            sessions[sessionID] = session
            emitPending(sessionID: sessionID, session: session, cause: cause)
            return false
        }

        sessions.removeValue(forKey: sessionID)
        switch cause {
        case .drain:
            emit(.drainReleased, sessionID: sessionID, session: session, outcome: "released")
        case .abort:
            emit(.abortReleased, sessionID: sessionID, session: session, outcome: "released")
        case .recovery:
            emit(
                wasPending ? .releaseRecovered : .drainReleased,
                sessionID: sessionID,
                session: session,
                outcome: wasPending ? "previous_owner_released" : "released"
            )
        }
        return true
    }

    private func releaseModifiers(_ session: inout Session, sessionID: UUID) {
        for keyCode in Array(session.ownedModifierKeyCodes.reversed()) {
            let physicalNow = physicalModifierKeyCodesProvider()
            guard !physicalNow.contains(keyCode) else {
                emit(.physicalModifierReleaseDeferred, sessionID: sessionID, session: session,
                     outcome: "physical_modifier_same_side_still_held")
                continue
            }
            guard Self.modifierFlagMask(for: keyCode) != nil else { continue }
            let remaining = session.ownedModifierKeyCodes.filter { $0 != keyCode }
            let nextFlags = combinedFlags(owned: Set(remaining), physical: physicalNow)
            let event = VoiceShortcutSyntheticEvent(
                kind: .flagsChanged,
                keyCode: keyCode,
                flags: nextFlags
            )
            switch sink.post(event) {
            case .posted:
                break
            case .eventConstructionFailed:
                emit(.modifierUpFailed, sessionID: sessionID, session: session,
                     outcome: "modifier_up_event_construction_failed")
                continue
            case .postFailed:
                emit(.modifierUpFailed, sessionID: sessionID, session: session,
                     outcome: "modifier_up_post_failed")
                continue
            }
            session.flags = nextFlags
            session.ownedModifierKeyCodes.removeAll { $0 == keyCode }
            emit(.modifierUpPosted, sessionID: sessionID, session: session, outcome: "posted")
        }
    }

    private func retainOrReleasePartial(_ session: Session, sessionID: UUID) -> Bool {
        guard session.primaryIsDown || !session.ownedModifierKeyCodes.isEmpty else { return true }
        sessions[sessionID] = session
        let released = release(sessionID: sessionID, cause: .abort)
        return released
    }

    private func emitPending(sessionID: UUID, session: Session, cause: ReleaseCause) {
        let (kind, outcome): (VoiceShortcutEmitterDiagnosticKind, String)
        switch cause {
        case .drain: (kind, outcome) = (.drainPending, "release_owner_retained")
        case .abort: (kind, outcome) = (.abortPending, "release_owner_retained")
        case .recovery: (kind, outcome) = (.drainPending, "recovery_still_pending")
        }
        emit(kind, sessionID: sessionID, session: session, outcome: outcome)
    }

    private func emit(
        _ kind: VoiceShortcutEmitterDiagnosticKind,
        sessionID: UUID,
        relatedSessionID: UUID? = nil,
        entryID: String,
        bindingKind: String = "chord",
        primaryKeyCode: UInt16? = nil,
        modifierKeyCodes: [UInt16],
        ownedModifierKeyCodes: [UInt16] = [],
        primaryIsDown: Bool = false,
        outcome: String
    ) {
        diagnosticSink(VoiceShortcutEmitterDiagnostic(
            kind: kind,
            sessionID: sessionID,
            relatedSessionID: relatedSessionID,
            entryID: entryID,
            bindingKind: bindingKind,
            primaryKeyCode: primaryKeyCode,
            modifierKeyCodes: modifierKeyCodes,
            ownedModifierKeyCodes: ownedModifierKeyCodes,
            primaryIsDown: primaryIsDown,
            outcome: outcome
        ))
    }

    private func emit(
        _ kind: VoiceShortcutEmitterDiagnosticKind,
        sessionID: UUID,
        relatedSessionID: UUID? = nil,
        session: Session,
        outcome: String
    ) {
        emit(
            kind,
            sessionID: sessionID,
            relatedSessionID: relatedSessionID,
            entryID: session.entryID,
            bindingKind: session.bindingKind,
            primaryKeyCode: session.primaryKeyCode,
            modifierKeyCodes: session.modifierKeyCodes,
            ownedModifierKeyCodes: session.ownedModifierKeyCodes,
            primaryIsDown: session.primaryIsDown,
            outcome: outcome
        )
    }

    private func ordered(_ keyCodes: [UInt16]) -> [UInt16] {
        let order: [UInt16] = [59, 62, 58, 61, 56, 60, 55, 54]
        let set = Set(keyCodes)
        return order.filter { set.contains($0) }
    }

    private func combinedFlags(owned: Set<UInt16>, physical: Set<UInt16>) -> UInt64 {
        let physicalModifierFlags = physicalModifierFlagsProvider() & Self.physicalModifierFlagMask
        return Self.flags(for: owned.union(physical)) | physicalModifierFlags
    }

    private static let physicalModifierFlagMask: UInt64 =
        CGEventFlags.maskAlphaShift.rawValue
        | CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskHelp.rawValue
        | CGEventFlags.maskSecondaryFn.rawValue

    private static func currentPhysicalModifierFlags() -> UInt64 {
        CGEventSource.flagsState(.hidSystemState).rawValue & physicalModifierFlagMask
    }

    private static func currentPhysicalModifierKeyCodes() -> Set<UInt16> {
        let flags = CGEventSource.flagsState(.hidSystemState).rawValue
        var keyCodes = modifierMasks.compactMap { keyCode, mask in
            flags & mask == 0 ? nil : keyCode
        }.reduce(into: Set<UInt16>()) { $0.insert($1) }
        let ambiguousFamilies: [(UInt64, UInt16, UInt16)] = [
            (CGEventFlags.maskCommand.rawValue, 55, 54),
            (CGEventFlags.maskControl.rawValue, 59, 62),
            (CGEventFlags.maskAlternate.rawValue, 58, 61),
            (CGEventFlags.maskShift.rawValue, 56, 60),
        ]
        for (familyMask, left, right) in ambiguousFamilies
        where flags & familyMask != 0 && !keyCodes.contains(left) && !keyCodes.contains(right) {
            // If HID state reports only an aggregate family flag, treat either
            // side as occupied. This is conservative and cannot steal a real edge.
            keyCodes.insert(left)
            keyCodes.insert(right)
        }
        return keyCodes
    }

    private static let modifierMasks: [(UInt16, UInt64)] = [
        (55, UInt64(NX_DEVICELCMDKEYMASK)), (54, UInt64(NX_DEVICERCMDKEYMASK)),
        (59, UInt64(NX_DEVICELCTLKEYMASK)), (62, UInt64(NX_DEVICERCTLKEYMASK)),
        (58, UInt64(NX_DEVICELALTKEYMASK)), (61, UInt64(NX_DEVICERALTKEYMASK)),
        (56, UInt64(NX_DEVICELSHIFTKEYMASK)), (60, UInt64(NX_DEVICERSHIFTKEYMASK)),
    ]

    private static func flags(for keyCodes: Set<UInt16>) -> UInt64 {
        keyCodes.reduce(into: UInt64(0)) { result, keyCode in
            result |= modifierFlagMask(for: keyCode) ?? 0
        }
    }

    private static func modifierFlagMask(for keyCode: UInt16) -> UInt64? {
        switch keyCode {
        case 55: return UInt64(NX_DEVICELCMDKEYMASK) | CGEventFlags.maskCommand.rawValue
        case 54: return UInt64(NX_DEVICERCMDKEYMASK) | CGEventFlags.maskCommand.rawValue
        case 59: return UInt64(NX_DEVICELCTLKEYMASK) | CGEventFlags.maskControl.rawValue
        case 62: return UInt64(NX_DEVICERCTLKEYMASK) | CGEventFlags.maskControl.rawValue
        case 58: return UInt64(NX_DEVICELALTKEYMASK) | CGEventFlags.maskAlternate.rawValue
        case 61: return UInt64(NX_DEVICERALTKEYMASK) | CGEventFlags.maskAlternate.rawValue
        case 56: return UInt64(NX_DEVICELSHIFTKEYMASK) | CGEventFlags.maskShift.rawValue
        case 60: return UInt64(NX_DEVICERSHIFTKEYMASK) | CGEventFlags.maskShift.rawValue
        default: return nil
        }
    }
}
