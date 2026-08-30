// RemoteOrbit: a multi-mode control surface for the Xiaomi Bluetooth Voice Remote 2 Pro.
//
// 1. Voice key (HID F5) → suppressed → bridge-generated Option semantics
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

/// Separates the remote's one physical voice button into two mutually
/// exclusive Doubao gestures:
///
/// * short press: Option tap + automatically selected physical microphone
/// * long press:  Option hold + remote ATVV microphone
///
/// We cannot know which gesture the user intends on the initial key-down, so
/// the event is held for a short classification window. Crucially, BLE
/// AUDIO_START alone never changes the routed microphone.
final class VoicePressCoordinator {
    private enum Mode {
        case idle
        case pending
        case holding
    }

    private let longPressThreshold: TimeInterval = 0.30
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

    func keyDown() {
        guard Date() >= suppressNewPressUntil else {
            print("[PRESS] ignored release bounce")
            return
        }
        guard mode == .idle else { return }
        AudioPipe.shared.beginRemoteCandidate()
        mode = .pending

        // Keep remote audio routed from the first edge. The short/long
        // classifier is independent from FloatTabs focus and must never wait
        // for another process before the remote microphone is armed.
        setRemoteRouted(true)

        let work = DispatchWorkItem { [weak self] in
            self?.promoteToLongPress()
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + longPressThreshold,
            execute: work
        )
        print("[PRESS] pending; waiting 300 ms to classify tap vs hold")
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
            emitShortPress()
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

    private func emitShortPress() {
        if RemoteVoiceKeyMapping.isEnabled {
            // The mapped physical Option tap is intercepted/released by
            // VoiceKeyFilter only while FloatTabs is repairing focus.
            print("[PRESS] SHORT → hardware Option tap; source=Doubao auto-selected microphone")
        } else {
            // Fallback for systems where hidutil could not be applied.
            print("[PRESS] SHORT → synthetic Option tap; source=Doubao auto-selected microphone")
            Key.optionTap()
        }
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
            return
        }
        manager = m
    }

    func stop() {
        if let m = manager {
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
    private var voiceKeyIsDown = false
    private var optionDeferralActive = false
    private var deferredOptionDownSeen = false
    private var deferredOptionUpSeen = false
    private var optionDeferralWorkItem: DispatchWorkItem?
    var onVoiceKeyDown: (() -> Void)?
    var onVoiceKeyUp: (() -> Void)?

    /// HIDMonitor 活跃时跳过语音键处理（防止双重触发）。
    var skipVoiceKey = false

    /// Temporarily hold only the Option events generated by the Xiaomi
    /// voice-key remap. The event tap returns immediately; FloatTabs focus is
    /// repaired in parallel and the captured modifier state is normalized
    /// into a fresh Option event pair when ready.
    /// This prevents the first Option edge from beating a stale WebKit text
    /// client without blocking the event-tap thread.
    func beginOptionDeferral() {
        optionDeferralWorkItem?.cancel()
        optionDeferralActive = true
        deferredOptionDownSeen = false
        deferredOptionUpSeen = false

        let work = DispatchWorkItem { [weak self] in
            self?.releaseDeferredOption(reason: "fallback-timeout")
        }
        optionDeferralWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.22,
            execute: work
        )
        print("[FLOATTABS] option deferral started; timeoutMs=220")
    }

    /// Release a deferred physical Option pair. This is idempotent because
    /// either the FloatTabs acknowledgement or the short fallback timer may
    /// win the race.
    func releaseDeferredOption(reason: String) {
        guard optionDeferralActive else { return }
        optionDeferralActive = false
        optionDeferralWorkItem?.cancel()
        optionDeferralWorkItem = nil

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
            "[FLOATTABS] option deferral released reason=\(reason) "
                + "optionDown=\(optionDownSeen) optionUp=\(optionUpSeen)"
        )
    }

    func start() throws {
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
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let filter = Unmanaged<VoiceKeyFilter>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = filter.tapPort {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    print("[FILTER] event tap was disabled; re-enabled")
                }
                return Unmanaged.passRetained(event)
            }
            let keyCode = CGKeyCode(
                event.getIntegerValueField(.keyboardEventKeycode)
            )

            // 跳过 App 自身合成的事件（防止递归拦截）
            let userData = event.getIntegerValueField(.eventSourceUserData)
            if userData == Key.syntheticMarker {
                return Unmanaged.passRetained(event)
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
                        return Unmanaged.passRetained(event)
                    }
                default:
                    break
                }
                return nil
            }

            if keyCode == VK.voiceKey {
                if filter.skipVoiceKey {
                    return Unmanaged.passRetained(event)
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

            return Unmanaged.passRetained(event)
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
            throw FilterError.tapCreationFailed
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[FILTER] tap enabled; voice key 0x60 (F5) is suppressed; hidutil supplies left Option (FloatTabs handoff is non-blocking)")
    }

    func stop() {
        releaseDeferredOption(reason: "stop")
        if voiceKeyIsDown {
            voiceKeyIsDown = false
            onVoiceKeyUp?()
        }
        if let t = tapPort { CGEvent.tapEnable(tap: t, enable: false) }
        tapPort = nil
    }
}

// MARK: - Menu bar UI

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusLabel: NSMenuItem!
    private var remoteStatusItem: NSMenuItem!
    private var audioStatusItem: NSMenuItem!

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
    private func beginVoicePress() {
        let needsFloatTabsFocus = FloatTabsCommandClient.shouldWaitForInputFocus
        if needsFloatTabsFocus {
            // The event tap itself must return immediately. Only the remote's
            // device-scoped Option pair is held; audio capture and gesture
            // classification continue independently.
            filter.beginOptionDeferral()
        }
        voicePress.keyDown()

        guard needsFloatTabsFocus else { return }
        let requested = FloatTabsCommandClient.requestInputFocusForVoice { [weak self] ready in
            guard let self else { return }
            print("[FLOATTABS] voice focus result=\(ready ? "ready" : "failed")")
            self.filter.releaseDeferredOption(
                reason: ready ? "focus-ready" : "focus-failed"
            )
        }
        if !requested {
            print("[FLOATTABS] voice focus request not accepted; fail-open")
            filter.releaseDeferredOption(reason: "request-rejected")
        } else {
            print("[FLOATTABS] voice focus request sent")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppStorage.prepare()

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
        updateStatus()

        // HID connection (status icon).
        watcher.onConnect = { [weak self] _ in
            // Keep Doubao's reliable physical Option path. Focus warming is
            // handled by FloatTabs presentation, not by delaying this key.
            RemoteVoiceKeyMapping.setEnabled(true)
            self?.hidConnected = true
            self?.updateStatus()
        }
        watcher.onDisconnect = { [weak self] _ in
            RemoteVoiceKeyMapping.setEnabled(false)
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
            if !connected { self?.remoteStreaming = false }
            self?.updateStatus()
        }
        ble.onStreamingChanged = { [weak self] streaming, _ in
            self?.voicePress.setRemoteStreaming(streaming)
            self?.remoteStreaming = streaming
            self?.updateStatus()
        }
        ble.start()

        // HID Monitor：读取遥控器所有按钮的原始 HID 报告
        // HID 设备连接/断开时切换语音键处理路径
        hidMonitor.onDeviceChange = { [weak self] active in
            self?.filter.skipVoiceKey = active
            if !active {
                self?.mappingStore.clearPressedBindings()
            }
            if active {
                print("[HID] monitor active → VoiceKeyFilter 跳过语音键")
            } else {
                print("[HID] monitor inactive → VoiceKeyFilter 处理语音键")
            }
        }
        hidMonitor.onButtonEdge = { [weak self] button, isDown in
            guard let self else { return }
            let binding = isDown
                ? self.mappingStore.beginPress(for: button)
                : self.mappingStore.endPress(for: button)

            // 语音键：仅在绑定为 voiceKeyDefault 时走 VoicePressCoordinator
            if button == .microphone {
                if case .voiceKeyDefault = binding {
                    if isDown {
                        self.beginVoicePress()
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
            } else {
                let sent = KeyInjector.sendUp(binding)
                print("[KEY] \(button.displayName) up → \(binding.displayName); sent=\(sent)")
            }
        }
        hidMonitor.shouldRepeatButton = { [weak self] button in
            guard let self else { return RemoteButton.repeatable.contains(button) }
            let binding = self.mappingStore.activePressBinding(for: button)
            switch binding {
            case let .shortcut(_, trigger):
                return trigger == .repeatWhileHeld
            case let .preset(action):
                return action.repeatsWhenHeld
            case .voiceKeyDefault:
                return false
            }
        }
        hidMonitor.onButtonRepeat = { [weak self] button in
            guard let self else { return }
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

    func menuWillOpen(_ menu: NSMenu) {
        updateStatus()
    }

    private func updateStatus() {
        let inputMonitoringGranted = HIDMonitor.isInputMonitoringGranted
        let accessibilityGranted = KeyInjector.isAccessibilityTrusted

        if remoteStreaming {
            setStatusSummary("状态 · 遥控器录音中", color: .systemGreen)
            startRecordingStatusPulse()
        } else if !inputMonitoringGranted || !accessibilityGranted {
            stopRecordingStatusPulse()
            let missing = !inputMonitoringGranted && !accessibilityGranted
                ? "输入监控 + 辅助功能"
                : !inputMonitoringGranted ? "输入监控" : "辅助功能"
            setStatusSummary("状态 · 需要授权 \(missing)", color: .systemOrange)
            setStatusIcon(systemName: "exclamationmark.triangle", color: .systemOrange)
        } else if hidConnected && bleConnected {
            stopRecordingStatusPulse()
            setStatusSummary("状态 · 已就绪", color: .systemGreen)
            setStatusIcon(systemName: "circle.dotted.and.circle", color: .white)
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
        if remoteStreaming {
            audioTitle = "语音链路 · 遥控器录音中"
            audioColor = .systemGreen
        } else if bleConnected {
            audioTitle = "语音链路 · BLE 已连接"
            audioColor = .systemGreen
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
        watcher.stop()
        voicePress.stop()
        filter.stop()
        hidMonitor.stop()
        mappingStore.clearPressedBindings()
        KeyInjector.releaseAll()
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
