import Foundation
import CoreGraphics

/// A process-local timeline for one voice gesture. It is diagnostic only: it
/// never gates callbacks or changes the voice state machine.
enum VoiceTimingLogger {
    private struct SessionTiming {
        let startedAt: TimeInterval
        var gateStartedAt: TimeInterval?
        var firstOptionAt: TimeInterval?
    }

    private static let lock = NSLock()
    private static var activeSessionID: UUID?
    private static var sessions: [UUID: SessionTiming] = [:]

    static func begin(
        sessionID: UUID,
        at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        lock.lock()
        let isNewSession = sessions[sessionID] == nil
        if isNewSession {
            sessions[sessionID] = SessionTiming(
                startedAt: uptime,
                gateStartedAt: nil,
                firstOptionAt: nil
            )
        }
        activeSessionID = sessionID
        lock.unlock()
        if isNewSession {
            mark("VOICE_DOWN", sessionID: sessionID, uptime: uptime)
        }
    }

    @discardableResult
    static func mark(
        _ event: String,
        sessionID: UUID? = nil,
        uptime: TimeInterval? = nil,
        details: String? = nil
    ) -> Bool {
        let eventUptime = uptime ?? ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard let resolvedSessionID = sessionID ?? activeSessionID,
              var timing = sessions[resolvedSessionID] else {
            lock.unlock()
            return false
        }
        if event == "OPTION_GATE_BEGIN" {
            timing.gateStartedAt = eventUptime
        } else if Self.isOptionEdgeEvent(event), timing.firstOptionAt == nil {
            timing.firstOptionAt = eventUptime
        }
        sessions[resolvedSessionID] = timing
        let shortID = String(resolvedSessionID.uuidString.prefix(4))
        let line = formatLine(
            event: event,
            shortID: shortID,
            uptime: eventUptime,
            startedAt: timing.startedAt,
            gateStartedAt: timing.gateStartedAt,
            firstOptionAt: timing.firstOptionAt,
            details: details
        )
        lock.unlock()
        print(line)
        return true
    }

    static func markControl(
        _ event: String,
        uptime: TimeInterval,
        details: String
    ) {
        print(
            "[VOICE][CONTROL][TIMING] \(event) "
                + "uptime=" + String(format: "%.6f", uptime) + " "
                + details
        )
    }

    static func end(sessionID: UUID) {
        lock.lock()
        sessions.removeValue(forKey: sessionID)
        if activeSessionID == sessionID {
            activeSessionID = nil
        }
        lock.unlock()
    }

    static func formatLine(
        event: String,
        shortID: String,
        uptime: TimeInterval,
        startedAt: TimeInterval,
        gateStartedAt: TimeInterval?,
        firstOptionAt: TimeInterval?,
        details: String? = nil
    ) -> String {
        var line = "[VOICE][\(shortID)][TIMING] \(event) "
            + "uptime=" + String(format: "%.6f", uptime) + " "
            + String(format: "+%.1fms", (uptime - startedAt) * 1_000)
            + " " + String(
                format: "deltaRawF5=%.1fms",
                (uptime - startedAt) * 1_000
            )
        if let gateStartedAt {
            line += " " + String(
                format: "deltaGate=%.1fms",
                (uptime - gateStartedAt) * 1_000
            )
        }
        if let firstOptionAt {
            line += " " + String(
                format: "deltaFirstOption=%.1fms",
                (uptime - firstOptionAt) * 1_000
            )
        }
        if let details, !details.isEmpty {
            line += " " + details
        }
        return line
    }

    private static func isOptionEdgeEvent(_ event: String) -> Bool {
        switch event {
        case "OPTION_FLAGS_DOWN_SEEN",
             "OPTION_FLAGS_UP_SEEN",
             "OPTION_KEY_DOWN_SEEN",
             "OPTION_KEY_UP_SEEN":
            return true
        default:
            return false
        }
    }
}

/// Diagnostic-only formatting and trace points for the physical Option path.
/// This type deliberately has no state machine, timers, event posting, or
/// policy decisions. It only records what the existing path observed.
enum VoiceOptionTrace {
    static func rawF5Down(
        sessionID: UUID,
        uptime: TimeInterval,
        remoteHIDActive: Bool,
        mappingEnabled: Bool
    ) {
        VoiceTimingLogger.begin(sessionID: sessionID, at: uptime)
        VoiceTimingLogger.mark(
            "RAW_F5_DOWN",
            sessionID: sessionID,
            uptime: uptime,
            details: "remoteHIDActive=\(remoteHIDActive) "
                + "mappingEnabled=\(mappingEnabled)"
        )
    }

    static func rawF5Up(sessionID: UUID, uptime: TimeInterval) {
        VoiceTimingLogger.mark("RAW_F5_UP", sessionID: sessionID, uptime: uptime)
    }

    static func gateBegin(sessionID: UUID, uptime: TimeInterval) {
        VoiceTimingLogger.mark("OPTION_GATE_BEGIN", sessionID: sessionID, uptime: uptime)
    }

    static func gateRelease(
        sessionID: UUID,
        uptime: TimeInterval,
        reason: String
    ) {
        VoiceTimingLogger.mark(
            "OPTION_GATE_RELEASE",
            sessionID: sessionID,
            uptime: uptime,
            details: "reason=\(reason)"
        )
    }

    static func gateCancel(
        sessionID: UUID,
        uptime: TimeInterval,
        reason: String,
        downSeen: Bool,
        upSeen: Bool,
        downCopyCount: Int,
        upCopyCount: Int
    ) {
        VoiceTimingLogger.mark(
            "OPTION_GATE_CANCEL",
            sessionID: sessionID,
            uptime: uptime,
            details: "reason=\(reason) downSeen=\(downSeen) "
                + "upSeen=\(upSeen) downCopyCount=\(downCopyCount) "
                + "upCopyCount=\(upCopyCount)"
        )
    }

    static func optionEvent(
        sessionID: UUID,
        type: CGEventType,
        event: CGEvent,
        uptime: TimeInterval,
        firstOptionEvent: Bool
    ) {
        let eventName = optionEventName(type: type, event: event)
        VoiceTimingLogger.mark(
            eventName,
            sessionID: sessionID,
            uptime: uptime,
            details: optionEventDetails(
                type: type,
                event: event,
                gateActive: true,
                firstOptionEvent: firstOptionEvent
            )
        )
    }

    static func controlOptionEvent(
        type: CGEventType,
        event: CGEvent,
        uptime: TimeInterval
    ) {
        VoiceTimingLogger.markControl(
            optionEventName(type: type, event: event),
            uptime: uptime,
            details: optionEventDetails(
                type: type,
                event: event,
                gateActive: false,
                firstOptionEvent: false
            )
        )
    }

    static func copyResult(
        sessionID: UUID,
        edge: HardwareOptionEdge,
        copied: Bool,
        uptime: TimeInterval
    ) {
        VoiceTimingLogger.mark(
            copied ? "OPTION_COPY_OK" : "OPTION_COPY_FAILED",
            sessionID: sessionID,
            uptime: uptime,
            details: "direction=\(edgeName(edge))"
        )
    }

    static func resolution(
        sessionID: UUID,
        resolution: HardwareOptionResolution,
        uptime: TimeInterval,
        downSeen: Bool,
        upSeen: Bool,
        downCopyCount: Int,
        upCopyCount: Int
    ) {
        VoiceTimingLogger.mark(
            "OPTION_RESOLUTION",
            sessionID: sessionID,
            uptime: uptime,
            details: "resolution=\(resolutionName(resolution)) "
                + "downSeen=\(downSeen) upSeen=\(upSeen) "
                + "downCopyCount=\(downCopyCount) upCopyCount=\(upCopyCount)"
        )
    }

    private static func optionEventName(type: CGEventType, event: CGEvent) -> String {
        switch type {
        case .flagsChanged:
            return event.flags.contains(.maskAlternate)
                ? "OPTION_FLAGS_DOWN_SEEN"
                : "OPTION_FLAGS_UP_SEEN"
        case .keyDown:
            return "OPTION_KEY_DOWN_SEEN"
        case .keyUp:
            return "OPTION_KEY_UP_SEEN"
        default:
            return "OPTION_EVENT_SEEN"
        }
    }

    private static func optionEventDetails(
        type: CGEventType,
        event: CGEvent,
        gateActive: Bool,
        firstOptionEvent: Bool
    ) -> String {
        let fields = [
            "type=\(eventTypeName(type))",
            "flags=0x\(String(event.flags.rawValue, radix: 16))",
            "keyboardEventKeycode=\(event.getIntegerValueField(.keyboardEventKeycode))",
            "keyboardEventAutorepeat=\(event.getIntegerValueField(.keyboardEventAutorepeat))",
            "eventSourceUserData=\(event.getIntegerValueField(.eventSourceUserData))",
            "eventTimestamp=\(event.timestamp)",
            "keyboardEventKeyboardType=\(event.getIntegerValueField(.keyboardEventKeyboardType))",
            "eventSourceStateID=\(event.getIntegerValueField(.eventSourceStateID))",
            "eventSourceUnixProcessID=\(event.getIntegerValueField(.eventSourceUnixProcessID))",
            "eventSourceUserID=\(event.getIntegerValueField(.eventSourceUserID))",
            "eventSourceGroupID=\(event.getIntegerValueField(.eventSourceGroupID))",
            "gateActive=\(gateActive)",
            "firstOptionEvent=\(firstOptionEvent)",
        ]
        return fields.joined(separator: " ")
    }

    private static func eventTypeName(_ type: CGEventType) -> String {
        switch type {
        case .flagsChanged: return "flagsChanged"
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        default: return "raw\(type.rawValue)"
        }
    }

    private static func edgeName(_ edge: HardwareOptionEdge) -> String {
        switch edge {
        case .down: return "down"
        case .up: return "up"
        }
    }

    private static func resolutionName(_ resolution: HardwareOptionResolution) -> String {
        switch resolution {
        case .hardwareReplay: return "hardwareReplay"
        case .syntheticTap: return "syntheticTap"
        case .syntheticDown: return "syntheticDown"
        case .noOptionEdge: return "noOptionEdge"
        }
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
