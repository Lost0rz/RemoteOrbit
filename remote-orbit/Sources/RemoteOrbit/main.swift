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
    static func setEnabled(_ shouldEnable: Bool, target: VoiceTriggerKey) -> Bool {
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
            scheduleDiagnosticReadback(enabled: shouldEnable, target: target)
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
        scheduleDiagnosticReadback(enabled: shouldEnable, target: target)
        return succeeded
    }

    private static func scheduleDiagnosticReadback(enabled shouldEnable: Bool, target: VoiceTriggerKey) {
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

final class VoicePressCoordinator {
    enum State: Equatable {
        case idle
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
        var isStillHeld = true
    }

    private struct PendingPersistentToggle {
        let gestureID: UUID
        let expectedFromMode: VoiceSessionMode
        let targetMode: VoiceSessionMode
        let triggerKey: VoiceTriggerKey
        let purpose: String
        let waitingGateOwner: UUID
    }

    var onStateChanged: ((State) -> Void)?
    /// Lets the HUD update when a long press receives its first real remote
    /// audio frame, without changing the gesture state itself.
    var onRemoteAudioChanged: ((Bool) -> Void)?
    /// Coordinates the physical hidutil Option edge with the short/long
    /// classifier. The event tap temporarily stores the original CGEvents
    /// until the gesture state decides whether to replay or drop them.
    var onHardwareOptionGateBegin: ((UUID) -> Void)?
    var onHardwareOptionGateLongReady: ((UUID) -> Void)?
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
    /// Complete a long gesture only after queued remote PCM has rendered.
    var onRemoteOutputDrain: ((UUID, @escaping () -> Void) -> Void)?
    /// The raw HID voice-key release arms the matching mapped Option-up.
    var onHardwareOptionGatePhysicalUp: ((UUID) -> Void)?
    /// Release a replayed hardware Option-up after output drain.
    var onHardwareOptionGateOutputDrained: ((UUID) -> Void)?

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
    private var tailWorkItem: DispatchWorkItem?
    private var tailSessionID: UUID?
    private var remoteStreaming = false
    private var remoteAudioAvailable = false
    private var remoteRouted = false
    private var longInputStarted = false
    private var releaseBounceDebounceUntil = Date.distantPast
    private var lastPhysicalUpAt: Date?
    private(set) var lastRepressDecisionForTesting: String?
    private var pendingRepress: PendingRepress?
    private var deferredRepressAwaitingActivation = false
    private var deferredRepressActivationWorkItem: DispatchWorkItem?
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
        diagnosticLogger: VoiceDiagnosticLogger? = nil
    ) {
        syntheticOptionTrigger = optionTrigger
        self.diagnosticLogger = diagnosticLogger
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
        mode != .idle
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
            "persistent_session_mode": voiceSessionMode == .persistentOpen
                ? "persistent_open" : "idle",
            "gesture_id": gestureID?.uuidString ?? "none",
            "pending_repress": pendingRepress != nil,
            "pending_persistent_toggle": pendingPersistentToggle != nil,
            "pending_persistent_toggle_gate_owner": pendingPersistentToggle?.waitingGateOwner.uuidString ?? "none",
            "remote_routed": remoteRouted,
            "remote_streaming": remoteStreaming,
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
        preparesRemoteTransport: Bool = false
    ) -> Bool {
        if let pendingPersistentToggle {
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
            print(
                "[PRESS] rejected release bounce delta=" +
                    String(format: "%.1fms", delta)
            )
            return false
        }
        guard mode == .idle, !awaitingPhysicalVoiceKeyUp else { return false }
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
                    preparesRemoteTransport: preparesRemoteTransport
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
            return true
        }
        if lastPhysicalUpAt != nil {
            lastRepressDecisionForTesting = "accepted-after-route-finished"
            print("[PRESS] accepted new gesture after previous route finished")
        } else {
            lastRepressDecisionForTesting = nil
        }

        return startAcceptedVoicePress(
            sessionID: sessionID,
            physicalDownAt: physicalDownAt,
            onShortTap: onShortTap,
            usesLocalMicrophone: usesLocalMicrophone,
            togglesPersistentVoiceSession: togglesPersistentVoiceSession,
            bypassesShortClassification: bypassesShortClassification,
            usesHardwareOption: usesHardwareOption,
            preparesRemoteTransport: preparesRemoteTransport
        )
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
            self.pendingRepress?.isStillHeld = false
            self.pendingRepress = nil
            deferredRepressAwaitingActivation = false
            deferredRepressActivationWorkItem?.cancel()
            deferredRepressActivationWorkItem = nil
            let shortID = String(pendingRepress.sessionID.uuidString.prefix(4))
            print(
                "[PRESS][\(shortID)] deferred re-press released before activation"
            )
            return false
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
        }
    }

    func suppressedHardwareGateDidClose(ownerID: UUID) {
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

    func setRemoteStreaming(_ streaming: Bool) {
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

    /// The BLE transport may announce AUDIO_START before delivering any PCM.
    /// Only the first decoded frame authorizes the long-press Option hold.
    func setRemoteAudioAvailable() {
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
        stopCurrentVoiceState(preservingDeferredRepress: false)
    }

    func stopCurrentVoiceStatePreservingDeferredRepress() {
        guard deferredRepressAwaitingActivation, pendingRepress != nil else {
            stop()
            return
        }
        print("[PRESS] preserving deferred re-press across old transport teardown")
        stopCurrentVoiceState(preservingDeferredRepress: true)
    }

    /// End the current transport segment while retaining a persistent IME
    /// session. A transport loss is a segment boundary, never a session tap.
    func handleTransportLoss(deviceRemoved: Bool = false) {
        guard voiceSessionMode == .persistentOpen else {
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
        self.pendingRepress = nil
        guard pendingRepress.isStillHeld else { return }

        let heldDuration = max(
            0,
            ProcessInfo.processInfo.systemUptime - pendingRepress.physicalDownAt
        )
        let shortID = String(pendingRepress.sessionID.uuidString.prefix(4))
        print(
            "[PRESS][\(shortID)] deferred re-press activated held=" +
                String(format: "%.1fms", heldDuration * 1000)
        )
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

    private func scheduleDeferredRepressActivation() {
        guard pendingRepress != nil else { return }
        deferredRepressAwaitingActivation = true
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
}

// MARK: - F5 → Option hold filter (CGEvent tap)

final class VoiceKeyFilter {
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
    private(set) var momentaryVoiceTriggerKey: VoiceTriggerKey = .leftOption
    /// Compatibility alias for callers that historically meant the mapped
    /// remote-microphone key.
    var voiceTriggerKey: VoiceTriggerKey { momentaryVoiceTriggerKey }
    private var deferredOptionDownSeen = false
    private var deferredOptionUpSeen = false
    private var deferredOptionDownEvents: [CGEvent] = []
    private var deferredOptionUpEvents: [CGEvent] = []
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
    var hasActiveHardwareTriggerOwnership: Bool {
        optionGate.activeSessionID != nil
            || optionGate.suppressedSessionID != nil
            || heldHardwareOptionSessionID != nil
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

    var diagnosticStateFields: [String: Any] {
        [
            "filter_active_gate": optionGate.activeSessionID?.uuidString ?? "none",
            "filter_suppressed_owner": optionGate.suppressedSessionID?.uuidString ?? "none",
            "held_hardware_owner": heldHardwareOptionSessionID?.uuidString ?? "none",
            "filter_configured_key": momentaryVoiceTriggerKey.rawValue,
            "synthetic_owner": syntheticOptionTrigger.activeSessionID?.uuidString ?? "none",
            "synthetic_down": syntheticOptionTrigger.isOptionDown,
        ]
    }

    init(
        syntheticOptionTrigger: VoiceOptionTrigger = .shared,
        diagnosticLogger: VoiceDiagnosticLogger? = nil
    ) {
        self.syntheticOptionTrigger = syntheticOptionTrigger
        self.diagnosticLogger = diagnosticLogger
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
        guard optionGate.activeSessionID != nil else { return false }
        if edge == .up, !deferredOptionDownSeen { return false }
        guard optionGate.capture(edge, copied: copiedEvent != nil) else {
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
    func beginOptionDeferral(gestureID: UUID) {
        if let shortTapOwner = optionGate.shortTapDiscardSessionID {
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
            return
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
            return
        }
        _ = syntheticOptionTrigger.begin(sessionID: gestureID)
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
    }

    /// Drop any older physical gate before a new gesture selects its Option
    /// source. This also covers a new synthetic-fallback gesture, which does
    /// not arm a replacement physical gate of its own.
    func cancelActiveOptionDeferral(reason: String) {
        if let gestureID = optionGate.activeSessionID {
            cancelDeferredOption(gestureID: gestureID, reason: reason)
        } else if let gestureID = heldHardwareOptionSessionID {
            abortHeldHardwareOption(gestureID: gestureID, reason: reason)
        } else if let gestureID = optionGate.suppressedSessionID {
            _ = resetSuppressedHardwareTrigger(
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
        clearHeldHardwareOption()
        if events.isEmpty {
            Key.voiceTriggerUp(momentaryVoiceTriggerKey)
            print("[VOICE] hardware Option-up missing; emergency balancing up")
        } else {
            events.forEach { $0.post(tap: .cghidEventTap) }
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
            Key.voiceTriggerUp(momentaryVoiceTriggerKey)
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

    /// Drops a fully captured gesture without replaying it. This is used only
    /// when a newer physical press supersedes a completed request; the stale
    /// request must never turn into a delayed Option tap in the new target.
    func cancelDeferredOption(gestureID: UUID, reason: String) {
        if heldHardwareOptionSessionID == gestureID {
            abortHeldHardwareOption(gestureID: gestureID, reason: reason)
            return
        }
        guard optionGate.cancel(sessionID: gestureID) else { return }
        _ = syntheticOptionTrigger.abort(sessionID: gestureID)
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
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
                switch type {
                case .flagsChanged:
                    guard !filter.isTriggerModifierActive(flags: event.flags),
                          !filter.heldHardwareOptionFlagsUpSeen else {
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
                    filter.heldHardwareOptionFlagsUpSeen = true
                case .keyUp:
                    guard !filter.heldHardwareOptionKeyUpSeen else {
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
                    filter.heldHardwareOptionKeyUpSeen = true
                default:
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
                if let copiedEvent = event.copy() {
                    filter.heldHardwareOptionUpEvents.append(copiedEvent)
                }
                filter.logMappedTriggerEvent(
                    keyCode: keyCode,
                    eventType: type,
                    flags: event.flags,
                    eventTimestamp: event.timestamp,
                    syntheticMarker: false,
                    action: "hold_release"
                )
                return nil
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

    private(set) var hidConnected = false
    private var bleConnected = false
    private var remoteStreaming = false
    private var statusPulseTimer: Timer?
    private var statusPulsePhase = false

    let filter: VoiceKeyFilter
    let voicePress: VoicePressCoordinator
    private let diagnosticLogger: VoiceDiagnosticLogger
    private var frontmostApplicationDiagnosticsObserver: FrontmostApplicationDiagnosticsObserver?
    private let ble = BLEBridge()
    private let mappingStore = MappingStore()
    private let hidMonitor = HIDMonitor()
    private let buttonGestureRecognizer = ButtonGestureRecognizer()
    private let actionHUD = RemoteActionHUD()
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
    private(set) var currentPersistentSessionTriggerKey: VoiceTriggerKey = .leftOption
    /// Compatibility alias: historical callers meant the mapped momentary
    /// remote-microphone trigger.
    var currentVoiceTriggerKey: VoiceTriggerKey { currentMomentaryVoiceTriggerKey }
    private(set) var voiceTriggerReconfigurationInProgress = false
    private(set) var voiceTriggerRuntimeLocked = false
    private var pendingVoiceHIDMappingRefresh = false
    private let isVoiceHIDMappingEnabled: () -> Bool
    private let applyVoiceHIDMapping: (Bool, VoiceTriggerKey) -> Bool
    private let readPersistedVoiceTriggerKey: () -> VoiceTriggerKey
    private let persistVoiceTriggerKey: (VoiceTriggerKey) -> Void
    private let readPersistedPersistentSessionTriggerKey: () -> VoiceTriggerKey
    private let persistPersistentSessionTriggerKey: (VoiceTriggerKey) -> Void
    private let diagnosticUptimeProvider: () -> TimeInterval
    private let voiceHIDMappingQueue = DispatchQueue(
        label: "com.remoteorbit.voice-trigger-hid-mapping",
        qos: .userInitiated
    )

    init(
        filter: VoiceKeyFilter = VoiceKeyFilter(diagnosticLogger: .shared),
        voicePress: VoicePressCoordinator = VoicePressCoordinator(diagnosticLogger: .shared),
        initiallyHIDConnected: Bool = false,
        isVoiceHIDMappingEnabled: @escaping () -> Bool = {
            RemoteVoiceKeyMapping.isEnabled
        },
        applyVoiceHIDMapping: @escaping (Bool, VoiceTriggerKey) -> Bool = {
            RemoteVoiceKeyMapping.setEnabled($0, target: $1)
        },
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
        diagnosticLogger: VoiceDiagnosticLogger = .shared,
        uptimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.filter = filter
        self.voicePress = voicePress
        self.diagnosticLogger = diagnosticLogger
        self.hidConnected = initiallyHIDConnected
        self.isVoiceHIDMappingEnabled = isVoiceHIDMappingEnabled
        self.applyVoiceHIDMapping = applyVoiceHIDMapping
        self.readPersistedVoiceTriggerKey = readPersistedVoiceTriggerKey
        self.persistVoiceTriggerKey = persistVoiceTriggerKey
        self.readPersistedPersistentSessionTriggerKey = readPersistedPersistentSessionTriggerKey
        self.persistPersistentSessionTriggerKey = persistPersistentSessionTriggerKey
        self.diagnosticUptimeProvider = uptimeProvider
        super.init()
    }

    @discardableResult
    func restoreVoiceTriggerRuntime() -> Bool {
        let restoredMomentaryKey = readPersistedVoiceTriggerKey()
        let restoredPersistentKey = readPersistedPersistentSessionTriggerKey()
        diagnosticLogger.log(
            category: "configuration",
            event: "RUNTIME_RESTORE_BEGIN",
            fields: [
                "persisted_persistent": restoredPersistentKey.rawValue,
                "persisted_momentary": restoredMomentaryKey.rawValue,
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
        currentPersistentSessionTriggerKey = restoredPersistentKey
        print(
            "[VOICE-KEY] startup restored momentary=\(restoredMomentaryKey.displayName) "
                + "persistent=\(restoredPersistentKey.displayName)"
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
            ]
        )
        return true
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
            completeVoiceTriggerReconfiguration(.applied, completion: completion)
            return
        }

        voiceHIDMappingQueue.async { [weak self] in
            guard let self else { return }
            let succeeded = self.applyVoiceHIDMapping(true, newKey)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard succeeded else {
                    self.rollbackVoiceTriggerApply(
                        oldKey: oldKey,
                        hadHardwareMapping: hadHardwareMapping,
                        completion: completion
                    )
                    return
                }
                self.currentMomentaryVoiceTriggerKey = newKey
                self.persistVoiceTriggerKey(newKey)
                print("[VOICE-KEY] runtime target committed=\(newKey.displayName)")
                self.completeVoiceTriggerReconfiguration(.applied, completion: completion)
            }
        }
    }

    private func voiceConfigurationBusyResult() -> VoiceTriggerApplyResult? {
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
        let shouldEnable = hidConnected
        let target = currentMomentaryVoiceTriggerKey
        voiceHIDMappingQueue.async { [weak self] in
            guard let self else { return }
            let succeeded = self.applyVoiceHIDMapping(shouldEnable, target)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if shouldEnable && !succeeded {
                    print("[HID-MAP] reconnect mapping failed; synthetic fallback remains available")
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
        let persistentKeyAtEntry = currentPersistentSessionTriggerKey
        let target = lockedTarget
            ?? MappingStore.preferredApplicationBundleIdentifier()
        let needsFloatTabsFocus = FloatTabsCommandClient.shouldPrepareInputFocus(
            for: target
        )
        let needsCodexFocus = !needsFloatTabsFocus
            && CodexCommandAdapter.shouldPrepareInputFocus(for: target)
        // Focus repair is useful for the text insertion target, but it must
        // never gate the physical Option edge or remote audio. AX/WebKit can
        // be slow or unavailable even while the receiver is already working.
        let needsFocusPreparation = needsFloatTabsFocus || needsCodexFocus
        // Gate every gesture while the real HID mapping is active. Otherwise
        // a disabled short slot could still leak the mapped trigger before
        // the 300 ms classifier resolves the press.
        // VoiceKeyFilter is the fallback path used while the HID monitor is
        // unavailable. Resolve the same app-scoped binding used by HID before
        // deciding the short action.
        let resolvedShortBinding = shortBinding
            ?? mappingStore.binding(for: .microphone, appBundleIdentifier: target)
        print(
            "[VOICE] short input binding → \(resolvedShortBinding.displayName); "
                + "target=\(target ?? "global")"
        )
        let usesLocalMicrophone = VoicePressCoordinator.usesLocalMicrophone(
            forShortBinding: resolvedShortBinding
        )
        let togglesPersistentVoiceSession = VoicePressCoordinator.togglesPersistentVoiceSession(
            forShortBinding: resolvedShortBinding
        )
        let bypassesShortClassification = Self.bypassesShortClassification(
            for: resolvedShortBinding
        )
        // Local capture is deliberately lazy. Starting it here would open the
        // physical microphone during the 300 ms short-vs-long classification
        // window, so a long hold would still briefly invoke the external mic.
        print(
            "[VOICE] 本机麦克风采集 → "
                + (usesLocalMicrophone
                    ? "短按确认后启用（长按不启用）"
                    : "关闭（单击未启用）")
        )

        let shortTapAction: (() -> Void)?
        switch resolvedShortBinding {
        case .voiceKeyDefault:
            // nil selects the coordinator's persistent IME session toggle.
            shortTapAction = nil
        case let binding where binding.isDisabled:
            // A disabled short slot must not fall through to the IME toggle.
            // The long remote-mic slot remains fully independent.
            shortTapAction = {
                print("[PRESS] SHORT release → disabled by microphone mapping")
            }
        default:
            // Codex voice chat is an optional short behavior, but it still
            // goes through this classifier so a long hold always remains the
            // remote ATVV microphone path.
            shortTapAction = { [weak self] in
                self?.handleVoiceShortTap(
                    resolvedShortBinding,
                    targetApplicationBundleIdentifier: target
                )
            }
        }

        let pressAccepted = voicePress.keyDown(
            sessionID: gestureID,
            onShortTap: shortTapAction,
            usesLocalMicrophone: usesLocalMicrophone,
            togglesPersistentVoiceSession: togglesPersistentVoiceSession,
            bypassesShortClassification: bypassesShortClassification,
            usesHardwareOption: isVoiceHIDMappingEnabled(),
            preparesRemoteTransport: resolvedShortBinding.isDisabled
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
                "persistent_key": persistentKeyAtEntry.rawValue,
            ]
        )
        guard pressAccepted else {
            return
        }

        // A deferred B edge has no active ownership yet. Leave A's focus and
        // Option state untouched and wait for VoicePressCoordinator to
        // activate the saved context after A's route is off.
        guard voicePress.pendingRepressSessionID == nil else {
            return
        }

        if let previousGestureID = voiceFocusTransactions.activeGestureID {
            voiceFocusSafetyWorkItem?.cancel()
            voiceFocusSafetyWorkItem = nil
            _ = voiceFocusTransactions.cancel(previousGestureID)
        }
        // Hardware activation already supersedes an older gate inside
        // beginOptionDeferral. Only the synthetic fallback needs the
        // coordinator call site to clear a stale physical gate here.
        if !isVoiceHIDMappingEnabled() {
            filter.cancelActiveOptionDeferral(reason: "superseded-by-new-gesture")
        }

        guard needsFocusPreparation else {
            return
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
        switch state {
        case .idle:
            actionHUD.dismiss()
        case .pending:
            guard voicePress.shouldShowPendingVoiceUI else {
                actionHUD.dismiss()
                return
            }
            actionHUD.show(
                button: .microphone,
                gesture: "按住",
                action: "遥控器语音输入",
                state: .pending,
                keepsVisible: true
            )
        case .holding:
            guard voicePress.hasRemoteAudio else {
                actionHUD.dismiss()
                return
            }
            actionHUD.show(
                button: .microphone,
                gesture: "按住",
                action: "遥控器语音输入",
                state: .recording,
                keepsVisible: true
            )
        }
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
        updateStatus()

        voicePress.onStateChanged = { [weak self] state in
            if state == .holding {
                // ATVV starts only after the gesture enters remote-microphone holding.
                // Enabled short actions reach this state after the normal hold threshold;
                // a disabled short action enters it immediately because there is no short
                // branch to classify.
                self?.ble.activateVoiceInput()
            }
            self?.updateVoiceHUD(for: state)
        }
        voicePress.onRemoteAudioChanged = { [weak self] available in
            guard let self else { return }
            if available {
                self.actionHUD.show(
                    button: .microphone,
                    gesture: "按住",
                    action: "遥控器语音输入",
                    state: .recording,
                    keepsVisible: true
                )
            } else {
                self.actionHUD.dismiss()
            }
        }
        voicePress.onHardwareOptionGateBegin = { [weak self] gestureID in
            guard let self else { return }
            self.filter.beginOptionDeferral(gestureID: gestureID)
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
        voicePress.onHardwareOptionGateCancel = { [weak self] gestureID in
            self?.filter.cancelDeferredOption(
                gestureID: gestureID,
                reason: "gesture-cancelled"
            )
        }
        voicePress.onRemoteTransportPreparation = { [weak self] in
            self?.ble.prepareVoiceTransport()
        }
        voicePress.onRemoteOutputDrain = { _, completion in
            AudioPipe.shared.waitForOutputDrain(completion: completion)
        }
        voicePress.onHardwareOptionGatePhysicalUp = { [weak self] gestureID in
            self?.filter.armHardwareOptionRelease(gestureID: gestureID)
        }
        voicePress.onHardwareOptionGateOutputDrained = { [weak self] gestureID in
            self?.filter.releaseHeldHardwareOption(
                gestureID: gestureID,
                reason: "output-drained"
            )
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

            // 语音键：单击走电脑/外部麦克风动作，长按走遥控器麦克风。
            if button == .microphone {
                let profile = self.mappingStore.activePressGestureProfile(for: button)
                let usesRemoteMicrophone = profile.longPressEnabled
                    && profile.longPress == .voiceKeyDefault
                    && profile.longPressBehavior != .none
                if usesRemoteMicrophone {
                    if isDown {
                        self.beginVoicePress(
                            targetApplicationBundleIdentifier: self.mappingStore
                                .activePressApplicationBundleIdentifier(for: button),
                            shortBinding: binding,
                            source: .hidMonitor
                        )
                    } else {
                        self.finishVoicePressRelease(source: .hidMonitor) {
                            self.ble.stopVoiceInput()
                        }
                    }
                    return
                }
                // 用户自定义了映射，走正常注入流程
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
                    self.dismissContextualOverlay(for: button)
                    let sent = KeyInjector.sendUp(binding)
                    print("[KEY] \(button.displayName) up → \(binding.displayName); sent=\(sent)")
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
            return HIDButtonDownPolicy(
                shouldDebounce: !shouldRepeat && !advanced,
                shouldRepeat: shouldRepeat
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
        let succeeded = applyVoiceHIDMapping(shouldEnable, currentMomentaryVoiceTriggerKey)
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

    private func setStatusIcon(systemName: String, color: NSColor = .white) {
        guard let symbol = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: ProductIdentity.name
        ) else { return }

        // Do not rely on NSStatusBarButton's template-image tinting here.
        // On some macOS menu-bar appearances the button ignores
        // `contentTintColor` and renders the template symbol black. Rasterize
        // the small symbol into the requested color so the visible pixels are
        // deterministic in both light and dark menu bars.
        let imageSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        let imageRect = NSRect(origin: .zero, size: imageSize)
        symbol.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: symbol.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        color.set()
        imageRect.fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false

        statusItem?.button?.image = image
        statusItem?.button?.title = ""
        statusItem?.button?.imageScaling = .scaleProportionallyDown
        statusItem?.button?.contentTintColor = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
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
let delegate = AppController()
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
