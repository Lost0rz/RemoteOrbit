// HIDMonitor.swift — IOHIDManager 读取遥控器原始 HID 报告
//
// HID remote monitor, kept focused on the supported voice remote devices.
// 识别所有 13 个按钮的按下/松开，通过 onButtonEdge 通知上层。
// 需要输入监控权限（Input Monitoring）。

import IOKit.hid
import IOKit.hidsystem
import Foundation
import Dispatch

/// All input policy decisions for one physical button-down edge.
/// Keeping the routing-dependent decisions together prevents the target
/// application from being resolved separately for gesture detection and
/// action dispatch.
struct HIDButtonDownPolicy {
    let shouldDebounce: Bool
    let shouldRepeat: Bool

    /// Resolve the existing single-edge policy. Legacy microphone and generic
    /// button rules stay unchanged.
    static func resolve(
        button: RemoteButton,
        shouldRepeat: Bool,
        usesAdvancedGestures: Bool,
        hasLivePhysicalCandidate: Bool = false
    ) -> HIDButtonDownPolicy {
        let advanced = button != .microphone && usesAdvancedGestures
        return HIDButtonDownPolicy(
            shouldDebounce: !shouldRepeat
                && !advanced
                && !(button == .microphone && hasLivePhysicalCandidate),
            shouldRepeat: shouldRepeat
        )
    }
}

// MARK: - C 回调函数（IOHIDManager 需要顶层函数指针）

private func hidDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.deviceDidMatch(result: result, device: device)
}

private func hidDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.deviceDidRemove(device: device)
}

private func hidInputReport(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context, result == kIOReturnSuccess, reportLength > 0 else { return }
    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
    let data = Data(bytes: report, count: reportLength)
    // IOHIDManager 被安排在主 RunLoop 上，优先同步处理报告。这样
    // EventSuppressor 能在系统把同一按键转换成原生 CGEvent 之前 arm，
    // 避免兼容（非 seize）模式下原生 Home/方向键漏出并发出提示音。
    if Thread.isMainThread {
        monitor.handleReport(reportID: reportID, data: data)
    } else {
        DispatchQueue.main.async {
            monitor.handleReport(reportID: reportID, data: data)
        }
    }
}

// MARK: - HIDMonitor

final class HIDMonitor {
    /// 遥控器厂商 ID（小米）。
    static let vendorID  = 0x2717
    /// 遥控器产品 ID（RC003）。
    static let productID = 0x32B8

    /// 按钮边沿回调：(button, isDown)。保留给旧调用方。
    var onButtonEdge: ((RemoteButton, Bool) -> Void)?

    /// 带单调时钟时间戳的边沿回调。高级手势使用这个入口，避免用 UI
    /// 回调到达时间估算长按时长；若设置了该回调，则不再调用旧入口。
    var onButtonEdgeAt: ((RemoteButton, Bool, TimeInterval) -> Void)?

    /// 被输入层防抖丢弃的边沿，仅用于诊断。
    var onButtonEdgeSuppressed: ((RemoteButton, Bool) -> Void)?

    /// 可重复按钮的后续重复回调。与真实按下边沿分开，便于上层根据映射
    /// 决定是保留一次点击，还是在按住时持续触发。
    var onButtonRepeat: ((RemoteButton) -> Void)?

    /// 判断某个按钮当前是否需要启动长按重复计时器。
    /// 未设置时沿用遥控器原本的方向/音量/返回键重复规则。
    var shouldRepeatButton: ((RemoteButton) -> Bool)?

    /// Advanced gesture buttons must receive every accepted down/up edge so
    /// the recognizer can distinguish a double tap from a bounce. Their
    /// repeat timer is owned by ButtonGestureRecognizer instead.
    var shouldUseAdvancedGestures: ((RemoteButton) -> Bool)?

    /// Resolve and snapshot the policy for one physical button-down edge.
    /// This callback runs before debouncing and before the edge is delivered.
    var onButtonDownPolicy: ((RemoteButton) -> HIDButtonDownPolicy)?

    /// 状态变化回调。
    var onStatusChange: ((String) -> Void)?

    /// 设备连接/断开回调：(active)。
    /// active = true 表示已连接到遥控器设备。
    var onDeviceChange: ((Bool) -> Void)?

    /// EventSuppressor：非独占模式下压制 macOS 原生事件。
    let eventSuppressor = EventSuppressor()

    private var manager: IOHIDManager?
    private var activeDevice: IOHIDDevice?
    private var activeDeviceIsSeized = false
    private var activeUsages = Set<UInt16>()
    /// Usages that were physically down when HID disappeared. Keep them
    /// across a reconnect so the first report after reconnect can distinguish
    /// “still held” from “released while the link was away”.
    private var pendingReconnectUsages = Set<UInt16>()
    private var repeatTimers: [UInt16: DispatchSourceTimer] = [:]
    private var debouncedUsages = Set<UInt16>()
    private var edgeDebouncer = ButtonEdgeDebouncer()
    private var hidReportSequence: UInt64 = 0
    private let diagnosticLogger: VoiceDiagnosticLogger?
    private(set) var status = "按键映射未启用"
    private(set) var isRunning = false

    init(diagnosticLogger: VoiceDiagnosticLogger? = .shared) {
        self.diagnosticLogger = diagnosticLogger
    }

    // MARK: - 权限

    static var inputMonitoringAccess: IOHIDAccessType {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    }

    static var isInputMonitoringGranted: Bool {
        inputMonitoringAccess == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - 生命周期

    func start() {
        stop()

        // RemoteOrbit intentionally has its own bundle identifier, so
        // macOS does not carry over a previous bundle's TCC decision. Ask once
        // here so a fresh installation can show the system permission flow;
        // the result still needs to be enabled by the user in Input
        // Monitoring when macOS presents the settings-only prompt.
        var inputGranted = Self.isInputMonitoringGranted
        if !inputGranted {
            let requested = Self.requestInputMonitoringAccess()
            print("[HID] input monitoring access request sent=\(requested)")
            inputGranted = Self.isInputMonitoringGranted
        }
        let accessibilityGranted = KeyInjector.isAccessibilityTrusted
        print("[HID] permissions: input=\(inputGranted) accessibility=\(accessibilityGranted)")

        guard inputGranted && accessibilityGranted else {
            if !inputGranted {
                updateStatus("需要输入监控权限")
            } else {
                updateStatus("需要辅助功能权限")
            }
            return
        }

        let suppressionReady = eventSuppressor.start()
        print("[HID] event suppressor ready=\(suppressionReady)")
        guard suppressionReady else {
            updateStatus("无法拦截遥控器原生按键")
            print("[HID] stopped: event suppressor unavailable; native power events are not safe to pass through")
            return
        }

        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
        ] as CFDictionary
        IOHIDManagerSetDeviceMatching(m, matching)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, hidDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(m, hidDeviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(m, hidInputReport, context)
        IOHIDManagerScheduleWithRunLoop(
            m,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let result = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                m,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            eventSuppressor.stop()
            updateStatus("无法打开 HID Manager（错误 \(result)）")
            return
        }
        self.manager = m
        self.isRunning = true
        DiagnosticRuntimeHealthRegistry.shared.setBool("hid_manager_running", true)
        updateStatus("等待遥控器连接")
        print("[HID] started; waiting for RC003")
    }

    func stop() {
        repeatTimers.values.forEach { $0.cancel() }
        repeatTimers.removeAll()
        activeUsages.removeAll()
        pendingReconnectUsages.removeAll()
        debouncedUsages.removeAll()
        edgeDebouncer.reset()
        eventSuppressor.stop()
        if let activeDevice {
            IOHIDDeviceClose(activeDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            self.activeDevice = nil
            activeDeviceIsSeized = false
        }
        if let m = manager {
            IOHIDManagerUnscheduleFromRunLoop(
                m,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
        isRunning = false
        DiagnosticRuntimeHealthRegistry.shared.setBool("hid_manager_running", false)
        DiagnosticRuntimeHealthRegistry.shared.setBool("hid_device_active", false)
        DiagnosticRuntimeHealthRegistry.shared.setBool("physical_voice_key_down", false)
    }

    /// Whether a physical button is still considered held while HID is
    /// reconnecting. The app uses this to keep hold-only UI tied to the
    /// physical key state rather than to the transport callback alone.
    func isButtonDown(_ button: RemoteButton) -> Bool {
        activeUsages.contains(button.hidUsage)
            || pendingReconnectUsages.contains(button.hidUsage)
    }

    /// Clear stuck pressed state when macOS Suppresses/drops a physical UP
    /// report mid-hold (for example when Secure Event Input turns on).
    @discardableResult
    func clearStuckButtonHold(_ button: RemoteButton) -> Bool {
        let usage = button.hidUsage
        let wasDown = activeUsages.remove(usage) != nil
            || pendingReconnectUsages.remove(usage) != nil
        debouncedUsages.remove(usage)
        repeatTimers.removeValue(forKey: usage)?.cancel()
        if wasDown {
            if !activeDeviceIsSeized {
                eventSuppressor.updateHeld(button: button, isDown: false)
            }
            if button == .microphone {
                DiagnosticRuntimeHealthRegistry.shared.setBool("physical_voice_key_down", false)
            }
        }
        return wasDown
    }

    // MARK: - 设备匹配/断开

    fileprivate func deviceDidMatch(result: IOReturn, device: IOHIDDevice) {
        guard manager != nil, activeDevice == nil else { return }

        guard result == kIOReturnSuccess else {
            updateStatus("无法读取遥控器（错误 \(result)）")
            return
        }

        // Keep the device in monitored mode so macOS can continue delivering
        // hidutil-translated events while EventSuppressor handles leakage.
        let monitorResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard monitorResult == kIOReturnSuccess else {
            print("[HID] device open failed: monitor=\(monitorResult)")
            return
        }

        activeDevice = device
        activeDeviceIsSeized = false
        DiagnosticRuntimeHealthRegistry.shared.setBool("hid_device_active", true)
        eventSuppressor.setRemotePowerSuppressionEnabled(true)
        updateStatus("遥控器已连接（兼容模式）")
        print("[HID] connected: monitored")
        onDeviceChange?(true)
    }

    fileprivate func deviceDidRemove(device: IOHIDDevice) {
        guard let activeDevice, CFEqual(activeDevice, device) else { return }
        IOHIDDeviceClose(activeDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        self.activeDevice = nil
        activeDeviceIsSeized = false
        DiagnosticRuntimeHealthRegistry.shared.setBool("hid_device_active", false)
        DiagnosticRuntimeHealthRegistry.shared.setBool("physical_voice_key_down", false)
        eventSuppressor.setRemotePowerSuppressionEnabled(false)
        pendingReconnectUsages.formUnion(activeUsages)
        activeUsages.removeAll()
        repeatTimers.values.forEach { $0.cancel() }
        repeatTimers.removeAll()
        debouncedUsages.removeAll()
        edgeDebouncer.reset()
        updateStatus("遥控器已断开")
        if !pendingReconnectUsages.isEmpty {
            let names = pendingReconnectUsages.compactMap { RemoteButton.usageMap[$0]?.displayName }
            print("[HID] disconnected; preserving held buttons: \(names.joined(separator: ", "))")
        } else {
            print("[HID] disconnected")
        }
        onDeviceChange?(false)
    }

    // MARK: - HID 报告解析

    fileprivate func handleReport(reportID: UInt32, data: Data) {
        guard manager != nil else { return }
        hidReportSequence &+= 1
        let reportSequence = hidReportSequence
        let reportObservedUptime = ProcessInfo.processInfo.systemUptime
        DiagnosticRuntimeHealthRegistry.shared.recordHIDReport(
            at: UInt64(max(0, reportObservedUptime * 1_000))
        )
        guard let usages = Self.parseUsages(reportID: reportID, data: data) else { return }

        let microphoneUsage = RemoteButton.microphone.hidUsage
        let previousMicDown = activeUsages.contains(microphoneUsage)
            || pendingReconnectUsages.contains(microphoneUsage)
        let pendingReconnectContainsMic = pendingReconnectUsages.contains(microphoneUsage)
        let deviceActive = activeDevice != nil

        let pressed = usages.subtracting(activeUsages)
        let released = activeUsages.subtracting(usages)
            .union(pendingReconnectUsages.subtracting(usages))
        pendingReconnectUsages.subtract(usages)
        activeUsages = usages

        // Preserve the production edge/debounce timing anchor exactly where
        // baseline sampled it. Raw-report diagnostics use reportObservedUptime
        // above and must not move the behavioral edge timestamp earlier.
        let now = ProcessInfo.processInfo.systemUptime

        for usage in pressed.sorted() {
            guard let button = RemoteButton.usageMap[usage] else { continue }
            let isDown = true
            if !activeDeviceIsSeized {
                eventSuppressor.updateHeld(button: button, isDown: true)
            }

            // Resolve routing, gesture mode and repeat behavior together. The
            // legacy callbacks remain as a compatibility fallback for callers
            // that construct HIDMonitor directly.
            let policy: HIDButtonDownPolicy
            if let onButtonDownPolicy {
                policy = onButtonDownPolicy(button)
            } else {
                let shouldRepeat = shouldRepeatButton?(button)
                    ?? RemoteButton.repeatable.contains(button)
                let shouldDebounce = !shouldRepeat
                    && !(shouldUseAdvancedGestures?(button) ?? false)
                policy = HIDButtonDownPolicy(
                    shouldDebounce: shouldDebounce,
                    shouldRepeat: shouldRepeat
                )
            }
            let shouldRepeat = policy.shouldRepeat
            let shouldDebounce = policy.shouldDebounce
            if shouldDebounce {
                debouncedUsages.insert(usage)
            }
            guard edgeDebouncer.shouldEmit(
                button: button,
                isDown: isDown,
                at: now,
                debouncing: shouldDebounce
            ) else {
                onButtonEdgeSuppressed?(button, isDown)
                if button == .microphone {
                    diagnosticLogger?.log(
                        category: "hid",
                        event: "HID_MIC_EDGE_SUPPRESSED",
                        fields: [
                            "edge": "down",
                            "event_uptime": now,
                            "raw_report_sequence": reportSequence,
                            "reason": "debounce",
                            "source": "hid_monitor",
                        ]
                    )
                }
                continue
            }

            emitButtonEdge(
                button: button,
                isDown: isDown,
                at: now,
                rawReportSequence: reportSequence
            )
            startRepeatIfNeeded(
                usage: usage,
                button: button,
                shouldRepeat: shouldRepeat
            )
            print("[HID] button down: \(button.displayName)")
        }

        for usage in released {
            guard let button = RemoteButton.usageMap[usage] else { continue }
            let isDown = false
            if !activeDeviceIsSeized {
                eventSuppressor.updateHeld(button: button, isDown: false)
            }

            let shouldDebounce = debouncedUsages.remove(usage) != nil
            guard edgeDebouncer.shouldEmit(
                button: button,
                isDown: isDown,
                at: now,
                debouncing: shouldDebounce
            ) else {
                onButtonEdgeSuppressed?(button, isDown)
                if button == .microphone {
                    diagnosticLogger?.log(
                        category: "hid",
                        event: "HID_MIC_EDGE_SUPPRESSED",
                        fields: [
                            "edge": "up",
                            "event_uptime": now,
                            "raw_report_sequence": reportSequence,
                            "reason": "debounce",
                            "source": "hid_monitor",
                        ]
                    )
                }
                repeatTimers.removeValue(forKey: usage)?.cancel()
                continue
            }

            emitButtonEdge(
                button: button,
                isDown: isDown,
                at: now,
                rawReportSequence: reportSequence
            )
            repeatTimers.removeValue(forKey: usage)?.cancel()
            print("[HID] button up: \(button.displayName)")
        }

        if let diagnosticLogger,
           let fields = Self.microphoneTransitionDiagnosticFields(
               reportID: reportID,
               data: data,
               parsedUsages: usages,
               previousMicDown: previousMicDown,
               pendingReconnectContainsMic: pendingReconnectContainsMic,
               deviceActive: deviceActive,
               sequence: reportSequence,
               uptime: reportObservedUptime,
               voiceAttemptID: VoiceAttemptDiagnostics.shared.currentID?.uuidString
           ) {
            DiagnosticRuntimeHealthRegistry.shared.recordMicrophoneTransition(
                at: UInt64(max(0, reportObservedUptime * 1_000))
            )
            diagnosticLogger.log(
                category: "hid",
                event: "RAW_HID_MIC_STATE",
                fields: fields
            )
        }
    }

    /// 解析 HID 报告中的 usage 集合。
    /// 报告格式（reportID=1）：[usage1_lo, usage1_hi, usage2_lo, usage2_hi, ...]
    /// 每个 usage 是 2 字节小端序，0 表示空槽。
    static func parseUsages(reportID: UInt32, data: Data) -> Set<UInt16>? {
        guard reportID == 1 else { return nil }
        var bytes = Array(data)
        // 某些报告首字节是 reportID，需要移除
        if bytes.count == 7, bytes.first == UInt8(reportID) {
            bytes.removeFirst()
        }
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return nil }

        var result = Set<UInt16>()
        for index in stride(from: 0, to: bytes.count, by: 2) {
            let usage = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
            if usage != 0 { result.insert(usage) }
        }
        return result
    }

    static func microphoneTransitionDiagnosticFields(
        reportID: UInt32,
        data: Data,
        parsedUsages: Set<UInt16>,
        activeUsages: Set<UInt16>,
        pendingReconnectUsages: Set<UInt16>,
        deviceActive: Bool,
        sequence: UInt64,
        uptime: TimeInterval,
        voiceAttemptID: String? = nil
    ) -> [String: Any]? {
        let microphoneUsage = RemoteButton.microphone.hidUsage
        return microphoneTransitionDiagnosticFields(
            reportID: reportID,
            data: data,
            parsedUsages: parsedUsages,
            previousMicDown: activeUsages.contains(microphoneUsage)
                || pendingReconnectUsages.contains(microphoneUsage),
            pendingReconnectContainsMic: pendingReconnectUsages.contains(microphoneUsage),
            deviceActive: deviceActive,
            sequence: sequence,
            uptime: uptime,
            voiceAttemptID: voiceAttemptID
        )
    }

    static func microphoneTransitionDiagnosticFields(
        reportID: UInt32,
        data: Data,
        parsedUsages: Set<UInt16>,
        previousMicDown: Bool,
        pendingReconnectContainsMic: Bool,
        deviceActive: Bool,
        sequence: UInt64,
        uptime: TimeInterval,
        voiceAttemptID: String? = nil
    ) -> [String: Any]? {
        let microphoneUsage = RemoteButton.microphone.hidUsage
        let currentMicDown = parsedUsages.contains(microphoneUsage)
        guard previousMicDown != currentMicDown else { return nil }

        return [
            "report_id": Int(reportID),
            "report_length": data.count,
            "raw_hex": data.map { String(format: "%02x", $0) }.joined(),
            "parsed_usages": parsedUsages.sorted().map(Int.init),
            "previous_mic_down": previousMicDown,
            "current_mic_down": currentMicDown,
            "computed_edge": currentMicDown ? "down" : "up",
            "event_uptime": uptime,
            "pending_reconnect_contains_mic": pendingReconnectContainsMic,
            "device_active": deviceActive,
            "hid_report_sequence": sequence,
            "voice_attempt_id": voiceAttemptID ?? "unavailable",
            "source": "iohid_report",
        ]
    }

    // MARK: - 按键重复

    private func emitButtonEdge(
        button: RemoteButton,
        isDown: Bool,
        at timestamp: TimeInterval,
        rawReportSequence: UInt64
    ) {
        let attemptID: UUID?
        if button == .microphone, isDown {
            attemptID = VoiceAttemptDiagnostics.shared.beginPhysicalAttempt(
                state: ["physical_source": .string("hid_monitor")]
            )
            DiagnosticRuntimeHealthRegistry.shared.setBool("physical_voice_key_down", true)
        } else if button == .microphone {
            attemptID = VoiceAttemptDiagnostics.shared.currentID
            DiagnosticRuntimeHealthRegistry.shared.setBool("physical_voice_key_down", false)
        } else {
            attemptID = nil
        }
        if let callback = onButtonEdgeAt {
            callback(button, isDown, timestamp)
        } else {
            onButtonEdge?(button, isDown)
        }
        if button == .microphone {
            DiagnosticRuntimeHealthRegistry.shared.recordMicrophoneTransition(
                at: UInt64(max(0, timestamp * 1_000))
            )
            diagnosticLogger?.log(
                category: "hid",
                event: "HID_MIC_EDGE_EMITTED",
                fields: Self.microphoneEdgeDiagnosticFields(
                    isDown: isDown,
                    timestamp: timestamp,
                    rawReportSequence: rawReportSequence,
                    attemptID: attemptID
                )
            )
        }
    }

    static func microphoneEdgeDiagnosticFields(
        isDown: Bool,
        timestamp: TimeInterval,
        rawReportSequence: UInt64,
        attemptID: UUID?
    ) -> [String: Any] {
        [
            "edge": isDown ? "down" : "up",
            "event_uptime": timestamp,
            "raw_report_sequence": rawReportSequence,
            "source": "hid_monitor",
            "voice_attempt_id": attemptID?.uuidString ?? "unavailable",
        ]
    }

    private func startRepeatIfNeeded(
        usage: UInt16,
        button: RemoteButton,
        shouldRepeat: Bool? = nil
    ) {
        // Clear any stale timer before evaluating the new mapping. This also
        // covers a missed release followed by a fresh down edge whose current
        // app template has changed from repeatable to single-shot.
        repeatTimers.removeValue(forKey: usage)?.cancel()
        let shouldRepeat = shouldRepeat
            ?? shouldRepeatButton?(button)
            ?? RemoteButton.repeatable.contains(button)
        guard shouldRepeat else { return }

        // A few remotes can emit a second down edge while a held key is being
        // re-announced. Never leave the previous timer alive, otherwise one
        // physical hold would create two repeat streams and duplicate toggles.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval: DispatchTimeInterval = button == .back
            ? .milliseconds(50)
            : .milliseconds(100)
        timer.schedule(deadline: .now() + .milliseconds(350), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, self.activeUsages.contains(usage) else { return }
            if !self.activeDeviceIsSeized {
                self.eventSuppressor.arm(button: button, edge: .down)
            }
            self.onButtonRepeat?(button)
        }
        repeatTimers[usage] = timer
        timer.resume()
    }

    private func updateStatus(_ value: String) {
        status = value
        onStatusChange?(value)
    }
}
