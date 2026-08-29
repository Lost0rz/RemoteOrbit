// EventSuppressor.swift — CGEvent tap 压制 macOS 对遥控器按钮的原生事件
//
// 参考 open-voice-bridge 的 KeyboardEventSuppressor.swift。
// 当 HIDMonitor 检测到按钮按下时，arm() 预设要压制的原生事件。
// CGEvent tap 收到匹配的 macOS 原生事件时吞掉它，防止双击效应。

import AppKit
import CoreGraphics
import Foundation

private func eventSuppressorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let suppressor = Unmanaged<EventSuppressor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return suppressor.handle(type: type, event: event)
        ? nil
        : Unmanaged.passUnretained(event)
}

final class EventSuppressor {
    private static let systemDefinedEventTypeRawValue: UInt32 = 14

    private struct PendingEvent {
        let event: RemoteNativeEvent
        let edge: RemoteEventEdge
        let expiresAt: TimeInterval
    }

    private let lock = NSLock()
    private var pendingEvents: [PendingEvent] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private(set) var isRunning = false

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << Self.systemDefinedEventTypeRawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            // 在 HID 层尽早吞掉遥控器的原生事件。兼容模式下设备不能
            // seize，继续使用 session 层会有机会先让 Home 等事件漏给系统。
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventSuppressorCallback,
            userInfo: context
        ) else {
            return false
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        lock.lock()
        pendingEvents.removeAll()
        lock.unlock()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    /// 预设要压制的原生事件。HIDMonitor 在检测到按钮边沿时调用。
    func arm(button: RemoteButton, edge: RemoteEventEdge) {
        guard let nativeEvent = button.nativeEvent else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        pendingEvents.removeAll { $0.expiresAt <= now }
        pendingEvents.append(PendingEvent(
            event: nativeEvent,
            edge: edge,
            expiresAt: now + 0.18
        ))
        if pendingEvents.count > 32 {
            pendingEvents.removeFirst(pendingEvents.count - 32)
        }
        lock.unlock()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        // 自动恢复被系统禁用的 tap
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }
        // 放行我们自己合成的事件
        if event.getIntegerValueField(.eventSourceUserData) == KeyInjector.syntheticMarker {
            return false
        }
        guard let descriptor = descriptor(type: type, event: event) else { return false }

        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        pendingEvents.removeAll { $0.expiresAt <= now }
        guard let matchIndex = pendingEvents.firstIndex(where: {
            $0.event == descriptor.event && $0.edge == descriptor.edge
        }) else {
            lock.unlock()
            return false
        }
        pendingEvents.remove(at: matchIndex)
        lock.unlock()
        return true
    }

    private func descriptor(
        type: CGEventType,
        event: CGEvent
    ) -> (event: RemoteNativeEvent, edge: RemoteEventEdge)? {
        // 系统事件（音量、电源等）
        if type.rawValue == Self.systemDefinedEventTypeRawValue {
            guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
            let systemKeyType = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
            let keyState = (nsEvent.data1 & 0x0000_FF00) >> 8
            let edge: RemoteEventEdge
            switch keyState {
            case 0xA: edge = .down
            case 0xB: edge = .up
            default: return nil
            }
            return (.systemKey(type: systemKeyType), edge)
        }

        // 键盘事件
        switch type {
        case .keyDown, .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return (.keyboard(keyCode: keyCode), type == .keyDown ? .down : .up)
        default:
            return nil
        }
    }
}
