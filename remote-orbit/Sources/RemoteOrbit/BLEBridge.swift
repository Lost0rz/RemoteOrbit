// BLEBridge: CoreBluetooth connection to the Xiaomi Bluetooth Voice Remote 2 Pro,
// runs the ATVV voice-stream handshake, and pumps decoded mono Int16 PCM
// into the AudioPipe.
//
// State machine for the ATVV voice flow, simplified for this app:
//   disconnected → connect → discoverServices → discoverChars
//   → send getCapabilities → wait for capabilities
//   → on .startSearch (voice-key press from remote): send micOpen
//   → audio frames flow on TX char → ADPCM decode → AudioPipe.feed

import CoreBluetooth
import Foundation

enum BLEAudioStartDisposition: Equatable {
    case accepted
    case ignoredDuringDrain(
        currentStreamID: UInt8,
        incomingStreamID: UInt8,
        pendingAudioStopReason: UInt8?
    )
}

final class BLEBridge: NSObject {
    // ATVV service / characteristic UUIDs (Google Android TV Remote protocol).
    static let serviceUUID  = CBUUID(string: "AB5E0001-5A21-4F05-BC7D-AF01F617B664")
    static let commandUUID  = CBUUID(string: "AB5E0002-5A21-4F05-BC7D-AF01F617B664")  // host writes commands to remote
    static let audioUUID    = CBUUID(string: "AB5E0003-5A21-4F05-BC7D-AF01F617B664")  // remote sends voice data to host (notify)
    static let controlUUID  = CBUUID(string: "AB5E0004-5A21-4F05-BC7D-AF01F617B664")  // control events from remote

    // Optional: filter by peripheral name in addition to UUID.
    let nameHint: String? = "小米"

    /// Where we persist a previously-discovered peripheral UUID so the next
    /// launch can attempt `retrievePeripherals` directly without scanning.
    private static let savedUUIDPath: String = {
        let env = ProcessInfo.processInfo.environment["REMOTE_ORBIT_UUID_FILE"]
        return env ?? NSString(string: "~/Library/Application Support/RemoteOrbit/uuid.txt").expandingTildeInPath
    }()

    /// Called whenever the bridge produces or stops producing audio (true = streaming).
    var onStreamingChanged: ((Bool, Int /* sampleRate */) -> Void)?
    /// Called after a decoded remote audio frame is available. A stream can be
    /// announced before its first frame; the voice UI waits for this callback
    /// before opening the external voice dialog.
    var onAudioFrame: (() -> Void)?
    /// Called when the device connection state changes.
    var onConnectionChanged: ((Bool) -> Void)?
    /// Audio level meter update; arg is dBFS in [-60, 0].
    var onLevel: ((Double, Int /* peak */) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var audioChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?
    private var discoveredATVVCharacteristics = Set<CBUUID>()
    private var capabilitiesRequested = false
    private var atvvReady = false

    // HID and ATVV are separate CoreBluetooth transports. Keep a reconnect
    // state machine for the voice transport so an HID reconnect does not
    // leave the remote microphone permanently offline.
    private var isStarted = false
    private var isScanning = false
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var handshakeTimeoutWorkItem: DispatchWorkItem?
    private var stopAfterVoiceWorkItem: DispatchWorkItem?
    private var audioStopDrainWorkItem: DispatchWorkItem?
    private let reconnectDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
    private let scanTimeout: TimeInterval = 8
    private let connectTimeout: TimeInterval = 12
    private let handshakeTimeout: TimeInterval = 4
    /// The remote often sends AUDIO_STOP before the final audio notifications
    /// reach CoreBluetooth. Keep the decoder and output path alive briefly so
    /// those packets can still be recorded and rendered.
    private let audioStopDrainDelay: TimeInterval = 0.35
    private let transportCloseDelay: TimeInterval = 0.60

    private let protocolHandler = ATVVProtocol()
    private var streamID: UInt8 = 0
    private var voiceInputRequested = false
    private var micOpenRequested = false
    private var isStreaming = false
    private var levelSumSq: Int64 = 0
    private var levelCount: Int = 0
    private var levelPeak: Int = 0
    private var levelLogAt = Date.distantPast
    private var diagFrameCount = 0
    private var streamFrameCount = 0
    private var streamSampleCount = 0
    private var streamPeak = 0
    private var streamSumSquares: Int64 = 0
    private var streamClippedSampleCount = 0
    private var pendingAudioSyncCount = 0
    private var streamAudioSyncCount = 0
    private var pendingAudioStopReason: UInt8?
    private var streamStartedAt = Date.distantPast
    private var firstAudioAt: Date?
    private var lastAudioAt: Date?
    private var maxAudioFrameGap: TimeInterval = 0
    private var streamDrainFrameCount = 0
    private var audioFramesOutsideStream = 0
    private var wavRecorder: WavRecorder?
    // Verbose PCM diagnostics are off unless explicitly requested.
    private static let diagnosticsEnabled =
        ProcessInfo.processInfo.environment["REMOTE_ORBIT_DIAGNOSTICS"] == "1"
    private var lastStartSearchAt = Date.distantPast

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    static func audioStartDisposition(
        drainPending: Bool,
        currentStreamID: UInt8,
        incomingStreamID: UInt8,
        pendingAudioStopReason: UInt8?
    ) -> BLEAudioStartDisposition {
        guard drainPending == false else {
            return .ignoredDuringDrain(
                currentStreamID: currentStreamID,
                incomingStreamID: incomingStreamID,
                pendingAudioStopReason: pendingAudioStopReason
            )
        }
        return .accepted
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        reconnectAttempt = 0
        if central.state == .poweredOn {
            tryDirectConnect()
        } else {
            print("[BLE] 等待蓝牙就绪…")
        }
    }

    func stop() {
        isStarted = false
        voiceInputRequested = false
        micOpenRequested = false
        stopAfterVoiceWorkItem?.cancel()
        stopAfterVoiceWorkItem = nil
        audioStopDrainWorkItem?.cancel()
        audioStopDrainWorkItem = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        central.stopScan()
        isScanning = false
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        clearTransportState(notify: true)
        peripheral = nil
    }

    /// ATVV must not be kept connected while the remote is idle. On this
    /// remote the idle ATVV link eventually takes over the same radio session
    /// used by HID, which makes ordinary buttons disappear during reconnects.
    /// Open the voice transport only for the lifetime of a voice-key hold.
    func startVoiceInput() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startVoiceInput()
            }
            return
        }
        voiceInputRequested = true
        micOpenRequested = false
        stopAfterVoiceWorkItem?.cancel()
        stopAfterVoiceWorkItem = nil
        start()
        requestMicOpenIfReady()
    }

    /// Release the ATVV transport shortly after the physical voice key is
    /// released. The small drain window lets the remote deliver AUDIO_STOP,
    /// then returns the radio to HID-only operation.
    func stopVoiceInput() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopVoiceInput()
            }
            return
        }
        voiceInputRequested = false
        if micOpenRequested, atvvReady {
            do {
                let command = try protocolHandler.micCloseCommand(streamID: streamID)
                writeCommand(command)
                print("[BLE] TX micClose")
                VoiceOptionTrace.timingMark(.micCloseTx)
            } catch {
                print("[BLE] micClose error: \(error.localizedDescription)")
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stopAfterVoiceWorkItem = nil
            self.stop()
            print("[BLE] 语音释放，ATVV 链路已关闭（恢复 HID-only）")
        }
        stopAfterVoiceWorkItem?.cancel()
        stopAfterVoiceWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + transportCloseDelay,
            execute: work
        )
    }

    func setRecordingEnabled(_ enabled: Bool) {
        AppStorage.recordingEnabled = enabled
        if enabled, isStreaming, wavRecorder == nil {
            wavRecorder = WavRecorder.createNext(prefix: "remote-orbit")
        } else if !enabled, let recorder = wavRecorder {
            recorder.close()
            wavRecorder = nil
        }
    }

    func clearRecordings() {
        if let recorder = wavRecorder {
            recorder.close()
            wavRecorder = nil
        }
        AppStorage.clearFiles(in: AppStorage.recordingsDirectory)
    }

    /// If we have a saved UUID from a previous scan, ask CoreBluetooth for
    /// the peripheral directly. This works even when the device is HID-paired
    /// (advertisement scan returns nothing in that case).
    private func tryDirectConnect() {
        guard isStarted, central.state == .poweredOn else { return }
        if let peripheral {
            if peripheral.state == .connected {
                discoverATVVServices(on: peripheral)
                return
            }
            if peripheral.state == .connecting {
                return
            }
        }
        guard let uuidString = try? String(contentsOfFile: Self.savedUUIDPath, encoding: .utf8),
              let uuid = UUID(uuidString: uuidString.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            if connectToAlreadyConnectedPeripheral() { return }
            print("[BLE] 新版本无已存 UUID，转扫描")
            return beginScan()
        }
        let known = central.retrievePeripherals(withIdentifiers: [uuid])
        if let p = known.first {
            print("[BLE] 已存 UUID 直接 connect: \(p.identifier)")
            connect(to: p)
        } else {
            if connectToAlreadyConnectedPeripheral() { return }
            print("[BLE] CB 未保留该 UUID，转扫描")
            beginScan()
        }
    }

    /// The app intentionally keeps its own UUID store after the product
    /// rename. If macOS/CoreBluetooth already has the remote connected, use
    /// that live connection without importing a legacy bridge implementation.
    /// configuration; otherwise the normal scan path remains unchanged.
    private func connectToAlreadyConnectedPeripheral() -> Bool {
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
        guard let peripheral = connected.first else { return false }
        print("[BLE] 复用当前已连接的 ATVV 外设: \(peripheral.identifier)")
        connect(to: peripheral)
        return true
    }

    private func beginScan() {
        guard isStarted, central.state == .poweredOn, !isScanning else { return }
        isScanning = true
        print("[BLE] 扫描中（按名字 \(nameHint ?? "?") + ATVV service 过滤）")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scanTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning else { return }
            self.central.stopScan()
            self.isScanning = false
            print("[BLE] 扫描超时，进入退避重连")
            self.scheduleReconnect(reason: "scan-timeout")
        }
        scanTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + scanTimeout,
            execute: work
        )
    }

    fileprivate func saveUUID(_ id: UUID) {
        let path = Self.savedUUIDPath
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? id.uuidString.write(to: url, atomically: true, encoding: .utf8)
        print("[BLE] 已保存 UUID: \(id.uuidString)")
    }

    fileprivate func connect(to p: CBPeripheral) {
        guard isStarted else { return }
        if let current = peripheral,
           current.identifier == p.identifier,
           current.state == .connecting || current.state == .connected {
            return
        }
        peripheral = p
        p.delegate = self
        central.stopScan()
        isScanning = false
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        clearTransportState(notify: false)

        // CoreBluetooth may return a live peripheral from
        // retrieveConnectedPeripherals(). Calling connect() again is not a
        // reliable way to restart ATVV discovery, so use the existing link.
        if p.state == .connected {
            discoverATVVServices(on: p)
            return
        }

        central.connect(p, options: nil)
        saveUUID(p.identifier)
        print("[BLE] 连接 \(p.name ?? "(no name)") (\(p.identifier))…")

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.peripheral?.identifier == p.identifier,
                  !self.atvvReady
            else { return }
            print("[BLE] 连接请求超时，进入退避重连")
            self.connectionSetupFailed("connect-timeout")
        }
        connectTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + connectTimeout,
            execute: work
        )
    }

    private func discoverATVVServices(on peripheral: CBPeripheral) {
        peripheral.delegate = self
        print("[BLE] 重新发现 ATVV 服务")
        peripheral.discoverServices([Self.serviceUUID])
    }

    private func scheduleReconnect(reason: String, immediate: Bool = false) {
        guard isStarted, voiceInputRequested, central.state == .poweredOn else { return }
        guard reconnectWorkItem == nil else { return }

        let index = min(reconnectAttempt, reconnectDelays.count - 1)
        let delay = immediate ? 0 : reconnectDelays[index]
        if !immediate {
            reconnectAttempt = min(reconnectAttempt + 1, reconnectDelays.count - 1)
        }
        print(
            "[BLE] \(reason)，\(String(format: "%.1f", delay)) 秒后重连 "
                + "(attempt=\(reconnectAttempt))"
        )

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.tryDirectConnect()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func markATVVReady() {
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        guard !atvvReady else { return }
        atvvReady = true
        reconnectAttempt = 0
        print("[BLE] ATVV 语音链路已就绪")
        onConnectionChanged?(true)
        requestMicOpenIfReady()
    }

    private func clearTransportState(notify: Bool) {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        audioStopDrainWorkItem?.cancel()
        audioStopDrainWorkItem = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        if let recorder = wavRecorder {
            recorder.close()
            wavRecorder = nil
        }
        let wasStreaming = isStreaming
        isStreaming = false
        pendingAudioStopReason = nil
        protocolHandler.endAudioStream()
        audioChar = nil
        commandChar = nil
        controlChar = nil
        discoveredATVVCharacteristics.removeAll()
        capabilitiesRequested = false
        micOpenRequested = false
        let wasReady = atvvReady
        atvvReady = false
        if wasStreaming || notify {
            notifyStreaming(false)
        }
        if wasReady {
            onConnectionChanged?(false)
        }
    }

    private func connectionSetupFailed(_ reason: String) {
        print("[BLE] ATVV 建链失败: \(reason)")
        let oldPeripheral = peripheral
        clearTransportState(notify: true)
        peripheral = nil
        if let oldPeripheral {
            central.cancelPeripheralConnection(oldPeripheral)
        }
        scheduleReconnect(reason: reason)
    }

    private func isCurrentPeripheral(_ candidate: CBPeripheral) -> Bool {
        isStarted && peripheral?.identifier == candidate.identifier
    }

    private func writeCommand(_ data: Data) {
        guard let p = peripheral, let c = commandChar else { return }
        // The remote exposes both write modes. ATVV commands are one-way
        // control packets; using write-without-response avoids serializing the
        // mic-open path behind an unnecessary ATT acknowledgement while still
        // falling back safely on firmware that only exposes write-with-response.
        let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
        p.writeValue(data, for: c, type: type)
    }

    private func requestMicOpenIfReady() {
        guard voiceInputRequested, atvvReady, !micOpenRequested else { return }
        do {
            protocolHandler.prepareForAudioStream()
            pendingAudioSyncCount = 0
            writeCommand(try protocolHandler.micOpenCommand())
            micOpenRequested = true
            print("[BLE] TX micOpen (voice hold)")
            VoiceOptionTrace.timingMark(.micOpenTx)
        } catch {
            print("[BLE] micOpen error: \(error.localizedDescription)")
        }
    }

    /// Send an ATVV keep-alive. Should be called every ~4 seconds while
    /// streaming to keep the device's audio stream open during long
    /// voice-key holds.
    private func sendKeepAlive() {
        guard isStreaming, let s = protocolHandler.codec else { return }
        do {
            let cmd = try protocolHandler.keepAliveCommand(streamID: streamID)
            writeCommand(cmd)
            // Quiet log; user only needs levels to debug.
        } catch {
            print("[BLE] keep-alive error: \(error.localizedDescription)")
        }
        _ = s
    }

    /// Start a periodic timer that keeps the ATVV voice stream alive while
    /// the remote thinks the user is holding the voice button.
    private var keepAliveTimer: Timer?
    private func startKeepAliveTimer() {
        stopKeepAliveTimer()
        keepAliveTimer = Timer.scheduledTimer(
            withTimeInterval: 4.0,
            repeats: true
        ) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }
    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private func notifyStreaming(_ on: Bool) {
        let sr = (protocolHandler.codec == .adpcm16k) ? 16_000 : 8_000
        onStreamingChanged?(on, sr)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLE] 蓝牙已就绪")
            if voiceInputRequested {
                scheduleReconnect(reason: "bluetooth-ready", immediate: true)
            }
        case .poweredOff:
            print("[BLE] 蓝牙未开启")
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            central.stopScan()
            isScanning = false
            clearTransportState(notify: true)
            onConnectionChanged?(false)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let n = peripheral.name ?? "(no name)"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
        let hasATVV = services.contains(Self.serviceUUID)
        let short = services.map { String($0.uuidString.prefix(8)) }
        // Don't log every device — just ones that match by name OR advertise ATVV.
        if (nameHint.map { n.contains($0) } ?? false) || hasATVV {
            print("[BLE] 候选: \(n) (\(peripheral.identifier)), services=\(short), rssi=\(RSSI)")
            connect(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isCurrentPeripheral(peripheral) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        print("[BLE] 已连接")
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        discoverATVVServices(on: peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("[BLE] 连接失败: \(error?.localizedDescription ?? "unknown")")
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        clearTransportState(notify: true)
        self.peripheral = nil
        // A failed connect does not call didDisconnectPeripheral, so without
        // this path an encryption timeout permanently stops voice reconnects.
        scheduleReconnect(reason: "connect-failed")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("[BLE] 断开: \(error?.localizedDescription ?? "ok")")
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        clearTransportState(notify: true)
        self.peripheral = nil
        scheduleReconnect(reason: "disconnected")
    }
}

// MARK: - CBPeripheralDelegate

extension BLEBridge: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isCurrentPeripheral(peripheral) else { return }
        guard error == nil, let services = peripheral.services else {
            print("[BLE] 服务发现失败: \(error?.localizedDescription ?? "?")")
            connectionSetupFailed("service-discovery-failed")
            return
        }
        guard services.contains(where: { $0.uuid == Self.serviceUUID }) else {
            connectionSetupFailed("ATVV-service-missing")
            return
        }
        print("[BLE] 发现 \(services.count) 个 service")
        for s in services {
            let tag = s.uuid == Self.serviceUUID ? " ←ATVV" : ""
            print("[BLE]   svc \(s.uuid.uuidString.prefix(8))…\(tag)")
            // Discover ALL characteristics on every service so we can also
            // see HOGP (HID-over-GATT) button channels if they exist.
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard isCurrentPeripheral(peripheral) else { return }
        guard error == nil, let chars = service.characteristics else {
            connectionSetupFailed("characteristic-discovery-failed")
            return
        }
        for c in chars {
            let props = describeProperties(c.properties)
            let isATVV = service.uuid == Self.serviceUUID
            print("[BLE]   char \(c.uuid.uuidString.prefix(8)) [\(props)]")
            if isATVV,
               c.uuid == Self.audioUUID
                || c.uuid == Self.commandUUID
                || c.uuid == Self.controlUUID {
                discoveredATVVCharacteristics.insert(c.uuid)
            }
            switch c.uuid {
            case Self.audioUUID:
                audioChar = c
                peripheral.setNotifyValue(true, for: c)
                print("[BLE]   → audio subscribed; isNotifying=\(c.isNotifying)")
            case Self.commandUUID:
                commandChar = c
                print("[BLE]   → command stored")
            case Self.controlUUID:
                controlChar = c
                peripheral.setNotifyValue(true, for: c)
                print("[BLE]   → control subscribed; isNotifying=\(c.isNotifying)")
            default:
                // Auto-subscribe to any notify-capable characteristic on this
                // service — we may find button events on HOGP here.
                if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: c)
                    print("[BLE]   → auto-subscribed (notify); isNotifying=\(c.isNotifying)")
                }
            }
        }
        let required = Set([Self.audioUUID, Self.commandUUID, Self.controlUUID])
        if required.isSubset(of: discoveredATVVCharacteristics),
           !capabilitiesRequested {
            // All three ATVV chars found: kick off capabilities handshake.
            writeCommand(protocolHandler.getCapabilitiesCommand)
            print("[BLE] TX getCapabilities")
            capabilitiesRequested = true
            handshakeTimeoutWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.atvvReady else { return }
                self.connectionSetupFailed("capabilities-timeout")
            }
            handshakeTimeoutWorkItem = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + handshakeTimeout,
                execute: work
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard isCurrentPeripheral(peripheral) else { return }
        guard characteristic.uuid == Self.audioUUID
                || characteristic.uuid == Self.controlUUID
        else { return }
        if let error {
            print("[BLE] 音频特征订阅失败: \(error.localizedDescription)")
            connectionSetupFailed("notification-subscription-failed")
        } else if !characteristic.isNotifying {
            print("[BLE] 音频特征未进入通知状态")
            connectionSetupFailed("notification-disabled")
        }
    }

    private func describeProperties(_ p: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if p.contains(.read) { parts.append("read") }
        if p.contains(.write) { parts.append("write") }
        if p.contains(.writeWithoutResponse) { parts.append("writeNoResp") }
        if p.contains(.notify) { parts.append("notify") }
        if p.contains(.indicate) { parts.append("indicate") }
        return parts.joined(separator: ",")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard isCurrentPeripheral(peripheral) else { return }
        if let error {
            print("[BLE] char update error: \(error.localizedDescription)")
            if characteristic.uuid == Self.audioUUID || characteristic.uuid == Self.controlUUID {
                connectionSetupFailed("characteristic-update-failed")
            }
            return
        }
        guard let data = characteristic.value else { return }
        let len = data.count
        switch characteristic.uuid {
        case Self.controlUUID:
            handleControl(data)
        case Self.audioUUID:
            handleAudio(data)
        default:
            print("[BLE] unexpected char update \(characteristic.uuid.uuidString.prefix(8)), \(len)B")
        }
    }

    private func handleControl(_ data: Data) {
        let ev = protocolHandler.parseControl(data)
        switch ev {
        case .startSearch:
            // Debounce: the 2 Pro re-sends START_SEARCH during long holds.
            // If we're already streaming OR we just opened within the last
            // 500ms, ignore the duplicate.
            let now = Date()
            if isStreaming { return }
            if now.timeIntervalSince(lastStartSearchAt) < 0.5 { return }
            lastStartSearchAt = now
            // ATVV control notifications and the HID key event do not have a
            // guaranteed ordering. Arm the short PCM pre-roll here so the
            // first decoded frames survive until the gesture is classified.
            AudioPipe.shared.beginRemoteCandidate()
            requestMicOpenIfReady()
        case .capabilities(let caps):
            do {
                try protocolHandler.acceptCapabilities(caps)
                print("[BLE] caps ok v\(caps.version) codec=\(protocolHandler.codec!)")
                markATVVReady()
            } catch {
                print("[BLE] caps error: \(error.localizedDescription)")
            }
        case .audioStart(_, let codec, let sid):
            switch Self.audioStartDisposition(
                drainPending: audioStopDrainWorkItem != nil,
                currentStreamID: streamID,
                incomingStreamID: sid,
                pendingAudioStopReason: pendingAudioStopReason
            ) {
            case .accepted:
                break
            case let .ignoredDuringDrain(currentStreamID, incomingStreamID, reason):
                let reasonText = reason.map { String(format: "0x%02x", $0) } ?? "none"
                print(
                    "[BLE] late AUDIO_START ignored during drain " +
                        "currentStreamID=\(currentStreamID) " +
                        "incomingStreamID=\(incomingStreamID) " +
                        "pendingReason=\(reasonText)"
                )
                return
            }
            audioStopDrainWorkItem?.cancel()
            audioStopDrainWorkItem = nil
            pendingAudioStopReason = nil
            protocolHandler.beginAudioStream(codec: codec)
            // Some firmware emits AUDIO_START before the matching HID
            // key-down reaches the tap. Keep the same bounded pre-roll alive
            // from the earliest audio-stream notification.
            AudioPipe.shared.beginRemoteCandidate()
            streamID = sid
            isStreaming = true
            notifyStreaming(true)
            diagFrameCount = 0
            streamFrameCount = 0
            streamSampleCount = 0
            streamPeak = 0
            streamSumSquares = 0
            streamClippedSampleCount = 0
            streamAudioSyncCount = pendingAudioSyncCount
            pendingAudioSyncCount = 0
            streamStartedAt = Date()
            firstAudioAt = nil
            lastAudioAt = nil
            maxAudioFrameGap = 0
            streamDrainFrameCount = 0
            audioFramesOutsideStream = 0
            wavRecorder = AppStorage.recordingEnabled
                ? WavRecorder.createNext(prefix: "remote-orbit")
                : nil
            startKeepAliveTimer()
            print("[BLE] AUDIO_START streamID=\(sid)")
            VoiceOptionTrace.timingMark(.audioStart)
        case .audioStop(let reason):
            guard isStreaming else {
                print("[BLE] AUDIO_STOP duplicate ignored reason=0x\(String(format: "%02x", reason))")
                return
            }
            if audioStopDrainWorkItem != nil {
                print("[BLE] AUDIO_STOP duplicate during drain ignored reason=0x\(String(format: "%02x", reason))")
                return
            }
            pendingAudioStopReason = reason
            stopKeepAliveTimer()
            VoiceOptionTrace.timingMark(.audioStop)
            print(
                "[BLE] AUDIO_STOP received; draining audio tail " +
                    "for \(Int(audioStopDrainDelay * 1_000))ms " +
                    "reason=0x\(String(format: "%02x", reason))"
            )
            let work = DispatchWorkItem { [weak self] in
                self?.finishAudioStopAfterDrain()
            }
            audioStopDrainWorkItem = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + audioStopDrainDelay,
                execute: work
            )
        case .audioSync(let codec, let sequence, let pred, let stepIndex):
            protocolHandler.applyAudioSync(
                codec: codec,
                sequence: sequence,
                predictor: pred,
                stepIndex: stepIndex
            )
            if isStreaming {
                streamAudioSyncCount += 1
            } else {
                pendingAudioSyncCount += 1
            }
            print(
                "[BLE] AUDIO_SYNC codec=\(codec) sequence=\(sequence) " +
                "predictor=\(pred) step=\(stepIndex) " +
                "phase=\(isStreaming ? "streaming" : "opening")"
            )
        case .micOpenError(let code):
            print("[BLE] MIC_OPEN 错误: 0x\(String(format: "%04x", code))")
        case .unknown(let d):
            // Capabilities-handshake uses 0x0B on the control char sometimes;
            // absorb instead of failing noisily.
            if data.first == 0x0B {
                if let caps = ATVVProtocol.parseCapabilities(data) {
                    do {
                        try protocolHandler.acceptCapabilities(caps)
                        print("[BLE] caps (fallback) v\(caps.version) codec=\(protocolHandler.codec!)")
                        markATVVReady()
                    } catch {
                        print("[BLE] caps fallback error: \(error.localizedDescription)")
                    }
                }
            }
            // Silently ignore other unknown events.
            _ = d
        }
    }

    private func handleAudio(_ data: Data) {
        guard isStreaming else {
            audioFramesOutsideStream += 1
            return
        }
        guard let frame = protocolHandler.decodeAudio(data) else { return }
        if frame.samples.isEmpty { return }
        let now = Date()
        if let lastAudioAt {
            maxAudioFrameGap = max(maxAudioFrameGap, now.timeIntervalSince(lastAudioAt))
        } else {
            firstAudioAt = now
            print(
                "[BLE] AUDIO_FIRST +\(String(format: "%.1f", now.timeIntervalSince(streamStartedAt) * 1_000))ms"
            )
        }
        lastAudioAt = now
        if audioStopDrainWorkItem != nil {
            streamDrainFrameCount += 1
        }
        streamFrameCount += 1
        streamSampleCount += frame.samples.count
        streamPeak = max(
            streamPeak,
            frame.samples.map { Int(abs(Int($0))) }.max() ?? 0
        )
        streamSumSquares += frame.samples.reduce(into: Int64(0)) {
            $0 += Int64($1) * Int64($1)
        }
        streamClippedSampleCount += frame.samples.reduce(into: 0) {
            if abs(Int($1)) >= 32_760 { $0 += 1 }
        }

        // Diagnostic: dump first few raw bytes & first few decoded samples
        if Self.diagnosticsEnabled, diagFrameCount < 5 {
            let rawHex = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            let samHex = frame.samples.prefix(8).map { String($0) }.joined(separator: ",")
            print("[AUDIO-DIAG] frame#\(diagFrameCount) raw[\(rawHex)] decoded[\(samHex)]")
            diagFrameCount += 1
        }

        // Optional developer-only recording. Production builds never create
        // a WAV because `recordingEnabled` is false.
        if let w = wavRecorder {
            w.appendSamples(frame.samples)
            w.appendRawBytes(data)
        }

        // Queue the decoded frame before opening the external voice dialog.
        // The first frame must already be available when the target app reacts
        // to the released Option edge; otherwise the opening syllable can be
        // lost even though the BLE decoder received it.
        AudioPipe.shared.feed(samples: frame.samples)
        onAudioFrame?()
        let needsLevel = onLevel != nil || Self.diagnosticsEnabled
        if needsLevel {
            levelSumSq += frame.samples.reduce(into: 0) {
                $0 += Int64($1) * Int64($1)
            }
            levelCount += frame.samples.count
            levelPeak = max(
                levelPeak,
                frame.samples.map { Int(abs(Int($0))) }.max() ?? 0
            )
        }
        if needsLevel, Date().timeIntervalSince(levelLogAt) >= 0.5 {
            let rms = levelCount > 0 ? sqrt(Double(levelSumSq) / Double(levelCount)) : 0
            let peak = levelPeak
            let db = rms > 0 ? 20.0 * log10(rms / 32768.0) : -120
            let bar = meterBar(level: db)
            if Self.diagnosticsEnabled {
                print(String(format: "[LVL] %@ ATVV rms=%.0f peak=%d  %.0f dBFS",
                             bar, rms, peak, db))
            }
            onLevel?(db, peak)
            levelSumSq = 0
            levelCount = 0
            levelPeak = 0
            levelLogAt = Date()
        }
    }

    private func finishAudioStopAfterDrain() {
        audioStopDrainWorkItem = nil
        guard isStreaming else { return }

        isStreaming = false
        protocolHandler.endAudioStream()
        if lastAudioAt != nil {
            VoiceOptionTrace.timingMark(.lastAudioFrame)
        }
        VoiceOptionTrace.timingMark(.drainFinish)
        notifyStreaming(false)
        levelSumSq = 0
        levelCount = 0
        levelPeak = 0
        onLevel?(-120, 0)
        diagFrameCount = 0
        if let w = wavRecorder {
            w.close()
            print("[WAV] closed \(w.filename)")
            wavRecorder = nil
        }
        let streamRMS = streamSampleCount > 0
            ? sqrt(Double(streamSumSquares) / Double(streamSampleCount))
            : 0
        let streamDB = streamRMS > 0
            ? 20.0 * log10(streamRMS / 32768.0)
            : -120
        let firstMS = firstAudioAt.map {
            String(format: "%.1f", $0.timeIntervalSince(streamStartedAt) * 1_000)
        } ?? "n/a"
        let maxGapMS = String(format: "%.1f", maxAudioFrameGap * 1_000)
        let summary = [
            "[BLE] AUDIO_SUMMARY streamID=\(streamID)",
            "frames=\(streamFrameCount)",
            "samples=\(streamSampleCount)",
            "peak=\(streamPeak)",
            "rms=\(Int(streamRMS.rounded()))",
            "db=\(String(format: "%.1f", streamDB))",
            "clipped=\(streamClippedSampleCount)",
            "syncs=\(streamAudioSyncCount)",
            "first=\(firstMS)ms",
            "maxGap=\(maxGapMS)ms",
            "drainFrames=\(streamDrainFrameCount)",
            "outside=\(audioFramesOutsideStream)"
        ].joined(separator: " ")
        print(summary)
        let reason = pendingAudioStopReason ?? 0
        pendingAudioStopReason = nil
        print("[BLE] AUDIO_STOP drained reason=0x\(String(format: "%02x", reason))")
    }

    /// Convert dBFS to a tiny ASCII bar for at-a-glance logs.
    private func meterBar(level: Double) -> String {
        let clamped = max(-60, min(0, level))
        let n = (clamped + 60) / 6   // 0..10 segments
        return "[" + String(repeating: "▓", count: Int(n)) +
                     String(repeating: "░", count: 10 - Int(n)) + "]"
    }
}
