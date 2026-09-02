// RemoteOrbit: a multi-mode control surface for the Xiaomi Bluetooth Voice Remote 2 Pro.
//
// 1. Voice key (HID F5) → suppressed → bridge-generated Option hold semantics
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

/// Remote voice input is intentionally hold-only:
///
/// * short tap: ignored; no local microphone and no external voice input
/// * hold: remote ATVV microphone + Option hold
///
/// Audio is armed on the first edge so the remote pre-roll is available while
/// the small hold threshold is being crossed. There is no short-press action
/// and no local-microphone fallback in this path.
final class VoicePressCoordinator {
    private enum Mode {
        case idle
        case pending
        case holding
    }

    /// This is only an activation guard, not a short-vs-long classifier. A
    /// quick tap is a no-op; a hold starts remote dictation after 120 ms so
    /// the first spoken syllable is not lost behind the old 300 ms window.
    private let holdActivationThreshold: TimeInterval = 0.12
    // The remote sends AUDIO_STOP before the HID key-up, so there is no BLE
    // tail left to wait for here. Keeping this delay near zero makes Doubao
    // leave its recording UI as soon as the user releases the button.
    private let tailDrainDelay: TimeInterval = 0.02
    private var mode: Mode = .idle
    private var holdWorkItem: DispatchWorkItem?
    private var tailWorkItem: DispatchWorkItem?
    private var remoteStreaming = false
    private var remoteRouted = false
    private var optionIsHeld = false
    private var suppressNewPressUntil = Date.distantPast

    @discardableResult
    func keyDown() -> Bool {
        guard Date() >= suppressNewPressUntil else {
            print("[PRESS] ignored release bounce")
            return false
        }
        guard mode == .idle else { return false }
        AudioPipe.shared.beginRemoteCandidate()
        mode = .pending

        // Keep remote audio routed from the first edge. The hold-only guard
        // must never wait for another process before the remote microphone is
        // armed, so the first decoded frames remain available.
        setRemoteRouted(true)

        let work = DispatchWorkItem { [weak self] in
            self?.promoteToLongPress()
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + holdActivationThreshold,
            execute: work
        )
        print("[PRESS] pending; hold-only activation in 120 ms; short tap is ignored")
        return true
    }

    func keyUp() {
        holdWorkItem?.cancel()
        holdWorkItem = nil

        switch mode {
        case .idle:
            return
        case .pending:
            mode = .idle
            setRemoteRouted(false)
            AudioPipe.shared.endRemoteCandidate()
            print("[PRESS] SHORT ignored; remote voice is hold-only")
        case .holding:
            mode = .idle
            suppressNewPressUntil = Date().addingTimeInterval(
                tailDrainDelay + 0.10
            )
            print("[PRESS] LONG release → finish immediately")
            scheduleLongFinish()
        }
    }

    func setRemoteStreaming(_ streaming: Bool) {
        remoteStreaming = streaming
        // BLE availability is informational only. HID owns gesture lifetime
        // and routing policy; transient ATVV stop/start events must never
        // toggle Doubao or fall back to the physical mic during a hold.
        print(
            "[PRESS] ATVV streaming=\(streaming); " +
            "gesture=\(modeName); routed=\(remoteRouted)"
        )
    }

    func stop() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        tailWorkItem?.cancel()
        tailWorkItem = nil
        if optionIsHeld {
            optionIsHeld = false
            Key.optionUp()
        }
        mode = .idle
        setRemoteRouted(false)
        AudioPipe.shared.endRemoteCandidate()
    }

    private func promoteToLongPress() {
        guard mode == .pending else { return }
        holdWorkItem = nil
        mode = .holding

        // Route selection follows the physical HID hold, not BLE notifications.
        // If ATVV is late or briefly drops, emit silence rather than leaking
        // the physical microphone into a remote-only gesture.
        setRemoteRouted(true)
        print(
            "[PRESS] LONG start → Option DOWN; source=" +
            (remoteStreaming ? "remote ready" : "remote waiting")
        )
        if RemoteVoiceKeyMapping.isEnabled {
            print("[PRESS] LONG uses hardware-held left Option")
            optionIsHeld = false
        } else {
            // Fallback for systems where hidutil could not be applied.
            print("[PRESS] LONG uses synthetic left Option")
            optionIsHeld = true
            Key.optionDown()
        }
    }

    private func scheduleLongFinish() {
        guard optionIsHeld else {
            setRemoteRouted(false)
            AudioPipe.shared.endRemoteCandidate()
            return
        }
        tailWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.tailWorkItem = nil
            self?.finishLongToggle()
        }
        tailWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + tailDrainDelay,
            execute: work
        )
    }

    private func finishLongToggle() {
        guard optionIsHeld else { return }
        optionIsHeld = false
        print("[PRESS] LONG end → Option UP")
        Key.optionUp()
        setRemoteRouted(false)
        AudioPipe.shared.endRemoteCandidate()
    }

    private func setRemoteRouted(_ active: Bool) {
        guard remoteRouted != active else { return }
        remoteRouted = active
        AudioPipe.shared.setRemoteActive(active)
    }

    private var modeName: String {
        switch mode {
        case .idle: return "idle"
        case .pending: return "pending"
        case .holding: return "holding"
        }
    }
}

// MARK: - HID watcher (2 Pro as keyboard, for connection status only)

final class HIDWatcher {
    static let vendorID  = 0x2717
    static let productID = 0x32B8

    var onConnect: ((String) -> Void)?
    var onDisconnect: ((String) -> Void)?

    private var manager: IOHIDManager?

    func start() {
        guard manager == nil else {
            print("[HID] watcher already running")
            return
        }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ] as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, HIDWatcher.deviceMatched, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, HIDWatcher.deviceRemoved, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            print("[HID] IOHIDManagerOpen failed: \(r)")
            IOHIDManagerUnscheduleFromRunLoop(
                m,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }
        manager = m
    }

    func stop() {
        if let m = manager {
            IOHIDManagerUnscheduleFromRunLoop(
                m,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    fileprivate func matched(_ device: IOHIDDevice) {
        let n = nameOf(device)
        print("[HID] 已连接: \(n)")
        onConnect?(n)
    }

    fileprivate func removed(_ device: IOHIDDevice) {
        let n = nameOf(device)
        print("[HID] 断开: \(n)")
        onDisconnect?(n)
    }

    private func nameOf(_ device: IOHIDDevice) -> String {
        if let n = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String { return n }
        return "(unknown)"
    }

    private static let deviceMatched: IOHIDDeviceCallback = { ctx, _, _, device in
        guard let ctx else { return }
        let me = Unmanaged<HIDWatcher>.fromOpaque(ctx).takeUnretainedValue()
        DispatchQueue.main.async { me.matched(device) }
    }
    private static let deviceRemoved: IOHIDDeviceCallback = { ctx, _, _, device in
        guard let ctx else { return }
        let me = Unmanaged<HIDWatcher>.fromOpaque(ctx).takeUnretainedValue()
        DispatchQueue.main.async { me.removed(device) }
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
    private var optionDeferralGestureID: UUID?
    private var deferredOptionDownSeen = false
    private var deferredOptionUpSeen = false
    var onVoiceKeyDown: (() -> Void)?
    var onVoiceKeyUp: (() -> Void)?

    private var optionDeferralActive: Bool {
        optionDeferralGestureID != nil
    }

    /// Whether a specific voice gesture is currently holding the remapped
    /// Option edge. Focus preparation is advisory now, so callers must not
    /// release or replay an Option pair unless this returns true.
    func isOptionDeferralActive(for gestureID: UUID) -> Bool {
        optionDeferralGestureID == gestureID
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
        if let activeGestureID = optionDeferralGestureID,
           activeGestureID != gestureID {
            cancelDeferredOption(
                gestureID: activeGestureID,
                reason: "superseded"
            )
        }
        optionDeferralGestureID = gestureID
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
        print("[VOICE] option gate armed gesture=\(gestureID.uuidString)")
    }

    /// Release a deferred physical Option pair. The gesture identifier makes
    /// this idempotent and prevents a late acknowledgement from releasing a
    /// newer gesture's Option edge.
    func releaseDeferredOption(gestureID: UUID, reason: String) {
        guard optionDeferralGestureID == gestureID else {
            print(
                "[VOICE] ignored stale option release gesture=\(gestureID.uuidString) "
                    + "active=\(optionDeferralGestureID?.uuidString ?? "none")"
            )
            return
        }
        optionDeferralGestureID = nil

        let optionDownSeen = deferredOptionDownSeen
        let optionUpSeen = deferredOptionUpSeen
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false

        // A macOS modifier normally arrives as flagsChanged only. Do not
        // replay that stale event object: normalize it through the same
        // flagsChanged + keyboard event pair used by the known-good fallback.
        // If the release was already captured, emit a real tap; otherwise
        // leave Option held and let the later physical release pass through.
        if optionDownSeen {
            if optionUpSeen {
                Key.optionTap()
            } else {
                Key.optionDown()
            }
        }
        print(
            "[VOICE] option gate released gesture=\(gestureID.uuidString) reason=\(reason) "
                + "optionDown=\(optionDownSeen) optionUp=\(optionUpSeen)"
        )
    }

    /// Drops a fully captured gesture without replaying it. This is used only
    /// when a newer physical press supersedes a completed request; the stale
    /// request must never turn into a delayed Option tap in the new target.
    func cancelDeferredOption(gestureID: UUID, reason: String) {
        guard optionDeferralGestureID == gestureID else { return }
        optionDeferralGestureID = nil
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false
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
                    } else if filter.deferredOptionDownSeen {
                        filter.deferredOptionUpSeen = true
                    }
                case .keyDown:
                    filter.deferredOptionDownSeen = true
                case .keyUp:
                    if filter.deferredOptionDownSeen {
                        filter.deferredOptionUpSeen = true
                    } else {
                        return Unmanaged.passUnretained(event)
                    }
                default:
                    break
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
        print("[FILTER] tap enabled; voice key 0x60 (F5) is suppressed; RemoteOrbit supplies a balanced synthetic left Option hold")
    }

    func stop() {
        if let gestureID = optionDeferralGestureID {
            cancelDeferredOption(gestureID: gestureID, reason: "stop")
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

    private let watcher = HIDWatcher()
    private let filter = VoiceKeyFilter()
    private let voicePress = VoicePressCoordinator()
    private let ble = BLEBridge()
    private let mappingStore = MappingStore()
    private let hidMonitor = HIDMonitor()
    private let buttonGestureRecognizer = ButtonGestureRecognizer()
    private let actionHUD = RemoteActionHUD()
    private var repeatGestureHUDButtons: Set<RemoteButton> = []
    private let voiceFocusTransactions = VoiceFocusTransactionTracker()
    private var voiceFocusSafetyWorkItem: DispatchWorkItem?
    private let voiceFocusSafetyTimeout: TimeInterval = 0.36

    private func beginVoicePress(
        targetApplicationBundleIdentifier lockedTarget: String? = nil
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
        let shouldGateMappedOption = RemoteVoiceKeyMapping.isEnabled
            && needsFocusPreparation

        if let previousGestureID = voiceFocusTransactions.activeGestureID {
            voiceFocusSafetyWorkItem?.cancel()
            voiceFocusSafetyWorkItem = nil
            filter.cancelDeferredOption(
                gestureID: previousGestureID,
                reason: "superseded-by-new-press"
            )
            _ = voiceFocusTransactions.cancel(previousGestureID)
        }

        // The remote's HID mapping produces a real left-Option edge which can
        // beat the asynchronous FloatTabs/Codex focus handoff. Arm the gate
        // before starting the voice transaction so the first edge is not
        // delivered to a stale text client. Audio routing remains immediate
        // inside VoicePressCoordinator and is never held behind focus work.
        if shouldGateMappedOption {
            filter.beginOptionDeferral(gestureID: gestureID)
        }

        guard voicePress.keyDown() else {
            if shouldGateMappedOption {
                filter.cancelDeferredOption(
                    gestureID: gestureID,
                    reason: "voice-press-rejected"
                )
            }
            return
        }

        guard needsFocusPreparation else {
            if shouldGateMappedOption {
                filter.cancelDeferredOption(
                    gestureID: gestureID,
                    reason: "focus-not-needed"
                )
            }
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
        if filter.isOptionDeferralActive(for: gestureID) {
            filter.releaseDeferredOption(
                gestureID: gestureID,
                reason: ready ? "focus-ready" : "focus-failed-\(reason)"
            )
        } else {
            print(
                "[VOICE] focus result is advisory; Option/audio path was not gated "
                    + "gesture=\(gestureID.uuidString)"
            )
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppStorage.prepare()
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

        // HID connection (status icon).
        watcher.onConnect = { [weak self] _ in
            // The voice key is intercepted as the remote's F5 event and the
            // coordinator emits a balanced synthetic Option hold after the
            // hold guard. Do not enable hidutil's second Option event: it
            // races the focus handoff and can make a short tap reach macOS.
            RemoteVoiceKeyMapping.setEnabled(false)
            self?.hidConnected = true
            self?.updateStatus()
        }
        watcher.onDisconnect = { [weak self] _ in
            RemoteVoiceKeyMapping.setEnabled(false)
            self?.voicePress.stop()
            self?.hidConnected = false
            self?.updateStatus()
        }
        watcher.start()

        // ATVV audio connection.
        filter.onVoiceKeyDown = { [weak self] in
            self?.beginVoicePress()
        }
        filter.onVoiceKeyUp = { [weak self] in
            self?.voicePress.keyUp()
        }
        ble.onConnectionChanged = { [weak self] connected in
            self?.bleConnected = connected
            if !connected {
                self?.remoteStreaming = false
                // A BLE loss can happen before HID emits the matching key-up.
                // Release the gesture and any synthetic modifier immediately;
                // reconnecting the audio link must never leave a stale hold.
                self?.voicePress.stop()
            }
            self?.updateStatus()
        }
        ble.onStreamingChanged = { [weak self] streaming, _ in
            self?.voicePress.setRemoteStreaming(streaming)
            self?.remoteStreaming = streaming
            self?.updateStatus()
        }
        ble.start()

        // Route recognized advanced gestures to the same binding injector as
        // ordinary button actions. Without this callback the recognizer can
        // classify a long press correctly but the selected action is dropped.
        buttonGestureRecognizer.onEvent = { [weak self] event in
            self?.handleGestureEvent(event)
        }

        // HID Monitor：读取遥控器所有按钮的原始 HID 报告
        // HID 设备连接/断开时切换语音键处理路径
        hidMonitor.onDeviceChange = { [weak self] active in
            self?.filter.skipVoiceKey = active
            if !active {
                // Device removal does not guarantee a final HID report. Stop
                // voice and advanced gestures explicitly so a lost release
                // cannot leave Option held or a repeat stream alive.
                self?.voicePress.stop()
                self?.mappingStore.clearPressedBindings()
                self?.buttonGestureRecognizer.cancelAll()
                self?.repeatGestureHUDButtons.removeAll()
                self?.actionHUD.dismiss()
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
                        keepsPendingVisible: true
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
                    return
                }
                binding = self.mappingStore.endPress(for: button)
            }

            // 语音键：仅在绑定为 voiceKeyDefault 时走 VoicePressCoordinator
            if button == .microphone {
                if case .voiceKeyDefault = binding {
                    if isDown {
                        self.actionHUD.show(
                            button: button,
                            gesture: "按住",
                            action: "遥控器语音输入",
                            state: .pending
                        )
                        self.beginVoicePress(
                            targetApplicationBundleIdentifier: self.mappingStore
                                .activePressApplicationBundleIdentifier(for: button)
                        )
                    } else {
                        self.voicePress.keyUp()
                    }
                    return
                }
                // 用户自定义了映射，走正常注入流程
                guard !binding.isDisabled else { return }
                if isDown {
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
                    let sent = KeyInjector.sendUp(binding)
                    print("[KEY] \(button.displayName) up → \(binding.displayName); sent=\(sent)")
                }
                return
            }

            // 其他按钮：使用按下时锁定的映射并注入
            guard !binding.isDisabled else { return }
            if isDown {
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
        } else if hidConnected && bleConnected && audioOutputReady {
            stopRecordingStatusPulse()
            setStatusSummary("状态 · 已就绪", color: .systemGreen)
            setStatusIcon(systemName: "circle.dotted.and.circle", color: .white)
        } else if hidConnected && bleConnected {
            stopRecordingStatusPulse()
            setStatusSummary("状态 · 音频设备未就绪", color: .systemRed)
            setStatusIcon(systemName: "waveform.slash", color: .systemRed)
        } else if hidConnected || bleConnected {
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
        } else {
            audioTitle = "语音链路 · 未连接"
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
        watcher.stop()
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
