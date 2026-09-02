// EventSuppressor.swift — CGEvent tap 压制 macOS 对遥控器按钮的原生事件
//
// Keyboard-level event suppression used by the bridge.
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
    private static let powerSystemKeyType: Int32 = 6

    private struct PendingEvent {
        let event: RemoteNativeEvent
        let edge: RemoteEventEdge
        let expiresAt: TimeInterval
    }

    private static let pendingEventLifetime: TimeInterval = 0.18

    private let lock = NSLock()
    private var pendingEvents: [PendingEvent] = []
    /// Native events belonging to a button that is currently down. In
    /// compatibility/monitor mode macOS may generate autorepeat keyDown
    /// events long after the first edge. A one-shot pending event cannot
    /// suppress that stream, so the HID-held state remains authoritative
    /// until the matching HID release arrives.
    private var heldNativeEvents: Set<RemoteNativeEvent> = []
    /// Short release fence for a keyboard autorepeat already in flight when
    /// the HID release arrives.
    private var recentlyReleasedNativeEvents: [RemoteNativeEvent: TimeInterval] = [:]
    /// Tracks native keyDown events that this tap actually swallowed. A
    /// matching keyUp may be swallowed only for those events; otherwise an
    /// early native keyDown can leak through while its keyUp is accidentally
    /// filtered, leaving macOS in a stuck autorepeat state.
    private var suppressedNativeKeyDowns: Set<RemoteNativeEvent> = []
    private var remotePowerSuppressionEnabled = false
    private var remoteMediaSuppressionEnabled = false
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
            CGEvent.tapEnable(tap: eventTap, enable: false)
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
        heldNativeEvents.removeAll()
        recentlyReleasedNativeEvents.removeAll()
        suppressedNativeKeyDowns.removeAll()
        remotePowerSuppressionEnabled = false
        remoteMediaSuppressionEnabled = false
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

    /// In monitor mode the remote's power button may still produce a native
    /// macOS power event. That event has no source-device identity at the
    /// CGEvent layer, so while the supported remote is connected we protect
    /// system power events and let RemoteOrbit deliver the mapped action.
    func setRemotePowerSuppressionEnabled(_ enabled: Bool) {
        lock.lock()
        remotePowerSuppressionEnabled = enabled
        lock.unlock()
    }

    /// In monitor mode the supported remote's volume HID reports can also be
    /// translated by macOS into native system-defined media events. Those
    /// events have no source-device identity, so allowing them through would
    /// cause a duplicate volume change or a volume HUD while a semantic
    /// mapping (such as FloatTabs tab switching) is being delivered. The
    /// matching RemoteOrbit action is posted separately and synthetic events
    /// are exempted by the marker check in `handle`.
    func setRemoteMediaSuppressionEnabled(_ enabled: Bool) {
        lock.lock()
        remoteMediaSuppressionEnabled = enabled
        lock.unlock()
    }

    static func shouldSuppressRemotePowerEvent(
        _ event: RemoteNativeEvent,
        remotePowerSuppressionEnabled: Bool
    ) -> Bool {
        remotePowerSuppressionEnabled
            && event == .systemKey(type: powerSystemKeyType)
    }

    /// 更新 HID 的权威按下状态，并预置当前边沿。
    /// held 状态会持续压制按住期间 macOS 产生的重复 keyDown；pending
    /// 边沿则覆盖原生事件早于 HID 回调到达的竞态。
    func updateHeld(button: RemoteButton, isDown: Bool) {
        guard let nativeEvent = button.nativeEvent else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        removeExpiredEvents(now: now)
        if isDown {
            heldNativeEvents.insert(nativeEvent)
            recentlyReleasedNativeEvents.removeValue(forKey: nativeEvent)
            // Recover if the previous native keyUp was never observed.
            suppressedNativeKeyDowns.remove(nativeEvent)
            appendPendingEventLocked(
                event: nativeEvent,
                edge: .down,
                expiresAt: now + Self.pendingEventLifetime
            )
        } else {
            heldNativeEvents.remove(nativeEvent)
            recentlyReleasedNativeEvents[nativeEvent] =
                now + Self.pendingEventLifetime
            appendPendingEventLocked(
                event: nativeEvent,
                edge: .up,
                expiresAt: now + Self.pendingEventLifetime
            )
        }
        lock.unlock()
    }

    /// 预设要压制的原生事件。HIDMonitor 在重复触发时调用。
    /// 已处于 held 状态的按下事件由 heldNativeEvents 持续压制，避免
    /// 每 100ms 额外堆积一个 pending 项。
    func arm(button: RemoteButton, edge: RemoteEventEdge) {
        guard let nativeEvent = button.nativeEvent else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        removeExpiredEvents(now: now)
        if !(edge == .down && heldNativeEvents.contains(nativeEvent)) {
            appendPendingEventLocked(
                event: nativeEvent,
                edge: edge,
                expiresAt: now + Self.pendingEventLifetime
            )
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

        lock.lock()
        let powerSuppressionEnabled = remotePowerSuppressionEnabled
        let mediaSuppressionEnabled = remoteMediaSuppressionEnabled
        lock.unlock()
        if Self.shouldSuppressRemotePowerEvent(
            descriptor.event,
            remotePowerSuppressionEnabled: powerSuppressionEnabled
        ) {
            return true
        }
        if Self.shouldSuppressRemoteMediaEvent(
            descriptor.event,
            remoteMediaSuppressionEnabled: mediaSuppressionEnabled
        ) {
            return true
        }

        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        removeExpiredEvents(now: now)

        // Once the HID edge says the remote button is down, every matching
        // native keyDown is part of that remote gesture. This blocks macOS's
        // own autorepeat in compatibility mode while keeping RemoteOrbit's
        // explicit repeat policy in control.
        if descriptor.edge == .down,
           heldNativeEvents.contains(descriptor.event) {
            if let pendingIndex = pendingEvents.firstIndex(where: {
                $0.event == descriptor.event && $0.edge == .down
            }) {
                pendingEvents.remove(at: pendingIndex)
            }
            suppressedNativeKeyDowns.insert(descriptor.event)
            lock.unlock()
            return true
        }

        // A keyboard repeat can arrive just after the HID release but before
        // the native keyUp. Consume only events marked as autorepeat so an
        // unrelated physical key press is not swallowed by this short fence.
        if descriptor.edge == .down,
           descriptor.isKeyboardAutorepeat,
           recentlyReleasedNativeEvents[descriptor.event] != nil {
            lock.unlock()
            return true
        }

        // Do not consume a native keyUp unless this suppressor consumed the
        // corresponding native keyDown. If keyDown raced ahead of the HID
        // report and was delivered to macOS, its keyUp must also be delivered
        // or macOS will continue generating autorepeat events forever.
        if descriptor.edge == .up {
            guard let matchIndex = pendingEvents.firstIndex(where: {
                $0.event == descriptor.event && $0.edge == .up
            }) else {
                lock.unlock()
                return false
            }
            pendingEvents.remove(at: matchIndex)
            let shouldSuppress = Self.shouldSuppressRemoteKeyUp(
                hasPendingRelease: true,
                nativeKeyDownWasSuppressed: suppressedNativeKeyDowns.remove(descriptor.event) != nil
            )
            lock.unlock()
            return shouldSuppress
        }

        guard let matchIndex = pendingEvents.firstIndex(where: {
            $0.event == descriptor.event && $0.edge == descriptor.edge
        }) else {
            lock.unlock()
            return false
        }
        pendingEvents.remove(at: matchIndex)
        suppressedNativeKeyDowns.insert(descriptor.event)
        lock.unlock()
        return true
    }

    static func shouldSuppressRemoteKeyUp(
        hasPendingRelease: Bool,
        nativeKeyDownWasSuppressed: Bool
    ) -> Bool {
        hasPendingRelease && nativeKeyDownWasSuppressed
    }

    static func shouldSuppressRemoteMediaEvent(
        _ event: RemoteNativeEvent,
        remoteMediaSuppressionEnabled: Bool
    ) -> Bool {
        guard remoteMediaSuppressionEnabled else { return false }
        switch event {
        case .systemKey(type: 0), .systemKey(type: 1):
            return true
        default:
            return false
        }
    }

    private func descriptor(
        type: CGEventType,
        event: CGEvent
    ) -> (
        event: RemoteNativeEvent,
        edge: RemoteEventEdge,
        isKeyboardAutorepeat: Bool
    )? {
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
            return (
                event: .systemKey(type: systemKeyType),
                edge: edge,
                isKeyboardAutorepeat: false
            )
        }

        // 键盘事件
        switch type {
        case .keyDown, .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return (
                event: .keyboard(keyCode: keyCode),
                edge: type == .keyDown ? .down : .up,
                isKeyboardAutorepeat: event.getIntegerValueField(
                    .keyboardEventAutorepeat
                ) != 0
            )
        default:
            return nil
        }
    }

    private func removeExpiredEvents(now: TimeInterval) {
        pendingEvents.removeAll { $0.expiresAt <= now }
        recentlyReleasedNativeEvents = recentlyReleasedNativeEvents.filter {
            $0.value > now
        }
    }

    private func appendPendingEventLocked(
        event: RemoteNativeEvent,
        edge: RemoteEventEdge,
        expiresAt: TimeInterval
    ) {
        pendingEvents.append(PendingEvent(
            event: event,
            edge: edge,
            expiresAt: expiresAt
        ))
        if pendingEvents.count > 32 {
            pendingEvents.removeFirst(pendingEvents.count - 32)
        }
    }
}
