// ShortcutCaptureMonitor.swift — exclusive physical shortcut recording
//
// The recorder owns the complete physical gesture at the HID event boundary.
// It deliberately remains separate from EventSuppressor, which owns remote
// button/native-event suppression.

import AppKit
import CoreGraphics
import Foundation

enum ShortcutCapturePhase: Equatable {
    case waitingForNeutral
    case armed
    case chordFrozen
    case drainingRelease
    case inactive
}

enum ShortcutCaptureInput: Equatable {
    case keyDown(
        keyCode: UInt16,
        keyLabel: String,
        modifiers: KeyChord.Modifiers,
        isRepeat: Bool
    )
    case keyUp(keyCode: UInt16)
    case flagsChanged(
        keyCode: UInt16,
        modifier: KeyChord.Modifiers,
        label: String,
        isDown: Bool
    )
    case synthetic
}

struct ShortcutCaptureDecision: Equatable {
    let shouldSuppress: Bool
    let preview: KeyChord?
    let committed: KeyChord?
    let didStop: Bool
    let phase: ShortcutCapturePhase
}

struct ShortcutCaptureStateMachine {
    private(set) var phase: ShortcutCapturePhase

    private var waitingModifiers: KeyChord.Modifiers
    private var waitingForFn: Bool
    private var ownedModifierKeyCodes = Set<UInt16>()
    private var ownedAdditionalKeyCodes = Set<UInt16>()
    private var primaryKeyCode: UInt16?
    private var primaryKeyReleased = false
    private var frozenChord: KeyChord?
    private var pureModifierKeyCode: UInt16?
    private var pureModifierLabel: String?
    private var cancellationRequested = false

    init(
        initiallyHeldModifiers: KeyChord.Modifiers = [],
        initiallyHoldingFn: Bool = false
    ) {
        waitingModifiers = initiallyHeldModifiers
        waitingForFn = initiallyHoldingFn
        phase = initiallyHeldModifiers.isEmpty && !initiallyHoldingFn
            ? .armed
            : .waitingForNeutral
    }

    mutating func reset(
        initiallyHeldModifiers: KeyChord.Modifiers = [],
        initiallyHoldingFn: Bool = false
    ) {
        self = Self(
            initiallyHeldModifiers: initiallyHeldModifiers,
            initiallyHoldingFn: initiallyHoldingFn
        )
    }

    mutating func handle(_ input: ShortcutCaptureInput) -> ShortcutCaptureDecision {
        guard phase != .inactive else {
            return decision()
        }

        if case .synthetic = input {
            return decision()
        }

        switch phase {
        case .waitingForNeutral:
            return handleWaitingForNeutral(input)
        case .armed:
            return handleArmed(input)
        case .chordFrozen, .drainingRelease:
            return handleOwnedGesture(input)
        case .inactive:
            return decision()
        }
    }

    mutating func requestCancel() -> ShortcutCaptureDecision {
        guard phase != .inactive else {
            return decision(didStop: true)
        }

        guard hasOwnedGesture else {
            phase = .inactive
            return decision(didStop: true)
        }

        cancellationRequested = true
        phase = .drainingRelease
        return decision()
    }

    mutating func abandon() {
        phase = .inactive
        ownedModifierKeyCodes.removeAll()
        ownedAdditionalKeyCodes.removeAll()
        primaryKeyCode = nil
        frozenChord = nil
        pureModifierKeyCode = nil
        pureModifierLabel = nil
        cancellationRequested = true
    }

    private var hasOwnedGesture: Bool {
        primaryKeyCode != nil ||
            !ownedModifierKeyCodes.isEmpty ||
            !ownedAdditionalKeyCodes.isEmpty
    }

    private mutating func handleWaitingForNeutral(
        _ input: ShortcutCaptureInput
    ) -> ShortcutCaptureDecision {
        guard case let .flagsChanged(keyCode, modifier, _, isDown) = input else {
            return decision()
        }

        if isDown {
            waitingModifiers.formUnion(modifier)
            if keyCode == 63 { waitingForFn = true }
        } else {
            waitingModifiers.subtract(modifier)
            if keyCode == 63 { waitingForFn = false }
        }

        if waitingModifiers.isEmpty && !waitingForFn {
            phase = .armed
        }
        // The pre-existing modifier down already reached macOS before the tap
        // was installed, so its balancing release must pass through too.
        return decision()
    }

    private mutating func handleArmed(
        _ input: ShortcutCaptureInput
    ) -> ShortcutCaptureDecision {
        switch input {
        case let .flagsChanged(keyCode, _, label, isDown):
            if isDown {
                ownedModifierKeyCodes.insert(keyCode)
                if primaryKeyCode == nil, pureModifierKeyCode == nil {
                    pureModifierKeyCode = keyCode
                    pureModifierLabel = label
                }
                return decision(shouldSuppress: true)
            }

            guard ownedModifierKeyCodes.remove(keyCode) != nil else {
                return decision()
            }
            if primaryKeyCode == nil, ownedModifierKeyCodes.isEmpty {
                return commitPureModifier()
            }
            return decision(shouldSuppress: true)

        case let .keyDown(keyCode, keyLabel, modifiers, isRepeat):
            guard !isRepeat else {
                return decision(shouldSuppress: false)
            }

            var chordModifiers = modifiers
            chordModifiers.formUnion(modifiersForOwnedModifierKeys)
            let chord = KeyChord(
                keyCode: keyCode,
                keyLabel: keyLabel,
                modifiers: chordModifiers
            )
            frozenChord = chord
            primaryKeyCode = keyCode
            primaryKeyReleased = false
            pureModifierKeyCode = nil
            pureModifierLabel = nil
            phase = .chordFrozen
            return decision(shouldSuppress: true, preview: chord)

        case .keyUp, .synthetic:
            return decision()
        }
    }

    private mutating func handleOwnedGesture(
        _ input: ShortcutCaptureInput
    ) -> ShortcutCaptureDecision {
        switch input {
        case let .flagsChanged(keyCode, _, _, isDown):
            if isDown {
                ownedModifierKeyCodes.insert(keyCode)
                return decision(shouldSuppress: true)
            }

            guard ownedModifierKeyCodes.remove(keyCode) != nil else {
                return decision()
            }
            if primaryKeyCode == nil, ownedModifierKeyCodes.isEmpty {
                if cancellationRequested {
                    phase = .inactive
                    return decision(shouldSuppress: true, didStop: true)
                }
                return commitPureModifier()
            }
            return finishIfReady(shouldSuppress: true)

        case let .keyDown(keyCode, _, _, _):
            if keyCode != primaryKeyCode {
                ownedAdditionalKeyCodes.insert(keyCode)
            }
            return decision(shouldSuppress: true)

        case let .keyUp(keyCode):
            if keyCode == primaryKeyCode {
                primaryKeyReleased = true
                return finishIfReady(shouldSuppress: true)
            }
            guard ownedAdditionalKeyCodes.remove(keyCode) != nil else {
                return decision()
            }
            return finishIfReady(shouldSuppress: true)

        case .synthetic:
            return decision()
        }
    }

    private var modifiersForOwnedModifierKeys: KeyChord.Modifiers {
        ownedModifierKeyCodes.reduce(into: KeyChord.Modifiers()) { result, keyCode in
            result.formUnion(Self.modifierForKeyCode(keyCode))
        }
    }

    private mutating func commitPureModifier() -> ShortcutCaptureDecision {
        guard
            let keyCode = pureModifierKeyCode,
            let label = pureModifierLabel
        else {
            phase = .inactive
            return decision(didStop: true)
        }

        phase = .inactive
        return decision(
            shouldSuppress: true,
            committed: KeyChord(keyCode: keyCode, keyLabel: label, modifiers: []),
            didStop: true
        )
    }

    private mutating func finishIfReady(
        shouldSuppress: Bool
    ) -> ShortcutCaptureDecision {
        guard primaryKeyReleased,
              ownedModifierKeyCodes.isEmpty,
              ownedAdditionalKeyCodes.isEmpty
        else {
            if primaryKeyReleased { phase = .drainingRelease }
            return decision(shouldSuppress: shouldSuppress)
        }

        phase = .inactive
        if cancellationRequested {
            return decision(shouldSuppress: shouldSuppress, didStop: true)
        }
        return decision(
            shouldSuppress: shouldSuppress,
            committed: frozenChord,
            didStop: true
        )
    }

    private func decision(
        shouldSuppress: Bool = false,
        preview: KeyChord? = nil,
        committed: KeyChord? = nil,
        didStop: Bool = false
    ) -> ShortcutCaptureDecision {
        ShortcutCaptureDecision(
            shouldSuppress: shouldSuppress,
            preview: preview,
            committed: committed,
            didStop: didStop,
            phase: phase
        )
    }

    static func modifierForKeyCode(_ keyCode: UInt16) -> KeyChord.Modifiers {
        switch keyCode {
        case 54, 55: return .command
        case 59, 62: return .control
        case 58, 61: return .option
        case 56, 60: return .shift
        default: return []
        }
    }
}

private func shortcutCaptureMonitorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<ShortcutCaptureMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}

enum ShortcutCaptureMonitorError: LocalizedError {
    case eventTapUnavailable
    case eventTapDisabled

    var errorDescription: String? {
        switch self {
        case .eventTapUnavailable:
            return "无法安装系统级快捷键捕获，请检查输入监控权限。"
        case .eventTapDisabled:
            return "系统级快捷键捕获已被 macOS 停用，本次录制已取消。"
        }
    }
}

final class ShortcutCaptureMonitor {
    typealias TriggerModeProvider = () -> ShortcutTriggerMode

    var onPreview: (String) -> Void = { _ in }
    var onRecord: (KeyChord, ShortcutTriggerMode) -> Void = { _, _ in }
    var onError: (String) -> Void = { _ in }
    var onStopped: () -> Void = {}

    private let triggerModeProvider: TriggerModeProvider
    private let initialFlags: CGEventFlags
    private var stateMachine: ShortcutCaptureStateMachine
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var drainRetain: ShortcutCaptureMonitor?
    private(set) var isRunning = false

    init(
        initiallyHeldFlags: CGEventFlags = [],
        triggerModeProvider: @escaping TriggerModeProvider
    ) {
        initialFlags = initiallyHeldFlags
        self.triggerModeProvider = triggerModeProvider
        stateMachine = ShortcutCaptureStateMachine(
            initiallyHeldModifiers: Self.modifiers(from: initiallyHeldFlags),
            initiallyHoldingFn: initiallyHeldFlags.contains(.maskSecondaryFn)
        )
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        stateMachine.reset(
            initiallyHeldModifiers: Self.modifiers(from: initialFlags),
            initiallyHoldingFn: initialFlags.contains(.maskSecondaryFn)
        )
        if stateMachine.phase == .waitingForNeutral {
            onPreview("请先松开当前按键")
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: shortcutCaptureMonitorCallback,
            userInfo: context
        ) else {
            report(.eventTapUnavailable)
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            report(.eventTapUnavailable)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        return true
    }

    /// Requests termination. Returns true when there was no owned gesture to
    /// drain and the caller may dismiss immediately.
    @discardableResult
    func requestCancel() -> Bool {
        let decision = stateMachine.requestCancel()
        if decision.didStop {
            stopInternal(notify: true)
            return true
        }
        drainRetain = self
        return false
    }

    /// Called by the sheet after it disappears without an owned gesture.
    /// An active gesture is converted into a drain request instead of tearing
    /// down the tap and leaking its release edges.
    @discardableResult
    func stop() -> Bool {
        if isRunning, !requestCancelIfNeeded() {
            drainRetain = self
            return false
        }
        stopInternal(notify: false)
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            report(.eventTapDisabled)
            return Unmanaged.passUnretained(event)
        }

        guard let input = Self.input(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        let decision = stateMachine.handle(input)
        if decision.preview == nil, decision.committed == nil, !decision.didStop {
            return decision.shouldSuppress ? nil : Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if decision.didStop {
                self.stopInternal(notify: false)
            }
            if let preview = decision.preview {
                self.onPreview(preview.displayName)
            }
            if let committed = decision.committed {
                self.onRecord(committed, self.triggerModeProvider())
            }
            if decision.didStop {
                self.onStopped()
            }
        }
        return decision.shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

    deinit {
        stopInternal(notify: false)
    }

    private func requestCancelIfNeeded() -> Bool {
        guard stateMachine.phase != .inactive else { return true }
        return requestCancel()
    }

    private func stopInternal(notify: Bool) {
        let wasActive = isRunning || eventTap != nil || runLoopSource != nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
        drainRetain = nil
        if notify, wasActive { onStopped() }
    }

    private func report(_ error: ShortcutCaptureMonitorError) {
        stateMachine.abandon()
        let report = { [weak self] in
            guard let self else { return }
            self.onError(error.localizedDescription)
            self.stopInternal(notify: true)
        }
        if Thread.isMainThread { report() }
        else { DispatchQueue.main.async(execute: report) }
    }

    private static func input(
        type: CGEventType,
        event: CGEvent
    ) -> ShortcutCaptureInput? {
        if event.getIntegerValueField(.eventSourceUserData) == KeyInjector.syntheticMarker {
            return .synthetic
        }

        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard let label = KeyChord.keyLabel(for: event) else { return nil }
            return .keyDown(
                keyCode: keyCode,
                keyLabel: label,
                modifiers: modifiers(from: event.flags),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case .keyUp:
            return .keyUp(
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            )
        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard let info = modifierInfo(for: keyCode) else { return nil }
            return .flagsChanged(
                keyCode: keyCode,
                modifier: info.modifier,
                label: info.label,
                isDown: event.flags.contains(info.mask)
            )
        default:
            return nil
        }
    }

    private static func modifiers(from flags: CGEventFlags) -> KeyChord.Modifiers {
        var modifiers: KeyChord.Modifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }

    private static func modifierInfo(
        for keyCode: UInt16
    ) -> (modifier: KeyChord.Modifiers, label: String, mask: CGEventFlags)? {
        switch keyCode {
        case 54, 55: return (.command, "⌘", .maskCommand)
        case 59, 62: return (.control, "⌃", .maskControl)
        case 58, 61: return (.option, "⌥", .maskAlternate)
        case 56, 60: return (.shift, "⇧", .maskShift)
        case 63: return ([], "Fn", .maskSecondaryFn)
        default: return nil
        }
    }
}

extension KeyChord {
    static func keyLabel(for event: CGEvent) -> String? {
        let fixed: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete",
            119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20", 63: "Fn", 54: "⌘", 55: "⌘", 59: "⌃", 62: "⌃",
            58: "⌥", 61: "⌥", 56: "⇧", 60: "⇧"
        ]
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if let label = fixed[keyCode] { return label }
        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
              characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar)
        else {
            return nil
        }
        return characters.uppercased()
    }
}
