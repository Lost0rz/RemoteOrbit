// AudioPipe sends decoded ATVV PCM into RemoteOrbit Mic 2ch. Doubao sees one
// stable USB microphone: the Mac/external microphone is opened only when the
// configured short voice input needs it, while the remote microphone takes
// over exclusively during a classified long press.
//
// ATVV Int16 PCM → CoreAudio IOProc → RemoteOrbit Mic 2ch

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
    /// Structural transport capacity only. The ring starts empty; this is
    /// not a startup reserve or a jitter/playout threshold.
    static let pcmRingCapacityFrames = 96_000
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
    /// This is a demand signal, not a permanent app capability. A disabled
    /// short slot must not even open AVCapture, and a remote long press stops
    /// the running session before accepting ATVV samples.
    private var localMicrophoneCaptureRequested = false
    private var localMicrophonePermissionRequestInFlight = false
    private var pendingLocalMicrophoneReady: (() -> Void)?
    // ATVV starts sending PCM before VoicePressCoordinator crosses the hold
    // guard. Keep only a short pre-roll so the first syllable is not lost.
    private var pendingRemotePrebuffer: [Int16] = []
    private let remotePrebufferLimit = 16_000 / 2
    private var outputDeviceID: AudioDeviceID?
    private var outputIOProcID: AudioDeviceIOProcID?
    private var outputDeviceName: String?
    private var outputDeviceReady = false
    private let outputRing = FixedCapacityPCMFrameRing(
        capacity: AudioPipe.pcmRingCapacityFrames
    )
    private let playoutReserve = AudioPipePlayoutReserve()
    private let realtimeDiagnostics = AudioPipeRealtimeDiagnostics()
    private var remoteOutputDrainWaiter: (() -> Void)?
    private let outputDrainSignal = DispatchSemaphore(value: 0)
    private let outputDrainMonitorQueue = DispatchQueue(
        label: "com.lost0rz.RemoteOrbit.audio-drain",
        qos: .userInteractive
    )
    private var outputDrainMonitorStarted = false
    private var scheduledMacBuffers = 0
    private var scheduledRemoteBuffers = 0
    private var scheduledPeak: Float = 0
    private var lastIdleMeterAt: TimeInterval = 0
    private var diagnosticsCumulative = AudioPipeDiagnosticsCounters()
    private var diagnosticsWindow = AudioPipeDiagnosticsCounters()
    private var diagnosticsTimer: Timer?
    private var remoteDiagnosticsActive = false
    private var remoteDiagnosticsSawActiveRoute = false
    private var longTermPrimaryTrace = FixedCapacityObservationTrace(
        frontCapacity: 64,
        recentCapacity: 512,
        incidentProducer: .audioPipe
    )
    private var longTermSecondaryTrace = FixedCapacityObservationTrace(
        frontCapacity: 64,
        recentCapacity: 512,
        incidentProducer: .audioPipe
    )
    private var longTermPrimaryTraceIsActive = true
    private var mainQueueResponsivenessProbe: MainQueueResponsivenessProbe?
    private var continuityRenderLedger: AudioContinuityRenderLedger?
    private var lastRemoteSubmittedMonotonicNanoseconds: UInt64?
    private var diagnosticStreamIdentity: UInt64 = 0
    private var diagnosticObservationSequence: UInt64 = 0

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
    }

    // MARK: - public

    static var installedOutputDeviceName: String? {
        findOutputDevice()?.name
    }

    /// A device can exist in CoreAudio while this process has failed to
    /// create/start its IOProc. Expose the process-level readiness separately
    /// so the menu bar does not report a green voice path in that state.
    var isOutputReady: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return outputDeviceReady
    }

    /// Number of output frames still waiting for the CoreAudio render
    /// callback. This is used to sequence the final Option-up safely.
    var queuedOutputFrames: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return outputRing.queuedFrames
    }

    func beginRemoteAudioDiagnostics(
        continuityContext: AudioContinuityCaptureContext? = nil
    ) {
        realtimeDiagnostics.endDiagnosticsAndWait()
        DiagnosticOutputBoundaryClock.shared.reset()
        // AUDIO_START can precede HID. Establish the shared observability
        // generation before this producer can publish any pre-HID evidence;
        // a later HID binding is intentionally not a reset boundary.
        LongTermIncidentCoordinator.shared.beginCaptureIfNeeded()
        let nextContinuityLedger = continuityContext.map {
            AudioContinuityRenderLedger(capture: $0)
        }
        let nextMainQueueProbe = MainQueueResponsivenessProbe(
            sampleIntervalNanoseconds: 50_000_000,
            onMaterialLag: { [weak self] in
                self?.markLongTermMaterialAnomaly(trigger: .mainQueueLag)
            }
        )
        let previousMainQueueProbe: MainQueueResponsivenessProbe?
        stateLock.lock()
        flushRealtimeEvidenceLocked()
        previousMainQueueProbe = mainQueueResponsivenessProbe
        if longTermPrimaryTraceIsActive {
            longTermPrimaryTrace.reset()
        } else {
            longTermSecondaryTrace.reset()
        }
        diagnosticStreamIdentity = 0
        diagnosticObservationSequence = 0
        mainQueueResponsivenessProbe = nextMainQueueProbe
        let currentDepth = outputRing.queuedRemoteFrames
        remoteDiagnosticsActive = true
        remoteDiagnosticsSawActiveRoute = remoteActive
        continuityRenderLedger = nextContinuityLedger
        diagnosticsCumulative.reset(currentQueueDepthFrames: currentDepth)
        diagnosticsWindow.reset(currentQueueDepthFrames: currentDepth)
        realtimeDiagnostics.beginDiagnostics(remoteActive: remoteActive)
        stateLock.unlock()
        _ = previousMainQueueProbe?.stop()
        nextMainQueueProbe.start()
    }

    /// Bind a live AUDIO_START capture to the matching HID session without
    /// scanning or reallocating its fixed-capacity render storage. A capture
    /// can be bound only once and only by its exact transport identity.
    @discardableResult
    func bindRemoteAudioDiagnostics(
        captureID: UUID,
        session: AudioContinuitySessionContext
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard remoteDiagnosticsActive else { return false }
        return continuityRenderLedger?.bind(
            captureID: captureID,
            session: session
        ) ?? false
    }

    func setDiagnosticStreamIdentity(_ streamIdentity: UInt64) {
        stateLock.lock()
        diagnosticStreamIdentity = streamIdentity
        stateLock.unlock()
    }

    func endRemoteAudioDiagnostics() -> AudioContinuityRenderSnapshot? {
        realtimeDiagnostics.endDiagnosticsAndWait()
        stateLock.lock()
        flushRealtimeEvidenceLocked()
        let detachedContinuityLedger = continuityRenderLedger
        continuityRenderLedger = nil
        remoteDiagnosticsActive = false
        remoteDiagnosticsSawActiveRoute = false
        stateLock.unlock()
        return detachedContinuityLedger?.snapshot()
    }

    func takeLongTermObservationSnapshot() -> LongTermAudioObservationSnapshot {
        let detachedTrace: FixedCapacityObservationTrace
        let probe: MainQueueResponsivenessProbe?
        stateLock.lock()
        flushRealtimeEvidenceLocked()
        if longTermPrimaryTraceIsActive {
            detachedTrace = longTermPrimaryTrace
            longTermPrimaryTrace = longTermSecondaryTrace
            longTermSecondaryTrace = detachedTrace
        } else {
            detachedTrace = longTermSecondaryTrace
            longTermSecondaryTrace = detachedTrace
        }
        var synchronizedTrace = detachedTrace
        synchronizedTrace.synchronizeIncidentWithCoordinator()
        longTermPrimaryTrace.reset()
        longTermPrimaryTraceIsActive = true
        probe = mainQueueResponsivenessProbe
        mainQueueResponsivenessProbe = nil
        stateLock.unlock()

        return LongTermAudioObservationSnapshot(
            trace: synchronizedTrace.snapshot(),
            mainQueueLag: probe?.stop() ?? .empty
        )
    }

    func takeAudioDiagnosticsSnapshot(
        resettingWindow: Bool = false
    ) -> AudioPipeDiagnosticsSnapshot {
        stateLock.lock()
        flushRealtimeEvidenceLocked()
        let totalDepth = outputRing.queuedFrames
        let currentDepth = outputRing.queuedRemoteFrames
        let counters = resettingWindow ? diagnosticsWindow : diagnosticsCumulative
        let realtimeSnapshot = realtimeDiagnostics.snapshot(reset: resettingWindow)
        var mergedCounters = counters
        mergedCounters.mergeRealtime(realtimeSnapshot)
        let snapshot = mergedCounters.snapshot(
            remoteActive: remoteActive,
            currentQueueDepthFrames: currentDepth,
            audioQueueDepthFrames: totalDepth,
            pendingRemoteFrames: outputRing.queuedRemoteFrames,
            sampleRate: Self.outputSampleRate,
            reserve: playoutReserve.snapshot(
                at: P1A4MonotonicClock.nowNanoseconds()
            ),
            lastRemoteSubmittedMonotonicNanoseconds:
                lastRemoteSubmittedMonotonicNanoseconds,
            lastRemoteRenderedMonotonicNanoseconds:
                realtimeSnapshot.lastRemoteRenderedMonotonicNanoseconds
        )
        if resettingWindow {
            diagnosticsWindow.reset(currentQueueDepthFrames: currentDepth)
        }
        stateLock.unlock()
        return snapshot
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

    /// Re-open the virtual microphone only when the process is currently not
    /// ready. This is intentionally a no-op during normal operation, but lets
    /// the menu's “刷新设备列表” action recover a driver that appeared after
    /// launch without rebuilding the app or restarting CoreAudio again.
    func recoverOutputDeviceIfNeeded() {
        guard !isOutputReady,
              let output = Self.findOutputDevice() else { return }
        startOutputDevice(output.id, name: output.name)
        SystemAudioDeviceManager.applyPreferredInputSelection()
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

    /// True only when the remote route is inactive and no output frames are
    /// waiting for the CoreAudio render callback.
    static func isOutputDrained(remoteActive: Bool, queuedFrames: Int) -> Bool {
        !remoteActive && queuedFrames <= 0
    }

    /// Complete on the main queue after already queued output has rendered.
    /// The caller owns session identity validation for the completion.
    func waitForOutputDrain(completion: @escaping () -> Void) {
        stateLock.lock()
        let queuedFrames = outputRing.queuedFrames
        let drained = Self.isOutputDrained(
            remoteActive: remoteActive,
            queuedFrames: queuedFrames
        )
        if !drained {
            remoteOutputDrainWaiter = completion
            realtimeDiagnostics.setDrainWaiterRequested(true)
        }
        stateLock.unlock()

        if drained {
            realtimeDiagnostics.setDrainWaiterRequested(false)
            VoiceTimingLogger.recordQueueEmpty(
                timestampNanoseconds: P1A4MonotonicClock.nowNanoseconds()
            )
            DispatchQueue.main.async(execute: completion)
        } else {
            startOutputDrainMonitorIfNeeded()
        }
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

    @discardableResult
    func setRemoteActive(_ active: Bool) -> Int {
        var prebuffer: [Int16] = []
        stateLock.lock()
        remoteActive = active
        if active {
            // A new voice session must never inherit a previous session's
            // samples. On deactivation, however, keep the already queued
            // frames alive so the BLE tail-drain window can render them.
            AudioPipeRemoteActivationTransition.perform(
                withdrawRealtimeActive: {
                    realtimeDiagnostics.setRemoteActive(false)
                },
                clearPriorDrainWaiter: {
                    remoteOutputDrainWaiter = nil
                    realtimeDiagnostics.setDrainWaiterRequested(false)
                },
                resetOutputRing: {
                    outputRing.reset()
                },
                resetPlayoutReserve: {
                    playoutReserve.reset(at: P1A4MonotonicClock.nowNanoseconds())
                },
                resetSessionBookkeeping: {
                    lastRemoteSubmittedMonotonicNanoseconds = nil
                    prebuffer = pendingRemotePrebuffer
                    pendingRemotePrebuffer.removeAll(keepingCapacity: true)
                },
                publishRealtimeActive: {
                    realtimeDiagnostics.setRemoteActive(true)
                    if remoteDiagnosticsActive {
                        remoteDiagnosticsSawActiveRoute = true
                    }
                }
            )
        } else {
            realtimeDiagnostics.setRemoteActive(false)
            pendingRemotePrebuffer.removeAll(keepingCapacity: true)
        }
        stateLock.unlock()
        DiagnosticRuntimeHealthRegistry.shared.setBool("audio_pipe_remote_active", active)
        if active {
            // A target app can cache the physical microphone selected in its
            // own audio session. Re-assert the bridge as the app-facing input
            // at the exact remote-voice transition, before the synthetic
            // Option-down opens the speech UI. This does not change the
            // user's saved preferred input and is restored for short input.
            _ = SystemAudioDeviceManager.selectRemoteOrbitInputForVoice()
            DiagnosticRuntimeHealthRegistry.shared.recordSelectedInputIdentity(
                SystemAudioDeviceManager.defaultInputDevice?.stableIdentifier
            )
            // The remote-only path must not leave the physical microphone
            // open. `captureOutput` also rejects late callbacks, but stopping
            // the session is required to release the device privacy claim.
            stopLocalMicCapture()
        }
        print(active
            ? "[AUDIO] 输入切换 → 遥控器麦克风"
            : "[AUDIO] 输入切换 → 等待下一次外部语音输入")

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

        if !active, isLocalMicrophoneCaptureRequested {
            // Return to the input selected for the short external-mic action
            // once a remote hold has ended.
            SystemAudioDeviceManager.applyPreferredInputSelection()
        }
        return prebuffer.count
    }

    /// Enable or disable the physical/external microphone path used by the
    /// short voice action. This deliberately does not follow `remoteActive`:
    /// a configured short action may keep the local capture session ready
    /// between taps, but a long press always stops it through setRemoteActive.
    func setLocalMicrophoneCaptureEnabled(
        _ enabled: Bool,
        onReady: (() -> Void)? = nil
    ) {
        stateLock.lock()
        localMicrophoneCaptureRequested = enabled
        realtimeDiagnostics.setLocalMicrophoneActive(enabled)
        if !enabled {
            localMicrophonePermissionRequestInFlight = false
            pendingLocalMicrophoneReady = nil
        }
        stateLock.unlock()

        if enabled {
            // The short action uses the user's selected physical source. If a
            // previous long hold temporarily forced RemoteOrbit Mic 2ch,
            // restore that preference before opening AVCapture.
            SystemAudioDeviceManager.applyPreferredInputSelection()
            requestLocalMicAccess(onReady: onReady)
        } else {
            stopLocalMicCapture()
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
        stateLock.lock()
        outputDeviceReady = false
        outputRing.reset()
        realtimeDiagnostics.setRemoteActive(false)
        realtimeDiagnostics.setLocalMicrophoneActive(false)
        realtimeDiagnostics.setDrainWaiterRequested(false)
        remoteOutputDrainWaiter = nil
        localMicrophoneCaptureRequested = false
        localMicrophonePermissionRequestInFlight = false
        pendingLocalMicrophoneReady = nil
        stateLock.unlock()
        DiagnosticRuntimeHealthRegistry.shared.markOutputDevice(ready: false, identity: nil)
        stopLocalMicCapture()
        endRemoteCandidate()
    }

    // MARK: - local physical microphone capture

    private func requestLocalMicAccess(onReady: (() -> Void)? = nil) {
        guard isLocalMicrophoneCaptureRequested, !isRemoteActive else {
            notifyLocalMicrophoneReady(onReady)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startLocalMicCapture(onReady: onReady)
        case .notDetermined:
            stateLock.lock()
            guard localMicrophoneCaptureRequested else {
                stateLock.unlock()
                notifyLocalMicrophoneReady(onReady)
                return
            }
            if localMicrophonePermissionRequestInFlight {
                pendingLocalMicrophoneReady = onReady
                stateLock.unlock()
                return
            }
            localMicrophonePermissionRequestInFlight = true
            pendingLocalMicrophoneReady = onReady
            stateLock.unlock()
            print("[AUDIO] 请求本机麦克风权限…")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                self.stateLock.lock()
                self.localMicrophonePermissionRequestInFlight = false
                let shouldStart = granted && self.localMicrophoneCaptureRequested
                let ready = self.pendingLocalMicrophoneReady
                self.pendingLocalMicrophoneReady = nil
                self.stateLock.unlock()
                guard shouldStart else {
                    if !granted {
                        print("[AUDIO] ⚠️ 本机麦克风权限被拒绝")
                    }
                    self.notifyLocalMicrophoneReady(ready)
                    return
                }
                self.startLocalMicCapture(onReady: ready)
            }
        default:
            print("[AUDIO] ⚠️ 没有本机麦克风权限；遥控器麦克风仍可使用")
            notifyLocalMicrophoneReady(onReady)
        }
    }

    private func startLocalMicCapture(onReady: (() -> Void)? = nil) {
        guard isLocalMicrophoneCaptureRequested, !isRemoteActive else {
            notifyLocalMicrophoneReady(onReady)
            return
        }
        captureQueue.async { [weak self] in
            self?.configureAndStartLocalMicCaptureOnQueue(onReady: onReady)
        }
    }

    /// AVCaptureSession start/stop/configuration all run on captureQueue. This
    /// prevents a long-press transition from racing a pending session start.
    private func configureAndStartLocalMicCaptureOnQueue(onReady: (() -> Void)? = nil) {
        guard isLocalMicrophoneCaptureRequested, !isRemoteActive else {
            notifyLocalMicrophoneReady(onReady)
            return
        }
        if captureSession.isRunning {
            notifyLocalMicrophoneReady(onReady)
            return
        }

        if !captureSession.inputs.isEmpty {
            captureSession.startRunning()
            print("[AUDIO] 本机麦克风采集已恢复, running=\(captureSession.isRunning)")
            notifyLocalMicrophoneReady(onReady)
            return
        }

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
            notifyLocalMicrophoneReady(onReady)
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
                notifyLocalMicrophoneReady(onReady)
                return
            }
            captureSession.addInput(input)
            captureSession.addOutput(output)
            captureSession.commitConfiguration()

            guard isLocalMicrophoneCaptureRequested, !isRemoteActive else {
                removeLocalMicCaptureConfigurationOnQueue()
                notifyLocalMicrophoneReady(onReady)
                return
            }
            captureSession.startRunning()
            print(
                "[AUDIO] 本机麦克风采集已启动: " +
                "\(device.localizedName), running=\(captureSession.isRunning)"
            )
            notifyLocalMicrophoneReady(onReady)
        } catch {
            print("[AUDIO] ⚠️ 本机麦克风采集失败: \(error.localizedDescription)")
            notifyLocalMicrophoneReady(onReady)
        }
    }

    private func notifyLocalMicrophoneReady(_ completion: (() -> Void)?) {
        guard let completion else { return }
        DispatchQueue.main.async(execute: completion)
    }

    private func stopLocalMicCapture() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            guard self.captureSession.isRunning
                || !self.captureSession.inputs.isEmpty
                || !self.captureSession.outputs.isEmpty else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.removeLocalMicCaptureConfigurationOnQueue()
            print("[AUDIO] 本机麦克风采集已停止")
        }
    }

    private func removeLocalMicCaptureConfigurationOnQueue() {
        guard !captureSession.inputs.isEmpty || !captureSession.outputs.isEmpty else { return }
        captureSession.beginConfiguration()
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        captureSession.commitConfiguration()
    }

    private var isLocalMicrophoneCaptureRequested: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return localMicrophoneCaptureRequested
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isLocalMicrophoneCaptureRequested,
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
        let remoteQueueBeforeSubmission = outputRing.queuedRemoteFrames
        let writeResult = outputRing.write(
            resampled,
            source: expectedRemoteMode ? .remote : .local
        )
        if expectedRemoteMode {
            scheduledRemoteBuffers += 1
            if writeResult.acceptedFrames > 0, remoteDiagnosticsActive {
                diagnosticsCumulative.recordSubmittedRemoteFrames(
                    writeResult.acceptedFrames
                )
                diagnosticsWindow.recordSubmittedRemoteFrames(
                    writeResult.acceptedFrames
                )
            }
            if writeResult.droppedFrames > 0, remoteDiagnosticsActive {
                diagnosticsCumulative.recordOverflow(writeResult.droppedFrames)
                diagnosticsWindow.recordOverflow(writeResult.droppedFrames)
                if VoiceTimingLogger.continuityEvidenceEnabled {
                    continuityRenderLedger?.recordOverflow(
                        timestampNanoseconds: P1A4MonotonicClock.nowNanoseconds(),
                        frames: writeResult.droppedFrames
                    )
                }
            }
            if writeResult.acceptedFrames > 0 {
                let submissionTimestamp = P1A4MonotonicClock.nowNanoseconds()
                lastRemoteSubmittedMonotonicNanoseconds = submissionTimestamp
                if VoiceTimingLogger.p1A5Enabled {
                    VoiceTimingLogger.recordIfAbsent(
                        "F4_first_pcm_submitted",
                        timestampNanoseconds: submissionTimestamp
                    )
                    if VoiceTimingLogger.hasEvent("F6_first_voiced_pcm_decoded") {
                        VoiceTimingLogger.recordIfAbsent(
                            "F7_first_voiced_pcm_submitted",
                            timestampNanoseconds: submissionTimestamp
                        )
                    }
                }
                if remoteDiagnosticsActive {
                    appendLongTermObservationLocked(
                        LongTermObservationPoint(
                            timestampNanoseconds: submissionTimestamp,
                            kind: .pcmSubmitted,
                            requestedFrames: UInt64(writeResult.acceptedFrames),
                            filledFrames: UInt64(writeResult.acceptedFrames),
                            unfilledFrames: 0,
                            queueDepthFrames: UInt64(
                                max(0, writeResult.remoteQueueDepthAfterFrames)
                            ),
                            byteOrSampleCount: UInt64(writeResult.acceptedFrames),
                            marker: .active,
                            queueDepthBeforeFrames: UInt64(
                                max(0, remoteQueueBeforeSubmission)
                            )
                        )
                    )
                    if VoiceTimingLogger.continuityEvidenceEnabled {
                        continuityRenderLedger?.recordSubmitted(
                            timestampNanoseconds: submissionTimestamp,
                            frames: writeResult.acceptedFrames,
                            queueDepthFrames: writeResult.remoteQueueDepthAfterFrames
                        )
                    }
                }
            }
        } else {
            scheduledMacBuffers += 1
        }
        scheduledPeak = max(
            scheduledPeak,
            resampled.reduce(0) { max($0, abs($1)) }
        )
        recordQueueDepthLocked(outputRing.queuedRemoteFrames)
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
            DiagnosticRuntimeHealthRegistry.shared.markOutputDevice(ready: false, identity: name)
            print("[AUDIO] ⚠️ 创建 RemoteOrbit IOProc 失败: OSStatus=\(createStatus)")
            return
        }

        let startStatus = AudioDeviceStart(deviceID, ioProcID)
        guard startStatus == noErr else {
            DiagnosticRuntimeHealthRegistry.shared.markOutputDevice(ready: false, identity: name)
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            print("[AUDIO] ⚠️ 启动 RemoteOrbit IOProc 失败: OSStatus=\(startStatus)")
            return
        }

        stateLock.lock()
        outputDeviceID = deviceID
        outputIOProcID = ioProcID
        outputDeviceName = name
        outputDeviceReady = true
        stateLock.unlock()
        DiagnosticRuntimeHealthRegistry.shared.markOutputDevice(ready: true, identity: name)
        print("[AUDIO] \(name) IOProc 已启动: id=\(deviceID), 48000 Hz stereo")

    }

    func render(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard let first = buffers.first else { return }
        let firstChannels = max(1, Int(first.mNumberChannels))
        let frameCount = Int(first.mDataByteSize) /
            MemoryLayout<Float>.size /
            firstChannels
        guard frameCount > 0 else { return }

        let remoteActive = realtimeDiagnostics.currentRemoteActive()
        let localMicrophoneActive = realtimeDiagnostics.currentLocalMicrophoneActive()
        let remoteWasActive = realtimeDiagnostics.currentRemoteWasActive()
        let diagnosticsActive = realtimeDiagnostics.beginRenderDiagnosticsIfActive()
        let renderTimestamp = P1A4MonotonicClock.nowNanoseconds()
        let reserveDecision = playoutReserve.decision(
            remoteActive: remoteActive,
            queuedFrames: outputRing.queuedRemoteFrames,
            now: renderTimestamp
        )
        let readResult: AudioPipePCMReadResult
        if reserveDecision == .wait {
            readResult = outputRing.writeReserveSilence(
                into: outputData,
                requestedFrames: frameCount
            )
        } else {
            readResult = outputRing.read(
                into: outputData,
                requestedFrames: frameCount
            )
        }
        let renderAccounting = AudioPipeRenderAccounting.measure(
            requestedFrames: frameCount,
            availableRemoteFrames: readResult.remoteQueueDepthBeforeFrames,
            pendingRemoteFrames: readResult.remoteQueueDepthBeforeFrames,
            remoteActive: remoteActive,
            remoteWasActive: remoteWasActive,
            localMicrophoneActive: localMicrophoneActive,
            reserveWaiting: reserveDecision == .wait
        )
        realtimeDiagnostics.recordMeter(
            filledFrames: readResult.filledFrames,
            peak: readResult.peak
        )
        if diagnosticsActive {
            realtimeDiagnostics.recordRender(
                renderAccounting,
                requestedFrames: frameCount,
                readResult: readResult,
                remoteWasActive: remoteWasActive,
                timestampNanoseconds: renderTimestamp
            )
            realtimeDiagnostics.endRenderDiagnostics()
        }

        if diagnosticsActive,
           readResult.remoteFramesConsumed > 0,
           readResult.peak > 0 {
            DiagnosticOutputBoundaryClock.shared.record(
                timestampNanoseconds: renderTimestamp
            )
        }
        if !remoteActive,
           readResult.queueDepthAfterFrames == 0,
           realtimeDiagnostics.hasDrainWaiterRequested() {
            outputDrainSignal.signal()
        }
    }

    private func recordQueueDepthLocked(_ pendingRemoteFrames: Int) {
        guard remoteDiagnosticsActive else { return }
        diagnosticsCumulative.recordQueueDepth(pendingRemoteFrames)
        diagnosticsWindow.recordQueueDepth(pendingRemoteFrames)
    }

    private func flushRealtimeEvidenceLocked() {
        realtimeDiagnostics.drainObservations { [weak self] observation in
            guard let self else { return }
            let marker = self.longTermMarker(for: observation.marker)
            switch observation.kind {
            case .render:
                self.appendLongTermObservationLocked(
                    LongTermObservationPoint(
                        timestampNanoseconds: observation.timestampNanoseconds,
                        kind: .render,
                        requestedFrames: UInt64(max(0, observation.requestedFrames)),
                        filledFrames: UInt64(max(0, observation.filledFrames)),
                        unfilledFrames: UInt64(max(0, observation.unfilledFrames)),
                        queueDepthFrames: UInt64(max(0, observation.queueDepthAfterFrames)),
                        byteOrSampleCount: UInt64(max(0, observation.byteOrSampleCount)),
                        marker: marker,
                        queueDepthBeforeFrames: UInt64(
                            max(0, observation.queueDepthBeforeFrames)
                        )
                    )
                )
                if VoiceTimingLogger.continuityEvidenceEnabled {
                    self.continuityRenderLedger?.recordRender(
                        timestampNanoseconds: observation.timestampNanoseconds,
                        accounting: self.renderAccounting(for: observation),
                        queueDepthBefore: observation.queueDepthBeforeFrames,
                        queueDepthAfter: observation.queueDepthAfterFrames
                    )
                }
            case .queueStarvation:
                self.appendLongTermObservationLocked(
                    LongTermObservationPoint(
                        timestampNanoseconds: observation.timestampNanoseconds,
                        kind: .queueStarvation,
                        requestedFrames: UInt64(max(0, observation.requestedFrames)),
                        filledFrames: UInt64(max(0, observation.filledFrames)),
                        unfilledFrames: UInt64(max(0, observation.unfilledFrames)),
                        queueDepthFrames: UInt64(max(0, observation.queueDepthAfterFrames)),
                        byteOrSampleCount: UInt64(max(0, observation.byteOrSampleCount)),
                        marker: marker,
                        queueDepthBeforeFrames: UInt64(
                            max(0, observation.queueDepthBeforeFrames)
                        )
                    )
                )
                if observation.byteOrSampleCount > 0 {
                    self.markLongTermMaterialAnomalyLocked(
                        trigger: .renderStarvation,
                        timestampNanoseconds: observation.timestampNanoseconds
                    )
                }
            case .frontEdgeUnderrun:
                VoiceTimingLogger.recordFrontEdgeUnderrun(
                    timestampNanoseconds: observation.timestampNanoseconds,
                    durationMilliseconds: Double(observation.requestedFrames)
                        / Self.outputSampleRate * 1_000,
                    queuedFramesBefore: observation.queueDepthBeforeFrames,
                    queuedFramesAfter: observation.queueDepthAfterFrames
                )
            }
        }

        let markers = realtimeDiagnostics.markers()
        if let firstRendered = markers.firstRemoteRenderedMonotonicNanoseconds {
            VoiceTimingLogger.recordIfAbsent(
                "F5_first_pcm_rendered",
                timestampNanoseconds: firstRendered
            )
            if VoiceTimingLogger.hasEvent("F6_first_voiced_pcm_decoded") {
                VoiceTimingLogger.recordIfAbsent(
                    "F8_first_voiced_pcm_rendered",
                    timestampNanoseconds: firstRendered
                )
            }
        }
        if VoiceTimingLogger.p1A5Enabled,
           let stable = markers.playoutStableMonotonicNanoseconds {
            VoiceTimingLogger.recordIfAbsent(
                "F9_playout_stable",
                timestampNanoseconds: stable
            )
        }
        if markers.droppedObservationCount > 0 {
            markLongTermMaterialAnomalyLocked(trigger: .traceDrop)
        }
    }

    private func longTermMarker(
        for rawValue: Int32
    ) -> LongTermObservationSemanticMarker {
        switch rawValue {
        case 0, 4: return .active
        case 1: return .tail
        default: return .unclassified
        }
    }

    private func renderAccounting(
        for observation: AudioPipeRealtimeObservation
    ) -> AudioPipeRenderAccounting {
        switch observation.marker {
        case 4:
            return AudioPipeRenderAccounting(
                state: .reserveWait,
                accounted: false,
                activeRequestedFrames: 0,
                activeFilledFrames: 0,
                activeUnderrunFrames: 0,
                activeUnderrunCallbacks: 0,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            )
        case 0:
            return AudioPipeRenderAccounting(
                state: .activeRemote,
                accounted: true,
                activeRequestedFrames: observation.requestedFrames,
                activeFilledFrames: observation.filledFrames,
                activeUnderrunFrames: observation.unfilledFrames,
                activeUnderrunCallbacks: observation.unfilledFrames > 0 ? 1 : 0,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            )
        case 1:
            return AudioPipeRenderAccounting(
                state: .tailDrain,
                accounted: true,
                activeRequestedFrames: 0,
                activeFilledFrames: 0,
                activeUnderrunFrames: 0,
                activeUnderrunCallbacks: 0,
                tailRenderedFrames: observation.filledFrames,
                tailEmptyCallbacks: observation.filledFrames == 0 ? 1 : 0,
                idleRenderCallbacks: 0
            )
        case 3:
            return AudioPipeRenderAccounting(
                state: .localMicrophone,
                accounted: false,
                activeRequestedFrames: 0,
                activeFilledFrames: 0,
                activeUnderrunFrames: 0,
                activeUnderrunCallbacks: 0,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 0
            )
        default:
            return AudioPipeRenderAccounting(
                state: .idle,
                accounted: false,
                activeRequestedFrames: 0,
                activeFilledFrames: 0,
                activeUnderrunFrames: 0,
                activeUnderrunCallbacks: 0,
                tailRenderedFrames: 0,
                tailEmptyCallbacks: 0,
                idleRenderCallbacks: 1
            )
        }
    }

    private func startOutputDrainMonitorIfNeeded() {
        stateLock.lock()
        guard !outputDrainMonitorStarted else {
            stateLock.unlock()
            return
        }
        outputDrainMonitorStarted = true
        stateLock.unlock()

        outputDrainMonitorQueue.async { [weak self] in
            guard let self else { return }
            while true {
                self.outputDrainSignal.wait()
                self.deliverOutputDrainIfReady()
            }
        }
    }

    private func deliverOutputDrainIfReady() {
        stateLock.lock()
        guard let completion = remoteOutputDrainWaiter,
              Self.isOutputDrained(
                  remoteActive: remoteActive,
                  queuedFrames: outputRing.queuedFrames
              ) else {
            stateLock.unlock()
            return
        }
        remoteOutputDrainWaiter = nil
        realtimeDiagnostics.setDrainWaiterRequested(false)
        stateLock.unlock()

        VoiceTimingLogger.recordQueueEmpty(
            timestampNanoseconds: P1A4MonotonicClock.nowNanoseconds()
        )
        DispatchQueue.main.async(execute: completion)
    }

    private func appendLongTermObservationLocked(_ point: LongTermObservationPoint) {
        diagnosticObservationSequence &+= 1
        let attributedPoint = LongTermObservationPoint(
            timestampNanoseconds: point.timestampNanoseconds,
            kind: point.kind,
            requestedFrames: point.requestedFrames,
            filledFrames: point.filledFrames,
            unfilledFrames: point.unfilledFrames,
            queueDepthFrames: point.queueDepthAfterFrames,
            byteOrSampleCount: point.byteOrSampleCount,
            marker: point.marker,
            streamIdentity: point.streamIdentity == 0
                ? diagnosticStreamIdentity
                : point.streamIdentity,
            sequence: diagnosticObservationSequence,
            queueDepthBeforeFrames: point.queueDepthBeforeFrames,
            source: "audio_pipe"
        )
        let appended: Bool
        if longTermPrimaryTraceIsActive {
            appended = longTermPrimaryTrace.append(attributedPoint)
        } else {
            appended = longTermSecondaryTrace.append(attributedPoint)
        }
        if !appended {
            LongTermIncidentCoordinator.shared.trigger(
                producer: .audioPipe,
                kind: .traceDrop,
                timestampNanoseconds: attributedPoint.timestampNanoseconds
            )
            if longTermPrimaryTraceIsActive {
                longTermPrimaryTrace.synchronizeIncidentWithCoordinator()
            } else {
                longTermSecondaryTrace.synchronizeIncidentWithCoordinator()
            }
        }
    }

    private func markLongTermMaterialAnomalyLocked(
        trigger: LongTermIncidentTriggerKind,
        timestampNanoseconds: UInt64 = P1A4MonotonicClock.nowNanoseconds()
    ) {
        LongTermIncidentCoordinator.shared.trigger(
            producer: .audioPipe,
            kind: trigger,
            timestampNanoseconds: timestampNanoseconds
        )
        if longTermPrimaryTraceIsActive {
            longTermPrimaryTrace.synchronizeIncidentWithCoordinator()
        } else {
            longTermSecondaryTrace.synchronizeIncidentWithCoordinator()
        }
    }

    private func markLongTermMaterialAnomaly(
        trigger: LongTermIncidentTriggerKind
    ) {
        stateLock.lock()
        markLongTermMaterialAnomalyLocked(trigger: trigger)
        stateLock.unlock()
    }

    /// Test seam for the same bounded accounting used by the CoreAudio render
    /// callback. It exercises production observation semantics without faking a
    /// coordinator freeze or touching product audio behavior.
    func recordLongTermRenderObservationForTesting(
        timestampNanoseconds: UInt64,
        requestedFrames: UInt64,
        filledFrames: UInt64,
        unfilledFrames: UInt64,
        queueDepthFrames: UInt64,
        queueDepthBeforeFrames: UInt64? = nil,
        marker: LongTermObservationSemanticMarker = .active
    ) {
        stateLock.lock()
        guard remoteDiagnosticsActive else {
            stateLock.unlock()
            return
        }
        appendLongTermObservationLocked(
            LongTermObservationPoint(
                timestampNanoseconds: timestampNanoseconds,
                kind: .render,
                requestedFrames: requestedFrames,
                filledFrames: filledFrames,
                unfilledFrames: unfilledFrames,
                queueDepthFrames: queueDepthFrames,
                byteOrSampleCount: filledFrames,
                marker: marker,
                queueDepthBeforeFrames: queueDepthBeforeFrames
            )
        )
        if unfilledFrames > 0 {
            appendLongTermObservationLocked(
                LongTermObservationPoint(
                    timestampNanoseconds: timestampNanoseconds,
                    kind: .queueStarvation,
                    requestedFrames: requestedFrames,
                    filledFrames: filledFrames,
                    unfilledFrames: unfilledFrames,
                    queueDepthFrames: queueDepthFrames,
                    byteOrSampleCount: unfilledFrames,
                    marker: marker,
                    queueDepthBeforeFrames: queueDepthBeforeFrames
                )
            )
            markLongTermMaterialAnomalyLocked(
                trigger: .renderStarvation,
                timestampNanoseconds: timestampNanoseconds
            )
        }
        stateLock.unlock()
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
            let mode: String
            if self.remoteActive {
                mode = "remote"
            } else if self.localMicrophoneCaptureRequested {
                mode = "mac"
            } else {
                mode = "idle"
            }
            let macBuffers = self.scheduledMacBuffers
            let remoteBuffers = self.scheduledRemoteBuffers
            let peak = self.scheduledPeak
            let queuedFrames = self.outputRing.queuedFrames
            let now = ProcessInfo.processInfo.systemUptime
            let shouldPrint = DiagnosticAudioMeterCadence.shouldEmit(
                mode: mode,
                now: now,
                lastIdleEmission: self.lastIdleMeterAt
            )
            if mode == "idle", shouldPrint {
                self.lastIdleMeterAt = now
            }
            self.scheduledMacBuffers = 0
            self.scheduledRemoteBuffers = 0
            self.scheduledPeak = 0
            self.stateLock.unlock()
            let meter = self.realtimeDiagnostics.takeMeterSnapshot(reset: true)
            guard shouldPrint else { return }
            print(String(
                format: "[AUDIO-METER] mode=%@ macBuffers=%d remoteBuffers=%d scheduledPeak=%.4f renders=%d renderedFrames=%d renderedPeak=%.4f queuedFrames=%d",
                mode,
                macBuffers,
                remoteBuffers,
                peak,
                meter.renderCallbackCount,
                meter.renderedFrames,
                meter.renderedPeak,
                queuedFrames
            ))
        }
    }
}

private extension AudioPipeDiagnosticsCounters {
    mutating func mergeRealtime(_ snapshot: AudioPipeRealtimeCounterSnapshot) {
        renderCallbackCount += snapshot.renderCallbackCount
        renderRequestedFrames += snapshot.renderRequestedFrames
        renderFilledFrames += snapshot.renderFilledFrames
        renderUnfilledFrames += snapshot.renderUnfilledFrames
        underrunCallbackCount += snapshot.underrunCallbackCount
        maxUnderrunFrames = max(maxUnderrunFrames, snapshot.maxUnderrunFrames)
        renderedRemoteFrames += snapshot.renderedRemoteFrames
        if let minDepth = snapshot.minQueueDepthFrames {
            minQueueDepthFrames = min(minQueueDepthFrames ?? minDepth, minDepth)
        }
        maxQueueDepthFrames = max(maxQueueDepthFrames, snapshot.maxQueueDepthFrames)
        tailRenderedFrames += snapshot.tailRenderedFrames
        tailEmptyCallbackCount += snapshot.tailEmptyCallbackCount
        idleRenderCallbackCount += snapshot.idleRenderCallbackCount
    }
}
