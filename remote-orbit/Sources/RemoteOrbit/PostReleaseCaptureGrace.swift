import Foundation

/// Owns the bounded interval between a physical voice-key release and the
/// remote ATVV close command. The owner and generation guard keep a delayed
/// release from acting on a newer gesture after cancellation or re-press.
final class PostReleaseCaptureGraceController {
    static let defaultDuration: TimeInterval = 1.0

    let duration: TimeInterval
    var onExpire: ((String, UInt64) -> Void)?

    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?
    private var activeSessionID: String?
    private var generation: UInt64 = 0

    init(
        duration: TimeInterval = PostReleaseCaptureGraceController.defaultDuration,
        queue: DispatchQueue = .main
    ) {
        self.duration = duration
        self.queue = queue
    }

    @discardableResult
    func start(sessionID: String) -> UInt64 {
        workItem?.cancel()
        generation &+= 1
        let token = generation
        activeSessionID = sessionID

        let work = DispatchWorkItem { [weak self] in
            _ = self?.expire(sessionID: sessionID, generation: token)
        }
        workItem = work
        queue.asyncAfter(
            deadline: .now() + duration,
            execute: work
        )
        return token
    }

    @discardableResult
    func cancel(sessionID: String? = nil) -> Bool {
        guard let activeSessionID,
              sessionID == nil || sessionID == activeSessionID else {
            return false
        }
        workItem?.cancel()
        workItem = nil
        self.activeSessionID = nil
        return true
    }

    @discardableResult
    func expireForTesting(sessionID: String, generation: UInt64) -> Bool {
        expire(sessionID: sessionID, generation: generation)
    }

    var isWaitingForTesting: Bool {
        activeSessionID != nil
    }

    var isWaiting: Bool {
        activeSessionID != nil
    }

    var currentSessionID: String? {
        activeSessionID
    }

    var activeSessionIDForTesting: String? {
        activeSessionID
    }

    var generationForTesting: UInt64 {
        generation
    }

    var configuredDurationForTesting: TimeInterval {
        duration
    }

    private func expire(sessionID: String, generation: UInt64) -> Bool {
        guard self.generation == generation,
              activeSessionID == sessionID else {
            return false
        }
        workItem = nil
        activeSessionID = nil
        onExpire?(sessionID, generation)
        return true
    }
}
