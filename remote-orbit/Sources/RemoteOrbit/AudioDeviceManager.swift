import CoreAudio
import Foundation

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

        return ids.compactMap { deviceID in
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
    }

    static func inputDevices(from devices: [SystemAudioDevice] = allDevices()) -> [SystemAudioDevice] {
        devices
            .filter { $0.hasInput && (!$0.isLoopback || $0.isRemoteOrbit) }
            .sorted { lhs, rhs in
                if lhs.isRemoteOrbit != rhs.isRemoteOrbit {
                    return lhs.isRemoteOrbit
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
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
        let devices = inputDevices()
        let preferred = UserDefaults.standard.string(forKey: preferredInputKey)
            ?? remoteOrbitSelection
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
        guard let remoteOrbit = inputDevices().first(where: { $0.isRemoteOrbit }) else {
            print("[AUDIO] ⚠️ 遥控器语音需要 RemoteOrbit Mic 2ch，但设备当前不可用")
            return false
        }
        guard setDefaultDevice(
            remoteOrbit.id,
            selector: kAudioHardwarePropertyDefaultInputDevice
        ) else { return false }
        print("[AUDIO] 遥控器语音已强制使用系统输入: \(remoteOrbit.name)")
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
        return allDevices().first(where: { $0.id == id })
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
