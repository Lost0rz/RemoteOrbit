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
