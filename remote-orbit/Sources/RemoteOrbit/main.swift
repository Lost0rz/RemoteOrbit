// RemoteOrbit: a multi-mode control surface for the Xiaomi Bluetooth Voice Remote 2 Pro.
//
// 1. Voice key (HID F5) → device-scoped physical left-Option mapping
//    (synthetic Option remains only as a fallback if hidutil cannot apply)
// 2. ATVV voice stream over BLE → decoded ADPCM → RemoteOrbit Mic 2ch
//    → voice application hears the selected source
//
// macOS-only. Requires:
//   * 2 Pro paired in System Settings → Bluetooth
//   * Accessibility permission (System Settings → Privacy & Security →
//     Accessibility) for the CGEvent tap that filters F6
//   * RemoteOrbitAudio.driver installed and visible as RemoteOrbit Mic 2ch in
//     System Settings → Sound → Input/Output
//   * configurable IME trigger and persistent voice-input session
//
// Run:   swift run
// Quit:  menu bar icon → 退出, or Ctrl+C

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreAudio
import CoreGraphics
import Darwin
import IOKit.hid
import Foundation
import SwiftUI

// MARK: - Virtual key codes

enum VK {
    static let option: CGKeyCode = 0x3A
    static let rightOption: CGKeyCode = 0x3D
    /// The 2 Pro reports voice key as USB HID usage 0x3D which macOS maps
    /// to virtual keyCode 0x60 (F5). Despite being labeled "F6" in some
    /// hardware profiles, the actual delivery is F5. Verified empirically.
    static let voiceKey: CGKeyCode = 0x60
}

// MARK: - Key synthesizer

enum Key {
    /// Lets the event tap distinguish Bridge-generated Option events from
    /// physical keyboards, other Bluetooth buttons, and external remappers.
    static let syntheticMarker: Int64 = 0x56_52_42_52 // "VRBR"

    /// Walkie-talkie style: Option key down only (no matching up). Pair with `optionUp`.
    static func optionDown() {
        voiceTriggerDown(.leftOption)
    }
    static func optionUp() {
        voiceTriggerUp(.leftOption)
    }

    static func voiceTriggerDown(_ key: VoiceTriggerKey) {
        postVoiceTrigger(key, keyDown: true)
    }

    static func voiceTriggerUp(_ key: VoiceTriggerKey) {
        postVoiceTrigger(key, keyDown: false)
    }

    /// A deliberate short modifier click for a persistent voice-input session.
    /// Keep the selected modifier down long enough for input methods to classify it.
    static func voiceTriggerTap(
        _ key: VoiceTriggerKey,
        completion: (() -> Void)? = nil
    ) {
        voiceTriggerDown(key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            voiceTriggerUp(key)
            completion?()
        }
    }

    /// Preserve the existing Option API and its 60 ms click duration.
    static func optionTap(completion: (() -> Void)? = nil) {
        voiceTriggerTap(.leftOption, completion: completion)
    }

    /// Emit both the modifier-state transition and the normal keyboard event
    /// using the selected key's Carbon virtual key code and modifier flag.
    private static func postVoiceTrigger(_ key: VoiceTriggerKey, keyDown: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let flags: CGEventFlags = keyDown ? key.syntheticModifierFlags : []

        if let flagsEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: key.cgKeyCode,
            keyDown: keyDown
        ) {
            flagsEvent.type = .flagsChanged
            flagsEvent.flags = flags
            flagsEvent.setIntegerValueField(
                .eventSourceUserData,
                value: syntheticMarker
            )
            flagsEvent.post(tap: .cghidEventTap)
        }

        if let keyEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: key.cgKeyCode,
            keyDown: keyDown
        ) {
            keyEvent.flags = flags
            keyEvent.setIntegerValueField(
                .eventSourceUserData,
                value: syntheticMarker
            )
            keyEvent.post(tap: .cgSessionEventTap)
        }
    }

    /// 合成任意 keyCode 的按键事件（down 或 up）。
    /// 标记 syntheticMarker 以防止被自身的 CGEvent tap 重复拦截。
    static func synthesize(keyCode: CGKeyCode, keyDown: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let e = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown) {
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Device-scoped voice-key mapping

/// Map the supported remote's F5 usage to the selected VoiceTriggerKey at the
/// HID event-system layer. AppController supplies the runtime authority key.
enum RemoteVoiceKeyMapping {
    private static let lock = NSLock()
    private static var enabled = false
    private static let matching = "{\"VendorID\":0x2717,\"ProductID\":0x32B8}"
    private static let source = "0x70000003E"
    private static let diagnosticReadbackQueue = DispatchQueue(
        label: "com.remoteorbit.voice-trigger-hid-diagnostic-readback",
        qos: .utility
    )
    static let emptyMappingJSON = "{\"UserKeyMapping\":[]}"

    static func mappingJSON(for target: VoiceTriggerKey) -> String {
        let destination = "0x" + String(target.hidutilDestination, radix: 16, uppercase: true)
        return "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":\(source),\"HIDKeyboardModifierMappingDst\":\(destination)}]}"
    }

    static var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    @discardableResult
    static func setEnabled(
        _ shouldEnable: Bool,
        target: VoiceTriggerKey,
        verificationCompletion: ((VoiceDiagnosticHIDVerification) -> Void)? = nil
    ) -> Bool {
        VoiceDiagnosticLogger.shared.log(
            category: "hid",
            event: "HID_APPLY_REQUEST",
            key: target,
            fields: [
                "enabled": shouldEnable,
                "source": source,
                "target": shouldEnable ? String(format: "0x%llX", target.hidutilDestination) : "none",
                "matching_vendor": "0x2717",
                "matching_product": "0x32B8",
            ]
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = [
            "property", "--matching", matching,
            "--set", shouldEnable ? mappingJSON(for: target) : emptyMappingJSON,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[HID-MAP] 执行 hidutil 失败: \(error.localizedDescription)")
            VoiceDiagnosticLogger.shared.log(
                category: "hid",
                event: "HID_APPLY_EXIT",
                key: target,
                fields: [
                    "enabled": shouldEnable,
                    "status": -1,
                    "requested_target": shouldEnable ? String(format: "0x%llX", target.hidutilDestination) : "none",
                    "error": error.localizedDescription,
                ]
            )
            lock.lock()
            enabled = false
            lock.unlock()
            scheduleDiagnosticReadback(
                enabled: shouldEnable,
                target: target,
                verificationCompletion: verificationCompletion
            )
            return false
        }

        let succeeded = process.terminationStatus == 0
        lock.lock()
        enabled = shouldEnable && succeeded
        lock.unlock()
        print(
            "[HID-MAP] 遥控器语音键 → \(target.displayName) " +
            (shouldEnable && succeeded ? "已启用" : shouldEnable ? "启用失败" : "已关闭")
        )
        VoiceDiagnosticLogger.shared.log(
            category: "hid",
            event: "HID_APPLY_EXIT",
            key: target,
            fields: [
                "enabled": shouldEnable,
                "status": Int(process.terminationStatus),
                "requested_target": shouldEnable ? String(format: "0x%llX", target.hidutilDestination) : "none",
            ]
        )
        scheduleDiagnosticReadback(
            enabled: shouldEnable,
            target: target,
            verificationCompletion: verificationCompletion
        )
        return succeeded
    }

    private static func scheduleDiagnosticReadback(
        enabled shouldEnable: Bool,
        target: VoiceTriggerKey,
        verificationCompletion: ((VoiceDiagnosticHIDVerification) -> Void)? = nil
    ) {
        diagnosticReadbackQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
            process.arguments = [
                "property", "--matching", matching,
                "--get", "UserKeyMapping",
            ]
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            let status: Int32
            do {
                try process.run()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                status = process.terminationStatus
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                VoiceDiagnosticLogger.shared.log(
                    category: "hid",
                    event: "HID_READBACK",
                    key: target,
                    fields: [
                        "exit_status": Int(status),
                        "stdout": stdout,
                        "stderr": stderr,
                        "requested_enabled": shouldEnable,
                    ]
                )
                let verification = VoiceDiagnosticHIDMappingParser.verify(
                    stdout: stdout,
                    stderr: stderr,
                    exitStatus: status,
                    requested: shouldEnable ? target : nil
                )
                VoiceDiagnosticLogger.shared.log(
                    category: "hid",
                    event: "HID_VERIFY",
                    key: target,
                    fields: [
                        "requested": shouldEnable ? String(format: "0x%llX", target.hidutilDestination) : "none",
                        "observed": VoiceDiagnosticHIDMappingParser.observedVoiceDestination(in: stdout)
                            .map { String(format: "0x%llX", $0) } ?? "none",
                        "result": verification.rawValue,
                    ]
                )
                verificationCompletion?(verification)
            } catch {
                VoiceDiagnosticLogger.shared.log(
                    category: "hid",
                    event: "HID_READBACK",
                    key: target,
                    fields: [
                        "exit_status": -1,
                        "stdout": "",
                        "stderr": error.localizedDescription,
                        "requested_enabled": shouldEnable,
                    ]
                )
                VoiceDiagnosticLogger.shared.log(
                    category: "hid",
                    event: "HID_VERIFY",
                    key: target,
                    fields: [
                        "requested": shouldEnable ? String(format: "0x%llX", target.hidutilDestination) : "none",
                        "observed": "none",
                        "result": VoiceDiagnosticHIDVerification.unparseable.rawValue,
                    ]
                )
                verificationCompletion?(.unparseable)
            }
        }
    }
}

// MARK: - Voice-button gesture state machine

/// The physical voice button exposes a persistent IME session toggle and a
/// remote-microphone hold. A hold inside an open IME session is audio-only;
/// outside that session, the momentary trigger behavior remains unchanged.
enum VoiceSessionMode: Equatable {
    case idle
    case persistentOpen
}

enum RemoteSegmentTriggerPolicy: Equatable {
    case momentaryTrigger
    case audioOnly
}

enum PendingHardwareOptionRepressBeginResult: Equatable {
    case armedAwaitingOldUpAcknowledgement
    case armedWithoutOldUpOwner
    case rejected

    var isArmed: Bool {
        self != .rejected
    }

    var awaitsOldUpAcknowledgement: Bool {
        self == .armedAwaitingOldUpAcknowledgement
    }
}

/// A cancellable one-shot used only for the private LONG-only admission
/// candidate. The factory is injectable so lifecycle stress tests can drive
/// callbacks without creating thousands of real GCD timers.
final class VoicePressCandidateTimer {
    private let cancelAction: () -> Void
    private var cancelled = false

    init(cancelAction: @escaping () -> Void) {
        self.cancelAction = cancelAction
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        cancelAction()
    }

    var isCancelled: Bool { cancelled }

    static func gcdFactory(
        delay: TimeInterval,
        fire: @escaping () -> Void
    ) -> VoicePressCandidateTimer {
        let work = DispatchWorkItem(block: fire)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, delay),
            execute: work
        )
        return VoicePressCandidateTimer(cancelAction: work.cancel)
    }
}

final class VoicePressCoordinator {
    enum State: Equatable {
        case idle
        case opening
        case streaming
        case draining
        case pending
        case holding
    }

    private struct PendingRepress {
        let sessionID: UUID
        let physicalDownAt: TimeInterval
        let onShortTap: (() -> Void)?
        let usesLocalMicrophone: Bool
        let togglesPersistentVoiceSession: Bool
        let bypassesShortClassification: Bool
        let usesHardwareOption: Bool
        let preparesRemoteTransport: Bool
        let classifiedTriggerKey: VoiceTriggerKey?
        let isDirectSession: Bool
        let directProfile: VoiceInputProfile?
        var isStillHeld = true

        init(
            sessionID: UUID,
            physicalDownAt: TimeInterval,
            onShortTap: (() -> Void)?,
            usesLocalMicrophone: Bool,
            togglesPersistentVoiceSession: Bool,
            bypassesShortClassification: Bool,
            usesHardwareOption: Bool,
            preparesRemoteTransport: Bool,
            classifiedTriggerKey: VoiceTriggerKey?,
            isDirectSession: Bool = false,
            directProfile: VoiceInputProfile? = nil,
            isStillHeld: Bool = true
        ) {
            self.sessionID = sessionID
            self.physicalDownAt = physicalDownAt
            self.onShortTap = onShortTap
            self.usesLocalMicrophone = usesLocalMicrophone
            self.togglesPersistentVoiceSession = togglesPersistentVoiceSession
            self.bypassesShortClassification = bypassesShortClassification
            self.usesHardwareOption = usesHardwareOption
            self.preparesRemoteTransport = preparesRemoteTransport
            self.classifiedTriggerKey = classifiedTriggerKey
            self.isDirectSession = isDirectSession
            self.directProfile = directProfile
            self.isStillHeld = isStillHeld
        }
    }

    private enum DeferredRepressWaitReason: Equatable {
        case previousRoute
        case audioDrain
        case directOutputDrain
    }

    private struct PendingPersistentToggle {
        let gestureID: UUID
        let expectedFromMode: VoiceSessionMode
        let targetMode: VoiceSessionMode
        let triggerKey: VoiceTriggerKey
        let purpose: String
        let waitingGateOwner: UUID
    }

    private enum LongOnlyTriggerStrategy {
        case hardware
        case syntheticHandoff
    }

    private struct LongOnlyCandidate {
        let sessionID: UUID
        let physicalDownAt: TimeInterval
        let profile: VoiceInputProfile
        let targetApplicationBundleIdentifier: String?
        let usesHardwareOption: Bool
        let waitsForPreviousOwnership: Bool
        let candidateOwnsTransportPrewarm: Bool
        let candidateOwnsPhysicalAttempt: Bool
        let candidatePhysicalAttemptID: UUID?
        let triggerStrategy: LongOnlyTriggerStrategy
        let generation: UUID
        var isStillHeld = true
        var longConfirmed = false
        var previousVoiceOwnershipReady: Bool
        var triggerOwnershipReady: Bool
    }

    var onStateChanged: ((State) -> Void)?
    /// Lets the HUD update when a long press receives its first real remote
    /// audio frame, without changing the gesture state itself.
    var onRemoteAudioChanged: ((Bool) -> Void)?
    /// Coordinates the physical hidutil Option edge with the short/long
    /// classifier. The event tap temporarily stores the original CGEvents
    /// until the gesture state decides whether to replay or drop them.
    var onHardwareOptionGateBegin: ((UUID) -> Void)?
    /// Result-bearing variant used by the LONG-only candidate. A rejected
    /// owner must reject the physical gesture before any candidate is armed.
    var onHardwareOptionGateBeginResult: ((UUID) -> Bool)?
    /// A SHORT tombstone keeps owning delayed mapped Option edges. A new
    /// hardware candidate may wait privately behind it, but must not steal it.
    var onHardwareOptionGateBeginDeferredBehindShortDiscard: ((UUID) -> Bool)?
    /// Register the one overlap candidate that will inherit a synthetic
    /// trigger after the active SHORT tombstone hands suppression to it.
    var onHardwareOptionGateShortHandoffBegin: ((UUID) -> Bool)?
    /// Keep bounded physical suppression alive when an overlap candidate
    /// releases before the active SHORT tombstone retires.
    var onHardwareOptionGateShortHandoffReleased: ((UUID) -> Bool)?
    var onHardwareOptionGateLongReady: ((UUID) -> Void)?
    /// LONG-only confirmation is independent from mapped Option-down arrival.
    var onHardwareOptionGateLongConfirmed: ((UUID) -> Void)?
    /// Transfer a discarded candidate into bounded mapped-trigger suppression.
    var onHardwareOptionGateShortDiscard: ((UUID) -> Bool)?
    /// Discard the mapped trigger when a persistent IME hold becomes an
    /// audio-only remote segment.
    var onHardwareOptionGateSuppressForAudioOnly: ((UUID) -> Bool)?
    /// Reset suppression only when HID device removal proves no matching up
    /// event can arrive; ordinary BLE loss keeps waiting for physical up.
    var onHardwareOptionGateResetSuppression: ((UUID) -> Void)?
    var onHardwareOptionGateShortReplay: ((UUID) -> Void)?
    var onPersistentSessionTriggerTap: ((UUID, VoiceTriggerKey, String) -> PersistentShortTapDispatchResult)?
    var onDeferredPersistentSessionTriggerTap: ((UUID, VoiceTriggerKey, String) -> Bool)?
    var onHardwareOptionGateCancel: ((UUID) -> Void)?
    /// Testable ordering seam: the state callback is where AppController
    /// requests BLE acquisition, and this callback marks route preparation.
    var onRemoteRoutePreparation: (() -> Void)?
    /// A disabled short press may prepare ATVV while classification is
    /// pending. This does not release Option or expose the voice HUD.
    var onRemoteTransportPreparation: (() -> Void)?
    var onRemoteTransportCancellation: (() -> Void)?
    /// Called only after a private candidate has been promoted into the
    /// existing direct opening lifecycle. Focus work belongs here, not at DOWN.
    var onLongOnlyCandidatePromoted: ((UUID, String?) -> Void)?
    /// Complete a long gesture only after queued remote PCM has rendered.
    var onRemoteOutputDrain: ((UUID, @escaping () -> Void) -> Void)?
    /// Returns true while BLE cleanup owns the admission boundary for a new
    /// voice session. A physical press is retained until the bridge reports
    /// that boundary clear; it must not start a stream that AUDIO_START will
    /// immediately reject as a late packet.
    var isVoiceSessionAdmissionBlocked: (() -> Bool)?
    /// BLE-owned candidate truth for rapid physical re-press admission. This
    /// synchronous read is authoritative; the mirrored flag below is only a
    /// lifecycle notification for the coordinator/UI.
    var hasLivePhysicalCandidate: (() -> Bool)?
    /// The raw HID voice-key release arms the matching mapped Option-up.
    var onHardwareOptionGatePhysicalUp: ((UUID) -> Void)?
    /// Release a replayed hardware Option-up after output drain.
    var onHardwareOptionGateOutputDrained: ((UUID) -> Void)?
    /// Capture a new mapped hardware DOWN while the previous direct session
    /// still owns terminal Option-UP retirement. This is a separate owner,
    /// not a second active voice session.
    var onHardwareOptionGatePendingRepressBegin:
        ((UUID, UUID) -> PendingHardwareOptionRepressBeginResult)?
    var onHardwareOptionGatePendingRepressPromote: ((UUID) -> Bool)?
    var onHardwareOptionGatePendingRepressCancel: ((UUID, String) -> Void)?
    var onPendingHardwareOptionRepressDownCaptured: ((UUID) -> Void)?

    /// This is the short-vs-long classifier. A quick default tap toggles the
    /// persistent IME session (or invokes the configured Codex short action);
    /// a hold starts remote dictation after the original 300 ms window.
    ///
    /// Keep this at 300 ms: the old hold-only experiment lowered it to 120 ms,
    /// but once short-press behavior was restored that made an ordinary tap
    /// look like a long press and opened remote dictation unexpectedly.
    static let holdActivationThreshold: TimeInterval = 0.30
    /// Persistent sessions prepare transport immediately while pending, but
    /// use the same 300ms short-vs-hold semantic boundary so ordinary taps can
    /// reliably close or reopen the session.
    static let persistentHoldActivationThreshold: TimeInterval =
        holdActivationThreshold

    static func isLongPress(heldDuration: TimeInterval) -> Bool {
        heldDuration >= holdActivationThreshold
    }

    static func isPersistentSessionLongPress(heldDuration: TimeInterval) -> Bool {
        heldDuration >= persistentHoldActivationThreshold
    }
    // The remote usually sends AUDIO_STOP just before the HID key-up, and the
    // BLE bridge keeps accepting packets during its drain window. Keep the
    // output route alive long enough for those final frames to render even
    // when the physical Option edge has already been released.
    static let tailDrainDelay: TimeInterval = 0.80
    // Physical release bounce is independent from the audio tail. Do not use
    // the tail-drain duration as a press lockout: a completed route must allow
    // the next real gesture immediately after this small debounce window.
    private let releaseBounceDebounce: TimeInterval = 0.18
    private var mode: State = .idle
    private var holdWorkItem: DispatchWorkItem?
    private var longOnlyCandidateTimer: VoicePressCandidateTimer?
    private var longOnlyCandidate: LongOnlyCandidate?
    private let candidateTimerFactory:
        (TimeInterval, @escaping () -> Void) -> VoicePressCandidateTimer
    private var tailWorkItem: DispatchWorkItem?
    private var tailSessionID: UUID?
    private var remoteStreaming = false
    private var preHIDPhysicalStreaming = false
    private var remoteAudioAvailable = false
    private var remoteRouted = false
    private var physicalTriggerSuppressionActive = false
    private var longInputStarted = false
    private var classifiedDualReceiverHold = false
    private var classifiedDualReceiverTriggerKey: VoiceTriggerKey?
    private var prearmedDualReceiverHardwareGateSessionID: UUID?
    private var releaseBounceDebounceUntil = Date.distantPast
    private var lastPhysicalUpAt: Date?
    private(set) var lastRepressDecisionForTesting: String?
    private var pendingRepress: PendingRepress?
    private var deferredRepressAwaitingActivation = false
    private var deferredRepressActivationWorkItem: DispatchWorkItem?
    private var deferredRepressWaitReason: DeferredRepressWaitReason?
    private var shortTapAction: (() -> Void)?
    private var shortInputUsesLocalMicrophone = false
    private var shortInputTogglesPersistentVoiceSession = false
    private(set) var voiceSessionMode: VoiceSessionMode = .idle
    private(set) var persistentSessionTriggerKey: VoiceTriggerKey = .defaultValue
    private var persistentSessionTriggerOwnerKey: VoiceTriggerKey?
    private var pendingPersistentToggle: PendingPersistentToggle?
    private var remoteSegmentTriggerPolicy: RemoteSegmentTriggerPolicy = .momentaryTrigger
    private var audioOnlyHardwareTriggerSuppressed = false
    private var resetAudioOnlyHardwareTriggerOnDrain = false
    private var gestureID: UUID?
    /// Gate-A production ownership. The legacy classifier fields below remain
    /// available only to historical unit seams; AppController never enters
    /// them for a physical voice-key press after Gate A.
    private var directSession = false
    private var capturedVoiceProfile: VoiceInputProfile?
    private var directPhysicalUp = false
    private var directTransportStopObserved = false
    private var preserveCandidateForDirectTransportStop = false
    private var directOutputDrainRequested = false
    private var directOutputDrained = false
    private var pendingDirectHardwareRepressAwaitingOldUp = false
    private var pendingDirectHardwareRepressOldSessionID: UUID?
    private var pendingDirectHardwareRepressACompleted = false
    private var pendingDirectHardwareRepressDownCaptured = false
    private var pendingShortPreparationID: UUID?
    private var usesHardwareOptionPath = false
    private var remoteOutputDrainRequestedSessionID: UUID?
    private var remoteOutputDrainedSessionID: UUID?
    private var physicalUpSessionID: UUID?
    private var awaitingPhysicalVoiceKeyUp = false
    private var pendingVoiceUIHidden = false
    private let syntheticOptionTrigger: VoiceOptionTrigger
    private let diagnosticLogger: VoiceDiagnosticLogger?
    private var gesturePhysicalDownUptime: TimeInterval?

    init(
        optionTrigger: VoiceOptionTrigger = .shared,
        diagnosticLogger: VoiceDiagnosticLogger? = nil,
        candidateTimerFactory: @escaping
            (TimeInterval, @escaping () -> Void) -> VoicePressCandidateTimer =
            VoicePressCandidateTimer.gcdFactory
    ) {
        syntheticOptionTrigger = optionTrigger
        self.diagnosticLogger = diagnosticLogger
        self.candidateTimerFactory = candidateTimerFactory
    }

    /// Only these short actions need RemoteOrbit to capture the Mac's
    /// physical/external microphone. The remote-microphone long press is
    /// independent and must never inherit this requirement.
    static func usesLocalMicrophone(forShortBinding binding: ButtonBinding) -> Bool {
        switch binding {
        case .preset(.chatGPTStartVoiceChat), .preset(.chatGPTStartDictation):
            return true
        default:
            return false
        }
    }

    static func togglesPersistentVoiceSession(forShortBinding binding: ButtonBinding) -> Bool {
        binding == .voiceKeyDefault
    }

    var hasRemoteAudio: Bool {
        remoteAudioAvailable
    }

    var pendingRepressSessionID: UUID? {
        pendingRepress?.sessionID
    }

    var hasDeferredRepressAwaitingActivationForTesting: Bool {
        deferredRepressAwaitingActivation
    }

    var hasPendingPersistentToggleForTesting: Bool {
        pendingPersistentToggle != nil
    }

    var currentStateForTesting: State {
        mode
    }

    var currentGestureIDForDiagnostics: UUID? {
        gestureID
    }

    var hasLongOnlyCandidateForTesting: Bool {
        longOnlyCandidate != nil
    }

    var longOnlyCandidateOwnsTransportPrewarmForTesting: Bool {
        longOnlyCandidate?.candidateOwnsTransportPrewarm ?? false
    }

    var longOnlyCandidateOwnsPhysicalAttemptForTesting: Bool {
        longOnlyCandidate?.candidateOwnsPhysicalAttempt ?? false
    }

    var longOnlyCandidateTriggerOwnershipReadyForTesting: Bool {
        longOnlyCandidate?.triggerOwnershipReady ?? false
    }

    var longOnlyCandidateUsesSyntheticHandoffForTesting: Bool {
        longOnlyCandidate?.triggerStrategy == .syntheticHandoff
    }

    var longOnlyCandidatePreviousOwnershipReadyForTesting: Bool {
        longOnlyCandidate?.previousVoiceOwnershipReady ?? false
    }

    var longOnlyCandidateTimerActiveForTesting: Bool {
        longOnlyCandidateTimer != nil
    }

    var longOnlyCandidateLongConfirmedForTesting: Bool {
        longOnlyCandidate?.longConfirmed ?? false
    }

    var longOnlyCandidateSessionIDForTesting: UUID? {
        longOnlyCandidate?.sessionID
    }

    /// Test seam for exercising the real promotion path without waiting on a
    /// wall-clock timer. Production input reaches the same method from the
    /// one-shot 300 ms candidate timer.
    @discardableResult
    func promoteLongOnlyCandidateForTesting() -> Bool {
        guard var candidate = longOnlyCandidate else { return false }
        candidate.longConfirmed = true
        longOnlyCandidate = candidate
        tryPromoteLongOnlyCandidate(sessionID: candidate.sessionID)
        return directSession || longOnlyCandidate == nil
    }

    var capturedVoiceProfileForTesting: VoiceInputProfile? {
        capturedVoiceProfile
    }

    var capturedTriggerKeyForTesting: VoiceTriggerKey? {
        capturedVoiceProfile?.triggerKey
    }

    var preHIDPhysicalStreamingForTesting: Bool {
        preHIDPhysicalStreaming
    }

    private var livePhysicalCandidateForAdmission: Bool {
        hasLivePhysicalCandidate?() ?? preHIDPhysicalStreaming
    }

    var persistentSessionActiveForTesting: Bool {
        voiceSessionMode == .persistentOpen
    }

    var currentSessionModeForTesting: VoiceSessionMode {
        voiceSessionMode
    }

    var remoteSegmentTriggerPolicyForTesting: RemoteSegmentTriggerPolicy {
        remoteSegmentTriggerPolicy
    }

    var hasActiveVoiceOwnershipForTriggerReconfiguration: Bool {
        mode != .idle
            || longOnlyCandidate != nil
            || pendingRepress != nil
            || gestureID != nil
            || remoteRouted
            || remoteStreaming
            || remoteAudioAvailable
            || longInputStarted
            || tailWorkItem != nil
            || deferredRepressAwaitingActivation
            || pendingShortPreparationID != nil
            || awaitingPhysicalVoiceKeyUp
            || physicalUpSessionID != nil
            || remoteOutputDrainRequestedSessionID != nil
            || pendingPersistentToggle != nil
    }

    var hasVoiceKeyHeldForReconfiguration: Bool {
        mode != .idle || longOnlyCandidate != nil
    }

    var hasReleaseOrTailOwnershipForReconfiguration: Bool {
        pendingRepress != nil
            || gestureID != nil
            || remoteRouted
            || remoteStreaming
            || remoteAudioAvailable
            || longInputStarted
            || tailWorkItem != nil
            || deferredRepressAwaitingActivation
            || pendingShortPreparationID != nil
            || awaitingPhysicalVoiceKeyUp
            || physicalUpSessionID != nil
            || remoteOutputDrainRequestedSessionID != nil
            || pendingPersistentToggle != nil
    }

    var persistentSessionTriggerOwnerKeyForTesting: VoiceTriggerKey? {
        persistentSessionTriggerOwnerKey
    }

    var diagnosticStateFields: [String: Any] {
        [
            "mode": modeName,
            "voice_session_state": directSession ? modeName : "legacy",
            "voice_input_profile_id": capturedVoiceProfile?.id ?? "none",
            "voice_input_trigger_key": capturedVoiceProfile?.triggerKey.rawValue ?? "none",
            "persistent_session_mode": voiceSessionMode == .persistentOpen
                ? "persistent_open" : "idle",
            "gesture_id": gestureID?.uuidString ?? "none",
            "pending_repress": pendingRepress != nil,
            "long_only_candidate": longOnlyCandidate != nil,
            "long_only_candidate_long_confirmed": longOnlyCandidate?.longConfirmed ?? false,
            "pending_persistent_toggle": pendingPersistentToggle != nil,
            "pending_persistent_toggle_gate_owner": pendingPersistentToggle?.waitingGateOwner.uuidString ?? "none",
            "remote_routed": remoteRouted,
            "remote_streaming": remoteStreaming,
            "pre_hid_physical_streaming": preHIDPhysicalStreaming,
            "transport_stop_observed": directTransportStopObserved,
            "remote_audio_available": remoteAudioAvailable,
            "long_input_started": longInputStarted,
            "tail_pending": tailWorkItem != nil,
            "awaiting_physical_up": awaitingPhysicalVoiceKeyUp,
            "momentary_config": syntheticOptionTrigger.momentaryVoiceTriggerKey.rawValue,
            "persistent_config": persistentSessionTriggerKey.rawValue,
            "persistent_owner": persistentSessionTriggerOwnerKey?.rawValue ?? "none",
            "synthetic_owner": syntheticOptionTrigger.activeSessionID?.uuidString ?? "none",
            "synthetic_down": syntheticOptionTrigger.isOptionDown,
        ]
    }

    @discardableResult
    func configurePersistentSessionTriggerKey(_ key: VoiceTriggerKey) -> Bool {
        guard pendingPersistentToggle == nil else { return false }
        persistentSessionTriggerKey = key
        return true
    }

    var tailDrainDelayForTesting: TimeInterval {
        Self.tailDrainDelay
    }

    var hasPendingTailForTesting: Bool {
        tailWorkItem != nil
    }

    var shouldShowPendingVoiceUI: Bool {
        !pendingVoiceUIHidden
    }

    func invokeTailCompletionForTesting(sessionID: UUID) {
        finishLongInput(sessionID: sessionID)
    }

    @discardableResult
    func keyDown(
        sessionID: UUID,
        onShortTap: (() -> Void)? = nil,
        usesLocalMicrophone: Bool = false,
        togglesPersistentVoiceSession: Bool = false,
        bypassesShortClassification: Bool = false,
        usesHardwareOption: Bool = false,
        preparesRemoteTransport: Bool = false,
        profile: VoiceInputProfile? = nil,
        directSession: Bool = false,
        longOnlyAdmission: Bool = false,
        targetApplicationBundleIdentifier: String? = nil
    ) -> Bool {
        if directSession {
            if longOnlyAdmission {
                return startLongOnlyDirectCandidate(
                    sessionID: sessionID,
                    profile: profile ?? .defaultProfile,
                    usesHardwareOption: usesHardwareOption,
                    preparesRemoteTransport: preparesRemoteTransport,
                    targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
                )
            }
            return startDirectVoicePress(
                sessionID: sessionID,
                profile: profile ?? .defaultProfile,
                usesHardwareOption: usesHardwareOption
            )
        }
        if let pendingPersistentToggle {
            logAdmissionDecision(
                sessionID: sessionID,
                result: "rejected",
                reason: "pending_persistent_toggle"
            )
            diagnosticLogger?.log(
                category: "voice",
                event: "VOICE_GESTURE_BLOCKED_PENDING_PERSISTENT_TOGGLE",
                gestureID: sessionID,
                key: pendingPersistentToggle.triggerKey,
                fields: [
                    "pending_gesture_id": pendingPersistentToggle.gestureID.uuidString,
                    "waiting_gate_owner": pendingPersistentToggle.waitingGateOwner.uuidString,
                    "purpose": pendingPersistentToggle.purpose,
                ]
            )
            return false
        }
        let now = Date()
        let physicalDownAt = ProcessInfo.processInfo.systemUptime
        if now < releaseBounceDebounceUntil {
            let delta = lastPhysicalUpAt.map {
                now.timeIntervalSince($0) * 1000
            } ?? 0
            lastRepressDecisionForTesting = "release-bounce"
            logAdmissionDecision(
                sessionID: sessionID,
                result: "rejected",
                reason: "release_bounce"
            )
            print(
                "[PRESS] rejected release bounce delta=" +
                    String(format: "%.1fms", delta)
            )
            return false
        }
        guard mode == .idle, !awaitingPhysicalVoiceKeyUp else {
            logAdmissionDecision(
                sessionID: sessionID,
                result: "rejected",
                reason: "voice_key_release_pending"
            )
            return false
        }
        if remoteRouted || longInputStarted || tailWorkItem != nil {
            if pendingRepress == nil {
                pendingRepress = PendingRepress(
                    sessionID: sessionID,
                    physicalDownAt: physicalDownAt,
                    onShortTap: onShortTap,
                    usesLocalMicrophone: usesLocalMicrophone,
                    togglesPersistentVoiceSession: togglesPersistentVoiceSession,
                    bypassesShortClassification: bypassesShortClassification,
                    usesHardwareOption: usesHardwareOption,
                    preparesRemoteTransport: preparesRemoteTransport,
                    classifiedTriggerKey: nil
                )
                let shortID = String(sessionID.uuidString.prefix(4))
                print(
                    "[VOICE][\(shortID)][TIMING] VOICE_DOWN_PHYSICAL " +
                        "uptime=" + String(format: "%.6f", physicalDownAt)
                )
                print(
                    "[PRESS][\(shortID)] deferred previous-tail-active " +
                        "session=\(sessionID.uuidString)"
                )
            } else {
                print("[PRESS] deferred re-press already pending")
            }
            lastRepressDecisionForTesting = "deferred-previous-tail-active"
            logAdmissionDecision(
                sessionID: sessionID,
                result: "deferred",
                reason: "previous_route_tail_active"
            )
            return true
        }
        if isVoiceSessionAdmissionBlocked?() == true {
            if pendingRepress == nil {
                pendingRepress = PendingRepress(
                    sessionID: sessionID,
                    physicalDownAt: physicalDownAt,
                    onShortTap: onShortTap,
                    usesLocalMicrophone: usesLocalMicrophone,
                    togglesPersistentVoiceSession: togglesPersistentVoiceSession,
                    bypassesShortClassification: bypassesShortClassification,
                    usesHardwareOption: usesHardwareOption,
                    preparesRemoteTransport: preparesRemoteTransport,
                    classifiedTriggerKey: nil
                )
                deferredRepressWaitReason = .audioDrain
                deferredRepressAwaitingActivation = true
                let shortID = String(sessionID.uuidString.prefix(4))
                print(
                    "[PRESS][\(shortID)] admission deferred reason=audio-drain "
                        + "session=\(sessionID.uuidString)"
                )
                logAdmissionDecision(
                    sessionID: sessionID,
                    result: "deferred",
                    reason: "audio_drain"
                )
            } else {
                print("[PRESS] admission deferred; re-press already pending")
                logAdmissionDecision(
                    sessionID: sessionID,
                    result: "deferred",
                    reason: "audio_drain_already_pending"
                )
            }
            lastRepressDecisionForTesting = "deferred-audio-drain"
            return true
        }
        if pendingRepress != nil || deferredRepressAwaitingActivation {
            logAdmissionDecision(
                sessionID: sessionID,
                result: "deferred",
                reason: "repress_activation_pending"
            )
            return true
        }
        if lastPhysicalUpAt != nil {
            lastRepressDecisionForTesting = "accepted-after-route-finished"
            print("[PRESS] accepted new gesture after previous route finished")
        } else {
            lastRepressDecisionForTesting = nil
        }

        let accepted = startAcceptedVoicePress(
            sessionID: sessionID,
            physicalDownAt: physicalDownAt,
            onShortTap: onShortTap,
            usesLocalMicrophone: usesLocalMicrophone,
            togglesPersistentVoiceSession: togglesPersistentVoiceSession,
            bypassesShortClassification: bypassesShortClassification,
            usesHardwareOption: usesHardwareOption,
            preparesRemoteTransport: preparesRemoteTransport
        )
        logAdmissionDecision(
            sessionID: sessionID,
            result: accepted ? "admitted" : "rejected",
            reason: accepted ? "ready" : "voice_session_start_failed"
        )
        return accepted
    }

    /// Gate-A production entry. The physical microphone press is private until
    /// the 300 ms boundary; only promotion enters the existing direct session.
    @discardableResult
    private func startLongOnlyDirectCandidate(
        sessionID: UUID,
        profile: VoiceInputProfile,
        usesHardwareOption: Bool,
        preparesRemoteTransport: Bool,
        targetApplicationBundleIdentifier: String?
    ) -> Bool {
        guard longOnlyCandidate == nil else {
            logAdmissionDecision(
                sessionID: sessionID,
                result: "rejected",
                reason: "long_only_candidate_already_active"
            )
            return false
        }

        if directSession,
           directPhysicalUp,
           !directOutputDrained,
           livePhysicalCandidateForAdmission {
            guard pendingRepress == nil,
                  !deferredRepressAwaitingActivation,
                  let oldSessionID = gestureID else {
                return false
            }
            if usesHardwareOption {
                guard let beginResult = onHardwareOptionGatePendingRepressBegin?(
                    sessionID,
                    oldSessionID
                ), beginResult.isArmed else {
                    lastRepressDecisionForTesting =
                        "pending-hardware-owner-failed"
                    logAdmissionDecision(
                        sessionID: sessionID,
                        result: "rejected",
                        reason: "pending_hardware_repress_begin_failed"
                    )
                    return false
                }
                pendingDirectHardwareRepressAwaitingOldUp =
                    beginResult.awaitsOldUpAcknowledgement
                pendingDirectHardwareRepressOldSessionID = oldSessionID
                pendingDirectHardwareRepressACompleted = false
                pendingDirectHardwareRepressDownCaptured = false
            } else {
                pendingDirectHardwareRepressAwaitingOldUp = false
                pendingDirectHardwareRepressOldSessionID = nil
                pendingDirectHardwareRepressACompleted = false
                pendingDirectHardwareRepressDownCaptured = false
            }
            pendingRepress = PendingRepress(
                sessionID: sessionID,
                physicalDownAt: ProcessInfo.processInfo.systemUptime,
                onShortTap: nil,
                usesLocalMicrophone: false,
                togglesPersistentVoiceSession: false,
                bypassesShortClassification: true,
                usesHardwareOption: usesHardwareOption,
                preparesRemoteTransport: preparesRemoteTransport,
                classifiedTriggerKey: nil,
                isDirectSession: true,
                directProfile: profile
            )
            deferredRepressAwaitingActivation = true
            deferredRepressWaitReason = .directOutputDrain
            lastRepressDecisionForTesting = "deferred-direct-output-drain"
            armLongOnlyCandidate(
                sessionID: sessionID,
                physicalDownAt: ProcessInfo.processInfo.systemUptime,
                profile: profile,
                targetApplicationBundleIdentifier: targetApplicationBundleIdentifier,
                usesHardwareOption: usesHardwareOption,
                waitsForPreviousOwnership: true,
                preparesRemoteTransport: preparesRemoteTransport,
                triggerOwnershipReady: true
            )
            logAdmissionDecision(
                sessionID: sessionID,
                result: "deferred",
                reason: "direct_output_drain"
            )
            return true
        }

        guard mode == .idle,
              gestureID == nil,
              !directSession,
              !hasReleaseOrTailOwnershipForReconfiguration,
              pendingRepress == nil,
              !deferredRepressAwaitingActivation else {
            logAdmissionDecision(
                sessionID: sessionID,
                result: "rejected",
                reason: "voice_session_busy"
            )
            return false
        }

        var triggerOwnershipReady = true
        var triggerStrategy: LongOnlyTriggerStrategy = .hardware
        if usesHardwareOption {
            let began: Bool
            if let beginResult = onHardwareOptionGateBeginResult {
                began = beginResult(sessionID)
            } else {
                onHardwareOptionGateBegin?(sessionID)
                began = true
            }
            if !began {
                guard onHardwareOptionGateBeginDeferredBehindShortDiscard?(sessionID) == true else {
                    logAdmissionDecision(
                        sessionID: sessionID,
                        result: "rejected",
                        reason: "hardware_option_owner_begin_failed"
                    )
                    return false
                }
                if let beginHandoff = onHardwareOptionGateShortHandoffBegin {
                    guard beginHandoff(sessionID) else {
                        logAdmissionDecision(
                            sessionID: sessionID,
                            result: "rejected",
                            reason: "short_tombstone_handoff_slot_busy"
                        )
                        return false
                    }
                    triggerStrategy = .syntheticHandoff
                }
                triggerOwnershipReady = false
            }
        }

        armLongOnlyCandidate(
            sessionID: sessionID,
            physicalDownAt: ProcessInfo.processInfo.systemUptime,
            profile: profile,
            targetApplicationBundleIdentifier: targetApplicationBundleIdentifier,
            usesHardwareOption: usesHardwareOption,
            waitsForPreviousOwnership: false,
            preparesRemoteTransport: preparesRemoteTransport,
            triggerOwnershipReady: triggerOwnershipReady,
            triggerStrategy: triggerStrategy
        )
        return true
    }

    private func beginCandidatePhysicalAttempt(
        for sessionID: UUID
    ) -> (attemptID: UUID?, ownsAttempt: Bool) {
        let existingAttemptID = VoiceAttemptDiagnostics.shared.currentID
        let returnedAttemptID = VoiceAttemptDiagnostics.shared.beginPhysicalAttempt(
            state: [
                "physical_source": .string("long_only_candidate"),
                "candidate_session_id": .string(sessionID.uuidString),
            ]
        )
        let currentAttemptID = VoiceAttemptDiagnostics.shared.currentID
        let belongsToActiveDirectSession: Bool = {
            guard directSession,
                  let activeGestureID = gestureID else { return false }
            return VoiceAttemptDiagnostics.shared.attemptID(
                for: activeGestureID.uuidString
            ) == returnedAttemptID.uuidString
        }()
        // The raw HID monitor may have created the attempt immediately before
        // AppController reaches this seam. A direct overlap, however, must
        // inherit A's attempt and never claim/end it for B.
        let ownsAttempt = returnedAttemptID == currentAttemptID
            && !belongsToActiveDirectSession
            && (existingAttemptID == nil || !directSession)
        return (returnedAttemptID, ownsAttempt)
    }

    private func armLongOnlyCandidate(
        sessionID: UUID,
        physicalDownAt: TimeInterval,
        profile: VoiceInputProfile,
        targetApplicationBundleIdentifier: String?,
        usesHardwareOption: Bool,
        waitsForPreviousOwnership: Bool,
        preparesRemoteTransport: Bool,
        triggerOwnershipReady: Bool,
        triggerStrategy: LongOnlyTriggerStrategy = .hardware
    ) {
        let generation = UUID()
        let physicalAttempt = beginCandidatePhysicalAttempt(for: sessionID)
        let ownsTransportPrewarm = preparesRemoteTransport && !waitsForPreviousOwnership
        longOnlyCandidate = LongOnlyCandidate(
            sessionID: sessionID,
            physicalDownAt: physicalDownAt,
            profile: profile,
            targetApplicationBundleIdentifier: targetApplicationBundleIdentifier,
            usesHardwareOption: usesHardwareOption,
            waitsForPreviousOwnership: waitsForPreviousOwnership,
            candidateOwnsTransportPrewarm: ownsTransportPrewarm,
            candidateOwnsPhysicalAttempt: physicalAttempt.ownsAttempt,
            candidatePhysicalAttemptID: physicalAttempt.attemptID,
            triggerStrategy: triggerStrategy,
            generation: generation,
            previousVoiceOwnershipReady: !waitsForPreviousOwnership,
            triggerOwnershipReady: triggerOwnershipReady
        )
        AudioPipe.shared.beginRemoteCandidate()
        if ownsTransportPrewarm {
            onRemoteTransportPreparation?()
        }
        scheduleLongOnlyCandidateTimer(
            sessionID: sessionID,
            generation: generation,
            physicalDownAt: physicalDownAt
        )
    }

    private func scheduleLongOnlyCandidateTimer(
        sessionID: UUID,
        generation: UUID,
        physicalDownAt: TimeInterval
    ) {
        longOnlyCandidateTimer?.cancel()
        let elapsed = max(
            0,
            ProcessInfo.processInfo.systemUptime - physicalDownAt
        )
        let remaining = max(0, Self.holdActivationThreshold - elapsed)
        longOnlyCandidateTimer = candidateTimerFactory(remaining) { [weak self] in
            self?.longOnlyCandidateTimerFired(
                sessionID: sessionID,
                generation: generation
            )
        }
    }

    private func longOnlyCandidateTimerFired(
        sessionID: UUID,
        generation: UUID
    ) {
        guard var candidate = longOnlyCandidate,
              candidate.sessionID == sessionID,
              candidate.generation == generation else {
            return
        }
        longOnlyCandidateTimer = nil
        guard candidate.isStillHeld else { return }
        candidate.longConfirmed = true
        longOnlyCandidate = candidate
        tryPromoteLongOnlyCandidate(sessionID: sessionID)
    }

    private func tryPromoteLongOnlyCandidate(sessionID: UUID) {
        guard let candidate = longOnlyCandidate,
              candidate.sessionID == sessionID,
              candidate.isStillHeld,
              candidate.longConfirmed,
              candidate.triggerOwnershipReady else {
            return
        }

        if candidate.waitsForPreviousOwnership {
            tryActivatePendingDirectHardwareRepress()
            return
        }
        guard candidate.previousVoiceOwnershipReady else { return }
        guard mode == .idle,
              gestureID == nil,
              !directSession,
              !hasReleaseOrTailOwnershipForReconfiguration,
              isVoiceSessionAdmissionBlocked?() != true else {
            return
        }
        promoteLongOnlyCandidate(candidate)
    }

    private func promoteLongOnlyCandidate(_ candidate: LongOnlyCandidate) {
        guard longOnlyCandidate?.sessionID == candidate.sessionID else { return }
        longOnlyCandidateTimer?.cancel()
        longOnlyCandidateTimer = nil
        longOnlyCandidate = nil
        let activated = startDirectVoicePress(
            sessionID: candidate.sessionID,
            profile: candidate.profile,
            usesHardwareOption: candidate.triggerStrategy == .hardware
                ? candidate.usesHardwareOption
                : false,
            fromLongOnlyCandidate: true,
            syntheticHandoff: candidate.triggerStrategy == .syntheticHandoff
        )
        guard activated else {
            finishFailedLongOnlyCandidate(candidate)
            return
        }
        onLongOnlyCandidatePromoted?(
            candidate.sessionID,
            candidate.targetApplicationBundleIdentifier
        )
        logAdmissionDecision(
            sessionID: candidate.sessionID,
            result: "admitted",
            reason: "long_hold_confirmed"
        )
    }

    private func finishFailedLongOnlyCandidate(_ candidate: LongOnlyCandidate) {
        if candidate.triggerStrategy == .syntheticHandoff {
            _ = onHardwareOptionGateShortHandoffReleased?(candidate.sessionID)
                ?? false
        } else if candidate.usesHardwareOption {
            if candidate.triggerOwnershipReady {
                _ = onHardwareOptionGateShortDiscard?(candidate.sessionID)
                    ?? false
            }
        } else {
            _ = syntheticOptionTrigger.abort(sessionID: candidate.sessionID)
        }
        if candidate.candidateOwnsTransportPrewarm {
            onRemoteTransportCancellation?()
        }
        AudioPipe.shared.endRemoteCandidate()
        endCandidatePhysicalAttemptIfOwned(candidate)
    }

    private func endCandidatePhysicalAttemptIfOwned(_ candidate: LongOnlyCandidate) {
        guard candidate.candidateOwnsPhysicalAttempt,
              let candidateAttemptID = candidate.candidatePhysicalAttemptID,
              VoiceAttemptDiagnostics.shared.currentID == candidateAttemptID else {
            return
        }
        VoiceAttemptDiagnostics.shared.end(sessionID: nil)
    }

    private func cancelLongOnlyCandidate(reason: String) -> Bool {
        guard let candidate = longOnlyCandidate else { return false }
        longOnlyCandidateTimer?.cancel()
        longOnlyCandidateTimer = nil
        longOnlyCandidate = nil
        if pendingRepress?.sessionID == candidate.sessionID {
            pendingRepress?.isStillHeld = false
            pendingRepress = nil
            deferredRepressAwaitingActivation = false
            deferredRepressActivationWorkItem?.cancel()
            deferredRepressActivationWorkItem = nil
            deferredRepressWaitReason = nil
            if candidate.usesHardwareOption {
                onHardwareOptionGatePendingRepressCancel?(
                    candidate.sessionID,
                    reason
                )
            }
            clearPendingDirectHardwareRepressState()
        } else if candidate.triggerStrategy == .syntheticHandoff {
            _ = onHardwareOptionGateShortHandoffReleased?(candidate.sessionID)
                ?? false
        } else if candidate.usesHardwareOption {
            if candidate.triggerOwnershipReady {
                _ = onHardwareOptionGateShortDiscard?(candidate.sessionID)
                    ?? false
            }
        } else {
            _ = syntheticOptionTrigger.abort(sessionID: candidate.sessionID)
        }
        if candidate.candidateOwnsTransportPrewarm {
            onRemoteTransportCancellation?()
        }
        AudioPipe.shared.endRemoteCandidate()
        endCandidatePhysicalAttemptIfOwned(candidate)
        if reason != "physical-up-before-promotion" {
            diagnosticLogger?.log(
                category: "voice",
                event: "LONG_CANDIDATE_CANCELLED",
                gestureID: candidate.sessionID,
                key: candidate.profile.triggerKey,
                fields: [
                    "reason": reason,
                    "long_confirmed": candidate.longConfirmed,
                ]
            )
        }
        return true
    }

    /// Gate A production path. Voice DOWN owns one profile and trigger from
    /// this point until output drain completes; no timing classifier or
    /// receiver/session mode participates in the lifecycle.
    private func startDirectVoicePress(
        sessionID: UUID,
        profile: VoiceInputProfile,
        usesHardwareOption: Bool,
        promotingPendingHardwareRepress: Bool = false,
        fromLongOnlyCandidate: Bool = false,
        syntheticHandoff: Bool = false
    ) -> Bool {
        if directSession,
           directPhysicalUp,
           !directOutputDrained,
           livePhysicalCandidateForAdmission {
            if pendingRepress == nil && !deferredRepressAwaitingActivation {
                if usesHardwareOption {
                    guard let oldSessionID = gestureID,
                          let beginResult = onHardwareOptionGatePendingRepressBegin?(
                              sessionID,
                              oldSessionID
                          ),
                          beginResult.isArmed else {
                        lastRepressDecisionForTesting =
                            "pending-hardware-owner-failed"
                        logAdmissionDecision(
                            sessionID: sessionID,
                            result: "rejected",
                            reason: "pending_hardware_repress_begin_failed"
                        )
                        print(
                            "[PRESS] direct re-press rejected; "
                                + "pending hardware owner could not be established"
                        )
                        return false
                    }
                    pendingDirectHardwareRepressAwaitingOldUp =
                        beginResult.awaitsOldUpAcknowledgement
                    pendingDirectHardwareRepressOldSessionID = oldSessionID
                    pendingDirectHardwareRepressACompleted = false
                    pendingDirectHardwareRepressDownCaptured = false
                } else {
                    pendingDirectHardwareRepressAwaitingOldUp = false
                    pendingDirectHardwareRepressOldSessionID = nil
                    pendingDirectHardwareRepressACompleted = false
                    pendingDirectHardwareRepressDownCaptured = false
                }
                pendingRepress = PendingRepress(
                    sessionID: sessionID,
                    physicalDownAt: ProcessInfo.processInfo.systemUptime,
                    onShortTap: nil,
                    usesLocalMicrophone: false,
                    togglesPersistentVoiceSession: false,
                    bypassesShortClassification: true,
                    usesHardwareOption: usesHardwareOption,
                    preparesRemoteTransport: false,
                    classifiedTriggerKey: nil,
                    isDirectSession: true,
                    directProfile: profile
                )
                deferredRepressAwaitingActivation = true
                deferredRepressWaitReason = .directOutputDrain
                lastRepressDecisionForTesting = "deferred-direct-output-drain"
                logAdmissionDecision(
                    sessionID: sessionID,
                    result: "deferred",
                    reason: "direct_output_drain"
                )
                print(
                    "[PRESS][\(String(sessionID.uuidString.prefix(4)))] "
                        + "direct re-press deferred until output drain"
                )
            } else {
                lastRepressDecisionForTesting = "deferred-direct-output-drain-already-pending"
                print("[PRESS] direct re-press already pending")
            }
            return true
        }
        guard mode == .idle,
              gestureID == nil,
              !directSession,
              !hasReleaseOrTailOwnershipForReconfiguration,
              isVoiceSessionAdmissionBlocked?() != true else {
            if promotingPendingHardwareRepress, usesHardwareOption {
                onHardwareOptionGatePendingRepressCancel?(
                    sessionID,
                    "admission-rejected-before-promotion"
                )
            }
            logAdmissionDecision(
                sessionID: sessionID,
                result: "rejected",
                reason: "voice_session_busy"
            )
            return false
        }

        // Resolve every coordinator admission guard before promotion can
        // mutate hardware ownership or replay B's captured DOWN. Once this
        // callback succeeds, the direct session below is committed and no
        // later admission rejection can strand a trigger owner.
        if promotingPendingHardwareRepress,
           usesHardwareOption,
           onHardwareOptionGatePendingRepressPromote?(sessionID) != true {
            onHardwareOptionGatePendingRepressCancel?(
                sessionID,
                "promotion-owner-missing"
            )
            logAdmissionDecision(
                sessionID: sessionID,
                result: "rejected",
                reason: "pending_hardware_repress_owner_missing"
            )
            return false
        }

        directSession = true
        capturedVoiceProfile = profile
        directPhysicalUp = false
        directTransportStopObserved = false
        preserveCandidateForDirectTransportStop = false
        directOutputDrainRequested = false
        directOutputDrained = false
        usesHardwareOptionPath = usesHardwareOption
        physicalTriggerSuppressionActive = syntheticHandoff
        gestureID = sessionID
        gesturePhysicalDownUptime = ProcessInfo.processInfo.systemUptime
        remoteAudioAvailable = false
        remoteStreaming = false
        remoteOutputDrainRequestedSessionID = nil
        remoteOutputDrainedSessionID = nil
        physicalUpSessionID = nil
        awaitingPhysicalVoiceKeyUp = false
        pendingVoiceUIHidden = false
        VoiceTimingLogger.begin(sessionID: sessionID)
        AudioPipe.shared.beginRemoteCandidate()

        diagnosticLogger?.log(
            category: "voice",
            event: "VOICE_SESSION_OPENING",
            gestureID: sessionID,
            key: profile.triggerKey,
            fields: [
                "voice_input_profile_id": profile.id,
                "trigger_key": profile.triggerKey.rawValue,
                "trigger_source": usesHardwareOption ? "hardware" : "synthetic",
                "classifier": "none",
            ]
        )
        VoiceTimingLogger.mark("BLE_START_REQUEST", sessionID: sessionID)

        // A LONG-only candidate armed the hardware capture at raw DOWN. At
        // promotion, confirm it independently of whether mapped DOWN has
        // arrived; the filter keeps the gate alive for a late mapped edge.
        if usesHardwareOption {
            if !promotingPendingHardwareRepress {
                if fromLongOnlyCandidate {
                    onHardwareOptionGateLongConfirmed?(sessionID)
                } else {
                    onHardwareOptionGateBegin?(sessionID)
                    onHardwareOptionGateLongReady?(sessionID)
                }
            }
            VoiceTimingLogger.mark("OPTION_GATE_RELEASE", sessionID: sessionID)
        } else {
            _ = syntheticOptionTrigger.begin(sessionID: sessionID)
            _ = syntheticOptionTrigger.sendDown(
                sessionID: sessionID,
                key: profile.triggerKey,
                purpose: "voice_session_opening"
            )
            VoiceTimingLogger.mark("OPTION_GATE_RELEASE", sessionID: sessionID)
        }

        setMode(.opening)
        VoiceTimingLogger.mark("REMOTE_ROUTE_BEGIN", sessionID: sessionID)
        onRemoteRoutePreparation?()
        setRemoteRouted(true)
        logAdmissionDecision(
            sessionID: sessionID,
            result: "admitted",
            reason: "voice_down_opening"
        )
        return true
    }

    private func finishDirectVoicePressRelease() -> Bool {
        guard directSession, let sessionID = gestureID else { return false }
        guard !directPhysicalUp else { return true }

        directPhysicalUp = true
        physicalUpSessionID = sessionID
        VoiceTimingLogger.mark("PHYSICAL_UP", sessionID: sessionID)
        diagnosticLogger?.log(
            category: "voice",
            event: "VOICE_SESSION_DRAINING",
            gestureID: sessionID,
            key: capturedVoiceProfile?.triggerKey,
            fields: [
                "voice_input_profile_id": capturedVoiceProfile?.id ?? "unknown",
                "trigger_key": capturedVoiceProfile?.triggerKey.rawValue ?? "unknown",
            ]
        )
        if usesHardwareOptionPath || physicalTriggerSuppressionActive {
            onHardwareOptionGatePhysicalUp?(sessionID)
        }
        setMode(.draining)
        VoiceTimingLogger.mark("STOP_REQUESTED", sessionID: sessionID)
        if directTransportStopObserved {
            finishDirectTransportStop(sessionID: sessionID)
        }
        return true
    }

    private func finishDirectTransportStop(
        sessionID: UUID,
        allowWithoutPhysicalUp: Bool = false
    ) {
        guard directSession,
              gestureID == sessionID,
              directTransportStopObserved,
              directPhysicalUp || allowWithoutPhysicalUp else { return }
        setMode(.draining)
        if !(preserveCandidateForDirectTransportStop && livePhysicalCandidateForAdmission) {
            AudioPipe.shared.endRemoteCandidate()
        }
        _ = setRemoteRouted(false)
        requestDirectOutputDrain(
            sessionID: sessionID,
            allowWithoutPhysicalUp: allowWithoutPhysicalUp
        )
    }

    private func requestDirectOutputDrain(
        sessionID: UUID,
        allowWithoutPhysicalUp: Bool = false
    ) {
        guard directSession,
              gestureID == sessionID,
              directPhysicalUp || allowWithoutPhysicalUp else { return }
        guard !directOutputDrainRequested else { return }
        directOutputDrainRequested = true
        VoiceTimingLogger.mark("OUTPUT_DRAIN_BEGIN", sessionID: sessionID)
        diagnosticLogger?.log(
            category: "voice",
            event: "OUTPUT_DRAIN_BEGIN",
            gestureID: sessionID,
            key: capturedVoiceProfile?.triggerKey,
            fields: ["voice_session_state": "draining"]
        )

        let completion = { [weak self] in
            guard let self,
                  self.directSession,
                  self.gestureID == sessionID,
                  !self.directOutputDrained else { return }
            self.directOutputDrained = true
            VoiceTimingLogger.mark("AUDIO_PIPELINE_CLOSED", sessionID: sessionID)
            self.diagnosticLogger?.log(
                category: "voice",
                event: "OUTPUT_DRAIN_COMPLETE",
                gestureID: sessionID,
                key: self.capturedVoiceProfile?.triggerKey,
                fields: ["voice_session_state": "draining"]
            )
            if self.usesHardwareOptionPath {
                self.onHardwareOptionGateOutputDrained?(sessionID)
            } else if self.capturedVoiceProfile?.triggerKey != nil {
                if self.physicalTriggerSuppressionActive {
                    self.onHardwareOptionGateOutputDrained?(sessionID)
                }
                _ = self.syntheticOptionTrigger.sendUp(sessionID: sessionID)
            } else {
                _ = self.syntheticOptionTrigger.abort(sessionID: sessionID)
            }
            VoiceTimingLogger.mark("OPTION_UP_REQUESTED", sessionID: sessionID)
            self.completeDirectVoiceSession(sessionID: sessionID)
        }

        if let onRemoteOutputDrain {
            onRemoteOutputDrain(sessionID, completion)
        } else {
            completion()
        }
    }

    private func completeDirectVoiceSession(sessionID: UUID) {
        guard directSession, gestureID == sessionID else { return }
        if deferredRepressWaitReason == .directOutputDrain,
           pendingRepress?.isDirectSession == true {
            pendingDirectHardwareRepressACompleted = true
        }
        directSession = false
        directPhysicalUp = false
        directTransportStopObserved = false
        preserveCandidateForDirectTransportStop = false
        directOutputDrainRequested = false
        directOutputDrained = false
        capturedVoiceProfile = nil
        remoteStreaming = false
        remoteAudioAvailable = false
        onRemoteAudioChanged?(false)
        usesHardwareOptionPath = false
        physicalTriggerSuppressionActive = false
        remoteOutputDrainRequestedSessionID = nil
        remoteOutputDrainedSessionID = nil
        physicalUpSessionID = nil
        awaitingPhysicalVoiceKeyUp = false
        pendingVoiceUIHidden = false
        gestureID = nil
        _ = syntheticOptionTrigger.abort(sessionID: sessionID)
        if !preHIDPhysicalStreaming && !livePhysicalCandidateForAdmission {
            AudioPipe.shared.endRemoteCandidate()
        }
        _ = setRemoteRouted(false)
        if mode != .idle { setMode(.idle) }
        VoiceTimingLogger.mark("ROUTE_OFF", sessionID: sessionID)
        VoiceTimingLogger.end(sessionID: sessionID)
        tryActivatePendingDirectHardwareRepress()
    }

    private func clearPendingDirectHardwareRepressState() {
        pendingDirectHardwareRepressAwaitingOldUp = false
        pendingDirectHardwareRepressOldSessionID = nil
        pendingDirectHardwareRepressACompleted = false
        pendingDirectHardwareRepressDownCaptured = false
    }

    private func tryActivatePendingDirectHardwareRepress() {
        guard deferredRepressWaitReason == .directOutputDrain,
              let pending = pendingRepress,
              pending.isDirectSession,
              pendingDirectHardwareRepressACompleted,
              !pendingDirectHardwareRepressAwaitingOldUp,
              !directSession else {
            return
        }
        if let candidate = longOnlyCandidate,
           candidate.sessionID == pending.sessionID {
            guard candidate.longConfirmed, candidate.isStillHeld else {
                return
            }
            guard candidate.triggerOwnershipReady else { return }
        } else {
            guard pending.isStillHeld else { return }
        }
        if pending.usesHardwareOption,
           !pendingDirectHardwareRepressDownCaptured {
            return
        }
        if var candidate = longOnlyCandidate,
           candidate.sessionID == pending.sessionID {
            candidate.previousVoiceOwnershipReady = true
            longOnlyCandidate = candidate
        }
        scheduleDeferredRepressActivation(waitReason: .directOutputDrain)
    }

    func pendingHardwareOptionRepressDownCaptured(sessionID: UUID) {
        guard pendingRepress?.sessionID == sessionID,
              pendingRepress?.isDirectSession == true,
              pendingRepress?.usesHardwareOption == true else {
            return
        }
        pendingDirectHardwareRepressDownCaptured = true
        tryActivatePendingDirectHardwareRepress()
    }

    /// Enters the existing route/hold lifecycle after the voice-specific
    /// classifier has already selected a long gesture. It intentionally does
    /// not start a second short/long timer or emit a receiver trigger edge;
    /// Task 7 supplies the selected receiver at the first-PCM boundary.
    @discardableResult
    func beginClassifiedHold(
        sessionID: UUID,
        physicalDownAt: TimeInterval,
        triggerKey: VoiceTriggerKey
    ) -> Bool {
        guard pendingPersistentToggle == nil,
              mode == .idle,
              !awaitingPhysicalVoiceKeyUp else {
            return false
        }

        if remoteRouted
            || longInputStarted
            || tailWorkItem != nil
            || gestureID != nil
            || remoteOutputDrainRequestedSessionID != nil
            || pendingRepress != nil
            || deferredRepressAwaitingActivation {
            guard pendingRepress == nil,
                  !deferredRepressAwaitingActivation else { return false }
            pendingRepress = PendingRepress(
                sessionID: sessionID,
                physicalDownAt: physicalDownAt,
                onShortTap: nil,
                usesLocalMicrophone: false,
                togglesPersistentVoiceSession: false,
                bypassesShortClassification: true,
                usesHardwareOption: false,
                preparesRemoteTransport: false,
                classifiedTriggerKey: triggerKey
            )
            lastRepressDecisionForTesting = "deferred-previous-tail-active"
            print("[PRESS] classified receiver re-press deferred until previous output closes")
            return true
        }

        return startClassifiedHold(
            sessionID: sessionID,
            physicalDownAt: physicalDownAt,
            triggerKey: triggerKey
        )
    }

    /// Arms the existing physical Option gate at the raw-HID boundary for an
    /// A-mapped dual-receiver press. Classification still happens in the
    /// dual-receiver recognizer; this method does not start voice routing.
    @discardableResult
    func beginClassifiedHardwareGate(sessionID: UUID) -> Bool {
        guard pendingPersistentToggle == nil,
              mode == .idle,
              !awaitingPhysicalVoiceKeyUp,
              !remoteRouted,
              !longInputStarted,
              tailWorkItem == nil,
              gestureID == nil,
              remoteOutputDrainRequestedSessionID == nil,
              pendingRepress == nil,
              !deferredRepressAwaitingActivation,
              prearmedDualReceiverHardwareGateSessionID == nil else {
            return false
        }
        prearmedDualReceiverHardwareGateSessionID = sessionID
        onHardwareOptionGateBegin?(sessionID)
        return true
    }

    /// Enters the existing route lifecycle after dual-receiver classification
    /// while retaining the hardware-mapped A edge owner armed at raw DOWN.
    /// It deliberately skips the legacy short/long classifier and never emits
    /// a synthetic receiver trigger edge.
    @discardableResult
    func beginClassifiedHardwareHold(
        sessionID: UUID,
        physicalDownAt: TimeInterval,
        triggerKey: VoiceTriggerKey
    ) -> Bool {
        guard prearmedDualReceiverHardwareGateSessionID == sessionID else {
            return false
        }
        let started = startClassifiedHold(
            sessionID: sessionID,
            physicalDownAt: physicalDownAt,
            triggerKey: triggerKey,
            usesHardwareOption: true
        )
        if started {
            prearmedDualReceiverHardwareGateSessionID = nil
        }
        return started
    }

    @discardableResult
    func cancelClassifiedHardwareGate(sessionID: UUID) -> Bool {
        guard prearmedDualReceiverHardwareGateSessionID == sessionID else {
            return false
        }
        prearmedDualReceiverHardwareGateSessionID = nil
        onHardwareOptionGateCancel?(sessionID)
        _ = syntheticOptionTrigger.abort(sessionID: sessionID)
        return true
    }

    private func startClassifiedHold(
        sessionID: UUID,
        physicalDownAt: TimeInterval,
        triggerKey: VoiceTriggerKey,
        usesHardwareOption: Bool = false
    ) -> Bool {
        guard pendingPersistentToggle == nil,
              mode == .idle,
              !awaitingPhysicalVoiceKeyUp,
              !remoteRouted,
              !longInputStarted,
              tailWorkItem == nil,
              gestureID == nil,
              remoteOutputDrainRequestedSessionID == nil,
              pendingRepress == nil,
              !deferredRepressAwaitingActivation else {
            return false
        }
        guard syntheticOptionTrigger.begin(sessionID: sessionID) else { return false }

        pendingShortPreparationID = nil
        AudioPipe.shared.setLocalMicrophoneCaptureEnabled(false)
        shortTapAction = nil
        shortInputUsesLocalMicrophone = false
        shortInputTogglesPersistentVoiceSession = false
        remoteSegmentTriggerPolicy = .momentaryTrigger
        audioOnlyHardwareTriggerSuppressed = false
        resetAudioOnlyHardwareTriggerOnDrain = false
        usesHardwareOptionPath = usesHardwareOption
        remoteOutputDrainRequestedSessionID = nil
        remoteOutputDrainedSessionID = nil
        physicalUpSessionID = nil
        awaitingPhysicalVoiceKeyUp = false
        pendingVoiceUIHidden = false
        classifiedDualReceiverHold = !usesHardwareOption
        classifiedDualReceiverTriggerKey = usesHardwareOption ? nil : triggerKey
        gestureID = sessionID
        gesturePhysicalDownUptime = physicalDownAt
        remoteAudioAvailable = false
        longInputStarted = false
        VoiceTimingLogger.begin(sessionID: sessionID)
        diagnosticLogger?.log(
            category: "voice",
            event: "GESTURE_BEGIN",
            gestureID: sessionID,
            fields: [
                "session_mode": voiceSessionMode == .persistentOpen ? "persistent_open" : "idle",
                "momentary_configured_key": syntheticOptionTrigger.momentaryVoiceTriggerKey.rawValue,
                "policy": "momentary_trigger",
                "classifier": "dual_receiver",
                "trigger_source": usesHardwareOption ? "hardware" : "synthetic",
            ]
        )
        logGestureClassification(
            result: "hold",
            sessionID: sessionID,
            policy: .momentaryTrigger
        )
        AudioPipe.shared.beginRemoteCandidate()
        enterHoldingState()
        return true
    }

    private func startAcceptedVoicePress(
        sessionID: UUID,
        physicalDownAt: TimeInterval,
        onShortTap: (() -> Void)?,
        usesLocalMicrophone: Bool,
        togglesPersistentVoiceSession: Bool,
        bypassesShortClassification: Bool,
        usesHardwareOption: Bool,
        preparesRemoteTransport: Bool
    ) -> Bool {
        // Local capture is only used by explicit Codex short actions.
        pendingShortPreparationID = nil
        classifiedDualReceiverHold = false
        classifiedDualReceiverTriggerKey = nil
        AudioPipe.shared.setLocalMicrophoneCaptureEnabled(false)
        shortTapAction = onShortTap
        shortInputTogglesPersistentVoiceSession = togglesPersistentVoiceSession
        shortInputUsesLocalMicrophone = usesLocalMicrophone
        let isPersistentSessionSegment =
            togglesPersistentVoiceSession && voiceSessionMode == .persistentOpen
        remoteSegmentTriggerPolicy = isPersistentSessionSegment
            ? .audioOnly
            : .momentaryTrigger
        audioOnlyHardwareTriggerSuppressed = false
        resetAudioOnlyHardwareTriggerOnDrain = false
        usesHardwareOptionPath = usesHardwareOption
        remoteOutputDrainRequestedSessionID = nil
        remoteOutputDrainedSessionID = nil
        physicalUpSessionID = nil
        awaitingPhysicalVoiceKeyUp = false
        pendingVoiceUIHidden = preparesRemoteTransport
        gestureID = sessionID
        gesturePhysicalDownUptime = physicalDownAt
        VoiceTimingLogger.begin(sessionID: sessionID)
        _ = syntheticOptionTrigger.begin(sessionID: sessionID)
        let holdThreshold = isPersistentSessionSegment
            ? Self.persistentHoldActivationThreshold
            : Self.holdActivationThreshold
        diagnosticLogger?.log(
            category: "voice",
            event: "GESTURE_BEGIN",
            gestureID: sessionID,
            fields: [
                "session_mode": voiceSessionMode == .persistentOpen ? "persistent_open" : "idle",
                "persistent_configured_key": persistentSessionTriggerKey.rawValue,
                "persistent_owner_key": persistentSessionTriggerOwnerKey?.rawValue ?? "none",
                "momentary_configured_key": syntheticOptionTrigger.momentaryVoiceTriggerKey.rawValue,
                "policy": remoteSegmentTriggerPolicy == .audioOnly ? "audio_only" : "momentary_trigger",
            ]
        )
        diagnosticLogger?.log(
            category: "voice",
            event: "GESTURE_CLASSIFIER",
            gestureID: sessionID,
            key: syntheticOptionTrigger.momentaryVoiceTriggerKey,
            fields: [
                "session_mode": voiceSessionMode == .persistentOpen ? "persistent_open" : "idle",
                "threshold_ms": Int(holdThreshold * 1000),
                "momentary_key": syntheticOptionTrigger.momentaryVoiceTriggerKey.rawValue,
                "persistent_configured_key": persistentSessionTriggerKey.rawValue,
                "persistent_owner_key": persistentSessionTriggerOwnerKey?.rawValue ?? "none",
                "bypasses_short_classification": bypassesShortClassification,
            ]
        )
        if usesHardwareOptionPath {
            onHardwareOptionGateBegin?(sessionID)
        }
        remoteAudioAvailable = false
        longInputStarted = false
        AudioPipe.shared.beginRemoteCandidate()

        if bypassesShortClassification {
            logGestureClassification(result: "hold", sessionID: sessionID, policy: remoteSegmentTriggerPolicy)
            enterHoldingState()
            return true
        }

        setMode(.pending)
        if (preparesRemoteTransport || isPersistentSessionSegment)
            && !bypassesShortClassification {
            onRemoteTransportPreparation?()
        }
        let heldDuration = max(
            0,
            ProcessInfo.processInfo.systemUptime - physicalDownAt
        )
        let isLongPress = heldDuration >= holdThreshold
        let remainingHoldTime = holdThreshold - heldDuration
        guard !isLongPress else {
            promoteToLongPress()
            return true
        }
        let work = DispatchWorkItem { [weak self] in
            self?.promoteToLongPress()
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + remainingHoldTime,
            execute: work
        )
        print(
            "[PRESS] pending; classifying short tap vs remote-mic hold in "
                + "\(Int(holdThreshold * 1000)) ms"
        )
        return true
    }

    @discardableResult
    func keyUp() -> Bool {
        if let candidate = longOnlyCandidate {
            let heldDuration = max(
                0,
                ProcessInfo.processInfo.systemUptime - candidate.physicalDownAt
            )
            if !candidate.longConfirmed,
               heldDuration >= Self.holdActivationThreshold,
               var current = longOnlyCandidate {
                current.longConfirmed = true
                longOnlyCandidate = current
                tryPromoteLongOnlyCandidate(sessionID: current.sessionID)
            }
            if longOnlyCandidate != nil {
                _ = cancelLongOnlyCandidate(reason: "physical-up-before-promotion")
                return true
            }
            if directSession {
                return finishDirectVoicePressRelease()
            }
        }
        if deferredRepressWaitReason == .directOutputDrain,
           let pendingValue = pendingRepress,
           pendingValue.isDirectSession {
            pendingRepress = nil
            deferredRepressAwaitingActivation = false
            deferredRepressActivationWorkItem?.cancel()
            deferredRepressActivationWorkItem = nil
            deferredRepressWaitReason = nil
            if pendingValue.usesHardwareOption {
                onHardwareOptionGatePendingRepressCancel?(
                    pendingValue.sessionID,
                    "physical-up-before-activation"
                )
                clearPendingDirectHardwareRepressState()
            }
            print("[PRESS] pending direct re-press released before activation")
            return false
        }
        if directSession {
            return finishDirectVoicePressRelease()
        }
        holdWorkItem?.cancel()
        holdWorkItem = nil

        switch mode {
        case .idle:
            if awaitingPhysicalVoiceKeyUp {
                awaitingPhysicalVoiceKeyUp = false
                if let currentGestureID = gestureID {
                    physicalUpSessionID = currentGestureID
                    if usesHardwareOptionPath {
                        onHardwareOptionGatePhysicalUp?(currentGestureID)
                    }
                    logPhysicalGestureRelease(
                        sessionID: currentGestureID,
                        policy: remoteSegmentTriggerPolicy
                    )
                    if longInputStarted {
                        completeLongInputIfReady(sessionID: currentGestureID)
                    } else {
                        completeVoiceRouteWithoutAudio(sessionID: currentGestureID)
                    }
                }
                print("[PRESS] completed route consumed pending physical voice-key release")
                return true
            }
            guard let pendingRepress else { return false }
            let wasClassifiedDualReceiver = pendingRepress.classifiedTriggerKey != nil
            self.pendingRepress?.isStillHeld = false
            self.pendingRepress = nil
            deferredRepressAwaitingActivation = false
            deferredRepressActivationWorkItem?.cancel()
            deferredRepressActivationWorkItem = nil
            deferredRepressWaitReason = nil
            let shortID = String(pendingRepress.sessionID.uuidString.prefix(4))
            print(
                "[PRESS][\(shortID)] deferred re-press released before activation"
            )
            return wasClassifiedDualReceiver
        case .pending:
            let action = shortTapAction
            shortTapAction = nil
            let shouldPrepareLocalMicrophone = shortInputUsesLocalMicrophone
            shortInputUsesLocalMicrophone = false
            let shouldTogglePersistentSession = shortInputTogglesPersistentVoiceSession
            shortInputTogglesPersistentVoiceSession = false
            let currentGestureID = gestureID
            if let currentGestureID {
                logGestureClassification(
                    result: "short",
                    sessionID: currentGestureID,
                    policy: remoteSegmentTriggerPolicy
                )
            }
            let shouldUseHardwareOption = usesHardwareOptionPath
            gestureID = nil
            usesHardwareOptionPath = false
            pendingVoiceUIHidden = false
            setMode(.idle)
            setRemoteRouted(false)
            AudioPipe.shared.endRemoteCandidate()
            if let currentGestureID {
                VoiceTimingLogger.end(sessionID: currentGestureID)
            }
            if shouldPrepareLocalMicrophone, let currentGestureID {
                pendingShortPreparationID = currentGestureID
                print("[PRESS] SHORT release → preparing local microphone")
                AudioPipe.shared.setLocalMicrophoneCaptureEnabled(true) { [weak self] in
                    guard let self,
                          self.pendingShortPreparationID == currentGestureID else { return }
                    self.pendingShortPreparationID = nil
                    if let action {
                        print("[PRESS] SHORT local microphone ready → configured voice action")
                        self.onHardwareOptionGateCancel?(currentGestureID)
                        _ = self.syntheticOptionTrigger.abort(sessionID: currentGestureID)
                        action()
                    } else {
                        print("[PRESS] SHORT local microphone ready → configured trigger")
                        self.onHardwareOptionGateShortReplay?(currentGestureID)
                        self.emitShortPress(
                            sessionID: currentGestureID,
                            usesHardwareOption: shouldUseHardwareOption
                        )
                    }
                }
            } else if shouldTogglePersistentSession, let currentGestureID {
                let previousSessionMode = voiceSessionMode
                let nextSessionMode: VoiceSessionMode =
                    voiceSessionMode == .persistentOpen ? .idle : .persistentOpen
                let triggerKey = nextSessionMode == .persistentOpen
                    ? persistentSessionTriggerKey
                    : persistentSessionTriggerOwnerKey
                let triggerPurpose = nextSessionMode == .persistentOpen
                    ? "persistent_open" : "persistent_close"
                diagnosticLogger?.log(
                    category: "voice",
                    event: "PERSISTENT_TOGGLE_REQUEST",
                    gestureID: currentGestureID,
                    key: triggerKey,
                    fields: [
                        "current_mode": previousSessionMode == .persistentOpen ? "persistent_open" : "idle",
                        "configured_key": persistentSessionTriggerKey.rawValue,
                        "owner_key": persistentSessionTriggerOwnerKey?.rawValue ?? "none",
                        "target_mode": nextSessionMode == .persistentOpen ? "persistent_open" : "idle",
                        "purpose": triggerPurpose,
                    ]
                )
                let dispatchResult: PersistentShortTapDispatchResult
                if let triggerKey, let onPersistentSessionTriggerTap {
                    dispatchResult = onPersistentSessionTriggerTap(
                        currentGestureID,
                        triggerKey,
                        triggerPurpose
                    )
                } else if let triggerKey, !shouldUseHardwareOption {
                    dispatchResult = syntheticOptionTrigger.sendTap(
                        sessionID: currentGestureID,
                        key: triggerKey,
                        purpose: triggerPurpose
                    ) ? .emitted : .failed
                } else {
                    dispatchResult = .failed
                }
                switch dispatchResult {
                case .emitted:
                    if let triggerKey {
                        commitPersistentSessionToggle(
                            gestureID: currentGestureID,
                            expectedFromMode: previousSessionMode,
                            targetMode: nextSessionMode,
                            triggerKey: triggerKey,
                            purpose: triggerPurpose
                        )
                    } else {
                        _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
                        logPersistentTriggerFailure(
                            gestureID: currentGestureID,
                            triggerKey: nil,
                            purpose: triggerPurpose
                        )
                    }
                case let .deferred(waitingOn):
                    guard previousSessionMode == .persistentOpen,
                          nextSessionMode == .idle,
                          triggerPurpose == "persistent_close",
                          let triggerKey,
                          pendingPersistentToggle == nil else {
                        _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
                        logPersistentTriggerFailure(
                            gestureID: currentGestureID,
                            triggerKey: triggerKey,
                            purpose: triggerPurpose
                        )
                        return true
                    }
                    let pending = PendingPersistentToggle(
                        gestureID: currentGestureID,
                        expectedFromMode: previousSessionMode,
                        targetMode: nextSessionMode,
                        triggerKey: triggerKey,
                        purpose: triggerPurpose,
                        waitingGateOwner: waitingOn
                    )
                    pendingPersistentToggle = pending
                    diagnosticLogger?.log(
                        category: "voice",
                        event: "PERSISTENT_TRIGGER_DEFERRED",
                        gestureID: currentGestureID,
                        key: triggerKey,
                        fields: [
                            "purpose": triggerPurpose,
                            "trigger_key": triggerKey.rawValue,
                            "from": "persistent_open",
                            "target": "idle",
                            "waiting_gate_owner": waitingOn.uuidString,
                        ]
                    )
                case .failed:
                    _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
                    logPersistentTriggerFailure(
                        gestureID: currentGestureID,
                        triggerKey: triggerKey,
                        purpose: triggerPurpose
                    )
                }
            } else if let action {
                print("[PRESS] SHORT release → configured voice action")
                if let currentGestureID {
                    onHardwareOptionGateCancel?(currentGestureID)
                    _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
                }
                action()
            } else {
                print("[PRESS] SHORT release → configured voice trigger")
                if let currentGestureID {
                    onHardwareOptionGateShortReplay?(currentGestureID)
                    emitShortPress(
                        sessionID: currentGestureID,
                        usesHardwareOption: shouldUseHardwareOption
                    )
                }
            }
            return true
        case .holding:
            shortTapAction = nil
            shortInputUsesLocalMicrophone = false
            let releasedSessionID = gestureID
            let releasedPolicy = remoteSegmentTriggerPolicy
            if let releasedSessionID {
                physicalUpSessionID = releasedSessionID
                VoiceTimingLogger.mark("PHYSICAL_UP", sessionID: releasedSessionID)
                if usesHardwareOptionPath {
                    onHardwareOptionGatePhysicalUp?(releasedSessionID)
                }
            }
            setMode(.idle)
            let physicalUpAt = Date()
            lastPhysicalUpAt = physicalUpAt
            releaseBounceDebounceUntil = physicalUpAt.addingTimeInterval(
                releaseBounceDebounce
            )
            if longInputStarted {
                print("[PRESS] LONG release → finish immediately")
                scheduleLongFinish(sessionID: releasedSessionID)
            } else {
                print("[PRESS] LONG release → no remote audio; no Option dialog")
                finishLongInput(sessionID: releasedSessionID)
            }
            if let releasedSessionID, releasedPolicy == .audioOnly {
                logPhysicalGestureRelease(sessionID: releasedSessionID, policy: releasedPolicy)
            }
            if let releasedSessionID, releasedPolicy == .momentaryTrigger {
                logPhysicalGestureRelease(sessionID: releasedSessionID, policy: releasedPolicy)
            }
            return true
        case .opening, .streaming, .draining:
            return finishDirectVoicePressRelease()
        }
    }

    private func armCandidateTriggerOwnershipIfAvailable() {
        guard var candidate = longOnlyCandidate,
              candidate.triggerStrategy == .hardware,
              candidate.usesHardwareOption,
              !candidate.triggerOwnershipReady,
              candidate.isStillHeld else {
            return
        }
        let began: Bool
        if let beginResult = onHardwareOptionGateBeginResult {
            began = beginResult(candidate.sessionID)
        } else {
            onHardwareOptionGateBegin?(candidate.sessionID)
            began = true
        }
        guard began else { return }
        candidate.triggerOwnershipReady = true
        longOnlyCandidate = candidate
        tryPromoteLongOnlyCandidate(sessionID: candidate.sessionID)
    }

    /// The filter transfers the active SHORT tombstone into B's physical
    /// suppression owner before notifying this coordinator. B is then free to
    /// promote through its permanently selected synthetic fallback strategy;
    /// it must never reopen a physical replay gate for the same gesture.
    func longOnlyTriggerHandoffDidBecomeReady(sessionID: UUID) {
        guard var candidate = longOnlyCandidate,
              candidate.sessionID == sessionID,
              candidate.triggerStrategy == .syntheticHandoff,
              candidate.isStillHeld else {
            return
        }
        candidate.triggerOwnershipReady = true
        longOnlyCandidate = candidate
        tryPromoteLongOnlyCandidate(sessionID: sessionID)
    }

    func longOnlyTriggerHandoffWasInvalidated(
        sessionID: UUID,
        reason: String
    ) {
        guard longOnlyCandidate?.sessionID == sessionID else { return }
        _ = cancelLongOnlyCandidate(reason: "short-handoff-\(reason)")
    }

    func suppressedHardwareGateDidClose(ownerID: UUID) {
        armCandidateTriggerOwnershipIfAvailable()
        guard let pending = pendingPersistentToggle,
              pending.waitingGateOwner == ownerID else { return }
        pendingPersistentToggle = nil
        diagnosticLogger?.log(
            category: "voice",
            event: "PERSISTENT_TRIGGER_RETRY",
            gestureID: pending.gestureID,
            key: pending.triggerKey,
            fields: [
                "purpose": pending.purpose,
                "trigger_key": pending.triggerKey.rawValue,
                "from": persistentSessionModeName(for: pending.expectedFromMode),
                "target": persistentSessionModeName(for: pending.targetMode),
                "waiting_gate_owner": ownerID.uuidString,
            ]
        )

        guard voiceSessionMode == pending.expectedFromMode,
              let emitDeferred = onDeferredPersistentSessionTriggerTap,
              emitDeferred(pending.gestureID, pending.triggerKey, pending.purpose) else {
            _ = syntheticOptionTrigger.abort(sessionID: pending.gestureID)
            logPersistentTriggerFailure(
                gestureID: pending.gestureID,
                triggerKey: pending.triggerKey,
                purpose: pending.purpose
            )
            return
        }
        commitPersistentSessionToggle(
            gestureID: pending.gestureID,
            expectedFromMode: pending.expectedFromMode,
            targetMode: pending.targetMode,
            triggerKey: pending.triggerKey,
            purpose: pending.purpose
        )
    }

    func suppressedHardwareGateWasInvalidated(ownerID: UUID, reason: String) {
        armCandidateTriggerOwnershipIfAvailable()
        guard pendingPersistentToggle?.waitingGateOwner == ownerID else { return }
        cancelPendingPersistentToggle(reason: reason)
    }

    private func cancelPendingPersistentToggle(reason: String) {
        guard let pending = pendingPersistentToggle else { return }
        pendingPersistentToggle = nil
        _ = syntheticOptionTrigger.abort(sessionID: pending.gestureID)
        diagnosticLogger?.log(
            category: "voice",
            event: "PERSISTENT_TRIGGER_DEFERRED_CANCELLED",
            gestureID: pending.gestureID,
            key: pending.triggerKey,
            fields: [
                "purpose": pending.purpose,
                "trigger_key": pending.triggerKey.rawValue,
                "from": persistentSessionModeName(for: pending.expectedFromMode),
                "target": persistentSessionModeName(for: pending.targetMode),
                "waiting_owner": pending.waitingGateOwner.uuidString,
                "reason": reason,
            ]
        )
    }

    private func commitPersistentSessionToggle(
        gestureID: UUID,
        expectedFromMode: VoiceSessionMode,
        targetMode: VoiceSessionMode,
        triggerKey: VoiceTriggerKey,
        purpose: String
    ) {
        guard voiceSessionMode == expectedFromMode else {
            logPersistentTriggerFailure(
                gestureID: gestureID,
                triggerKey: triggerKey,
                purpose: purpose
            )
            return
        }
        voiceSessionMode = targetMode
        persistentSessionTriggerOwnerKey = targetMode == .persistentOpen
            ? triggerKey
            : nil
        diagnosticLogger?.log(
            category: "voice",
            event: "PERSISTENT_TRIGGER_RESULT",
            gestureID: gestureID,
            key: triggerKey,
            fields: ["result": "success", "purpose": purpose]
        )
        var stateFields: [String: Any] = [
            "from": persistentSessionModeName(for: expectedFromMode),
            "to": persistentSessionModeName(for: targetMode),
            "configured_key": persistentSessionTriggerKey.rawValue,
        ]
        if targetMode == .persistentOpen {
            stateFields["owner_key"] = triggerKey.rawValue
        } else {
            stateFields["closing_key"] = triggerKey.rawValue
        }
        diagnosticLogger?.log(
            category: "voice",
            event: "PERSISTENT_STATE_CHANGE",
            gestureID: gestureID,
            key: triggerKey,
            fields: stateFields
        )
        print("[PRESS] IME persistent session → \(targetMode)")
    }

    private func logPersistentTriggerFailure(
        gestureID: UUID,
        triggerKey: VoiceTriggerKey?,
        purpose: String
    ) {
        diagnosticLogger?.log(
            category: "voice",
            event: "PERSISTENT_TRIGGER_RESULT",
            gestureID: gestureID,
            key: triggerKey,
            fields: [
                "result": "failed",
                "purpose": purpose,
                "state_unchanged": true,
            ]
        )
        print("[PRESS] IME persistent session unchanged; configured trigger tap failed")
    }

    private func persistentSessionModeName(for mode: VoiceSessionMode) -> String {
        mode == .persistentOpen ? "persistent_open" : "idle"
    }

    func setPreHIDPhysicalStreaming(_ streaming: Bool) {
        if !streaming, hasLivePhysicalCandidate?() == true {
            // An old epoch's callback must not erase newer BLE-owned truth.
            return
        }
        preHIDPhysicalStreaming = streaming
        diagnosticLogger?.log(
            category: "voice",
            event: streaming ? "PHYSICAL_HTT_CANDIDATE_START" : "PHYSICAL_HTT_CANDIDATE_STOP",
            gestureID: gestureID,
            key: capturedVoiceProfile?.triggerKey,
            fields: [
                "pre_hid_physical_streaming": streaming,
                "voice_session_ownership": false,
            ]
        )
        print(
            "[PRESS] PHYSICAL_HTT candidate streaming=\(streaming); "
                + "voice_session_ownership=\(remoteStreaming)"
        )
    }

    func setRemoteStreaming(_ streaming: Bool) {
        if directSession {
            if hasLivePhysicalCandidate?() != true {
                preHIDPhysicalStreaming = false
            }
            remoteStreaming = streaming
            directTransportStopObserved = !streaming
            diagnosticLogger?.log(
                category: "voice",
                event: streaming ? "AUDIO_START" : "AUDIO_STOP",
                gestureID: gestureID,
                key: capturedVoiceProfile?.triggerKey,
                fields: [
                    "voice_session_state": streaming ? "streaming" : modeName,
                    "remote_streaming": streaming,
                    "remote_routed": remoteRouted,
                ]
            )
            if streaming {
                setMode(.streaming)
            } else if directPhysicalUp, let currentGestureID = gestureID {
                finishDirectTransportStop(sessionID: currentGestureID)
            }
            print(
                "[PRESS] ATVV streaming=\(streaming); "
                    + "voice_session_state=\(modeName)"
            )
            return
        }
        remoteStreaming = streaming
        diagnosticLogger?.log(
            category: "voice",
            event: streaming ? "AUDIO_START" : "AUDIO_STOP",
            gestureID: gestureID,
            fields: [
                "session_mode": voiceSessionMode == .persistentOpen ? "persistent_open" : "idle",
                "remote_streaming": streaming,
                "remote_routed": remoteRouted,
            ]
        )
        if !streaming {
            remoteAudioAvailable = false
            onRemoteAudioChanged?(false)
            if mode == .holding {
                // The BLE side has stopped accepting input, but queued PCM
                // still owns the Option-up lifetime.
                print("[PRESS] remote audio stopped after drain; waiting for output drain")
                if longInputStarted {
                    awaitingPhysicalVoiceKeyUp = true
                    setMode(.idle)
                    requestRemoteOutputDrain(sessionID: gestureID)
                } else if remoteSegmentTriggerPolicy == .audioOnly {
                    // Keep the captured mapped edge owned until the physical
                    // voice-key release can arm its suppressed-up lifecycle.
                    awaitingPhysicalVoiceKeyUp = true
                    setRemoteRouted(false)
                    AudioPipe.shared.endRemoteCandidate()
                    setMode(.idle)
                } else {
                    if let currentGestureID = gestureID {
                        onHardwareOptionGateCancel?(currentGestureID)
                        _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
                    }
                    setMode(.idle)
                    finishLongInput(sessionID: gestureID)
                }
            } else if longInputStarted {
                // The physical HID edge may have arrived before the BLE
                // drain callback. Preserve the same output-drain barrier.
                print("[PRESS] remote audio drain complete; waiting for output drain")
                requestRemoteOutputDrain(sessionID: gestureID)
            }
        }
        // BLE availability is informational only. HID owns gesture lifetime
        // and routing policy; transient ATVV events never toggle the IME
        // session or fall back to the physical mic during a hold.
        print(
            "[PRESS] ATVV streaming=\(streaming); " +
            "gesture=\(modeName); routed=\(remoteRouted)"
        )
    }

    /// Retire the old direct session's transport ownership when a distinct
    /// physical AUDIO_START supersedes its BLE drain. This is intentionally a
    /// separate event from `setRemoteStreaming(false)`: A must begin its
    /// existing output/trigger-UP lifecycle while B's candidate remains live.
    func handlePhysicalTransportSupersession() {
        guard directSession, let sessionID = gestureID else { return }
        remoteStreaming = false
        directTransportStopObserved = true
        preserveCandidateForDirectTransportStop = true
        onRemoteAudioChanged?(false)
        diagnosticLogger?.log(
            category: "voice",
            event: "PHYSICAL_TRANSPORT_SUPERSEDED",
            gestureID: sessionID,
            key: capturedVoiceProfile?.triggerKey,
            fields: [
                "voice_session_state": modeName,
                "preserve_replacement_candidate": true,
                "physical_up_seen": directPhysicalUp,
            ]
        )
        if directPhysicalUp {
            finishDirectTransportStop(sessionID: sessionID)
        }
    }

    /// The BLE transport may announce AUDIO_START before delivering any PCM.
    /// Only the first decoded frame authorizes the long-press Option hold.
    func setRemoteAudioAvailable() {
        if directSession {
            guard let currentGestureID = gestureID, !remoteAudioAvailable else { return }
            remoteAudioAvailable = true
            VoiceTimingLogger.mark("AUDIO_FIRST", sessionID: currentGestureID)
            diagnosticLogger?.log(
                category: "voice",
                event: "AUDIO_FIRST",
                gestureID: currentGestureID,
                key: capturedVoiceProfile?.triggerKey,
                fields: [
                    "voice_session_state": modeName,
                    "voice_input_profile_id": capturedVoiceProfile?.id ?? "unknown",
                ]
            )
            onRemoteAudioChanged?(true)
            return
        }
        guard mode == .pending || mode == .holding else { return }
        guard !remoteAudioAvailable else { return }
        remoteAudioAvailable = true
        if let currentGestureID = gestureID {
            VoiceTimingLogger.mark("AUDIO_FIRST", sessionID: currentGestureID)
            diagnosticLogger?.log(
                category: "voice",
                event: "AUDIO_FIRST",
                gestureID: currentGestureID,
                fields: ["session_mode": voiceSessionMode == .persistentOpen ? "persistent_open" : "idle"]
            )
            if remoteSegmentTriggerPolicy == .audioOnly {
                diagnosticLogger?.log(
                    category: "voice",
                    event: "PERSISTENT_SEGMENT_AUDIO_FIRST",
                    gestureID: currentGestureID,
                    fields: ["owner_key": persistentSessionTriggerOwnerKey?.rawValue ?? "none"]
                )
            }
        }
        if mode == .holding {
            onRemoteAudioChanged?(true)
        }
        guard mode == .holding else { return }
        beginLongInput()
    }

    func stop() {
        _ = cancelLongOnlyCandidate(reason: "stop")
        if directSession, let sessionID = gestureID {
            if !directPhysicalUp {
                _ = finishDirectVoicePressRelease()
            }
            if !directOutputDrainRequested {
                completeDirectVoiceSession(sessionID: sessionID)
            }
            return
        }
        stopCurrentVoiceState(preservingDeferredRepress: false)
    }

    /// A removed HID device cannot deliver the matching physical UP. Retire
    /// the private candidate and its bounded trigger/transport ownership at
    /// the same identity-preserving boundary as the rest of HID cleanup.
    func cancelLongOnlyCandidateForHIDRemoval() {
        _ = cancelLongOnlyCandidate(reason: "hid-removed")
    }

    func stopCurrentVoiceStatePreservingDeferredRepress() {
        guard deferredRepressAwaitingActivation, pendingRepress != nil else {
            stop()
            return
        }
        print("[PRESS] preserving deferred re-press across old transport teardown")
        stopCurrentVoiceState(preservingDeferredRepress: true)
    }

    /// The BLE bridge calls this after the old AUDIO_STOP drain has fully
    /// retired. Activate the retained physical press on the next main-queue
    /// turn so Session A's callback stack cannot run into Session B.
    func voiceSessionAdmissionBecameAvailable() {
        if let candidate = longOnlyCandidate,
           candidate.longConfirmed,
           candidate.isStillHeld {
            if candidate.waitsForPreviousOwnership {
                tryActivatePendingDirectHardwareRepress()
            } else {
                tryPromoteLongOnlyCandidate(sessionID: candidate.sessionID)
            }
        }
        guard deferredRepressAwaitingActivation,
              deferredRepressWaitReason == .audioDrain,
              pendingRepress != nil,
              mode == .idle,
              !remoteRouted,
              !longInputStarted,
              tailWorkItem == nil,
              gestureID == nil,
              remoteOutputDrainRequestedSessionID == nil,
              isVoiceSessionAdmissionBlocked?() != true else {
            return
        }
        deferredRepressAwaitingActivation = false
        deferredRepressWaitReason = nil
        deferredRepressActivationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deferredRepressActivationWorkItem = nil
            guard let pendingRepress = self.pendingRepress else { return }
            self.lastRepressDecisionForTesting = "admitted-after-audio-drain"
            self.logAdmissionDecision(
                sessionID: pendingRepress.sessionID,
                result: "admitted",
                reason: "audio_drain_cleared"
            )
            self.activatePendingRepressIfHeld()
        }
        deferredRepressActivationWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    /// Records whether the old hardware trigger-up now has an event-tap
    /// replay awaiting acknowledgement. A direct pending re-press may not
    /// activate until that acknowledgement boundary is complete.
    func hardwareOptionGateOutputDrainCompleted(
        sessionID: UUID,
        awaitingPassAcknowledgement: Bool
    ) {
        guard pendingDirectHardwareRepressOldSessionID == sessionID else {
            return
        }
        pendingDirectHardwareRepressAwaitingOldUp = awaitingPassAcknowledgement
        tryActivatePendingDirectHardwareRepress()
    }

    /// Called only after the filter has observed every replayed old UP
    /// component pass the event-tap boundary.
    func hardwareOptionUpPassAcknowledged(sessionID: UUID) {
        guard pendingDirectHardwareRepressOldSessionID == sessionID else {
            return
        }
        pendingDirectHardwareRepressAwaitingOldUp = false
        tryActivatePendingDirectHardwareRepress()
    }

    /// End the current transport segment while retaining a persistent IME
    /// session. A transport loss is a segment boundary, never a session tap.
    func handleTransportLoss(deviceRemoved: Bool = false) {
        if deviceRemoved {
            _ = cancelLongOnlyCandidate(reason: "hid-removed")
        }
        if directSession {
            remoteStreaming = false
            directTransportStopObserved = true
            onRemoteAudioChanged?(false)
            if deviceRemoved, !directPhysicalUp {
                _ = finishDirectVoicePressRelease()
            }
            if let sessionID = gestureID {
                // A transport failure is a terminal retirement boundary even
                // when HID has not delivered physical UP. The existing output
                // drain and trigger-owner guards still serialize final release;
                // the optional physical-up bypass only prevents a dead ATVV
                // session from leaving the trigger and route permanently held.
                if !directPhysicalUp {
                    VoiceTimingLogger.mark("STOP_REQUESTED", sessionID: sessionID)
                    diagnosticLogger?.log(
                        category: "voice",
                        event: "VOICE_TRANSPORT_LOST",
                        gestureID: sessionID,
                        key: capturedVoiceProfile?.triggerKey,
                        fields: [
                            "voice_session_state": modeName,
                            "physical_up_seen": false,
                            "device_removed": deviceRemoved,
                        ]
                    )
                }
                finishDirectTransportStop(
                    sessionID: sessionID,
                    allowWithoutPhysicalUp: true
                )
            }
            return
        }
        guard voiceSessionMode == .persistentOpen else {
            if deviceRemoved,
               pendingRepress?.classifiedTriggerKey != nil {
                deferredRepressActivationWorkItem?.cancel()
                deferredRepressActivationWorkItem = nil
                deferredRepressAwaitingActivation = false
                pendingRepress = nil
            }
            stopCurrentVoiceStatePreservingDeferredRepress()
            return
        }

        if deviceRemoved, let pending = pendingPersistentToggle {
            onHardwareOptionGateResetSuppression?(pending.waitingGateOwner)
            if pendingPersistentToggle?.gestureID == pending.gestureID {
                cancelPendingPersistentToggle(reason: "device-removed")
            }
        }

        remoteStreaming = false
        remoteAudioAvailable = false
        onRemoteAudioChanged?(false)
        holdWorkItem?.cancel()
        holdWorkItem = nil
        tailWorkItem?.cancel()
        tailWorkItem = nil
        tailSessionID = nil

        guard let sessionID = gestureID else {
            setRemoteRouted(false)
            AudioPipe.shared.endRemoteCandidate()
            if mode != .idle {
                setMode(.idle)
            }
            shortTapAction = nil
            shortInputUsesLocalMicrophone = false
            shortInputTogglesPersistentVoiceSession = false
            pendingVoiceUIHidden = false
            return
        }

        print("[PRESS] transport lost; ending persistent remote segment")
        if physicalUpSessionID != sessionID {
            if deviceRemoved {
                // A removed HID device cannot deliver its matching key-up.
                // Its suppression owner is explicitly reset after audio drain.
                resetAudioOnlyHardwareTriggerOnDrain = true
                physicalUpSessionID = sessionID
                awaitingPhysicalVoiceKeyUp = false
                let physicalUpAt = Date()
                lastPhysicalUpAt = physicalUpAt
                releaseBounceDebounceUntil = physicalUpAt.addingTimeInterval(
                    releaseBounceDebounce
                )
            } else {
                // A BLE loss alone does not prove that the physical key is up.
                awaitingPhysicalVoiceKeyUp = true
            }
        }
        if mode != .idle {
            setMode(.idle)
        }
        if longInputStarted {
            requestRemoteOutputDrain(sessionID: sessionID)
        } else if physicalUpSessionID == sessionID {
            completeVoiceRouteWithoutAudio(sessionID: sessionID)
        } else {
            setRemoteRouted(false)
            AudioPipe.shared.endRemoteCandidate()
        }
    }

    private func stopCurrentVoiceState(preservingDeferredRepress: Bool) {
        cancelPendingPersistentToggle(reason: "voice-stop")
        let shouldResetSuppressedHardwareTrigger =
            remoteSegmentTriggerPolicy == .audioOnly && audioOnlyHardwareTriggerSuppressed
        holdWorkItem?.cancel()
        holdWorkItem = nil
        tailWorkItem?.cancel()
        tailWorkItem = nil
        tailSessionID = nil
        if !preservingDeferredRepress {
            deferredRepressActivationWorkItem?.cancel()
            deferredRepressActivationWorkItem = nil
            deferredRepressAwaitingActivation = false
            pendingRepress = nil
            deferredRepressWaitReason = nil
        }
        releaseBounceDebounceUntil = .distantPast
        lastPhysicalUpAt = nil
        shortTapAction = nil
        shortInputUsesLocalMicrophone = false
        shortInputTogglesPersistentVoiceSession = false
        voiceSessionMode = .idle
        persistentSessionTriggerOwnerKey = nil
        remoteSegmentTriggerPolicy = .momentaryTrigger
        audioOnlyHardwareTriggerSuppressed = false
        resetAudioOnlyHardwareTriggerOnDrain = false
        classifiedDualReceiverHold = false
        classifiedDualReceiverTriggerKey = nil
        let stoppedSessionID = gestureID
        if let currentGestureID = gestureID {
            if shouldResetSuppressedHardwareTrigger {
                onHardwareOptionGateResetSuppression?(currentGestureID)
            } else {
                onHardwareOptionGateCancel?(currentGestureID)
            }
            _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
        } else {
            _ = syntheticOptionTrigger.reset()
        }
        gestureID = nil
        usesHardwareOptionPath = false
        pendingShortPreparationID = nil
        AudioPipe.shared.setLocalMicrophoneCaptureEnabled(false)
        setMode(.idle)
        setRemoteRouted(false)
        AudioPipe.shared.endRemoteCandidate()
        pendingVoiceUIHidden = false
        longInputStarted = false
        remoteAudioAvailable = false
        remoteStreaming = false
        awaitingPhysicalVoiceKeyUp = false
        remoteOutputDrainRequestedSessionID = nil
        remoteOutputDrainedSessionID = nil
        physicalUpSessionID = nil
        if let stoppedSessionID {
            VoiceTimingLogger.mark("ROUTE_OFF", sessionID: stoppedSessionID)
            VoiceTimingLogger.end(sessionID: stoppedSessionID)
        }
    }

    private func promoteToLongPress() {
        guard mode == .pending else { return }
        holdWorkItem = nil
        if let currentGestureID = gestureID {
            logGestureClassification(
                result: "hold",
                sessionID: currentGestureID,
                policy: remoteSegmentTriggerPolicy
            )
        }
        enterHoldingState()
    }

    private func enterHoldingState() {
        guard let currentGestureID = gestureID else { return }
        shortTapAction = nil
        shortInputUsesLocalMicrophone = false
        shortInputTogglesPersistentVoiceSession = false
        VoiceTimingLogger.mark("HOLD_CONFIRMED", sessionID: currentGestureID)
        VoiceTimingLogger.mark("BLE_START_REQUEST", sessionID: currentGestureID)
        if remoteSegmentTriggerPolicy == .audioOnly, usesHardwareOptionPath {
            audioOnlyHardwareTriggerSuppressed =
                onHardwareOptionGateSuppressForAudioOnly?(currentGestureID) ?? false
            if !audioOnlyHardwareTriggerSuppressed {
                print(
                    "[PRESS] audio-only trigger suppression transfer unavailable; "
                        + "keeping the mapped edge behind its active gate"
                )
            }
        }
        setMode(.holding)

        // Route selection follows the physical HID hold, not BLE notifications.
        // If ATVV is late or briefly drops, emit silence rather than leaking
        // the physical microphone into a remote-only gesture.
        VoiceTimingLogger.mark("REMOTE_ROUTE_BEGIN", sessionID: currentGestureID)
        onRemoteRoutePreparation?()
        setRemoteRouted(true)
        print(
            "[PRESS] LONG start → waiting for remote audio; source=" +
            (remoteStreaming ? "stream announced" : "remote waiting")
        )
        if remoteAudioAvailable {
            beginLongInput()
        }
    }

    private func beginLongInput() {
        guard mode == .holding, !longInputStarted else { return }
        longInputStarted = true
        guard let currentGestureID = gestureID else { return }
        if remoteSegmentTriggerPolicy == .audioOnly {
            diagnosticLogger?.log(
                category: "voice",
                event: "PERSISTENT_SEGMENT_BEGIN",
                gestureID: currentGestureID,
                key: syntheticOptionTrigger.momentaryVoiceTriggerKey,
                fields: [
                    "owner_key": persistentSessionTriggerOwnerKey?.rawValue ?? "none",
                    "momentary_physical_key": syntheticOptionTrigger.momentaryVoiceTriggerKey.rawValue,
                    "policy": "audio_only",
                    "trigger_edge_emitted": false,
                    "first_pcm": true,
                ]
            )
            print("[PRESS] persistent IME segment audio ready; no trigger edge")
        } else if classifiedDualReceiverHold {
            guard let selectedKey = classifiedDualReceiverTriggerKey else {
                print("[PRESS] classified dual receiver transaction has no captured key")
                _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
                return
            }
            guard syntheticOptionTrigger.sendDown(
                sessionID: currentGestureID,
                key: selectedKey,
                purpose: "dual_receiver_\(selectedKey.rawValue)"
            ) else {
                print("[PRESS] dual receiver selected trigger DOWN was rejected")
                return
            }
            print("[PRESS] dual receiver first PCM → \(selectedKey.displayName) DOWN")
        } else if usesHardwareOptionPath {
            print("[PRESS] LONG audio ready → Option DOWN; source=remote")
            print("[PRESS] LONG uses hardware-held \(syntheticOptionTrigger.momentaryVoiceTriggerKey.displayName)")
            onHardwareOptionGateLongReady?(currentGestureID)
            VoiceTimingLogger.mark("OPTION_GATE_RELEASE", sessionID: currentGestureID)
            diagnosticLogger?.log(
                category: "voice",
                event: "MOMENTARY_HOLD_READY",
                gestureID: currentGestureID,
                key: syntheticOptionTrigger.momentaryVoiceTriggerKey,
                fields: ["source": "hardware", "first_pcm": true]
            )
        } else {
            // Fallback for systems where hidutil could not be applied.
            print("[PRESS] LONG audio ready → Option DOWN; source=remote")
            print("[PRESS] LONG uses synthetic \(syntheticOptionTrigger.momentaryVoiceTriggerKey.displayName)")
            _ = syntheticOptionTrigger.sendDown(sessionID: currentGestureID)
            VoiceTimingLogger.mark("OPTION_GATE_RELEASE", sessionID: currentGestureID)
            diagnosticLogger?.log(
                category: "voice",
                event: "MOMENTARY_HOLD_READY",
                gestureID: currentGestureID,
                key: syntheticOptionTrigger.momentaryVoiceTriggerKey,
                fields: ["source": "synthetic", "first_pcm": true]
            )
        }
    }

    private func scheduleLongFinish(sessionID: UUID?) {
        guard longInputStarted else {
            setRemoteRouted(false)
            AudioPipe.shared.endRemoteCandidate()
            longInputStarted = false
            remoteAudioAvailable = false
            gestureID = nil
            usesHardwareOptionPath = false
            tailSessionID = nil
            return
        }
        tailWorkItem?.cancel()
        tailSessionID = sessionID
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.tailSessionID == sessionID else {
                print("[PRESS] stale tail completion ignored")
                return
            }
            self.tailWorkItem = nil
            self.tailSessionID = nil
            self.requestRemoteOutputDrain(sessionID: sessionID)
        }
        tailWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.tailDrainDelay,
            execute: work
        )
    }

    private func activatePendingRepressIfHeld() {
        guard let pendingRepress else { return }
        let longOnlyCandidate = self.longOnlyCandidate
        if pendingRepress.isDirectSession,
           let longOnlyCandidate,
           (longOnlyCandidate.sessionID != pendingRepress.sessionID
                || !longOnlyCandidate.longConfirmed
                || !longOnlyCandidate.isStillHeld) {
            return
        }
        self.pendingRepress = nil
        deferredRepressWaitReason = nil
        guard pendingRepress.isStillHeld else {
            if pendingRepress.isDirectSession {
                clearPendingDirectHardwareRepressState()
            }
            return
        }

        if pendingRepress.isDirectSession {
            guard livePhysicalCandidateForAdmission else {
                clearPendingDirectHardwareRepressState()
                print("[PRESS] direct re-press activation lost physical candidate")
                return
            }
            let activated = startDirectVoicePress(
                sessionID: pendingRepress.sessionID,
                profile: pendingRepress.directProfile ?? .defaultProfile,
                usesHardwareOption: pendingRepress.usesHardwareOption,
                promotingPendingHardwareRepress: pendingRepress.usesHardwareOption
            )
            clearPendingDirectHardwareRepressState()
            guard activated else {
                if let longOnlyCandidate {
                    self.longOnlyCandidate = nil
                    self.longOnlyCandidateTimer?.cancel()
                    self.longOnlyCandidateTimer = nil
                    finishFailedLongOnlyCandidate(longOnlyCandidate)
                }
                print("[PRESS] direct re-press activation rejected")
                return
            }
            if let longOnlyCandidate {
                self.longOnlyCandidate = nil
                self.longOnlyCandidateTimer?.cancel()
                self.longOnlyCandidateTimer = nil
                onLongOnlyCandidatePromoted?(
                    longOnlyCandidate.sessionID,
                    longOnlyCandidate.targetApplicationBundleIdentifier
                )
            }
            lastRepressDecisionForTesting = "admitted-after-direct-output-drain"
            return
        }

        let heldDuration = max(
            0,
            ProcessInfo.processInfo.systemUptime - pendingRepress.physicalDownAt
        )
        let shortID = String(pendingRepress.sessionID.uuidString.prefix(4))
        print(
            "[PRESS][\(shortID)] deferred re-press activated held=" +
                String(format: "%.1fms", heldDuration * 1000)
        )
        if let triggerKey = pendingRepress.classifiedTriggerKey {
            _ = startClassifiedHold(
                sessionID: pendingRepress.sessionID,
                physicalDownAt: pendingRepress.physicalDownAt,
                triggerKey: triggerKey
            )
            return
        }
        _ = startAcceptedVoicePress(
            sessionID: pendingRepress.sessionID,
            physicalDownAt: pendingRepress.physicalDownAt,
            onShortTap: pendingRepress.onShortTap,
            usesLocalMicrophone: pendingRepress.usesLocalMicrophone,
            togglesPersistentVoiceSession: pendingRepress.togglesPersistentVoiceSession,
            bypassesShortClassification: pendingRepress.bypassesShortClassification,
            usesHardwareOption: pendingRepress.usesHardwareOption,
            preparesRemoteTransport: pendingRepress.preparesRemoteTransport
        )
    }

    private func scheduleDeferredRepressActivation(
        waitReason: DeferredRepressWaitReason = .previousRoute
    ) {
        guard pendingRepress != nil else { return }
        deferredRepressAwaitingActivation = true
        deferredRepressWaitReason = waitReason
        deferredRepressActivationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deferredRepressActivationWorkItem = nil
            guard self.deferredRepressAwaitingActivation else { return }
            self.deferredRepressAwaitingActivation = false
            self.activatePendingRepressIfHeld()
        }
        deferredRepressActivationWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    func finishLongInput(sessionID: UUID?) {
        if let sessionID, gestureID != sessionID {
            print(
                "[PRESS] stale tail completion ignored session=" +
                    sessionID.uuidString + " current=" +
                    (gestureID?.uuidString ?? "none")
            )
            return
        }
        guard let currentSessionID = sessionID ?? gestureID else { return }
        guard longInputStarted else {
            completeVoiceRouteWithoutAudio(sessionID: currentSessionID)
            return
        }
        requestRemoteOutputDrain(sessionID: currentSessionID)
        completeLongInputIfReady(sessionID: currentSessionID)
    }

    private func requestRemoteOutputDrain(sessionID: UUID?) {
        guard let sessionID,
              gestureID == sessionID,
              longInputStarted else { return }
        if remoteOutputDrainRequestedSessionID == sessionID {
            completeLongInputIfReady(sessionID: sessionID)
            return
        }

        // Stop accepting new remote samples before asking the output side to
        // drain. `setRemoteActive(false)` keeps already queued PCM alive.
        AudioPipe.shared.endRemoteCandidate()
        _ = setRemoteRouted(false)
        VoiceTimingLogger.mark("STOP_REQUESTED", sessionID: sessionID)
        VoiceTimingLogger.mark("OUTPUT_DRAIN_BEGIN", sessionID: sessionID)
        diagnosticLogger?.log(
            category: "voice",
            event: "OUTPUT_DRAIN_BEGIN",
            gestureID: sessionID,
            fields: [
                "session_mode": voiceSessionMode == .persistentOpen ? "persistent_open" : "idle",
                "tail_pending": tailWorkItem != nil,
            ]
        )
        remoteOutputDrainRequestedSessionID = sessionID

        let completion = { [weak self] in
            guard let self,
                  self.gestureID == sessionID,
                  self.longInputStarted else { return }
            self.remoteOutputDrainedSessionID = sessionID
            VoiceTimingLogger.mark("AUDIO_PIPELINE_CLOSED", sessionID: sessionID)
            self.diagnosticLogger?.log(
                category: "voice",
                event: "OUTPUT_DRAIN_COMPLETE",
                gestureID: sessionID,
                fields: ["session_mode": self.voiceSessionMode == .persistentOpen ? "persistent_open" : "idle"]
            )
            self.completeLongInputIfReady(sessionID: sessionID)
        }
        if let onRemoteOutputDrain {
            onRemoteOutputDrain(sessionID, completion)
        } else {
            completion()
        }
    }

    private func completeLongInputIfReady(sessionID: UUID) {
        guard gestureID == sessionID,
              longInputStarted,
              remoteOutputDrainedSessionID == sessionID,
              physicalUpSessionID == sessionID else { return }

        holdWorkItem?.cancel()
        holdWorkItem = nil
        tailWorkItem?.cancel()
        tailWorkItem = nil
        tailSessionID = nil
        VoiceTimingLogger.mark("OPTION_UP_REQUESTED", sessionID: sessionID)
        if remoteSegmentTriggerPolicy == .audioOnly {
            _ = syntheticOptionTrigger.abort(sessionID: sessionID)
            if usesHardwareOptionPath {
                if audioOnlyHardwareTriggerSuppressed {
                    if resetAudioOnlyHardwareTriggerOnDrain {
                        onHardwareOptionGateResetSuppression?(sessionID)
                    } else {
                        onHardwareOptionGateOutputDrained?(sessionID)
                    }
                } else {
                    onHardwareOptionGateCancel?(sessionID)
                }
            }
            print("[PRESS] persistent IME segment ended without trigger edge")
            diagnosticLogger?.log(
                category: "voice",
                event: "PERSISTENT_SEGMENT_COMPLETE",
                gestureID: sessionID,
                fields: [
                    "owner_key": persistentSessionTriggerOwnerKey?.rawValue ?? "none",
                    "session_remains_open": voiceSessionMode == .persistentOpen,
                ]
            )
        } else if classifiedDualReceiverHold {
            _ = syntheticOptionTrigger.abort(sessionID: sessionID)
        } else if usesHardwareOptionPath {
            onHardwareOptionGateOutputDrained?(sessionID)
            print("[PRESS] LONG end → Option UP after output drain")
        } else if syntheticOptionTrigger.sendUp(sessionID: sessionID) {
            print("[PRESS] LONG end → synthetic Option UP after output drain")
        } else {
            _ = syntheticOptionTrigger.abort(sessionID: sessionID)
        }
        if remoteSegmentTriggerPolicy == .momentaryTrigger {
            diagnosticLogger?.log(
                category: "voice",
                event: "MOMENTARY_COMPLETE",
                gestureID: sessionID,
                key: syntheticOptionTrigger.momentaryVoiceTriggerKey,
                fields: ["source": usesHardwareOptionPath ? "hardware" : "synthetic"]
            )
        }
        longInputStarted = false
        remoteAudioAvailable = false
        gestureID = nil
        usesHardwareOptionPath = false
        remoteOutputDrainRequestedSessionID = nil
        remoteOutputDrainedSessionID = nil
        physicalUpSessionID = nil
        awaitingPhysicalVoiceKeyUp = false
        pendingVoiceUIHidden = false
        shortInputUsesLocalMicrophone = false
        shortInputTogglesPersistentVoiceSession = false
        remoteSegmentTriggerPolicy = .momentaryTrigger
        audioOnlyHardwareTriggerSuppressed = false
        resetAudioOnlyHardwareTriggerOnDrain = false
        classifiedDualReceiverHold = false
        classifiedDualReceiverTriggerKey = nil
        if mode != .idle {
            setMode(.idle)
        }
        VoiceTimingLogger.mark("ROUTE_OFF", sessionID: sessionID)
        VoiceTimingLogger.end(sessionID: sessionID)
        scheduleDeferredRepressActivation()
    }

    private func completeVoiceRouteWithoutAudio(sessionID: UUID) {
        if remoteSegmentTriggerPolicy == .audioOnly {
            diagnosticLogger?.log(
                category: "voice",
                event: "PERSISTENT_SEGMENT_COMPLETE",
                gestureID: sessionID,
                fields: [
                    "owner_key": persistentSessionTriggerOwnerKey?.rawValue ?? "none",
                    "session_remains_open": voiceSessionMode == .persistentOpen,
                    "first_pcm": false,
                ]
            )
        }
        if remoteSegmentTriggerPolicy == .audioOnly,
           usesHardwareOptionPath,
           audioOnlyHardwareTriggerSuppressed {
            if resetAudioOnlyHardwareTriggerOnDrain {
                onHardwareOptionGateResetSuppression?(sessionID)
            } else {
                onHardwareOptionGateOutputDrained?(sessionID)
            }
        } else {
            onHardwareOptionGateCancel?(sessionID)
        }
        _ = syntheticOptionTrigger.abort(sessionID: sessionID)
        _ = setRemoteRouted(false)
        AudioPipe.shared.endRemoteCandidate()
        longInputStarted = false
        remoteAudioAvailable = false
        gestureID = nil
        usesHardwareOptionPath = false
        remoteOutputDrainRequestedSessionID = nil
        remoteOutputDrainedSessionID = nil
        physicalUpSessionID = nil
        awaitingPhysicalVoiceKeyUp = false
        pendingVoiceUIHidden = false
        shortInputUsesLocalMicrophone = false
        shortInputTogglesPersistentVoiceSession = false
        remoteSegmentTriggerPolicy = .momentaryTrigger
        audioOnlyHardwareTriggerSuppressed = false
        resetAudioOnlyHardwareTriggerOnDrain = false
        classifiedDualReceiverHold = false
        classifiedDualReceiverTriggerKey = nil
        VoiceTimingLogger.mark("ROUTE_OFF", sessionID: sessionID)
        VoiceTimingLogger.end(sessionID: sessionID)
        scheduleDeferredRepressActivation()
    }

    /// Emit one configured-trigger tap for opening or closing the IME session.
    private func emitShortPress(
        sessionID: UUID,
        usesHardwareOption: Bool
    ) {
        if usesHardwareOption {
            print("[PRESS] SHORT → hardware trigger tap; persistent IME session")
        } else {
            print("[PRESS] SHORT → synthetic trigger tap; persistent IME session")
            _ = syntheticOptionTrigger.sendTap(sessionID: sessionID)
        }
    }

    @discardableResult
    private func setRemoteRouted(_ active: Bool) -> Int {
        guard remoteRouted != active else { return 0 }
        remoteRouted = active
        return AudioPipe.shared.setRemoteActive(active)
    }

    private func setMode(_ newMode: State) {
        guard mode != newMode else { return }
        mode = newMode
        onStateChanged?(newMode)
    }

    private var modeName: String {
        switch mode {
        case .idle: return "idle"
        case .opening: return "opening"
        case .streaming: return "streaming"
        case .draining: return "draining"
        case .pending: return "pending"
        case .holding: return "holding"
        }
    }

    private func logGestureClassification(
        result: String,
        sessionID: UUID,
        policy: RemoteSegmentTriggerPolicy
    ) {
        let heldDuration = max(
            0,
            ProcessInfo.processInfo.systemUptime - (gesturePhysicalDownUptime ?? ProcessInfo.processInfo.systemUptime)
        )
        diagnosticLogger?.log(
            category: "voice",
            event: "GESTURE_CLASSIFIED",
            gestureID: sessionID,
            fields: [
                "result": result,
                "held_ms": Int(heldDuration * 1000),
                "policy": policy == .audioOnly ? "audio_only" : "momentary_trigger",
            ]
        )
        VoiceTimingLogger.observeControlPolicy(
            policy: policy == .audioOnly ? "audio_only" : "momentary_trigger",
            classification: result,
            triggerSource: usesHardwareOptionPath ? "hardware" : "synthetic",
            triggerKey: syntheticOptionTrigger.momentaryVoiceTriggerKey.rawValue
        )
    }

    private func logPhysicalGestureRelease(
        sessionID: UUID,
        policy: RemoteSegmentTriggerPolicy
    ) {
        if policy == .audioOnly {
            diagnosticLogger?.log(
                category: "voice",
                event: "PERSISTENT_SEGMENT_RELEASE",
                gestureID: sessionID,
                key: syntheticOptionTrigger.momentaryVoiceTriggerKey,
                fields: ["owner_key": persistentSessionTriggerOwnerKey?.rawValue ?? "none"]
            )
        } else {
            diagnosticLogger?.log(
                category: "voice",
                event: "MOMENTARY_RELEASE",
                gestureID: sessionID,
                key: syntheticOptionTrigger.momentaryVoiceTriggerKey,
                fields: ["tail_pending": tailWorkItem != nil]
            )
        }
    }

    private func logAdmissionDecision(
        sessionID: UUID,
        result: String,
        reason: String
    ) {
        diagnosticLogger?.log(
            category: "voice",
            event: "VOICE_PRESS_ADMISSION",
            gestureID: sessionID,
            fields: [
                "result": result,
                "reason": reason,
            ]
        )
        print(
            "[PRESS][\(String(sessionID.uuidString.prefix(4)))] "
                + "admission=\(result) reason=\(reason)"
        )
    }
}

// MARK: - F5 → Option hold filter (CGEvent tap)

final class VoiceKeyFilter {
    enum HeldHardwareOptionUpCaptureDecision: Equatable {
        case captured
        case suppressed
        case pass
    }

    enum PendingHardwareOptionRepressCaptureDecision: Equatable {
        case captured
        case suppressed
        case pass
    }

    enum FilterError: LocalizedError {
        case accessibilityDenied
        case tapCreationFailed
        var errorDescription: String? {
            switch self {
            case .accessibilityDenied:
                return "需要辅助功能权限"
            case .tapCreationFailed:
                return "无法创建 CGEvent tap（通常因辅助功能权限未授予）"
            }
        }
    }

    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var voiceKeyIsDown = false
    private let optionGate = HardwareOptionGate()
    private let syntheticOptionTrigger: VoiceOptionTrigger
    private let diagnosticLogger: VoiceDiagnosticLogger?
    private let emitEmergencyHardwareOptionUp: (VoiceTriggerKey) -> Void
    private let replayEventPoster: (CGEvent) -> Void
    private struct ReplayedHardwareOptionUpFingerprint: Hashable {
        let keyCode: CGKeyCode
        let eventTypeRawValue: UInt32
        let timestamp: CGEventTimestamp

        init(keyCode: CGKeyCode, eventType: CGEventType, timestamp: CGEventTimestamp) {
            self.keyCode = keyCode
            eventTypeRawValue = eventType.rawValue
            self.timestamp = timestamp
        }
    }
    private struct PendingReplayedHardwareOptionUp {
        let gestureID: UUID
        let key: VoiceTriggerKey
        var remainingComponents: Set<ReplayedHardwareOptionUpFingerprint>
    }
    private struct PendingHardwareOptionRepress {
        let gestureID: UUID
        let key: VoiceTriggerKey
        let serializedBehind: UUID
        var downEvents: [CGEvent]
        var capturedFlagsDown = false
        var capturedKeyDown = false
        var observedFlagsUp = false
        var observedKeyUp = false
        var cancelled = false

        var expectedReleaseCount: Int {
            let flags = capturedFlagsDown ? 1 : 0
            let key = capturedKeyDown ? 1 : 0
            return flags + key
        }

        var observedReleaseCount: Int {
            let flags = observedFlagsUp && capturedFlagsDown ? 1 : 0
            let key = observedKeyUp && capturedKeyDown ? 1 : 0
            return flags + key
        }
    }
    private struct PendingLongOnlySuppressionHandoff {
        let gestureID: UUID
        var releasedBeforeHandoff = false
    }
    private var pendingReplayedHardwareOptionUp: PendingReplayedHardwareOptionUp?
    private var pendingHardwareOptionRepress: PendingHardwareOptionRepress?
    private var pendingLongOnlySuppressionHandoff: PendingLongOnlySuppressionHandoff?
    private(set) var momentaryVoiceTriggerKey: VoiceTriggerKey = .leftOption
    /// Compatibility alias for callers that historically meant the mapped
    /// remote-microphone key.
    var voiceTriggerKey: VoiceTriggerKey { momentaryVoiceTriggerKey }
    private var deferredOptionDownSeen = false
    private var deferredOptionUpSeen = false
    private var deferredOptionDownEvents: [CGEvent] = []
    private var deferredOptionUpEvents: [CGEvent] = []
    private var longConfirmedOptionGestureID: UUID?
    private var heldHardwareOptionSessionID: UUID?
    private var heldHardwareOptionUpEvents: [CGEvent] = []
    private var heldHardwareOptionFlagsUpSeen = false
    private var heldHardwareOptionKeyUpSeen = false
    private var hardwareOptionReleaseArmed = false
    private var suppressedTriggerReleaseCompletionWorkItem: DispatchWorkItem?
    private var suppressedTriggerReleaseCompletionToken: UUID?
    private var voiceTriggerReconfigurationKeyCodes: Set<CGKeyCode>?
    var suppressedHardwareTriggerSessionID: UUID? {
        optionGate.suppressedSessionID
    }
    var hasShortTapDiscardOwnership: Bool {
        optionGate.shortTapDiscardSessionID != nil
    }
    var pendingReplayedHardwareOptionUpGestureID: UUID? {
        pendingReplayedHardwareOptionUp?.gestureID
    }
    var pendingHardwareOptionRepressGestureID: UUID? {
        pendingHardwareOptionRepress?.gestureID
    }
    var pendingHardwareOptionRepressDownCountForTesting: Int {
        pendingHardwareOptionRepress?.downEvents.count ?? 0
    }
    var pendingHardwareOptionRepressIsCancelledForTesting: Bool {
        pendingHardwareOptionRepress?.cancelled ?? false
    }
    var pendingLongOnlySuppressionHandoffGestureIDForTesting: UUID? {
        pendingLongOnlySuppressionHandoff?.gestureID
    }
    var onReplayedHardwareOptionUpPassAcknowledged: ((UUID) -> Void)?
    var onPendingHardwareOptionRepressDownCaptured: ((UUID) -> Void)?
    var hasActiveHardwareTriggerOwnership: Bool {
        optionGate.activeSessionID != nil
            || optionGate.suppressedSessionID != nil
            || heldHardwareOptionSessionID != nil
            || pendingReplayedHardwareOptionUp != nil
            || pendingHardwareOptionRepress != nil
            || pendingLongOnlySuppressionHandoff != nil
            || hardwareOptionReleaseArmed
            || !heldHardwareOptionUpEvents.isEmpty
            || voiceKeyIsDown
    }
    var hasSyntheticTriggerOwnership: Bool {
        syntheticOptionTrigger.activeSessionID != nil
            || syntheticOptionTrigger.isOptionDown
    }
    var isSyntheticTriggerDown: Bool {
        syntheticOptionTrigger.isOptionDown
    }
    var isVoiceKeyHeld: Bool {
        voiceKeyIsDown
    }
    var onVoiceKeyDown: (() -> Void)?
    var onVoiceKeyUp: (() -> Void)?
    var onSuppressedHardwareTriggerSafelyClosed: ((UUID) -> Void)?
    var onSuppressedHardwareTriggerInvalidated: ((UUID, String) -> Void)?
    var onLongOnlySuppressionHandoffReady: ((UUID) -> Void)?
    var onLongOnlySuppressionHandoffInvalidated: ((UUID, String) -> Void)?

    var diagnosticStateFields: [String: Any] {
        [
            "filter_active_gate": optionGate.activeSessionID?.uuidString ?? "none",
            "filter_suppressed_owner": optionGate.suppressedSessionID?.uuidString ?? "none",
            "held_hardware_owner": heldHardwareOptionSessionID?.uuidString ?? "none",
            "pending_hardware_repress_owner": pendingHardwareOptionRepress?.gestureID.uuidString ?? "none",
            "pending_hardware_repress_cancelled": pendingHardwareOptionRepress?.cancelled ?? false,
            "filter_configured_key": momentaryVoiceTriggerKey.rawValue,
            "synthetic_owner": syntheticOptionTrigger.activeSessionID?.uuidString ?? "none",
            "synthetic_down": syntheticOptionTrigger.isOptionDown,
        ]
    }

    init(
        syntheticOptionTrigger: VoiceOptionTrigger = .shared,
        diagnosticLogger: VoiceDiagnosticLogger? = nil,
        replayEventPoster: @escaping (CGEvent) -> Void = {
            $0.post(tap: .cghidEventTap)
        },
        emitEmergencyHardwareOptionUp: @escaping (VoiceTriggerKey) -> Void = {
            Key.voiceTriggerUp($0)
        }
    ) {
        self.syntheticOptionTrigger = syntheticOptionTrigger
        self.diagnosticLogger = diagnosticLogger
        self.replayEventPoster = replayEventPoster
        self.emitEmergencyHardwareOptionUp = emitEmergencyHardwareOptionUp
    }

    @discardableResult
    func configureVoiceTriggerKey(_ key: VoiceTriggerKey) -> Bool {
        guard !hasActiveHardwareTriggerOwnership else {
            return false
        }
        guard syntheticOptionTrigger.configureVoiceTriggerKey(key) else {
            return false
        }
        momentaryVoiceTriggerKey = key
        return true
    }

    @discardableResult
    func beginVoiceTriggerReconfiguration(
        from oldKey: VoiceTriggerKey,
        to newKey: VoiceTriggerKey
    ) -> Bool {
        guard voiceTriggerReconfigurationKeyCodes == nil,
              !hasActiveHardwareTriggerOwnership,
              !hasSyntheticTriggerOwnership else {
            return false
        }
        voiceTriggerReconfigurationKeyCodes = [
            VK.voiceKey,
            oldKey.cgKeyCode,
            newKey.cgKeyCode,
        ]
        return true
    }

    func endVoiceTriggerReconfiguration() {
        voiceTriggerReconfigurationKeyCodes = nil
    }

    func shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: CGKeyCode) -> Bool {
        voiceTriggerReconfigurationKeyCodes?.contains(keyCode) == true
    }

    func matchesTriggerKeyCode(_ keyCode: CGKeyCode) -> Bool {
        keyCode == momentaryVoiceTriggerKey.cgKeyCode
    }

    func isTriggerModifierActive(flags: CGEventFlags) -> Bool {
        flags.contains(momentaryVoiceTriggerKey.cgEventFlag)
    }

    private var optionDeferralActive: Bool {
        optionGate.activeSessionID != nil
    }

    /// Whether a specific voice gesture is currently holding the remapped
    /// Option edge. Focus preparation is advisory now, so callers must not
    /// release or replay an Option pair unless this returns true.
    func isOptionDeferralActive(for gestureID: UUID) -> Bool {
        optionGate.activeSessionID == gestureID
    }

    /// Record one deferred physical edge, keeping the capture decision in the
    /// same narrow seam used by the event tap and focused tests.
    @discardableResult
    func captureDeferredHardwareOptionEdge(
        _ edge: HardwareOptionEdge,
        copiedEvent: CGEvent?
    ) -> Bool {
        captureDeferredHardwareOptionEdge(
            edge,
            copied: copiedEvent != nil,
            copiedEvent: copiedEvent
        )
    }

    /// Models a successfully copied physical event in transaction tests
    /// without retaining or posting a CGEvent into the user's session.
    @discardableResult
    func captureDeferredHardwareOptionEdgeForTesting(
        _ edge: HardwareOptionEdge,
        copied: Bool
    ) -> Bool {
        captureDeferredHardwareOptionEdge(edge, copied: copied, copiedEvent: nil)
    }

    @discardableResult
    func captureHeldHardwareOptionUpEvent(
        _ event: CGEvent,
        type: CGEventType
    ) -> HeldHardwareOptionUpCaptureDecision {
        guard heldHardwareOptionSessionID != nil,
              hardwareOptionReleaseArmed,
              CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                == momentaryVoiceTriggerKey.cgKeyCode else {
            return .pass
        }

        switch type {
        case .flagsChanged:
            guard !isTriggerModifierActive(flags: event.flags),
                  !heldHardwareOptionFlagsUpSeen else {
                return .suppressed
            }
            heldHardwareOptionFlagsUpSeen = true
        case .keyUp:
            guard !heldHardwareOptionKeyUpSeen else { return .suppressed }
            heldHardwareOptionKeyUpSeen = true
        default:
            return .pass
        }

        if let copiedEvent = event.copy() {
            heldHardwareOptionUpEvents.append(copiedEvent)
        }
        return .captured
    }

    /// Arm the one pending-new-DOWN owner used while an older direct gesture
    /// still owns terminal hardware UP retirement. This intentionally does
    /// not touch `optionGate` or the old held-UP owner.
    @discardableResult
    func beginPendingHardwareOptionRepress(
        gestureID: UUID,
        serializedBehind oldGestureID: UUID
    ) -> PendingHardwareOptionRepressBeginResult {
        guard pendingHardwareOptionRepress == nil else {
            return .rejected
        }
        if let heldHardwareOptionSessionID,
           heldHardwareOptionSessionID != oldGestureID {
            return .rejected
        }
        if let replayGestureID = pendingReplayedHardwareOptionUp?.gestureID,
           replayGestureID != oldGestureID {
            return .rejected
        }
        let beginResult: PendingHardwareOptionRepressBeginResult =
            heldHardwareOptionSessionID != nil || pendingReplayedHardwareOptionUp != nil
            ? .armedAwaitingOldUpAcknowledgement
            : .armedWithoutOldUpOwner
        pendingHardwareOptionRepress = PendingHardwareOptionRepress(
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            serializedBehind: oldGestureID,
            downEvents: []
        )
        diagnosticLogger?.log(
            category: "filter",
            event: "PENDING_HARDWARE_REPRESS_BEGIN",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: [
                "old_owner": heldHardwareOptionSessionID?.uuidString
                    ?? pendingReplayedHardwareOptionUp?.gestureID.uuidString
                    ?? "none",
                "serialized_behind": oldGestureID.uuidString,
                "awaiting_old_up_ack": beginResult.awaitsOldUpAcknowledgement,
            ]
        )
        return beginResult
    }

    /// Capture mapped trigger components belonging to the pending new press.
    /// Replayed old UP components are checked before this method by the event
    /// tap, so they cannot be consumed by the new owner.
    @discardableResult
    func capturePendingHardwareOptionRepressEvent(
        _ event: CGEvent,
        type: CGEventType
    ) -> PendingHardwareOptionRepressCaptureDecision {
        guard var pending = pendingHardwareOptionRepress,
              CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                == pending.key.cgKeyCode else {
            return .pass
        }

        if pending.cancelled {
            switch type {
            case .flagsChanged:
                if isTriggerModifierActive(flags: event.flags) {
                    return .suppressed
                }
                pending.observedFlagsUp = true
            case .keyDown:
                return .suppressed
            case .keyUp:
                pending.observedKeyUp = true
            default:
                return .pass
            }
            let shouldClear = pending.expectedReleaseCount == 0
                ? pending.observedFlagsUp || pending.observedKeyUp
                : pending.observedReleaseCount >= pending.expectedReleaseCount
            if shouldClear {
                pendingHardwareOptionRepress = nil
            } else {
                pendingHardwareOptionRepress = pending
            }
            return .suppressed
        }

        switch type {
        case .flagsChanged:
            if isTriggerModifierActive(flags: event.flags) {
                guard !pending.capturedFlagsDown else { return .suppressed }
                pending.capturedFlagsDown = true
                if let copied = event.copy() {
                    pending.downEvents.append(copied)
                }
                pendingHardwareOptionRepress = pending
                onPendingHardwareOptionRepressDownCaptured?(pending.gestureID)
                return .captured
            }
            // The old held-UP owner remains responsible for release
            // components. A pending new owner captures DOWN only, so an old
            // UP cannot be mistaken for the new gesture's early release.
            return .pass
        case .keyDown:
            guard !pending.capturedKeyDown else { return .suppressed }
            pending.capturedKeyDown = true
            if let copied = event.copy() {
                pending.downEvents.append(copied)
            }
            pendingHardwareOptionRepress = pending
            onPendingHardwareOptionRepressDownCaptured?(pending.gestureID)
            return .captured
        case .keyUp:
            // Let the old held-UP owner retain release ownership. If raw HID
            // UP has already cancelled this pending gesture, the tombstone
            // branch above consumes the later mapped release.
            return .pass
        default:
            return .suppressed
        }
    }

    /// Cancel the pending coordinator owner without replaying its captured
    /// DOWN. Keep a tombstone until the expected mapped UP components have
    /// been consumed, preventing an unmatched UP from reaching the receiver.
    func cancelPendingHardwareOptionRepress(gestureID: UUID, reason: String) {
        guard var pending = pendingHardwareOptionRepress,
              pending.gestureID == gestureID else { return }
        pending.cancelled = true
        pending.downEvents.removeAll(keepingCapacity: true)
        pendingHardwareOptionRepress = pending
        diagnosticLogger?.log(
            category: "filter",
            event: "PENDING_HARDWARE_REPRESS_CANCEL",
            gestureID: gestureID,
            key: pending.key,
            fields: ["reason": reason]
        )
    }

    /// Promote the captured new DOWN after old hardware UP acknowledgement.
    /// The posted copies re-enter the canonical event-tap boundary in their
    /// original order; no synthetic trigger edge is generated.
    @discardableResult
    func promotePendingHardwareOptionRepress(gestureID: UUID) -> Bool {
        guard let pending = pendingHardwareOptionRepress,
              pending.gestureID == gestureID,
              !pending.cancelled,
              !pending.downEvents.isEmpty,
              optionGate.activeSessionID == nil,
              optionGate.suppressedSessionID == nil,
              heldHardwareOptionSessionID == nil,
              pendingReplayedHardwareOptionUp == nil else {
            return false
        }

        // Promotion is the same physical replay boundary as a normal long
        // hardware press. Re-establish the gate long enough to resolve the
        // copied DOWN as hardware replay, then retain the promoted gesture as
        // the held UP/output-drain owner before posting B's DOWN.
        guard optionGate.begin(sessionID: gestureID) else { return false }
        _ = syntheticOptionTrigger.begin(sessionID: gestureID)
        guard optionGate.capture(.down, copied: true),
              optionGate.resolve(sessionID: gestureID) == .hardwareReplay else {
            _ = syntheticOptionTrigger.abort(sessionID: gestureID)
            return false
        }

        pendingHardwareOptionRepress = nil
        _ = syntheticOptionTrigger.abort(sessionID: gestureID)
        heldHardwareOptionSessionID = gestureID
        heldHardwareOptionUpEvents.removeAll(keepingCapacity: true)
        heldHardwareOptionFlagsUpSeen = false
        heldHardwareOptionKeyUpSeen = false
        hardwareOptionReleaseArmed = false
        pending.downEvents.forEach(replayEventPoster)
        diagnosticLogger?.log(
            category: "filter",
            event: "PENDING_HARDWARE_REPRESS_PROMOTE",
            gestureID: gestureID,
            key: pending.key,
            fields: [
                "captured_down_count": pending.downEvents.count,
                "held_up_owner": gestureID.uuidString,
            ]
        )
        return true
    }

    /// A copied hardware UP is acknowledged only at the event-tap pass
    /// decision. The pending record keeps this gesture's trigger owned until
    /// every expected event fingerprint has re-entered the filter.
    @discardableResult
    func acknowledgeReplayedHardwareOptionUpIfExpected(
        _ event: CGEvent,
        type: CGEventType
    ) -> Bool {
        guard var pending = pendingReplayedHardwareOptionUp,
              pending.key == momentaryVoiceTriggerKey else {
            return false
        }
        let fingerprint = ReplayedHardwareOptionUpFingerprint(
            keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
            eventType: type,
            timestamp: event.timestamp
        )
        guard pending.remainingComponents.remove(fingerprint) != nil else {
            return false
        }

        let gestureID = pending.gestureID
        let key = pending.key
        let allComponentsPassed = pending.remainingComponents.isEmpty
        if allComponentsPassed {
            pendingReplayedHardwareOptionUp = nil
        } else {
            pendingReplayedHardwareOptionUp = pending
        }
        logMappedTriggerEvent(
            keyCode: fingerprint.keyCode,
            eventType: type,
            flags: event.flags,
            eventTimestamp: event.timestamp,
            syntheticMarker: false,
            action: "replay_up_pass_ack"
        )
        diagnosticLogger?.log(
            category: "filter",
            event: "REPLAY_UP_PASS_ACK",
            gestureID: gestureID,
            key: key,
            fields: [
                "key_code": Int(fingerprint.keyCode),
                "event_type": Int(fingerprint.eventTypeRawValue),
                "cg_event_timestamp_raw": UInt64(fingerprint.timestamp),
                "components_remaining": pending.remainingComponents.count,
            ]
        )
        if allComponentsPassed {
            onReplayedHardwareOptionUpPassAcknowledged?(gestureID)
        }
        return true
    }

    @discardableResult
    private func captureDeferredHardwareOptionEdge(
        _ edge: HardwareOptionEdge,
        copied: Bool,
        copiedEvent: CGEvent?
    ) -> Bool {
        guard optionGate.activeSessionID != nil else { return false }
        if edge == .up, !deferredOptionDownSeen { return false }
        guard optionGate.capture(edge, copied: copied) else {
            return false
        }

        switch edge {
        case .down:
            deferredOptionDownSeen = true
            if let copiedEvent {
                deferredOptionDownEvents.append(copiedEvent)
            }
        case .up:
            deferredOptionUpSeen = true
            if let copiedEvent {
                deferredOptionUpEvents.append(copiedEvent)
            }
        }
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_CAPTURE",
            gestureID: optionGate.activeSessionID,
            key: momentaryVoiceTriggerKey,
            fields: ["edge": edge == .down ? "down" : "up"]
        )
        if edge == .down,
           longConfirmedOptionGestureID == optionGate.activeSessionID,
           let gestureID = optionGate.activeSessionID {
            releaseDeferredOption(
                gestureID: gestureID,
                reason: "long-confirmed-late-mapped-down"
            )
        }
        return true
    }

    func recordMappedTriggerEventForTesting(
        keyCode: CGKeyCode,
        eventType: CGEventType,
        flags: CGEventFlags,
        eventTimestamp: CGEventTimestamp? = nil,
        syntheticMarker: Bool,
        action: String
    ) {
        logMappedTriggerEvent(
            keyCode: keyCode,
            eventType: eventType,
            flags: flags,
            eventTimestamp: eventTimestamp,
            syntheticMarker: syntheticMarker,
            action: action
        )
    }

    private func logMappedTriggerEvent(
        keyCode: CGKeyCode,
        eventType: CGEventType,
        flags: CGEventFlags,
        eventTimestamp: CGEventTimestamp? = nil,
        syntheticMarker: Bool,
        action: String
    ) {
        guard let observed = VoiceTriggerKey.allCases.first(where: { $0.cgKeyCode == keyCode }) else {
            return
        }
        let owner = optionGate.activeSessionID
            ?? optionGate.suppressedSessionID
            ?? heldHardwareOptionSessionID
        let eventName: String
        switch eventType {
        case .keyDown: eventName = "key_down"
        case .keyUp: eventName = "key_up"
        case .flagsChanged: eventName = "flags_changed"
        default: eventName = "other_\(eventType.rawValue)"
        }
        var fields: [String: Any] = [
            "key_code": Int(keyCode),
            "event_type": eventName,
            "flags": UInt64(flags.rawValue),
            "synthetic_marker": syntheticMarker,
            "filter_configured_key": momentaryVoiceTriggerKey.rawValue,
            "gate_state": optionGate.activeSessionID != nil ? "deferring"
                : optionGate.suppressedSessionID != nil ? "suppressed"
                : heldHardwareOptionSessionID != nil ? "holding_release" : "none",
            "action": action,
            "observer_uptime": ProcessInfo.processInfo.systemUptime,
        ]
        if let eventTimestamp {
            fields["cg_event_timestamp_raw"] = UInt64(eventTimestamp)
            fields["cg_event_timestamp_clock"] = "quartz_event_timestamp_raw"
        }
        diagnosticLogger?.log(
            category: "filter",
            event: "MAPPED_TRIGGER_EVENT",
            gestureID: owner,
            key: observed,
            fields: fields
        )
        if !syntheticMarker, observed != momentaryVoiceTriggerKey {
            diagnosticLogger?.log(
                category: "filter",
                event: "MAPPED_TRIGGER_MISMATCH",
                gestureID: owner,
                key: observed,
                fields: [
                    "observed": observed.rawValue,
                    "configured": momentaryVoiceTriggerKey.rawValue,
                    "event_type": eventName,
                    "action": action,
                ]
            )
        }
    }

    /// Discard a captured mapped down and transfer its later release to a
    /// bounded, gesture-scoped suppression owner. Unlike cancellation, this
    /// deliberately remains active after the deferral gate is closed.
    @discardableResult
    func suppressDeferredHardwareTrigger(
        gestureID: UUID,
        reason: String
    ) -> Bool {
        cancelSuppressedTriggerReleaseCompletion()
        let transferredShortTapDiscard =
            optionGate.transferShortTapDiscardToAudioOnlySuppression(sessionID: gestureID)
        guard transferredShortTapDiscard || optionGate.suppress(sessionID: gestureID) else {
            return false
        }
        _ = syntheticOptionTrigger.abort(sessionID: gestureID)
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
        deferredOptionDownEvents.removeAll(keepingCapacity: true)
        deferredOptionUpEvents.removeAll(keepingCapacity: true)
        print(
            "[VOICE] mapped trigger suppressed gesture=\(gestureID.uuidString) "
                + "reason=\(reason)"
        )
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_SUPPRESS",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason]
        )
        return true
    }

    /// Reserve the one bounded B handoff slot while A's SHORT tombstone still
    /// owns ambiguous mapped Option components. B remains private and emits
    /// no trigger until the filter transfers suppression atomically.
    @discardableResult
    func beginLongOnlySuppressionHandoff(gestureID: UUID) -> Bool {
        guard optionGate.shortTapDiscardSessionID != nil else {
            return false
        }
        if let pending = pendingLongOnlySuppressionHandoff,
           !pending.releasedBeforeHandoff {
            return false
        }
        pendingLongOnlySuppressionHandoff = PendingLongOnlySuppressionHandoff(
            gestureID: gestureID
        )
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_LONG_ONLY_HANDOFF_BEGIN",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey
        )
        return true
    }

    /// B released before A's tombstone retired. Keep the handoff reservation
    /// so late B physical components receive bounded suppression after A
    /// closes, but never emit a synthetic trigger for B.
    @discardableResult
    func releaseLongOnlySuppressionHandoff(gestureID: UUID) -> Bool {
        if var pending = pendingLongOnlySuppressionHandoff,
           pending.gestureID == gestureID {
            pending.releasedBeforeHandoff = true
            pendingLongOnlySuppressionHandoff = pending
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_LONG_ONLY_HANDOFF_RELEASED",
                gestureID: gestureID,
                key: momentaryVoiceTriggerKey,
                fields: ["before_handoff": true]
            )
            return true
        }
        guard optionGate.suppressedSessionID == gestureID,
              optionGate.shortTapDiscardSessionID == nil else {
            return false
        }
        return retireLongOnlySuppressionOwner(
            gestureID: gestureID,
            reason: "candidate-released-after-handoff"
        )
    }

    private func retireLongOnlySuppressionOwner(
        gestureID: UUID,
        reason: String
    ) -> Bool {
        guard optionGate.suppressedSessionID == gestureID,
              optionGate.shortTapDiscardSessionID == nil else {
            return false
        }
        cancelSuppressedTriggerReleaseCompletion()
        _ = optionGate.armSuppressedRelease(sessionID: gestureID)
        guard optionGate.markSuppressedOutputDrainCompleted(sessionID: gestureID) else {
            return false
        }
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_LONG_ONLY_HANDOFF_DISCARD",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason]
        )
        scheduleSuppressedTriggerReleaseCompletion(sessionID: gestureID)
        return true
    }

    /// Testable event-tap seam: consume every configured-trigger edge while a
    /// discarded down still owns the lifecycle.
    @discardableResult
    func shouldSuppressDiscardedHardwareTriggerEvent(
        keyCode: CGKeyCode,
        type: CGEventType,
        eventFlags: CGEventFlags? = nil
    ) -> Bool {
        guard matchesTriggerKeyCode(keyCode),
              let owner = optionGate.suppressedSessionID else {
            return false
        }
        if optionGate.isShortTapDiscardSession(sessionID: owner) {
            switch type {
            case .keyDown, .keyUp, .flagsChanged:
                _ = optionGate.observeSuppressedReleaseEdge(sessionID: owner)
                scheduleSuppressedTriggerReleaseCompletion(sessionID: owner)
                return true
            default:
                return false
            }
        }
        switch type {
        case .keyDown:
            return true
        case .keyUp:
            _ = optionGate.observeSuppressedReleaseEdge(sessionID: owner)
            scheduleSuppressedTriggerReleaseCompletion(sessionID: owner)
            return true
        case .flagsChanged:
            if let eventFlags, !isTriggerModifierActive(flags: eventFlags) {
                _ = optionGate.observeSuppressedReleaseEdge(sessionID: owner)
                scheduleSuppressedTriggerReleaseCompletion(sessionID: owner)
            }
            return true
        default:
            return false
        }
    }

    @discardableResult
    func armSuppressedHardwareTriggerRelease(gestureID: UUID) -> Bool {
        guard optionGate.armSuppressedRelease(sessionID: gestureID) else { return false }
        scheduleSuppressedTriggerReleaseCompletion(sessionID: gestureID)
        return true
    }

    /// Mark output drain complete. Suppression remains active until the raw
    /// release and a quiet window after the last mapped release component.
    @discardableResult
    func completeSuppressedHardwareTrigger(
        gestureID: UUID,
        reason: String
    ) -> Bool {
        guard optionGate.markSuppressedOutputDrainCompleted(sessionID: gestureID) else {
            return false
        }
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_OUTPUT_DRAINED",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason, "gate_state": "suppressed"]
        )
        _ = completeSuppressedHardwareTriggerIfSafe(gestureID: gestureID, reason: reason)
        return true
    }

    private func completeSuppressedHardwareTriggerIfSafe(
        gestureID: UUID,
        reason: String
    ) -> Bool {
        if let pending = pendingLongOnlySuppressionHandoff,
           optionGate.isShortTapDiscardSession(sessionID: gestureID),
           optionGate.transferShortTapDiscardToAudioOnlySuppression(
               sessionID: pending.gestureID
           ) {
            pendingLongOnlySuppressionHandoff = nil
            cancelSuppressedTriggerReleaseCompletion()
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_LONG_ONLY_HANDOFF_READY",
                gestureID: pending.gestureID,
                key: momentaryVoiceTriggerKey,
                fields: ["previous_owner": gestureID.uuidString]
            )
            if pending.releasedBeforeHandoff {
                _ = retireLongOnlySuppressionOwner(
                    gestureID: pending.gestureID,
                    reason: "released-before-handoff"
                )
            } else {
                onLongOnlySuppressionHandoffReady?(pending.gestureID)
            }
            return true
        }
        guard optionGate.completeSuppressed(sessionID: gestureID) else { return false }
        cancelSuppressedTriggerReleaseCompletion()
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_CLOSED",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason, "gate_state": "suppressed"]
        )
        print(
            "[VOICE] mapped trigger suppression completed "
                + "gesture=\(gestureID.uuidString) reason=\(reason)"
        )
        onSuppressedHardwareTriggerSafelyClosed?(gestureID)
        return true
    }

    /// Explicit reset/supersede cleanup for suppressed ownership. No modifier
    /// event is emitted because the physical down was discarded.
    @discardableResult
    func resetSuppressedHardwareTrigger(
        gestureID: UUID? = nil,
        reason: String
    ) -> Bool {
        guard let owner = optionGate.suppressedSessionID,
              gestureID == nil || gestureID == owner,
              optionGate.resetSuppressed(sessionID: owner) else {
            return false
        }
        let invalidatedHandoff = pendingLongOnlySuppressionHandoff
        pendingLongOnlySuppressionHandoff = nil
        cancelSuppressedTriggerReleaseCompletion()
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_CLOSED",
            gestureID: owner,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason, "gate_state": "suppressed_reset"]
        )
        print(
            "[VOICE] mapped trigger suppression reset "
                + "gesture=\(owner.uuidString) reason=\(reason)"
        )
        onSuppressedHardwareTriggerInvalidated?(owner, reason)
        if let invalidatedHandoff {
            onLongOnlySuppressionHandoffInvalidated?(
                invalidatedHandoff.gestureID,
                reason
            )
        }
        return true
    }

    private func scheduleSuppressedTriggerReleaseCompletion(sessionID: UUID) {
        suppressedTriggerReleaseCompletionWorkItem?.cancel()
        let token = UUID()
        suppressedTriggerReleaseCompletionToken = token
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.suppressedTriggerReleaseCompletionToken == token else {
                return
            }
            self.suppressedTriggerReleaseCompletionWorkItem = nil
            self.suppressedTriggerReleaseCompletionToken = nil
            _ = self.completeSuppressedHardwareTriggerQuietPeriod(gestureID: sessionID)
        }
        suppressedTriggerReleaseCompletionWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + VoicePressCoordinator.tailDrainDelay,
            execute: work
        )
    }

    @discardableResult
    func completeSuppressedHardwareTriggerQuietPeriod(gestureID: UUID) -> Bool {
        guard optionGate.markSuppressedReleaseQuietPeriodElapsed(sessionID: gestureID) else {
            return false
        }
        return completeSuppressedHardwareTriggerIfSafe(
            gestureID: gestureID,
            reason: "mapped-release-quiet-window"
        )
    }

    private func cancelSuppressedTriggerReleaseCompletion() {
        suppressedTriggerReleaseCompletionWorkItem?.cancel()
        suppressedTriggerReleaseCompletionWorkItem = nil
        suppressedTriggerReleaseCompletionToken = nil
    }

    /// Emit the persistent-session semantic tap while taking ownership of all
    /// physical mapped edges for a bounded quiet window. The physical gate is
    /// discarded even when no mapped edge arrived before raw HID-up.
    @discardableResult
    func emitPersistentShortTap(
        gestureID: UUID,
        reason: String,
        triggerKey: VoiceTriggerKey,
        purpose: String = "persistent_toggle"
    ) -> PersistentShortTapDispatchResult {
        if let waitingOn = optionGate.audioOnlySuppressionOwnerID {
            return .deferred(waitingOn: waitingOn)
        }
        guard optionGate.beginShortTapDiscard(sessionID: gestureID) else {
            _ = syntheticOptionTrigger.abort(sessionID: gestureID)
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_STALE_EVENT",
                gestureID: gestureID,
                fields: [
                    "owner": optionGate.suppressedSessionID?.uuidString
                        ?? optionGate.activeSessionID?.uuidString ?? "none",
                    "incoming": gestureID.uuidString,
                ]
            )
            return .failed
        }
        cancelSuppressedTriggerReleaseCompletion()
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
        deferredOptionDownEvents.removeAll(keepingCapacity: true)
        deferredOptionUpEvents.removeAll(keepingCapacity: true)
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_SHORT_DISCARD",
            gestureID: gestureID,
            key: triggerKey,
            fields: ["reason": reason]
        )
        scheduleSuppressedTriggerReleaseCompletion(sessionID: gestureID)
        let emitted = syntheticOptionTrigger.sendTap(
            sessionID: gestureID,
            key: triggerKey,
            purpose: purpose
        )
        print(
            "[VOICE] persistent short trigger \(emitted ? "emitted" : "failed") "
                + "gesture=\(gestureID.uuidString) reason=\(reason)"
        )
        return emitted ? .emitted : .failed
    }

    @discardableResult
    func emitDeferredPersistentShortTap(
        gestureID: UUID,
        triggerKey: VoiceTriggerKey,
        purpose: String
    ) -> Bool {
        guard optionGate.activeSessionID == nil,
              optionGate.suppressedSessionID == nil,
              syntheticOptionTrigger.activeSessionID == gestureID,
              !syntheticOptionTrigger.isOptionDown else {
            return false
        }
        return syntheticOptionTrigger.sendTap(
            sessionID: gestureID,
            key: triggerKey,
            purpose: purpose
        )
    }

    /// HIDMonitor 活跃时跳过语音键处理（防止双重触发）。
    var skipVoiceKey = false

    /// Temporarily hold only the Option events generated by the Xiaomi
    /// voice-key remap. The event tap returns immediately; FloatTabs focus is
    /// repaired in parallel and the captured modifier state is normalized
    /// into a fresh Option event pair when ready.
    /// This prevents the first Option edge from beating a stale WebKit text
    /// client without blocking the event-tap thread.
    @discardableResult
    func beginOptionDeferral(gestureID: UUID) -> Bool {
        beginOptionDeferral(
            gestureID: gestureID,
            preservingShortDiscard: false
        )
    }

    @discardableResult
    func beginLongOnlyOptionDeferral(gestureID: UUID) -> Bool {
        beginOptionDeferral(
            gestureID: gestureID,
            preservingShortDiscard: true
        )
    }

    @discardableResult
    private func beginOptionDeferral(
        gestureID: UUID,
        preservingShortDiscard: Bool
    ) -> Bool {
        if let pendingGestureID = pendingReplayedHardwareOptionUpGestureID,
           pendingGestureID != gestureID {
            invalidatePendingReplayedHardwareOptionUp(
                gestureID: pendingGestureID,
                reason: "superseded"
            )
        }
        if !preservingShortDiscard,
           let shortTapOwner = optionGate.shortTapDiscardSessionID {
            _ = resetSuppressedHardwareTrigger(
                gestureID: shortTapOwner,
                reason: "new-voice-gesture"
            )
        }
        if let owner = optionGate.suppressedSessionID {
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_STALE_EVENT",
                gestureID: owner,
                fields: ["owner": owner.uuidString, "incoming": gestureID.uuidString]
            )
            return false
        }
        if let heldSessionID = heldHardwareOptionSessionID,
           heldSessionID != gestureID {
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_STALE_EVENT",
                gestureID: heldSessionID,
                fields: ["owner": heldSessionID.uuidString, "incoming": gestureID.uuidString]
            )
            abortHeldHardwareOption(
                gestureID: heldSessionID,
                reason: "superseded"
            )
        }
        if let activeGestureID = optionGate.activeSessionID,
           activeGestureID != gestureID {
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_STALE_EVENT",
                gestureID: activeGestureID,
                fields: ["owner": activeGestureID.uuidString, "incoming": gestureID.uuidString]
            )
            cancelDeferredOption(
                gestureID: activeGestureID,
                reason: "superseded"
            )
        }
        guard optionGate.begin(sessionID: gestureID) else {
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_STALE_EVENT",
                gestureID: optionGate.activeSessionID,
                fields: [
                    "owner": optionGate.activeSessionID?.uuidString ?? "none",
                    "incoming": gestureID.uuidString,
                ]
            )
            return false
        }
        _ = syntheticOptionTrigger.begin(sessionID: gestureID)
        longConfirmedOptionGestureID = nil
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
        deferredOptionDownEvents.removeAll(keepingCapacity: true)
        deferredOptionUpEvents.removeAll(keepingCapacity: true)
        print("[VOICE] option gate armed gesture=\(gestureID.uuidString)")
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_BEGIN",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey
        )
        return true
    }

    /// Confirm a long press independently from mapped Option-down arrival.
    /// A late mapped down remains inside the active gate and is released from
    /// the same capture seam when it arrives.
    @discardableResult
    func confirmLongOption(gestureID: UUID) -> Bool {
        guard optionGate.activeSessionID == gestureID else { return false }
        longConfirmedOptionGestureID = gestureID
        if deferredOptionDownSeen {
            releaseDeferredOption(
                gestureID: gestureID,
                reason: "long-confirmed-mapped-down-ready"
            )
        }
        return true
    }

    /// Transfer a short or otherwise unpromoted candidate into the existing
    /// bounded trigger-discard owner. This deliberately does not cancel the
    /// gate: late hidutil Option edges must still be consumed safely.
    @discardableResult
    func discardDeferredHardwareTrigger(
        gestureID: UUID,
        reason: String
    ) -> Bool {
        cancelSuppressedTriggerReleaseCompletion()
        guard optionGate.beginShortTapDiscard(sessionID: gestureID) else {
            return false
        }
        _ = syntheticOptionTrigger.abort(sessionID: gestureID)
        longConfirmedOptionGestureID = nil
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
        deferredOptionDownEvents.removeAll(keepingCapacity: true)
        deferredOptionUpEvents.removeAll(keepingCapacity: true)
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_SHORT_DISCARD",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason]
        )
        scheduleSuppressedTriggerReleaseCompletion(sessionID: gestureID)
        return true
    }

    /// Drop any older physical gate before a new gesture selects its Option
    /// source. This also covers a new synthetic-fallback gesture, which does
    /// not arm a replacement physical gate of its own.
    func cancelActiveOptionDeferral(reason: String) {
        if let gestureID = optionGate.activeSessionID {
            cancelDeferredOption(gestureID: gestureID, reason: reason)
        } else if let gestureID = heldHardwareOptionSessionID {
            abortHeldHardwareOption(gestureID: gestureID, reason: reason)
        } else if let gestureID = optionGate.suppressedSessionID,
                  optionGate.shortTapDiscardSessionID == nil {
            _ = resetSuppressedHardwareTrigger(
                gestureID: gestureID,
                reason: reason
            )
        } else if let gestureID = pendingReplayedHardwareOptionUpGestureID {
            invalidatePendingReplayedHardwareOptionUp(
                gestureID: gestureID,
                reason: reason
            )
        } else if let gestureID = pendingHardwareOptionRepressGestureID {
            cancelPendingHardwareOptionRepress(
                gestureID: gestureID,
                reason: reason
            )
        }
    }

    /// Release a deferred physical Option pair. The gesture identifier makes
    /// this idempotent and prevents a late acknowledgement from releasing a
    /// newer gesture's Option edge.
    func releaseDeferredOption(gestureID: UUID, reason: String) {
        guard optionGate.activeSessionID == gestureID else {
            print(
                "[VOICE] ignored stale option release gesture=\(gestureID.uuidString) "
                    + "active=\(optionGate.activeSessionID?.uuidString ?? "none")"
            )
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_STALE_EVENT",
                gestureID: gestureID,
                fields: [
                    "owner": optionGate.activeSessionID?.uuidString ?? "none",
                    "incoming": gestureID.uuidString,
                ]
            )
            return
        }

        let optionDownSeen = deferredOptionDownSeen
        let optionUpSeen = deferredOptionUpSeen
        let optionDownEvents = deferredOptionDownEvents
        let optionUpEvents = deferredOptionUpEvents
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
        longConfirmedOptionGestureID = nil
        deferredOptionDownEvents.removeAll(keepingCapacity: true)
        deferredOptionUpEvents.removeAll(keepingCapacity: true)
        guard let resolution = optionGate.resolve(sessionID: gestureID) else {
            return
        }

        switch resolution {
        case .hardwareReplay:
            // Replay the original physical events without the synthetic
            // marker. If only the down edge arrived before release, the later
            // physical up event is allowed through once the gate is cleared.
            _ = syntheticOptionTrigger.abort(sessionID: gestureID)
            optionDownEvents.forEach { $0.post(tap: .cghidEventTap) }
            if optionUpSeen {
                optionUpEvents.forEach { $0.post(tap: .cghidEventTap) }
            } else if optionDownSeen {
                // A long remote hold has a captured Option-down but its
                // matching up arrives with the raw HID voice-key release.
                // Hold that one session's mapped up until output drains.
                heldHardwareOptionSessionID = gestureID
                heldHardwareOptionUpEvents.removeAll(keepingCapacity: true)
                heldHardwareOptionFlagsUpSeen = false
                heldHardwareOptionKeyUpSeen = false
                hardwareOptionReleaseArmed = false
            }
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_REPLAY",
                gestureID: gestureID,
                key: momentaryVoiceTriggerKey,
                fields: ["option_down_seen": optionDownSeen, "option_up_seen": optionUpSeen]
            )
        case .syntheticTap:
            _ = syntheticOptionTrigger.sendTap(sessionID: gestureID)
        case .syntheticDown:
            _ = syntheticOptionTrigger.sendDown(sessionID: gestureID)
        case .noOptionEdge:
            _ = syntheticOptionTrigger.abort(sessionID: gestureID)
        }
        print(
            "[VOICE] option gate released gesture=\(gestureID.uuidString) reason=\(reason) "
                + "optionDown=\(optionDownSeen) optionUp=\(optionUpSeen) "
                + "resolution=\(String(describing: resolution))"
        )
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_CLOSED",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason, "resolution": String(describing: resolution)]
        )
    }

    /// Called after the raw HID microphone-up was accepted for this gesture.
    func armHardwareOptionRelease(gestureID: UUID) {
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_PHYSICAL_UP",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey
        )
        _ = armSuppressedHardwareTriggerRelease(gestureID: gestureID)
        if optionGate.activeSessionID == gestureID {
            _ = discardDeferredHardwareTrigger(
                gestureID: gestureID,
                reason: "physical-up-before-mapped-down"
            )
            return
        }
        guard heldHardwareOptionSessionID == gestureID else { return }
        hardwareOptionReleaseArmed = true
        print("[VOICE] hardware Option-up armed gesture=\(gestureID.uuidString)")
    }

    /// Release the captured hardware Option-up after remote output drains.
    /// If macOS did not deliver a matching up, use the existing synthetic
    /// helper only as an emergency balancing edge.
    func releaseHeldHardwareOption(gestureID: UUID, reason: String) {
        if completeSuppressedHardwareTrigger(
            gestureID: gestureID,
            reason: reason
        ) {
            return
        }
        guard heldHardwareOptionSessionID == gestureID else {
            print(
                "[VOICE] ignored stale hardware Option-up release gesture="
                    + "\(gestureID.uuidString) active="
                    + "\(heldHardwareOptionSessionID?.uuidString ?? "none")"
            )
            diagnosticLogger?.log(
                category: "filter",
                event: "OPTION_GATE_STALE_EVENT",
                gestureID: gestureID,
                fields: [
                    "owner": heldHardwareOptionSessionID?.uuidString ?? "none",
                    "incoming": gestureID.uuidString,
                ]
            )
            return
        }
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_OUTPUT_DRAINED",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason]
        )
        let events = heldHardwareOptionUpEvents
        if !events.isEmpty {
            let fingerprints = Set(events.map { event in
                ReplayedHardwareOptionUpFingerprint(
                    keyCode: CGKeyCode(
                        event.getIntegerValueField(.keyboardEventKeycode)
                    ),
                    eventType: event.type,
                    timestamp: event.timestamp
                )
            })
            pendingReplayedHardwareOptionUp = PendingReplayedHardwareOptionUp(
                gestureID: gestureID,
                key: momentaryVoiceTriggerKey,
                remainingComponents: fingerprints
            )
            diagnosticLogger?.log(
                category: "filter",
                event: "REPLAY_UP_PENDING",
                gestureID: gestureID,
                key: momentaryVoiceTriggerKey,
                fields: ["component_count": fingerprints.count]
            )
        }
        clearHeldHardwareOption()
        if events.isEmpty {
            emitEmergencyHardwareOptionUp(momentaryVoiceTriggerKey)
            print("[VOICE] hardware Option-up missing; emergency balancing up")
        } else {
            events.forEach(replayEventPoster)
            diagnosticLogger?.log(
                category: "filter",
                event: "REPLAY_UP_POSTED",
                gestureID: gestureID,
                key: momentaryVoiceTriggerKey,
                fields: ["component_count": events.count]
            )
        }
        VoiceTimingLogger.mark("OPTION_UP_EMITTED", sessionID: gestureID)
        print(
            "[VOICE] hardware Option-up released gesture=\(gestureID.uuidString) "
                + "reason=\(reason)"
        )
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_CLOSED",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason, "gate_state": "held_release"]
        )
    }

    private func abortHeldHardwareOption(gestureID: UUID, reason: String) {
        guard heldHardwareOptionSessionID == gestureID else { return }
        let events = heldHardwareOptionUpEvents
        clearHeldHardwareOption()
        if events.isEmpty {
            emitEmergencyHardwareOptionUp(momentaryVoiceTriggerKey)
        } else {
            events.forEach { $0.post(tap: .cghidEventTap) }
        }
        VoiceTimingLogger.mark("OPTION_UP_EMITTED", sessionID: gestureID)
        print(
            "[VOICE] hardware Option-up emergency release gesture="
                + "\(gestureID.uuidString) reason=\(reason)"
        )
    }

    private func clearHeldHardwareOption() {
        heldHardwareOptionSessionID = nil
        heldHardwareOptionUpEvents.removeAll(keepingCapacity: true)
        heldHardwareOptionFlagsUpSeen = false
        heldHardwareOptionKeyUpSeen = false
        hardwareOptionReleaseArmed = false
    }

    private func invalidatePendingReplayedHardwareOptionUp(
        gestureID: UUID,
        reason: String
    ) {
        guard pendingReplayedHardwareOptionUp?.gestureID == gestureID else { return }
        let key = pendingReplayedHardwareOptionUp?.key
        pendingReplayedHardwareOptionUp = nil
        diagnosticLogger?.log(
            category: "filter",
            event: "REPLAY_UP_INVALIDATED",
            gestureID: gestureID,
            key: key,
            fields: ["reason": reason]
        )
    }

    /// Drops a fully captured gesture without replaying it. This is used only
    /// when a newer physical press supersedes a completed request; the stale
    /// request must never turn into a delayed Option tap in the new target.
    func cancelDeferredOption(gestureID: UUID, reason: String) {
        if pendingReplayedHardwareOptionUpGestureID == gestureID {
            invalidatePendingReplayedHardwareOptionUp(gestureID: gestureID, reason: reason)
            return
        }
        if heldHardwareOptionSessionID == gestureID {
            abortHeldHardwareOption(gestureID: gestureID, reason: reason)
            return
        }
        guard optionGate.cancel(sessionID: gestureID) else { return }
        _ = syntheticOptionTrigger.abort(sessionID: gestureID)
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
        longConfirmedOptionGestureID = nil
        deferredOptionDownEvents.removeAll(keepingCapacity: true)
        deferredOptionUpEvents.removeAll(keepingCapacity: true)
        print(
            "[VOICE] option gate cancelled gesture=\(gestureID.uuidString) reason=\(reason)"
        )
        diagnosticLogger?.log(
            category: "filter",
            event: "OPTION_GATE_CLOSED",
            gestureID: gestureID,
            key: momentaryVoiceTriggerKey,
            fields: ["reason": reason, "gate_state": "cancelled"]
        )
    }

    func start() throws {
        guard tapPort == nil else {
            print("[FILTER] event tap already running")
            return
        }

        // Don't prompt user each time — check if already trusted.
        let trusted = AXIsProcessTrusted()
        let opts: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as CFString: !trusted
        ] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(opts)
        print("[FILTER] AX trusted=\(granted) (was \(trusted))")
        if !granted {
            // mtime on the binary changes when SwiftPM rebuilds; we exit
            // and the user re-runs after granting once.
            throw FilterError.accessibilityDenied
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { (_, type, event, userInfo) -> Unmanaged<CGEvent>? in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let filter = Unmanaged<VoiceKeyFilter>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = filter.tapPort {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    print("[FILTER] event tap was disabled; re-enabled")
                }
                return Unmanaged.passUnretained(event)
            }
            let keyCode = CGKeyCode(
                event.getIntegerValueField(.keyboardEventKeycode)
            )

            // 跳过 App 自身合成的事件（防止递归拦截）
            let userData = event.getIntegerValueField(.eventSourceUserData)
            if userData == Key.syntheticMarker {
                filter.logMappedTriggerEvent(
                    keyCode: keyCode,
                    eventType: type,
                    flags: event.flags,
                    eventTimestamp: event.timestamp,
                    syntheticMarker: true,
                    action: "pass"
                )
                return Unmanaged.passUnretained(event)
            }

            if keyCode == VK.voiceKey && (type == .keyDown || type == .keyUp) {
                filter.diagnosticLogger?.log(
                    category: "filter",
                    event: "RAW_VOICE_KEY",
                    fields: [
                        "edge": type == .keyDown ? "down" : "up",
                        "gesture_id": NSNull(),
                        "key_code": Int(keyCode),
                        "flags": UInt64(event.flags.rawValue),
                        "cg_event_timestamp_raw": UInt64(event.timestamp),
                        "cg_event_timestamp_clock": "quartz_event_timestamp_raw",
                        "observer_uptime": ProcessInfo.processInfo.systemUptime,
                    ]
                )
            }

            if filter.acknowledgeReplayedHardwareOptionUpIfExpected(event, type: type) {
                return Unmanaged.passUnretained(event)
            }

            if filter.shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: keyCode) {
                filter.logMappedTriggerEvent(
                    keyCode: keyCode,
                    eventType: type,
                    flags: event.flags,
                    eventTimestamp: event.timestamp,
                    syntheticMarker: false,
                    action: "reconfiguration_suppress"
                )
                return nil
            }

            if filter.shouldSuppressDiscardedHardwareTriggerEvent(
                keyCode: keyCode,
                type: type,
                eventFlags: event.flags
            ) {
                filter.logMappedTriggerEvent(
                    keyCode: keyCode,
                    eventType: type,
                    flags: event.flags,
                    eventTimestamp: event.timestamp,
                    syntheticMarker: false,
                    action: "suppress"
                )
                return nil
            }

            // A direct rapid re-press may arrive while the previous gesture's
            // hardware UP is still held or awaiting replay acknowledgement.
            // Capture only the new DOWN owner here; the old replay is checked
            // above and remains owned by its original gesture.
            if filter.matchesTriggerKeyCode(keyCode),
               filter.pendingHardwareOptionRepressGestureID != nil {
                let decision = filter.capturePendingHardwareOptionRepressEvent(
                    event,
                    type: type
                )
                let action: String
                switch decision {
                case .captured: action = "pending_repress_capture"
                case .suppressed: action = "pending_repress_suppress"
                case .pass: action = "pending_repress_old_owner_pass"
                }
                filter.logMappedTriggerEvent(
                    keyCode: keyCode,
                    eventType: type,
                    flags: event.flags,
                    eventTimestamp: event.timestamp,
                    syntheticMarker: false,
                    action: action
                )
                switch decision {
                case .captured, .suppressed:
                    return nil
                case .pass:
                    break
                }
            }

            // hidutil converts the remote's F5 usage into left Option. When a
            // FloatTabs voice handoff is active, hold that generated Option
            // pair only; real keyboard Option events remain untouched outside
            // this narrow gesture window.
            if filter.matchesTriggerKeyCode(keyCode),
               filter.optionDeferralActive {
                var action = "suppress"
                switch type {
                case .flagsChanged:
                    if filter.isTriggerModifierActive(flags: event.flags) {
                        let captured = filter.captureDeferredHardwareOptionEdge(
                            .down,
                            copiedEvent: event.copy()
                        )
                        action = captured ? "defer_down" : "suppress"
                    } else if filter.deferredOptionDownSeen {
                        let captured = filter.captureDeferredHardwareOptionEdge(
                            .up,
                            copiedEvent: event.copy()
                        )
                        action = captured ? "defer_up" : "suppress"
                    }
                case .keyDown:
                    let captured = filter.captureDeferredHardwareOptionEdge(
                        .down,
                        copiedEvent: event.copy()
                    )
                    action = captured ? "defer_down" : "suppress"
                case .keyUp:
                    if filter.deferredOptionDownSeen {
                        let captured = filter.captureDeferredHardwareOptionEdge(
                            .up,
                            copiedEvent: event.copy()
                        )
                        action = captured ? "defer_up" : "suppress"
                    } else {
                        filter.logMappedTriggerEvent(
                            keyCode: keyCode,
                            eventType: type,
                            flags: event.flags,
                            eventTimestamp: event.timestamp,
                            syntheticMarker: false,
                            action: "unmatched_pass"
                        )
                        return Unmanaged.passUnretained(event)
                    }
                default:
                    break
                }
                filter.logMappedTriggerEvent(
                    keyCode: keyCode,
                    eventType: type,
                    flags: event.flags,
                    eventTimestamp: event.timestamp,
                    syntheticMarker: false,
                    action: action
                )
                return nil
            }

            // Once a long hardware replay has been selected and the raw HID
            // voice-key up is accepted, hold only that session's mapped
            // Option-up until AudioPipe confirms the queued PCM is drained.
            if filter.matchesTriggerKeyCode(keyCode),
               filter.heldHardwareOptionSessionID != nil,
               filter.hardwareOptionReleaseArmed {
                switch filter.captureHeldHardwareOptionUpEvent(event, type: type) {
                case .captured:
                    filter.logMappedTriggerEvent(
                        keyCode: keyCode,
                        eventType: type,
                        flags: event.flags,
                        eventTimestamp: event.timestamp,
                        syntheticMarker: false,
                        action: "hold_release"
                    )
                    return nil
                case .suppressed:
                    filter.logMappedTriggerEvent(
                        keyCode: keyCode,
                        eventType: type,
                        flags: event.flags,
                        eventTimestamp: event.timestamp,
                        syntheticMarker: false,
                        action: "suppress"
                    )
                    return nil
                case .pass:
                    filter.logMappedTriggerEvent(
                        keyCode: keyCode,
                        eventType: type,
                        flags: event.flags,
                        eventTimestamp: event.timestamp,
                        syntheticMarker: false,
                        action: "pass"
                    )
                    return Unmanaged.passUnretained(event)
                }
            }

            if keyCode == VK.voiceKey {
                if filter.skipVoiceKey {
                    return Unmanaged.passUnretained(event)
                }
                if type == .keyDown {
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    if filter.voiceKeyIsDown || isRepeat {
                        return nil
                    }
                    filter.voiceKeyIsDown = true
                    print("[KEY] voice-key DOWN → gesture pending")
                    filter.onVoiceKeyDown?()
                    return nil
                } else if type == .keyUp {
                    guard filter.voiceKeyIsDown else { return nil }
                    filter.voiceKeyIsDown = false
                    print("[KEY] voice-key UP   → finish gesture")
                    filter.onVoiceKeyUp?()
                    return nil
                }
            }

            filter.logMappedTriggerEvent(
                keyCode: keyCode,
                eventType: type,
                flags: event.flags,
                eventTimestamp: event.timestamp,
                syntheticMarker: false,
                action: "pass"
            )
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw FilterError.tapCreationFailed
        }
        tapPort = tap
        guard let src = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CGEvent.tapEnable(tap: tap, enable: false)
            tapPort = nil
            throw FilterError.tapCreationFailed
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        tapSource = src
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[FILTER] tap enabled; voice key 0x60 (F5) is suppressed; HID mapping supplies physical Option, with synthetic fallback")
    }

    func stop() {
        if let gestureID = optionGate.activeSessionID {
            cancelDeferredOption(gestureID: gestureID, reason: "stop")
        }
        if let gestureID = heldHardwareOptionSessionID {
            abortHeldHardwareOption(gestureID: gestureID, reason: "stop")
        }
        if let gestureID = optionGate.suppressedSessionID {
            _ = resetSuppressedHardwareTrigger(
                gestureID: gestureID,
                reason: "stop"
            )
        }
        if let gestureID = pendingReplayedHardwareOptionUpGestureID {
            invalidatePendingReplayedHardwareOptionUp(
                gestureID: gestureID,
                reason: "stop"
            )
        }
        if let gestureID = pendingHardwareOptionRepressGestureID {
            pendingHardwareOptionRepress = nil
            diagnosticLogger?.log(
                category: "filter",
                event: "PENDING_HARDWARE_REPRESS_CANCEL",
                gestureID: gestureID,
                key: momentaryVoiceTriggerKey,
                fields: ["reason": "stop"]
            )
        }
        if voiceKeyIsDown {
            voiceKeyIsDown = false
            onVoiceKeyUp?()
        }
        if let source = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let t = tapPort { CGEvent.tapEnable(tap: t, enable: false) }
        tapSource = nil
        tapPort = nil
    }
}

// MARK: - Menu bar UI

enum VoiceTriggerApplyResult: Equatable {
    case applied
    case unchanged
    case busy
    case busyActiveHold
    case busyReleaseDrain
    case failed
    case locked
}

enum VoicePressInputSource: String {
    case hidMonitor = "hid_monitor"
    case voiceKeyFilterFallback = "voice_key_filter_fallback"
}

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusLabel: NSMenuItem!
    private var remoteStatusItem: NSMenuItem!
    private var audioStatusItem: NSMenuItem!
    private var audioInputMenu: NSMenu!
    private var audioOutputMenu: NSMenu!
    private var voiceInputProfileMenu: NSMenu!

    private(set) var hidConnected = false
    private var bleConnected = false
    private var remoteStreaming = false
    private var statusPulseTimer: Timer?
    private var statusPulsePhase = false

    let filter: VoiceKeyFilter
    let voicePress: VoicePressCoordinator
    let dualReceiverVoiceGestureRecognizer: DualReceiverVoiceGestureRecognizer
    private(set) var dualReceiverVoiceMode: DualReceiverVoiceMode = .legacy
    private let diagnosticLogger: VoiceDiagnosticLogger
    private var frontmostApplicationDiagnosticsObserver: FrontmostApplicationDiagnosticsObserver?
    private let ble = BLEBridge()
    private let mappingStore = MappingStore()
    private let hidMonitor = HIDMonitor()
    private let buttonGestureRecognizer = ButtonGestureRecognizer()
    private let actionHUD = RemoteActionHUD()
    private let voiceReceiverReadinessMonitor = VoiceReceiverReadinessMonitor()
    private var lastReceiverReadiness: VoiceReceiverReadiness = .inactive
    private let keymapOverlayController = KeymapOverlayController()
    /// The contextual mapping overlay is a press-and-hold surface. Keep the
    /// originating button so its release can dismiss only its own overlay.
    private var contextualOverlayButton: RemoteButton?
    /// Buttons that were physically held when HID disappeared. Their next
    /// report is a transport re-announcement, not a new click; keep the
    /// marker until the matching release arrives.
    private var reconnectHeldButtons: Set<RemoteButton> = []
    private var repeatGestureHUDButtons: Set<RemoteButton> = []
    private let voiceFocusTransactions = VoiceFocusTransactionTracker()
    private var voiceFocusSafetyWorkItem: DispatchWorkItem?
    private let voiceFocusSafetyTimeout: TimeInterval = 0.36
    private(set) var currentMomentaryVoiceTriggerKey: VoiceTriggerKey = .leftOption
    private(set) var currentVoiceInputProfile: VoiceInputProfile = .defaultProfile
    private(set) var currentPersistentSessionTriggerKey: VoiceTriggerKey = .leftOption
    private(set) var currentSecondaryMomentaryVoiceTriggerKey: VoiceTriggerKey?
    private var currentDualReceiverShortBinding: ButtonBinding?
    private(set) var dualReceiverMappedTriggerState = DualReceiverMappedTriggerState()
    /// Compatibility alias: historical callers meant the mapped momentary
    /// remote-microphone trigger.
    var currentVoiceTriggerKey: VoiceTriggerKey { currentMomentaryVoiceTriggerKey }
    private(set) var voiceTriggerReconfigurationInProgress = false
    private(set) var voiceTriggerRuntimeLocked = false
    private var pendingVoiceHIDMappingRefresh = false
    private var dualReceiverReconfigurationGateActive = false
    private(set) var lastAToBApplyMillisecondsForTesting: Double?
    private(set) var lastBToAApplyMillisecondsForTesting: Double?
    private(set) var lastFirstUpToSecondaryReadyMillisecondsForTesting: Double?
    private var dualReceiverPrewarmGestureID: UUID?
    private var dualReceiverPhysicalDownAt: TimeInterval?
    private var activeDualReceiverGestureID: UUID?
    private let isVoiceHIDMappingEnabled: () -> Bool
    private let applyVoiceHIDMapping: (Bool, VoiceTriggerKey) -> Bool
    private let applyVoiceHIDMappingWithReadback: ((
        Bool,
        VoiceTriggerKey,
        @escaping (VoiceDiagnosticHIDVerification) -> Void
    ) -> Bool)?
    private let rawHIDReadiness: (() -> Bool)?
    private let eventSuppressorReadiness: (() -> Bool)?
    private let prepareVoiceTransportAction: (() -> Void)?
    private let activateVoiceInputAction: (() -> Void)?
    private let cancelVoiceTransportPreparationAction: (() -> Void)?
    private let stopVoiceInputAction: (() -> Void)?
    private let readPersistedVoiceTriggerKey: () -> VoiceTriggerKey
    private let persistVoiceTriggerKey: (VoiceTriggerKey) -> Void
    private let usePersistedVoiceProfile: Bool
    private let readPersistedPersistentSessionTriggerKey: () -> VoiceTriggerKey
    private let persistPersistentSessionTriggerKey: (VoiceTriggerKey) -> Void
    private let readPersistedSecondaryMomentaryVoiceTriggerKey: () -> VoiceTriggerKey?
    private let persistSecondaryMomentaryVoiceTriggerKey: (VoiceTriggerKey?) -> Void
    private let diagnosticUptimeProvider: () -> TimeInterval
    private let voiceHIDMappingQueue = DispatchQueue(
        label: "com.remoteorbit.voice-trigger-hid-mapping",
        qos: .userInitiated
    )

    init(
        filter: VoiceKeyFilter = VoiceKeyFilter(diagnosticLogger: .shared),
        voicePress: VoicePressCoordinator = VoicePressCoordinator(diagnosticLogger: .shared),
        dualReceiverVoiceGestureRecognizer: DualReceiverVoiceGestureRecognizer =
            DualReceiverVoiceGestureRecognizer(),
        initiallyHIDConnected: Bool = false,
        isVoiceHIDMappingEnabled: @escaping () -> Bool = {
            RemoteVoiceKeyMapping.isEnabled
        },
        applyVoiceHIDMapping: @escaping (Bool, VoiceTriggerKey) -> Bool = {
            RemoteVoiceKeyMapping.setEnabled($0, target: $1)
        },
        applyVoiceHIDMappingWithReadback: ((
            Bool,
            VoiceTriggerKey,
            @escaping (VoiceDiagnosticHIDVerification) -> Void
        ) -> Bool)? = nil,
        rawHIDReadiness: (() -> Bool)? = nil,
        eventSuppressorReadiness: (() -> Bool)? = nil,
        prepareVoiceTransport: (() -> Void)? = nil,
        activateVoiceInput: (() -> Void)? = nil,
        cancelVoiceTransportPreparation: (() -> Void)? = nil,
        stopVoiceInput: (() -> Void)? = nil,
        usePersistedVoiceProfile: Bool = true,
        readPersistedVoiceTriggerKey: @escaping () -> VoiceTriggerKey = {
            AppStorage.momentaryVoiceTriggerKey
        },
        persistVoiceTriggerKey: @escaping (VoiceTriggerKey) -> Void = {
            AppStorage.momentaryVoiceTriggerKey = $0
        },
        readPersistedPersistentSessionTriggerKey: @escaping () -> VoiceTriggerKey = {
            AppStorage.persistentSessionTriggerKey
        },
        persistPersistentSessionTriggerKey: @escaping (VoiceTriggerKey) -> Void = {
            AppStorage.persistentSessionTriggerKey = $0
        },
        readPersistedSecondaryMomentaryVoiceTriggerKey: @escaping () -> VoiceTriggerKey? = {
            AppStorage.secondaryMomentaryVoiceTriggerKey
        },
        persistSecondaryMomentaryVoiceTriggerKey: @escaping (VoiceTriggerKey?) -> Void = {
            AppStorage.secondaryMomentaryVoiceTriggerKey = $0
        },
        diagnosticLogger: VoiceDiagnosticLogger = .shared,
        uptimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.filter = filter
        self.voicePress = voicePress
        self.dualReceiverVoiceGestureRecognizer = dualReceiverVoiceGestureRecognizer
        self.diagnosticLogger = diagnosticLogger
        self.hidConnected = initiallyHIDConnected
        self.isVoiceHIDMappingEnabled = isVoiceHIDMappingEnabled
        self.applyVoiceHIDMapping = applyVoiceHIDMapping
        self.applyVoiceHIDMappingWithReadback = applyVoiceHIDMappingWithReadback
        self.rawHIDReadiness = rawHIDReadiness
        self.eventSuppressorReadiness = eventSuppressorReadiness
        self.prepareVoiceTransportAction = prepareVoiceTransport
        self.activateVoiceInputAction = activateVoiceInput
        self.cancelVoiceTransportPreparationAction = cancelVoiceTransportPreparation
        self.stopVoiceInputAction = stopVoiceInput
        self.usePersistedVoiceProfile = usePersistedVoiceProfile
        self.readPersistedVoiceTriggerKey = readPersistedVoiceTriggerKey
        self.persistVoiceTriggerKey = persistVoiceTriggerKey
        self.readPersistedPersistentSessionTriggerKey = readPersistedPersistentSessionTriggerKey
        self.persistPersistentSessionTriggerKey = persistPersistentSessionTriggerKey
        self.readPersistedSecondaryMomentaryVoiceTriggerKey =
            readPersistedSecondaryMomentaryVoiceTriggerKey
        self.persistSecondaryMomentaryVoiceTriggerKey = persistSecondaryMomentaryVoiceTriggerKey
        self.diagnosticUptimeProvider = uptimeProvider
        super.init()
        dualReceiverVoiceGestureRecognizer.onEvent = { [weak self] event in
            self?.handleDualReceiverGestureEvent(event)
        }
        voicePress.onStateChanged = { [weak self] state in
            // Gate A uses `.opening`; `.holding` remains only for the
            // historical classified test seam, which AppController no
            // longer enters from production HID microphone edges.
            if state == .opening || state == .holding {
                self?.activateVoiceInput()
            }
        }
        voicePress.onRemoteTransportPreparation = { [weak self] in
            self?.prepareVoiceTransport()
        }
        voiceReceiverReadinessMonitor.onStateChanged = { [weak self] readiness in
            guard let self else { return }
            self.lastReceiverReadiness = readiness
            self.diagnosticLogger.log(
                category: "voice",
                event: "VOICE_RECEIVER_READINESS",
                fields: readiness.diagnosticFields
            )
            self.updateVoiceHUD(for: self.voicePress.currentStateForTesting)
        }
        voicePress.isVoiceSessionAdmissionBlocked = { [weak self] in
            self?.ble.isVoiceSessionAdmissionBlocked ?? false
        }
        voicePress.hasLivePhysicalCandidate = { [weak self] in
            self?.ble.hasLivePreHIDPhysicalCandidate ?? false
        }
        ble.onVoiceSessionAdmissionAvailable = { [weak self] in
            self?.voicePress.voiceSessionAdmissionBecameAvailable()
        }
        filter.onReplayedHardwareOptionUpPassAcknowledged = { [weak self] gestureID in
            self?.voicePress.hardwareOptionUpPassAcknowledged(sessionID: gestureID)
            self?.handleDualReceiverHardwareOutputDrainClosed(gestureID: gestureID)
        }
    }

    @discardableResult
    func restoreVoiceTriggerRuntime() -> Bool {
        // AppStorage.prepare() performs the real startup migration before the
        // production delegate reaches this method. The injected legacy reader
        // remains the deterministic test seam for controller-only harnesses;
        // it does not participate in the launched app path once the profile ID
        // has been persisted.
        let restoredProfile = usePersistedVoiceProfile
            ? VoiceInputProfileStore.persistedProfile(from: UserDefaults.standard)
                ?? VoiceInputProfileStore.profile(for: readPersistedVoiceTriggerKey())
            : VoiceInputProfileStore.profile(for: readPersistedVoiceTriggerKey())
        let restoredMomentaryKey = restoredProfile.triggerKey
        // The direct Gate A path never consults this legacy field. Keep its
        // injected value only for historical coordinator tests and rollback
        // compatibility; no production voice edge routes through it.
        let restoredPersistentKey = readPersistedPersistentSessionTriggerKey()
        let restoredSecondaryMomentaryKey = readPersistedSecondaryMomentaryVoiceTriggerKey()
        currentDualReceiverShortBinding = mappingStore.binding(for: .microphone)
        diagnosticLogger.log(
            category: "configuration",
            event: "RUNTIME_RESTORE_BEGIN",
            fields: [
                "persisted_persistent": restoredPersistentKey.rawValue,
                "persisted_momentary": restoredMomentaryKey.rawValue,
                "voice_input_profile_id": restoredProfile.id,
                "persisted_legacy": UserDefaults.standard.string(
                    forKey: AppStorage.voiceTriggerKeyKey
                ) ?? "none",
            ]
        )
        guard filter.configureVoiceTriggerKey(restoredMomentaryKey) else {
            voiceTriggerRuntimeLocked = true
            print("[VOICE-KEY] startup restore failed; runtime locked")
            diagnosticLogger.log(
                category: "configuration",
                event: "RUNTIME_RESTORE_FAIL",
                fields: ["reason": "momentary_filter_configure_failed"]
            )
            return false
        }
        guard voicePress.configurePersistentSessionTriggerKey(restoredPersistentKey) else {
            voiceTriggerRuntimeLocked = true
            print("[VOICE-KEY] persistent startup restore failed; runtime locked")
            diagnosticLogger.log(
                category: "configuration",
                event: "RUNTIME_RESTORE_FAIL",
                fields: ["reason": "persistent_controller_configure_failed"]
            )
            return false
        }
        currentMomentaryVoiceTriggerKey = restoredMomentaryKey
        currentVoiceInputProfile = restoredProfile
        currentPersistentSessionTriggerKey = restoredPersistentKey
        currentSecondaryMomentaryVoiceTriggerKey = restoredSecondaryMomentaryKey
        print(
            "[VOICE-KEY] startup restored profile=\(restoredProfile.displayName)"
        )
        diagnosticLogger.log(
            category: "configuration",
            event: "RUNTIME_RESTORE_COMMIT",
            key: restoredMomentaryKey,
            fields: [
                "controller_persistent": currentPersistentSessionTriggerKey.rawValue,
                "controller_momentary": currentMomentaryVoiceTriggerKey.rawValue,
                "filter_momentary": filter.momentaryVoiceTriggerKey.rawValue,
                "synthetic_momentary": voicePress.diagnosticStateFields["momentary_config"] as? String ?? "unknown",
                "persisted_persistent": restoredPersistentKey.rawValue,
                "persisted_momentary": restoredMomentaryKey.rawValue,
                "voice_input_profile_id": restoredProfile.id,
            ]
        )
        return true
    }

    /// Establishes Receiver A's device-scoped mapping before raw-F5 dual mode can
    /// accept gestures. The process result is authoritative; callers must not
    /// infer success from the cached RemoteVoiceKeyMapping.isEnabled value.
    @discardableResult
    func applyPrimaryRemoteVoiceHIDMappingForDualMode() -> Bool {
        let primaryKey = currentMomentaryVoiceTriggerKey
        return voiceHIDMappingQueue.sync {
            applyVoiceHIDMapping(true, primaryKey)
        }
    }

    /// Selects the dual-receiver authority only after the raw HID owner, its
    /// existing EventSuppressor, and the primary mapping operation are
    /// all ready and Receiver A's mapping has been applied. A valid but unsafe
    /// request remains unavailable so it cannot fall through to the legacy path.
    func configureDualReceiverVoiceMode(
        shortBinding: ButtonBinding,
        receiverB: VoiceTriggerKey?
    ) -> DualReceiverVoiceModeUpdateResult {
        guard DualReceiverVoiceMode.canChangeConfiguration(
            while: dualReceiverVoiceOwnership
        ) else {
            return .busy
        }

        let rawHIDReady = rawHIDReadiness?() ?? hidMonitor.isRunning
        let suppressorReady = eventSuppressorReadiness?()
            ?? hidMonitor.eventSuppressor.isRunning
        let eligibility = DualReceiverVoiceMode.evaluate(
            shortIsDisabled: shortBinding.isDisabled,
            receiverA: currentMomentaryVoiceTriggerKey,
            receiverB: receiverB,
            rawHIDReady: rawHIDReady,
            eventSuppressorReady: suppressorReady,
            primaryMappingSucceeded: true
        )

        switch eligibility {
        case .legacy:
            if dualReceiverVoiceMode != .legacy && hidConnected {
                guard applyVoiceHIDMapping(true, currentMomentaryVoiceTriggerKey) else {
                    let reason = DualReceiverVoiceMode.UnavailabilityReason
                        .legacyMappingRestoreFailed
                    dualReceiverVoiceMode = .unavailable(reason)
                    dualReceiverMappedTriggerState.markUnavailable(
                        reason: .primaryRestoreFailed
                    )
                    return .unavailable(reason)
                }
            }
            currentDualReceiverShortBinding = shortBinding
            dualReceiverVoiceMode = .legacy
            dualReceiverMappedTriggerState.markUnavailable(reason: .dualModeInactive)
            return .applied(.legacy)
        case let .unavailable(reason):
            dualReceiverVoiceMode = eligibility
            dualReceiverMappedTriggerState.markUnavailable(reason: .dualModeUnavailable)
            return .unavailable(reason)
        case .active:
            let filterKey = filter.voiceTriggerKey
            guard filter.beginVoiceTriggerReconfiguration(
                from: filterKey,
                to: currentMomentaryVoiceTriggerKey
            ) else {
                dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
                dualReceiverMappedTriggerState.markUnavailable(
                    reason: .filterConfigurationFailed
                )
                return .unavailable(.primaryMappingFailed)
            }
            dualReceiverReconfigurationGateActive = true
            voiceTriggerReconfigurationInProgress = true
            let primaryMappingSucceeded = applyPrimaryRemoteVoiceHIDMappingForDualMode()
            let filterConfigured = primaryMappingSucceeded
                && filter.configureVoiceTriggerKey(currentMomentaryVoiceTriggerKey)
            filter.endVoiceTriggerReconfiguration()
            dualReceiverReconfigurationGateActive = false
            voiceTriggerReconfigurationInProgress = false
            let resolved = DualReceiverVoiceMode.evaluate(
                shortIsDisabled: shortBinding.isDisabled,
                receiverA: currentMomentaryVoiceTriggerKey,
                receiverB: receiverB,
                rawHIDReady: rawHIDReady,
                eventSuppressorReady: suppressorReady,
                primaryMappingSucceeded: primaryMappingSucceeded && filterConfigured
            )
            dualReceiverVoiceMode = resolved
            if case let .unavailable(reason) = resolved {
                dualReceiverMappedTriggerState.markUnavailable(reason: .mappingApplyFailed)
                return .unavailable(reason)
            }
            currentDualReceiverShortBinding = shortBinding
            dualReceiverMappedTriggerState.establishPrimaryReady()
            return .applied(resolved)
        }
    }

    /// Applies Receiver B only while the dual-recognizer, transaction, filter,
    /// and release/drain path are unowned. Receiver A and Persistent Session
    /// remain separate preferences and runtime authorities.
    func applySecondaryVoiceTriggerKey(
        _ newKey: VoiceTriggerKey?,
        shortBinding: ButtonBinding,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(.locked)
                    return
                }
                self.applySecondaryVoiceTriggerKey(
                    newKey,
                    shortBinding: shortBinding,
                    completion: completion
                )
            }
            return
        }
        guard !voiceTriggerRuntimeLocked else {
            completion(.locked)
            return
        }
        guard !voiceTriggerReconfigurationInProgress else {
            completion(.busy)
            return
        }
        guard newKey != currentSecondaryMomentaryVoiceTriggerKey else {
            completion(.unchanged)
            return
        }
        if dualReceiverVoiceGestureRecognizer.isBusy {
            completion(.busy)
            return
        }
        if voicePress.hasVoiceKeyHeldForReconfiguration || filter.isVoiceKeyHeld {
            completion(.busyActiveHold)
            return
        }
        if voicePress.hasReleaseOrTailOwnershipForReconfiguration
            || filter.hasActiveHardwareTriggerOwnership
            || filter.isSyntheticTriggerDown
            || filter.hasSyntheticTriggerOwnership {
            completion(.busyReleaseDrain)
            return
        }

        switch configureDualReceiverVoiceMode(
            shortBinding: shortBinding,
            receiverB: newKey
        ) {
        case .busy:
            completion(.busy)
        case .unavailable:
            completion(.failed)
        case .applied:
            currentSecondaryMomentaryVoiceTriggerKey = newKey
            currentDualReceiverShortBinding = shortBinding
            persistSecondaryMomentaryVoiceTriggerKey(newKey)
            diagnosticLogger.log(
                category: "configuration",
                event: "SECONDARY_MOMENTARY_RECONFIG_COMMIT",
                key: newKey,
                fields: [
                    "receiver_a": currentMomentaryVoiceTriggerKey.rawValue,
                    "receiver_b": newKey?.rawValue ?? "off",
                    "dual_mode": String(describing: dualReceiverVoiceMode),
                    "short_disabled": String(shortBinding.isDisabled),
                ]
            )
            completion(.applied)
        }
    }

    /// Routes one raw HID microphone edge through the voice-specific classifier.
    /// Physical timestamps are passed through unchanged; wall-clock/UI timing
    /// is never used to classify the gesture.
    func handleDualReceiverMicrophoneEdge(
        isDown: Bool,
        at timestamp: TimeInterval
    ) {
        if isDown {
            switch dualReceiverMappedTriggerState.phase {
            case let .armingSecondary(gestureID, _):
                guard dualReceiverMappedTriggerState.blockPressUntilRelease(
                    gestureID: gestureID
                ) else {
                    return
                }
                dualReceiverVoiceGestureRecognizer.cancel()
                _ = voicePress.cancelClassifiedHardwareGate(sessionID: gestureID)
                if dualReceiverPrewarmGestureID == gestureID {
                    cancelPendingDualReceiverPrewarm()
                }
                dualReceiverPhysicalDownAt = timestamp
                diagnosticLogger.log(
                    category: "input",
                    event: "DUAL_RECEIVER_SECOND_DOWN_ADMISSION",
                    gestureID: gestureID,
                    fields: [
                        "SECOND_DOWN_READY_BEFORE_EDGE": false,
                        "admitted": false,
                        "mapping_phase": "armingSecondary",
                    ]
                )
                return

            case .restoringPrimary, .blockedUntilRelease:
                diagnosticLogger.log(
                    category: "input",
                    event: "DUAL_RECEIVER_SECOND_DOWN_ADMISSION",
                    fields: [
                        "SECOND_DOWN_READY_BEFORE_EDGE": false,
                        "admitted": false,
                        "mapping_phase": String(describing: dualReceiverMappedTriggerState.phase),
                    ]
                )
                return

            case let .secondaryReady(gestureID):
                diagnosticLogger.log(
                    category: "input",
                    event: "DUAL_RECEIVER_SECOND_DOWN_ADMISSION",
                    gestureID: gestureID,
                    fields: [
                        "SECOND_DOWN_READY_BEFORE_EDGE": true,
                        "mapping_phase": "secondaryReady",
                    ]
                )

            case .secondaryActive:
                diagnosticLogger.log(
                    category: "input",
                    event: "DUAL_RECEIVER_SECOND_DOWN_ADMISSION",
                    fields: [
                        "SECOND_DOWN_READY_BEFORE_EDGE": false,
                        "admitted": false,
                        "mapping_phase": "secondaryActive",
                    ]
                )
                return

            case .primaryReady, .unavailable:
                break
            }
        }

        if !isDown,
           case let .blockedUntilRelease(gestureID) = dualReceiverMappedTriggerState.phase {
            dualReceiverVoiceGestureRecognizer.cancel()
            dualReceiverPhysicalDownAt = nil
            restorePrimaryMappingAfterSecondary(
                gestureID: gestureID,
                reason: "early-second-press-released"
            )
            return
        }

        if !isDown,
           case .restoringPrimary = dualReceiverMappedTriggerState.phase {
            return
        }

        if !isDown, activeDualReceiverGestureID != nil {
            _ = dualReceiverVoiceGestureRecognizer.handleUp(at: timestamp)
            finishActiveDualReceiverGestureRelease()
            return
        }

        if isDown,
           case .active = dualReceiverVoiceMode,
           let reason = dualReceiverReadinessFailure() {
            dualReceiverVoiceMode = .unavailable(reason)
            dualReceiverVoiceGestureRecognizer.cancel()
            cancelPendingDualReceiverPrewarm()
            dualReceiverPhysicalDownAt = nil
            return
        }

        guard case .active = dualReceiverVoiceMode else {
            if !isDown {
                dualReceiverVoiceGestureRecognizer.cancel()
                cancelPendingDualReceiverPrewarm()
                dualReceiverPhysicalDownAt = nil
            }
            return
        }

        if isDown {
            guard activeDualReceiverGestureID == nil else { return }
            let gestureID = dualReceiverVoiceGestureRecognizer.handleDown(at: timestamp)
            guard let gestureID else { return }
            dualReceiverPhysicalDownAt = timestamp
            let mappingPhase = dualReceiverMappedTriggerState.phase
            let shouldPrearmHardwareGate: Bool
            switch mappingPhase {
            case .primaryReady:
                shouldPrearmHardwareGate = true
            case let .secondaryReady(readyGestureID):
                shouldPrearmHardwareGate = readyGestureID == gestureID
            case .armingSecondary, .secondaryActive, .restoringPrimary,
                 .blockedUntilRelease, .unavailable:
                shouldPrearmHardwareGate = false
            }
            if shouldPrearmHardwareGate,
               !voicePress.beginClassifiedHardwareGate(sessionID: gestureID) {
                dualReceiverVoiceGestureRecognizer.cancel()
                dualReceiverPhysicalDownAt = nil
                if case .secondaryReady = mappingPhase {
                    if dualReceiverPrewarmGestureID == gestureID {
                        cancelPendingDualReceiverPrewarm()
                    }
                    restorePrimaryMappingAfterSecondary(
                        gestureID: gestureID,
                        reason: "secondary-hardware-gate-begin-failed"
                    )
                }
                return
            }
            if dualReceiverPrewarmGestureID != gestureID {
                dualReceiverPrewarmGestureID = gestureID
                prepareVoiceTransport()
            }
            return
        }

        _ = dualReceiverVoiceGestureRecognizer.handleUp(at: timestamp)
        // A delayed main-queue classifier timer can be first observed on the
        // physical release edge. If that edge crosses the hold threshold, the
        // classification callback starts the voice transaction synchronously;
        // consume this same physical release instead of leaving the route held.
        finishActiveDualReceiverGestureRelease()
    }

    private func finishActiveDualReceiverGestureRelease() {
        let releasedGestureID = activeDualReceiverGestureID
        guard releasedGestureID != nil else { return }
        activeDualReceiverGestureID = nil
        dualReceiverPhysicalDownAt = nil
        finishVoicePressRelease(source: .hidMonitor) { [weak self] in
            self?.stopVoiceInput()
        }
        if let releasedGestureID {
            handleDualReceiverHardwareOutputDrainClosed(
                gestureID: releasedGestureID,
                outputDrainCompleted: false
            )
        }
    }

    private func handleDualReceiverGestureEvent(
        _ event: DualReceiverVoiceGestureRecognizer.Event
    ) {
        switch event {
        case let .awaitingSecondPress(gestureID, firstUpAt):
            _ = voicePress.cancelClassifiedHardwareGate(sessionID: gestureID)
            dualReceiverPhysicalDownAt = nil
            beginSecondaryMappingArm(
                gestureID: gestureID,
                firstUpAt: firstUpAt
            )
        case let .noAction(gestureID):
            _ = voicePress.cancelClassifiedHardwareGate(sessionID: gestureID)
            if dualReceiverPrewarmGestureID == gestureID {
                cancelPendingDualReceiverPrewarm()
            }
            dualReceiverPhysicalDownAt = nil
            switch dualReceiverMappedTriggerState.phase {
            case .armingSecondary, .secondaryReady:
                restorePrimaryMappingAfterSecondary(
                    gestureID: gestureID,
                    reason: "second-press-window-expired"
                )
            case .primaryReady, .restoringPrimary, .secondaryActive,
                 .blockedUntilRelease, .unavailable:
                break
            }
        case let .classified(gestureID, receiver):
            guard case let .active(receiverA, receiverB) = dualReceiverVoiceMode,
                  dualReceiverPrewarmGestureID == gestureID,
                  let physicalDownAt = dualReceiverPhysicalDownAt else {
                cancelPendingDualReceiverPrewarm()
                dualReceiverPhysicalDownAt = nil
                dualReceiverVoiceGestureRecognizer.cancel()
                return
            }
            let mappingPhase = dualReceiverMappedTriggerState.phase
            let receiverIsReady = receiver == .a
                ? mappingPhase == .primaryReady
                : mappingPhase == .secondaryReady(gestureID: gestureID)
            guard receiverIsReady else {
                if receiver == .b,
                   case let .armingSecondary(armingGestureID, _) = mappingPhase,
                   armingGestureID == gestureID {
                    _ = dualReceiverMappedTriggerState.blockPressUntilRelease(
                        gestureID: gestureID
                    )
                    dualReceiverVoiceGestureRecognizer.cancel()
                    dualReceiverPhysicalDownAt = physicalDownAt
                    if dualReceiverPrewarmGestureID == gestureID {
                        cancelPendingDualReceiverPrewarm()
                    }
                } else {
                    cancelPendingDualReceiverPrewarm()
                    dualReceiverPhysicalDownAt = nil
                    dualReceiverVoiceGestureRecognizer.cancel()
                }
                diagnosticLogger.log(
                    category: "input",
                    event: "DUAL_RECEIVER_CLASSIFICATION_DISCARDED",
                    gestureID: gestureID,
                    key: receiver == .a ? receiverA : receiverB,
                    fields: [
                        "receiver": receiver == .a ? "A" : "B",
                        "mapping_phase": String(describing: mappingPhase),
                        "reason": "mapping-not-ready",
                    ]
                )
                return
            }
            let triggerKey = receiver == .a ? receiverA : receiverB
            dualReceiverPrewarmGestureID = nil
            dualReceiverPhysicalDownAt = nil
            if receiver == .b {
                guard dualReceiverMappedTriggerState.admitSecondaryPress(
                    gestureID: gestureID
                ) else {
                    _ = voicePress.cancelClassifiedHardwareGate(sessionID: gestureID)
                    cancelVoiceTransportPreparation()
                    dualReceiverVoiceGestureRecognizer.cancel()
                    restorePrimaryMappingAfterSecondary(
                        gestureID: gestureID,
                        reason: "secondary-admission-generation-stale",
                        keepDualModeLocked: true
                    )
                    return
                }
                guard voicePress.beginClassifiedHardwareHold(
                    sessionID: gestureID,
                    physicalDownAt: physicalDownAt,
                    triggerKey: triggerKey
                ) else {
                    _ = voicePress.cancelClassifiedHardwareGate(sessionID: gestureID)
                    cancelVoiceTransportPreparation()
                    dualReceiverVoiceGestureRecognizer.cancel()
                    restorePrimaryMappingAfterSecondary(
                        gestureID: gestureID,
                        reason: "secondary-hardware-hold-begin-failed"
                    )
                    return
                }
                activeDualReceiverGestureID = gestureID
                return
            }
            let beganVoicePress = voicePress.beginClassifiedHardwareHold(
                sessionID: gestureID,
                physicalDownAt: physicalDownAt,
                triggerKey: triggerKey
            )
            guard beganVoicePress else {
                _ = voicePress.cancelClassifiedHardwareGate(sessionID: gestureID)
                cancelVoiceTransportPreparation()
                dualReceiverVoiceGestureRecognizer.cancel()
                return
            }
            activeDualReceiverGestureID = gestureID
        }
    }

    private func beginSecondaryMappingArm(
        gestureID: UUID,
        firstUpAt: TimeInterval
    ) {
        guard case let .active(receiverA, receiverB) = dualReceiverVoiceMode,
              let generation = dualReceiverMappedTriggerState
                .beginSecondaryArming(gestureID: gestureID) else {
            return
        }
        guard !voiceTriggerRuntimeLocked,
              !voiceTriggerReconfigurationInProgress,
              filter.beginVoiceTriggerReconfiguration(from: receiverA, to: receiverB) else {
            dualReceiverMappedTriggerState.markUnavailable(reason: .filterConfigurationFailed)
            dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
            voiceTriggerRuntimeLocked = true
            return
        }

        dualReceiverReconfigurationGateActive = true
        voiceTriggerReconfigurationInProgress = true
        diagnosticLogger.log(
            category: "configuration",
            event: "A_TO_B_RECONFIGURATION_BEGIN",
            key: receiverB,
            fields: [
                "receiver_a": receiverA.rawValue,
                "receiver_b": receiverB.rawValue,
                "generation": generation,
            ]
        )
        voiceHIDMappingQueue.async { [weak self] in
            guard let self else { return }
            let startedAt = P1A4MonotonicClock.nowNanoseconds()
            let succeeded: Bool
            if let applyWithReadback = self.applyVoiceHIDMappingWithReadback {
                succeeded = applyWithReadback(true, receiverB) { [weak self] verification in
                    DispatchQueue.main.async { [weak self] in
                        self?.handleSecondaryMappingReadback(
                            gestureID: gestureID,
                            generation: generation,
                            receiverB: receiverB,
                            verification: verification
                        )
                    }
                }
            } else {
                succeeded = self.applyVoiceHIDMapping(true, receiverB)
            }
            let endedAt = P1A4MonotonicClock.nowNanoseconds()
            let durationMilliseconds = Double(endedAt - startedAt) / 1_000_000
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastAToBApplyMillisecondsForTesting = durationMilliseconds
                self.diagnosticLogger.log(
                    category: "configuration",
                    event: "A_TO_B_MAPPING_APPLY",
                    key: receiverB,
                    fields: [
                        "A_TO_B_APPLY_MS": durationMilliseconds,
                        "success": succeeded,
                        "generation": generation,
                    ]
                )
                guard self.dualReceiverMappedTriggerState.phase == .armingSecondary(
                    gestureID: gestureID,
                    generation: generation
                ) else {
                    return
                }
                guard succeeded else {
                    self.restorePrimaryMappingAfterSecondary(
                        gestureID: gestureID,
                        reason: "secondary-mapping-apply-failed"
                    )
                    return
                }
                guard self.filter.configureVoiceTriggerKey(receiverB) else {
                    self.diagnosticLogger.log(
                        category: "configuration",
                        event: "A_TO_B_FILTER_COMMIT_FAILED",
                        key: receiverB,
                        fields: ["generation": generation]
                    )
                    self.restorePrimaryMappingAfterSecondary(
                        gestureID: gestureID,
                        reason: "secondary-filter-configure-failed"
                    )
                    return
                }
                self.filter.endVoiceTriggerReconfiguration()
                self.dualReceiverReconfigurationGateActive = false
                self.voiceTriggerReconfigurationInProgress = false
                guard self.dualReceiverMappedTriggerState.completeSecondaryArming(
                    gestureID: gestureID,
                    generation: generation
                ) else {
                    self.restorePrimaryMappingAfterSecondary(
                        gestureID: gestureID,
                        reason: "secondary-arm-generation-stale"
                    )
                    return
                }
                self.diagnosticLogger.log(
                    category: "configuration",
                    event: "B_MAPPING_READY",
                    key: receiverB,
                    fields: [
                        "filter_key": self.filter.voiceTriggerKey.rawValue,
                        "generation": generation,
                    ]
                )
                let readinessMilliseconds = max(
                    0,
                    ProcessInfo.processInfo.systemUptime - firstUpAt
                ) * 1_000
                self.lastFirstUpToSecondaryReadyMillisecondsForTesting = readinessMilliseconds
                self.diagnosticLogger.log(
                    category: "configuration",
                    event: "SECONDARY_READY_TIMING",
                    gestureID: gestureID,
                    key: receiverB,
                    fields: [
                        "FIRST_UP_TO_SECONDARY_READY_MS": readinessMilliseconds,
                        "A_TO_B_APPLY_MS": self.lastAToBApplyMillisecondsForTesting ?? -1,
                        "generation": generation,
                    ]
                )
            }
        }
    }

    private func restorePrimaryMappingAfterSecondary(
        gestureID: UUID,
        reason: String,
        keepDualModeLocked: Bool = false
    ) {
        let primaryKey = currentMomentaryVoiceTriggerKey
        let generation = dualReceiverMappedTriggerState.beginPrimaryRestore()
        if !dualReceiverReconfigurationGateActive {
            guard filter.beginVoiceTriggerReconfiguration(
                from: filter.voiceTriggerKey,
                to: primaryKey
            ) else {
                voiceTriggerRuntimeLocked = true
                voiceTriggerReconfigurationInProgress = true
                dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
                _ = dualReceiverMappedTriggerState.completePrimaryRestore(
                    generation: generation,
                    succeeded: false
                )
                return
            }
            dualReceiverReconfigurationGateActive = true
            voiceTriggerReconfigurationInProgress = true
        }
        diagnosticLogger.log(
            category: "configuration",
            event: "B_TO_A_RESTORE_BEGIN",
            key: primaryKey,
            fields: ["reason": reason, "generation": generation]
        )
        voiceHIDMappingQueue.async { [weak self] in
            guard let self else { return }
            let mappingStartedAt = P1A4MonotonicClock.nowNanoseconds()
            let succeeded = self.applyVoiceHIDMapping(true, primaryKey)
            let mappingEndedAt = P1A4MonotonicClock.nowNanoseconds()
            let durationMilliseconds = Double(mappingEndedAt - mappingStartedAt) / 1_000_000
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.dualReceiverMappedTriggerState.phase
                    == .restoringPrimary(generation: generation) else {
                    self.diagnosticLogger.log(
                        category: "configuration",
                        event: "B_TO_A_RESTORE_STALE_COMPLETION",
                        gestureID: gestureID,
                        key: primaryKey,
                        fields: [
                            "generation": generation,
                            "current_generation": self.dualReceiverMappedTriggerState.generation,
                            "mapping_success": succeeded,
                        ]
                    )
                    return
                }
                let filterRestored = succeeded
                    && self.filter.configureVoiceTriggerKey(primaryKey)
                let restored = succeeded && filterRestored
                self.lastBToAApplyMillisecondsForTesting = durationMilliseconds
                self.diagnosticLogger.log(
                    category: "configuration",
                    event: "B_TO_A_MAPPING_APPLY",
                    key: primaryKey,
                    fields: [
                        "B_TO_A_APPLY_MS": durationMilliseconds,
                        "success": succeeded,
                        "generation": generation,
                    ]
                )
                _ = self.dualReceiverMappedTriggerState.completePrimaryRestore(
                    generation: generation,
                    succeeded: restored
                )
                self.diagnosticLogger.log(
                    category: "configuration",
                    event: restored ? "B_TO_A_RESTORE_COMMIT" : "B_TO_A_RESTORE_FAILED",
                    key: primaryKey,
                    fields: [
                        "reason": reason,
                        "gesture_id": gestureID.uuidString,
                        "generation": generation,
                        "mapping_success": succeeded,
                        "filter_success": filterRestored,
                    ]
                )
                guard restored else {
                    self.voiceTriggerRuntimeLocked = true
                    self.voiceTriggerReconfigurationInProgress = true
                    self.dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
                    return
                }
                self.filter.endVoiceTriggerReconfiguration()
                self.dualReceiverReconfigurationGateActive = false
                self.voiceTriggerReconfigurationInProgress = false
                if keepDualModeLocked {
                    self.dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
                    self.dualReceiverMappedTriggerState.markUnavailable(
                        reason: .mappingApplyFailed
                    )
                }
            }
        }
    }

    /// Re-establish A only after the mapped B-up has passed the filter. The
    /// main-queue hop runs after the event-tap pass acknowledgement commits.
    func handleDualReceiverHardwareOutputDrainClosed(
        gestureID: UUID,
        outputDrainCompleted: Bool = true
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.dualReceiverMappedTriggerState.phase
                    == .secondaryActive(gestureID: gestureID) else {
                return
            }
            guard self.filter.pendingReplayedHardwareOptionUpGestureID != gestureID else {
                return
            }
            let coordinatorOwnershipActive = self.voicePress
                .hasReleaseOrTailOwnershipForReconfiguration
            let filterOwnershipActive = self.filter.hasActiveHardwareTriggerOwnership
                || self.filter.hasSyntheticTriggerOwnership
            guard outputDrainCompleted
                    || (!coordinatorOwnershipActive && !filterOwnershipActive) else {
                return
            }
            guard !self.filter.hasActiveHardwareTriggerOwnership,
                  !self.filter.hasSyntheticTriggerOwnership,
                  !self.voicePress.hasReleaseOrTailOwnershipForReconfiguration else {
                self.voiceTriggerRuntimeLocked = true
                self.voiceTriggerReconfigurationInProgress = true
                self.dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
                self.dualReceiverMappedTriggerState.markUnavailable(
                    reason: .primaryRestoreFailed
                )
                self.diagnosticLogger.log(
                    category: "configuration",
                    event: "B_TO_A_RESTORE_FAILED",
                    gestureID: gestureID,
                    key: self.currentMomentaryVoiceTriggerKey,
                    fields: [
                        "reason": "secondary-output-ownership-not-closed",
                        "hardware_owner_active": self.filter.hasActiveHardwareTriggerOwnership,
                        "synthetic_owner_active": self.filter.hasSyntheticTriggerOwnership,
                    ]
                )
                return
            }
            self.restorePrimaryMappingAfterSecondary(
                gestureID: gestureID,
                reason: "secondary-output-drained"
            )
        }
    }

    private func handleSecondaryMappingReadback(
        gestureID: UUID,
        generation: UInt64,
        receiverB: VoiceTriggerKey,
        verification: VoiceDiagnosticHIDVerification
    ) {
        guard dualReceiverMappedTriggerState.generation == generation else { return }
        guard verification != .match else { return }
        let fields: [String: Any] = [
            "verification": verification.rawValue,
            "generation": generation,
            "filter_key": filter.voiceTriggerKey.rawValue,
        ]
        diagnosticLogger.log(
            category: "configuration",
            event: "B_MAPPING_READBACK_MISMATCH",
            gestureID: gestureID,
            key: receiverB,
            fields: fields
        )
        voiceTriggerRuntimeLocked = true
        dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
        switch dualReceiverMappedTriggerState.phase {
        case .secondaryReady:
            restorePrimaryMappingAfterSecondary(
                gestureID: gestureID,
                reason: "secondary-readback-\(verification.rawValue.lowercased())",
                keepDualModeLocked: true
            )
        case .armingSecondary:
            restorePrimaryMappingAfterSecondary(
                gestureID: gestureID,
                reason: "secondary-readback-\(verification.rawValue.lowercased())-before-commit",
                keepDualModeLocked: true
            )
        case .secondaryActive, .restoringPrimary, .blockedUntilRelease,
             .primaryReady, .unavailable:
            break
        }
    }

    private func cancelPendingDualReceiverPrewarm() {
        guard dualReceiverPrewarmGestureID != nil else { return }
        dualReceiverPrewarmGestureID = nil
        cancelVoiceTransportPreparation()
    }

    private func dualReceiverReadinessFailure()
        -> DualReceiverVoiceMode.UnavailabilityReason? {
        guard rawHIDReadiness?() ?? hidMonitor.isRunning else {
            return .rawHIDUnavailable
        }
        guard eventSuppressorReadiness?() ?? hidMonitor.eventSuppressor.isRunning else {
            return .eventSuppressorUnavailable
        }
        return nil
    }

    private func prepareVoiceTransport() {
        VoiceAttemptDiagnostics.shared.stage("TRANSPORT_PREWARM_REQUEST")
        if let prepareVoiceTransportAction {
            prepareVoiceTransportAction()
        } else {
            ble.prepareVoiceTransport()
        }
    }

    private func activateVoiceInput() {
        VoiceAttemptDiagnostics.shared.stage("VOICE_INPUT_ACTIVATION")
        if let activateVoiceInputAction {
            activateVoiceInputAction()
        } else {
            ble.activateVoiceInput()
        }
    }

    private func cancelVoiceTransportPreparation() {
        if let cancelVoiceTransportPreparationAction {
            cancelVoiceTransportPreparationAction()
        } else {
            ble.cancelVoiceTransportPreparation()
        }
    }

    private func stopVoiceInput() {
        if let stopVoiceInputAction {
            stopVoiceInputAction()
        } else {
            ble.stopVoiceInput()
        }
    }

    func cancelDualReceiverGestureStateForHIDRemoval() {
        hidConnected = false
        voicePress.cancelLongOnlyCandidateForHIDRemoval()
        if let pendingReplayGestureID = filter.pendingReplayedHardwareOptionUpGestureID {
            filter.cancelDeferredOption(
                gestureID: pendingReplayGestureID,
                reason: "hid-removed"
            )
        }
        if let pendingGestureID = dualReceiverPrewarmGestureID {
            _ = voicePress.cancelClassifiedHardwareGate(sessionID: pendingGestureID)
        }
        dualReceiverVoiceGestureRecognizer.cancel()
        cancelPendingDualReceiverPrewarm()
        dualReceiverPhysicalDownAt = nil
        activeDualReceiverGestureID = nil
        if dualReceiverVoiceMode != .legacy {
            dualReceiverMappedTriggerState.markUnavailable(reason: .dualModeUnavailable)
            dualReceiverVoiceMode = .unavailable(.rawHIDUnavailable)
            pendingVoiceHIDMappingRefresh = false
            if dualReceiverReconfigurationGateActive {
                filter.endVoiceTriggerReconfiguration()
                dualReceiverReconfigurationGateActive = false
                voiceTriggerReconfigurationInProgress = false
            }
        }
    }

    func applyPersistentSessionTriggerKey(
        _ newKey: VoiceTriggerKey,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(.locked)
                    return
                }
                self.applyPersistentSessionTriggerKey(newKey, completion: completion)
            }
            return
        }
        let oldKey = currentPersistentSessionTriggerKey
        diagnosticLogger.log(
            category: "configuration",
            event: "PERSISTENT_RECONFIG_REQUEST",
            key: newKey,
            fields: [
                "old": oldKey.rawValue,
                "new": newKey.rawValue,
                "session_mode": voicePress.persistentSessionActiveForTesting ? "persistent_open" : "idle",
                "session_owner": voicePress.persistentSessionTriggerOwnerKeyForTesting?.rawValue ?? "none",
            ]
        )
        guard !voiceTriggerRuntimeLocked else {
            logReconfigurationBusy(reason: "runtime_locked", event: "PERSISTENT_RECONFIG_REJECTED")
            completion(.locked)
            return
        }
        guard !voiceTriggerReconfigurationInProgress else {
            logReconfigurationBusy(reason: "reconfiguration_busy", event: "PERSISTENT_RECONFIG_REJECTED")
            completion(.busy)
            return
        }
        guard newKey != oldKey else {
            completion(.unchanged)
            return
        }
        if let busy = voiceConfigurationBusyResult() {
            logReconfigurationBusy(reason: applyResultReason(busy), event: "PERSISTENT_RECONFIG_REJECTED")
            completion(busy)
            return
        }
        guard voicePress.configurePersistentSessionTriggerKey(newKey) else {
            logReconfigurationBusy(reason: "reconfiguration_busy", event: "PERSISTENT_RECONFIG_REJECTED")
            completion(.busy)
            return
        }
        currentPersistentSessionTriggerKey = newKey
        persistPersistentSessionTriggerKey(newKey)
        diagnosticLogger.log(
            category: "configuration",
            event: "PERSISTENT_RECONFIG_COMMIT",
            key: newKey,
            fields: [
                "old": oldKey.rawValue,
                "new": newKey.rawValue,
                "configured_key_changed": true,
                "session_owner": voicePress.persistentSessionTriggerOwnerKeyForTesting?.rawValue ?? "none",
                "open_owner_unchanged": voicePress.persistentSessionActiveForTesting,
            ]
        )
        completion(.applied)
    }

    /// Runtime key changes are initiated on the main run loop so the EventTap
    /// can enforce its bounded suppression gate while hidutil runs off-thread.
    /// The completion is called on the main run loop for every result.
    func applyVoiceTriggerKey(
        _ newKey: VoiceTriggerKey,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(.locked)
                    return
                }
                self.applyVoiceTriggerKey(newKey, completion: completion)
            }
            return
        }

        let oldKey = currentMomentaryVoiceTriggerKey
        diagnosticLogger.log(
            category: "configuration",
            event: "MOMENTARY_RECONFIG_REQUEST",
            key: newKey,
            fields: [
                "old": oldKey.rawValue,
                "new": newKey.rawValue,
                "hid_connected": hidConnected,
                "mapping_enabled": RemoteVoiceKeyMapping.isEnabled,
            ]
        )
        guard !voiceTriggerRuntimeLocked else {
            logReconfigurationBusy(reason: "runtime_locked", event: "MOMENTARY_RECONFIG_REJECTED")
            completion(.locked)
            return
        }
        guard !voiceTriggerReconfigurationInProgress else {
            logReconfigurationBusy(reason: "reconfiguration_busy", event: "MOMENTARY_RECONFIG_REJECTED")
            completion(.busy)
            return
        }
        guard newKey != oldKey else {
            completion(.unchanged)
            return
        }
        if let busy = voiceConfigurationBusyResult() {
            logReconfigurationBusy(reason: applyResultReason(busy), event: "MOMENTARY_RECONFIG_REJECTED")
            completion(busy)
            return
        }
        let dualShortBinding = currentDualReceiverShortBinding
            ?? mappingStore.binding(for: .microphone)
        let requestedDualMode = DualReceiverVoiceMode.evaluate(
            shortIsDisabled: dualShortBinding.isDisabled,
            receiverA: newKey,
            receiverB: currentSecondaryMomentaryVoiceTriggerKey,
            rawHIDReady: rawHIDReadiness?() ?? hidMonitor.isRunning,
            eventSuppressorReady: eventSuppressorReadiness?()
                ?? hidMonitor.eventSuppressor.isRunning,
            primaryMappingSucceeded: true
        )
        let hadHardwareMapping = isVoiceHIDMappingEnabled()
        guard filter.beginVoiceTriggerReconfiguration(from: oldKey, to: newKey) else {
            logReconfigurationBusy(reason: "reconfiguration_busy", event: "MOMENTARY_RECONFIG_REJECTED")
            completion(.busy)
            return
        }
        voiceTriggerReconfigurationInProgress = true
        diagnosticLogger.log(
            category: "configuration",
            event: "FILTER_RECONFIG_BEGIN",
            key: newKey,
            fields: ["old": oldKey.rawValue, "new": newKey.rawValue]
        )

        guard filter.configureVoiceTriggerKey(newKey) else {
            filter.endVoiceTriggerReconfiguration()
            voiceTriggerReconfigurationInProgress = false
            logReconfigurationBusy(reason: "reconfiguration_busy", event: "MOMENTARY_RECONFIG_REJECTED")
            completion(.busy)
            return
        }
        diagnosticLogger.log(
            category: "configuration",
            event: "FILTER_RECONFIG_COMMIT",
            key: newKey,
            fields: [
                "filter_key": filter.momentaryVoiceTriggerKey.rawValue,
                "synthetic_key": voicePress.diagnosticStateFields["momentary_config"] as? String ?? "unknown",
            ]
        )

        guard hidConnected else {
            currentMomentaryVoiceTriggerKey = newKey
            persistVoiceTriggerKey(newKey)
            // A disconnected receiver cannot begin a raw-HID dual transaction.
            // Establish the primary mapping when the device announces itself.
            dualReceiverVoiceMode = .legacy
            completeVoiceTriggerReconfiguration(.applied, completion: completion)
            return
        }

        voiceHIDMappingQueue.async { [weak self] in
            guard let self else { return }
            let succeeded = self.applyVoiceHIDMapping(true, newKey)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard succeeded else {
                    if requestedDualMode != .legacy {
                        self.dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
                        self.rollbackVoiceTriggerApply(
                            oldKey: oldKey,
                            hadHardwareMapping: hadHardwareMapping,
                            completion: completion
                        )
                        return
                    }
                    self.rollbackVoiceTriggerApply(
                        oldKey: oldKey,
                        hadHardwareMapping: hadHardwareMapping,
                        completion: completion
                    )
                    return
                }
                self.currentMomentaryVoiceTriggerKey = newKey
                self.persistVoiceTriggerKey(newKey)
                self.dualReceiverVoiceMode = requestedDualMode
                print("[VOICE-KEY] runtime target committed=\(newKey.displayName)")
                self.completeVoiceTriggerReconfiguration(.applied, completion: completion)
            }
        }
    }

    func applyVoiceInputProfile(
        _ profile: VoiceInputProfile,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        applyVoiceTriggerKey(profile.triggerKey) { [weak self] result in
            guard let self else {
                completion(.locked)
                return
            }
            if result == .applied || result == .unchanged {
                self.currentVoiceInputProfile = profile
                VoiceInputProfileStore.writeSelectedProfile(profile, to: UserDefaults.standard)
            }
            completion(result)
        }
    }

    private func voiceConfigurationBusyResult() -> VoiceTriggerApplyResult? {
        switch dualReceiverMappedTriggerState.phase {
        case .armingSecondary, .secondaryReady:
            return .busy
        case .secondaryActive:
            return .busyActiveHold
        case .restoringPrimary, .blockedUntilRelease:
            return .busyReleaseDrain
        case .primaryReady, .unavailable:
            break
        }
        if dualReceiverVoiceGestureRecognizer.isBusy {
            return .busyActiveHold
        }
        if voicePress.hasVoiceKeyHeldForReconfiguration || filter.isVoiceKeyHeld {
            return .busyActiveHold
        }
        if voicePress.hasReleaseOrTailOwnershipForReconfiguration
            || filter.hasActiveHardwareTriggerOwnership
            || filter.isSyntheticTriggerDown
            || filter.hasSyntheticTriggerOwnership {
            return .busyReleaseDrain
        }
        return nil
    }

    private var dualReceiverVoiceOwnership: DualReceiverVoiceOwnership {
        if voiceTriggerReconfigurationInProgress || voiceTriggerRuntimeLocked {
            return .runtimeReconfiguration
        }
        switch dualReceiverMappedTriggerState.phase {
        case .armingSecondary, .secondaryReady:
            return .waitingSecondTap
        case .secondaryActive:
            return .activeTransaction
        case .restoringPrimary, .blockedUntilRelease:
            return .runtimeReconfiguration
        case .primaryReady, .unavailable:
            break
        }
        switch dualReceiverVoiceGestureRecognizer.stateForTesting {
        case .idle:
            break
        case .firstPressPending:
            return .firstTapPending
        case .awaitingSecondPress:
            return .waitingSecondTap
        case .secondPressPending, .activeA, .activeB:
            return .activeTransaction
        }
        if voicePress.hasVoiceKeyHeldForReconfiguration {
            return .activeTransaction
        }
        if filter.isVoiceKeyHeld || filter.hasActiveHardwareTriggerOwnership {
            return .physicalRelease
        }
        if voicePress.hasReleaseOrTailOwnershipForReconfiguration
            || filter.isSyntheticTriggerDown
            || filter.hasSyntheticTriggerOwnership {
            return .outputDrain
        }
        return .idle
    }

    private func rollbackVoiceTriggerApply(
        oldKey: VoiceTriggerKey,
        hadHardwareMapping: Bool,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        diagnosticLogger.log(
            category: "configuration",
            event: "MOMENTARY_RECONFIG_ROLLBACK_BEGIN",
            key: oldKey,
            fields: ["requested_key": currentMomentaryVoiceTriggerKey.rawValue]
        )
        print("[VOICE-KEY] new HID mapping failed; rolling back to \(oldKey.displayName)")
        let localRollbackSucceeded = filter.configureVoiceTriggerKey(oldKey)
        guard hadHardwareMapping else {
            guard localRollbackSucceeded else {
                lockVoiceTriggerRuntime(reason: "local rollback failed")
                completion(.locked)
                return
            }
            completeVoiceTriggerReconfiguration(.failed, completion: completion)
            return
        }

        voiceHIDMappingQueue.async { [weak self] in
            guard let self else { return }
            let hidRollbackSucceeded = self.applyVoiceHIDMapping(true, oldKey)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard localRollbackSucceeded && hidRollbackSucceeded else {
                    self.lockVoiceTriggerRuntime(
                        reason: localRollbackSucceeded
                            ? "old HID mapping rollback failed"
                            : "local and HID rollback did not both succeed"
                    )
                    completion(.locked)
                    return
                }
                print("[VOICE-KEY] rollback restored target=\(oldKey.displayName)")
                self.completeVoiceTriggerReconfiguration(.failed, completion: completion)
            }
        }
    }

    private func lockVoiceTriggerRuntime(reason: String) {
        voiceTriggerRuntimeLocked = true
        voiceTriggerReconfigurationInProgress = true
        print("[VOICE-KEY] runtime locked; reconfiguration gate remains active: \(reason)")
        var fields = voicePress.diagnosticStateFields
        fields.merge(filter.diagnosticStateFields) { _, new in new }
        fields["reason"] = reason
        diagnosticLogger.log(
            category: "configuration",
            event: "MOMENTARY_RUNTIME_LOCKED",
            fields: fields
        )
    }

    private func completeVoiceTriggerReconfiguration(
        _ result: VoiceTriggerApplyResult,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        guard !voiceTriggerRuntimeLocked else {
            completion(.locked)
            return
        }
        guard pendingVoiceHIDMappingRefresh else {
            voiceTriggerReconfigurationInProgress = false
            filter.endVoiceTriggerReconfiguration()
            logMomentaryReconfigurationFinish(result)
            completion(result)
            return
        }

        pendingVoiceHIDMappingRefresh = false
        let shortBinding = currentDualReceiverShortBinding
            ?? mappingStore.binding(for: .microphone)
        let refreshedDualMode: DualReceiverVoiceMode = hidConnected
            ? DualReceiverVoiceMode.evaluate(
                shortIsDisabled: shortBinding.isDisabled,
                receiverA: currentMomentaryVoiceTriggerKey,
                receiverB: currentSecondaryMomentaryVoiceTriggerKey,
                rawHIDReady: rawHIDReadiness?() ?? hidMonitor.isRunning,
                eventSuppressorReady: eventSuppressorReadiness?()
                    ?? hidMonitor.eventSuppressor.isRunning,
                primaryMappingSucceeded: true
            )
            : .legacy
        let shouldEnable = hidConnected
        let target = currentMomentaryVoiceTriggerKey
        voiceHIDMappingQueue.async { [weak self] in
            guard let self else { return }
            let succeeded = self.applyVoiceHIDMapping(shouldEnable, target)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if shouldEnable && !succeeded {
                    if refreshedDualMode != .legacy {
                        self.dualReceiverVoiceMode = .unavailable(.primaryMappingFailed)
                    } else {
                        print("[HID-MAP] reconnect mapping failed; synthetic fallback remains available")
                    }
                } else if succeeded {
                    self.dualReceiverVoiceMode = refreshedDualMode
                }
                if self.pendingVoiceHIDMappingRefresh {
                    self.completeVoiceTriggerReconfiguration(result, completion: completion)
                    return
                }
                self.voiceTriggerReconfigurationInProgress = false
                self.filter.endVoiceTriggerReconfiguration()
                self.logMomentaryReconfigurationFinish(result)
                completion(result)
            }
        }
    }

    private func applyResultReason(_ result: VoiceTriggerApplyResult) -> String {
        switch result {
        case .busyActiveHold: "active_hold"
        case .busyReleaseDrain: "release_drain"
        case .locked: "runtime_locked"
        case .busy: "reconfiguration_busy"
        case .applied, .unchanged, .failed: "unknown"
        }
    }

    private func logReconfigurationBusy(reason: String, event: String) {
        var fields = voicePress.diagnosticStateFields
        fields.merge(filter.diagnosticStateFields) { _, new in new }
        fields["reason"] = reason
        diagnosticLogger.log(
            category: "configuration",
            event: "VOICE_RECONFIG_BUSY",
            fields: fields
        )
        diagnosticLogger.log(
            category: "configuration",
            event: event,
            fields: fields
        )
    }

    private func logMomentaryReconfigurationFinish(_ result: VoiceTriggerApplyResult) {
        guard result == .applied || result == .failed else { return }
        let event = result == .applied
            ? "MOMENTARY_RECONFIG_COMMIT" : "MOMENTARY_RECONFIG_ROLLBACK_COMMIT"
        diagnosticLogger.log(
            category: "configuration",
            event: event,
            key: currentMomentaryVoiceTriggerKey,
            fields: [
                "controller": currentMomentaryVoiceTriggerKey.rawValue,
                "filter": filter.momentaryVoiceTriggerKey.rawValue,
                "synthetic": voicePress.diagnosticStateFields["momentary_config"] as? String ?? "unknown",
                "persisted": readPersistedVoiceTriggerKey().rawValue,
                "hid_connected": hidConnected,
                "mapping_enabled": RemoteVoiceKeyMapping.isEnabled,
            ]
        )
    }

    static func bypassesShortClassification(for binding: ButtonBinding) -> Bool {
        false
    }

    /// Focus work is part of the public direct opening lifecycle, never the
    /// private DOWN-to-300ms candidate. The target is the identity captured at
    /// physical DOWN, so promotion cannot retarget an already-held gesture.
    private func beginVoiceFocusPreparation(
        gestureID: UUID,
        targetApplicationBundleIdentifier target: String?
    ) {
        let needsFloatTabsFocus = FloatTabsCommandClient.shouldPrepareInputFocus(
            for: target
        )
        let needsCodexFocus = !needsFloatTabsFocus
            && CodexCommandAdapter.shouldPrepareInputFocus(for: target)
        guard needsFloatTabsFocus || needsCodexFocus else { return }

        if let previousGestureID = voiceFocusTransactions.activeGestureID {
            voiceFocusSafetyWorkItem?.cancel()
            voiceFocusSafetyWorkItem = nil
            _ = voiceFocusTransactions.cancel(previousGestureID)
        }
        voiceFocusTransactions.begin(gestureID)
        armVoiceFocusSafetyTimeout(gestureID: gestureID)
        print(
            "[VOICE] focus transaction started gesture=\(gestureID.uuidString) "
                + "target=\(target ?? "unknown")"
        )

        if needsFloatTabsFocus {
            let requested = FloatTabsCommandClient.requestInputFocusForVoice(
                gestureID: gestureID
            ) { [weak self] ready, reason in
                self?.completeVoiceFocus(
                    gestureID: gestureID,
                    ready: ready,
                    source: "FloatTabs",
                    reason: reason
                )
            }
            if !requested {
                completeVoiceFocus(
                    gestureID: gestureID,
                    ready: false,
                    source: "FloatTabs",
                    reason: "request-rejected"
                )
            }
            return
        }

        CodexCommandAdapter.prepareInputFocusForVoice { [weak self] ready, reason in
            self?.completeVoiceFocus(
                gestureID: gestureID,
                ready: ready,
                source: "Codex",
                reason: reason
            )
        }
    }

    func beginVoicePress(
        targetApplicationBundleIdentifier lockedTarget: String? = nil,
        shortBinding: ButtonBinding? = nil,
        source: VoicePressInputSource = .voiceKeyFilterFallback
    ) {
        guard !voiceTriggerReconfigurationInProgress,
              !voiceTriggerRuntimeLocked else {
            print("[VOICE] press rejected during trigger reconfiguration or runtime lock")
            return
        }
        let gestureID = UUID()
        let occurrenceUptime = diagnosticUptimeProvider()
        let hidConnectedAtEntry = hidConnected
        let filterSkipVoiceKeyAtEntry = filter.skipVoiceKey
        let momentaryKeyAtEntry = currentMomentaryVoiceTriggerKey
        let target = lockedTarget
            ?? MappingStore.preferredApplicationBundleIdentifier()
        let pressAccepted = voicePress.keyDown(
            sessionID: gestureID,
            usesHardwareOption: isVoiceHIDMappingEnabled(),
            preparesRemoteTransport: true,
            profile: currentVoiceInputProfile,
            directSession: true,
            longOnlyAdmission: true,
            targetApplicationBundleIdentifier: target
        )
        diagnosticLogger.log(
            category: "voice",
            event: "VOICE_PRESS_ENTRY",
            gestureID: gestureID,
            fields: [
                "source": source.rawValue,
                "hid_connected": hidConnectedAtEntry,
                "filter_skip_voice_key": filterSkipVoiceKeyAtEntry,
                "observer_uptime": occurrenceUptime,
                "momentary_key": momentaryKeyAtEntry.rawValue,
                "voice_input_profile_id": currentVoiceInputProfile.id,
                "voice_input_trigger_key": currentVoiceInputProfile.triggerKey.rawValue,
                "classifier": "none",
            ]
        )
        guard pressAccepted else {
            return
        }

        // Hardware activation already supersedes an older gate inside
        // beginOptionDeferral. Only the synthetic fallback needs the
        // coordinator call site to clear a stale physical gate here.
        if !isVoiceHIDMappingEnabled() {
            filter.cancelActiveOptionDeferral(reason: "superseded-by-new-gesture")
        }
    }

    private func recordVoiceReleaseEntry(
        source: VoicePressInputSource,
        gestureID: UUID?,
        occurrenceUptime: TimeInterval
    ) {
        diagnosticLogger.log(
            category: "voice",
            event: "VOICE_RELEASE_ENTRY",
            gestureID: gestureID,
            fields: [
                "source": source.rawValue,
                "observer_uptime": occurrenceUptime,
            ]
        )
    }

    func finishVoicePressRelease(
        source: VoicePressInputSource,
        stopVoiceInput: () -> Void
    ) {
        let gestureID = voicePress.currentGestureIDForDiagnostics
        let occurrenceUptime = diagnosticUptimeProvider()
        let shouldStopVoiceInput = voicePress.keyUp()
        if shouldStopVoiceInput {
            stopVoiceInput()
        }
        recordVoiceReleaseEntry(
            source: source,
            gestureID: gestureID,
            occurrenceUptime: occurrenceUptime
        )
    }

    private func handleVoiceShortTap(
        _ binding: ButtonBinding,
        targetApplicationBundleIdentifier target: String?
    ) {
        if handleContextualAction(
            binding,
            button: .microphone,
            gesture: "单击"
        ) {
            return
        }
        let sent = KeyInjector.send(
            binding,
            targetApplicationBundleIdentifier: target,
            scrollLinesPerStep: mappingStore.scrollLinesPerStep
        )
        print("[KEY] 语音键 short → \(binding.displayName); sent=\(sent)")
        actionHUD.show(
            button: .microphone,
            gesture: "单击",
            action: binding.hudDisplayName,
            state: actionHUDState(
                for: binding,
                targetApplicationBundleIdentifier: target,
                sent: sent
            )
        )
    }

    private func armVoiceFocusSafetyTimeout(gestureID: UUID) {
        voiceFocusSafetyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.completeVoiceFocus(
                gestureID: gestureID,
                ready: false,
                source: "safety",
                reason: "transaction-timeout"
            )
        }
        voiceFocusSafetyWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + voiceFocusSafetyTimeout,
            execute: work
        )
    }

    private func updateVoiceHUD(for state: VoicePressCoordinator.State) {
        guard let hudState = VoiceHUDProjection.state(
            for: state,
            remoteAudioAvailable: voicePress.hasRemoteAudio,
            receiverReadiness: lastReceiverReadiness
        ) else {
            actionHUD.dismiss()
            return
        }
        if state == .pending, !voicePress.shouldShowPendingVoiceUI {
            actionHUD.dismiss()
            return
        }
        let isDraining = state == .draining
        actionHUD.show(
            button: .microphone,
            gesture: isDraining ? "松开" : state == .opening ? "按下" : "按住",
            action: isDraining ? "语音收尾中" : "遥控器语音输入",
            state: hudState,
            keepsVisible: true
        )
    }

    private func completeVoiceFocus(
        gestureID: UUID,
        ready: Bool,
        source: String,
        reason: String
    ) {
        guard voiceFocusTransactions.complete(gestureID) else {
            print(
                "[VOICE] ignored stale focus result gesture=\(gestureID.uuidString) "
                    + "source=\(source) ready=\(ready) reason=\(reason)"
            )
            return
        }
        voiceFocusSafetyWorkItem?.cancel()
        voiceFocusSafetyWorkItem = nil
        print(
            "[VOICE] focus transaction completed gesture=\(gestureID.uuidString) "
                + "source=\(source) ready=\(ready) reason=\(reason)"
        )
        print(
            "[VOICE] focus result is advisory; Option source and ownership "
                + "remain fixed for gesture=\(gestureID.uuidString)"
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppStorage.prepare()
        DiagnosticRuntimeHealthService.shared.start()
        if let input = SystemAudioDeviceManager.defaultInputDevice {
            DiagnosticRuntimeHealthRegistry.shared.setString(
                "selected_input_identity",
                input.stableIdentifier
            )
        }
        var runStartFields = P1A4MonotonicClock.runStartCalibrationFields()
        runStartFields["persisted_persistent"] = readPersistedPersistentSessionTriggerKey().rawValue
        runStartFields["persisted_momentary"] = readPersistedVoiceTriggerKey().rawValue
        runStartFields["persisted_legacy"] = UserDefaults.standard.string(
            forKey: AppStorage.voiceTriggerKeyKey
        ) ?? "none"
        diagnosticLogger.startRun(fields: runStartFields)
        _ = restoreVoiceTriggerRuntime()
        if ProcessInfo.processInfo.environment["REMOTE_ORBIT_DIAGNOSTICS"] == "1" {
            let sourceHead = Bundle.main.object(
                forInfoDictionaryKey: "RemoteOrbitDiagnosticSourceHead"
            ) as? String ?? "UNSTAMPED"
            let receiverFinalizationInstrumentation =
                ProcessInfo.processInfo.environment["REMOTE_ORBIT_P1A4_RECEIVER_FINALIZATION"] == "1"
            let frontEdgeInstrumentation =
                ProcessInfo.processInfo.environment["REMOTE_ORBIT_P1A5_FRONT_EDGE"] == "1"
            let instrumentation = frontEdgeInstrumentation
                ? "p1-a5-front-edge"
                : receiverFinalizationInstrumentation
                ? "p1-a4-receiver-finalization"
                : "p0"
            print(
                "[AUDIO-PATH] DIAGNOSTIC_BUILD "
                    + "head=\(sourceHead) instrumentation=\(instrumentation)"
            )
            let observer = FrontmostApplicationDiagnosticsObserver()
            observer.start()
            frontmostApplicationDiagnosticsObserver = observer
        }
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
        let buildVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "development"
        print(
            "[APP] launch version=\(appVersion) build=\(buildVersion) "
                + "path=\(Bundle.main.bundlePath) "
                + "FloatTabsProtocol=\(FloatTabsCommandClient.protocolVersion)"
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusIcon(systemName: "exclamationmark.triangle")

        let menu = NSMenu()
        menu.delegate = self
        let brand = NSMenuItem(title: ProductIdentity.name, action: nil, keyEquivalent: "")
        brand.isEnabled = false
        menu.addItem(brand)

        let status = NSMenuItem(title: "状态 · 启动中", action: nil, keyEquivalent: "")
        status.isEnabled = true
        menu.addItem(status)
        statusLabel = status

        let remoteStatus = NSMenuItem(title: "遥控器 · 检查中", action: nil, keyEquivalent: "")
        remoteStatus.isEnabled = true
        menu.addItem(remoteStatus)
        remoteStatusItem = remoteStatus

        let audioStatus = NSMenuItem(title: "语音链路 · 检查中", action: nil, keyEquivalent: "")
        audioStatus.isEnabled = true
        menu.addItem(audioStatus)
        audioStatusItem = audioStatus

        let inputItem = NSMenuItem(title: "输入设备", action: nil, keyEquivalent: "")
        let outputItem = NSMenuItem(title: "输出设备", action: nil, keyEquivalent: "")
        audioInputMenu = NSMenu()
        audioOutputMenu = NSMenu()
        inputItem.submenu = audioInputMenu
        outputItem.submenu = audioOutputMenu
        menu.addItem(inputItem)
        menu.addItem(outputItem)

        let voiceProfileItem = NSMenuItem(title: "语音输入", action: nil, keyEquivalent: "")
        voiceInputProfileMenu = NSMenu()
        voiceProfileItem.submenu = voiceInputProfileMenu
        menu.addItem(voiceProfileItem)
        menu.addItem(.separator())

        let refreshAudioDevices = NSMenuItem(
            title: "刷新设备列表",
            action: #selector(refreshAudioDeviceMenus),
            keyEquivalent: ""
        )
        refreshAudioDevices.target = self
        menu.addItem(refreshAudioDevices)

        menu.addItem(.separator())

        let controlCenter = NSMenuItem(
            title: "打开设置…",
            action: #selector(openKeyMapping),
            keyEquivalent: ","
        )
        controlCenter.target = self
        menu.addItem(controlCenter)

        let quit = NSMenuItem(
            title: "退出 \(ProductIdentity.name)",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        refreshAudioDeviceMenus()
        rebuildVoiceInputProfileMenu()
        updateStatus()

        voicePress.onStateChanged = { [weak self] state in
            if state == .opening {
                // Gate A starts ATVV as soon as the physical voice key goes down.
                self?.activateVoiceInput()
            }
            switch state {
            case .opening, .pending, .holding, .streaming:
                self?.voiceReceiverReadinessMonitor.activate()
            case .draining, .idle:
                self?.lastReceiverReadiness = .inactive
                self?.voiceReceiverReadinessMonitor.deactivate()
            }
            self?.updateVoiceHUD(for: state)
        }
        voicePress.onRemoteAudioChanged = { [weak self] _ in
            guard let self else { return }
            self.updateVoiceHUD(for: self.voicePress.currentStateForTesting)
        }
        voicePress.onHardwareOptionGateBegin = { [weak self] gestureID in
            guard let self else { return }
            self.filter.beginOptionDeferral(gestureID: gestureID)
        }
        voicePress.onHardwareOptionGateBeginResult = { [weak self] gestureID in
            self?.filter.beginLongOnlyOptionDeferral(gestureID: gestureID) ?? false
        }
        voicePress.onHardwareOptionGateBeginDeferredBehindShortDiscard = { [weak self] _ in
            self?.filter.hasShortTapDiscardOwnership ?? false
        }
        voicePress.onHardwareOptionGateShortHandoffBegin = { [weak self] gestureID in
            self?.filter.beginLongOnlySuppressionHandoff(gestureID: gestureID) ?? false
        }
        voicePress.onHardwareOptionGateShortHandoffReleased = { [weak self] gestureID in
            self?.filter.releaseLongOnlySuppressionHandoff(gestureID: gestureID) ?? false
        }
        voicePress.onHardwareOptionGateLongConfirmed = { [weak self] gestureID in
            _ = self?.filter.confirmLongOption(gestureID: gestureID)
        }
        voicePress.onHardwareOptionGateShortDiscard = { [weak self] gestureID in
            self?.filter.discardDeferredHardwareTrigger(
                gestureID: gestureID,
                reason: "short-or-unpromoted-candidate"
            ) ?? false
        }
        voicePress.onHardwareOptionGateLongReady = { [weak self] gestureID in
            self?.filter.releaseDeferredOption(
                gestureID: gestureID,
                reason: "remote-audio-ready"
            )
        }
        voicePress.onHardwareOptionGateSuppressForAudioOnly = { [weak self] gestureID in
            self?.filter.suppressDeferredHardwareTrigger(
                gestureID: gestureID,
                reason: "persistent-ime-audio-only"
            ) ?? false
        }
        voicePress.onHardwareOptionGateResetSuppression = { [weak self] gestureID in
            _ = self?.filter.resetSuppressedHardwareTrigger(
                gestureID: gestureID,
                reason: "explicit-persistent-suppression-reset"
            )
        }
        voicePress.onHardwareOptionGateShortReplay = { [weak self] gestureID in
            self?.filter.releaseDeferredOption(
                gestureID: gestureID,
                reason: "short-configured-trigger"
            )
        }
        voicePress.onPersistentSessionTriggerTap = { [weak self] gestureID, triggerKey, purpose in
            self?.filter.emitPersistentShortTap(
                gestureID: gestureID,
                reason: "persistent-session-toggle",
                triggerKey: triggerKey,
                purpose: purpose
            ) ?? .failed
        }
        voicePress.onDeferredPersistentSessionTriggerTap = { [weak self] gestureID, triggerKey, purpose in
            self?.filter.emitDeferredPersistentShortTap(
                gestureID: gestureID,
                triggerKey: triggerKey,
                purpose: purpose
            ) ?? false
        }
        filter.onSuppressedHardwareTriggerSafelyClosed = { [weak self] ownerID in
            self?.voicePress.suppressedHardwareGateDidClose(ownerID: ownerID)
        }
        filter.onSuppressedHardwareTriggerInvalidated = { [weak self] ownerID, reason in
            self?.voicePress.suppressedHardwareGateWasInvalidated(
                ownerID: ownerID,
                reason: reason
            )
        }
        filter.onLongOnlySuppressionHandoffReady = { [weak self] gestureID in
            self?.voicePress.longOnlyTriggerHandoffDidBecomeReady(sessionID: gestureID)
        }
        filter.onLongOnlySuppressionHandoffInvalidated = { [weak self] gestureID, reason in
            self?.voicePress.longOnlyTriggerHandoffWasInvalidated(
                sessionID: gestureID,
                reason: reason
            )
        }
        voicePress.onHardwareOptionGateCancel = { [weak self] gestureID in
            self?.filter.cancelDeferredOption(
                gestureID: gestureID,
                reason: "gesture-cancelled"
            )
        }
        voicePress.onRemoteTransportPreparation = { [weak self] in
            self?.prepareVoiceTransport()
        }
        voicePress.onRemoteTransportCancellation = { [weak self] in
            self?.cancelVoiceTransportPreparation()
        }
        voicePress.onLongOnlyCandidatePromoted = { [weak self] gestureID, target in
            self?.beginVoiceFocusPreparation(
                gestureID: gestureID,
                targetApplicationBundleIdentifier: target
            )
        }
        voicePress.onRemoteOutputDrain = { _, completion in
            AudioPipe.shared.waitForOutputDrain(completion: completion)
        }
        voicePress.onHardwareOptionGatePhysicalUp = { [weak self] gestureID in
            self?.filter.armHardwareOptionRelease(gestureID: gestureID)
        }
        voicePress.onHardwareOptionGatePendingRepressBegin = { [weak self] gestureID, oldGestureID in
            self?.filter.beginPendingHardwareOptionRepress(
                gestureID: gestureID,
                serializedBehind: oldGestureID
            ) ?? .rejected
        }
        voicePress.onHardwareOptionGatePendingRepressPromote = { [weak self] gestureID in
            self?.filter.promotePendingHardwareOptionRepress(gestureID: gestureID) ?? false
        }
        voicePress.onHardwareOptionGatePendingRepressCancel = { [weak self] gestureID, reason in
            self?.filter.cancelPendingHardwareOptionRepress(
                gestureID: gestureID,
                reason: reason
            )
        }
        filter.onPendingHardwareOptionRepressDownCaptured = { [weak self] gestureID in
            self?.voicePress.pendingHardwareOptionRepressDownCaptured(sessionID: gestureID)
        }
        voicePress.onHardwareOptionGateOutputDrained = { [weak self] gestureID in
            guard let self else { return }
            self.filter.releaseHeldHardwareOption(
                gestureID: gestureID,
                reason: "output-drained"
            )
            let awaitingPassAcknowledgement =
                self.filter.pendingReplayedHardwareOptionUpGestureID == gestureID
            self.voicePress.hardwareOptionGateOutputDrainCompleted(
                sessionID: gestureID,
                awaitingPassAcknowledgement: awaitingPassAcknowledgement
            )
            guard !awaitingPassAcknowledgement else {
                return
            }
            self.handleDualReceiverHardwareOutputDrainClosed(gestureID: gestureID)
        }

        // ATVV audio connection.
        filter.onVoiceKeyDown = { [weak self] in
            self?.beginVoicePress(source: .voiceKeyFilterFallback)
        }
        filter.onVoiceKeyUp = { [weak self] in
            guard let self else { return }
            self.finishVoicePressRelease(source: .voiceKeyFilterFallback) {
                self.ble.stopVoiceInput()
            }
        }
        ble.onConnectionChanged = { [weak self] connected in
            self?.bleConnected = connected
            DiagnosticRuntimeHealthRegistry.shared.setBool("ble_connected", connected)
            if !connected {
                self?.remoteStreaming = false
                // A BLE loss can happen before HID emits the matching key-up.
                // Persistent sessions retain ownership while their current
                // segment drains; any deferred B waits for this callback stack.
                self?.voicePress.handleTransportLoss()
            }
            self?.updateStatus()
        }
        ble.onStreamingChanged = { [weak self] streaming, _ in
            self?.voicePress.setRemoteStreaming(streaming)
            self?.remoteStreaming = streaming
            DiagnosticRuntimeHealthRegistry.shared.setBool("atvv_streaming", streaming)
            self?.updateStatus()
        }
        ble.onPhysicalTransportSuperseded = { [weak self] in
            self?.voicePress.handlePhysicalTransportSupersession()
        }
        ble.onPreHIDPhysicalStreamChanged = { [weak self] streaming, _ in
            self?.voicePress.setPreHIDPhysicalStreaming(streaming)
            self?.remoteStreaming = streaming
            DiagnosticRuntimeHealthRegistry.shared.setBool("atvv_streaming", streaming)
            self?.updateStatus()
        }
        ble.onAudioFrame = { [weak self] in
            self?.voicePress.setRemoteAudioAvailable()
        }

        // Route recognized advanced gestures to the same binding injector as
        // ordinary button actions. Without this callback the recognizer can
        // classify a long press correctly but the selected action is dropped.
        buttonGestureRecognizer.onEvent = { [weak self] event in
            self?.handleGestureEvent(event)
        }

        // HID Monitor：读取遥控器所有按钮的原始 HID 报告
        // HID 设备连接/断开时切换语音键处理路径
        // HIDMonitor is the single IOHIDManager owner. A second status-only
        // manager used to observe the same BLE HID device and could race the
        // real monitor during a supervision-timeout reconnect.
        hidMonitor.onDeviceChange = { [weak self] active in
            guard let self else { return }
            self.filter.skipVoiceKey = active
            self.hidConnected = active
            if !active {
                self.cancelDualReceiverGestureStateForHIDRemoval()
            }
            if self.voiceTriggerReconfigurationInProgress {
                self.pendingVoiceHIDMappingRefresh = true
            } else {
                self.applyVoiceHIDMappingForConnection(active)
            }
            self.updateStatus()
            if !active {
                self.reconnectHeldButtons = Set(
                    RemoteButton.allCases.filter {
                        self.hidMonitor.isButtonDown($0)
                    }
                )
                if !self.reconnectHeldButtons.isEmpty {
                    let names = self.reconnectHeldButtons
                        .map(\.displayName)
                        .sorted()
                    print(
                        "[HID] reconnect hold snapshot: "
                            + names.joined(separator: ", ")
                    )
                }
                // Device removal does not guarantee a final HID report. End
                // the voice segment explicitly and let its drained cleanup
                // reset any trigger suppression owned by the removed device.
                self.voicePress.handleTransportLoss(deviceRemoved: true)
                self.mappingStore.clearPressedBindings()
                self.buttonGestureRecognizer.cancelAll()
                self.repeatGestureHUDButtons.removeAll()
                self.actionHUD.dismiss()
                if let button = self.contextualOverlayButton {
                    if self.reconnectHeldButtons.contains(button) {
                        // A long-held button can outlive the BLE HID link's
                        // supervision timeout. Keep the press-and-hold panel
                        // alive and let the first post-reconnect report decide
                        // whether the physical key was released.
                        print(
                            "[KEYMAP] HID 断开，保留 \(button.displayName) 浮层；"
                                + "等待真实 button up，不合成释放"
                        )
                    } else {
                        // If the panel's source button was not held at the
                        // moment of removal, it is safe to close it. This is
                        // the only disconnect path that dismisses the panel;
                        // a held long press remains tied to release.
                        self.keymapOverlayController.close()
                        self.contextualOverlayButton = nil
                        print(
                            "[KEYMAP] HID 断开且 \(button.displayName) 未按下，"
                                + "隐藏当前快捷映射浮层"
                        )
                    }
                }
            } else if !self.reconnectHeldButtons.isEmpty {
                print("[HID] reconnected; waiting for held-button release")
            }
            if active {
                print("[HID] monitor active → VoiceKeyFilter 跳过语音键")
            } else {
                print("[HID] monitor inactive → VoiceKeyFilter 处理语音键")
            }
        }
        hidMonitor.onButtonEdgeSuppressed = { [weak self] button, isDown in
            if isDown {
                self?.mappingStore.cancelPress(for: button)
            }
            print(
                "[HID] debounce suppressed: \(button.displayName) "
                    + (isDown ? "down" : "up")
            )
        }
        hidMonitor.onButtonEdgeAt = { [weak self] button, isDown, timestamp in
            guard let self else { return }
            // Dismiss before resolving the release mapping. The active
            // template may have changed while the overlay was visible, and a
            // disabled/re-routed release must never strand the panel.
            if !isDown {
                self.dismissContextualOverlay(for: button)
            }
            if self.reconnectHeldButtons.contains(button) {
                if isDown {
                    print(
                        "[HID] \(button.displayName) reconnect re-announcement; "
                            + "ignore as new click"
                    )
                    return
                }
                self.reconnectHeldButtons.remove(button)
                self.dismissContextualOverlay(for: button)
                print("[HID] \(button.displayName) reconnect release recovered")
                return
            }
            let binding: ButtonBinding
            let targetApplicationBundleIdentifier: String?
            if isDown {
                binding = self.mappingStore.beginPress(for: button)
                targetApplicationBundleIdentifier = self.mappingStore
                    .activePressApplicationBundleIdentifier(for: button)
                let profile = self.mappingStore.activePressGestureProfile(for: button)
                if button == .microphone {
                    DiagnosticRuntimeHealthRegistry.shared.setBool(
                        "mapping_enabled",
                        !binding.isDisabled
                    )
                    DiagnosticRuntimeHealthRegistry.shared.setBool("mapping_verified", true)
                    VoiceAttemptDiagnostics.shared.stage(
                        "MAPPING_RESOLVED",
                        state: [
                            "mapping_enabled": .bool(!binding.isDisabled),
                            "mapping_verified": .bool(true),
                        ]
                    )
                }
                if button != .microphone, profile.isEnabled {
                    print(
                        "[GESTURE-ROUTE] " + button.displayName + " down "
                            + "advanced=\(profile.usesAdvancedGestures) "
                            + "long=\(profile.longPressBehavior.rawValue) "
                            + "double=\(profile.doubleTap?.displayName ?? "none") "
                            + "longAction=\(profile.longPress?.displayName ?? "none")"
                    )
                }
                if button != .microphone, profile.usesAdvancedGestures {
                    self.actionHUD.show(
                        button: button,
                        gesture: "识别中",
                        action: "等待确认",
                        state: .pending,
                        keepsVisible: true
                    )
                    self.buttonGestureRecognizer.handleDown(
                        button: button,
                        context: ButtonGestureContext(
                            baseBinding: binding,
                            profile: profile,
                            targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
                        ),
                        at: timestamp
                    )
                    return
                }
            } else {
                targetApplicationBundleIdentifier = self.mappingStore
                    .activePressApplicationBundleIdentifier(for: button)
                let profile = self.mappingStore.activePressGestureProfile(for: button)
                if button != .microphone, profile.isEnabled {
                    print(
                        "[GESTURE-ROUTE] " + button.displayName + " up "
                            + "advanced=\(profile.usesAdvancedGestures) "
                            + "long=\(profile.longPressBehavior.rawValue)"
                    )
                }
                if button != .microphone, profile.usesAdvancedGestures {
                    if profile.longPressBehavior == .repeatWhileHeld,
                       let longPressBinding = profile.longPress,
                       self.shouldCancelFloatTabsScroll(
                           binding: longPressBinding,
                           button: button,
                           targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
                       ) {
                        let sent = FloatTabsCommandClient.send(.cancelScroll)
                        print(
                            "[GESTURE] \(button.displayName) scroll cancel → "
                                + "\(longPressBinding.displayName); sent=\(sent)"
                        )
                    }
                    self.buttonGestureRecognizer.handleUp(button: button, at: timestamp)
                    _ = self.mappingStore.endPress(for: button)
                    self.repeatGestureHUDButtons.remove(button)
                    self.dismissContextualOverlay(for: button)
                    return
                }
                binding = self.mappingStore.endPress(for: button)
            }

            // Gate A voice control: every physical microphone DOWN/UP owns one
            // transport session. App mappings and short/long classification do
            // not participate in this path.
            if button == .microphone {
                if isDown {
                    self.beginVoicePress(
                        targetApplicationBundleIdentifier: self.mappingStore
                            .activePressApplicationBundleIdentifier(for: button),
                        source: .hidMonitor
                    )
                } else {
                    self.finishVoicePressRelease(source: .hidMonitor) {
                        self.ble.stopVoiceInput()
                    }
                }
                return
            }

            // 其他按钮：使用按下时锁定的映射并注入
            guard !binding.isDisabled else { return }
            if isDown {
                if self.handleContextualAction(
                    binding,
                    button: button,
                    gesture: "按下"
                ) {
                    return
                }
                let sent = KeyInjector.send(
                    binding,
                    targetApplicationBundleIdentifier: self.mappingStore
                        .activePressApplicationBundleIdentifier(for: button),
                    scrollLinesPerStep: self.mappingStore.scrollLinesPerStep
                )
                print("[KEY] \(button.displayName) down → \(binding.displayName); sent=\(sent)")
                self.actionHUD.show(
                    button: button,
                    gesture: "按下",
                    action: binding.hudDisplayName,
                    state: self.actionHUDState(
                        for: binding,
                        targetApplicationBundleIdentifier: self.mappingStore
                            .activePressApplicationBundleIdentifier(for: button),
                        sent: sent
                    )
                )
            } else {
                if self.shouldCancelFloatTabsScroll(
                    binding: binding,
                    button: button,
                    targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
                ) {
                    let sent = FloatTabsCommandClient.send(.cancelScroll)
                    print(
                        "[KEY] \(button.displayName) scroll cancel → \(binding.displayName); sent=\(sent)"
                    )
                }
                self.dismissContextualOverlay(for: button)
                let sent = KeyInjector.sendUp(binding)
                print("[KEY] \(button.displayName) up → \(binding.displayName); sent=\(sent)")
            }
        }
        hidMonitor.onButtonDownPolicy = { [weak self] button in
            guard let self else {
                let repeatable = RemoteButton.repeatable.contains(button)
                return HIDButtonDownPolicy(
                    shouldDebounce: !repeatable,
                    shouldRepeat: repeatable
                )
            }

            // This prepares the app target, base binding and gesture profile
            // together. The edge callback below reuses that exact snapshot.
            let binding = self.mappingStore.preparePress(for: button)
            let profile = self.mappingStore.activePressGestureProfile(for: button)
            let advanced = button != .microphone && profile.usesAdvancedGestures
            let shouldRepeat: Bool
            if advanced {
                shouldRepeat = false
            } else {
                switch binding {
                case let .shortcut(_, trigger):
                    shouldRepeat = trigger == .repeatWhileHeld
                case let .preset(action):
                    shouldRepeat = action.repeatsWhenHeld
                case .voiceKeyDefault:
                    shouldRepeat = false
                }
            }
            return HIDButtonDownPolicy.resolve(
                button: button,
                shouldRepeat: shouldRepeat,
                usesAdvancedGestures: profile.usesAdvancedGestures,
                dualReceiverVoiceMode: .legacy,
                hasLivePhysicalCandidate: self.ble.hasLivePreHIDPhysicalCandidate
            )
        }
        hidMonitor.onButtonRepeat = { [weak self] button in
            guard let self else { return }
            guard !self.mappingStore.activePressGestureProfile(for: button)
                .usesAdvancedGestures else { return }
            let binding = self.mappingStore.activePressBinding(for: button)
            guard !binding.isDisabled else { return }

            // 单次快捷键不会创建重复计时器；这里再次判断作为防御，避免
            // 映射在按住期间发生变化时意外重复发送。
            if case let .shortcut(_, trigger) = binding, trigger != .repeatWhileHeld {
                return
            }
            let sent = KeyInjector.send(
                binding,
                targetApplicationBundleIdentifier: self.mappingStore
                    .activePressApplicationBundleIdentifier(for: button),
                scrollLinesPerStep: self.mappingStore.scrollLinesPerStep
            )
            print("[KEY] \(button.displayName) repeat → \(binding.displayName); sent=\(sent)")
        }
        hidMonitor.onStatusChange = { status in
            print("[HID] status: \(status)")
        }

        // Start the loopback engine eagerly so device binding is verified
        // before the first BLE audio packet arrives.
        _ = AudioPipe.shared

        // F6 filter (may prompt for Accessibility).
        do {
            try filter.start()
        } catch {
            voiceTriggerRuntimeLocked = true
            let msg = error.localizedDescription
            setStatusSummary("状态 · \(msg)", color: .systemOrange)
            setStatusIcon(systemName: "exclamationmark.triangle", color: .systemOrange)
            print("[ERR] filter: \(msg)")
        }

        // The persisted target is configured and the EventTap is ready before
        // a newly observed remote can activate its device-scoped HID mapping.
        hidMonitor.start()
    }

    private func applyVoiceHIDMappingForConnection(_ active: Bool) {
        let shouldEnable = active && !voiceTriggerRuntimeLocked
        let primaryKey = currentVoiceInputProfile.triggerKey
        let succeeded = voiceHIDMappingQueue.sync {
            applyVoiceHIDMapping(shouldEnable, primaryKey)
        }
        if shouldEnable && !succeeded {
            print("[HID-MAP] connect mapping failed; synthetic fallback remains available")
        }
    }

    private func handleGestureEvent(_ event: ButtonGestureEvent) {
        let binding: ButtonBinding?
        switch event.kind {
        case .singleTap:
            binding = event.context.baseBinding
        case .doubleTap:
            binding = event.context.profile.doubleTap
        case .longPress, .repeatStep:
            binding = event.context.profile.longPress
        }

        guard let binding, binding.isUsableGestureAction else {
            print(
                "[GESTURE] \(event.button.displayName) \(event.kind.displayName) "
                    + "duration=\(String(format: "%.3f", event.duration))s "
                    + "clicks=\(event.clickCount) → disabled"
            )
            actionHUD.show(
                button: event.button,
                gesture: event.kind.displayName,
                action: "未配置动作",
                state: .failure
            )
            return
        }

        // This is an Orbit-owned semantic action, not a keyboard event. It
        // resolves the current foreground app at the moment the gesture is
        // confirmed, so the same TV/other button can show Codex, FloatTabs,
        // Obsidian, or the global mapping without a separate Orbit hotkey.
        if handleContextualAction(
            binding,
            button: event.button,
            gesture: event.kind.displayName
        ) {
            return
        }

        let sent = KeyInjector.send(
            binding,
            targetApplicationBundleIdentifier: event.context
                .targetApplicationBundleIdentifier,
            scrollLinesPerStep: mappingStore.scrollLinesPerStep
        )
        print(
            "[GESTURE] \(event.button.displayName) \(event.kind.displayName) "
                + "duration=\(String(format: "%.3f", event.duration))s "
                + "clicks=\(event.clickCount) → \(binding.displayName); sent=\(sent)"
        )
        // Repeat gestures can arrive every 100 ms. Show the resolved
        // “按住重复” result once, on the first confirmed repeat action, then
        // let the normal result timeout remove it. Rebuilding an AppKit view
        // for every repeat would add flicker and unnecessary work.
        let shouldShowRepeatResult: Bool
        if event.kind == .repeatStep {
            shouldShowRepeatResult = !repeatGestureHUDButtons.contains(event.button)
            repeatGestureHUDButtons.insert(event.button)
        } else {
            shouldShowRepeatResult = false
        }
        if event.kind != .repeatStep || shouldShowRepeatResult {
            actionHUD.show(
                button: event.button,
                gesture: event.kind.displayName,
                action: binding.hudDisplayName,
                state: actionHUDState(
                    for: binding,
                    targetApplicationBundleIdentifier: event.context
                        .targetApplicationBundleIdentifier,
                    sent: sent
                )
            )
        }
    }

    private func handleContextualAction(
        _ binding: ButtonBinding,
        button: RemoteButton,
        gesture: String
    ) -> Bool {
        guard case .preset(.inspectCurrentKeymap) = binding else { return false }
        actionHUD.dismiss()
        keymapOverlayController.show(store: mappingStore)
        contextualOverlayButton = button
        print("[KEYMAP] \(button.displayName) \(gesture) → 显示当前快捷映射")
        return true
    }

    private func dismissContextualOverlay(for button: RemoteButton) {
        guard contextualOverlayButton == button else { return }
        keymapOverlayController.close()
        contextualOverlayButton = nil
        print("[KEYMAP] \(button.displayName) 松开 → 隐藏当前快捷映射")
    }

    private func actionHUDState(
        for binding: ButtonBinding,
        targetApplicationBundleIdentifier: String?,
        sent: Bool
    ) -> RemoteActionHUDState {
        guard sent else { return .failure }
        return KeyInjector.isAsynchronous(
            binding,
            targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
        ) ? .queued : .success
    }

    private func shouldCancelFloatTabsScroll(
        binding: ButtonBinding,
        button: RemoteButton,
        targetApplicationBundleIdentifier: String?
    ) -> Bool {
        guard button == .up || button == .down,
              targetApplicationBundleIdentifier == FloatTabsCommandClient.bundleIdentifier,
              case let .preset(action) = binding
        else { return false }
        return action == .pageUp || action == .pageDown
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshAudioDeviceMenus()
        rebuildVoiceInputProfileMenu()
        updateStatus()
    }

    @objc private func refreshAudioDeviceMenus() {
        AudioPipe.shared.recoverOutputDeviceIfNeeded()
        rebuildAudioMenu(
            audioInputMenu,
            devices: SystemAudioDeviceManager.inputDevices(),
            selectedID: SystemAudioDeviceManager.defaultInputDevice?.id,
            action: #selector(selectAudioInput(_:))
        )
        rebuildAudioMenu(
            audioOutputMenu,
            devices: SystemAudioDeviceManager.outputDevices(),
            selectedID: SystemAudioDeviceManager.defaultOutputDevice?.id,
            action: #selector(selectAudioOutput(_:))
        )
    }

    private func rebuildVoiceInputProfileMenu() {
        guard let menu = voiceInputProfileMenu else { return }
        menu.removeAllItems()
        for profile in VoiceInputProfile.supported {
            let item = NSMenuItem(
                title: profile.displayName,
                action: #selector(selectVoiceInputProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == currentVoiceInputProfile.id ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func selectVoiceInputProfile(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? String,
              let profile = VoiceInputProfile.supported.first(where: { $0.id == profileID })
        else { return }
        applyVoiceInputProfile(profile) { [weak self] result in
            guard let self else { return }
            if result != .applied && result != .unchanged {
                print("[VOICE-PROFILE] selection rejected: \(result)")
            }
            self.rebuildVoiceInputProfileMenu()
            self.updateStatus()
        }
    }

    private func rebuildAudioMenu(
        _ menu: NSMenu?,
        devices: [SystemAudioDevice],
        selectedID: AudioDeviceID?,
        action: Selector
    ) {
        guard let menu else { return }
        menu.removeAllItems()

        if devices.isEmpty {
            let unavailable = NSMenuItem(title: "未检测到可用设备", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false
            menu.addItem(unavailable)
            return
        }

        for device in devices {
            let item = NSMenuItem(
                title: SystemAudioDeviceManager.displayName(for: device),
                action: action,
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.stableIdentifier
            item.state = device.id == selectedID ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func selectAudioInput(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        _ = SystemAudioDeviceManager.selectInput(identifier: identifier)
        refreshAudioDeviceMenus()
        updateStatus()
    }

    @objc private func selectAudioOutput(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        _ = SystemAudioDeviceManager.selectOutput(identifier: identifier)
        refreshAudioDeviceMenus()
        updateStatus()
    }

    private func updateStatus() {
        let inputMonitoringGranted = HIDMonitor.isInputMonitoringGranted
        let accessibilityGranted = KeyInjector.isAccessibilityTrusted
        let audioOutputReady = AudioPipe.shared.isOutputReady

        if remoteStreaming, audioOutputReady {
            setStatusSummary("状态 · 遥控器录音中", color: .systemGreen)
            startRecordingStatusPulse()
        } else if !inputMonitoringGranted || !accessibilityGranted {
            stopRecordingStatusPulse()
            let missing = !inputMonitoringGranted && !accessibilityGranted
                ? "输入监控 + 辅助功能"
                : !inputMonitoringGranted ? "输入监控" : "辅助功能"
            setStatusSummary("状态 · 需要授权 \(missing)", color: .systemOrange)
            setStatusIcon(systemName: "exclamationmark.triangle", color: .systemOrange)
        } else if remoteStreaming {
            stopRecordingStatusPulse()
            setStatusSummary("状态 · 录音中但音频设备未就绪", color: .systemRed)
            setStatusIcon(systemName: "waveform.slash", color: .systemRed)
        } else if hidConnected && audioOutputReady {
            stopRecordingStatusPulse()
            setStatusSummary("状态 · 已就绪", color: .systemGreen)
            setStatusIcon(systemName: "circle.dotted.and.circle", color: .white)
        } else if hidConnected {
            stopRecordingStatusPulse()
            setStatusSummary("状态 · 音频设备未就绪", color: .systemRed)
            setStatusIcon(systemName: "waveform.slash", color: .systemRed)
        } else if bleConnected {
            stopRecordingStatusPulse()
            setStatusSummary("状态 · 正在连接", color: .systemOrange)
            setStatusIcon(systemName: "hourglass", color: .systemOrange)
        } else {
            stopRecordingStatusPulse()
            setStatusSummary("状态 · 等待遥控器", color: .systemRed)
            setStatusIcon(systemName: "exclamationmark.triangle", color: .systemRed)
        }

        setMenuStatus(remoteStatusItem, title: "遥控器 · " + (hidConnected ? "HID 已连接" : "未连接"), color: hidConnected ? .systemGreen : .systemRed)
        let audioTitle: String
        let audioColor: NSColor
        if remoteStreaming, audioOutputReady {
            audioTitle = "语音链路 · 遥控器录音中"
            audioColor = .systemGreen
        } else if remoteStreaming {
            audioTitle = "语音链路 · 音频设备未就绪"
            audioColor = .systemRed
        } else if bleConnected, audioOutputReady {
            audioTitle = "语音链路 · BLE 已连接"
            audioColor = .systemGreen
        } else if bleConnected {
            audioTitle = "语音链路 · BLE 已连接 / 音频未就绪"
            audioColor = .systemRed
        } else if hidConnected, audioOutputReady {
            audioTitle = "语音检测 · 可用（按住语音键启动）"
            audioColor = .systemGreen
        } else if hidConnected {
            audioTitle = "语音检测 · 音频设备未就绪"
            audioColor = .systemOrange
        } else {
            audioTitle = "语音检测 · 等待遥控器"
            audioColor = .systemRed
        }
        setMenuStatus(audioStatusItem, title: audioTitle, color: audioColor)
    }

    /// 录音期间用轻量的两相波形切换，让菜单栏能直观看到语音链路正在接收数据。
    /// 不创建额外窗口或动画视图，避免影响音频和 HID 事件线程。
    private func startRecordingStatusPulse() {
        renderRecordingStatusIcon()
        guard statusPulseTimer == nil else { return }
        statusPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) {
            [weak self] _ in
            self?.statusPulsePhase.toggle()
            self?.renderRecordingStatusIcon()
        }
    }

    private func renderRecordingStatusIcon() {
        let symbolName = statusPulsePhase ? "waveform.badge.mic" : "waveform"
        let color: NSColor = statusPulsePhase ? .systemGreen : .systemYellow
        setStatusIcon(systemName: symbolName, color: color)
    }

    private func stopRecordingStatusPulse() {
        statusPulseTimer?.invalidate()
        statusPulseTimer = nil
        statusPulsePhase = false
    }

    private func setStatusSummary(_ title: String, color: NSColor) {
        setMenuStatus(statusLabel, title: title, color: color)
    }

    private func setMenuStatus(_ item: NSMenuItem?, title: String, color: NSColor) {
        guard let item else { return }
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: color]
        )
    }

    private func setStatusIcon(systemName _: String, color _: NSColor = .white) {
        let image = ProductBrandMark.menuBarTemplateImage(size: 18)
        statusItem?.button?.image = image
        statusItem?.button?.title = ""
        statusItem?.button?.imageScaling = .scaleProportionallyDown
        statusItem?.button?.contentTintColor = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        voiceReceiverReadinessMonitor.deactivate()
        frontmostApplicationDiagnosticsObserver?.stop()
        frontmostApplicationDiagnosticsObserver = nil
        stopRecordingStatusPulse()
        voiceFocusSafetyWorkItem?.cancel()
        voiceFocusSafetyWorkItem = nil
        voiceFocusTransactions.cancelAll()
        keymapOverlayController.close()
        contextualOverlayButton = nil
        reconnectHeldButtons.removeAll()
        voicePress.stop()
        filter.stop()
        hidMonitor.stop()
        mappingStore.clearPressedBindings()
        KeyInjector.releaseAll()
        ble.stop()
        AudioPipe.shared.stop()
        voiceHIDMappingQueue.sync {
            _ = applyVoiceHIDMapping(false, currentMomentaryVoiceTriggerKey)
        }
        diagnosticLogger.close()
    }

    @objc private func openKeyMapping() {
        VoiceSettingsRuntimeBridge.readSecondaryVoiceTriggerKey = { [weak self] in
            self?.currentSecondaryMomentaryVoiceTriggerKey
        }
        VoiceSettingsRuntimeBridge.changeSecondaryVoiceTriggerKey = {
            [weak self] key, shortBinding, completion in
            guard let self else {
                completion(.locked)
                return
            }
            self.applySecondaryVoiceTriggerKey(
                key,
                shortBinding: shortBinding,
                completion: completion
            )
        }
        VoiceSettingsRuntimeBridge.changeMicrophoneShortBinding = { [weak self] binding, completion in
            guard let self else {
                completion(.locked)
                return
            }
            switch self.configureDualReceiverVoiceMode(
                shortBinding: binding,
                receiverB: self.currentSecondaryMomentaryVoiceTriggerKey
            ) {
            case .applied:
                self.currentDualReceiverShortBinding = binding
                completion(.applied)
            case .busy:
                completion(.busy)
            case .unavailable:
                completion(.failed)
            }
        }
        SettingsWindow.open(
            store: mappingStore,
            onRecordingChanged: { [weak self] enabled in
                self?.ble.setRecordingEnabled(enabled)
            },
            initialMomentaryVoiceTriggerKey: currentMomentaryVoiceTriggerKey,
            initialPersistentSessionTriggerKey: currentPersistentSessionTriggerKey,
            onVoiceTriggerChanged: { [weak self] key, completion in
                guard let self else {
                    completion(.locked)
                    return
                }
                self.applyVoiceTriggerKey(key, completion: completion)
            },
            onPersistentSessionTriggerKeyChanged: { [weak self] key, completion in
                guard let self else {
                    completion(.locked)
                    return
                }
                self.applyPersistentSessionTriggerKey(key, completion: completion)
            }
        )
    }

}

// MARK: - Entry

if let diagnosticCLIExitCode = DiagnosticCLI.runIfRequested() {
    exit(diagnosticCLIExitCode)
}


/// LaunchAtLogin uses `open`, and users can also start the app manually. Keep
/// the product to one process so two HID monitors, event taps, BLE clients,
/// or CoreAudio IOProcs cannot compete for the same remote.
private func terminateDuplicateInstanceIfNeeded() -> Bool {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier,
          bundleIdentifier == ProductIdentity.bundleIdentifier
    else { return false }

    let currentPID = ProcessInfo.processInfo.processIdentifier
    guard let existing = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
    ).first(where: { $0.processIdentifier != currentPID }) else {
        return false
    }

    _ = existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    Swift.print("[APP] duplicate launch ignored; existing pid=\(existing.processIdentifier)")
    return true
}

if terminateDuplicateInstanceIfNeeded() {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppController(
    applyVoiceHIDMappingWithReadback: { enabled, key, verificationCompletion in
        RemoteVoiceKeyMapping.setEnabled(
            enabled,
            target: key,
            verificationCompletion: verificationCompletion
        )
    }
)
app.delegate = delegate

// Convert SIGTERM (including `kill`/`pkill`) into a normal AppKit
// termination so Option and the CoreAudio IOProc are always released.
signal(SIGTERM, SIG_IGN)
let terminationSignal = DispatchSource.makeSignalSource(
    signal: SIGTERM,
    queue: .main
)
terminationSignal.setEventHandler {
    NSApp.terminate(nil)
}
terminationSignal.resume()

app.run()
