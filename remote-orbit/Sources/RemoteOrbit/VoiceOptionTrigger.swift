import Foundation

/// A process-local timeline for one voice gesture. It is diagnostic only: it
/// never gates callbacks or changes the voice state machine.
enum VoiceTimingLogger {
    private static let lock = NSLock()
    private static var activeSessionID: UUID?
    private static var startedAt: TimeInterval = 0

    static func begin(sessionID: UUID) {
        lock.lock()
        activeSessionID = sessionID
        startedAt = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        mark("VOICE_DOWN", sessionID: sessionID)
    }

    static func mark(_ event: String, sessionID: UUID? = nil) {
        lock.lock()
        guard let activeSessionID,
              sessionID == nil || sessionID == activeSessionID else {
            lock.unlock()
            return
        }
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        let shortID = String(activeSessionID.uuidString.prefix(4))
        lock.unlock()
        print(
            "[VOICE][\(shortID)][TIMING] \(event) "
                + String(format: "+%.1fms", elapsedMS)
        )
    }

    static func end(sessionID: UUID) {
        lock.lock()
        if activeSessionID == sessionID {
            activeSessionID = nil
        }
        lock.unlock()
    }
}

/// The physical HID path is the normal owner. This small state object only
/// records the captured edges so VoiceKeyFilter can choose the existing
/// hardware replay or copy-failure fallback without losing gesture identity.
enum HardwareOptionEdge: Equatable {
    case down
    case up
}

enum HardwareOptionResolution: Equatable {
    case hardwareReplay
    case syntheticTap
    case syntheticDown
    case noOptionEdge
}

final class HardwareOptionGate {
    private(set) var activeSessionID: UUID?
    private var downSeen = false
    private var upSeen = false
    private var copiedDownPresent = false

    @discardableResult
    func begin(sessionID: UUID) -> Bool {
        if let activeSessionID, activeSessionID != sessionID {
            _ = cancel(sessionID: activeSessionID)
        }
        if activeSessionID == sessionID {
            return true
        }
        activeSessionID = sessionID
        downSeen = false
        upSeen = false
        copiedDownPresent = false
        return true
    }

    @discardableResult
    func capture(_ edge: HardwareOptionEdge, copied: Bool) -> Bool {
        guard activeSessionID != nil else { return false }
        switch edge {
        case .down:
            downSeen = true
            copiedDownPresent = copiedDownPresent || copied
        case .up:
            guard downSeen else { return false }
            upSeen = true
        }
        return true
    }

    @discardableResult
    func resolve(sessionID: UUID) -> HardwareOptionResolution? {
        guard activeSessionID == sessionID else { return nil }
        let resolution: HardwareOptionResolution
        if copiedDownPresent {
            resolution = .hardwareReplay
        } else if !downSeen {
            resolution = .noOptionEdge
        } else if upSeen {
            resolution = .syntheticTap
        } else {
            resolution = .syntheticDown
        }
        clear()
        return resolution
    }

    @discardableResult
    func cancel(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        clear()
        return true
    }

    private func clear() {
        activeSessionID = nil
        downSeen = false
        upSeen = false
        copiedDownPresent = false
    }
}

/// Owns synthetic Option fallback edges for one voice gesture. In
/// particular, the delayed up from a short tap is ignored once a newer
/// session owns the trigger, so it cannot release the newer gesture.
final class VoiceOptionTrigger {
    typealias EventSink = (_ isDown: Bool) -> Void

    static let shared = VoiceOptionTrigger { isDown in
        if isDown {
            Key.optionDown()
        } else {
            Key.optionUp()
        }
    }

    private let eventSink: EventSink
    private(set) var activeSessionID: UUID?
    private(set) var isOptionDown = false

    init(eventSink: @escaping EventSink) {
        self.eventSink = eventSink
    }

    convenience init() {
        self.init { isDown in
            if isDown {
                Key.optionDown()
            } else {
                Key.optionUp()
            }
        }
    }

    @discardableResult
    func begin(sessionID: UUID) -> Bool {
        if let activeSessionID, activeSessionID != sessionID {
            _ = abort(sessionID: activeSessionID)
        }
        if activeSessionID != sessionID {
            activeSessionID = sessionID
            isOptionDown = false
        }
        return true
    }

    @discardableResult
    func sendDown(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID, !isOptionDown else { return false }
        isOptionDown = true
        eventSink(true)
        return true
    }

    @discardableResult
    func sendUp(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID, isOptionDown else { return false }
        isOptionDown = false
        activeSessionID = nil
        eventSink(false)
        return true
    }

    @discardableResult
    func abort(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        let wasDown = isOptionDown
        isOptionDown = false
        activeSessionID = nil
        if wasDown {
            eventSink(false)
        }
        return wasDown
    }

    @discardableResult
    func reset() -> Bool {
        guard let activeSessionID else { return false }
        return abort(sessionID: activeSessionID)
    }

    @discardableResult
    func sendTap(sessionID: UUID, duration: TimeInterval = 0.06) -> Bool {
        guard activeSessionID == sessionID else { return false }
        guard sendDown(sessionID: sessionID) else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            _ = self?.sendUp(sessionID: sessionID)
        }
        return true
    }
}
