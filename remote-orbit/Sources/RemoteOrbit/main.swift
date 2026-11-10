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
//   * configurable momentary voice-input trigger profile
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
    }

    private struct PendingRepress {
        let sessionID: UUID
        let usesHardwareOption: Bool
        let profile: VoiceInputProfile
        var isStillHeld = true

        init(
            sessionID: UUID,
            usesHardwareOption: Bool,
            profile: VoiceInputProfile,
            isStillHeld: Bool = true
        ) {
            self.sessionID = sessionID
            self.usesHardwareOption = usesHardwareOption
            self.profile = profile
            self.isStillHeld = isStillHeld
        }
    }

    private enum DeferredRepressWaitReason: Equatable {
        case directOutputDrain
    }

    private enum LongOnlyTriggerStrategy {
        case hardware
        case syntheticHandoff
        case voiceShortcutChord
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
    /// Coordinates the physical hidutil Option edge with Gate-A candidate
    /// ownership. The event tap temporarily stores the original CGEvents
    /// until the retained LONG-only path decides whether to release or drop them.
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
    /// Reset suppression only when HID device removal proves no matching up
    /// event can arrive; ordinary BLE loss keeps waiting for physical up.
    /// Testable ordering seam: the state callback is where AppController
    /// requests BLE acquisition, and this callback marks route preparation.
    var onRemoteRoutePreparation: (() -> Void)?
    /// A LONG-only candidate may prewarm ATVV before the 300 ms promotion
    /// boundary. This does not release Option or expose the voice HUD.
    var onRemoteTransportPreparation: (() -> Void)?
    var onRemoteTransportCancellation: (() -> Void)?
    /// Called only after a private candidate has been promoted into the
    /// existing direct opening lifecycle. Focus work belongs here, not at DOWN.
    var onLongOnlyCandidatePromoted: ((UUID, String?) -> Void)?
    /// Complete a long gesture only after queued remote PCM has rendered.
    var onRemoteOutputDrain: ((UUID, @escaping () -> Void) -> Void)?
    /// Release the temporary RemoteOrbit system-input lease after the final
    /// remote voice session has fully drained and no immediate direct
    /// successor owns the next session. Transport deactivation must not fire
    /// this: the queued remote PCM tail still owns the input until the
    /// actual output drain completes.
    var onRemoteInputLeaseRelease: (() -> Void)?
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

    /// Keep this at 300 ms: a physical voice-key press remains a private
    /// candidate until this LONG-only boundary is confirmed.
    static let holdActivationThreshold: TimeInterval = 0.30
    static func isLongPress(heldDuration: TimeInterval) -> Bool {
        heldDuration >= holdActivationThreshold
    }

    // The remote usually sends AUDIO_STOP just before the HID key-up, and the
    // BLE bridge keeps accepting packets during its drain window. Keep the
    // output route alive long enough for those final frames to render even
    // when the physical Option edge has already been released.
    static let tailDrainDelay: TimeInterval = 0.80
    private var mode: State = .idle
    private var longOnlyCandidateTimer: VoicePressCandidateTimer?
    private var longOnlyCandidate: LongOnlyCandidate?
    private let candidateTimerFactory:
        (TimeInterval, @escaping () -> Void) -> VoicePressCandidateTimer
    private var remoteStreaming = false
    private var preHIDPhysicalStreaming = false
    private var remoteAudioAvailable = false
    private var remoteRouted = false
    private var physicalTriggerSuppressionActive = false
    private(set) var lastRepressDecisionForTesting: String?
    private var pendingRepress: PendingRepress?
    private var deferredRepressAwaitingActivation = false
    private var deferredRepressActivationWorkItem: DispatchWorkItem?
    private var deferredRepressWaitReason: DeferredRepressWaitReason?
    private var gestureID: UUID?
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
    private var usesHardwareOptionPath = false
    /// Remote voice temporarily leases the system default input to RemoteOrbit
    /// Mic 2ch. The lease survives transport stop and transfers across a
    /// rapid direct repress; only a post-drain completion with no immediate
    /// direct successor restores the persisted preferred input.
    private var remoteInputLeaseHeld = false
    private let syntheticOptionTrigger: VoiceOptionTrigger
    private let voiceShortcutEmitter: VoiceShortcutEmitter
    private let diagnosticLogger: VoiceDiagnosticLogger?
    private var gesturePhysicalDownUptime: TimeInterval?

    init(
        optionTrigger: VoiceOptionTrigger = .shared,
        voiceShortcutEmitter: VoiceShortcutEmitter = VoiceShortcutEmitter(),
        diagnosticLogger: VoiceDiagnosticLogger? = nil,
        candidateTimerFactory: @escaping
            (TimeInterval, @escaping () -> Void) -> VoicePressCandidateTimer =
            VoicePressCandidateTimer.gcdFactory
    ) {
        syntheticOptionTrigger = optionTrigger
        self.voiceShortcutEmitter = voiceShortcutEmitter
        self.diagnosticLogger = diagnosticLogger
        self.candidateTimerFactory = candidateTimerFactory
        if let diagnosticLogger {
            self.voiceShortcutEmitter.diagnosticSink = { [weak diagnosticLogger] diagnostic in
                diagnosticLogger?.log(
                    category: "voice",
                    event: diagnostic.kind.rawValue,
                    gestureID: diagnostic.sessionID,
                    fields: diagnostic.fields
                )
            }
        }
    }

    var hasRemoteAudio: Bool {
        remoteAudioAvailable
    }

    var hasPhysicalCandidateReaderForQATapRecreation: Bool {
        hasLivePhysicalCandidate != nil
    }

    var isSessionAdmissionClearForQATapRecreation: Bool {
        isVoiceSessionAdmissionBlocked?() == false
    }

    var hasUnresolvedVoiceShortcutOwnership: Bool {
        voiceShortcutEmitter.hasUnresolvedOwnership
    }

    @discardableResult
    func recoverPendingVoiceShortcutReleaseOwnership() -> Bool {
        voiceShortcutEmitter.recoverPendingReleases()
    }

    var remoteInputLeaseHeldForTesting: Bool {
        remoteInputLeaseHeld
    }

    var pendingRepressSessionID: UUID? {
        pendingRepress?.sessionID
    }

    var hasDeferredRepressAwaitingActivationForTesting: Bool {
        deferredRepressAwaitingActivation
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

    var hasActiveVoiceOwnershipForTriggerReconfiguration: Bool {
        mode != .idle
            || longOnlyCandidate != nil
            || pendingRepress != nil
            || gestureID != nil
            || remoteRouted
            || remoteStreaming
            || remoteAudioAvailable
            || deferredRepressAwaitingActivation
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
            || deferredRepressAwaitingActivation
    }

    var hasAnyOwnershipForQATapRecreation: Bool {
        mode != .idle
            || longOnlyCandidateTimer != nil
            || longOnlyCandidate != nil
            || remoteStreaming
            || preHIDPhysicalStreaming
            || remoteAudioAvailable
            || remoteRouted
            || physicalTriggerSuppressionActive
            || pendingRepress != nil
            || deferredRepressAwaitingActivation
            || deferredRepressActivationWorkItem != nil
            || deferredRepressWaitReason != nil
            || gestureID != nil
            || directSession
            || (directOutputDrainRequested && !directOutputDrained)
            || pendingDirectHardwareRepressAwaitingOldUp
            || pendingDirectHardwareRepressOldSessionID != nil
            || pendingDirectHardwareRepressACompleted
            || pendingDirectHardwareRepressDownCaptured
            || remoteInputLeaseHeld
            || syntheticOptionTrigger.activeSessionID != nil
            || syntheticOptionTrigger.isOptionDown
            || voiceShortcutEmitter.hasUnresolvedOwnership
            || livePhysicalCandidateForAdmission
    }

    var diagnosticStateFields: [String: Any] {
        [
            "mode": modeName,
            "voice_session_state": modeName,
            "voice_input_profile_id": capturedVoiceProfile?.id ?? "none",
            "voice_input_trigger_key": capturedVoiceProfile?.triggerKey?.rawValue ?? "none",
            "gesture_id": gestureID?.uuidString ?? "none",
            "pending_repress": pendingRepress != nil,
            "long_only_candidate": longOnlyCandidate != nil,
            "long_only_candidate_long_confirmed": longOnlyCandidate?.longConfirmed ?? false,
            "remote_routed": remoteRouted,
            "remote_streaming": remoteStreaming,
            "pre_hid_physical_streaming": preHIDPhysicalStreaming,
            "transport_stop_observed": directTransportStopObserved,
            "remote_audio_available": remoteAudioAvailable,
            "momentary_config": syntheticOptionTrigger.momentaryVoiceTriggerKey.rawValue,
            "synthetic_owner": syntheticOptionTrigger.activeSessionID?.uuidString ?? "none",
            "synthetic_down": syntheticOptionTrigger.isOptionDown,
        ]
    }

    @discardableResult
    func keyDown(
        sessionID: UUID,
        usesHardwareOption: Bool = false,
        preparesRemoteTransport: Bool = false,
        profile: VoiceInputProfile? = nil,
        targetApplicationBundleIdentifier: String? = nil
    ) -> Bool {
        startLongOnlyDirectCandidate(
            sessionID: sessionID,
            profile: profile ?? .defaultProfile,
            usesHardwareOption: usesHardwareOption,
            preparesRemoteTransport: preparesRemoteTransport,
            targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
        )
    }

    /// Test seam for the retained direct opening lifecycle. Production input
    /// always enters through `keyDown`, which owns the 300 ms candidate gate.
    @discardableResult
    func keyDownForTesting(
        sessionID: UUID,
        usesHardwareOption: Bool = false,
        profile: VoiceInputProfile? = nil
    ) -> Bool {
        startDirectVoicePress(
            sessionID: sessionID,
            profile: profile ?? .defaultProfile,
            usesHardwareOption: usesHardwareOption
        )
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
        let usesHardwareOption = usesHardwareOption && profile.triggerKey != nil
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
                usesHardwareOption: usesHardwareOption,
                profile: profile
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
        var triggerStrategy: LongOnlyTriggerStrategy = profile.triggerKey == nil
            ? .voiceShortcutChord
            : .hardware
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
        defer { releaseRemoteInputLeaseIfUnowned() }
        if candidate.triggerStrategy == .syntheticHandoff {
            _ = onHardwareOptionGateShortHandoffReleased?(candidate.sessionID)
                ?? false
        } else if candidate.usesHardwareOption {
            if candidate.triggerOwnershipReady {
                _ = onHardwareOptionGateShortDiscard?(candidate.sessionID)
                    ?? false
            }
        } else if candidate.triggerStrategy == .voiceShortcutChord {
            _ = voiceShortcutEmitter.abort(sessionID: candidate.sessionID)
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
        defer { releaseRemoteInputLeaseIfUnowned() }
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
        } else if candidate.triggerStrategy == .voiceShortcutChord {
            _ = voiceShortcutEmitter.abort(sessionID: candidate.sessionID)
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
        let usesHardwareOption = usesHardwareOption && profile.triggerKey != nil
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
                    usesHardwareOption: usesHardwareOption,
                    profile: profile
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

        if profile.binding.usesVoiceShortcutEmitter {
            let beginResult = voiceShortcutEmitter.begin(
                sessionID: sessionID,
                entryID: profile.id,
                binding: profile.binding
            )
            guard beginResult.wasAccepted else {
                _ = voiceShortcutEmitter.abort(sessionID: sessionID)
                let reason: String
                switch beginResult {
                case .rejected(.unresolvedOwnership): reason = "voice_shortcut_unresolved_ownership"
                case .rejected(.physicalModifierConflict): reason = "voice_shortcut_physical_modifier_conflict"
                case .rejected(.invalidBinding): reason = "voice_shortcut_invalid_binding"
                case .rejected(.eventConstructionFailed): reason = "voice_shortcut_event_construction_failed"
                case .rejected(.postFailed): reason = "voice_shortcut_post_failed"
                case .accepted: reason = "voice_shortcut_emit_failed"
                }
                logAdmissionDecision(
                    sessionID: sessionID,
                    result: "rejected",
                    reason: reason
                )
                return false
            }
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
        VoiceTimingLogger.begin(sessionID: sessionID)
        AudioPipe.shared.beginRemoteCandidate()

        diagnosticLogger?.log(
            category: "voice",
            event: "VOICE_SESSION_OPENING",
            gestureID: sessionID,
            key: profile.triggerKey,
            fields: voiceInputDiagnosticFields(profile).merging([
                "voice_input_profile_id": profile.id,
                "trigger_key": profile.triggerKey?.rawValue ?? "chord",
                "trigger_source": usesHardwareOption ? "hardware" : (profile.triggerKey == nil ? "voice_shortcut_chord" : "synthetic"),
                "classifier": "none",
            ]) { _, new in new }
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
        } else if profile.triggerKey != nil {
            _ = syntheticOptionTrigger.begin(sessionID: sessionID)
            _ = syntheticOptionTrigger.sendDown(
                sessionID: sessionID,
                key: profile.triggerKey!,
                purpose: "voice_session_opening"
            )
            VoiceTimingLogger.mark("OPTION_GATE_RELEASE", sessionID: sessionID)
        } else {
            VoiceTimingLogger.mark("VOICE_SHORTCUT_DOWN", sessionID: sessionID)
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
        VoiceTimingLogger.mark("PHYSICAL_UP", sessionID: sessionID)
        diagnosticLogger?.log(
            category: "voice",
            event: "VOICE_SESSION_DRAINING",
            gestureID: sessionID,
            key: capturedVoiceProfile?.triggerKey,
            fields: voiceInputDiagnosticFields(capturedVoiceProfile).merging([
                "voice_input_profile_id": capturedVoiceProfile?.id ?? "unknown",
                "trigger_key": capturedVoiceProfile?.triggerKey?.rawValue ?? "chord",
            ]) { _, new in new }
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
            fields: voiceInputDiagnosticFields(capturedVoiceProfile).merging([
                "voice_session_state": "draining"
            ]) { _, new in new }
        )

        let drainProfile = capturedVoiceProfile
        let completion = { [weak self] in
            guard let self else { return }
            guard self.directSession,
                  self.gestureID == sessionID,
                  !self.directOutputDrained else {
                if let drainProfile, drainProfile.binding.usesVoiceShortcutEmitter {
                    self.voiceShortcutEmitter.recordLateDrainCallback(
                        sessionID: sessionID,
                        entryID: drainProfile.id,
                        binding: drainProfile.binding
                    )
                }
                return
            }
            self.directOutputDrained = true
            VoiceTimingLogger.mark("AUDIO_PIPELINE_CLOSED", sessionID: sessionID)
            self.diagnosticLogger?.log(
                category: "voice",
                event: "OUTPUT_DRAIN_COMPLETE",
                gestureID: sessionID,
                key: self.capturedVoiceProfile?.triggerKey,
                fields: self.voiceInputDiagnosticFields(self.capturedVoiceProfile).merging([
                    "voice_session_state": "draining"
                ]) { _, new in new }
            )
            if self.usesHardwareOptionPath {
                self.onHardwareOptionGateOutputDrained?(sessionID)
            } else if self.capturedVoiceProfile?.triggerKey != nil {
                if self.physicalTriggerSuppressionActive {
                    self.onHardwareOptionGateOutputDrained?(sessionID)
                }
                _ = self.syntheticOptionTrigger.sendUp(sessionID: sessionID)
            } else if self.capturedVoiceProfile?.binding.usesVoiceShortcutEmitter == true {
                _ = self.voiceShortcutEmitter.end(sessionID: sessionID)
            } else {
                _ = self.syntheticOptionTrigger.abort(sessionID: sessionID)
            }
            if self.capturedVoiceProfile?.binding.usesVoiceShortcutEmitter == true {
                VoiceTimingLogger.mark("VOICE_SHORTCUT_UP_REQUESTED", sessionID: sessionID)
            } else {
                VoiceTimingLogger.mark("OPTION_UP_REQUESTED", sessionID: sessionID)
            }
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
           pendingRepress != nil {
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
        gestureID = nil
        _ = syntheticOptionTrigger.abort(sessionID: sessionID)
        _ = voiceShortcutEmitter.abort(sessionID: sessionID)
        if !preHIDPhysicalStreaming && !livePhysicalCandidateForAdmission {
            AudioPipe.shared.endRemoteCandidate()
        }
        _ = setRemoteRouted(false)
        settleRemoteInputLeaseAtDirectCompletion()
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

    /// A promoted remote LONG temporarily leases the system input to
    /// RemoteOrbit Mic 2ch. At post-drain direct-session completion, keep the
    /// lease only when an immediate direct successor — a registered rapid
    /// repress or a live replacement physical candidate epoch — will own the
    /// next session; otherwise restore the persisted preferred input. This
    /// is deliberately not part of `AudioPipe.setRemoteActive(false)`, which
    /// runs before the queued remote PCM tail has drained.
    private func settleRemoteInputLeaseAtDirectCompletion() {
        guard remoteInputLeaseHeld else { return }
        let hasImmediateDirectSuccessor =
            (deferredRepressWaitReason == .directOutputDrain && pendingRepress != nil)
            || pendingDirectHardwareRepressAwaitingOldUp
            || preHIDPhysicalStreaming
            || livePhysicalCandidateForAdmission
        guard !hasImmediateDirectSuccessor else { return }
        remoteInputLeaseHeld = false
        onRemoteInputLeaseRelease?()
    }

    /// Release a lease that was retained for a successor once that successor
    /// dies without promoting into a direct session.
    private func releaseRemoteInputLeaseIfUnowned() {
        guard remoteInputLeaseHeld,
              !directSession,
              pendingRepress == nil,
              !deferredRepressAwaitingActivation,
              !pendingDirectHardwareRepressAwaitingOldUp,
              !preHIDPhysicalStreaming,
              !livePhysicalCandidateForAdmission else { return }
        remoteInputLeaseHeld = false
        onRemoteInputLeaseRelease?()
    }

    private func tryActivatePendingDirectHardwareRepress() {
        guard deferredRepressWaitReason == .directOutputDrain,
              let pending = pendingRepress,
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
        scheduleDeferredRepressActivation()
    }

    func pendingHardwareOptionRepressDownCaptured(sessionID: UUID) {
        guard pendingRepress?.sessionID == sessionID,
              pendingRepress?.usesHardwareOption == true else {
            return
        }
        pendingDirectHardwareRepressDownCaptured = true
        tryActivatePendingDirectHardwareRepress()
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
           let pendingValue = pendingRepress {
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
            }
            clearPendingDirectHardwareRepressState()
            releaseRemoteInputLeaseIfUnowned()
            print("[PRESS] pending direct re-press released before activation")
            return false
        }

        if directSession {
            return finishDirectVoicePressRelease()
        }

        guard let pendingRepress else { return false }
        self.pendingRepress?.isStillHeld = false
        self.pendingRepress = nil
        deferredRepressAwaitingActivation = false
        deferredRepressActivationWorkItem?.cancel()
        deferredRepressActivationWorkItem = nil
        deferredRepressWaitReason = nil
        if pendingRepress.usesHardwareOption {
            onHardwareOptionGatePendingRepressCancel?(
                pendingRepress.sessionID,
                "physical-up-before-activation"
            )
        }
        clearPendingDirectHardwareRepressState()
        return false
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
    }

    func suppressedHardwareGateWasInvalidated(ownerID: UUID, reason: String) {
        armCandidateTriggerOwnershipIfAvailable()
    }

    func setPreHIDPhysicalStreaming(_ streaming: Bool) {
        if !streaming, hasLivePhysicalCandidate?() == true {
            // An old epoch's callback must not erase newer BLE-owned truth.
            return
        }
        preHIDPhysicalStreaming = streaming
        if !streaming {
            releaseRemoteInputLeaseIfUnowned()
        }
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
        guard directSession else { return }
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
        guard directSession,
              let currentGestureID = gestureID,
              !remoteAudioAvailable else { return }
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

        deferredRepressActivationWorkItem?.cancel()
        deferredRepressActivationWorkItem = nil
        deferredRepressAwaitingActivation = false
        if let pendingRepress {
            if pendingRepress.usesHardwareOption {
                onHardwareOptionGatePendingRepressCancel?(
                    pendingRepress.sessionID,
                    "stop"
                )
            }
            self.pendingRepress = nil
        }
        deferredRepressWaitReason = nil
        clearPendingDirectHardwareRepressState()
        _ = syntheticOptionTrigger.reset()
        voiceShortcutEmitter.abortAll()
        releaseRemoteInputLeaseIfUnowned()
    }

    /// A removed HID device cannot deliver the matching physical UP. Retire
    /// the private candidate and its bounded trigger/transport ownership at
    /// the same identity-preserving boundary as the rest of HID cleanup.
    func cancelLongOnlyCandidateForHIDRemoval() {
        _ = cancelLongOnlyCandidate(reason: "hid-removed")
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

    /// End the current transport segment and release its bounded ownership.
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
    }

    private func activatePendingRepressIfHeld() {
        guard let pendingRepress else { return }
        defer { releaseRemoteInputLeaseIfUnowned() }
        let longOnlyCandidate = self.longOnlyCandidate
        if let longOnlyCandidate,
           (longOnlyCandidate.sessionID != pendingRepress.sessionID
                || !longOnlyCandidate.longConfirmed
                || !longOnlyCandidate.isStillHeld) {
            return
        }
        self.pendingRepress = nil
        deferredRepressWaitReason = nil
        guard pendingRepress.isStillHeld else {
            clearPendingDirectHardwareRepressState()
            return
        }

        guard livePhysicalCandidateForAdmission else {
            clearPendingDirectHardwareRepressState()
            print("[PRESS] direct re-press activation lost physical candidate")
            return
        }
        let activated = startDirectVoicePress(
            sessionID: pendingRepress.sessionID,
            profile: pendingRepress.profile,
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
    }

    private func scheduleDeferredRepressActivation() {
        guard pendingRepress != nil else { return }
        deferredRepressAwaitingActivation = true
        deferredRepressWaitReason = .directOutputDrain
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

    @discardableResult
    private func setRemoteRouted(_ active: Bool) -> Int {
        guard remoteRouted != active else { return 0 }
        remoteRouted = active
        if active {
            remoteInputLeaseHeld = true
        }
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
        }
    }

    private func voiceInputDiagnosticFields(_ profile: VoiceInputProfile?) -> [String: Any] {
        guard let profile else { return [:] }
        var fields = profile.binding.diagnosticFields
        fields["entry_id"] = profile.id
        return fields
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

protocol VoiceKeyFilterTapResourceLifecycle: AnyObject {
    var tapPort: CFMachPort? { get }
    var isReadyForEventDelivery: Bool { get }
    var isAbsent: Bool { get }

    func create(
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) throws
    func removeAndVerifyAbsence() -> Bool
}

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

    private let tapResourceLifecycle: VoiceKeyFilterTapResourceLifecycle
    private let accessibilityTrustCheck: () -> Bool
    private let accessibilityTrustRequest: (Bool) -> Bool
    private var retainedTapCallback: CGEventTapCallBack?
    private let tapCallbackStateLock = NSLock()
    private var tapCallbackDepth = 0
    private var qaTapRecreationAccepted = false
    private var qaTapRecreationInProgress = false
    private var tapPort: CFMachPort? { tapResourceLifecycle.tapPort }
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
    private(set) var configureVoiceTriggerKeyCallCountForTesting = 0
    var onReplayedHardwareOptionUpPassAcknowledged: ((UUID) -> Void)?
    var onPendingHardwareOptionRepressDownCaptured: ((UUID) -> Void)?
    var hasActiveHardwareTriggerOwnership: Bool {
        optionGate.activeSessionID != nil
            || optionGate.suppressedSessionID != nil
            || optionGate.shortTapDiscardSessionID != nil
            || heldHardwareOptionSessionID != nil
            || pendingReplayedHardwareOptionUp != nil
            || pendingHardwareOptionRepress != nil
            || pendingLongOnlySuppressionHandoff != nil
            || hardwareOptionReleaseArmed
            || !heldHardwareOptionUpEvents.isEmpty
            || heldHardwareOptionFlagsUpSeen
            || heldHardwareOptionKeyUpSeen
            || deferredOptionDownSeen
            || deferredOptionUpSeen
            || !deferredOptionDownEvents.isEmpty
            || !deferredOptionUpEvents.isEmpty
            || longConfirmedOptionGestureID != nil
            || suppressedTriggerReleaseCompletionWorkItem != nil
            || suppressedTriggerReleaseCompletionToken != nil
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

    var isQuiescentForQATapRecreation: Bool {
        !hasActiveHardwareTriggerOwnership
            && !hasShortTapDiscardOwnership
            && !hasSyntheticTriggerOwnership
            && !isSyntheticTriggerDown
            && voiceTriggerReconfigurationKeyCodes == nil
            && !hasTapCallbackInFlight
            && !qaTapRecreationInProgress
    }

    var hasAcceptedQATapRecreation: Bool {
        qaTapRecreationAccepted
    }

    private var hasTapCallbackInFlight: Bool {
        tapCallbackStateLock.lock()
        defer { tapCallbackStateLock.unlock() }
        return tapCallbackDepth > 0
    }

    private func tapCallbackDidEnter() {
        tapCallbackStateLock.lock()
        tapCallbackDepth += 1
        tapCallbackStateLock.unlock()
    }

    private func tapCallbackDidExit() {
        tapCallbackStateLock.lock()
        tapCallbackDepth = max(0, tapCallbackDepth - 1)
        tapCallbackStateLock.unlock()
    }

    func withTapCallbackOwnershipForTesting(_ body: () -> Void) {
        tapCallbackDidEnter()
        defer { tapCallbackDidExit() }
        body()
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
        },
        tapResourceLifecycle: VoiceKeyFilterTapResourceLifecycle =
            CoreGraphicsVoiceKeyFilterTapResourceLifecycle(),
        accessibilityTrustCheck: @escaping () -> Bool = {
            AXIsProcessTrusted()
        },
        accessibilityTrustRequest: @escaping (Bool) -> Bool = { prompt in
            let opts: CFDictionary = [
                kAXTrustedCheckOptionPrompt.takeRetainedValue() as CFString: prompt
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
    ) {
        self.syntheticOptionTrigger = syntheticOptionTrigger
        self.diagnosticLogger = diagnosticLogger
        self.replayEventPoster = replayEventPoster
        self.emitEmergencyHardwareOptionUp = emitEmergencyHardwareOptionUp
        self.tapResourceLifecycle = tapResourceLifecycle
        self.accessibilityTrustCheck = accessibilityTrustCheck
        self.accessibilityTrustRequest = accessibilityTrustRequest
    }

    @discardableResult
    func configureVoiceTriggerKey(_ key: VoiceTriggerKey) -> Bool {
        configureVoiceTriggerKeyCallCountForTesting += 1
        guard !hasActiveHardwareTriggerOwnership else {
            return false
        }
        guard syntheticOptionTrigger.configureVoiceTriggerKey(key) else {
            return false
        }
        momentaryVoiceTriggerKey = key
        return true
    }

    func isVoiceTriggerConfiguredConsistently(for key: VoiceTriggerKey) -> Bool {
        momentaryVoiceTriggerKey == key
            && syntheticOptionTrigger.momentaryVoiceTriggerKey == key
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
        guard tapResourceLifecycle.isAbsent else {
            print("[FILTER] event tap already running")
            return
        }

        // Don't prompt user each time — check if already trusted.
        let trusted = accessibilityTrustCheck()
        let granted = accessibilityTrustRequest(!trusted)
        print("[FILTER] AX trusted=\(granted) (was \(trusted))")
        if !granted {
            // mtime on the binary changes when SwiftPM rebuilds; we exit
            // and the user re-runs after granting once.
            throw FilterError.accessibilityDenied
        }

        let callback: CGEventTapCallBack
        if let retainedTapCallback {
            callback = retainedTapCallback
        } else {
            callback = { (_, type, event, userInfo) -> Unmanaged<CGEvent>? in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let filter = Unmanaged<VoiceKeyFilter>.fromOpaque(userInfo).takeUnretainedValue()
            filter.tapCallbackDidEnter()
            defer { filter.tapCallbackDidExit() }
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
            retainedTapCallback = callback
        }
        do {
            try tapResourceLifecycle.create(
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        } catch {
            throw FilterError.tapCreationFailed
        }
        guard tapResourceLifecycle.isReadyForEventDelivery else {
            _ = tapResourceLifecycle.removeAndVerifyAbsence()
            throw FilterError.tapCreationFailed
        }
        print("[FILTER] tap enabled; voice key 0x60 (F5) is suppressed; HID mapping supplies physical Option, with synthetic fallback")
    }

    enum QATapRecreationResult: Equatable {
        case recreated(attempts: Int)
        case rejected(reason: String)
        case degraded(reason: String)
    }

#if DEBUG
    func recreateTapResourcesForQA() -> QATapRecreationResult {
        guard Thread.isMainThread else {
            return .rejected(reason: "not_main_thread")
        }
        guard !qaTapRecreationAccepted else {
            return .rejected(reason: "one_shot_already_used")
        }
        guard isQuiescentForQATapRecreation else {
            return .rejected(reason: "filter_ownership_active_or_uncertain")
        }
        guard accessibilityTrustCheck() else {
            return .rejected(reason: "accessibility_trust_unavailable")
        }
        guard tapResourceLifecycle.isReadyForEventDelivery else {
            return .rejected(reason: "existing_tap_invalid_or_disabled")
        }
        guard let retainedTapCallback else {
            return .rejected(reason: "retained_callback_missing")
        }

        // Consume the one-shot before touching the Tap. A failed teardown or
        // replacement must not make this action repeatable in the same process.
        qaTapRecreationAccepted = true
        qaTapRecreationInProgress = true
        defer { qaTapRecreationInProgress = false }

        guard tapResourceLifecycle.removeAndVerifyAbsence(),
              tapResourceLifecycle.isAbsent else {
            return .degraded(reason: "old_tap_teardown_not_verified")
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        for attempt in 1...2 {
            do {
                try tapResourceLifecycle.create(
                    callback: retainedTapCallback,
                    userInfo: userInfo
                )
            } catch {
                // The manager may have allocated a partial replacement; the
                // next attempt is allowed only after verified teardown.
            }

            if tapResourceLifecycle.isReadyForEventDelivery {
                return .recreated(attempts: attempt)
            }

            guard tapResourceLifecycle.removeAndVerifyAbsence(),
                  tapResourceLifecycle.isAbsent else {
                return .degraded(reason: "failed_replacement_cleanup_not_verified")
            }
            if attempt == 2 {
                return .degraded(reason: "replacement_failed_after_one_retry")
            }
        }

        return .degraded(reason: "replacement_failed")
    }
#endif

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
        _ = tapResourceLifecycle.removeAndVerifyAbsence()
    }
}

final class CoreGraphicsVoiceKeyFilterTapResourceLifecycle:
    VoiceKeyFilterTapResourceLifecycle {
    private(set) var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?

    var isReadyForEventDelivery: Bool {
        guard let tapPort, let tapSource else { return false }
        return CFMachPortIsValid(tapPort)
            && CFRunLoopContainsSource(
                CFRunLoopGetMain(),
                tapSource,
                CFRunLoopMode.defaultMode
            )
            && CGEvent.tapIsEnabled(tap: tapPort)
    }

    var isAbsent: Bool {
        tapPort == nil && tapSource == nil
    }

    func create(
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) throws {
        guard isAbsent else { throw VoiceKeyFilter.FilterError.tapCreationFailed }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            throw VoiceKeyFilter.FilterError.tapCreationFailed
        }
        tapPort = tap
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            tapPort = nil
            throw VoiceKeyFilter.FilterError.tapCreationFailed
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        tapSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        guard isReadyForEventDelivery else {
            _ = removeAndVerifyAbsence()
            throw VoiceKeyFilter.FilterError.tapCreationFailed
        }
    }

    func removeAndVerifyAbsence() -> Bool {
        let runLoop = CFRunLoopGetMain()
        let oldPort = tapPort
        let oldSource = tapSource
        if let oldPort {
            CGEvent.tapEnable(tap: oldPort, enable: false)
        }
        if let oldSource {
            CFRunLoopRemoveSource(runLoop, oldSource, .commonModes)
        }
        if let oldPort {
            CFMachPortInvalidate(oldPort)
        }
        tapSource = nil
        tapPort = nil

        let sourceRemoved = oldSource.map {
            !CFRunLoopContainsSource(runLoop, $0, CFRunLoopMode.defaultMode)
        } ?? true
        let portInvalidated = oldPort.map { !CFMachPortIsValid($0) } ?? true
        return isAbsent && sourceRemoved && portInvalidated
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
#if DEBUG
    private var qaTapRecreationMenuItem: NSMenuItem?
#endif

    let filter: VoiceKeyFilter
    let voicePress: VoicePressCoordinator
    private let diagnosticLogger: VoiceDiagnosticLogger
    private lazy var frontmostApplicationDiagnosticsLifecycle =
        FrontmostApplicationDiagnosticsLifecycle {
            FrontmostApplicationDiagnosticsObserver()
        }
    private var diagnosticsRuntimeObserverRegistered = false
    private let ble = BLEBridge()
    private let mappingStore = MappingStore()
    private let voiceShortcutPresentation = VoiceShortcutPresentation.shared
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
    private(set) var currentVoiceShortcutSnapshot = VoiceShortcutSnapshot.seeded()
    private(set) var voiceShortcutReadOnlyReason: VoiceShortcutValidationError?
    /// Compatibility alias: historical callers meant the mapped momentary
    /// remote-microphone trigger.
    var currentVoiceTriggerKey: VoiceTriggerKey { currentMomentaryVoiceTriggerKey }
    private(set) var voiceTriggerReconfigurationInProgress = false
    private(set) var voiceTriggerRuntimeLocked = false
    private var pendingVoiceHIDMappingRefresh = false
    private let isVoiceHIDMappingEnabled: () -> Bool
    private let applyVoiceHIDMapping: (Bool, VoiceTriggerKey) -> Bool
    private let prepareVoiceTransportAction: (() -> Void)?
    private let activateVoiceInputAction: (() -> Void)?
    private let cancelVoiceTransportPreparationAction: (() -> Void)?
    private let stopVoiceInputAction: (() -> Void)?
    private let readPersistedVoiceTriggerKey: () -> VoiceTriggerKey
    private let persistVoiceTriggerKey: (VoiceTriggerKey) -> Void
    private let usePersistedVoiceProfile: Bool
    private let voiceShortcutDefaults: UserDefaults
    private let diagnosticUptimeProvider: () -> TimeInterval
    private let qaTapRecreationModifierFlagsProvider: () -> CGEventFlags
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
        prepareVoiceTransport: (() -> Void)? = nil,
        activateVoiceInput: (() -> Void)? = nil,
        cancelVoiceTransportPreparation: (() -> Void)? = nil,
        stopVoiceInput: (() -> Void)? = nil,
        usePersistedVoiceProfile: Bool = true,
        voiceShortcutDefaults: UserDefaults = .standard,
        readPersistedVoiceTriggerKey: @escaping () -> VoiceTriggerKey = {
            AppStorage.momentaryVoiceTriggerKey
        },
        persistVoiceTriggerKey: @escaping (VoiceTriggerKey) -> Void = {
            AppStorage.momentaryVoiceTriggerKey = $0
        },
        diagnosticLogger: VoiceDiagnosticLogger = .shared,
        uptimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        qaTapRecreationModifierFlagsProvider: @escaping () -> CGEventFlags = {
            CGEventSource.flagsState(.combinedSessionState)
                .union(CGEventSource.flagsState(.hidSystemState))
        }
    ) {
        self.filter = filter
        self.voicePress = voicePress
        self.diagnosticLogger = diagnosticLogger
        self.hidConnected = initiallyHIDConnected
        self.isVoiceHIDMappingEnabled = isVoiceHIDMappingEnabled
        self.applyVoiceHIDMapping = applyVoiceHIDMapping
        self.prepareVoiceTransportAction = prepareVoiceTransport
        self.activateVoiceInputAction = activateVoiceInput
        self.cancelVoiceTransportPreparationAction = cancelVoiceTransportPreparation
        self.stopVoiceInputAction = stopVoiceInput
        self.usePersistedVoiceProfile = usePersistedVoiceProfile
        self.voiceShortcutDefaults = voiceShortcutDefaults
        self.readPersistedVoiceTriggerKey = readPersistedVoiceTriggerKey
        self.persistVoiceTriggerKey = persistVoiceTriggerKey
        self.diagnosticUptimeProvider = uptimeProvider
        self.qaTapRecreationModifierFlagsProvider = qaTapRecreationModifierFlagsProvider
        super.init()
        voicePress.onStateChanged = { [weak self] state in
            if state == .opening {
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
        }
    }

#if DEBUG
    @discardableResult
    func attemptQATapRecreationForTesting() -> VoiceKeyFilter.QATapRecreationResult {
        let result: VoiceKeyFilter.QATapRecreationResult
        if let reason = qaTapRecreationBlockReason() {
            result = .rejected(reason: reason)
        } else {
            result = filter.recreateTapResourcesForQA()
        }

        var fields: [String: Any]
        switch result {
        case .recreated(let attempts):
            fields = ["outcome": "recreated", "create_attempts": attempts]
        case .rejected(let reason):
            fields = ["outcome": "rejected", "reason": reason]
        case .degraded(let reason):
            fields = ["outcome": "degraded", "reason": reason]
        }
        diagnosticLogger.log(
            category: "filter",
            event: "VOICE_FILTER_QA_TAP_RECREATION",
            fields: fields
        )
        if filter.hasAcceptedQATapRecreation {
            qaTapRecreationMenuItem?.isEnabled = false
        }
        return result
    }

    private func qaTapRecreationBlockReason() -> String? {
        guard Thread.isMainThread else { return "not_main_run_loop" }
        guard !voiceTriggerRuntimeLocked,
              !voiceTriggerReconfigurationInProgress,
              !pendingVoiceHIDMappingRefresh else {
            return "configuration_transition_or_lock"
        }
        guard voicePress.hasPhysicalCandidateReaderForQATapRecreation,
              voicePress.isSessionAdmissionClearForQATapRecreation else {
            return "hardware_admission_state_uncertain"
        }
        guard !voicePress.hasAnyOwnershipForQATapRecreation else {
            return "voice_coordinator_or_emitter_ownership"
        }
        guard voiceFocusTransactions.activeGestureID == nil,
              voiceFocusSafetyWorkItem == nil else {
            return "voice_focus_transaction_active"
        }
        guard VoiceAttemptDiagnostics.shared.currentID == nil else {
            return "voice_attempt_active"
        }
        guard filter.isQuiescentForQATapRecreation else {
            return "filter_hardware_or_replay_ownership"
        }

        let relevantModifierFlags: CGEventFlags = [
            .maskAlternate,
            .maskCommand,
            .maskControl,
            .maskShift,
            .maskSecondaryFn,
        ]
        guard qaTapRecreationModifierFlagsProvider()
            .intersection(relevantModifierFlags).isEmpty else {
            return "physical_modifier_flags_active"
        }
        return nil
    }

    @objc private func performQATapRecreation(_ sender: Any) {
        _ = attemptQATapRecreationForTesting()
    }
#endif

    @discardableResult
    func restoreVoiceTriggerRuntime() -> Bool {
        let loaded = VoiceShortcutStore.load(from: voiceShortcutDefaults)
        currentVoiceShortcutSnapshot = loaded.snapshot
        voiceShortcutReadOnlyReason = loaded.reason
        voiceShortcutPresentation.replace(
            snapshot: loaded.snapshot,
            readOnlyReason: loaded.reason
        )
        let legacyProfile = VoiceInputProfileStore.profile(for: readPersistedVoiceTriggerKey())
        let restoredProfile = usePersistedVoiceProfile
            ? loaded.snapshot.activeEntry?.profile ?? legacyProfile
            : legacyProfile
        let restoredMomentaryKey = restoredProfile.triggerKey ?? readPersistedVoiceTriggerKey()
        diagnosticLogger.log(
            category: "configuration",
            event: "RUNTIME_RESTORE_BEGIN",
            fields: [
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
        currentMomentaryVoiceTriggerKey = restoredMomentaryKey
        currentVoiceInputProfile = restoredProfile
        let mappingShouldBeEnabled = restoredProfile.triggerKey != nil && hidConnected
        let restoredMapping = voiceHIDMappingQueue.sync {
            applyVoiceHIDMapping(mappingShouldBeEnabled, restoredMomentaryKey)
        }
        if !restoredMapping {
            voiceTriggerRuntimeLocked = true
            diagnosticLogger.log(
                category: "configuration",
                event: "RUNTIME_RESTORE_FAIL",
                fields: ["reason": "hid_mapping_restore_failed"]
            )
            return false
        }
        print(
            "[VOICE-KEY] startup restored profile=\(restoredProfile.displayName)"
        )
        diagnosticLogger.log(
            category: "configuration",
            event: "RUNTIME_RESTORE_COMMIT",
            key: restoredMomentaryKey,
            fields: [
                "controller_momentary": currentMomentaryVoiceTriggerKey.rawValue,
                "filter_momentary": filter.momentaryVoiceTriggerKey.rawValue,
                "synthetic_momentary": voicePress.diagnosticStateFields["momentary_config"] as? String ?? "unknown",
                "persisted_momentary": restoredMomentaryKey.rawValue,
                "voice_input_profile_id": restoredProfile.id,
            ]
        )
        return true
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

    func cancelVoiceGestureStateForHIDRemoval() {
        hidConnected = false
        voicePress.cancelLongOnlyCandidateForHIDRemoval()
        if let pendingReplayGestureID = filter.pendingReplayedHardwareOptionUpGestureID {
            filter.cancelDeferredOption(
                gestureID: pendingReplayGestureID,
                reason: "hid-removed"
            )
        }
    }

    /// Runtime key changes are initiated on the main run loop so the EventTap
    /// can enforce its bounded suppression gate while hidutil runs off-thread.
    /// The completion is called on the main run loop for every result.
    func applyVoiceTriggerKey(
        _ newKey: VoiceTriggerKey,
        persistLegacy: Bool = true,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(.locked)
                    return
                }
                self.applyVoiceTriggerKey(newKey, persistLegacy: persistLegacy, completion: completion)
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
        if voicePress.hasUnresolvedVoiceShortcutOwnership {
            _ = voicePress.recoverPendingVoiceShortcutReleaseOwnership()
            guard !voicePress.hasUnresolvedVoiceShortcutOwnership else {
                logReconfigurationBusy(
                    reason: "unresolved_voice_shortcut_synthetic_ownership",
                    event: "MOMENTARY_RECONFIG_REJECTED"
                )
                completion(.busyReleaseDrain)
                return
            }
        }
        let hadHardwareMapping = isVoiceHIDMappingEnabled()
        guard newKey != oldKey || (hidConnected && !hadHardwareMapping) else {
            completion(.unchanged)
            return
        }
        if let busy = voiceConfigurationBusyResult() {
            logReconfigurationBusy(reason: applyResultReason(busy), event: "MOMENTARY_RECONFIG_REJECTED")
            completion(busy)
            return
        }
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
            if persistLegacy { persistVoiceTriggerKey(newKey) }
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
                if persistLegacy { self.persistVoiceTriggerKey(newKey) }
                print("[VOICE-KEY] runtime target committed=\(newKey.displayName)")
                self.completeVoiceTriggerReconfiguration(.applied, completion: completion)
            }
        }
    }

    func applyVoiceInputProfile(
        _ profile: VoiceInputProfile,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        var proposed = currentVoiceShortcutSnapshot
        guard proposed.entries.contains(where: { $0.id == profile.id }) else {
            completion(.failed)
            return
        }
        proposed.activeEntryID = profile.id
        updateVoiceShortcutSnapshot(proposed, completion: completion)
    }

    func updateVoiceShortcutSnapshot(
        _ proposed: VoiceShortcutSnapshot,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        logVoiceShortcutConfiguration(
            event: "VOICE_SHORTCUT_CONFIG_REQUESTED",
            entry: proposed.activeEntry,
            outcome: "requested"
        )
        guard Thread.isMainThread,
              voiceShortcutReadOnlyReason == nil,
              (try? VoiceShortcutStore.validate(proposed)) != nil
        else {
            logVoiceShortcutConfiguration(
                event: "VOICE_SHORTCUT_CONFIG_REJECTED",
                entry: proposed.activeEntry,
                outcome: "rejected",
                reason: "not_main_thread_read_only_or_invalid_snapshot"
            )
            completion(.failed)
            return
        }
        let oldSnapshot = currentVoiceShortcutSnapshot
        guard let targetEntry = proposed.activeEntry else {
            logVoiceShortcutConfiguration(
                event: "VOICE_SHORTCUT_CONFIG_REJECTED",
                entry: nil,
                outcome: "rejected",
                reason: "missing_active_entry"
            )
            completion(.failed)
            return
        }
        let target = targetEntry.profile
        let oldActive = oldSnapshot.activeEntry?.profile ?? currentVoiceInputProfile
        let activeBindingChanged = oldActive.id != target.id || oldActive.binding != target.binding
        guard activeBindingChanged else {
            do {
                try VoiceShortcutStore.persist(proposed, to: voiceShortcutDefaults)
                currentVoiceShortcutSnapshot = proposed
                currentVoiceInputProfile = target
                self.voiceShortcutPresentation.replace(
                    snapshot: proposed,
                    readOnlyReason: nil
                )
                rebuildVoiceInputProfileMenu()
                logVoiceShortcutConfiguration(
                    event: "VOICE_SHORTCUT_CONFIG_COMMITTED",
                    entry: targetEntry,
                    outcome: "snapshot_committed_without_runtime_change"
                )
                completion(.applied)
            } catch {
                logVoiceShortcutConfiguration(
                    event: "VOICE_SHORTCUT_CONFIG_COMMIT_FAILED",
                    entry: targetEntry,
                    outcome: "commit_failed",
                    reason: "snapshot_persist_failed"
                )
                completion(.failed)
            }
            return
        }

        logVoiceShortcutConfiguration(
            event: "VOICE_SHORTCUT_RUNTIME_RECONFIG_BEGIN",
            entry: targetEntry,
            outcome: "begin",
            reason: "active_binding_changed"
        )
        currentVoiceInputProfile = target
        let apply: (@escaping (VoiceTriggerApplyResult) -> Void) -> Void
        if let key = target.triggerKey {
            apply = { [weak self] done in
                self?.applyVoiceTriggerKey(key, persistLegacy: false, completion: done)
                    ?? done(.locked)
            }
        } else {
            apply = { [weak self] done in
                self?.applyVoiceShortcutChordRuntime(entry: targetEntry, completion: done) ?? done(.locked)
            }
        }
        apply { [weak self] result in
            guard let self else { completion(.locked); return }
            guard result == .applied || result == .unchanged else {
                self.currentVoiceInputProfile = oldActive
                let isBusy = result == .busy || result == .busyActiveHold || result == .busyReleaseDrain
                self.logVoiceShortcutConfiguration(
                    event: isBusy ? "VOICE_SHORTCUT_CONFIG_BUSY" : "VOICE_SHORTCUT_CONFIG_REJECTED",
                    entry: targetEntry,
                    outcome: isBusy ? "busy" : "rejected",
                    reason: self.applyResultReason(result)
                )
                completion(result)
                return
            }
            do {
                try VoiceShortcutStore.persist(proposed, to: voiceShortcutDefaults)
                self.currentVoiceShortcutSnapshot = proposed
                self.currentVoiceInputProfile = target
                self.voiceShortcutPresentation.replace(
                    snapshot: proposed,
                    readOnlyReason: nil
                )
                voiceShortcutDefaults.set(target.id, forKey: VoiceInputProfileStore.selectedProfileIDKey)
                if let key = target.triggerKey {
                    self.persistVoiceTriggerKey(key)
                }
                self.rebuildVoiceInputProfileMenu()
                self.logVoiceShortcutConfiguration(
                    event: "VOICE_SHORTCUT_CONFIG_COMMITTED",
                    entry: targetEntry,
                    outcome: "runtime_and_snapshot_committed"
                )
                completion(result == .unchanged ? .applied : result)
            } catch {
                self.currentVoiceInputProfile = oldActive
                self.logVoiceShortcutConfiguration(
                    event: "VOICE_SHORTCUT_ROLLBACK_BEGIN",
                    entry: targetEntry,
                    outcome: "rollback_requested",
                    reason: "snapshot_persist_failed"
                )
                self.rollbackVoiceShortcutRuntime(to: oldActive) { rollback in
                    if rollback == .applied || rollback == .unchanged {
                        self.logVoiceShortcutConfiguration(
                            event: "VOICE_SHORTCUT_ROLLBACK_COMPLETE",
                            entry: oldSnapshot.activeEntry,
                            outcome: "previous_runtime_restored",
                            reason: "snapshot_persist_failed"
                        )
                        completion(.failed)
                    } else {
                        self.logVoiceShortcutConfiguration(
                            event: "VOICE_SHORTCUT_ROLLBACK_FAILED",
                            entry: oldSnapshot.activeEntry,
                            outcome: "runtime_state_uncertain",
                            reason: self.applyResultReason(rollback)
                        )
                        self.lockVoiceTriggerRuntime(reason: "voice shortcut snapshot readback and runtime rollback failed")
                        completion(.locked)
                    }
                }
            }
        }
    }

    private func logVoiceShortcutConfiguration(
        event: String,
        entry: VoiceShortcutEntry?,
        outcome: String,
        reason: String? = nil
    ) {
        var fields = entry?.diagnosticFields ?? ["binding_kind": "unknown"]
        fields["outcome"] = outcome
        if let reason { fields["reason"] = reason }
        diagnosticLogger.log(category: "configuration", event: event, fields: fields)
    }

    private func rollbackVoiceShortcutRuntime(
        to profile: VoiceInputProfile,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        currentVoiceInputProfile = profile
        if let key = profile.triggerKey {
            applyVoiceTriggerKey(key, completion: completion)
        } else {
            applyVoiceShortcutChordRuntime(
                entry: currentVoiceShortcutSnapshot.entries.first { $0.id == profile.id },
                completion: completion
            )
        }
    }

    private func applyVoiceShortcutChordRuntime(
        entry: VoiceShortcutEntry? = nil,
        completion: @escaping (VoiceTriggerApplyResult) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyVoiceShortcutChordRuntime(entry: entry, completion: completion) ?? completion(.locked)
            }
            return
        }
        let targetEntry = entry ?? currentVoiceShortcutSnapshot.activeEntry
        logVoiceShortcutConfiguration(
            event: "VOICE_SHORTCUT_RUNTIME_RECONFIG_REQUESTED",
            entry: targetEntry,
            outcome: "requested"
        )
        guard !voiceTriggerRuntimeLocked else {
            logVoiceShortcutConfiguration(
                event: "VOICE_SHORTCUT_CONFIG_BUSY",
                entry: targetEntry,
                outcome: "busy",
                reason: "runtime_locked"
            )
            completion(.locked)
            return
        }
        guard !voiceTriggerReconfigurationInProgress else {
            logVoiceShortcutConfiguration(
                event: "VOICE_SHORTCUT_CONFIG_BUSY",
                entry: targetEntry,
                outcome: "busy",
                reason: "reconfiguration_busy"
            )
            completion(.busy)
            return
        }
        if let busy = voiceConfigurationBusyResult() {
            logVoiceShortcutConfiguration(
                event: "VOICE_SHORTCUT_CONFIG_BUSY",
                entry: targetEntry,
                outcome: "busy",
                reason: applyResultReason(busy)
            )
            completion(busy)
            return
        }

        let key = currentMomentaryVoiceTriggerKey
        let hadHardwareMapping = isVoiceHIDMappingEnabled()
        let previousBindingIsModifierChord: Bool = {
            guard let binding = currentVoiceShortcutSnapshot.activeEntry?.binding,
                  case .modifierChord = binding else {
                return false
            }
            return true
        }()
        let targetBindingIsModifierChord: Bool = {
            guard let binding = targetEntry?.binding,
                  case .modifierChord = binding else {
                return false
            }
            return true
        }()
        if previousBindingIsModifierChord,
           targetBindingIsModifierChord,
           !hadHardwareMapping,
           filter.isVoiceTriggerConfiguredConsistently(for: key),
           !filter.shouldSuppressDuringVoiceTriggerReconfiguration(keyCode: VK.voiceKey) {
            completion(.unchanged)
            return
        }

        guard filter.beginVoiceTriggerReconfiguration(from: key, to: key) else {
            logVoiceShortcutConfiguration(
                event: "VOICE_SHORTCUT_CONFIG_BUSY",
                entry: targetEntry,
                outcome: "busy",
                reason: "filter_reconfiguration_busy"
            )
            completion(.busy)
            return
        }
        voiceTriggerReconfigurationInProgress = true
        guard filter.configureVoiceTriggerKey(key) else {
            voiceTriggerReconfigurationInProgress = false
            filter.endVoiceTriggerReconfiguration()
            logVoiceShortcutConfiguration(
                event: "VOICE_SHORTCUT_RUNTIME_RECONFIG_FAILED",
                entry: targetEntry,
                outcome: "failed_before_mapping_change",
                reason: "filter_configuration_failed"
            )
            completion(.busy)
            return
        }
        voiceHIDMappingQueue.async { [weak self] in
            guard let self else { return }
            let disabled = self.applyVoiceHIDMapping(false, key)
            DispatchQueue.main.async { [weak self] in
                guard let self else { completion(.locked); return }
                guard disabled else {
                    self.logVoiceShortcutConfiguration(
                        event: "VOICE_SHORTCUT_ROLLBACK_BEGIN",
                        entry: targetEntry,
                        outcome: "restore_previous_hid_mapping",
                        reason: "chord_mapping_disable_failed"
                    )
                    if hadHardwareMapping {
                        self.voiceHIDMappingQueue.async { [weak self] in
                            guard let self else { return }
                            let restored = self.applyVoiceHIDMapping(true, key)
                            DispatchQueue.main.async { [weak self] in
                                guard let self else { completion(.locked); return }
                                if restored {
                                    self.logVoiceShortcutConfiguration(
                                        event: "VOICE_SHORTCUT_ROLLBACK_COMPLETE",
                                        entry: targetEntry,
                                        outcome: "previous_hid_mapping_restored",
                                        reason: "chord_mapping_disable_failed"
                                    )
                                    self.completeVoiceTriggerReconfiguration(.failed, completion: completion)
                                } else {
                                    self.logVoiceShortcutConfiguration(
                                        event: "VOICE_SHORTCUT_ROLLBACK_FAILED",
                                        entry: targetEntry,
                                        outcome: "runtime_state_uncertain",
                                        reason: "hid_mapping_restore_failed"
                                    )
                                    self.lockVoiceTriggerRuntime(reason: "F5 mapping rollback failed after chord apply")
                                    completion(.locked)
                                }
                            }
                        }
                    } else {
                        self.logVoiceShortcutConfiguration(
                            event: "VOICE_SHORTCUT_ROLLBACK_COMPLETE",
                            entry: targetEntry,
                            outcome: "no_previous_hid_mapping_to_restore",
                            reason: "chord_mapping_disable_failed"
                        )
                        self.completeVoiceTriggerReconfiguration(.failed, completion: completion)
                    }
                    return
                }
                self.logVoiceShortcutConfiguration(
                    event: "VOICE_SHORTCUT_RUNTIME_RECONFIG_COMMITTED",
                    entry: targetEntry,
                    outcome: "chord_mapping_active"
                )
                self.completeVoiceTriggerReconfiguration(.applied, completion: completion)
            }
        }
    }

    private func voiceConfigurationBusyResult() -> VoiceTriggerApplyResult? {
        if voicePress.hasVoiceKeyHeldForReconfiguration || filter.isVoiceKeyHeld {
            return .busyActiveHold
        }
        if voicePress.hasUnresolvedVoiceShortcutOwnership {
            _ = voicePress.recoverPendingVoiceShortcutReleaseOwnership()
            if voicePress.hasUnresolvedVoiceShortcutOwnership {
                return .busyReleaseDrain
            }
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
        let shouldEnable = hidConnected && currentVoiceInputProfile.triggerKey != nil
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
        case .busyReleaseDrain:
            voicePress.hasUnresolvedVoiceShortcutOwnership
                ? "unresolved_voice_shortcut_synthetic_ownership"
                : "release_drain"
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
                "voice_input_trigger_key": currentVoiceInputProfile.triggerKey?.rawValue ?? "chord",
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
        let diagnosticsEnabled = DiagnosticsRuntimeGate.shared.isEnabled
        if diagnosticsEnabled {
            if let input = SystemAudioDeviceManager.defaultInputDevice {
                DiagnosticRuntimeHealthRegistry.shared.setString(
                    "selected_input_identity",
                    input.stableIdentifier
                )
            }
            var runStartFields = P1A4MonotonicClock.runStartCalibrationFields()
            runStartFields["persisted_momentary"] = readPersistedVoiceTriggerKey().rawValue
            runStartFields["persisted_legacy"] = UserDefaults.standard.string(
                forKey: AppStorage.voiceTriggerKeyKey
            ) ?? "none"
            diagnosticLogger.startRun(fields: runStartFields)
        }
        _ = restoreVoiceTriggerRuntime()
        if diagnosticsEnabled {
            let sourceHead = Bundle.main.object(
                forInfoDictionaryKey: "RemoteOrbitDiagnosticSourceHead"
            ) as? String ?? "UNSTAMPED"
            let receiverFinalizationInstrumentation =
                ProcessInfo.processInfo.environment["REMOTE_ORBIT_P1A4_RECEIVER_FINALIZATION"] == "1"
            let instrumentation = receiverFinalizationInstrumentation
                ? "p1-a4-receiver-finalization"
                : "p0"
            print(
                "[AUDIO-PATH] DIAGNOSTIC_BUILD "
                    + "head=\(sourceHead) instrumentation=\(instrumentation)"
            )
        }
        diagnosticsRuntimeObserverRegistered = true
        DiagnosticsRuntimeGate.shared.observe { [weak self] enabled in
            guard let self, self.diagnosticsRuntimeObserverRegistered else { return }
            self.frontmostApplicationDiagnosticsLifecycle.setEnabled(enabled)
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

#if DEBUG
        let qaTapRecreation = NSMenuItem(
            title: "QA：重建语音 Event Tap（一次）",
            action: #selector(performQATapRecreation),
            keyEquivalent: ""
        )
        qaTapRecreation.target = self
        qaTapRecreationMenuItem = qaTapRecreation
        menu.addItem(qaTapRecreation)
        menu.addItem(.separator())
#endif

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
            case .opening, .streaming:
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
        voicePress.onRemoteInputLeaseRelease = {
            SystemAudioDeviceManager.applyPreferredInputSelection()
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
                // A BLE loss can happen before HID emits the matching key-up;
                // the coordinator owns the bounded teardown boundary.
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
                self.cancelVoiceGestureStateForHIDRemoval()
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
        let shouldEnable = active
            && !voiceTriggerRuntimeLocked
            && currentVoiceInputProfile.triggerKey != nil
        let primaryKey = currentVoiceInputProfile.triggerKey ?? currentMomentaryVoiceTriggerKey
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
        for entry in currentVoiceShortcutSnapshot.entries {
            let profile = entry.profile
            let item = NSMenuItem(
                title: profile.displayName,
                action: #selector(selectVoiceInputProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == currentVoiceInputProfile.id ? .on : .off
            item.isEnabled = voiceShortcutReadOnlyReason == nil
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(
            title: "管理语音快捷键…",
            action: #selector(openKeyMapping),
            keyEquivalent: ""
        )
        manage.target = self
        menu.addItem(manage)
    }

    @objc private func selectVoiceInputProfile(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? String,
              let profile = currentVoiceShortcutSnapshot.entries
                .first(where: { $0.id == profileID })?.profile
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
        diagnosticsRuntimeObserverRegistered = false
        frontmostApplicationDiagnosticsLifecycle.stop()
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
        DiagnosticRuntimeHealthService.shared.stop()
        voiceHIDMappingQueue.sync {
            _ = applyVoiceHIDMapping(false, currentMomentaryVoiceTriggerKey)
        }
        diagnosticLogger.close()
    }

    @objc private func openKeyMapping() {
        voiceShortcutPresentation.updateSnapshot = { [weak self] snapshot, completion in
            self?.updateVoiceShortcutSnapshot(snapshot, completion: completion)
                ?? completion(.locked)
        }
        SettingsWindow.open(
            store: mappingStore,
            onRecordingChanged: { [weak self] enabled in
                self?.ble.setRecordingEnabled(enabled)
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
