import CoreAudio
import Foundation

enum RuntimeEnvironment {
    static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["REMOTE_ORBIT_UNIT_TESTING"] == "1" {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return CommandLine.arguments.contains {
            $0.contains("xctest") || $0.hasSuffix(".xctest")
        }
    }()
}

struct SystemAudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool

    var stableIdentifier: String {
        uid.isEmpty ? "device:\(id)" : uid
    }

    var isRemoteOrbit: Bool {
        SystemAudioDeviceManager.isRemoteOrbitDeviceName(name)
    }

    var isLoopback: Bool {
        SystemAudioDeviceManager.isLoopbackDeviceName(name)
    }
}

/// Reads and changes macOS's system default audio devices. The bridge's
/// virtual microphone is an input choice, while physical speakers, monitors,
/// and headphones are output choices. Loopback drivers are deliberately kept
/// out of the output menu so a virtual microphone cannot become the speaker.
enum SystemAudioDeviceManager {
    static let remoteOrbitInputName = "RemoteOrbit Mic 2ch"
    static let remoteOrbitSelection = "__remoteorbit__"
    static let preferredInputKey = "RemoteOrbit.preferredInputDevice"
    private static let cacheLock = NSLock()
    private static var cachedRemoteOrbitDeviceID: AudioDeviceID?
    private static var cachedInputDeviceIDByIdentifier: [String: AudioDeviceID] = [:]

    static func allDevices() -> [SystemAudioDevice] {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        ) == noErr else { return [] }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &ids
        ) == noErr else { return [] }

        return ids.compactMap { makeDevice(id: $0) }
    }

    static func inputDevices(from devices: [SystemAudioDevice] = allDevices()) -> [SystemAudioDevice] {
        let filtered = devices
            .filter { $0.hasInput && (!$0.isLoopback || $0.isRemoteOrbit) }
            .sorted { lhs, rhs in
                if lhs.isRemoteOrbit != rhs.isRemoteOrbit {
                    return lhs.isRemoteOrbit
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        updateCache(from: filtered)
        return filtered
    }

    static func outputDevices(from devices: [SystemAudioDevice] = allDevices()) -> [SystemAudioDevice] {
        devices
            .filter { $0.hasOutput && !$0.isLoopback }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static var defaultInputDevice: SystemAudioDevice? {
        device(for: defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice))
    }

    static var defaultInputStableIdentifier: String? {
        guard let id = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice) else {
            return nil
        }
        return stableIdentifier(for: id)
    }

    static var defaultOutputDevice: SystemAudioDevice? {
        device(for: defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice))
    }

    @discardableResult
    static func selectInput(identifier: String) -> Bool {
        let devices = inputDevices()
        guard let device = devices.first(where: { $0.stableIdentifier == identifier }) else {
            print("[AUDIO] 输入设备不可用: \(identifier)")
            return false
        }
        guard setDefaultDevice(
            device.id,
            selector: kAudioHardwarePropertyDefaultInputDevice
        ) else { return false }

        let selection = device.isRemoteOrbit ? remoteOrbitSelection : device.stableIdentifier
        UserDefaults.standard.set(selection, forKey: preferredInputKey)
        print("[AUDIO] 系统默认输入已切换: \(device.name)")
        return true
    }

    @discardableResult
    static func selectOutput(identifier: String) -> Bool {
        let devices = outputDevices()
        guard let device = devices.first(where: { $0.stableIdentifier == identifier }) else {
            print("[AUDIO] 输出设备不可用: \(identifier)")
            return false
        }
        guard setDefaultDevice(
            device.id,
            selector: kAudioHardwarePropertyDefaultOutputDevice
        ) else { return false }

        print("[AUDIO] 系统默认输出已切换: \(device.name)")
        return true
    }

    /// Restores the last explicit input choice. New installations preserve
    /// the historical bridge behavior by selecting RemoteOrbit Mic 2ch until
    /// the user picks a physical microphone from the menu.
    static func applyPreferredInputSelection() {
        if RuntimeEnvironment.isRunningTests {
            return
        }
        let preferred = UserDefaults.standard.string(forKey: preferredInputKey)
            ?? remoteOrbitSelection

        if preferred == remoteOrbitSelection,
           let cachedID = validatedCachedRemoteOrbitID() {
            if setDefaultDevice(
                cachedID,
                selector: kAudioHardwarePropertyDefaultInputDevice
            ) {
                print("[AUDIO] 已恢复系统默认输入: \(remoteOrbitInputName)")
                return
            }
        } else if preferred != remoteOrbitSelection,
                  let cachedID = validatedCachedInputID(for: preferred) {
            if setDefaultDevice(
                cachedID,
                selector: kAudioHardwarePropertyDefaultInputDevice
            ) {
                print("[AUDIO] 已恢复系统默认输入: \(preferred)")
                return
            }
        }

        let devices = inputDevices()
        let candidate: SystemAudioDevice?
        if preferred == remoteOrbitSelection {
            candidate = devices.first(where: { $0.isRemoteOrbit })
        } else {
            candidate = devices.first(where: { $0.stableIdentifier == preferred })
        }

        guard let candidate else {
            if preferred != remoteOrbitSelection,
               let remoteOrbit = devices.first(where: { $0.isRemoteOrbit }) {
                _ = setDefaultDevice(
                    remoteOrbit.id,
                    selector: kAudioHardwarePropertyDefaultInputDevice
                )
                UserDefaults.standard.set(remoteOrbitSelection, forKey: preferredInputKey)
                print("[AUDIO] 已保存的输入设备不存在，回退到: \(remoteOrbit.name)")
            } else {
                print("[AUDIO] 没有可恢复的默认输入设备")
            }
            return
        }

        if setDefaultDevice(
            candidate.id,
            selector: kAudioHardwarePropertyDefaultInputDevice
        ) {
            print("[AUDIO] 已恢复系统默认输入: \(candidate.name)")
        }
    }

    /// Makes the bridge endpoint the app-facing input for one remote-mic
    /// gesture. Do not overwrite the user's preferred input setting: the
    /// direct voice lifecycle restores that choice after the final remote
    /// output drain.
    @discardableResult
    static func selectRemoteOrbitInputForVoice() -> Bool {
        if RuntimeEnvironment.isRunningTests {
            return false
        }
        let targetID: AudioDeviceID?
        if let cachedID = validatedCachedRemoteOrbitID() {
            targetID = cachedID
        } else {
            targetID = inputDevices().first(where: { $0.isRemoteOrbit })?.id
        }
        guard let targetID else {
            print("[AUDIO] ⚠️ 遥控器语音需要 RemoteOrbit Mic 2ch，但设备当前不可用")
            return false
        }
        guard setDefaultDevice(
            targetID,
            selector: kAudioHardwarePropertyDefaultInputDevice
        ) else { return false }
        print("[AUDIO] 遥控器语音已强制使用系统输入: \(remoteOrbitInputName)")
        return true
    }

    static func displayName(for device: SystemAudioDevice) -> String {
        device.isRemoteOrbit ? "\(device.name)（遥控器/自动）" : device.name
    }

    static func isRemoteOrbitDeviceName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(remoteOrbitInputName) == .orderedSame
    }

    static func isLoopbackDeviceName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("blackhole")
            || normalized.contains("miremote")
            || normalized.contains("mi remote")
            || normalized.contains("voiceremote")
            || normalized.contains("voice remote")
            || normalized.contains("remoteorbit")
    }

    private static func device(for id: AudioDeviceID?) -> SystemAudioDevice? {
        guard let id else { return nil }
        return makeDevice(id: id)
    }

    private static func makeDevice(id deviceID: AudioDeviceID) -> SystemAudioDevice? {
        guard deviceID != 0,
              let name = stringProperty(deviceID, selector: kAudioObjectPropertyName)
        else { return nil }
        return SystemAudioDevice(
            id: deviceID,
            uid: stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "",
            name: name,
            hasInput: channelCount(deviceID, scope: kAudioObjectPropertyScopeInput) > 0,
            hasOutput: channelCount(deviceID, scope: kAudioObjectPropertyScopeOutput) > 0
        )
    }

    private static func stableIdentifier(for deviceID: AudioDeviceID) -> String {
        let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? ""
        return uid.isEmpty ? "device:\(deviceID)" : uid
    }

    private static func updateCache(from inputDevices: [SystemAudioDevice]) {
        var byIdentifier: [String: AudioDeviceID] = [:]
        byIdentifier.reserveCapacity(inputDevices.count)
        var remoteOrbitID: AudioDeviceID?
        for device in inputDevices {
            byIdentifier[device.stableIdentifier] = device.id
            if device.isRemoteOrbit {
                remoteOrbitID = device.id
            }
        }
        cacheLock.lock()
        cachedInputDeviceIDByIdentifier = byIdentifier
        cachedRemoteOrbitDeviceID = remoteOrbitID
        cacheLock.unlock()
    }

    private static func validatedCachedRemoteOrbitID() -> AudioDeviceID? {
        cacheLock.lock()
        let cached = cachedRemoteOrbitDeviceID
        cacheLock.unlock()
        guard let cached,
              let name = stringProperty(cached, selector: kAudioObjectPropertyName),
              isRemoteOrbitDeviceName(name) else {
            return nil
        }
        return cached
    }

    private static func validatedCachedInputID(for identifier: String) -> AudioDeviceID? {
        cacheLock.lock()
        let cached = cachedInputDeviceIDByIdentifier[identifier]
        cacheLock.unlock()
        guard let cached,
              stringProperty(cached, selector: kAudioObjectPropertyName) != nil,
              stableIdentifier(for: cached) == identifier,
              channelCount(cached, scope: kAudioObjectPropertyScopeInput) > 0 else {
            return nil
        }
        return cached
    }

    private static func defaultDeviceID(
        selector: AudioObjectPropertySelector
    ) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        ) == noErr,
        deviceID != 0 else { return nil }
        return deviceID
    }

    @discardableResult
    private static func setDefaultDevice(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var target = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &target
        )
        if status != noErr {
            print("[AUDIO] 切换系统音频设备失败: selector=\(selector), OSStatus=\(status)")
        }
        return status == noErr
    }

    private static func stringProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &value
        ) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func channelCount(
        _ deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &propertySize
        ) == noErr,
        propertySize >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 0 }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            rawBuffer
        ) == noErr else { return 0 }

        let bufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }
}
