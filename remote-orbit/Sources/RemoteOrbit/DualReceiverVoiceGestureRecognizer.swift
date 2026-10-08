import Foundation

/// Classifies the microphone button's direct-hold and tap-then-hold gestures.
/// It only reports a selected receiver or no action; trigger edges and voice
/// transport remain owned by the existing voice transaction path.
final class DualReceiverVoiceGestureRecognizer {
    enum Receiver: Equatable {
        case a
        case b
    }

    enum Event: Equatable {
        case classified(gestureID: UUID, receiver: Receiver)
        case noAction(gestureID: UUID)
    }

    enum StateForTesting: Equatable {
        case idle
        case firstPressPending
        case awaitingSecondPress
        case secondPressPending
        case activeA
        case activeB
    }

    typealias Cancellation = () -> Void
    typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Cancellation

    static let longPressThreshold: TimeInterval = 0.350
    static let doubleTapWindow: TimeInterval = 0.300

    var onEvent: ((Event) -> Void)?

    private struct Press {
        let gestureID: UUID
        let downAt: TimeInterval
        let generation: UUID
        var cancelTimer: Cancellation?
    }

    private struct WaitingForSecond {
        let gestureID: UUID
        let firstUpAt: TimeInterval
        let generation: UUID
        var cancelTimer: Cancellation?
    }

    private enum State {
        case idle
        case firstPressPending(Press)
        case awaitingSecondPress(WaitingForSecond)
        case secondPressPending(Press)
        case active(gestureID: UUID, receiver: Receiver)
    }

    private let monotonicNow: () -> TimeInterval
    private let schedule: Schedule
    private var state: State = .idle

    init(
        monotonicNow: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        schedule: @escaping Schedule = DualReceiverVoiceGestureRecognizer.dispatchSchedule
    ) {
        self.monotonicNow = monotonicNow
        self.schedule = schedule
    }

    var stateForTesting: StateForTesting {
        switch state {
        case .idle:
            return .idle
        case .firstPressPending:
            return .firstPressPending
        case .awaitingSecondPress:
            return .awaitingSecondPress
        case .secondPressPending:
            return .secondPressPending
        case .active(_, receiver: .a):
            return .activeA
        case .active(_, receiver: .b):
            return .activeB
        }
    }

    var isBusy: Bool {
        if case .idle = state { return false }
        return true
    }

    var currentGestureID: UUID? {
        switch state {
        case .idle:
            return nil
        case let .firstPressPending(press), let .secondPressPending(press):
            return press.gestureID
        case let .awaitingSecondPress(waiting):
            return waiting.gestureID
        case let .active(gestureID, _):
            return gestureID
        }
    }

    /// Returns the owning gesture ID when this down edge starts or continues a
    /// recognized gesture. Duplicate downs while held are ignored.
    @discardableResult
    func handleDown(at timestamp: TimeInterval) -> UUID? {
        switch state {
        case .idle:
            return beginFirstPress(at: timestamp)

        case let .awaitingSecondPress(waiting):
            let offset = timestamp - waiting.firstUpAt
            guard offset >= 0, offset <= Self.doubleTapWindow else {
                waiting.cancelTimer?()
                state = .idle
                onEvent?(.noAction(gestureID: waiting.gestureID))
                return beginFirstPress(at: timestamp)
            }

            waiting.cancelTimer?()
            let press = Press(
                gestureID: waiting.gestureID,
                downAt: timestamp,
                generation: UUID(),
                cancelTimer: nil
            )
            state = .secondPressPending(press)
            scheduleHold(for: press, receiver: .b, isSecondPress: true)
            return waiting.gestureID

        case .firstPressPending, .secondPressPending, .active:
            return nil
        }
    }

    /// Returns the owning gesture ID for a matched release edge.
    @discardableResult
    func handleUp(at timestamp: TimeInterval) -> UUID? {
        switch state {
        case let .firstPressPending(press):
            press.cancelTimer?()
            if timestamp - press.downAt >= Self.longPressThreshold {
                state = .idle
                onEvent?(.classified(gestureID: press.gestureID, receiver: .a))
            } else {
                let waiting = WaitingForSecond(
                    gestureID: press.gestureID,
                    firstUpAt: timestamp,
                    generation: UUID(),
                    cancelTimer: nil
                )
                state = .awaitingSecondPress(waiting)
                scheduleSecondPressTimeout(for: waiting)
            }
            return press.gestureID

        case let .secondPressPending(press):
            press.cancelTimer?()
            state = .idle
            if timestamp - press.downAt >= Self.longPressThreshold {
                onEvent?(.classified(gestureID: press.gestureID, receiver: .b))
            } else {
                onEvent?(.noAction(gestureID: press.gestureID))
            }
            return press.gestureID

        case let .active(gestureID, _):
            state = .idle
            return gestureID

        case .idle, .awaitingSecondPress:
            return nil
        }
    }

    /// Cancels pending timing and ownership without classifying the gesture.
    func cancel() {
        switch state {
        case let .firstPressPending(press), let .secondPressPending(press):
            press.cancelTimer?()
        case let .awaitingSecondPress(waiting):
            waiting.cancelTimer?()
        case .idle, .active:
            break
        }
        state = .idle
    }

    private func beginFirstPress(at timestamp: TimeInterval) -> UUID {
        let press = Press(
            gestureID: UUID(),
            downAt: timestamp,
            generation: UUID(),
            cancelTimer: nil
        )
        state = .firstPressPending(press)
        scheduleHold(for: press, receiver: .a, isSecondPress: false)
        return press.gestureID
    }

    private func scheduleHold(
        for press: Press,
        receiver: Receiver,
        isSecondPress: Bool
    ) {
        let deadline = press.downAt + Self.longPressThreshold
        let delay = max(0, deadline - monotonicNow())
        let cancelTimer = schedule(delay) { [weak self] in
            self?.holdDeadlineReached(
                gestureID: press.gestureID,
                generation: press.generation,
                downAt: press.downAt,
                receiver: receiver,
                isSecondPress: isSecondPress
            )
        }
        updatePressCancellation(
            generation: press.generation,
            isSecondPress: isSecondPress,
            cancelTimer: cancelTimer
        )
    }

    private func holdDeadlineReached(
        gestureID: UUID,
        generation: UUID,
        downAt: TimeInterval,
        receiver: Receiver,
        isSecondPress: Bool
    ) {
        guard currentPressMatches(
            gestureID: gestureID,
            generation: generation,
            isSecondPress: isSecondPress
        ) else { return }

        let remaining = downAt + Self.longPressThreshold - monotonicNow()
        guard remaining <= 0 else {
            let press = Press(
                gestureID: gestureID,
                downAt: downAt,
                generation: generation,
                cancelTimer: nil
            )
            scheduleHold(for: press, receiver: receiver, isSecondPress: isSecondPress)
            return
        }

        state = .active(gestureID: gestureID, receiver: receiver)
        onEvent?(.classified(gestureID: gestureID, receiver: receiver))
    }

    private func scheduleSecondPressTimeout(for waiting: WaitingForSecond) {
        let deadline = waiting.firstUpAt + Self.doubleTapWindow
        let delay = max(0, deadline - monotonicNow())
        let cancelTimer = schedule(delay) { [weak self] in
            self?.secondPressDeadlineReached(
                gestureID: waiting.gestureID,
                generation: waiting.generation,
                deadline: deadline
            )
        }
        guard case var .awaitingSecondPress(current) = state,
              current.generation == waiting.generation
        else {
            cancelTimer()
            return
        }
        current.cancelTimer = cancelTimer
        state = .awaitingSecondPress(current)
    }

    private func secondPressDeadlineReached(
        gestureID: UUID,
        generation: UUID,
        deadline: TimeInterval
    ) {
        guard case let .awaitingSecondPress(waiting) = state,
              waiting.gestureID == gestureID,
              waiting.generation == generation
        else { return }

        let remaining = deadline - monotonicNow()
        guard remaining < 0 else {
            let cancelTimer = schedule(max(remaining, 0.000_001)) { [weak self] in
                self?.secondPressDeadlineReached(
                    gestureID: gestureID,
                    generation: generation,
                    deadline: deadline
                )
            }
            guard case var .awaitingSecondPress(current) = state,
                  current.generation == generation
            else {
                cancelTimer()
                return
            }
            current.cancelTimer = cancelTimer
            state = .awaitingSecondPress(current)
            return
        }

        state = .idle
        onEvent?(.noAction(gestureID: gestureID))
    }

    private func currentPressMatches(
        gestureID: UUID,
        generation: UUID,
        isSecondPress: Bool
    ) -> Bool {
        switch state {
        case let .firstPressPending(press):
            return !isSecondPress
                && press.gestureID == gestureID
                && press.generation == generation
        case let .secondPressPending(press):
            return isSecondPress
                && press.gestureID == gestureID
                && press.generation == generation
        case .idle, .awaitingSecondPress, .active:
            return false
        }
    }

    private func updatePressCancellation(
        generation: UUID,
        isSecondPress: Bool,
        cancelTimer: @escaping Cancellation
    ) {
        if isSecondPress,
           case var .secondPressPending(press) = state,
           press.generation == generation {
            press.cancelTimer = cancelTimer
            state = .secondPressPending(press)
        } else if !isSecondPress,
                  case var .firstPressPending(press) = state,
                  press.generation == generation {
            press.cancelTimer = cancelTimer
            state = .firstPressPending(press)
        } else {
            cancelTimer()
        }
    }

    private static func dispatchSchedule(
        after delay: TimeInterval,
        work: @escaping () -> Void
    ) -> Cancellation {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return { item.cancel() }
    }
}
