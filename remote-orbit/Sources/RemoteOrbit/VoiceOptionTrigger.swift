import Foundation

enum VoiceOptionDiagnosticContext {
    private static let lock = NSLock()
    private static var sessionID: UUID?
    private static var diagnostics: VoiceSessionDiagnostics?

    static func with<T>(
        sessionID: UUID,
        diagnostics: VoiceSessionDiagnostics,
        operation: () -> T
    ) -> T {
        lock.lock()
        let previousSessionID = self.sessionID
        let previousDiagnostics = self.diagnostics
        self.sessionID = sessionID
        self.diagnostics = diagnostics
        lock.unlock()
        defer {
            lock.lock()
            self.sessionID = previousSessionID
            self.diagnostics = previousDiagnostics
            lock.unlock()
        }
        return operation()
    }

    static func current() -> (sessionID: UUID, diagnostics: VoiceSessionDiagnostics)? {
        lock.lock()
        defer { lock.unlock() }
        guard let sessionID, let diagnostics else { return nil }
        return (sessionID, diagnostics)
    }
}

/// A process-local timeline for one voice gesture. It is diagnostic only: it
/// never gates callbacks or changes the voice state machine.
enum VoiceTimingLogger {
    private static let lock = NSLock()
    private static var activeSessionID: UUID?
    private static var startedAt: TimeInterval = 0
    private static var activeDiagnostics: VoiceSessionDiagnostics?
    private static var firstPCMStages: Set<VoicePCMStage> = []

    static func begin(
        sessionID: UUID,
        diagnostics: VoiceSessionDiagnostics = .shared
    ) {
        lock.lock()
        activeSessionID = sessionID
        startedAt = ProcessInfo.processInfo.systemUptime
        activeDiagnostics = diagnostics
        firstPCMStages.removeAll()
        lock.unlock()
    }

    static func mark(_ event: String, sessionID: UUID? = nil) {
        lock.lock()
        guard let activeSessionID,
              sessionID == nil || sessionID == activeSessionID else {
            lock.unlock()
            return
        }
        let currentSessionID = activeSessionID
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        let shortID = String(currentSessionID.uuidString.prefix(4))
        let diagnostics = activeDiagnostics
        lock.unlock()
        print(
            "[VOICE][\(shortID)][TIMING] \(event) "
                + String(format: "+%.1fms", elapsedMS)
        )
        diagnostics?.record(
            sessionID: currentSessionID,
            category: category(for: event),
            event: event
        )
    }

    static func markFirstPCM(
        _ stage: VoicePCMStage,
        sessionID: UUID? = nil
    ) {
        lock.lock()
        guard let activeSessionID,
              sessionID == nil || sessionID == activeSessionID,
              firstPCMStages.insert(stage).inserted
        else {
            lock.unlock()
            return
        }
        let currentSessionID = activeSessionID
        let diagnostics = activeDiagnostics
        lock.unlock()
        diagnostics?.markFirstPCM(sessionID: currentSessionID, stage: stage)
    }

    static func end(sessionID: UUID) {
        lock.lock()
        if activeSessionID == sessionID {
            activeSessionID = nil
            activeDiagnostics = nil
            firstPCMStages.removeAll()
        }
        lock.unlock()
    }

    private static func category(for event: String) -> VoiceDiagnosticCategory {
        if event.hasPrefix("OPTION") { return .option }
        if event.hasPrefix("PCM") || event.hasPrefix("AUDIO") {
            return .audio
        }
        if event.hasPrefix("BLE") || event.hasPrefix("MIC") {
            return .ble
        }
        if event.hasPrefix("ROUTE") { return .route }
        if event.hasPrefix("PHYSICAL") { return .hid }
        if event.hasPrefix("SESSION") { return .session }
        return .session
    }
}

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

enum HardwareOptionOwner: String, Equatable {
    case hardware
    case syntheticFallback = "synthetic_fallback"
}

enum HardwareOptionGateState: Equatable {
    case waitingForHardware
    case hardwareOwned
    case fallbackOwned
    case resolved
    case cancelled
}

enum HardwareOptionEventDisposition: Equatable {
    case deferred
    case suppressedLate
    case passThrough
    case ignored
}

/// Coordinates the mapped physical Option edge with the voice gesture.
///
/// The gate is deliberately independent from `VoiceOptionTrigger`: hardware
/// owns the normal path, while the synthetic trigger is selected only after a
/// missing/copy-failed physical edge is explicitly resolved as fallback.
final class HardwareOptionGate {
    private(set) var activeSessionID: UUID?
    private(set) var state: HardwareOptionGateState = .cancelled
    private(set) var selectedOwner: HardwareOptionOwner?
    private(set) var fallbackReason: String?
    private(set) var hardwareDownSeen = false
    private(set) var hardwareUpSeen = false
    private(set) var copiedDownPresent = false

    private var replayedDownAwaitingPhysicalUp = false
    private var hardwareCopyFailed = false

    @discardableResult
    func begin(sessionID: UUID) -> Bool {
        if let activeSessionID, activeSessionID != sessionID {
            _ = cancel(sessionID: activeSessionID)
        }
        guard activeSessionID != sessionID else { return true }
        self.activeSessionID = sessionID
        state = .waitingForHardware
        selectedOwner = nil
        fallbackReason = nil
        hardwareDownSeen = false
        hardwareUpSeen = false
        copiedDownPresent = false
        replayedDownAwaitingPhysicalUp = false
        hardwareCopyFailed = false
        return true
    }

    /// Compatibility/test seam that reports whether an edge was deferred.
    @discardableResult
    func capture(_ edge: HardwareOptionEdge, copied: Bool) -> Bool {
        captureEvent(edge, copied: copied) == .deferred
    }

    /// Record an edge and tell the event tap whether to defer, suppress, or
    /// pass it through. The caller supplies whether `CGEvent.copy()` worked.
    @discardableResult
    func captureEvent(
        _ edge: HardwareOptionEdge,
        copied: Bool
    ) -> HardwareOptionEventDisposition {
        guard activeSessionID != nil else { return .ignored }

        switch state {
        case .waitingForHardware, .hardwareOwned:
            switch edge {
            case .down:
                hardwareDownSeen = true
                if copied {
                    copiedDownPresent = true
                    state = .hardwareOwned
                } else {
                    hardwareCopyFailed = true
                }
                return .deferred
            case .up:
                guard hardwareDownSeen else { return .passThrough }
                hardwareUpSeen = true
                if !copied {
                    hardwareCopyFailed = true
                }
                return .deferred
            }
        case .fallbackOwned:
            return .suppressedLate
        case .resolved:
            if edge == .up, replayedDownAwaitingPhysicalUp {
                replayedDownAwaitingPhysicalUp = false
                activeSessionID = nil
                return .passThrough
            }
            return .suppressedLate
        case .cancelled:
            return .passThrough
        }
    }

    @discardableResult
    func resolve(sessionID: UUID) -> HardwareOptionResolution? {
        guard activeSessionID == sessionID else { return nil }
        guard state == .waitingForHardware || state == .hardwareOwned else {
            return nil
        }
        if copiedDownPresent, !hardwareCopyFailed {
            selectedOwner = .hardware
            state = .resolved
            return .hardwareReplay
        }
        return resolutionWithoutOwner()
    }

    /// Select synthetic fallback after the caller has reached the narrow
    /// resolution point (first PCM for a long press, or copy failure).
    @discardableResult
    func selectFallback(
        sessionID: UUID,
        reason: String
    ) -> HardwareOptionResolution? {
        guard activeSessionID == sessionID else { return nil }
        guard state == .waitingForHardware || state == .hardwareOwned else {
            return nil
        }
        selectedOwner = .syntheticFallback
        fallbackReason = reason
        state = .fallbackOwned
        let resolution = resolutionWithoutOwner()
        return resolution == .noOptionEdge ? .syntheticDown : resolution
    }

    func owner(for sessionID: UUID) -> HardwareOptionOwner? {
        guard activeSessionID == sessionID else { return nil }
        return selectedOwner
    }

    /// Returns true when an event must be dropped because fallback already
    /// owns the session, or because it is a duplicate after hardware replay.
    @discardableResult
    func shouldSuppressLateHardwareEvent(
        _ edge: HardwareOptionEdge,
        sessionID: UUID
    ) -> Bool {
        guard activeSessionID == sessionID else { return false }
        return captureEvent(edge, copied: false) == .suppressedLate
    }

    /// Finish hardware replay. If only the copied down was replayed, retain a
    /// tiny resolved gate so the matching physical up can pass exactly once.
    func completeHardwareReplay(
        sessionID: UUID,
        replayedDown: Bool,
        replayedUp: Bool
    ) {
        guard activeSessionID == sessionID,
              selectedOwner == .hardware,
              state == .resolved
        else { return }
        replayedDownAwaitingPhysicalUp = replayedDown && !replayedUp
        if !replayedDownAwaitingPhysicalUp {
            activeSessionID = nil
        }
    }

    @discardableResult
    func cancel(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        activeSessionID = nil
        state = .cancelled
        selectedOwner = nil
        fallbackReason = nil
        hardwareDownSeen = false
        hardwareUpSeen = false
        copiedDownPresent = false
        replayedDownAwaitingPhysicalUp = false
        hardwareCopyFailed = false
        return true
    }

    private func resolutionWithoutOwner() -> HardwareOptionResolution {
        guard hardwareDownSeen else { return .noOptionEdge }
        return hardwareUpSeen ? .syntheticTap : .syntheticDown
    }
}

/// Owns synthetic Option edges for one voice gesture. In particular, the
/// delayed up from a short tap is ignored once a newer session owns the
/// trigger, so it cannot release the newer gesture.
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
    private let diagnostics: VoiceSessionDiagnostics
    private(set) var activeSessionID: UUID?
    private(set) var isOptionDown = false

    init(
        eventSink: @escaping EventSink,
        diagnostics: VoiceSessionDiagnostics = .shared
    ) {
        self.eventSink = eventSink
        self.diagnostics = diagnostics
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
        guard activeSessionID == sessionID, !isOptionDown else {
            if activeSessionID != nil, activeSessionID != sessionID {
                diagnostics.recordStaleCallback(
                    callback: "option-down",
                    callbackSession: sessionID,
                    activeSession: activeSessionID
                )
            }
            return false
        }
        isOptionDown = true
        diagnostics.recordOptionRequest(sessionID: sessionID, direction: .down)
        VoiceOptionDiagnosticContext.with(
            sessionID: sessionID,
            diagnostics: diagnostics
        ) {
            eventSink(true)
        }
        return true
    }

    @discardableResult
    func sendUp(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID, isOptionDown else {
            if activeSessionID != nil, activeSessionID != sessionID {
                diagnostics.recordStaleCallback(
                    callback: "option-up",
                    callbackSession: sessionID,
                    activeSession: activeSessionID
                )
            }
            return false
        }
        isOptionDown = false
        activeSessionID = nil
        diagnostics.recordOptionRequest(sessionID: sessionID, direction: .up)
        VoiceOptionDiagnosticContext.with(
            sessionID: sessionID,
            diagnostics: diagnostics
        ) {
            eventSink(false)
        }
        return true
    }

    @discardableResult
    func abort(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        let wasDown = isOptionDown
        isOptionDown = false
        activeSessionID = nil
        if wasDown {
            diagnostics.recordOptionRequest(
                sessionID: sessionID,
                direction: .up,
                event: "OPTION_ABORT_UP_REQUEST"
            )
            VoiceOptionDiagnosticContext.with(
                sessionID: sessionID,
                diagnostics: diagnostics
            ) {
                eventSink(false)
            }
        }
        return wasDown
    }

    @discardableResult
    func reset() -> Bool {
        guard let activeSessionID else { return false }
        return abort(sessionID: activeSessionID)
    }

    @discardableResult
    func sendTap(
        sessionID: UUID,
        duration: TimeInterval = 0.06,
        completion: ((Bool) -> Void)? = nil
    ) -> Bool {
        guard activeSessionID == sessionID else { return false }
        guard sendDown(sessionID: sessionID) else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            let released = self?.sendUp(sessionID: sessionID) ?? false
            completion?(released)
        }
        return true
    }
}
