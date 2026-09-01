// ButtonGestureRecognizer.swift — optional multi-gesture button state machine
//
// The legacy mapping path sends a button's base action immediately. This
// recognizer is only used for buttons with an explicitly enabled gesture
// profile, and keeps its timers scoped to an active press or double-tap
// window. There is no background polling loop.

import Foundation

enum ButtonGestureEventKind: String {
    case singleTap
    case doubleTap
    case longPress
    case repeatStep

    var displayName: String {
        switch self {
        case .singleTap: return "单击"
        case .doubleTap: return "双击"
        case .longPress: return "长按"
        case .repeatStep: return "按住重复"
        }
    }
}

/// The mapping and target captured at the first edge of a gesture. Keeping
/// this context in the recognizer means a delayed single-click decision never
/// has to re-read the frontmost application or a mutable template.
struct ButtonGestureContext {
    let baseBinding: ButtonBinding
    let profile: ButtonGestureProfile
    let targetApplicationBundleIdentifier: String?
}

struct ButtonGestureEvent {
    let button: RemoteButton
    let kind: ButtonGestureEventKind
    let duration: TimeInterval
    let clickCount: Int
    let context: ButtonGestureContext
}

final class ButtonGestureRecognizer {
    static let longPressThreshold: TimeInterval = 0.35
    static let doubleTapWindow: TimeInterval = 0.25
    static let repeatInterval: TimeInterval = 0.10

    var onEvent: ((ButtonGestureEvent) -> Void)?

    private final class PressState {
        let button: RemoteButton
        let context: ButtonGestureContext
        let downAt: TimeInterval
        let isSecondTap: Bool
        var longPressFired = false
        var longPressWork: DispatchWorkItem?
        var repeatTimer: DispatchSourceTimer?

        init(
            button: RemoteButton,
            context: ButtonGestureContext,
            downAt: TimeInterval,
            isSecondTap: Bool
        ) {
            self.button = button
            self.context = context
            self.downAt = downAt
            self.isSecondTap = isSecondTap
        }

        func cancelTimers() {
            longPressWork?.cancel()
            longPressWork = nil
            repeatTimer?.cancel()
            repeatTimer = nil
        }
    }

    private final class PendingTap {
        let context: ButtonGestureContext
        let downAt: TimeInterval
        let upAt: TimeInterval
        var timeoutWork: DispatchWorkItem?

        init(
            context: ButtonGestureContext,
            downAt: TimeInterval,
            upAt: TimeInterval
        ) {
            self.context = context
            self.downAt = downAt
            self.upAt = upAt
        }

        func cancel() {
            timeoutWork?.cancel()
            timeoutWork = nil
        }
    }

    private var activePresses: [RemoteButton: PressState] = [:]
    private var pendingTaps: [RemoteButton: PendingTap] = [:]

    /// Consume an accepted HID down edge for a profile-enabled button.
    func handleDown(
        button: RemoteButton,
        context: ButtonGestureContext,
        at now: TimeInterval
    ) {
        guard context.profile.usesAdvancedGestures else { return }

        // Recover cleanly from a missed release. A new physical down edge
        // never inherits a previous hold timer or creates a second repeat
        // stream for the same button.
        activePresses[button]?.cancelTimers()
        activePresses.removeValue(forKey: button)

        var isSecondTap = false
        if let pending = pendingTaps[button] {
            if now - pending.upAt <= Self.doubleTapWindow,
               pending.context.profile.doubleTap?.isUsableGestureAction == true {
                isSecondTap = true
                pending.cancel()
                pendingTaps.removeValue(forKey: button)
                // Use the first tap's target and profile for the complete
                // double-click gesture. This locks the gesture to one scope.
                let state = PressState(
                    button: button,
                    context: pending.context,
                    downAt: now,
                    isSecondTap: true
                )
                activePresses[button] = state
                scheduleLongPressIfNeeded(state)
                return
            }

            pending.cancel()
            pendingTaps.removeValue(forKey: button)
            emit(
                button: button,
                kind: .singleTap,
                duration: max(0, pending.upAt - pending.downAt),
                clickCount: 1,
                context: pending.context
            )
        }

        let state = PressState(
            button: button,
            context: context,
            downAt: now,
            isSecondTap: isSecondTap
        )
        activePresses[button] = state
        scheduleLongPressIfNeeded(state)
    }

    /// Consume an accepted HID up edge. Single clicks are delayed only when
    /// a double-click action is configured; otherwise they remain immediate.
    func handleUp(button: RemoteButton, at now: TimeInterval) {
        guard let state = activePresses.removeValue(forKey: button) else { return }
        state.cancelTimers()

        let duration = max(0, now - state.downAt)
        if state.longPressFired {
            return
        }

        if state.isSecondTap {
            if let doubleTap = state.context.profile.doubleTap,
               doubleTap.isUsableGestureAction {
                emit(
                    button: button,
                    kind: .doubleTap,
                    duration: duration,
                    clickCount: 2,
                    context: state.context
                )
            } else {
                emit(
                    button: button,
                    kind: .singleTap,
                    duration: duration,
                    clickCount: 1,
                    context: state.context
                )
            }
            return
        }

        if let doubleTap = state.context.profile.doubleTap,
           doubleTap.isUsableGestureAction {
            let pending = PendingTap(
                context: state.context,
                downAt: state.downAt,
                upAt: now
            )
            let work = DispatchWorkItem { [weak self, weak pending] in
                guard let self, let pending,
                      self.pendingTaps[button] === pending
                else { return }
                self.pendingTaps.removeValue(forKey: button)
                self.emit(
                    button: button,
                    kind: .singleTap,
                    duration: max(0, pending.upAt - state.downAt),
                    clickCount: 1,
                    context: pending.context
                )
            }
            pending.timeoutWork = work
            pendingTaps[button] = pending
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.doubleTapWindow,
                execute: work
            )
            return
        }

        emit(
            button: button,
            kind: .singleTap,
            duration: duration,
            clickCount: 1,
            context: state.context
        )
    }

    /// Cancel all pending state on disconnect, application stop, or a
    /// recovered HID stream. Cancellation intentionally emits no action.
    func cancelAll() {
        activePresses.values.forEach { $0.cancelTimers() }
        activePresses.removeAll()
        pendingTaps.values.forEach { $0.cancel() }
        pendingTaps.removeAll()
    }

    private func scheduleLongPressIfNeeded(_ state: PressState) {
        let profile = state.context.profile
        guard profile.longPress?.isUsableGestureAction == true,
              profile.longPressBehavior != .none
        else { return }

        let work = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state,
                  self.activePresses[state.button] === state
            else { return }
            self.fireLongPress(state)
        }
        state.longPressWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.longPressThreshold,
            execute: work
        )
    }

    private func fireLongPress(_ state: PressState) {
        guard !state.longPressFired else { return }
        state.longPressFired = true
        let duration = max(
            0,
            ProcessInfo.processInfo.systemUptime - state.downAt
        )
        switch state.context.profile.longPressBehavior {
        case .none:
            return
        case .triggerOnce:
            emit(
                button: state.button,
                kind: .longPress,
                duration: duration,
                clickCount: state.isSecondTap ? 2 : 1,
                context: state.context
            )
        case .repeatWhileHeld:
            emit(
                button: state.button,
                kind: .repeatStep,
                duration: duration,
                clickCount: state.isSecondTap ? 2 : 1,
                context: state.context
            )
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(
                deadline: .now() + Self.repeatInterval,
                repeating: .milliseconds(Int(Self.repeatInterval * 1_000))
            )
            timer.setEventHandler { [weak self, weak state] in
                guard let self, let state,
                      self.activePresses[state.button] === state
                else { return }
                let duration = max(
                    0,
                    ProcessInfo.processInfo.systemUptime - state.downAt
                )
                self.emit(
                    button: state.button,
                    kind: .repeatStep,
                    duration: duration,
                    clickCount: state.isSecondTap ? 2 : 1,
                    context: state.context
                )
            }
            state.repeatTimer = timer
            timer.resume()
        }
    }

    private func emit(
        button: RemoteButton,
        kind: ButtonGestureEventKind,
        duration: TimeInterval,
        clickCount: Int,
        context: ButtonGestureContext
    ) {
        onEvent?(
            ButtonGestureEvent(
                button: button,
                kind: kind,
                duration: duration,
                clickCount: clickCount,
                context: context
            )
        )
    }
}
