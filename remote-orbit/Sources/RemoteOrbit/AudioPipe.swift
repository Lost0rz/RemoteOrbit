// AudioPipe: selects a local physical mic or decoded ATVV PCM and plays
// that source into RemoteOrbit Mic 2ch. Doubao sees one stable USB microphone.
//
// Local physical mic → AVCaptureSession ─┐
//                                        ├→ CoreAudio IOProc → RemoteOrbit Mic 2ch
// ATVV Int16 PCM ────────────────────────┘   (remote wins while key is held)

import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMedia
import Foundation

final class AudioPipe: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = AudioPipe()

    // RemoteOrbit owns a fresh audio namespace. The installer moves old
    // project drivers into a recoverable backup, so runtime never silently
    // attaches to an inherited legacy endpoint.
    private static let targetDeviceNames = ["RemoteOrbit Mic 2ch"]
    private static let outputSampleRate: Double = 48_000
    private static let outputChannels: AVAudioChannelCount = 2
    /// RemoteOrbit voice input is remote-only. Keep the virtual microphone
    /// silent while idle or after a short tap; never fall back to the Mac's
    /// built-in or external microphone.
    private static let localMicrophoneEnabled = false
    /// The remote's decoded ATVV signal is intentionally quiet. Add roughly
    /// +26 dB and use a soft limiter so a nearby speaker does not hard-clip.
    private static let remoteGain: Float = 20.0

    private let captureSession = AVCaptureSession()
    private let captureQueue = DispatchQueue(
        label: "com.lost0rz.RemoteOrbit.capture",
        qos: .userInteractive
    )

    private let stateLock = NSLock()
    private var remoteActive = false
    private var remoteCandidateActive = false
    // ATVV starts sending PCM before VoicePressCoordinator crosses the hold
    // guard. Keep only a short pre-roll so the first syllable is not lost.
    private var pendingRemotePrebuffer: [Int16] = []
    private let remotePrebufferLimit = 16_000 / 2
    private var outputDeviceID: AudioDeviceID?
    private var outputIOProcID: AudioDeviceIOProcID?
    private var outputDeviceName: String?
    private var pendingOutput: [Float] = []
    private var pendingOutputIndex = 0
    private var scheduledMacBuffers = 0
    private var scheduledRemoteBuffers = 0
    private var scheduledPeak: Float = 0
    private var renderCallbackCount = 0
    private var renderedFrames = 0
    private var renderedPeak: Float = 0
    private var diagnosticsTimer: Timer?

    private override init() {
        super.init()

        if let output = Self.findOutputDevice() {
            startOutputDevice(output.id, name: output.name)
            SystemAudioDeviceManager.applyPreferredInputSelection()
        } else {
            print(
                "[AUDIO] ⚠️ 找不到语音输出设备；已查找: "
                    + Self.targetDeviceNames.joined(separator: ", ")
                    + "，请确认 RemoteOrbitAudio.driver 已安装"
            )
        }

        if ProcessInfo.processInfo.environment["REMOTE_ORBIT_DIAGNOSTICS"] == "1" ||
            AppStorage.loggingEnabled {
            startDiagnosticsTimer()
        }
        if Self.localMicrophoneEnabled {
            requestLocalMicAccess()
        } else {
            print("[AUDIO] 本机物理麦克风采集已关闭；仅接收遥控器麦克风")
        }
    }

    // MARK: - public

    static var installedOutputDeviceName: String? {
        findOutputDevice()?.name
    }

    func restartOutputDevice() {
        stop()
        if let output = Self.findOutputDevice() {
            startOutputDevice(output.id, name: output.name)
            SystemAudioDeviceManager.applyPreferredInputSelection()
        } else {
            print("[AUDIO] 补装后仍未发现语音输出设备")
        }
    }

    func beginRemoteCandidate() {
        stateLock.lock()
        guard !remoteCandidateActive else {
            stateLock.unlock()
            return
        }
        remoteCandidateActive = true
        pendingRemotePrebuffer.removeAll(keepingCapacity: true)
        stateLock.unlock()
    }

    func endRemoteCandidate() {
        stateLock.lock()
        remoteCandidateActive = false
        pendingRemotePrebuffer.removeAll(keepingCapacity: true)
        stateLock.unlock()
    }

    func feed(samples: [Int16], inputSampleRate: Double = 16_000) {
        guard !samples.isEmpty else { return }
        stateLock.lock()
        let active = remoteActive
        if !active {
            if remoteCandidateActive {
                pendingRemotePrebuffer.append(contentsOf: samples)
                if pendingRemotePrebuffer.count > remotePrebufferLimit {
                    pendingRemotePrebuffer.removeFirst(
                        pendingRemotePrebuffer.count - remotePrebufferLimit
                    )
                }
            }
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        let floatSamples = samples.map { sample -> Float in
            let amplified = Float(sample) / 32768.0 * Self.remoteGain
            return Float(tanh(Double(amplified)))
        }
        schedule(
            monoSamples: floatSamples,
            sampleRate: inputSampleRate,
            expectedRemoteMode: true
        )
    }

    func setRemoteActive(_ active: Bool) {
        var prebuffer: [Int16] = []
        stateLock.lock()
        remoteActive = active
        pendingOutput.removeAll(keepingCapacity: true)
        pendingOutputIndex = 0
        if active {
            prebuffer = pendingRemotePrebuffer
            pendingRemotePrebuffer.removeAll(keepingCapacity: true)
        } else {
            pendingRemotePrebuffer.removeAll(keepingCapacity: true)
        }
        stateLock.unlock()
        print(active
            ? "[AUDIO] 输入切换 → 遥控器麦克风"
            : "[AUDIO] 输入切换 → 无输入（等待遥控器）")

        if active, !prebuffer.isEmpty {
            print("[AUDIO] 远程语音预缓冲已补入: \(prebuffer.count) samples")
            let floatSamples = prebuffer.map { sample -> Float in
                let amplified = Float(sample) / 32768.0 * Self.remoteGain
                return Float(tanh(Double(amplified)))
            }
            schedule(
                monoSamples: floatSamples,
                sampleRate: 16_000,
                expectedRemoteMode: true
            )
        }
    }

    /// Release the HAL callback before the process exits. BlackHole-derived
    /// drivers can leave coreaudiod waiting on a stale client when the process
    /// is killed while an IOProc is still registered.
    func stop() {
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil

        if let deviceID = outputDeviceID, let ioProcID = outputIOProcID {
            let stopStatus = AudioDeviceStop(deviceID, ioProcID)
            let destroyStatus = AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            print(
                "[AUDIO] \(outputDeviceName ?? "语音输出") IOProc 已释放: " +
                "stop=\(stopStatus), destroy=\(destroyStatus)"
            )
        }
        outputIOProcID = nil
        outputDeviceID = nil
        outputDeviceName = nil
        endRemoteCandidate()
    }

    // MARK: - local physical microphone capture

    private func requestLocalMicAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startLocalMicCapture()
        case .notDetermined:
            print("[AUDIO] 请求本机麦克风权限…")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startLocalMicCapture()
                    } else {
                        print("[AUDIO] ⚠️ 本机麦克风权限被拒绝")
                    }
                }
            }
        default:
            print("[AUDIO] ⚠️ 没有本机麦克风权限；遥控器麦克风仍可使用")
        }
    }

    private func startLocalMicCapture() {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInMicrophone]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.external)
        } else {
            deviceTypes.append(.externalUnknown)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )
        // On current macOS versions this discovery type returns CoreAudio
        // inputs beyond a single built-in microphone. Include external audio
        // devices explicitly as well, then prefer the system default when it
        // is physical. The fallback still avoids feeding any bridge/loopback
        // device back into RemoteOrbit Mic.
        let devices = discovery.devices
        func isLoopback(_ candidate: AVCaptureDevice) -> Bool {
            Self.isLoopbackDeviceName(candidate.localizedName)
        }
        let defaultDevice = AVCaptureDevice.default(for: .audio)
        let device = defaultDevice.flatMap { isLoopback($0) ? nil : $0 }
            ?? devices.first { !isLoopback($0) }
        guard let device else {
            let names = devices.map(\.localizedName).joined(separator: ", ")
            print("[AUDIO] ⚠️ 找不到可用物理麦克风；发现: \(names)")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureAudioDataOutput()
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
            ]
            output.setSampleBufferDelegate(self, queue: captureQueue)

            captureSession.beginConfiguration()
            guard captureSession.canAddInput(input), captureSession.canAddOutput(output) else {
                captureSession.commitConfiguration()
                print("[AUDIO] ⚠️ 无法建立本机麦克风采集会话")
                return
            }
            captureSession.addInput(input)
            captureSession.addOutput(output)
            captureSession.commitConfiguration()

            captureQueue.async { [weak self] in
                guard let self else { return }
                self.captureSession.startRunning()
                print(
                    "[AUDIO] 本机麦克风采集已启动: " +
                    "\(device.localizedName), running=\(self.captureSession.isRunning)"
                )
            }
        } catch {
            print("[AUDIO] ⚠️ 本机麦克风采集失败: \(error.localizedDescription)")
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard Self.localMicrophoneEnabled,
              !isRemoteActive,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription
              ),
              streamDescription.pointee.mFormatID == kAudioFormatLinearPCM,
              streamDescription.pointee.mBitsPerChannel == 32,
              streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        else { return }

        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        guard byteCount >= MemoryLayout<Float>.size else { return }
        var data = Data(count: byteCount)
        let copyStatus = data.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: bytes.baseAddress!
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else { return }

        let channels = max(1, Int(streamDescription.pointee.mChannelsPerFrame))
        let floats: [Float] = data.withUnsafeBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: Float.self)
            if channels == 1 {
                return Array(values)
            }
            let frameCount = values.count / channels
            return (0..<frameCount).map { frame in
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += values[frame * channels + channel]
                }
                return sum / Float(channels)
            }
        }

        schedule(
            monoSamples: floats,
            sampleRate: streamDescription.pointee.mSampleRate,
            expectedRemoteMode: false
        )
    }

    // MARK: - playback

    private var isRemoteActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return remoteActive
    }

    private func schedule(
        monoSamples: [Float],
        sampleRate: Double,
        expectedRemoteMode: Bool
    ) {
        guard !monoSamples.isEmpty, sampleRate > 0 else { return }
        let resampled = Self.resample(
            monoSamples,
            from: sampleRate,
            to: Self.outputSampleRate
        )
        guard !resampled.isEmpty else { return }

        stateLock.lock()
        guard remoteActive == expectedRemoteMode else {
            stateLock.unlock()
            return
        }
        compactOutputBufferIfNeeded()
        pendingOutput.append(contentsOf: resampled)
        if expectedRemoteMode {
            scheduledRemoteBuffers += 1
        } else {
            scheduledMacBuffers += 1
        }
        scheduledPeak = max(
            scheduledPeak,
            resampled.reduce(0) { max($0, abs($1)) }
        )
        stateLock.unlock()
    }

    private static func resample(
        _ input: [Float],
        from inputRate: Double,
        to outputRate: Double
    ) -> [Float] {
        if abs(inputRate - outputRate) < 1 {
            return input
        }
        let ratio = outputRate / inputRate
        let outputCount = max(1, Int((Double(input.count) * ratio).rounded(.down)))
        var output = [Float](repeating: 0, count: outputCount)
        for index in 0..<outputCount {
            let position = Double(index) / ratio
            let lower = min(Int(position), input.count - 1)
            let upper = min(lower + 1, input.count - 1)
            let fraction = Float(position - Double(lower))
            output[index] = input[lower] + (input[upper] - input[lower]) * fraction
        }
        return output
    }

    // MARK: - CoreAudio direct output

    private func startOutputDevice(_ deviceID: AudioDeviceID, name: String) {
        var ioProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            deviceID,
            nil
        ) { [weak self] _, _, _, outputData, _ in
            self?.render(outputData)
        }
        guard createStatus == noErr, let ioProcID else {
            print("[AUDIO] ⚠️ 创建 RemoteOrbit IOProc 失败: OSStatus=\(createStatus)")
            return
        }

        let startStatus = AudioDeviceStart(deviceID, ioProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            print("[AUDIO] ⚠️ 启动 RemoteOrbit IOProc 失败: OSStatus=\(startStatus)")
            return
        }

        outputDeviceID = deviceID
        outputIOProcID = ioProcID
        outputDeviceName = name
        print("[AUDIO] \(name) IOProc 已启动: id=\(deviceID), 48000 Hz stereo")

    }

    private func render(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard let first = buffers.first else { return }
        let firstChannels = max(1, Int(first.mNumberChannels))
        let frameCount = Int(first.mDataByteSize) /
            MemoryLayout<Float>.size /
            firstChannels
        guard frameCount > 0 else { return }

        var mono = [Float](repeating: 0, count: frameCount)
        stateLock.lock()
        let available = pendingOutput.count - pendingOutputIndex
        if available > 0 {
            let take = min(frameCount, available)
            let start = pendingOutputIndex
            let end = start + take
            mono.replaceSubrange(
                0..<take,
                with: pendingOutput[start..<end]
            )
            renderedFrames += take
            renderedPeak = max(
                renderedPeak,
                pendingOutput[start..<end].reduce(0) { max($0, abs($1)) }
            )
            pendingOutputIndex = end
            compactOutputBufferIfNeeded()
        }
        renderCallbackCount += 1
        stateLock.unlock()

        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let channelCount = max(1, Int(buffer.mNumberChannels))
            let writableFrames = min(
                frameCount,
                Int(buffer.mDataByteSize) /
                    MemoryLayout<Float>.size /
                    channelCount
            )
            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<writableFrames {
                for channel in 0..<channelCount {
                    output[frame * channelCount + channel] = mono[frame]
                }
            }
        }
    }

    private func compactOutputBufferIfNeeded() {
        if pendingOutputIndex > 4_096 {
            pendingOutput.removeFirst(pendingOutputIndex)
            pendingOutputIndex = 0
        }
        let maximumQueuedFrames = Int(Self.outputSampleRate * 2)
        let available = pendingOutput.count - pendingOutputIndex
        if available > maximumQueuedFrames {
            pendingOutputIndex += available - maximumQueuedFrames
        }
    }

    private static func findOutputDevice() -> (id: AudioDeviceID, name: String)? {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &propertySize
        ) == noErr else { return nil }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &propertySize, &devices
        ) == noErr else { return nil }

        for id in devices where id != 0 {
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(
                id, &nameAddress, 0, nil, &nameSize, &nameRef
            ) == noErr else { continue }
            guard let name = nameRef?.takeRetainedValue() as String? else { continue }
            if let targetName = targetDeviceNames.first(where: {
                name.caseInsensitiveCompare($0) == .orderedSame
            }) {
                return (id: id, name: targetName)
            }
        }
        return nil
    }

    private static func isLoopbackDeviceName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        // AVCaptureDevice.DiscoverySession(.builtInMicrophone) can expose
        // HAL loopbacks as capture candidates. In a namespace cutover the
        // old MiRemoteV/VoiceRemote devices may still be registered beside
        // RemoteOrbit, so name-checking only the new driver is insufficient:
        // the stale endpoint can become the default and produce a silent
        // short-press capture path.
        return normalized.contains("remoteorbit")
            || normalized.contains("blackhole")
            || normalized.contains("miremote")
            || normalized.contains("mi remote")
            || normalized.contains("voiceremote")
            || normalized.contains("voice remote")
    }

    // MARK: - diagnostics

    private func startDiagnosticsTimer() {
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            self.stateLock.lock()
            let mode = self.remoteActive ? "remote" : "mac"
            let macBuffers = self.scheduledMacBuffers
            let remoteBuffers = self.scheduledRemoteBuffers
            let peak = self.scheduledPeak
            let renders = self.renderCallbackCount
            let renderedFrames = self.renderedFrames
            let renderedPeak = self.renderedPeak
            let queuedFrames = self.pendingOutput.count - self.pendingOutputIndex
            self.scheduledMacBuffers = 0
            self.scheduledRemoteBuffers = 0
            self.scheduledPeak = 0
            self.renderCallbackCount = 0
            self.renderedFrames = 0
            self.renderedPeak = 0
            self.stateLock.unlock()
            print(String(
                format: "[AUDIO-METER] mode=%@ macBuffers=%d remoteBuffers=%d scheduledPeak=%.4f renders=%d renderedFrames=%d renderedPeak=%.4f queuedFrames=%d",
                mode,
                macBuffers,
                remoteBuffers,
                peak,
                renders,
                renderedFrames,
                renderedPeak,
                queuedFrames
            ))
        }
    }
}
