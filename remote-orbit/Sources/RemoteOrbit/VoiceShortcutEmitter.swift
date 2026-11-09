import CoreGraphics
import Foundation
import IOKit.hidsystem

enum VoiceShortcutEventKind: Equatable {
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
    func post(_ event: VoiceShortcutSyntheticEvent) -> Bool
}

struct CGEventVoiceShortcutSink: VoiceShortcutEventSink {
    func post(_ event: VoiceShortcutSyntheticEvent) -> Bool {
        guard let cgEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(event.keyCode),
            keyDown: event.kind != .keyUp
        ) else { return false }
        switch event.kind {
        case .flagsChanged: cgEvent.type = .flagsChanged
        case .keyDown: cgEvent.type = .keyDown
        case .keyUp: cgEvent.type = .keyUp
        }
        cgEvent.flags = CGEventFlags(rawValue: event.flags)
        cgEvent.setIntegerValueField(.eventSourceUserData, value: Key.syntheticMarker)
        cgEvent.post(tap: .cghidEventTap)
        return true
    }
}

/// Owns only the CGEvent edges it successfully posted for one promoted voice
/// session. Posting is not an acknowledgement from the selected IME.
final class VoiceShortcutEmitter {
    static let shared = VoiceShortcutEmitter()
    private struct Session {
        let primaryKeyCode: UInt16
        var modifierKeyCodes: [UInt16]
        var flags: UInt64
        var primaryIsDown: Bool
    }

    private let sink: VoiceShortcutEventSink
    private var sessions: [UUID: Session] = [:]

    init(sink: VoiceShortcutEventSink = CGEventVoiceShortcutSink()) {
        self.sink = sink
    }

    @discardableResult
    func begin(sessionID: UUID, binding: VoiceShortcutBinding) -> Bool {
        guard (try? VoiceShortcutStore.validate(binding: binding)) != nil else { return false }
        guard case let .chord(primaryKeyCode, _, rawModifiers) = binding else {
            return false
        }
        guard sessions[sessionID] == nil else { return true }
        let modifierKeyCodes = ordered(rawModifiers)
        var session = Session(
            primaryKeyCode: primaryKeyCode,
            modifierKeyCodes: [],
            flags: 0,
            primaryIsDown: false
        )
        for keyCode in modifierKeyCodes {
            guard let mask = Self.modifierFlagMask(for: keyCode) else {
                releaseModifiers(&session)
                retainIfStillOwned(session, sessionID: sessionID)
                return false
            }
            let nextFlags = session.flags | mask
            let event = VoiceShortcutSyntheticEvent(
                kind: .flagsChanged,
                keyCode: keyCode,
                flags: nextFlags
            )
            guard sink.post(event) else {
                releaseModifiers(&session)
                retainIfStillOwned(session, sessionID: sessionID)
                return false
            }
            session.flags = nextFlags
            session.modifierKeyCodes.append(keyCode)
        }

        let primaryDown = VoiceShortcutSyntheticEvent(
            kind: .keyDown,
            keyCode: primaryKeyCode,
            flags: session.flags
        )
        guard sink.post(primaryDown) else {
            releaseModifiers(&session)
            retainIfStillOwned(session, sessionID: sessionID)
            return false
        }
        session.primaryIsDown = true
        sessions[sessionID] = session
        return true
    }

    @discardableResult
    func end(sessionID: UUID) -> Bool {
        guard var session = sessions[sessionID] else { return false }
        if session.primaryIsDown {
            let event = VoiceShortcutSyntheticEvent(
                kind: .keyUp,
                keyCode: session.primaryKeyCode,
                flags: session.flags
            )
            guard sink.post(event) else {
                sessions[sessionID] = session
                return false
            }
            session.primaryIsDown = false
        }
        releaseModifiers(&session)
        if session.primaryIsDown || !session.modifierKeyCodes.isEmpty {
            sessions[sessionID] = session
            return false
        }
        sessions.removeValue(forKey: sessionID)
        return true
    }

    @discardableResult
    func abort(sessionID: UUID) -> Bool {
        end(sessionID: sessionID)
    }

    func abortAll() {
        for id in Array(sessions.keys) {
            _ = end(sessionID: id)
            _ = end(sessionID: id)
        }
    }

    var ownedSessionIDs: Set<UUID> { Set(sessions.keys) }

    private func releaseModifiers(_ session: inout Session) {
        for keyCode in Array(session.modifierKeyCodes.reversed()) {
            guard Self.modifierFlagMask(for: keyCode) != nil else { continue }
            let remaining = session.modifierKeyCodes.filter { $0 != keyCode }
            let nextFlags = Self.flags(for: remaining)
            let event = VoiceShortcutSyntheticEvent(
                kind: .flagsChanged,
                keyCode: keyCode,
                flags: nextFlags
            )
            guard sink.post(event) else { continue }
            session.flags = nextFlags
            session.modifierKeyCodes.removeAll { $0 == keyCode }
        }
    }

    private func retainIfStillOwned(_ session: Session, sessionID: UUID) {
        if session.primaryIsDown || !session.modifierKeyCodes.isEmpty {
            sessions[sessionID] = session
        }
    }

    private func ordered(_ keyCodes: [UInt16]) -> [UInt16] {
        let order: [UInt16] = [59, 62, 58, 61, 56, 60, 55, 54]
        let set = Set(keyCodes)
        return order.filter { set.contains($0) }
    }

    private static func flags(for keyCodes: [UInt16]) -> UInt64 {
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
