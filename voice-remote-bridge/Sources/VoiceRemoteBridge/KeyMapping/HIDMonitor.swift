// HIDMonitor.swift — IOHIDManager 读取遥控器原始 HID 报告
//
// HID remote monitor, kept focused on the supported voice remote devices.
// 识别所有 13 个按钮的按下/松开，通过 onButtonEdge 通知上层。
// 需要输入监控权限（Input Monitoring）。

import IOKit.hid
import IOKit.hidsystem
import Foundation
import Dispatch

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

    /// 按钮边沿回调：(button, isDown)。
    var onButtonEdge: ((RemoteButton, Bool) -> Void)?

    /// 可重复按钮的后续重复回调。与真实按下边沿分开，便于上层根据映射
    /// 决定是保留一次点击，还是在按住时持续触发。
    var onButtonRepeat: ((RemoteButton) -> Void)?

    /// 判断某个按钮当前是否需要启动长按重复计时器。
    /// 未设置时沿用遥控器原本的方向/音量/返回键重复规则。
    var shouldRepeatButton: ((RemoteButton) -> Bool)?

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
    private var repeatTimers: [UInt16: DispatchSourceTimer] = [:]
    private var permissionMonitor: DispatchSourceTimer?
    private(set) var status = "按键映射未启用"
    private(set) var isRunning = false

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

        let inputGranted = Self.isInputMonitoringGranted
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
        startPermissionMonitor()
        updateStatus("等待遥控器连接")
        print("[HID] started; waiting for RC003")
    }

    func stop() {
        permissionMonitor?.cancel()
        permissionMonitor = nil
        repeatTimers.values.forEach { $0.cancel() }
        repeatTimers.removeAll()
        activeUsages.removeAll()
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
    }

    // MARK: - 设备匹配/断开

    fileprivate func deviceDidMatch(result: IOReturn, device: IOHIDDevice) {
        guard manager != nil, activeDevice == nil else { return }

        var openSucceeded = false
        var seized = false

        if result == kIOReturnSuccess {
            // 优先尝试独占模式（seize）：阻止 macOS 接收遥控器事件
            let seizeResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if seizeResult == kIOReturnSuccess {
                openSucceeded = true
                seized = true
            } else {
                // 降级为 monitor 模式
                let monitorResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                if monitorResult == kIOReturnSuccess {
                    openSucceeded = true
                } else {
                    print("[HID] device open failed: seize=\(seizeResult) monitor=\(monitorResult)")
                }
            }
        }

        guard openSucceeded else {
            updateStatus("无法读取遥控器（错误 \(result)）")
            return
        }

        activeDevice = device
        activeDeviceIsSeized = seized
        if seized {
            updateStatus("遥控器已连接（独占模式）")
            print("[HID] connected: seized")
        } else {
            updateStatus("遥控器已连接（兼容模式）")
            print("[HID] connected: monitored")
        }
        onDeviceChange?(true)
    }

    fileprivate func deviceDidRemove(device: IOHIDDevice) {
        guard let activeDevice, CFEqual(activeDevice, device) else { return }
        IOHIDDeviceClose(activeDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        self.activeDevice = nil
        activeDeviceIsSeized = false
        activeUsages.removeAll()
        repeatTimers.values.forEach { $0.cancel() }
        repeatTimers.removeAll()
        updateStatus("遥控器已断开")
        print("[HID] disconnected")
        onDeviceChange?(false)
    }

    // MARK: - HID 报告解析

    fileprivate func handleReport(reportID: UInt32, data: Data) {
        guard manager != nil else { return }
        guard let usages = Self.parseUsages(reportID: reportID, data: data) else { return }

        let pressed = usages.subtracting(activeUsages)
        let released = activeUsages.subtracting(usages)
        activeUsages = usages

        for usage in pressed.sorted() {
            guard let button = RemoteButton.usageMap[usage] else { continue }
            let isDown = true
            if !activeDeviceIsSeized {
                eventSuppressor.arm(button: button, edge: .down)
            }
            onButtonEdge?(button, isDown)
            startRepeatIfNeeded(usage: usage, button: button)
            print("[HID] button down: \(button.displayName)")
        }

        for usage in released {
            guard let button = RemoteButton.usageMap[usage] else { continue }
            let isDown = false
            if !activeDeviceIsSeized {
                eventSuppressor.arm(button: button, edge: .up)
            }
            onButtonEdge?(button, isDown)
            repeatTimers.removeValue(forKey: usage)?.cancel()
            print("[HID] button up: \(button.displayName)")
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

    // MARK: - 按键重复

    private func startRepeatIfNeeded(usage: UInt16, button: RemoteButton) {
        // Clear any stale timer before evaluating the new mapping. This also
        // covers a missed release followed by a fresh down edge whose current
        // app template has changed from repeatable to single-shot.
        repeatTimers.removeValue(forKey: usage)?.cancel()
        let shouldRepeat = shouldRepeatButton?(button) ?? RemoteButton.repeatable.contains(button)
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

    // MARK: - 权限监控

    private func startPermissionMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, self.manager != nil else { return }
            if !Self.isInputMonitoringGranted || !KeyInjector.isAccessibilityTrusted {
                self.stop()
                self.updateStatus("系统权限已失效；已停止监控")
                print("[HID] permissions revoked; stopped")
            }
        }
        permissionMonitor = timer
        timer.resume()
    }

    private func updateStatus(_ value: String) {
        status = value
        onStatusChange?(value)
    }
}
