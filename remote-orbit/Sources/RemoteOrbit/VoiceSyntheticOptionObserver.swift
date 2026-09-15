import AppKit
import CoreGraphics
import Foundation

struct VoiceSyntheticOptionClassification: Equatable {
    let direction: VoiceOptionDirection
    let component: VoiceOptionComponent
}

/// A listen-only observer for the two CGEvents making up one synthetic
/// fallback Option edge. It never suppresses, rewrites, or triggers voice
/// lifecycle; hardware-primary sessions are intentionally excluded from its
/// correlation path by `VoiceSessionDiagnostics`.
final class VoiceSyntheticOptionObserver {
    typealias Handler = (
        _ direction: VoiceOptionDirection,
        _ component: VoiceOptionComponent,
        _ uptime: TimeInterval
    ) -> Void

    private(set) var isAvailable = false
    private let handler: Handler
    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?

    init(handler: @escaping Handler = { direction, component, uptime in
        _ = VoiceSessionDiagnostics.shared.observeSyntheticOption(
            direction: direction,
            component: component,
            uptime: uptime
        )
    }) {
        self.handler = handler
    }

    /// Pure classifier seam used by tests and by the tap callback.
    static func classify(
        userData: Int64,
        keyCode: CGKeyCode,
        type: CGEventType,
        flags: CGEventFlags
    ) -> VoiceSyntheticOptionClassification? {
        guard userData == Key.syntheticMarker, keyCode == VK.option else {
            return nil
        }
        switch type {
        case .flagsChanged:
            return VoiceSyntheticOptionClassification(
                direction: flags.contains(.maskAlternate) ? .down : .up,
                component: .flags
            )
        case .keyDown:
            return VoiceSyntheticOptionClassification(direction: .down, component: .key)
        case .keyUp:
            return VoiceSyntheticOptionClassification(direction: .up, component: .key)
        default:
            return nil
        }
    }

    @discardableResult
    func start() -> Bool {
        guard tapPort == nil else { return isAvailable }
        let events: CGEventMask =
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: events,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let observer = Unmanaged<VoiceSyntheticOptionObserver>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                observer.handle(type: type, event: event)
                // Listen-only means this event must pass through untouched.
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isAvailable = false
            return false
        }

        tapPort = port
        tapSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            port,
            0
        )
        if let tapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        CGEvent.tapEnable(tap: port, enable: true)
        isAvailable = true
        return true
    }

    func stop() {
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
        }
        tapSource = nil
        tapPort = nil
        isAvailable = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let userData = event.getIntegerValueField(.eventSourceUserData)
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let classification = Self.classify(
            userData: userData,
            keyCode: keyCode,
            type: type,
            flags: event.flags
        ) else { return }
        handler(
            classification.direction,
            classification.component,
            ProcessInfo.processInfo.systemUptime
        )
    }

    deinit {
        stop()
    }
}
