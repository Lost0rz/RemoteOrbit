import Foundation

enum VoiceDiagnosticCategory: String, Equatable {
    case hid = "HID"
    case session = "SESSION"
    case ble = "BLE"
    case audio = "AUDIO"
    case option = "OPTION"
    case focus = "FOCUS"
    case route = "ROUTE"
    case safety = "SAFETY"
}

enum VoicePCMStage: String, Equatable, Hashable {
    case decode
    case feed
    case audioCallback
}

enum VoiceOptionDirection: String, Equatable {
    case down
    case up
}

enum VoiceOptionComponent: String, Equatable {
    case flags
    case key
}

enum VoiceSessionLifecycle: String, Equatable {
    case balanced
    case aborted
    case incomplete
}

enum VoiceSessionCompletion: String, Equatable {
    case normalDrain = "normal-drain"
    case tailFallback = "tail-fallback"
    case abort
    case noPCM = "no-pcm"
    case disconnect
    case shortTap = "short-tap"
    case incomplete
}

struct VoiceDiagnosticEvent: Equatable {
    let sessionID: UUID
    let shortID: String
    let sequence: Int
    let uptime: TimeInterval
    let elapsedMilliseconds: Double
    let thread: String
    let category: VoiceDiagnosticCategory
    let event: String
    let fields: [String: String]
}

struct VoiceSessionSummary: Equatable {
    let sessionID: UUID
    let shortID: String
    let sequence: Int
    let durationMilliseconds: Double
    let legacySafe: Bool
    let shortBindingMode: String
    let bypassShortClassification: Bool
    let targetBundleID: String?
    let lifecycle: VoiceSessionLifecycle
    let completion: VoiceSessionCompletion
    let firstPCM: Bool
    let optionDownRequests: Int
    let optionUpRequests: Int
    let downFlagsPosted: Int
    let downKeyPosted: Int
    let upFlagsPosted: Int
    let upKeyPosted: Int
    let downFlagsObserved: Int
    let downKeyObserved: Int
    let upFlagsObserved: Int
    let upKeyObserved: Int
    let observerAvailable: Bool
    let focusSource: String?
    let focusReady: Bool?
    let staleCallbacksRejected: Int
    let invariantViolations: Int

    var deliveryEvidence: String {
        guard observerAvailable else { return "observer-unavailable" }
        let hasCompleteDown = downFlagsPosted > 0 && downKeyPosted > 0
            && downFlagsObserved > 0 && downKeyObserved > 0
        let hasCompleteUp = upFlagsPosted > 0 && upKeyPosted > 0
            && upFlagsObserved > 0 && upKeyObserved > 0
        return hasCompleteDown && hasCompleteUp ? "complete" : "partial"
    }
}

/// Thread-safe, diagnostic-only state for one voice gesture at a time.
///
/// This type deliberately has no BLE, audio, focus, or lifecycle control. It
/// records facts supplied by those owners and never sends a corrective event.
final class VoiceSessionDiagnostics {
    typealias EventSink = (String) -> Void
    typealias Clock = () -> TimeInterval

    private static let defaultSummaryGrace: TimeInterval = 0.18
    private static let observationWindow: TimeInterval = 1.0

    private final class ExpectedOptionEdge {
        let direction: VoiceOptionDirection
        var postedAt: TimeInterval
        var flagsObserved = false
        var keyObserved = false

        init(direction: VoiceOptionDirection, postedAt: TimeInterval) {
            self.direction = direction
            self.postedAt = postedAt
        }
    }

    private final class SessionState {
        let sessionID: UUID
        let shortID: String
        let startedAt: TimeInterval
        let legacySafe: Bool
        let shortBindingMode: String
        let bypassShortClassification: Bool
        let targetBundleID: String?
        var nextSequence = 1
        var events: [VoiceDiagnosticEvent] = []
        var firstPCMStages = Set<VoicePCMStage>()
        var optionDownRequests = 0
        var optionUpRequests = 0
        var downFlagsPosted = 0
        var downKeyPosted = 0
        var upFlagsPosted = 0
        var upKeyPosted = 0
        var downFlagsObserved = 0
        var downKeyObserved = 0
        var upFlagsObserved = 0
        var upKeyObserved = 0
        var logicalOptionDown = false
        var holdConfirmed = false
        var observerAvailable: Bool
        var focusSource: String?
        var focusReady: Bool?
        var staleCallbacksRejected = 0
        var invariantViolations = 0
        var expectedOptionEdges: [ExpectedOptionEdge] = []
        var endedAt: TimeInterval?
        var lifecycle: VoiceSessionLifecycle = .incomplete
        var completion: VoiceSessionCompletion = .incomplete
        var summary: VoiceSessionSummary?

        init(
            sessionID: UUID,
            startedAt: TimeInterval,
            legacySafe: Bool,
            shortBindingMode: String,
            bypassShortClassification: Bool,
            targetBundleID: String?,
            observerAvailable: Bool
        ) {
            self.sessionID = sessionID
            self.shortID = String(sessionID.uuidString.prefix(8))
            self.startedAt = startedAt
            self.legacySafe = legacySafe
            self.shortBindingMode = shortBindingMode
            self.bypassShortClassification = bypassShortClassification
            self.targetBundleID = targetBundleID
            self.observerAvailable = observerAvailable
        }
    }

    static let shared = VoiceSessionDiagnostics(eventSink: VoiceReliabilityLog.write)

    private let lock = NSLock()
    private let eventSink: EventSink
    private let summaryGrace: TimeInterval
    private let clock: Clock
    private var sessions: [UUID: SessionState] = [:]
    private var activeSessionID: UUID?
    private var defaultObserverAvailable = false

    init(
        eventSink: @escaping EventSink = { _ in },
        summaryGrace: TimeInterval = VoiceSessionDiagnostics.defaultSummaryGrace,
        clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.eventSink = eventSink
        self.summaryGrace = max(0, summaryGrace)
        self.clock = clock
    }

    @discardableResult
    func begin(
        sessionID: UUID,
        legacySafe: Bool,
        shortBindingMode: String = "unknown",
        bypassShortClassification: Bool = false,
        targetBundleID: String? = nil
    ) -> Bool {
        guard legacySafe else {
            recordVoiceBlocked(reason: "legacy-mapping-unsafe")
            return false
        }

        let now = clock()
        lock.lock()
        let state = SessionState(
            sessionID: sessionID,
            startedAt: now,
            legacySafe: true,
            shortBindingMode: Self.safeValue(shortBindingMode),
            bypassShortClassification: bypassShortClassification,
            targetBundleID: targetBundleID.map(Self.safeValue),
            observerAvailable: defaultObserverAvailable
        )
        sessions[sessionID] = state
        activeSessionID = sessionID
        let event = appendEventLocked(
            state,
            category: .session,
            event: "SESSION_BEGIN",
            fields: [
                "legacySafe": "true",
                "shortBinding": Self.safeValue(shortBindingMode),
                "bypassShortClassification": String(bypassShortClassification),
                "targetBundle": targetBundleID.map(Self.safeValue) ?? "unknown",
            ]
        )
        lock.unlock()
        emit(event)
        return true
    }

    func recordVoiceBlocked(reason: String) {
        emitGlobal(
            category: .safety,
            event: "VOICE_BLOCKED",
            fields: ["reason": reason]
        )
    }

    func recordLegacyMappingClear(reason: String, success: Bool) {
        emitGlobal(
            category: .safety,
            event: "LEGACY_MAPPING_CLEAR",
            fields: [
                "reason": reason,
                "success": String(success),
            ]
        )
    }

    func record(
        sessionID: UUID,
        category: VoiceDiagnosticCategory,
        event: String,
        fields: [String: String] = [:]
    ) {
        lock.lock()
        guard let state = sessions[sessionID], state.summary == nil else {
            lock.unlock()
            return
        }
        let diagnosticEvent = appendEventLocked(
            state,
            category: category,
            event: event,
            fields: fields
        )
        if event == "HOLD_CONFIRMED" {
            state.holdConfirmed = true
        }
        lock.unlock()
        emit(diagnosticEvent)
    }

    func markFirstPCM(sessionID: UUID, stage: VoicePCMStage) {
        lock.lock()
        guard let state = sessions[sessionID], state.summary == nil else {
            lock.unlock()
            return
        }
        guard state.firstPCMStages.insert(stage).inserted else {
            lock.unlock()
            return
        }
        let eventName: String
        switch stage {
        case .decode: eventName = "PCM_DECODE_FIRST"
        case .feed: eventName = "PCM_FEED_FIRST"
        case .audioCallback: eventName = "AUDIO_FIRST_CALLBACK"
        }
        let event = appendEventLocked(state, category: .audio, event: eventName)
        lock.unlock()
        emit(event)
    }

    func recordOptionRequest(
        sessionID: UUID,
        direction: VoiceOptionDirection,
        event requestedEvent: String? = nil
    ) {
        lock.lock()
        guard let state = sessions[sessionID], state.summary == nil else {
            lock.unlock()
            return
        }
        let eventName = requestedEvent
            ?? (direction == .down ? "OPTION_DOWN_REQUEST" : "OPTION_UP_REQUEST")
        var events = [appendEventLocked(state, category: .option, event: eventName)]
        switch direction {
        case .down:
            state.optionDownRequests += 1
            if state.holdConfirmed && state.firstPCMStages.isEmpty {
                events.append(
                    appendInvariantLocked(state, type: "option-down-before-first-pcm")
                )
            }
            if state.logicalOptionDown {
                events.append(appendInvariantLocked(state, type: "duplicate-option-down"))
            }
            state.logicalOptionDown = true
            state.expectedOptionEdges.append(
                ExpectedOptionEdge(direction: .down, postedAt: clock())
            )
        case .up:
            state.optionUpRequests += 1
            if !state.logicalOptionDown {
                events.append(appendInvariantLocked(state, type: "option-up-without-down"))
            }
            state.logicalOptionDown = false
            state.expectedOptionEdges.append(
                ExpectedOptionEdge(direction: .up, postedAt: clock())
            )
        }
        lock.unlock()
        emit(events)
    }

    func recordOptionPost(
        sessionID: UUID,
        direction: VoiceOptionDirection,
        component: VoiceOptionComponent
    ) {
        lock.lock()
        guard let state = sessions[sessionID], state.summary == nil else {
            lock.unlock()
            return
        }
        switch (direction, component) {
        case (.down, .flags): state.downFlagsPosted += 1
        case (.down, .key): state.downKeyPosted += 1
        case (.up, .flags): state.upFlagsPosted += 1
        case (.up, .key): state.upKeyPosted += 1
        }
        if let expected = state.expectedOptionEdges.last(where: { $0.direction == direction }) {
            expected.postedAt = clock()
        }
        let eventName = optionEvidenceEvent(
            direction: direction,
            component: component,
            observed: false
        )
        let event = appendEventLocked(state, category: .option, event: eventName)
        lock.unlock()
        emit(event)
    }

    /// Correlates a listen-only downstream event without guessing a session.
    /// Returns the matched session ID, or nil for an uncorrelated event.
    @discardableResult
    func observeSyntheticOption(
        direction: VoiceOptionDirection,
        component: VoiceOptionComponent,
        uptime: TimeInterval? = nil
    ) -> UUID? {
        let now = uptime ?? clock()
        lock.lock()
        purgeExpiredExpectedEdgesLocked(now: now)
        let candidates = sessions.values
            .filter { $0.summary == nil }
            .sorted { $0.startedAt > $1.startedAt }
        var matchedState: SessionState?
        var matchedExpected: ExpectedOptionEdge?
        for state in candidates {
            guard let expected = state.expectedOptionEdges.last(where: {
                $0.direction == direction
            }) else { continue }
            guard now >= expected.postedAt,
                  now - expected.postedAt <= Self.observationWindow else { continue }
            matchedState = state
            matchedExpected = expected
            break
        }

        guard let state = matchedState, let expected = matchedExpected else {
            let active = activeSessionID?.uuidString ?? "none"
            lock.unlock()
            emitGlobal(
                category: .option,
                event: optionEvidenceEvent(
                    direction: direction,
                    component: component,
                    observed: true
                ),
                fields: ["uncorrelated": "true", "activeSession": active]
            )
            return nil
        }

        let alreadyObserved: Bool
        switch component {
        case .flags: alreadyObserved = expected.flagsObserved
        case .key: alreadyObserved = expected.keyObserved
        }
        switch (direction, component) {
        case (.down, .flags):
            if !alreadyObserved { state.downFlagsObserved += 1 }
            expected.flagsObserved = true
        case (.down, .key):
            if !alreadyObserved { state.downKeyObserved += 1 }
            expected.keyObserved = true
        case (.up, .flags):
            if !alreadyObserved { state.upFlagsObserved += 1 }
            expected.flagsObserved = true
        case (.up, .key):
            if !alreadyObserved { state.upKeyObserved += 1 }
            expected.keyObserved = true
        }
        var fields = ["uncorrelated": "false"]
        if alreadyObserved { fields["duplicate"] = "true" }
        let event = appendEventLocked(
            state,
            category: .option,
            event: optionEvidenceEvent(
                direction: direction,
                component: component,
                observed: true
            ),
            fields: fields
        )
        lock.unlock()
        emit(event)
        return state.sessionID
    }

    func setObserverAvailable(_ available: Bool) {
        lock.lock()
        defaultObserverAvailable = available
        if let activeSessionID, let state = sessions[activeSessionID], state.summary == nil {
            state.observerAvailable = available
        }
        lock.unlock()
    }

    func recordFocusRequest(
        sessionID: UUID,
        source: String,
        targetBundleID: String?
    ) {
        record(
            sessionID: sessionID,
            category: .focus,
            event: "FOCUS_REQUEST",
            fields: [
                "source": Self.safeValue(source),
                "targetBundle": targetBundleID.map(Self.safeValue) ?? "unknown",
                "advisory": "true",
            ]
        )
    }

    func recordFocusResult(
        sessionID: UUID,
        source: String,
        targetBundleID: String?,
        ready: Bool,
        reason: String,
        latencyMilliseconds: Double
    ) {
        lock.lock()
        guard let state = sessions[sessionID], state.summary == nil else {
            lock.unlock()
            return
        }
        state.focusSource = Self.safeValue(source)
        state.focusReady = ready
        let event = appendEventLocked(
            state,
            category: .focus,
            event: "FOCUS_RESULT",
            fields: [
                "source": Self.safeValue(source),
                "targetBundle": targetBundleID.map(Self.safeValue) ?? "unknown",
                "ready": String(ready),
                "reason": Self.safeValue(reason),
                "latency_ms": Self.formatMilliseconds(latencyMilliseconds),
                "advisory": "true",
            ]
        )
        lock.unlock()
        emit(event)
    }

    func recordStaleCallback(
        callback: String,
        callbackSession: UUID,
        activeSession: UUID?,
        currentState: String? = nil,
        pendingRepressSession: UUID? = nil
    ) {
        lock.lock()
        guard let state = sessions[callbackSession] else {
            lock.unlock()
            return
        }
        if state.summary == nil {
            state.staleCallbacksRejected += 1
        }
        var fields = [
            "callback": Self.safeValue(callback),
            "callbackSession": callbackSession.uuidString,
            "activeSession": activeSession?.uuidString ?? "none",
        ]
        if let currentState { fields["currentState"] = Self.safeValue(currentState) }
        if let pendingRepressSession {
            fields["pendingRepressSession"] = pendingRepressSession.uuidString
        }
        let event = appendEventLocked(
            state,
            category: .safety,
            event: "STALE_CALLBACK_REJECTED",
            fields: fields
        )
        lock.unlock()
        emit(event)
    }

    func end(
        sessionID: UUID,
        completion: VoiceSessionCompletion,
        lifecycle: VoiceSessionLifecycle
    ) {
        lock.lock()
        guard let state = sessions[sessionID],
              state.summary == nil,
              state.endedAt == nil
        else {
            lock.unlock()
            return
        }
        var events: [VoiceDiagnosticEvent] = []
        if state.logicalOptionDown {
            events.append(appendInvariantLocked(state, type: "session-ended-option-down"))
        }
        state.lifecycle = lifecycle
        state.completion = completion
        state.endedAt = clock()
        events.append(
            appendEventLocked(
                state,
                category: .session,
                event: "SESSION_END",
                fields: [
                    "lifecycle": lifecycle.rawValue,
                    "completion": completion.rawValue,
                ]
            )
        )
        let delay = summaryGrace
        lock.unlock()
        emit(events)

        if delay == 0 {
            finalizeSummary(sessionID: sessionID)
        } else {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                [weak self] in
                self?.finalizeSummary(sessionID: sessionID)
            }
        }
    }

    func events(for sessionID: UUID) -> [VoiceDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return sessions[sessionID]?.events ?? []
    }

    func summary(for sessionID: UUID) -> VoiceSessionSummary? {
        lock.lock()
        defer { lock.unlock() }
        guard let state = sessions[sessionID] else { return nil }
        return state.summary ?? makeSummaryLocked(state)
    }

    private func finalizeSummary(sessionID: UUID) {
        lock.lock()
        guard let state = sessions[sessionID], state.summary == nil else {
            lock.unlock()
            return
        }
        let summary = makeSummaryLocked(state)
        state.summary = summary
        let line = formatSummary(summary)
        lock.unlock()
        eventSink(line)
    }

    private func makeSummaryLocked(_ state: SessionState) -> VoiceSessionSummary {
        let end = state.endedAt ?? clock()
        return VoiceSessionSummary(
            sessionID: state.sessionID,
            shortID: state.shortID,
            sequence: max(0, state.nextSequence - 1),
            durationMilliseconds: max(0, (end - state.startedAt) * 1_000),
            legacySafe: state.legacySafe,
            shortBindingMode: state.shortBindingMode,
            bypassShortClassification: state.bypassShortClassification,
            targetBundleID: state.targetBundleID,
            lifecycle: state.lifecycle,
            completion: state.completion,
            firstPCM: !state.firstPCMStages.isEmpty,
            optionDownRequests: state.optionDownRequests,
            optionUpRequests: state.optionUpRequests,
            downFlagsPosted: state.downFlagsPosted,
            downKeyPosted: state.downKeyPosted,
            upFlagsPosted: state.upFlagsPosted,
            upKeyPosted: state.upKeyPosted,
            downFlagsObserved: state.downFlagsObserved,
            downKeyObserved: state.downKeyObserved,
            upFlagsObserved: state.upFlagsObserved,
            upKeyObserved: state.upKeyObserved,
            observerAvailable: state.observerAvailable,
            focusSource: state.focusSource,
            focusReady: state.focusReady,
            staleCallbacksRejected: state.staleCallbacksRejected,
            invariantViolations: state.invariantViolations
        )
    }

    private func appendEventLocked(
        _ state: SessionState,
        category: VoiceDiagnosticCategory,
        event: String,
        fields: [String: String] = [:]
    ) -> VoiceDiagnosticEvent {
        let now = clock()
        let diagnosticEvent = VoiceDiagnosticEvent(
            sessionID: state.sessionID,
            shortID: state.shortID,
            sequence: state.nextSequence,
            uptime: now,
            elapsedMilliseconds: max(0, (now - state.startedAt) * 1_000),
            thread: Thread.isMainThread ? "main" : "background",
            category: category,
            event: event,
            fields: fields.mapValues(Self.safeValue)
        )
        state.nextSequence += 1
        state.events.append(diagnosticEvent)
        return diagnosticEvent
    }

    private func appendInvariantLocked(
        _ state: SessionState,
        type: String
    ) -> VoiceDiagnosticEvent {
        state.invariantViolations += 1
        return appendEventLocked(
            state,
            category: .safety,
            event: "INVARIANT_VIOLATION",
            fields: ["type": type]
        )
    }

    private func purgeExpiredExpectedEdgesLocked(now: TimeInterval) {
        for state in sessions.values {
            state.expectedOptionEdges.removeAll {
                now - $0.postedAt > Self.observationWindow
            }
        }
    }

    private func emit(_ event: VoiceDiagnosticEvent) {
        eventSink(format(event))
    }

    private func emit(_ events: [VoiceDiagnosticEvent]) {
        events.forEach { emit($0) }
    }

    private func emitGlobal(
        category: VoiceDiagnosticCategory,
        event: String,
        fields: [String: String]
    ) {
        var parts = [
            "schema=1",
            "session=none",
            "short=GLOBAL",
            "seq=0",
            String(format: "uptime=%.6f", clock()),
            "elapsed_ms=0.0",
            "thread=\(Thread.isMainThread ? "main" : "background")",
            "category=\(category.rawValue)",
            "event=\(event)",
        ]
        fields.keys.sorted().forEach { key in
            parts.append("\(key)=\(Self.safeValue(fields[key] ?? ""))")
        }
        eventSink("[VOICE][GLOBAL][\(event)] " + parts.joined(separator: " "))
    }

    private func format(_ event: VoiceDiagnosticEvent) -> String {
        var parts = [
            "schema=1",
            "session=\(event.sessionID.uuidString)",
            "short=\(event.shortID)",
            String(format: "seq=%03d", event.sequence),
            String(format: "uptime=%.6f", event.uptime),
            "elapsed_ms=\(Self.formatMilliseconds(event.elapsedMilliseconds))",
            "thread=\(event.thread)",
            "category=\(event.category.rawValue)",
            "event=\(event.event)",
        ]
        event.fields.keys.sorted().forEach { key in
            parts.append("\(key)=\(Self.safeValue(event.fields[key] ?? ""))")
        }
        return "[VOICE][\(event.shortID)][\(String(format: "%03d", event.sequence))] "
            + parts.joined(separator: " ")
    }

    private func formatSummary(_ summary: VoiceSessionSummary) -> String {
        let fields: [(String, String)] = [
            ("schema", "1"),
            ("session", summary.sessionID.uuidString),
            ("short", summary.shortID),
            ("seq", String(summary.sequence)),
            ("duration_ms", Self.formatMilliseconds(summary.durationMilliseconds)),
            ("legacySafe", String(summary.legacySafe)),
            ("shortBinding", summary.shortBindingMode),
            ("bypassShortClassification", String(summary.bypassShortClassification)),
            ("targetBundle", summary.targetBundleID ?? "unknown"),
            ("lifecycle", summary.lifecycle.rawValue),
            ("completion", summary.completion.rawValue),
            ("deliveryEvidence", summary.deliveryEvidence),
            ("firstPCM", String(summary.firstPCM)),
            ("optionDownRequests", String(summary.optionDownRequests)),
            ("optionUpRequests", String(summary.optionUpRequests)),
            ("downFlagsPosted", String(summary.downFlagsPosted > 0)),
            ("downKeyPosted", String(summary.downKeyPosted > 0)),
            ("upFlagsPosted", String(summary.upFlagsPosted > 0)),
            ("upKeyPosted", String(summary.upKeyPosted > 0)),
            ("downFlagsObserved", String(summary.downFlagsObserved > 0)),
            ("downKeyObserved", String(summary.downKeyObserved > 0)),
            ("upFlagsObserved", String(summary.upFlagsObserved > 0)),
            ("upKeyObserved", String(summary.upKeyObserved > 0)),
            ("observerAvailable", String(summary.observerAvailable)),
            ("focusSource", summary.focusSource ?? "none"),
            ("focusReady", summary.focusReady.map(String.init) ?? "unknown"),
            ("staleCallbacksRejected", String(summary.staleCallbacksRejected)),
            ("invariantViolations", String(summary.invariantViolations)),
        ]
        return "[VOICE][\(summary.shortID)][SUMMARY] "
            + fields.map { "\($0.0)=\(Self.safeValue($0.1))" }.joined(separator: " ")
    }

    private func optionEvidenceEvent(
        direction: VoiceOptionDirection,
        component: VoiceOptionComponent,
        observed: Bool
    ) -> String {
        let prefix = direction == .down ? "OPTION_DOWN" : "OPTION_UP"
        let suffix: String
        switch (component, observed) {
        case (.flags, false): suffix = "FLAGS_POST"
        case (.key, false): suffix = "KEY_POST"
        case (.flags, true): suffix = "FLAGS_OBSERVED"
        case (.key, true): suffix = "KEY_OBSERVED"
        }
        return "\(prefix)_\(suffix)"
    }

    private static func safeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "=", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
    }

    private static func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.1f", max(0, value))
    }
}
