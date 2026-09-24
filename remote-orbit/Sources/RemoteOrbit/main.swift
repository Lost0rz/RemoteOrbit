// RemoteOrbit: a multi-mode control surface for the Xiaomi Bluetooth Voice Remote 2 Pro.
//
// 1. Voice key (HID F5) → device-scoped physical left-Option mapping
//    (synthetic Option remains only as a fallback if hidutil cannot apply)
// 2. ATVV voice stream over BLE → decoded ADPCM → RemoteOrbit Mic 2ch
//    → macOS audio input → Doubao hears the selected source
//
// macOS-only. Requires:
//   * 2 Pro paired in System Settings → Bluetooth
//   * Accessibility permission (System Settings → Privacy & Security →
//     Accessibility) for the CGEvent tap that filters F6
//   * RemoteOrbitAudio.driver installed and visible as RemoteOrbit Mic 2ch in
//     System Settings → Sound → Input/Output
//   * Doubao IME configured for Option-as-voice-mode trigger
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
        postOption(keyDown: true)
    }
    static func optionUp() {
        postOption(keyDown: false)
    }
    /// A deliberate short Option click for Doubao's toggle mode.
    ///
    /// Posting down and up back-to-back is sometimes too fast for an input
    /// method to classify as a real click, so keep the modifier down briefly.
    static func optionTap(completion: (() -> Void)? = nil) {
        optionDown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            optionUp()
            completion?()
        }
    }

    /// Doubao needs both the modifier-state transition and a normal keyboard
    /// event. The former makes macOS track left Option correctly; the latter
    /// is what Doubao's global shortcut listener sees.
    private static func postOption(keyDown: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let flags: CGEventFlags = keyDown ? .maskAlternate : []

        if let flagsEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: VK.option,
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
            virtualKey: VK.option,
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

/// Map only the supported remote's F5 usage to a real left Option at the HID
/// event-system layer. Doubao recognizes this physical mapping reliably.
/// The event tap may briefly defer this mapped Option pair only when FloatTabs
/// needs to repair a stale WebKit text client.
enum RemoteVoiceKeyMapping {
    private static let lock = NSLock()
    private static var enabled = false
    private static let matching = "{\"VendorID\":0x2717,\"ProductID\":0x32B8}"
    private static let mapping =
        "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000003E," +
        "\"HIDKeyboardModifierMappingDst\":0x7000000E2}]}"
    private static let emptyMapping = "{\"UserKeyMapping\":[]}"

    static var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    @discardableResult
    static func setEnabled(_ shouldEnable: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = [
            "property", "--matching", matching,
            "--set", shouldEnable ? mapping : emptyMapping,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[HID-MAP] 执行 hidutil 失败: \(error.localizedDescription)")
            lock.lock()
            enabled = false
            lock.unlock()
            return false
        }

        let succeeded = process.terminationStatus == 0
        lock.lock()
        enabled = shouldEnable && succeeded
        lock.unlock()
        print(
            "[HID-MAP] 遥控器语音键 → 左 Option " +
            (shouldEnable && succeeded ? "已启用" : shouldEnable ? "启用失败" : "已关闭")
        )
        return succeeded
    }
}

// MARK: - Voice-button gesture state machine

/// The physical voice button exposes two independent input paths:
///
/// * short tap: one Doubao Option tap, using the Mac/external microphone
/// * hold: remote ATVV microphone + Option hold
///
/// The remote transport is opened only after the hold threshold, so a short
/// tap never selects the RemoteOrbit virtual microphone. A configured Codex
/// voice action may replace the short tap, but it remains inside this
/// classifier rather than becoming a normal one-button injection.
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
        let togglesLocalMicrophone: Bool
        let bypassesShortClassification: Bool
        let usesHardwareOption: Bool
        let preparesRemoteTransport: Bool
        var isStillHeld = true
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
    var onHardwareOptionGateShortResult: ((UUID, Bool) -> Void)?
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

    /// This is the short-vs-long classifier. A quick tap invokes Doubao's
    /// computer/external-microphone input (or the optional Codex short action);
    /// a hold starts remote dictation after the original 300 ms window.
    ///
    /// Keep this at 300 ms: the old hold-only experiment lowered it to 120 ms,
    /// but once short-press behavior was restored that made an ordinary tap
    /// look like a long press and opened Doubao unexpectedly.
    static let holdActivationThreshold: TimeInterval = 0.30
    // The remote usually sends AUDIO_STOP just before the HID key-up, and the
    // BLE bridge keeps accepting packets during its drain window. Keep the
    // output route alive long enough for those final frames to render even
    // when the physical Option edge has already been released.
    private let tailDrainDelay: TimeInterval = 0.80
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
    private var shortInputClosesLocalMicrophoneSession = false
    private var shortInputTogglesLocalMicrophone = false
    /// The default Doubao short action is a toggle: the first tap opens the
    /// external-microphone input and the next tap closes it. Keep this state
    /// separate from the current physical gesture so a closing tap never
    /// starts AVCapture again while it is waiting to send Option-up.
    private var localShortVoiceSessionActive = false
    private var gestureID: UUID?
    private var pendingShortPreparationID: UUID?
    private var usesHardwareOptionPath = false
    private var remoteOutputDrainRequestedSessionID: UUID?
    private var remoteOutputDrainedSessionID: UUID?
    private var physicalUpSessionID: UUID?
    private var awaitingPhysicalVoiceKeyUp = false
    private var pendingVoiceUIHidden = false
    private let syntheticOptionTrigger: VoiceOptionTrigger

    init(optionTrigger: VoiceOptionTrigger = .shared) {
        syntheticOptionTrigger = optionTrigger
    }

    /// Only these short actions need RemoteOrbit to capture the Mac's
    /// physical/external microphone. The remote-microphone long press is
    /// independent and must never inherit this requirement.
    static func usesLocalMicrophone(forShortBinding binding: ButtonBinding) -> Bool {
        switch binding {
        case .voiceKeyDefault:
            return true
        case .preset(.chatGPTStartVoiceChat), .preset(.chatGPTStartDictation):
            return true
        default:
            return false
        }
    }

    static func togglesLocalMicrophone(forShortBinding binding: ButtonBinding) -> Bool {
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

    var currentStateForTesting: State {
        mode
    }

    var tailDrainDelayForTesting: TimeInterval {
        tailDrainDelay
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
        togglesLocalMicrophone: Bool = false,
        bypassesShortClassification: Bool = false,
        usesHardwareOption: Bool = false,
        preparesRemoteTransport: Bool = false
    ) -> Bool {
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
        guard mode == .idle else { return false }
        if remoteRouted || longInputStarted || tailWorkItem != nil {
            if pendingRepress == nil {
                pendingRepress = PendingRepress(
                    sessionID: sessionID,
                    physicalDownAt: physicalDownAt,
                    onShortTap: onShortTap,
                    usesLocalMicrophone: usesLocalMicrophone,
                    togglesLocalMicrophone: togglesLocalMicrophone,
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
            togglesLocalMicrophone: togglesLocalMicrophone,
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
        togglesLocalMicrophone: Bool,
        bypassesShortClassification: Bool,
        usesHardwareOption: Bool,
        preparesRemoteTransport: Bool
    ) -> Bool {
        // A new physical press owns the voice key now. Do not keep a local
        // session left by an earlier short tap alive during the classifier:
        // if this press becomes a hold, the physical mic must be closed from
        // the first edge, not only after the 300 ms timer fires. When the
        // default Doubao toggle is already open, remember that this tap is a
        // close operation so keyUp can send Option immediately without
        // reopening AVCapture first.
        pendingShortPreparationID = nil
        AudioPipe.shared.setLocalMicrophoneCaptureEnabled(false)
        shortTapAction = onShortTap
        shortInputClosesLocalMicrophoneSession =
            togglesLocalMicrophone && localShortVoiceSessionActive
        shortInputTogglesLocalMicrophone = togglesLocalMicrophone
        shortInputUsesLocalMicrophone =
            usesLocalMicrophone && !shortInputClosesLocalMicrophoneSession
        usesHardwareOptionPath = usesHardwareOption
        remoteOutputDrainRequestedSessionID = nil
        remoteOutputDrainedSessionID = nil
        physicalUpSessionID = nil
        awaitingPhysicalVoiceKeyUp = false
        pendingVoiceUIHidden = preparesRemoteTransport
        gestureID = sessionID
        VoiceTimingLogger.begin(sessionID: sessionID)
        _ = syntheticOptionTrigger.begin(sessionID: sessionID)
        if usesHardwareOptionPath {
            onHardwareOptionGateBegin?(sessionID)
        }
        remoteAudioAvailable = false
        longInputStarted = false
        AudioPipe.shared.beginRemoteCandidate()

        if bypassesShortClassification {
            enterHoldingState()
            return true
        }

        setMode(.pending)
        if preparesRemoteTransport && !bypassesShortClassification {
            onRemoteTransportPreparation?()
        }
        let heldDuration = max(
            0,
            ProcessInfo.processInfo.systemUptime - physicalDownAt
        )
        let remainingHoldTime = Self.holdActivationThreshold - heldDuration
        guard remainingHoldTime > 0 else {
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
        print("[PRESS] pending; classifying short tap vs remote-mic hold in 300 ms")
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
                    completeLongInputIfReady(sessionID: currentGestureID)
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
            let shouldCloseLocalMicrophoneSession = shortInputClosesLocalMicrophoneSession
            shortInputClosesLocalMicrophoneSession = false
            let shouldTrackLocalMicrophoneSession = shortInputTogglesLocalMicrophone
            shortInputTogglesLocalMicrophone = false
            let currentGestureID = gestureID
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
            if shouldCloseLocalMicrophoneSession {
                // The default short action is a toggle. The local capture was
                // already stopped at keyDown to keep a possible long hold
                // isolated; do not start it again just to deliver the close
                // click.
                localShortVoiceSessionActive = false
                print("[PRESS] SHORT release → closing Doubao without microphone restart")
                if let currentGestureID {
                    onHardwareOptionGateShortResult?(currentGestureID, true)
                    emitShortPress(
                        sessionID: currentGestureID,
                        usesHardwareOption: shouldUseHardwareOption
                    )
                }
            } else if shouldPrepareLocalMicrophone, let currentGestureID {
                pendingShortPreparationID = currentGestureID
                print("[PRESS] SHORT release → preparing local microphone")
                AudioPipe.shared.setLocalMicrophoneCaptureEnabled(true) { [weak self] in
                    guard let self,
                          self.pendingShortPreparationID == currentGestureID else { return }
                    self.pendingShortPreparationID = nil
                    if shouldTrackLocalMicrophoneSession {
                        self.localShortVoiceSessionActive = true
                    }
                    if let action {
                        print("[PRESS] SHORT local microphone ready → configured voice action")
                        self.onHardwareOptionGateShortResult?(currentGestureID, false)
                        _ = self.syntheticOptionTrigger.abort(sessionID: currentGestureID)
                        action()
                    } else {
                        print("[PRESS] SHORT local microphone ready → Doubao")
                        self.onHardwareOptionGateShortResult?(currentGestureID, true)
                        self.emitShortPress(
                            sessionID: currentGestureID,
                            usesHardwareOption: shouldUseHardwareOption
                        )
                    }
                }
            } else if let action {
                print("[PRESS] SHORT release → configured voice action")
                if let currentGestureID {
                    onHardwareOptionGateShortResult?(currentGestureID, false)
                    _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
                }
                action()
            } else {
                print("[PRESS] SHORT release → Doubao")
                if let currentGestureID {
                    onHardwareOptionGateShortResult?(currentGestureID, true)
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
            if let releasedSessionID {
                physicalUpSessionID = releasedSessionID
                if usesHardwareOptionPath {
                    onHardwareOptionGatePhysicalUp?(releasedSessionID)
                }
            }
            if let currentGestureID = gestureID, !longInputStarted {
                onHardwareOptionGateCancel?(currentGestureID)
                _ = syntheticOptionTrigger.abort(sessionID: currentGestureID)
                gestureID = nil
                usesHardwareOptionPath = false
            }
            setMode(.idle)
            let physicalUpAt = Date()
            lastPhysicalUpAt = physicalUpAt
            releaseBounceDebounceUntil = physicalUpAt.addingTimeInterval(
                releaseBounceDebounce
            )
            if longInputStarted {
                print("[PRESS] LONG release → finish immediately")
                scheduleLongFinish(sessionID: gestureID)
            } else {
                print("[PRESS] LONG release → no remote audio; no Option dialog")
                finishLongInput(sessionID: nil)
            }
            return true
        }
    }

    func setRemoteStreaming(_ streaming: Bool) {
        remoteStreaming = streaming
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
        // and routing policy; transient ATVV stop/start events must never
        // toggle Doubao or fall back to the physical mic during a hold.
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

    private func stopCurrentVoiceState(preservingDeferredRepress: Bool) {
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
        shortInputClosesLocalMicrophoneSession = false
        shortInputTogglesLocalMicrophone = false
        localShortVoiceSessionActive = false
        let stoppedSessionID = gestureID
        if let currentGestureID = gestureID {
            onHardwareOptionGateCancel?(currentGestureID)
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
        enterHoldingState()
    }

    private func enterHoldingState() {
        guard let currentGestureID = gestureID else { return }
        VoiceTimingLogger.mark("HOLD_CONFIRMED", sessionID: currentGestureID)
        VoiceTimingLogger.mark("BLE_START_REQUEST", sessionID: currentGestureID)
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
        print("[PRESS] LONG audio ready → Option DOWN; source=remote")
        guard let currentGestureID = gestureID else { return }
        if usesHardwareOptionPath {
            print("[PRESS] LONG uses hardware-held left Option")
            onHardwareOptionGateLongReady?(currentGestureID)
            VoiceTimingLogger.mark("OPTION_GATE_RELEASE", sessionID: currentGestureID)
        } else {
            // Fallback for systems where hidutil could not be applied.
            print("[PRESS] LONG uses synthetic left Option")
            _ = syntheticOptionTrigger.sendDown(sessionID: currentGestureID)
            VoiceTimingLogger.mark("OPTION_GATE_RELEASE", sessionID: currentGestureID)
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
            deadline: .now() + tailDrainDelay,
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
            togglesLocalMicrophone: pendingRepress.togglesLocalMicrophone,
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
        remoteOutputDrainRequestedSessionID = sessionID

        let completion = { [weak self] in
            guard let self,
                  self.gestureID == sessionID,
                  self.longInputStarted else { return }
            self.remoteOutputDrainedSessionID = sessionID
            VoiceTimingLogger.mark("AUDIO_PIPELINE_CLOSED", sessionID: sessionID)
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
        if usesHardwareOptionPath {
            onHardwareOptionGateOutputDrained?(sessionID)
            print("[PRESS] LONG end → Option UP after output drain")
        } else if syntheticOptionTrigger.sendUp(sessionID: sessionID) {
            print("[PRESS] LONG end → synthetic Option UP after output drain")
        } else {
            _ = syntheticOptionTrigger.abort(sessionID: sessionID)
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
        if mode != .idle {
            setMode(.idle)
        }
        VoiceTimingLogger.mark("ROUTE_OFF", sessionID: sessionID)
        VoiceTimingLogger.end(sessionID: sessionID)
        scheduleDeferredRepressActivation()
    }

    private func completeVoiceRouteWithoutAudio(sessionID: UUID) {
        onHardwareOptionGateCancel?(sessionID)
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
        VoiceTimingLogger.mark("ROUTE_OFF", sessionID: sessionID)
        VoiceTimingLogger.end(sessionID: sessionID)
        scheduleDeferredRepressActivation()
    }

    /// Preserve the original Doubao integration: one short voice-key press
    /// is a single Option tap, which lets Doubao use the physical microphone
    /// selected by macOS/RemoteOrbit's stable virtual input path.
    private func emitShortPress(
        sessionID: UUID,
        usesHardwareOption: Bool
    ) {
        if usesHardwareOption {
            print("[PRESS] SHORT → hardware Option tap; source=Doubao Mac/external microphone")
        } else {
            print("[PRESS] SHORT → synthetic Option tap; source=Doubao Mac/external microphone")
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
    private let syntheticOptionTrigger = VoiceOptionTrigger.shared
    private var deferredOptionDownSeen = false
    private var deferredOptionUpSeen = false
    private var deferredOptionDownEvents: [CGEvent] = []
    private var deferredOptionUpEvents: [CGEvent] = []
    private var heldHardwareOptionSessionID: UUID?
    private var heldHardwareOptionUpEvents: [CGEvent] = []
    private var heldHardwareOptionFlagsUpSeen = false
    private var heldHardwareOptionKeyUpSeen = false
    private var hardwareOptionReleaseArmed = false
    var onVoiceKeyDown: (() -> Void)?
    var onVoiceKeyUp: (() -> Void)?

    private var optionDeferralActive: Bool {
        optionGate.activeSessionID != nil
    }

    /// Whether a specific voice gesture is currently holding the remapped
    /// Option edge. Focus preparation is advisory now, so callers must not
    /// release or replay an Option pair unless this returns true.
    func isOptionDeferralActive(for gestureID: UUID) -> Bool {
        optionGate.activeSessionID == gestureID
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
        if let heldSessionID = heldHardwareOptionSessionID,
           heldSessionID != gestureID {
            abortHeldHardwareOption(
                gestureID: heldSessionID,
                reason: "superseded"
            )
        }
        if let activeGestureID = optionGate.activeSessionID,
           activeGestureID != gestureID {
            cancelDeferredOption(
                gestureID: activeGestureID,
                reason: "superseded"
            )
        }
        _ = optionGate.begin(sessionID: gestureID)
        _ = syntheticOptionTrigger.begin(sessionID: gestureID)
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
        deferredOptionDownEvents.removeAll(keepingCapacity: true)
        deferredOptionUpEvents.removeAll(keepingCapacity: true)
        print("[VOICE] option gate armed gesture=\(gestureID.uuidString)")
    }

    /// Drop any older physical gate before a new gesture selects its Option
    /// source. This also covers a new synthetic-fallback gesture, which does
    /// not arm a replacement physical gate of its own.
    func cancelActiveOptionDeferral(reason: String) {
        if let gestureID = optionGate.activeSessionID {
            cancelDeferredOption(gestureID: gestureID, reason: reason)
        } else if let gestureID = heldHardwareOptionSessionID {
            abortHeldHardwareOption(gestureID: gestureID, reason: reason)
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
    }

    /// Called after the raw HID microphone-up was accepted for this gesture.
    func armHardwareOptionRelease(gestureID: UUID) {
        guard heldHardwareOptionSessionID == gestureID else { return }
        hardwareOptionReleaseArmed = true
        print("[VOICE] hardware Option-up armed gesture=\(gestureID.uuidString)")
    }

    /// Release the captured hardware Option-up after remote output drains.
    /// If macOS did not deliver a matching up, use the existing synthetic
    /// helper only as an emergency balancing edge.
    func releaseHeldHardwareOption(gestureID: UUID, reason: String) {
        guard heldHardwareOptionSessionID == gestureID else {
            print(
                "[VOICE] ignored stale hardware Option-up release gesture="
                    + "\(gestureID.uuidString) active="
                    + "\(heldHardwareOptionSessionID?.uuidString ?? "none")"
            )
            return
        }
        let events = heldHardwareOptionUpEvents
        clearHeldHardwareOption()
        if events.isEmpty {
            Key.optionUp()
            print("[VOICE] hardware Option-up missing; emergency balancing up")
        } else {
            events.forEach { $0.post(tap: .cghidEventTap) }
        }
        VoiceTimingLogger.mark("OPTION_UP_EMITTED", sessionID: gestureID)
        print(
            "[VOICE] hardware Option-up released gesture=\(gestureID.uuidString) "
                + "reason=\(reason)"
        )
    }

    private func abortHeldHardwareOption(gestureID: UUID, reason: String) {
        guard heldHardwareOptionSessionID == gestureID else { return }
        let events = heldHardwareOptionUpEvents
        clearHeldHardwareOption()
        if events.isEmpty {
            Key.optionUp()
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
                return Unmanaged.passUnretained(event)
            }

            // hidutil converts the remote's F5 usage into left Option. When a
            // FloatTabs voice handoff is active, hold that generated Option
            // pair only; real keyboard Option events remain untouched outside
            // this narrow gesture window.
            if keyCode == VK.option,
               filter.optionDeferralActive {
                switch type {
                case .flagsChanged:
                    if event.flags.contains(.maskAlternate) {
                        filter.deferredOptionDownSeen = true
                        let copiedEvent = event.copy()
                        _ = filter.optionGate.capture(
                            .down,
                            copied: copiedEvent != nil
                        )
                        if let copiedEvent {
                            filter.deferredOptionDownEvents.append(copiedEvent)
                        }
                    } else if filter.deferredOptionDownSeen {
                        filter.deferredOptionUpSeen = true
                        let copiedEvent = event.copy()
                        _ = filter.optionGate.capture(
                            .up,
                            copied: copiedEvent != nil
                        )
                        if let copiedEvent {
                            filter.deferredOptionUpEvents.append(copiedEvent)
                        }
                    }
                case .keyDown:
                    filter.deferredOptionDownSeen = true
                    let copiedEvent = event.copy()
                    _ = filter.optionGate.capture(
                        .down,
                        copied: copiedEvent != nil
                    )
                    if let copiedEvent {
                        filter.deferredOptionDownEvents.append(copiedEvent)
                    }
                case .keyUp:
                    if filter.deferredOptionDownSeen {
                        filter.deferredOptionUpSeen = true
                        let copiedEvent = event.copy()
                        _ = filter.optionGate.capture(
                            .up,
                            copied: copiedEvent != nil
                        )
                        if let copiedEvent {
                            filter.deferredOptionUpEvents.append(copiedEvent)
                        }
                    } else {
                        return Unmanaged.passUnretained(event)
                    }
                default:
                    break
                }
                return nil
            }

            // Once a long hardware replay has been selected and the raw HID
            // voice-key up is accepted, hold only that session's mapped
            // Option-up until AudioPipe confirms the queued PCM is drained.
            if keyCode == VK.option,
               filter.heldHardwareOptionSessionID != nil,
               filter.hardwareOptionReleaseArmed {
                switch type {
                case .flagsChanged:
                    guard !event.flags.contains(.maskAlternate),
                          !filter.heldHardwareOptionFlagsUpSeen else {
                        return nil
                    }
                    filter.heldHardwareOptionFlagsUpSeen = true
                case .keyUp:
                    guard !filter.heldHardwareOptionKeyUpSeen else {
                        return nil
                    }
                    filter.heldHardwareOptionKeyUpSeen = true
                default:
                    return Unmanaged.passUnretained(event)
                }
                if let copiedEvent = event.copy() {
                    filter.heldHardwareOptionUpEvents.append(copiedEvent)
                }
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

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusLabel: NSMenuItem!
    private var remoteStatusItem: NSMenuItem!
    private var audioStatusItem: NSMenuItem!
    private var audioInputMenu: NSMenu!
    private var audioOutputMenu: NSMenu!

    private var hidConnected = false
    private var bleConnected = false
    private var remoteStreaming = false
    private var statusPulseTimer: Timer?
    private var statusPulsePhase = false

    private let filter = VoiceKeyFilter()
    private let voicePress = VoicePressCoordinator()
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

    static func bypassesShortClassification(for _: ButtonBinding) -> Bool {
        // A disabled short action still uses the normal classifier.
        false
    }

    private func beginVoicePress(
        targetApplicationBundleIdentifier lockedTarget: String? = nil,
        shortBinding: ButtonBinding? = nil
    ) {
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
        let gestureID = UUID()
        // Gate every gesture while the real HID mapping is active. Otherwise
        // a disabled short slot could still leak the mapped Option into
        // Doubao before the 300 ms classifier resolves the press.
        // VoiceKeyFilter is the fallback path used while the HID monitor is
        // unavailable. It used to pass nil here, which accidentally meant
        // “use the Doubao default” even when the user disabled the single-tap
        // slot. Resolve the same app-scoped binding used by HID before
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
        let togglesLocalMicrophone = VoicePressCoordinator.togglesLocalMicrophone(
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
            // nil deliberately selects VoicePressCoordinator's original
            // Doubao Option-tap path: one tap, computer/external microphone.
            shortTapAction = nil
        case let binding where binding.isDisabled:
            // A disabled short slot must not fall through to the Doubao
            // default. The long remote-mic slot remains fully independent.
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

        guard voicePress.keyDown(
            sessionID: gestureID,
            onShortTap: shortTapAction,
            usesLocalMicrophone: usesLocalMicrophone,
            togglesLocalMicrophone: togglesLocalMicrophone,
            bypassesShortClassification: bypassesShortClassification,
            usesHardwareOption: RemoteVoiceKeyMapping.isEnabled,
            preparesRemoteTransport: resolvedShortBinding.isDisabled
        ) else {
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
        if !RemoteVoiceKeyMapping.isEnabled {
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
                // Do not open ATVV for a short tap. The coordinator promotes
                // only after the long-press threshold has been crossed.
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
        voicePress.onHardwareOptionGateShortResult = { [weak self] gestureID, shouldRelease in
            guard let self else { return }
            if shouldRelease {
                self.filter.releaseDeferredOption(
                    gestureID: gestureID,
                    reason: "short-doubao"
                )
            } else {
                self.filter.cancelDeferredOption(
                    gestureID: gestureID,
                    reason: "short-binding-disabled-or-custom"
                )
            }
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
            self?.beginVoicePress()
        }
        filter.onVoiceKeyUp = { [weak self] in
            guard let self else { return }
            if self.voicePress.keyUp() {
                self.ble.stopVoiceInput()
            }
        }
        ble.onConnectionChanged = { [weak self] connected in
            self?.bleConnected = connected
            if !connected {
                self?.remoteStreaming = false
                // A BLE loss can happen before HID emits the matching key-up.
                // Release A immediately, but preserve a deferred B until the
                // old transport callback stack has returned to the run loop.
                self?.voicePress.stopCurrentVoiceStatePreservingDeferredRepress()
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
            // Restore the original device-scoped HID path. The event tap
            // temporarily gates the resulting physical Option edge so short
            // disabled/custom bindings still get dropped before Doubao sees
            // them; long press replays the untouched HID event.
            RemoteVoiceKeyMapping.setEnabled(active)
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
                // Device removal does not guarantee a final HID report. Stop
                // voice and advanced gestures explicitly so a lost release
                // cannot leave Option held or a repeat stream alive.
                self.voicePress.stop()
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
                            shortBinding: binding
                        )
                    } else {
                        if self.voicePress.keyUp() {
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
        hidMonitor.start()

        // Start the loopback engine eagerly so device binding is verified
        // before the first BLE audio packet arrives.
        _ = AudioPipe.shared

        // F6 filter (may prompt for Accessibility).
        do {
            try filter.start()
        } catch {
            let msg = error.localizedDescription
            setStatusSummary("状态 · \(msg)", color: .systemOrange)
            setStatusIcon(systemName: "exclamationmark.triangle", color: .systemOrange)
            print("[ERR] filter: \(msg)")
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
        RemoteVoiceKeyMapping.setEnabled(false)
    }

    @objc private func openKeyMapping() {
        SettingsWindow.open(
            store: mappingStore,
            onRecordingChanged: { [weak self] enabled in
                self?.ble.setRecordingEnabled(enabled)
            }
        )
    }

}

// MARK: - Entry

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
