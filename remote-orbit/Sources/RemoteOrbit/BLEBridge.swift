// BLEBridge: CoreBluetooth connection to the Xiaomi Bluetooth Voice Remote 2 Pro,
// runs the ATVV voice-stream handshake, and pumps decoded mono Int16 PCM
// into the AudioPipe.
//
// State machine for the ATVV voice flow, simplified for this app:
//   disconnected → connect → discoverServices → discoverChars
//   → send getCapabilities → wait for capabilities
//   → on long-press promotion: send micOpen
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

enum BLEStreamOwnership: Equatable {
    case none
    case preHIDPhysical
    case voiceSession
}

enum BLEVoiceConnectionState: String, Equatable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case ready = "ready"
}

/// Transport preparation and user-visible voice activation are separate
/// intents. The classifier may prepare ATVV, but only long confirmation may
/// request micOpen and create an audio stream.
struct BLEVoiceTransportState {
    var isStarted = false
    var transportPrepared = false
    var pendingPreCaptureRequested = false
    var voiceInputRequested = false
    var atvvReady = false
    var micOpenRequested = false
    var connectionState: BLEVoiceConnectionState = .disconnected
    var audioCharacteristicDiscovered = false
    var commandCharacteristicDiscovered = false
    var controlCharacteristicDiscovered = false
    var audioNotificationConfirmed = false
    var controlNotificationConfirmed = false
    var capabilitiesAccepted = false

    var isPreparing: Bool {
        isStarted && !transportPrepared
    }

    mutating func prepareTransport() {
        isStarted = true
        if connectionState != .ready {
            clearReadinessFacts()
        }
    }

    mutating func beginConnection() {
        clearReadinessFacts()
        connectionState = .connecting
        transportPrepared = false
        atvvReady = false
    }

    @discardableResult
    mutating func evaluateATVVReadiness() -> Bool {
        guard !atvvReady,
              audioCharacteristicDiscovered,
              commandCharacteristicDiscovered,
              controlCharacteristicDiscovered,
              audioNotificationConfirmed,
              controlNotificationConfirmed,
              capabilitiesAccepted else {
            return false
        }
        connectionState = .ready
        transportPrepared = true
        atvvReady = true
        return true
    }

    mutating func markDisconnected() {
        connectionState = .disconnected
        transportPrepared = false
        atvvReady = false
        clearReadinessFacts()
    }

    mutating func markAudioCharacteristicDiscovered() {
        audioCharacteristicDiscovered = true
    }

    mutating func markCommandCharacteristicDiscovered() {
        commandCharacteristicDiscovered = true
    }

    mutating func markControlCharacteristicDiscovered() {
        controlCharacteristicDiscovered = true
    }

    mutating func markAudioNotificationConfirmed() {
        audioNotificationConfirmed = true
    }

    mutating func markControlNotificationConfirmed() {
        controlNotificationConfirmed = true
    }

    mutating func markCapabilitiesAccepted() {
        capabilitiesAccepted = true
    }

    private mutating func clearReadinessFacts() {
        audioCharacteristicDiscovered = false
        commandCharacteristicDiscovered = false
        controlCharacteristicDiscovered = false
        audioNotificationConfirmed = false
        controlNotificationConfirmed = false
        capabilitiesAccepted = false
    }

    mutating func requestPendingPreCapture() {
        pendingPreCaptureRequested = true
    }

    mutating func requestVoiceInput() {
        voiceInputRequested = true
        pendingPreCaptureRequested = false
    }

    mutating func cancelVoiceInput() {
        voiceInputRequested = false
        pendingPreCaptureRequested = false
    }

    /// Keep the active ATVV intent through physical release until the
    /// post-release grace owner commits the actual remote close.
    func deferVoiceInputCloseForPostReleaseGrace() -> Bool {
        voiceInputRequested || micOpenRequested
    }

    mutating func commitVoiceInputClose() {
        cancelVoiceInput()
        micOpenRequested = false
    }

    mutating func finishVoiceSession() {
        commitVoiceInputClose()
    }

    var canReuseReadyTransport: Bool {
        isStarted
            && connectionState == .ready
            && transportPrepared
            && atvvReady
    }

    mutating func cancelTransportPreparation() {
        guard !voiceInputRequested else { return }
        pendingPreCaptureRequested = false
    }

    var shouldRequestMicOpen: Bool {
        voiceInputRequested
            && atvvReady
            && !micOpenRequested
    }

    func shouldRetryConnection(
        peripheralState: CBPeripheralState?,
        isScanning: Bool,
        hasReconnectWork: Bool
    ) -> Bool {
        isStarted
            && voiceInputRequested
            && !transportPrepared
            && peripheralState != .connected
            && peripheralState != .connecting
            && !isScanning
            && !hasReconnectWork
    }
}

final class BLEBridge: NSObject {
    private struct AdoptedPhysicalRetirement {
        let sessionID: String
        var physicalReleaseObserved = false
        var audioStopDrainCompleted = false
    }

    private struct ReleasedHostMicOpenGrace {
        let sessionID: String
        let physicalReleaseObserved: Bool
    }

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
    /// Called for a physical HTT stream that exists before the matching HID
    /// press. This is candidate transport state, not VoicePress ownership.
    var onPreHIDPhysicalStreamChanged: ((Bool, Int /* sampleRate */) -> Void)?
    /// Called after a decoded remote audio frame is available. A stream can be
    /// announced before its first frame; the voice UI waits for this callback
    /// before opening the external voice dialog.
    var onAudioFrame: (() -> Void)?
    /// Called when the device connection state changes.
    var onConnectionChanged: ((Bool) -> Void)?
    /// Audio level meter update; arg is dBFS in [-60, 0].
    var onLevel: ((Double, Int /* peak */) -> Void)?
    /// Called after the old stream's AUDIO_STOP drain has fully retired and a
    /// deferred physical press may be admitted on a fresh lifecycle.
    var onVoiceSessionAdmissionAvailable: (() -> Void)?

    private let bleQueue: DispatchQueue
    private let bleQueueKey = DispatchSpecificKey<Void>()
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var audioChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?
    private var discoveredATVVCharacteristics = Set<CBUUID>()
    private var capabilitiesRequested = false
    private var transportState = BLEVoiceTransportState()

    // HID and ATVV are separate CoreBluetooth transports. Keep a reconnect
    // state machine for the voice transport so an HID reconnect does not
    // leave the remote microphone permanently offline.
    private var isScanning = false
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var handshakeTimeoutWorkItem: DispatchWorkItem?
    private var voiceCloseTimeoutWorkItem: DispatchWorkItem?
    private var audioStopDrainWorkItem: DispatchWorkItem?
    private lazy var postReleaseGrace = PostReleaseCaptureGraceController(queue: bleQueue)
    private let reconnectDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
    private let scanTimeout: TimeInterval = 8
    private let connectTimeout: TimeInterval = 12
    private let handshakeTimeout: TimeInterval = 4
    /// The remote often sends AUDIO_STOP before the final audio notifications
    /// reach CoreBluetooth. Keep the decoder and output path alive briefly so
    /// those packets can still be recorded and rendered.
    private let audioStopDrainDelay: TimeInterval = 0.35
    /// Preserve the existing bounded post-close safety window, but use it only
    /// to classify a missing AUDIO_STOP as a transport failure. A healthy
    /// session retires through the normal AUDIO_STOP drain and keeps READY.
    private let voiceCloseTimeout: TimeInterval = 0.60

    private let protocolHandler = ATVVProtocol()
    private var streamID: UInt8 = 0
    private var isStreaming = false
    private var streamOwnership: BLEStreamOwnership = .none
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
    private var streamStartedUptime: TimeInterval = 0
    private var streamSessionID = "NA"
    private var streamSessionOrigin: ATVVSessionOrigin = .unknown
    private var micOpenRequestCountForTestingStorage = 0
    private var micCloseRequestCountForTestingStorage = 0
    private var adoptedPhysicalRetirement: AdoptedPhysicalRetirement?
    private var releasedHostMicOpenGrace: ReleasedHostMicOpenGrace?
    private var keepAliveSequence = 0
    private var lastKeepAliveElapsedMilliseconds: Double?
    private var firstAudioAt: Date?
    private var lastAudioAt: Date?
    private var audioStopReceivedAt: Date?
    private var drainFinishedAt: Date?
    private var prewarmVoiceInputActive = false
    private var maxAudioFrameGap: TimeInterval = 0
    private var streamDrainFrameCount = 0
    private var audioFramesOutsideStream = 0
    private var streamNotificationTelemetry = BLENotificationTelemetry()
    private var streamDecodeRejectCount = 0
    private var streamZeroSampleDecodeCount = 0
    private var hasRecordedFirstP1A4AudioPacket = false
    private var p1A5VoiceOnsetDetector = P1A5VoiceOnsetDetector()
    private var wavRecorder: WavRecorder?
    // These seams keep the recording lifecycle testable without a live
    // peripheral. They do not participate in the production transport path.
    var recordingDirectoryOverrideForTesting: URL?
    private(set) var lastRecordingFailureForTesting: String?
    // Verbose PCM diagnostics are off unless explicitly requested.
    private static let diagnosticsEnabled =
        ProcessInfo.processInfo.environment["REMOTE_ORBIT_DIAGNOSTICS"] == "1"
    private var lastStartSearchAt = Date.distantPast

    /// A new voice session must not request micOpen while the previous stream
    /// still owns the AUDIO_STOP drain barrier. Otherwise its AUDIO_START can
    /// be rejected as a late packet and the physical press disappears.
    var isVoiceSessionAdmissionBlocked: Bool {
        if DispatchQueue.getSpecific(key: bleQueueKey) != nil {
            return audioStopDrainWorkItem != nil
        }
        return bleQueue.sync { audioStopDrainWorkItem != nil }
    }

    func queueIdentityForTesting() -> (label: String, isDedicatedQueue: Bool) {
        bleQueue.sync {
            (bleQueue.label, DispatchQueue.getSpecific(key: bleQueueKey) != nil)
        }
    }

    func deliverAudioFrameCallbackForTesting() {
        bleQueue.async { [weak self] in
            self?.notifyAudioFrame()
        }
    }

    var streamOwnershipForTesting: BLEStreamOwnership {
        bleQueue.sync { streamOwnership }
    }

    var micOpenRequestedForTesting: Bool {
        bleQueue.sync { transportState.micOpenRequested }
    }

    var micOpenRequestCountForTesting: Int {
        bleQueue.sync { micOpenRequestCountForTestingStorage }
    }

    var micCloseRequestCountForTesting: Int {
        bleQueue.sync { micCloseRequestCountForTestingStorage }
    }

    var voiceInputRequestedForTesting: Bool {
        bleQueue.sync { transportState.voiceInputRequested }
    }

    var postReleaseGraceWaitingForTesting: Bool {
        bleQueue.sync { postReleaseGrace.isWaiting }
    }

    var postReleaseGraceSessionIDForTesting: String? {
        bleQueue.sync { postReleaseGrace.currentSessionID }
    }

    var postReleaseGraceGenerationForTesting: UInt64 {
        bleQueue.sync { postReleaseGrace.generationForTesting }
    }

    var canReuseReadyTransportForTesting: Bool {
        bleQueue.sync { transportState.canReuseReadyTransport }
    }

    func beginPreHIDPhysicalStreamForTesting() {
        performOnBLEQueueSynchronously {
            AudioPipe.shared.beginRemoteCandidate()
            self.isStreaming = true
            self.streamOwnership = .preHIDPhysical
            self.streamSessionOrigin = .physicalHTT
            self.notifyPreHIDPhysicalStreaming(true)
        }
    }

    func requestVoiceActivationForTesting() {
        performOnBLEQueueSynchronously {
            try? self.protocolHandler.acceptCapabilities(
                ATVVCapabilities(
                    version: .v10,
                    codecs: ATVVCodec.adpcm16k.rawValue,
                    interactionModel: 0,
                    frameSize: 120
                )
            )
            self.transportState.prepareTransport()
            self.transportState.connectionState = .ready
            self.transportState.transportPrepared = true
            self.transportState.atvvReady = true
            self.transportState.requestVoiceInput()
            self.requestMicOpenIfReady()
        }
    }

    func releasePhysicalVoiceInputForTesting() {
        performOnBLEQueueSynchronously {
            self.stopVoiceInputOnBLEQueue()
        }
    }

    // Test seams exercise the real drain-retirement and transport-reset paths
    // without requiring a live CoreBluetooth peripheral.
    func beginAudioStopDrainForTesting() {
        performOnBLEQueueSynchronously {
            self.audioStopDrainWorkItem?.cancel()
            self.isStreaming = true
            self.audioStopDrainWorkItem = DispatchWorkItem { }
        }
    }

    func completeAudioStopDrainForTesting() {
        performOnBLEQueueSynchronously {
            self.finishAudioStopAfterDrain()
        }
    }

    func resetTransportForTesting() {
        performOnBLEQueueSynchronously {
            self.clearTransportState(notify: true)
        }
    }

    func beginAudioStartForTesting() {
        performOnBLEQueueSynchronously {
            self.isStreaming = true
            if self.streamOwnership == .none {
                self.streamOwnership = .voiceSession
            }
            self.wavRecorder = self.createRecordingIfEnabled(reason: "AUDIO_START_TEST")
        }
    }

    func requestVoiceInputForTesting() {
        performOnBLEQueueSynchronously {
            self.transportState.requestVoiceInput()
            self.transportState.micOpenRequested = true
        }
    }

    func completeNoAudioVoiceCloseForTesting() {
        performOnBLEQueueSynchronously {
            self.cancelPostReleaseGrace(reason: "test_close")
            self.sendMicCloseAfterPostReleaseGrace(sessionID: self.streamSessionID)
        }
    }

    func receiveAudioStartForTesting(reason: UInt8, streamID: UInt8) {
        performOnBLEQueueSynchronously {
            self.handleControl(
                Data([0x04, reason, ATVVCodec.adpcm16k.rawValue, streamID])
            )
        }
    }

    func expirePostReleaseGraceForTesting(
        sessionID: String,
        generation: UInt64
    ) -> Bool {
        if DispatchQueue.getSpecific(key: bleQueueKey) != nil {
            return postReleaseGrace.expireForTesting(
                sessionID: sessionID,
                generation: generation
            )
        }
        return bleQueue.sync {
            postReleaseGrace.expireForTesting(
                sessionID: sessionID,
                generation: generation
            )
        }
    }

    func appendRecordingDataForTesting(rawData: Data, samples: [Int16]) {
        performOnBLEQueueSynchronously {
            self.wavRecorder?.appendRawBytes(rawData)
            self.wavRecorder?.appendSamples(samples)
        }
    }

    func closeRecordingForTesting() {
        performOnBLEQueueSynchronously {
            self.wavRecorder?.close()
            self.wavRecorder = nil
            self.isStreaming = false
        }
    }

    private func performOnBLEQueueSynchronously(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: bleQueueKey) != nil {
            work()
        } else {
            bleQueue.sync(execute: work)
        }
    }

    override init() {
        bleQueue = DispatchQueue(
            label: "com.remoteorbit.ble",
            qos: .userInitiated
        )
        super.init()
        bleQueue.setSpecific(key: bleQueueKey, value: ())
        central = CBCentralManager(delegate: self, queue: bleQueue)
        postReleaseGrace.onExpire = { [weak self] sessionID, generation in
            self?.expirePostReleaseGrace(sessionID: sessionID, generation: generation)
        }
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

    static func streamOwnershipForAudioStart(
        micOpenRequested: Bool,
        voiceInputRequested: Bool
    ) -> BLEStreamOwnership {
        switch ATVVKeepAliveTelemetry.sessionOrigin(
            micOpenRequested: micOpenRequested,
            voiceInputRequested: voiceInputRequested
        ) {
        case .physicalHTT:
            return .preHIDPhysical
        case .hostMicOpen, .unknown:
            return .voiceSession
        }
    }

    func start() {
        bleQueue.async { [weak self] in
            self?.startOnBLEQueue()
        }
    }

    private func startOnBLEQueue() {
        if !transportState.isStarted {
            transportState.prepareTransport()
            reconnectAttempt = 0
        }
        updateDiagnosticTransportState()
        guard central.state == .poweredOn else {
            print("[BLE] 等待蓝牙就绪…")
            return
        }
        if !transportState.transportPrepared {
            transportState.beginConnection()
            updateDiagnosticTransportState()
        }
        tryDirectConnect()
    }

    func stop() {
        performOnBLEQueueSynchronously {
            self.stopOnBLEQueue()
        }
    }

    private func stopOnBLEQueue() {
        cancelPostReleaseGrace(reason: "transport_stop")
        transportState.isStarted = false
        transportState.transportPrepared = false
        transportState.pendingPreCaptureRequested = false
        transportState.voiceInputRequested = false
        transportState.micOpenRequested = false
        prewarmVoiceInputActive = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        voiceCloseTimeoutWorkItem?.cancel()
        voiceCloseTimeoutWorkItem = nil
        central.stopScan()
        isScanning = false
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        clearTransportState(notify: true)
        peripheral = nil
        updateDiagnosticTransportState()
    }

    /// Prepare ATVV while the short-vs-long classifier is pending. This is
    /// transport-only: it must never request micOpen or start an audio stream.
    func prepareVoiceTransport() {
        bleQueue.async { [weak self] in
            self?.prepareVoiceTransportOnBLEQueue()
        }
    }

    private func prepareVoiceTransportOnBLEQueue() {
        cancelPostReleaseGrace(reason: "new_transport_session")
        prewarmVoiceInputActive = true
        transportState.requestPendingPreCapture()
        updateDiagnosticTransportState()
        startOnBLEQueue()
        print("[BLE] transport prewarm requested; micOpen deferred until long confirmation")
    }

    /// Activate ATVV after long-press confirmation. This is the only
    /// production entry point that may request micOpen.
    func activateVoiceInput() {
        bleQueue.async { [weak self] in
            self?.activateVoiceInputOnBLEQueue()
        }
    }

    private func activateVoiceInputOnBLEQueue() {
        cancelPostReleaseGrace(reason: "new_voice_session")
        prewarmVoiceInputActive = false
        transportState.requestVoiceInput()
        updateDiagnosticTransportState()
        startOnBLEQueue()
        if transportState.shouldRetryConnection(
            peripheralState: peripheral?.state,
            isScanning: isScanning,
            hasReconnectWork: reconnectWorkItem != nil
        ) {
            print("[BLE] voice hold recovering transport after prewarm failure")
            tryDirectConnect()
        }
        requestMicOpenIfReady()
    }

    /// Cancel a transport-only prewarm without sending micClose. No voice
    /// activation has occurred in this state, so stopping the prepared link
    /// is sufficient to restore HID-only operation.
    func cancelVoiceTransportPreparation() {
        bleQueue.async { [weak self] in
            self?.cancelVoiceTransportPreparationOnBLEQueue()
        }
    }

    private func cancelVoiceTransportPreparationOnBLEQueue() {
        cancelPostReleaseGrace(reason: "transport_preparation_cancelled")
        guard !transportState.voiceInputRequested,
              !transportState.micOpenRequested else { return }
        transportState.cancelTransportPreparation()
        prewarmVoiceInputActive = false
        guard transportState.isStarted else { return }
        if transportState.canReuseReadyTransport {
            updateDiagnosticTransportState()
            print("[BLE] prepared transport retained READY after prewarm cancellation")
        } else {
            stopOnBLEQueue()
            print("[BLE] prepared transport cancelled; HID-only restored")
        }
    }

    /// Release the ATVV transport shortly after the physical voice key is
    /// released. The small drain window lets the remote deliver AUDIO_STOP,
    /// then closes only the current voice stream while retaining READY.
    func stopVoiceInput() {
        bleQueue.async { [weak self] in
            self?.stopVoiceInputOnBLEQueue()
        }
    }

    private func stopVoiceInputOnBLEQueue() {
        if !transportState.voiceInputRequested,
           !transportState.micOpenRequested {
            cancelVoiceTransportPreparationOnBLEQueue()
            return
        }
        guard transportState.deferVoiceInputCloseForPostReleaseGrace() else {
            cancelVoiceTransportPreparationOnBLEQueue()
            return
        }
        guard !postReleaseGrace.isWaiting else { return }

        let sessionID = VoiceTimingLogger.currentSessionID?.uuidString ?? streamSessionID
        if sessionID != "NA" {
            streamSessionID = sessionID
        }
        markAdoptedPhysicalReleaseIfNeeded(sessionID: sessionID)
        _ = postReleaseGrace.start(sessionID: sessionID)
        if transportState.micOpenRequested, adoptedPhysicalRetirement == nil {
            releasedHostMicOpenGrace = ReleasedHostMicOpenGrace(
                sessionID: sessionID,
                physicalReleaseObserved: true
            )
        } else {
            releasedHostMicOpenGrace = nil
        }
        print(postReleaseGraceLine(
            event: "POST_RELEASE_GRACE_STARTED",
            sessionID: sessionID,
            reason: "physical_release"
        ))
        retireAdoptedPhysicalVoiceIntentIfReady()
    }

    private var postReleaseGraceMilliseconds: Int {
        Int((postReleaseGrace.duration * 1_000).rounded())
    }

    private func postReleaseGraceLine(
        event: String,
        sessionID: String,
        reason: String
    ) -> String {
        ATVVKeepAliveTelemetry.postReleaseGraceLine(
            event: event,
            sessionID: sessionID,
            configuredGraceMilliseconds: postReleaseGraceMilliseconds,
            elapsedMilliseconds: currentStreamElapsedMilliseconds(),
            reason: reason
        )
    }

    @discardableResult
    private func cancelPostReleaseGrace(reason: String) -> Bool {
        guard let sessionID = postReleaseGrace.currentSessionID,
              postReleaseGrace.cancel(sessionID: sessionID) else {
            return false
        }
        releasedHostMicOpenGrace = nil
        print(postReleaseGraceLine(
            event: "POST_RELEASE_GRACE_CANCELLED",
            sessionID: sessionID,
            reason: reason
        ))
        return true
    }

    /// A new explicit physical ATVV start supersedes only a released host
    /// MIC_OPEN owner. The old request is retired locally because a v1.0
    /// MIC_CLOSE carries the mutable current stream ID and could close the
    /// newly arrived physical stream.
    private func supersedeReleasedHostMicOpenGraceIfNeeded(reason: UInt8) -> Bool {
        guard reason == 0x03,
              let owner = releasedHostMicOpenGrace,
              owner.physicalReleaseObserved,
              postReleaseGrace.currentSessionID == owner.sessionID,
              audioStopDrainWorkItem == nil,
              transportState.micOpenRequested else {
            return false
        }

        let oldSessionWasStreaming = isStreaming && streamOwnership == .voiceSession
        guard cancelPostReleaseGrace(reason: "physical_audio_start_superseded_host") else {
            return false
        }
        transportState.finishVoiceSession()
        releasedHostMicOpenGrace = nil
        updateDiagnosticTransportState()
        if oldSessionWasStreaming {
            notifyStreaming(false)
        }
        print(
            "[BLE] physical AUDIO_START superseded released HOST_MIC_OPEN "
                + "session_id=\(owner.sessionID); ATVV READY retained"
        )
        return true
    }

    private func cancelPostReleaseGraceIfIncompatibleSession() {
        guard let graceSessionID = postReleaseGrace.currentSessionID,
              let currentSessionID = VoiceTimingLogger.currentSessionID?.uuidString,
              graceSessionID != currentSessionID else {
            return
        }
        _ = cancelPostReleaseGrace(reason: "new_incompatible_audio_session")
    }

    private func markAdoptedPhysicalReleaseIfNeeded(sessionID: String) {
        guard var retirement = adoptedPhysicalRetirement,
              retirement.sessionID == sessionID else {
            return
        }
        retirement.physicalReleaseObserved = true
        adoptedPhysicalRetirement = retirement
    }

    private func retireAdoptedPhysicalVoiceIntentIfReady() {
        guard let retirement = adoptedPhysicalRetirement,
              retirement.physicalReleaseObserved,
              retirement.audioStopDrainCompleted,
              postReleaseGrace.currentSessionID == retirement.sessionID,
              !transportState.micOpenRequested,
              transportState.voiceInputRequested else {
            return
        }
        guard cancelPostReleaseGrace(reason: "adopted_physical_audio_stop") else {
            return
        }
        transportState.cancelVoiceInput()
        adoptedPhysicalRetirement = nil
        updateDiagnosticTransportState()
        print(
            "[BLE] adopted PHYSICAL_HTT voice intent retired after AUDIO_STOP drain; "
                + "ATVV READY retained"
        )
    }

    private func expirePostReleaseGrace(sessionID: String, generation: UInt64) {
        _ = generation
        let currentLoggerSessionID = VoiceTimingLogger.currentSessionID?.uuidString
        guard sessionID == streamSessionID || sessionID == currentLoggerSessionID else {
            print(postReleaseGraceLine(
                event: "POST_RELEASE_GRACE_CANCELLED",
                sessionID: sessionID,
                reason: "stale_session"
            ))
            return
        }

        print(postReleaseGraceLine(
            event: "POST_RELEASE_GRACE_EXPIRED",
            sessionID: sessionID,
            reason: "grace_elapsed"
        ))
        sendMicCloseAfterPostReleaseGrace(sessionID: sessionID)
    }

    private func sendMicCloseAfterPostReleaseGrace(sessionID: String) {
        let currentLoggerSessionID = VoiceTimingLogger.currentSessionID?.uuidString
        guard sessionID == streamSessionID || sessionID == currentLoggerSessionID else {
            return
        }

        let wasStreaming = isStreaming
        let hadMicOpen = transportState.micOpenRequested
        transportState.finishVoiceSession()
        if releasedHostMicOpenGrace?.sessionID == sessionID {
            releasedHostMicOpenGrace = nil
        }
        if adoptedPhysicalRetirement?.sessionID == sessionID {
            adoptedPhysicalRetirement = nil
        }
        if hadMicOpen, transportState.atvvReady {
            do {
                let command = try protocolHandler.micCloseCommand(streamID: streamID)
                writeCommand(command)
                micCloseRequestCountForTestingStorage += 1
                print("[BLE] TX micClose")
                if let sessionUUID = UUID(uuidString: sessionID) {
                    VoiceTimingLogger.markForSession("MIC_CLOSE_TX", sessionID: sessionUUID)
                } else {
                    VoiceTimingLogger.mark("MIC_CLOSE_TX")
                }
            } catch {
                print("[BLE] micClose error: \(error.localizedDescription)")
            }
        }
        scheduleVoiceCloseTimeoutIfNeeded()
        updateDiagnosticTransportState()
        if !wasStreaming {
            // MIC_OPEN can be accepted without a matching AUDIO_START. The
            // post-release close is then the truthful terminal boundary for
            // the opening attempt; notify the existing voice lifecycle owner
            // so it can finish the already-physical-up session through the
            // normal output-drain/trigger-release path.
            notifyStreaming(false)
        }
        print("[BLE] voice session closed; ATVV transport remains READY")
    }

    private func scheduleVoiceCloseTimeoutIfNeeded() {
        guard isStreaming else { return }
        voiceCloseTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.voiceCloseTimeoutWorkItem = nil
            guard self.isStreaming, self.audioStopDrainWorkItem == nil else { return }
            print("[BLE] AUDIO_STOP timeout after MIC_CLOSE; clearing stale transport state")
            let oldPeripheral = self.peripheral
            self.clearTransportState(notify: true)
            if let oldPeripheral {
                self.central.cancelPeripheralConnection(oldPeripheral)
                self.peripheral = nil
            }
        }
        voiceCloseTimeoutWorkItem = work
        bleQueue.asyncAfter(deadline: .now() + voiceCloseTimeout, execute: work)
    }

    func setRecordingEnabled(_ enabled: Bool) {
        performOnBLEQueueSynchronously {
            AppStorage.recordingEnabled = enabled
            print(
                "[RECORDING] setRecordingEnabled enabled=\(enabled) "
                    + "persisted=\(AppStorage.recordingEnabled) isStreaming=\(self.isStreaming)"
            )
            if enabled, self.isStreaming, self.wavRecorder == nil {
                self.wavRecorder = self.createRecordingIfEnabled(reason: "recording_toggle")
            } else if !enabled, let recorder = self.wavRecorder {
                recorder.close()
                self.wavRecorder = nil
            }
        }
    }

    private func createRecordingIfEnabled(reason: String) -> WavRecorder? {
        let enabled = AppStorage.recordingEnabled
        print(
            "[RECORDING] recorder_request reason=\(reason) "
                + "recordingEnabled=\(enabled)"
        )
        guard enabled else {
            print("[RECORDING] recorder_skipped reason=disabled")
            return nil
        }

        do {
            let recorder = try WavRecorder.createNext(
                prefix: "remote-orbit",
                directory: recordingDirectoryOverrideForTesting
                    ?? AppStorage.recordingsDirectory
            )
            lastRecordingFailureForTesting = nil
            print(
                "[RECORDING] recorder_created wav=\(recorder.wavPath) "
                    + "raw=\(recorder.rawPath)"
            )
            return recorder
        } catch {
            let message = error.localizedDescription
            lastRecordingFailureForTesting = message
            print(
                "[RECORDING] recorder_creation_failed reason=\(reason) "
                    + "error=\(message)"
            )
            return nil
        }
    }

    func clearRecordings() {
        performOnBLEQueueSynchronously {
            if let recorder = self.wavRecorder {
                recorder.close()
                self.wavRecorder = nil
            }
            AppStorage.clearFiles(in: AppStorage.recordingsDirectory)
        }
    }

    /// If we have a saved UUID from a previous scan, ask CoreBluetooth for
    /// the peripheral directly. This works even when the device is HID-paired
    /// (advertisement scan returns nothing in that case).
    private func tryDirectConnect() {
        guard transportState.isStarted,
              !transportState.transportPrepared,
              central.state == .poweredOn else { return }
        if transportState.connectionState != .connecting {
            transportState.beginConnection()
            updateDiagnosticTransportState()
        }
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
        guard transportState.isStarted, central.state == .poweredOn, !isScanning else { return }
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
        bleQueue.asyncAfter(
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
        guard transportState.isStarted else { return }
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
        transportState.beginConnection()
        updateDiagnosticTransportState()

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
                  self.peripheral === p,
                  !self.transportState.atvvReady
            else { return }
            print("[BLE] 连接请求超时，进入退避重连")
            self.connectionSetupFailed("connect-timeout")
        }
        connectTimeoutWorkItem = work
        bleQueue.asyncAfter(
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
        guard transportState.isStarted,
              transportState.voiceInputRequested,
              central.state == .poweredOn else { return }
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
        bleQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func evaluateATVVReadiness() {
        guard transportState.evaluateATVVReadiness() else {
            updateDiagnosticTransportState()
            return
        }
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        reconnectAttempt = 0
        updateDiagnosticTransportState()
        print("[BLE] ATVV 语音链路已就绪")
        notifyConnectionChanged(true)
        requestMicOpenIfReady()
    }

    private func clearTransportState(notify: Bool) {
        cancelPostReleaseGrace(reason: "transport_reset")
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        voiceCloseTimeoutWorkItem?.cancel()
        voiceCloseTimeoutWorkItem = nil
        let continuitySnapshot = AudioPipe.shared.endRemoteAudioDiagnostics()
        VoiceTimingLogger.mergeContinuityRenderSnapshot(continuitySnapshot)
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        if let recorder = wavRecorder {
            recorder.close()
            wavRecorder = nil
        }
        let wasStreaming = isStreaming
        let wasStreamOwnership = streamOwnership
        let hadVoiceIntent = transportState.voiceInputRequested
            || transportState.micOpenRequested
        adoptedPhysicalRetirement = nil
        isStreaming = false
        streamOwnership = .none
        pendingAudioStopReason = nil
        protocolHandler.endAudioStream()
        audioChar = nil
        commandChar = nil
        controlChar = nil
        discoveredATVVCharacteristics.removeAll()
        capabilitiesRequested = false
        transportState.micOpenRequested = false
        let wasReady = transportState.atvvReady
        transportState.markDisconnected()
        if wasStreaming || notify {
            if wasStreamOwnership == .preHIDPhysical {
                AudioPipe.shared.endRemoteCandidate()
                notifyPreHIDPhysicalStreaming(false)
            } else {
                notifyStreaming(false)
            }
        }
        if wasReady || (notify && hadVoiceIntent) {
            notifyConnectionChanged(false)
        }
        updateDiagnosticTransportState()
        retireAudioStopDrainBarrier()
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
        transportState.isStarted && peripheral === candidate
    }

    private func isCurrentNotificationCharacteristic(_ candidate: CBCharacteristic) -> Bool {
        switch candidate.uuid {
        case Self.audioUUID:
            return audioChar === candidate
        case Self.controlUUID:
            return controlChar === candidate
        default:
            return false
        }
    }

    private func writeCommand(_ data: Data) {
        guard let p = peripheral, let c = commandChar else { return }
        // The remote exposes both write modes. ATVV commands are one-way
        // control packets; using write-without-response avoids serializing the
        // mic-open path behind an unnecessary ATT acknowledgement while still
        // falling back safely on firmware that only exposes write-with-response.
        let type = commandWriteType(for: c)
        p.writeValue(data, for: c, type: type)
    }

    private func commandWriteType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
    }

    private func requestMicOpenIfReady() {
        guard transportState.voiceInputRequested,
              !transportState.micOpenRequested else { return }
        if adoptPreHIDPhysicalStreamIfNeeded() {
            return
        }
        guard transportState.canReuseReadyTransport else { return }
        micOpenRequestCountForTestingStorage += 1
        VoiceAttemptDiagnostics.shared.stage("MIC_OPEN_REQUEST")
        do {
            protocolHandler.prepareForAudioStream()
            pendingAudioSyncCount = 0
            writeCommand(try protocolHandler.micOpenCommand())
            transportState.micOpenRequested = true
            updateDiagnosticTransportState()
            print("[BLE] TX micOpen (voice hold)")
            VoiceTimingLogger.mark("MIC_OPEN_TX")
        } catch {
            VoiceAttemptDiagnostics.shared.stage(
                "MIC_OPEN_WRITE_FAILED",
                state: ["failure_category": .string("command_write")]
            )
            updateDiagnosticTransportState()
            print("[BLE] micOpen error: \(error.localizedDescription)")
        }
    }

    /// Send an ATVV keep-alive. Should be called every ~4 seconds while
    /// streaming to keep the device's audio stream open during long
    /// voice-key holds.
    private func sendKeepAlive() {
        keepAliveSequence += 1
        let elapsedMilliseconds = currentStreamElapsedMilliseconds()
        let protocolVersion = protocolHandler.capabilities?.version.description ?? "UNKNOWN"
        let reasons = ATVVKeepAliveGuard.rejectionReasons(
            isStreaming: isStreaming,
            codecPresent: protocolHandler.codec != nil,
            peripheralPresent: peripheral != nil,
            commandCharacteristicPresent: commandChar != nil
        )
        if !reasons.isEmpty {
            print(ATVVKeepAliveTelemetry.attemptLine(
                sessionID: streamSessionID,
                elapsedMilliseconds: elapsedMilliseconds,
                sequence: keepAliveSequence,
                protocolVersion: protocolVersion,
                streamID: streamID,
                command: nil,
                peripheralPresent: peripheral != nil,
                commandCharacteristicPresent: commandChar != nil,
                writeType: .notAttempted,
                canSendWriteWithoutResponse: peripheral?.canSendWriteWithoutResponse,
                result: .guardRejected,
                guardReasons: reasons
            ))
            return
        }

        guard let p = peripheral, let c = commandChar else { return }
        do {
            let cmd = try protocolHandler.keepAliveCommand(streamID: streamID)
            let writeType = commandWriteType(for: c)
            let writeTypeTelemetry: ATVVKeepAliveWriteType = writeType == .withoutResponse
                ? .withoutResponse
                : .withResponse
            print(ATVVKeepAliveTelemetry.attemptLine(
                sessionID: streamSessionID,
                elapsedMilliseconds: elapsedMilliseconds,
                sequence: keepAliveSequence,
                protocolVersion: protocolVersion,
                streamID: streamID,
                command: cmd,
                peripheralPresent: true,
                commandCharacteristicPresent: true,
                writeType: writeTypeTelemetry,
                canSendWriteWithoutResponse: p.canSendWriteWithoutResponse,
                result: .writeAttempted,
                guardReasons: []
            ))
            p.writeValue(cmd, for: c, type: writeType)
            lastKeepAliveElapsedMilliseconds = elapsedMilliseconds
        } catch {
            print(ATVVKeepAliveTelemetry.attemptLine(
                sessionID: streamSessionID,
                elapsedMilliseconds: elapsedMilliseconds,
                sequence: keepAliveSequence,
                protocolVersion: protocolVersion,
                streamID: streamID,
                command: nil,
                peripheralPresent: true,
                commandCharacteristicPresent: true,
                writeType: .notAttempted,
                canSendWriteWithoutResponse: p.canSendWriteWithoutResponse,
                result: .commandBuildFailed,
                guardReasons: []
            ))
            print("[BLE] keep-alive error: \(error.localizedDescription)")
        }
    }

    /// Start a periodic timer that keeps the ATVV voice stream alive while
    /// the remote thinks the user is holding the voice button.
    private var keepAliveTimer: DispatchSourceTimer?
    private func startKeepAliveTimer() {
        stopKeepAliveTimer()
        let timer = DispatchSource.makeTimerSource(queue: bleQueue)
        timer.schedule(deadline: .now() + 4.0, repeating: 4.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            print(ATVVKeepAliveTelemetry.timerLine(
                event: "KEEPALIVE_TIMER_FIRED",
                sessionID: self.streamSessionID,
                elapsedMilliseconds: self.currentStreamElapsedMilliseconds(),
                timestampNanoseconds: P1A4MonotonicClock.nowNanoseconds()
            ))
            self.sendKeepAlive()
        }
        timer.resume()
        keepAliveTimer = timer
        print(ATVVKeepAliveTelemetry.timerLine(
            event: "KEEPALIVE_TIMER_STARTED",
            sessionID: streamSessionID,
            elapsedMilliseconds: currentStreamElapsedMilliseconds(),
            timestampNanoseconds: P1A4MonotonicClock.nowNanoseconds()
        ))
    }
    private func stopKeepAliveTimer() {
        guard keepAliveTimer != nil else { return }
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        print(ATVVKeepAliveTelemetry.timerLine(
            event: "KEEPALIVE_TIMER_STOPPED",
            sessionID: streamSessionID,
            elapsedMilliseconds: currentStreamElapsedMilliseconds(),
            timestampNanoseconds: P1A4MonotonicClock.nowNanoseconds()
        ))
    }

    private func currentStreamElapsedMilliseconds() -> Double {
        guard streamStartedUptime > 0 else { return 0 }
        return max(0, ProcessInfo.processInfo.systemUptime - streamStartedUptime) * 1_000
    }

    private func notifyStreaming(_ on: Bool) {
        let sr = (protocolHandler.codec == .adpcm16k) ? 16_000 : 8_000
        updateDiagnosticTransportState()
        guard let callback = onStreamingChanged else { return }
        DispatchQueue.main.async {
            callback(on, sr)
        }
    }

    private func notifyPreHIDPhysicalStreaming(_ on: Bool) {
        let sr = (protocolHandler.codec == .adpcm16k) ? 16_000 : 8_000
        updateDiagnosticTransportState()
        guard let callback = onPreHIDPhysicalStreamChanged else { return }
        DispatchQueue.main.async {
            callback(on, sr)
        }
    }

    private func adoptPreHIDPhysicalStreamIfNeeded() -> Bool {
        guard isStreaming, streamOwnership == .preHIDPhysical else { return false }
        streamOwnership = .voiceSession
        streamSessionID = VoiceTimingLogger.currentSessionID?.uuidString ?? streamSessionID
        adoptedPhysicalRetirement = AdoptedPhysicalRetirement(sessionID: streamSessionID)
        updateDiagnosticTransportState()
        print(
            "[BLE] adopted active PHYSICAL_HTT stream into voice session "
                + "session_id=\(streamSessionID)"
        )
        notifyStreaming(true)
        return true
    }

    private func notifyAudioFrame() {
        guard let callback = onAudioFrame else { return }
        DispatchQueue.main.async(execute: callback)
    }

    private func notifyConnectionChanged(_ connected: Bool) {
        guard let callback = onConnectionChanged else { return }
        DispatchQueue.main.async {
            callback(connected)
        }
    }

    private func notifyLevel(_ db: Double, peak: Int) {
        guard let callback = onLevel else { return }
        DispatchQueue.main.async {
            callback(db, peak)
        }
    }

    private func updateDiagnosticTransportState() {
        let transportStateName = transportState.connectionState.rawValue
        let streamStateName: String
        if isStreaming {
            streamStateName = "streaming"
        } else if transportState.micOpenRequested {
            streamStateName = "opening"
        } else {
            streamStateName = "idle"
        }
        DiagnosticRuntimeHealthRegistry.shared.setString(
            "ble_peripheral_state",
            peripheral.map { String($0.state.rawValue) } ?? "unavailable"
        )
        DiagnosticRuntimeHealthRegistry.shared.setString(
            "ble_transport_state",
            transportStateName
        )
        DiagnosticRuntimeHealthRegistry.shared.setString(
            "ble_voice_stream_state",
            streamStateName
        )
        DiagnosticRuntimeHealthRegistry.shared.setBool(
            "transport_prepared",
            transportState.transportPrepared
        )
        DiagnosticRuntimeHealthRegistry.shared.setBool(
            "atvv_ready",
            transportState.atvvReady
        )
        DiagnosticRuntimeHealthRegistry.shared.setString(
            "mic_open_state",
            transportState.micOpenRequested
                ? (isStreaming ? "streaming" : "requested")
                : "idle"
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLE] 蓝牙已就绪")
            if transportState.voiceInputRequested {
                scheduleReconnect(reason: "bluetooth-ready", immediate: true)
            }
        case .poweredOff:
            print("[BLE] 蓝牙未开启")
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            central.stopScan()
            isScanning = false
            clearTransportState(notify: true)
            notifyConnectionChanged(false)
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
        guard self.peripheral === peripheral else { return }
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
        guard self.peripheral === peripheral else { return }
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
                switch c.uuid {
                case Self.audioUUID:
                    transportState.markAudioCharacteristicDiscovered()
                case Self.commandUUID:
                    transportState.markCommandCharacteristicDiscovered()
                case Self.controlUUID:
                    transportState.markControlCharacteristicDiscovered()
                default:
                    break
                }
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
                guard let self, !self.transportState.atvvReady else { return }
                self.connectionSetupFailed("capabilities-timeout")
            }
            handshakeTimeoutWorkItem = work
            bleQueue.asyncAfter(
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
        guard isCurrentNotificationCharacteristic(characteristic) else {
            print("[BLE] 忽略过期通知特征确认 \(characteristic.uuid.uuidString.prefix(8))")
            return
        }
        if let error {
            print("[BLE] 音频特征订阅失败: \(error.localizedDescription)")
            connectionSetupFailed("notification-subscription-failed")
        } else if !characteristic.isNotifying {
            print("[BLE] 音频特征未进入通知状态")
            connectionSetupFailed("notification-disabled")
        } else {
            switch characteristic.uuid {
            case Self.audioUUID:
                transportState.markAudioNotificationConfirmed()
            case Self.controlUUID:
                transportState.markControlNotificationConfirmed()
            default:
                break
            }
            evaluateATVVReadiness()
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
                transportState.markCapabilitiesAccepted()
                evaluateATVVReadiness()
            } catch {
                print("[BLE] caps error: \(error.localizedDescription)")
            }
        case .audioStart(let reason, let codec, let sid):
            switch Self.audioStartDisposition(
                drainPending: audioStopDrainWorkItem != nil,
                currentStreamID: streamID,
                incomingStreamID: sid,
                pendingAudioStopReason: pendingAudioStopReason
            ) {
            case .accepted:
                if !supersedeReleasedHostMicOpenGraceIfNeeded(reason: reason) {
                    cancelPostReleaseGraceIfIncompatibleSession()
                }
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
            pendingAudioStopReason = nil
            protocolHandler.beginAudioStream(codec: codec)
            // Some firmware emits AUDIO_START before the matching HID
            // key-down reaches the tap. Keep the same bounded pre-roll alive
            // from the earliest audio-stream notification.
            AudioPipe.shared.beginRemoteCandidate()
            streamID = sid
            isStreaming = true
            streamSessionOrigin = ATVVKeepAliveTelemetry.sessionOrigin(
                micOpenRequested: transportState.micOpenRequested,
                voiceInputRequested: transportState.voiceInputRequested
            )
            streamOwnership = Self.streamOwnershipForAudioStart(
                micOpenRequested: transportState.micOpenRequested,
                voiceInputRequested: transportState.voiceInputRequested
            )
            if streamOwnership == .preHIDPhysical {
                notifyPreHIDPhysicalStreaming(true)
            } else {
                notifyStreaming(true)
            }
            diagFrameCount = 0
            streamFrameCount = 0
            streamSampleCount = 0
            streamPeak = 0
            streamSumSquares = 0
            streamClippedSampleCount = 0
            streamNotificationTelemetry.reset()
            streamDecodeRejectCount = 0
            streamZeroSampleDecodeCount = 0
            hasRecordedFirstP1A4AudioPacket = false
            p1A5VoiceOnsetDetector.reset()
            if VoiceTimingLogger.p1A5Enabled {
                VoiceTimingLogger.recordIfAbsent(
                    "F1_audio_pipeline_start_requested",
                    timestampNanoseconds: P1A4MonotonicClock.nowNanoseconds()
                )
            }
            let continuityContext = VoiceTimingLogger.continuityCaptureContextForAudioStart()
            AudioPipe.shared.beginRemoteAudioDiagnostics(
                continuityContext: continuityContext
            )
            streamAudioSyncCount = pendingAudioSyncCount
            pendingAudioSyncCount = 0
            streamStartedAt = Date()
            streamStartedUptime = ProcessInfo.processInfo.systemUptime
            streamSessionID = VoiceTimingLogger.currentSessionID?.uuidString ?? "NA"
            keepAliveSequence = 0
            lastKeepAliveElapsedMilliseconds = nil
            audioStopReceivedAt = nil
            drainFinishedAt = nil
            firstAudioAt = nil
            lastAudioAt = nil
            maxAudioFrameGap = 0
            streamDrainFrameCount = 0
            audioFramesOutsideStream = 0
            wavRecorder = createRecordingIfEnabled(reason: "AUDIO_START")
            startKeepAliveTimer()
            print(
                "[BLE] AUDIO_START "
                    + "protocol_version=\(protocolHandler.capabilities?.version.description ?? "UNKNOWN") "
                    + "audio_start_reason=0x\(String(format: "%02x", reason)) "
                    + "codec=\(codec) stream_id=\(sid) streamID=\(sid) "
                    + "session_origin=\(streamSessionOrigin.rawValue)"
            )
            _ = VoiceTimingLogger.observeTransportStart(
                protocolVersion: protocolHandler.capabilities?.version.description ?? "unknown",
                mode: protocolHandler.capabilities?.version == .v10
                    ? "playback_realtime"
                    : "codec_selected",
                codec: codec.description,
                sampleRate: UInt64(max(0, codec.sampleRate)),
                reason: UInt64(reason),
                streamID: UInt64(sid)
            )
            VoiceTimingLogger.mark("AUDIO_START")
        case .audioStop(let reason):
            guard isStreaming else {
                print("[BLE] AUDIO_STOP duplicate ignored reason=0x\(String(format: "%02x", reason))")
                return
            }
            voiceCloseTimeoutWorkItem?.cancel()
            voiceCloseTimeoutWorkItem = nil
            if audioStopDrainWorkItem != nil {
                print("[BLE] AUDIO_STOP duplicate during drain ignored reason=0x\(String(format: "%02x", reason))")
                return
            }
            pendingAudioStopReason = reason
            audioStopReceivedAt = Date()
            let elapsedMilliseconds = currentStreamElapsedMilliseconds()
            let sinceLastKeepAlive = lastKeepAliveElapsedMilliseconds.map {
                elapsedMilliseconds - $0
            }
            print(ATVVKeepAliveTelemetry.audioStopLine(
                sessionID: streamSessionID,
                elapsedMilliseconds: elapsedMilliseconds,
                reason: reason,
                voiceKeyStillHeld: transportState.voiceInputRequested,
                lastKeepAliveElapsedMilliseconds: lastKeepAliveElapsedMilliseconds,
                millisecondsSinceLastKeepAlive: sinceLastKeepAlive
            ))
            if cancelPostReleaseGrace(reason: "remote_audio_stop") {
                transportState.finishVoiceSession()
            }
            stopKeepAliveTimer()
            VoiceTimingLogger.mark("AUDIO_STOP")
            VoiceTimingLogger.mark("AUDIO_DRAIN_BEGIN")
            print(
                "[BLE] AUDIO_STOP received; draining audio tail " +
                    "for \(Int(audioStopDrainDelay * 1_000))ms " +
                    "reason=0x\(String(format: "%02x", reason))"
            )
            let work = DispatchWorkItem { [weak self] in
                self?.finishAudioStopAfterDrain()
            }
            audioStopDrainWorkItem = work
            bleQueue.asyncAfter(
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
                        transportState.markCapabilitiesAccepted()
                        evaluateATVVReadiness()
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

        let packetTimestamp = P1A4MonotonicClock.nowNanoseconds()
        // The first timestamp is the first received BLE audio notification;
        // the last timestamp is overwritten for each packet without logging
        // from the notification callback.
        if !hasRecordedFirstP1A4AudioPacket {
            VoiceTimingLogger.record(
                "T1_first_ble_audio_packet",
                timestampNanoseconds: packetTimestamp
            )
            hasRecordedFirstP1A4AudioPacket = true
            if VoiceTimingLogger.p1A5Enabled {
                VoiceTimingLogger.recordIfAbsent(
                    "F2_first_ble_packet_received",
                    timestampNanoseconds: packetTimestamp
                )
            }
        }
        VoiceTimingLogger.record(
            "T2_last_ble_audio_packet_received",
            timestampNanoseconds: packetTimestamp
        )

        let now = Date()
        streamNotificationTelemetry.record(
            size: data.count,
            frameSize: protocolHandler.capabilities?.frameSize ?? 0,
            at: now.timeIntervalSinceReferenceDate
        )
        VoiceTimingLogger.observeNotification(
            bytes: data.count,
            gapNanoseconds: UInt64(max(0, streamNotificationTelemetry.lastNotificationGapMilliseconds * 1_000_000)),
            timestampNanoseconds: packetTimestamp
        )
        if VoiceTimingLogger.continuityEvidenceEnabled {
            VoiceTimingLogger.recordContinuityBLE(
                timestampNanoseconds: packetTimestamp,
                bytes: data.count
            )
        }
        wavRecorder?.appendRawBytes(data)

        switch protocolHandler.decodeAudioFrames(data) {
        case .rejected:
            streamDecodeRejectCount += 1
        case .waitingForFrame:
            return
        case .frames(let frames):
            for frame in frames {
                processDecodedFrame(frame, rawData: data, at: now)
            }
        }
    }

    private func processDecodedFrame(
        _ frame: ATVVDecodedFrame,
        rawData: Data,
        at now: Date
    ) {
        guard !frame.samples.isEmpty else {
            streamZeroSampleDecodeCount += 1
            return
        }
        let decodedTimestamp = P1A4MonotonicClock.nowNanoseconds()
        VoiceTimingLogger.record(
            "T3_last_decoded_pcm_frame",
            timestampNanoseconds: decodedTimestamp
        )
        VoiceTimingLogger.observeDecoded(
            frameCount: 1,
            sampleCount: frame.samples.count,
            timestampNanoseconds: decodedTimestamp
        )
        VoiceTimingLogger.observeSupply(submittedFrames: frame.samples.count)
        if VoiceTimingLogger.continuityEvidenceEnabled {
            VoiceTimingLogger.recordContinuityDecoded(
                timestampNanoseconds: decodedTimestamp,
                frameCount: 1,
                sampleCount: frame.samples.count
            )
        }
        if VoiceTimingLogger.p1A5Enabled {
            VoiceTimingLogger.recordIfAbsent(
                "F3_first_pcm_decoded",
                timestampNanoseconds: decodedTimestamp
            )
            if let candidate = p1A5VoiceOnsetDetector.analyze(
                samples: frame.samples,
                frameIndex: streamFrameCount,
                timestampNanoseconds: decodedTimestamp
            ) {
                VoiceTimingLogger.recordVoiceOnset(
                    candidate,
                    detectedAtNanoseconds: decodedTimestamp
                )
            }
        }
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

        if Self.diagnosticsEnabled, diagFrameCount < 5 {
            let rawHex = rawData.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            let samHex = frame.samples.prefix(8).map { String($0) }.joined(separator: ",")
            print("[AUDIO-DIAG] frame#\(diagFrameCount) seq=\(frame.sequence) raw[\(rawHex)] decoded[\(samHex)]")
            diagFrameCount += 1
        }

        wavRecorder?.appendSamples(frame.samples)

        // Queue the decoded frame before opening the external voice dialog.
        AudioPipe.shared.feed(samples: frame.samples)
        notifyAudioFrame()
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
        if needsLevel, now.timeIntervalSince(levelLogAt) >= 0.5 {
            let rms = levelCount > 0 ? sqrt(Double(levelSumSq) / Double(levelCount)) : 0
            let peak = levelPeak
            let db = rms > 0 ? 20.0 * log10(rms / 32768.0) : -120
            let bar = meterBar(level: db)
            if Self.diagnosticsEnabled {
                print(String(format: "[LVL] %@ ATVV rms=%.0f peak=%d  %.0f dBFS",
                             bar, rms, peak, db))
            }
            notifyLevel(db, peak: peak)
            levelSumSq = 0
            levelCount = 0
            levelPeak = 0
            levelLogAt = now
        }
    }

    private func finishAudioStopAfterDrain() {
        guard audioStopDrainWorkItem != nil else { return }
        voiceCloseTimeoutWorkItem?.cancel()
        voiceCloseTimeoutWorkItem = nil
        guard isStreaming else {
            retireAudioStopDrainBarrier()
            return
        }

        drainFinishedAt = Date()
        let timing = AudioDeliveryTiming.measure(
            streamStartedAt: streamStartedAt.timeIntervalSinceReferenceDate,
            audioStopReceivedAt: audioStopReceivedAt?.timeIntervalSinceReferenceDate,
            lastAudioAt: lastAudioAt?.timeIntervalSinceReferenceDate,
            drainFinishedAt: drainFinishedAt?.timeIntervalSinceReferenceDate
        )
        let endedStreamOwnership = streamOwnership
        let endedStreamSessionID = streamSessionID
        if endedStreamOwnership == .voiceSession,
           streamSessionOrigin == .physicalHTT,
           !transportState.micOpenRequested,
           var retirement = adoptedPhysicalRetirement,
           retirement.sessionID == endedStreamSessionID {
            retirement.audioStopDrainCompleted = true
            adoptedPhysicalRetirement = retirement
        }
        isStreaming = false
        streamOwnership = .none
        protocolHandler.endAudioStream()
        if lastAudioAt != nil {
            VoiceTimingLogger.mark("LAST_AUDIO_FRAME")
        }
        VoiceTimingLogger.mark("DRAIN_FINISH")
        if endedStreamOwnership == .preHIDPhysical {
            AudioPipe.shared.endRemoteCandidate()
            notifyPreHIDPhysicalStreaming(false)
        } else {
            notifyStreaming(false)
        }
        levelSumSq = 0
        levelCount = 0
        levelPeak = 0
        notifyLevel(-120, peak: 0)
        diagFrameCount = 0
        if let w = wavRecorder {
            let wavPath = w.wavPath
            w.close()
            let wavSamples = w.totalSamples
            print("[WAV] closed \(w.filename)")
            print(String(
                format: "[AUDIO-PATH] WAV_SUMMARY path=%@ wav_samples=%llu wav_audio_ms=%.1f lifecycle_elapsed_ms=%.1f",
                wavPath,
                wavSamples,
                Double(wavSamples) / Double(w.recordedSampleRate) * 1_000,
                timing.lifecycleElapsedSeconds * 1_000
            ))
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
            "[BLE] AUDIO_SUMMARY streamID=\(streamID) session_id=\(streamSessionID)",
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
        let sampleRate = protocolHandler.codec?.sampleRate ?? 0
        let delivery = AudioDeliveryAccounting.measure(
            decodedSamples: streamSampleCount,
            sampleRate: sampleRate,
            elapsedSeconds: timing.measurementElapsedSeconds
        )
        VoiceTimingLogger.observeTransportMetrics(
            notificationCount: streamNotificationTelemetry.notificationCount,
            notificationBytes: streamNotificationTelemetry.notificationBytesTotal,
            notificationSizeMin: streamNotificationTelemetry.notificationSizeMin,
            notificationSizeMax: streamNotificationTelemetry.notificationSizeMax,
            notificationSizeDistribution: streamNotificationTelemetry.fixedSizeHistogramDescription,
            notificationFrameSizeDistribution: streamNotificationTelemetry.frameSizeHistogramDescription,
            notificationMaxGapMilliseconds: streamNotificationTelemetry.maxNotificationGapMilliseconds,
            notificationP95GapMilliseconds: streamNotificationTelemetry.p95NotificationGapMilliseconds,
            gapOver20Milliseconds: streamNotificationTelemetry.gapOver20Milliseconds,
            gapOver30Milliseconds: streamNotificationTelemetry.gapOver30Milliseconds,
            gapOver50Milliseconds: streamNotificationTelemetry.gapOver50Milliseconds,
            gapOver100Milliseconds: streamNotificationTelemetry.gapOver100Milliseconds,
            decodeRejectCount: streamDecodeRejectCount,
            zeroSampleDecodeCount: streamZeroSampleDecodeCount,
            audioSyncCount: streamAudioSyncCount,
            decodedAudioDurationMilliseconds: sampleRate > 0
                ? Double(streamSampleCount) / Double(sampleRate) * 1_000
                : 0,
            measurementElapsedMilliseconds: timing.measurementElapsedSeconds * 1_000,
            expectedSamples: delivery.expectedSamples,
            deliveredSamples: streamSampleCount,
            deliveryRatio: delivery.deliveryRatio,
            deficitSamples: delivery.deficitSamples,
            deficitMilliseconds: delivery.deficitMilliseconds
        )
        let pipe = AudioPipe.shared.takeAudioDiagnosticsSnapshot()
        VoiceTimingLogger.observeAudioPipeSnapshot(pipe)
        if let timestamp = pipe.lastRemoteSubmittedMonotonicNanoseconds {
            VoiceTimingLogger.record(
                "T4_last_playout_frame_submitted",
                timestampNanoseconds: timestamp
            )
        }
        if let timestamp = pipe.lastRemoteRenderedMonotonicNanoseconds {
            VoiceTimingLogger.record(
                "T4R_last_playout_frame_rendered",
                timestampNanoseconds: timestamp
            )
        }
        let queueDepthMinMS = Double(pipe.minQueueDepthFrames) / 48_000 * 1_000
        let queueDepthMaxMS = Double(pipe.maxQueueDepthFrames) / 48_000 * 1_000
        let queueDepthCurrentMS = Double(pipe.currentQueueDepthFrames) / 48_000 * 1_000
        print(String(
            format: "[AUDIO-PATH] BLE_DECODE_SUMMARY stream=%d session_id=%@ codec=%@ sample_rate=%d frame_size=%d measurement_elapsed_ms=%.1f lifecycle_elapsed_ms=%.1f audio_stop_at_ms=%@ last_audio_at_ms=%@ stop_to_last_audio_ms=%@ drain_finish_ms=%@ post_last_audio_drain_ms=%@ notifications=%d notification_bytes=%d notification_size_min=%d notification_size_max=%d notification_size_distribution=%@ frame_size_distribution=%@ decoded_frames=%d decoded_samples=%d decoded_audio_ms=%.1f delivery_ratio=%.3f expected_samples=%d deficit_samples=%d deficit_ms=%.1f decode_rejects=%d zero_sample_decodes=%d max_notification_gap_ms=%.1f p95_notification_gap_ms=%.1f gap_gt20ms=%d gap_gt30ms=%d gap_gt50ms=%d gap_gt100ms=%d",
            streamID,
            streamSessionID,
            protocolHandler.codec?.description ?? "unknown",
            sampleRate,
            protocolHandler.capabilities?.frameSize ?? 0,
            timing.measurementElapsedSeconds * 1_000,
            timing.lifecycleElapsedSeconds * 1_000,
            formatMilliseconds(timing.audioStopAtMilliseconds),
            formatMilliseconds(timing.lastAudioAtMilliseconds),
            formatMilliseconds(timing.stopToLastAudioMilliseconds),
            formatMilliseconds(timing.drainFinishAtMilliseconds),
            formatMilliseconds(timing.postLastAudioDrainMilliseconds),
            streamNotificationTelemetry.notificationCount,
            streamNotificationTelemetry.notificationBytesTotal,
            streamNotificationTelemetry.notificationSizeMin,
            streamNotificationTelemetry.notificationSizeMax,
            streamNotificationTelemetry.fixedSizeHistogramDescription,
            streamNotificationTelemetry.frameSizeHistogramDescription,
            streamFrameCount,
            streamSampleCount,
            sampleRate > 0 ? Double(streamSampleCount) / Double(sampleRate) * 1_000 : 0,
            delivery.deliveryRatio,
            delivery.expectedSamples,
            delivery.deficitSamples,
            delivery.deficitMilliseconds,
            streamDecodeRejectCount,
            streamZeroSampleDecodeCount,
            streamNotificationTelemetry.maxNotificationGapMilliseconds,
            streamNotificationTelemetry.p95NotificationGapMilliseconds,
            streamNotificationTelemetry.gapOver20Milliseconds,
            streamNotificationTelemetry.gapOver30Milliseconds,
            streamNotificationTelemetry.gapOver50Milliseconds,
            streamNotificationTelemetry.gapOver100Milliseconds
        ))
        print(String(
            format: "[AUDIO-PATH] AUDIOPIPE_SUMMARY stream=%d session_id=%@ render_callback_count=%d render_requested_frames=%d render_filled_frames=%d render_unfilled_frames=%d underrun_callbacks=%d underrun_duration_ms=%.1f max_underrun_frames=%d active_remote_underrun_frames=%d active_remote_underrun_callbacks=%d tail_rendered_frames=%d tail_empty_callbacks=%d idle_render_callbacks=%d queue_depth_current_ms=%.1f queue_depth_min_ms=%.1f queue_depth_max_ms=%.1f overflow_dropped_frames=%d overflow_dropped_ms=%.1f compaction_count=%d reserve_candidate_ms=%d reserve_configured_frames=%d reserve_state=%@ reserve_start_depth_frames=%d reserve_wait_ms=%.1f reserve_start_reason=%@ reserve_selected_default_ms=%d",
            streamID,
            streamSessionID,
            pipe.renderCallbackCount,
            pipe.renderRequestedFrames,
            pipe.renderFilledFrames,
            pipe.renderUnfilledFrames,
            pipe.underrunCallbackCount,
            pipe.totalUnderrunMilliseconds,
            pipe.maxUnderrunFrames,
            pipe.renderUnfilledFrames,
            pipe.underrunCallbackCount,
            pipe.tailRenderedFrames,
            pipe.tailEmptyCallbackCount,
            pipe.idleRenderCallbackCount,
            queueDepthCurrentMS,
            queueDepthMinMS,
            queueDepthMaxMS,
            pipe.overflowDroppedFrames,
            pipe.overflowDroppedMilliseconds,
            pipe.compactionCount,
            pipe.reserveCandidate.milliseconds,
            pipe.reserveConfiguredFrames,
            pipe.reserveState == .started ? "started" : "waiting_for_reserve",
            pipe.reserveStartDepthFrames ?? 0,
            pipe.reserveWaitDurationMilliseconds,
            pipe.reserveStartReason.map(String.init(describing:)) ?? "unavailable",
            pipe.reserveSelectedDefaultCandidate.milliseconds
        ))
        let continuitySnapshot = AudioPipe.shared.endRemoteAudioDiagnostics()
        VoiceTimingLogger.mergeContinuityRenderSnapshot(continuitySnapshot)
        VoiceTimingLogger.observeLongTermAudioSnapshot(
            AudioPipe.shared.takeLongTermObservationSnapshot()
        )
        let reason = pendingAudioStopReason ?? 0
        pendingAudioStopReason = nil
        print("[BLE] AUDIO_STOP drained reason=0x\(String(format: "%02x", reason))")
        retireAdoptedPhysicalVoiceIntentIfReady()
        retireAudioStopDrainBarrier()
    }

    /// Retire the AUDIO_STOP drain barrier from every production lifecycle.
    /// The admission callback is emitted only when this transition actually
    /// clears an active barrier, so reset/stop/normal completion and a stale
    /// canceled completion remain exactly-once.
    @discardableResult
    private func retireAudioStopDrainBarrier() -> Bool {
        guard audioStopDrainWorkItem != nil else { return false }
        audioStopDrainWorkItem?.cancel()
        audioStopDrainWorkItem = nil
        notifyVoiceSessionAdmissionAvailable()
        return true
    }

    private func notifyVoiceSessionAdmissionAvailable() {
        guard let callback = onVoiceSessionAdmissionAvailable else { return }
        DispatchQueue.main.async(execute: callback)
    }

    private func formatMilliseconds(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "n/a"
    }

    /// Convert dBFS to a tiny ASCII bar for at-a-glance logs.
    private func meterBar(level: Double) -> String {
        let clamped = max(-60, min(0, level))
        let n = (clamped + 60) / 6   // 0..10 segments
        return "[" + String(repeating: "▓", count: Int(n)) +
                     String(repeating: "░", count: 10 - Int(n)) + "]"
    }
}
