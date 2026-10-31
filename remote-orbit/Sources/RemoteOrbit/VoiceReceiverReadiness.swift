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
        case .opening, .pending:
            return .voiceStarting
        case .holding, .streaming:
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

final class VoiceReceiverReadinessObserver {
    typealias StateHandler = (VoiceReceiverReadiness) -> Void

    private struct ListenerRegistration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let listener: AudioObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(
        label: "com.lost0rz.RemoteOrbit.voice-receiver-readiness",
        qos: .utility
    )
    private let stateLock = NSLock()
    private let excludedPID: Int32
    private let targetDeviceName: String
    private var started = false
    private var targetDeviceID: AudioDeviceID?
    private var processObjectIDs: [AudioObjectID] = []
    private var systemListenerAddress: AudioObjectPropertyAddress?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [ListenerRegistration] = []
    private var state: VoiceReceiverReadiness = .unsupported

    var onStateChanged: StateHandler?

    init(
        excludedPID: Int32 = Int32(getpid()),
        targetDeviceName: String = "RemoteOrbit Mic 2ch"
    ) {
        self.excludedPID = excludedPID
        self.targetDeviceName = targetDeviceName
    }

    var currentState: VoiceReceiverReadiness {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.sync { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() {
        guard !started else { return }
        started = true

        guard #available(macOS 14.0, *) else {
            publish(.unsupported)
            return
        }

        guard let deviceID = findTargetDeviceID() else {
            publish(.unsupported)
            return
        }
        targetDeviceID = deviceID

        installSystemProcessListListener()
        refreshProcessObjects()
    }

    private func stopOnQueue() {
        guard started else { return }
        removeProcessListeners()
        if let listener = systemListener,
           var address = systemListenerAddress {
            _ = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue,
                listener
            )
        }
        systemListener = nil
        systemListenerAddress = nil
        processObjectIDs.removeAll()
        started = false
    }

    @available(macOS 14.0, *)
    private func installSystemProcessListListener() {
        guard systemListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshFromListener()
        }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        ) == noErr else {
            publish(.unsupported)
            return
        }
        systemListenerAddress = address
        systemListener = listener
    }

    private func refreshFromListener() {
        queue.async { [weak self] in
            guard let self else { return }
            guard #available(macOS 14.0, *) else {
                self.publish(.unsupported)
                return
            }
            self.refreshProcessObjects()
        }
    }

    @available(macOS 14.0, *)
    private func refreshProcessObjects() {
        guard let objectIDs = readProcessObjectIDs(),
              let targetDeviceID
        else {
            publish(.unsupported)
            return
        }

        removeProcessListeners()
        processObjectIDs = objectIDs
        for objectID in objectIDs {
            installProcessListeners(for: objectID)
        }
        publish(evaluateCurrentProcesses(targetDeviceID: targetDeviceID))
    }

    @available(macOS 14.0, *)
    private func installProcessListeners(for objectID: AudioObjectID) {
        let addresses = [
            AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyDevices,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            ),
        ]

        for address in addresses {
            var listenerAddress = address
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.refreshFromListener()
            }
            guard AudioObjectAddPropertyListenerBlock(
                objectID,
                &listenerAddress,
                queue,
                listener
            ) == noErr else {
                continue
            }
            processListeners.append(
                ListenerRegistration(
                    objectID: objectID,
                    address: address,
                    listener: listener
                )
            )
        }
    }

    private func removeProcessListeners() {
        for registration in processListeners {
            var address = registration.address
            _ = AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &address,
                queue,
                registration.listener
            )
        }
        processListeners.removeAll()
    }

    @available(macOS 14.0, *)
    private func evaluateCurrentProcesses(
        targetDeviceID: AudioDeviceID
    ) -> VoiceReceiverReadiness {
        let snapshots = processObjectIDs.compactMap {
            readProcessSnapshot($0)
        }
        return VoiceReceiverReadinessEvaluator.evaluate(
            processes: snapshots,
            targetDeviceID: targetDeviceID,
            excludingPID: excludedPID
        )
    }

    @available(macOS 14.0, *)
    private func readProcessObjectIDs() -> [AudioObjectID]? {
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

    @available(macOS 14.0, *)
    private func readProcessSnapshot(
        _ objectID: AudioObjectID
    ) -> VoiceReceiverProcessSnapshot? {
        var pid: pid_t = 0
        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidSize = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &pidAddress,
            0,
            nil,
            &pidSize,
            &pid
        ) == noErr else {
            return nil
        }

        var runningInput: UInt32 = 0
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &runningAddress,
            0,
            nil,
            &runningSize,
            &runningInput
        ) == noErr else {
            return nil
        }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyDevices,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var devicesSize: UInt32 = 0
        var inputDeviceIDs: [AudioDeviceID] = []
        if AudioObjectGetPropertyDataSize(
            objectID,
            &devicesAddress,
            0,
            nil,
            &devicesSize
        ) == noErr, devicesSize > 0 {
            inputDeviceIDs = [AudioDeviceID](
                repeating: 0,
                count: Int(devicesSize) / MemoryLayout<AudioDeviceID>.size
            )
            if AudioObjectGetPropertyData(
                objectID,
                &devicesAddress,
                0,
                nil,
                &devicesSize,
                &inputDeviceIDs
            ) != noErr {
                inputDeviceIDs = []
            }
        }

        return VoiceReceiverProcessSnapshot(
            pid: Int32(pid),
            bundleID: readStringProperty(
                objectID: objectID,
                selector: kAudioProcessPropertyBundleID
            ),
            runningInput: runningInput != 0,
            inputDeviceIDs: inputDeviceIDs
        )
    }

    private func findTargetDeviceID() -> AudioDeviceID? {
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
            readStringProperty(objectID: $0, selector: kAudioObjectPropertyName)?
                .caseInsensitiveCompare(targetDeviceName) == .orderedSame
        })
    }

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

    private func publish(_ newState: VoiceReceiverReadiness) {
        stateLock.lock()
        let changed = state != newState
        state = newState
        stateLock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(newState)
        }
    }
}
