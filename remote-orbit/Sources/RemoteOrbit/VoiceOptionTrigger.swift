import Foundation
import CoreGraphics

enum VoiceTimingEvent: Int64 {
    case voiceDown
    case rawF5Down
    case rawF5Up
    case optionGateBegin
    case optionGateRelease
    case optionGateCancel
    case optionCopyOK
    case optionCopyFailed
    case optionResolution
    case physicalUp
    case audioFirst
    case routeOff
    case holdConfirmed
    case bleStartRequest
    case remoteRouteBegin
    case bleStopRequest
    case micCloseTx
    case micOpenTx
    case audioStart
    case audioStop
    case lastAudioFrame
    case drainFinish

    var name: String {
        switch self {
        case .voiceDown: return "VOICE_DOWN"
        case .rawF5Down: return "RAW_F5_DOWN"
        case .rawF5Up: return "RAW_F5_UP"
        case .optionGateBegin: return "OPTION_GATE_BEGIN"
        case .optionGateRelease: return "OPTION_GATE_RELEASE"
        case .optionGateCancel: return "OPTION_GATE_CANCEL"
        case .optionCopyOK: return "OPTION_COPY_OK"
        case .optionCopyFailed: return "OPTION_COPY_FAILED"
        case .optionResolution: return "OPTION_RESOLUTION"
        case .physicalUp: return "PHYSICAL_UP"
        case .audioFirst: return "AUDIO_FIRST"
        case .routeOff: return "ROUTE_OFF"
        case .holdConfirmed: return "HOLD_CONFIRMED"
        case .bleStartRequest: return "BLE_START_REQUEST"
        case .remoteRouteBegin: return "REMOTE_ROUTE_BEGIN"
        case .bleStopRequest: return "BLE_STOP_REQUEST"
        case .micCloseTx: return "MIC_CLOSE_TX"
        case .micOpenTx: return "MIC_OPEN_TX"
        case .audioStart: return "AUDIO_START"
        case .audioStop: return "AUDIO_STOP"
        case .lastAudioFrame: return "LAST_AUDIO_FRAME"
        case .drainFinish: return "DRAIN_FINISH"
        }
    }
}

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

    /// Called only by VoiceOptionTrace's serial diagnostic queue. Keeping this
    /// off the event-tap callback prevents diagnostic session bookkeeping from
    /// changing the physical event's return latency.
    static func beginForDiagnostics(
        sessionID: UUID,
        at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        lock.lock()
        if sessions[sessionID] == nil {
            sessions[sessionID] = SessionTiming(
                startedAt: uptime,
                gateStartedAt: nil,
                firstOptionAt: nil
            )
        }
        activeSessionID = sessionID
        lock.unlock()
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
        VoiceOptionTrace.scheduleSessionEnd(sessionID)
    }

    static func finishSessionForDiagnostics(_ sessionID: UUID) {
        lock.lock()
        if activeSessionID == sessionID {
            activeSessionID = nil
        }
        sessions.removeValue(forKey: sessionID)
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
    private static let diagnosticQueueKey = DispatchSpecificKey<Void>()
    private static let diagnosticQueue: DispatchQueue = {
        let queue = DispatchQueue(
            label: "com.lost0rz.RemoteOrbit.voice-option-diagnostics"
        )
        queue.setSpecific(key: diagnosticQueueKey, value: ())
        return queue
    }()

    static let controlTraceEnabled = controlTraceEnabled(
        environment: ProcessInfo.processInfo.environment
    )

    // This map is owned and mutated only by diagnosticQueue. Product gesture
    // IDs remain the coordinator's existing ownership IDs; this is solely the
    // background correlation from a product gesture to a raw F5 trace.
    private static var diagnosticSessionByGestureID: [UUID: UUID] = [:]

    static func controlTraceEnabled(environment: [String: String]) -> Bool {
        environment["REMOTEORBIT_OPTION_CONTROL_TRACE"] == "1"
    }

    /// Warm the diagnostic queue and the environment opt-in before the event
    /// tap starts. This keeps lazy static initialization out of the callback.
    static func initialize() {
        _ = diagnosticQueue
        _ = controlTraceEnabled
    }

    private struct OptionEventSnapshot {
        let typeRawValue: Int64
        let flagsRawValue: UInt64
        let keyCode: Int64
        let autorepeat: Int64
        let eventSourceUserData: Int64
        let eventTimestamp: UInt64
        let keyboardType: Int64
        let sourceStateID: Int64
        let sourceProcessID: Int64
        let sourceUserID: Int64
        let sourceGroupID: Int64
        let uptime: TimeInterval
        let sessionID: UUID?
        let gateActive: Bool
        let firstOptionEvent: Bool
    }

    private static func enqueue(_ work: @escaping () -> Void) {
        diagnosticQueue.async(execute: work)
    }

    static func bindGestureSession(
        diagnosticSessionID: UUID,
        gestureID: UUID
    ) {
        enqueue {
            diagnosticSessionByGestureID[gestureID] = diagnosticSessionID
        }
    }

    #if DEBUG
    /// Test-only probe used to keep formatting on the diagnostic queue.
    static func enqueueFormattingProbeForTesting(
        _ completion: @escaping (Bool) -> Void
    ) {
        enqueue {
            _ = VoiceTimingLogger.formatLine(
                event: VoiceTimingEvent.optionResolution.name,
                shortID: "TEST",
                uptime: 2,
                startedAt: 1,
                gateStartedAt: nil,
                firstOptionAt: nil
            )
            completion(
                DispatchQueue.getSpecific(key: diagnosticQueueKey) != nil
            )
        }
    }

    static func waitForDiagnosticsForTesting() {
        diagnosticQueue.sync {}
    }
    #endif

    static func rawF5Down(
        sessionID: UUID,
        uptime: TimeInterval,
        remoteHIDActive: Bool,
        mappingEnabled: Bool
    ) {
        enqueue {
            VoiceTimingLogger.beginForDiagnostics(sessionID: sessionID, at: uptime)
            VoiceTimingLogger.mark(
                VoiceTimingEvent.voiceDown.name,
                sessionID: sessionID,
                uptime: uptime
            )
            VoiceTimingLogger.mark(
                VoiceTimingEvent.rawF5Down.name,
                sessionID: sessionID,
                uptime: uptime,
                details: "remoteHIDActive=\(remoteHIDActive) "
                    + "mappingEnabled=\(mappingEnabled)"
            )
        }
    }

    static func rawF5Up(sessionID: UUID, uptime: TimeInterval) {
        timingMark(.rawF5Up, sessionID: sessionID, uptime: uptime)
    }

    static func gateBegin(sessionID: UUID, uptime: TimeInterval) {
        timingMark(.optionGateBegin, sessionID: sessionID, uptime: uptime)
    }

    static func gateRelease(
        sessionID: UUID,
        uptime: TimeInterval
    ) {
        enqueue {
            VoiceTimingLogger.mark(
                VoiceTimingEvent.optionGateRelease.name,
                sessionID: diagnosticSessionID(for: sessionID),
                uptime: uptime
            )
        }
    }

    static func gateCancel(
        sessionID: UUID,
        uptime: TimeInterval,
        downSeen: Bool,
        upSeen: Bool,
        downCopyCount: Int,
        upCopyCount: Int
    ) {
        enqueue {
            VoiceTimingLogger.mark(
                VoiceTimingEvent.optionGateCancel.name,
                sessionID: diagnosticSessionID(for: sessionID),
                uptime: uptime,
                details: "downSeen=\(downSeen) "
                    + "upSeen=\(upSeen) downCopyCount=\(downCopyCount) "
                    + "upCopyCount=\(upCopyCount)"
            )
        }
    }

    static func optionEvent(
        sessionID: UUID,
        type: CGEventType,
        event: CGEvent,
        uptime: TimeInterval,
        firstOptionEvent: Bool
    ) {
        let snapshot = makeOptionEventSnapshot(
            type: type,
            event: event,
            uptime: uptime,
            sessionID: sessionID,
            gateActive: true,
            firstOptionEvent: firstOptionEvent
        )
        enqueue {
            let diagnosticSessionID = snapshot.sessionID.map {
                self.diagnosticSessionID(for: $0)
            }
            VoiceTimingLogger.mark(
                optionEventName(snapshot: snapshot),
                sessionID: diagnosticSessionID,
                uptime: snapshot.uptime,
                details: optionEventDetails(snapshot: snapshot)
            )
        }
    }

    static func controlOptionEvent(
        type: CGEventType,
        event: CGEvent,
        uptime: TimeInterval
    ) {
        guard controlTraceEnabled else { return }
        let snapshot = makeOptionEventSnapshot(
            type: type,
            event: event,
            uptime: uptime,
            sessionID: nil,
            gateActive: false,
            firstOptionEvent: false
        )
        enqueue {
            VoiceTimingLogger.markControl(
                optionEventName(snapshot: snapshot),
                uptime: snapshot.uptime,
                details: optionEventDetails(snapshot: snapshot)
            )
        }
    }

    static func timingMark(
        _ event: VoiceTimingEvent,
        sessionID: UUID,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        enqueue {
            VoiceTimingLogger.mark(
                event.name,
                sessionID: diagnosticSessionID(for: sessionID),
                uptime: uptime
            )
        }
    }

    static func timingMark(
        _ event: VoiceTimingEvent,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        enqueue {
            VoiceTimingLogger.mark(event.name, uptime: uptime)
        }
    }

    static func copyResult(
        sessionID: UUID,
        edge: HardwareOptionEdge,
        copied: Bool,
        uptime: TimeInterval
    ) {
        let directionRawValue: Int64 = edge == .down ? 0 : 1
        enqueue {
            VoiceTimingLogger.mark(
                copied
                    ? VoiceTimingEvent.optionCopyOK.name
                    : VoiceTimingEvent.optionCopyFailed.name,
                sessionID: diagnosticSessionID(for: sessionID),
                uptime: uptime,
                details: "direction=\(directionName(rawValue: directionRawValue))"
            )
        }
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
        let resolutionRawValue = resolution.rawValue
        enqueue {
            VoiceTimingLogger.mark(
                VoiceTimingEvent.optionResolution.name,
                sessionID: diagnosticSessionID(for: sessionID),
                uptime: uptime,
                details: "resolution=\(resolutionName(rawValue: resolutionRawValue)) "
                    + "downSeen=\(downSeen) upSeen=\(upSeen) "
                    + "downCopyCount=\(downCopyCount) upCopyCount=\(upCopyCount)"
            )
        }
    }

    static func scheduleSessionEnd(_ sessionID: UUID) {
        enqueue {
            let diagnosticID = diagnosticSessionByGestureID.removeValue(forKey: sessionID)
                ?? sessionID
            VoiceTimingLogger.finishSessionForDiagnostics(diagnosticID)
        }
    }

    private static func diagnosticSessionID(for gestureID: UUID) -> UUID {
        diagnosticSessionByGestureID[gestureID] ?? gestureID
    }

    private static func makeOptionEventSnapshot(
        type: CGEventType,
        event: CGEvent,
        uptime: TimeInterval,
        sessionID: UUID?,
        gateActive: Bool,
        firstOptionEvent: Bool
    ) -> OptionEventSnapshot {
        OptionEventSnapshot(
            typeRawValue: Int64(type.rawValue),
            flagsRawValue: UInt64(event.flags.rawValue),
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat),
            eventSourceUserData: event.getIntegerValueField(.eventSourceUserData),
            eventTimestamp: event.timestamp,
            keyboardType: event.getIntegerValueField(.keyboardEventKeyboardType),
            sourceStateID: event.getIntegerValueField(.eventSourceStateID),
            sourceProcessID: event.getIntegerValueField(.eventSourceUnixProcessID),
            sourceUserID: event.getIntegerValueField(.eventSourceUserID),
            sourceGroupID: event.getIntegerValueField(.eventSourceGroupID),
            uptime: uptime,
            sessionID: sessionID,
            gateActive: gateActive,
            firstOptionEvent: firstOptionEvent
        )
    }

    private static func optionEventName(snapshot: OptionEventSnapshot) -> String {
        if snapshot.typeRawValue == Int64(CGEventType.flagsChanged.rawValue) {
            return snapshot.flagsRawValue & CGEventFlags.maskAlternate.rawValue != 0
                ? "OPTION_FLAGS_DOWN_SEEN"
                : "OPTION_FLAGS_UP_SEEN"
        }
        if snapshot.typeRawValue == Int64(CGEventType.keyDown.rawValue) {
            return "OPTION_KEY_DOWN_SEEN"
        }
        if snapshot.typeRawValue == Int64(CGEventType.keyUp.rawValue) {
            return "OPTION_KEY_UP_SEEN"
        }
        return "OPTION_EVENT_SEEN"
    }

    private static func optionEventDetails(snapshot: OptionEventSnapshot) -> String {
        let fields = [
            "type=\(eventTypeName(rawValue: snapshot.typeRawValue))",
            "flags=0x\(String(snapshot.flagsRawValue, radix: 16))",
            "keyboardEventKeycode=\(snapshot.keyCode)",
            "keyboardEventAutorepeat=\(snapshot.autorepeat)",
            "eventSourceUserData=\(snapshot.eventSourceUserData)",
            "eventTimestamp=\(snapshot.eventTimestamp)",
            "keyboardEventKeyboardType=\(snapshot.keyboardType)",
            "eventSourceStateID=\(snapshot.sourceStateID)",
            "eventSourceUnixProcessID=\(snapshot.sourceProcessID)",
            "eventSourceUserID=\(snapshot.sourceUserID)",
            "eventSourceGroupID=\(snapshot.sourceGroupID)",
            "gateActive=\(snapshot.gateActive)",
            "firstOptionEvent=\(snapshot.firstOptionEvent)",
        ]
        return fields.joined(separator: " ")
    }

    private static func eventTypeName(rawValue: Int64) -> String {
        if rawValue == Int64(CGEventType.flagsChanged.rawValue) {
            return "flagsChanged"
        }
        if rawValue == Int64(CGEventType.keyDown.rawValue) {
            return "keyDown"
        }
        if rawValue == Int64(CGEventType.keyUp.rawValue) {
            return "keyUp"
        }
        return "raw\(rawValue)"
    }

    private static func directionName(rawValue: Int64) -> String {
        rawValue == 0 ? "down" : "up"
    }

    private static func resolutionName(rawValue: Int64) -> String {
        switch rawValue {
        case HardwareOptionResolution.hardwareReplay.rawValue:
            return "hardwareReplay"
        case HardwareOptionResolution.syntheticTap.rawValue:
            return "syntheticTap"
        case HardwareOptionResolution.syntheticDown.rawValue:
            return "syntheticDown"
        case HardwareOptionResolution.noOptionEdge.rawValue:
            return "noOptionEdge"
        default:
            return "raw\(rawValue)"
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

enum HardwareOptionResolution: Int64, Equatable {
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
