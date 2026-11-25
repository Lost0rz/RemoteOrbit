import CoreAudio
import Darwin
import Foundation

enum VoiceReceiverReadiness: Equatable {
    case unsupported
    case inactive
    case listening(consumerPID: Int32, bundleID: String?)

    var isListening: Bool {
        if case .listening = self {
            return true
        }
        return false
    }

    var diagnosticFields: [String: Any] {
        switch self {
        case .unsupported:
            return [
                "supported": false,
                "state": "unsupported",
            ]
        case .inactive:
            return [
                "supported": true,
                "state": "inactive",
            ]
        case let .listening(consumerPID, bundleID):
            return [
                "supported": true,
                "state": "listening",
                "consumer_pid": consumerPID,
                "consumer_bundle_id": bundleID ?? "unknown",
            ]
        }
    }
}

struct VoiceReceiverProcessSnapshot: Equatable {
    let pid: Int32
    let bundleID: String?
    let runningInput: Bool
    let inputDeviceIDs: [UInt32]
}

enum VoiceReceiverReadinessEvaluator {
    static func evaluate(
        processes: [VoiceReceiverProcessSnapshot],
        targetDeviceID: UInt32,
        excludingPID: Int32,
        apiAvailable: Bool = true
    ) -> VoiceReceiverReadiness {
        guard apiAvailable else {
            return .unsupported
        }

        guard let consumer = processes
            .filter({
                $0.pid != excludingPID
                    && $0.runningInput
                    && $0.inputDeviceIDs.contains(targetDeviceID)
            })
            .sorted(by: { $0.pid < $1.pid })
            .first
        else {
            return .inactive
        }

        return .listening(
            consumerPID: consumer.pid,
            bundleID: consumer.bundleID
        )
    }
}

enum VoiceHUDProjection {
    static func state(
        for voiceState: VoicePressCoordinator.State,
        remoteAudioAvailable: Bool,
        receiverReadiness: VoiceReceiverReadiness
    ) -> RemoteActionHUDState? {
        switch voiceState {
        case .idle:
            return nil
        case .opening:
            return .voiceStarting
        case .streaming:
            guard remoteAudioAvailable else {
                return .voiceStarting
            }
            return receiverReadiness.isListening
                ? .recording
                : .voiceAudioReady
        case .draining:
            return .pending
        }
    }
}

/// The synchronous property reads used by CoreAudioVoiceReceiverProbe.
/// Keeping this seam separate makes the candidate-selection rules testable
/// without creating live Core Audio objects in unit tests.
protocol VoiceReceiverReadSource: AnyObject {
    func targetDeviceID(named name: String) -> AudioDeviceID?
    func processObjectIDs() -> [AudioObjectID]?
    func processPID(_ objectID: AudioObjectID) -> Int32?
    func processIsRunningInput(_ objectID: AudioObjectID) -> Bool?
    func processInputDeviceIDs(_ objectID: AudioObjectID) -> [AudioDeviceID]?
    func processBundleID(_ objectID: AudioObjectID) -> String?
}

/// Default read-only Core Audio property access. It has no listener, timer,
/// callback, or retained process-object lifecycle.
final class CoreAudioVoiceReceiverReadSource: VoiceReceiverReadSource {
    func targetDeviceID(named name: String) -> AudioDeviceID? {
        guard #available(macOS 14.2, *) else {
            return nil
        }
        return targetDeviceIDAvailable(named: name)
    }

    func processObjectIDs() -> [AudioObjectID]? {
        guard #available(macOS 14.2, *) else {
            return nil
        }
        return processObjectIDsAvailable()
    }

    func processPID(_ objectID: AudioObjectID) -> Int32? {
        guard #available(macOS 14.2, *) else {
            return nil
        }
        var pid: pid_t = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &pid
        ) == noErr else {
            return nil
        }
        return Int32(pid)
    }

    func processIsRunningInput(_ objectID: AudioObjectID) -> Bool? {
        guard #available(macOS 14.2, *) else {
            return nil
        }
        var value: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value != 0
    }

    func processInputDeviceIDs(_ objectID: AudioObjectID) -> [AudioDeviceID]? {
        guard #available(macOS 14.2, *) else {
            return nil
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyDevices,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            objectID,
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }
        guard size > 0 else {
            return []
        }
        var deviceIDs = [AudioDeviceID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else {
            return nil
        }
        return deviceIDs
    }

    func processBundleID(_ objectID: AudioObjectID) -> String? {
        guard #available(macOS 14.2, *) else {
            return nil
        }
        return readStringProperty(
            objectID: objectID,
            selector: kAudioProcessPropertyBundleID
        )
    }

    @available(macOS 14.2, *)
    private func targetDeviceIDAvailable(named name: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }
        var deviceIDs = [AudioDeviceID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else {
            return nil
        }
        return deviceIDs.first(where: {
            readStringProperty(
                objectID: $0,
                selector: kAudioObjectPropertyName
            )?.caseInsensitiveCompare(name) == .orderedSame
        })
    }

    @available(macOS 14.2, *)
    private func processObjectIDsAvailable() -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }
        guard size > 0 else {
            return []
        }
        var objectIDs = [AudioObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &objectIDs
        ) == noErr else {
            return nil
        }
        return objectIDs
    }

    @available(macOS 14.2, *)
    private func readStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }
}

protocol VoiceReceiverReadinessProbe: AnyObject {
    func beginGeneration()
    func sample() -> VoiceReceiverReadiness
}

/// One synchronous, fail-closed snapshot of external input consumption.
final class CoreAudioVoiceReceiverProbe: VoiceReceiverReadinessProbe {
    private let source: VoiceReceiverReadSource
    private let excludedPID: Int32
    private let targetDeviceName: String
    private var cachedTargetDeviceID: AudioDeviceID?
    private var cachedPIDs: [AudioObjectID: Int32] = [:]
    private var cachedBundleIDs: [AudioObjectID: String] = [:]
    private var lastListeningObjectID: AudioObjectID?

    init(
        excludedPID: Int32 = Int32(getpid()),
        targetDeviceName: String = "RemoteOrbit Mic 2ch",
        source: VoiceReceiverReadSource = CoreAudioVoiceReceiverReadSource()
    ) {
        self.excludedPID = excludedPID
        self.targetDeviceName = targetDeviceName
        self.source = source
    }

    func beginGeneration() {
        cachedTargetDeviceID = nil
        cachedPIDs.removeAll(keepingCapacity: true)
        cachedBundleIDs.removeAll(keepingCapacity: true)
        lastListeningObjectID = nil
    }

    func sample() -> VoiceReceiverReadiness {
        guard #available(macOS 14.2, *) else {
            return .unsupported
        }

        guard let targetDeviceID = cachedTargetDeviceID
                ?? source.targetDeviceID(named: targetDeviceName)
        else {
            return .unsupported
        }
        cachedTargetDeviceID = targetDeviceID

        guard let processObjectIDs = source.processObjectIDs() else {
            return .unsupported
        }

        if cachedPIDs.count > processObjectIDs.count {
            let liveSet = Set(processObjectIDs)
            cachedPIDs = cachedPIDs.filter { liveSet.contains($0.key) }
            cachedBundleIDs = cachedBundleIDs.filter { liveSet.contains($0.key) }
        }

        var checkedLastObjectID: AudioObjectID?
        if let lastID = lastListeningObjectID {
            if processObjectIDs.contains(lastID),
               let listening = inspectCandidate(lastID, targetDeviceID: targetDeviceID) {
                return listening
            }
            lastListeningObjectID = nil
            checkedLastObjectID = lastID
        }

        for objectID in processObjectIDs {
            if objectID == checkedLastObjectID {
                continue
            }
            if let listening = inspectCandidate(objectID, targetDeviceID: targetDeviceID) {
                lastListeningObjectID = objectID
                return listening
            }
        }

        return .inactive
    }

    private func inspectCandidate(
        _ objectID: AudioObjectID,
        targetDeviceID: AudioDeviceID
    ) -> VoiceReceiverReadiness? {
        let pid: Int32
        if let cachedPID = cachedPIDs[objectID] {
            pid = cachedPID
        } else if let fetchedPID = source.processPID(objectID) {
            cachedPIDs[objectID] = fetchedPID
            pid = fetchedPID
        } else {
            return nil
        }
        if pid == excludedPID {
            return nil
        }
        guard let runningInput = source.processIsRunningInput(objectID) else {
            return nil
        }
        if !runningInput {
            return nil
        }
        guard let inputDeviceIDs = source.processInputDeviceIDs(objectID),
              inputDeviceIDs.contains(targetDeviceID)
        else {
            return nil
        }

        let bundleID: String?
        if let cachedBundle = cachedBundleIDs[objectID] {
            bundleID = cachedBundle
        } else if let fetchedBundle = source.processBundleID(objectID) {
            cachedBundleIDs[objectID] = fetchedBundle
            bundleID = fetchedBundle
        } else {
            bundleID = nil
        }
        return .listening(
            consumerPID: pid,
            bundleID: bundleID
        )
    }
}

protocol VoiceReceiverReadinessTimer: AnyObject {
    var eventHandler: (() -> Void)? { get set }

    func schedule(
        deadline: DispatchTime,
        repeating: DispatchTimeInterval,
        leeway: DispatchTimeInterval
    )
    func resume()
    func cancel()
}

private final class DispatchSourceVoiceReceiverReadinessTimer: VoiceReceiverReadinessTimer {
    private let source: DispatchSourceTimer
    private var handler: (() -> Void)?

    init(queue: DispatchQueue) {
        source = DispatchSource.makeTimerSource(queue: queue)
    }

    var eventHandler: (() -> Void)? {
        get { handler }
        set {
            handler = newValue
            source.setEventHandler(handler: newValue)
        }
    }

    func schedule(
        deadline: DispatchTime,
        repeating: DispatchTimeInterval,
        leeway: DispatchTimeInterval
    ) {
        source.schedule(deadline: deadline, repeating: repeating, leeway: leeway)
    }

    func resume() {
        source.resume()
    }

    func cancel() {
        source.cancel()
    }
}

/// Session-scoped scheduler for receiver readiness. It owns one serial queue,
/// one optional timer, and one synchronous sample at a time.
final class VoiceReceiverReadinessMonitor {
    typealias StateHandler = (VoiceReceiverReadiness) -> Void
    typealias TimerFactory = (DispatchQueue) -> VoiceReceiverReadinessTimer

    private let queue: DispatchQueue
    private let probe: VoiceReceiverReadinessProbe
    private let timerFactory: TimerFactory
    private let timerInterval: DispatchTimeInterval
    private let timerLeeway: DispatchTimeInterval
    private let steadyListeningTimerInterval: DispatchTimeInterval
    private let steadyListeningTimerLeeway: DispatchTimeInterval
    private var timer: VoiceReceiverReadinessTimer?
    private var generation: UInt64 = 0
    private var isActive = false
    private var usingSteadyInterval = false
    private var state: VoiceReceiverReadiness?

    var onStateChanged: StateHandler?

    init(
        probe: VoiceReceiverReadinessProbe = CoreAudioVoiceReceiverProbe(),
        queue: DispatchQueue = DispatchQueue(
            label: "com.lost0rz.RemoteOrbit.voice-receiver-readiness",
            qos: .utility
        ),
        timerFactory: @escaping TimerFactory = {
            DispatchSourceVoiceReceiverReadinessTimer(queue: $0)
        },
        timerInterval: DispatchTimeInterval = .milliseconds(25),
        timerLeeway: DispatchTimeInterval = .milliseconds(5),
        steadyListeningTimerInterval: DispatchTimeInterval = .milliseconds(125),
        steadyListeningTimerLeeway: DispatchTimeInterval = .milliseconds(20)
    ) {
        self.probe = probe
        self.queue = queue
        self.timerFactory = timerFactory
        self.timerInterval = timerInterval
        self.timerLeeway = timerLeeway
        self.steadyListeningTimerInterval = steadyListeningTimerInterval
        self.steadyListeningTimerLeeway = steadyListeningTimerLeeway
    }

    func activate() {
        queue.async { [weak self] in
            self?.activateOnQueue()
        }
    }

    func deactivate() {
        queue.async { [weak self] in
            self?.deactivateOnQueue()
        }
    }

    private func activateOnQueue() {
        guard !isActive else {
            return
        }

        isActive = true
        generation &+= 1
        let activeGeneration = generation
        probe.beginGeneration()
        let initialSample = probe.sample()
        publish(initialSample)
        usingSteadyInterval = initialSample.isListening

        let newTimer = timerFactory(queue)
        newTimer.eventHandler = { [weak self] in
            self?.handleTimerTick(generation: activeGeneration)
        }
        let interval = usingSteadyInterval ? steadyListeningTimerInterval : timerInterval
        let leeway = usingSteadyInterval ? steadyListeningTimerLeeway : timerLeeway
        newTimer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: leeway
        )
        timer = newTimer
        newTimer.resume()
    }

    private func deactivateOnQueue() {
        guard isActive || timer != nil else {
            return
        }

        isActive = false
        usingSteadyInterval = false
        generation &+= 1
        timer?.cancel()
        timer = nil
        publish(.inactive)
    }

    /// The DispatchSourceTimer targets `queue`, so the handler samples
    /// directly here. There is deliberately no extra dispatch or work-item
    /// per tick, and the serial queue prevents overlapping samples.
    private func handleTimerTick(generation timerGeneration: UInt64) {
        guard isActive, timerGeneration == generation else {
            return
        }
        let sampled = probe.sample()
        publish(sampled)
        if sampled.isListening != usingSteadyInterval {
            usingSteadyInterval = sampled.isListening
            let interval = usingSteadyInterval ? steadyListeningTimerInterval : timerInterval
            let leeway = usingSteadyInterval ? steadyListeningTimerLeeway : timerLeeway
            timer?.schedule(
                deadline: .now() + interval,
                repeating: interval,
                leeway: leeway
            )
        }
    }

    private func publish(_ newState: VoiceReceiverReadiness) {
        guard state != newState else {
            return
        }
        state = newState
        let handler = onStateChanged
        DispatchQueue.main.async {
            handler?(newState)
        }
    }

    // Deterministic test seams. They execute on the same serial queue as the
    // production timer and expose only bounded scheduler state.
    var currentStateForTesting: VoiceReceiverReadiness {
        queue.sync { state ?? .inactive }
    }

    func waitForIdleForTesting() {
        queue.sync {}
    }

    var activeTimerCountForTesting: Int {
        queue.sync { timer == nil ? 0 : 1 }
    }

    var currentGenerationForTesting: UInt64 {
        queue.sync { generation }
    }

    func invokeTimerGenerationForTesting(_ timerGeneration: UInt64) {
        queue.sync {
            handleTimerTick(generation: timerGeneration)
        }
    }
}
