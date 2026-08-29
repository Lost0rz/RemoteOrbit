import AppKit
import Foundation

/// FloatTabs 的本地语义命令。它和 FloatTabs 端的枚举保持同名与同值，
/// 但两个工程不共享源码，避免米遥桥必须依赖 FloatTabs 的构建产物。
enum FloatTabsDirectCommand: String {
    case show = "show"
    case toggleVisibility = "toggleVisibility"
    case nextSlot = "nextSlot"
    case previousSlot = "previousSlot"
    case togglePrimaryFocus = "togglePrimaryFocus"
    case scrollUp = "scrollUp"
    case scrollDown = "scrollDown"
    case focusInputForVoice = "focusInputForVoice"
    case settings = "settings"

    static let notificationName = Notification.Name(
        "com.lost0rz.FloatTabs.external-command.v1"
    )
    static let focusReadyNotificationName = Notification.Name(
        "com.lost0rz.FloatTabs.focus-ready.v1"
    )
}

enum FloatTabsCommandClient {
    static let bundleIdentifier = "com.lost0rz.FloatTabs"
    private static let stateLock = NSLock()
    private static var lastShowRequestAt = Date.distantPast
    private static var focusReadyObserver: NSObjectProtocol?
    private static var pendingFocusRequests: [String: (Bool) -> Void] = [:]
    private static let presentationVoiceGrace: TimeInterval = 1.25
    private static let focusRequestTimeout: TimeInterval = 1.75

    /// 向正在运行的 FloatTabs 发送命令。命令本身不携带快捷键，因此 FloatTabs
    /// 用户修改自己的快捷键后，米遥桥预设仍然有效。
    @discardableResult
    static func send(
        _ command: FloatTabsDirectCommand,
        scrollLines: Int? = nil
    ) -> Bool {
        guard isRunning else { return false }
        post(command, scrollLines: scrollLines)
        return true
    }

    /// 全局“打开 / 显示 / 隐藏 FloatTabs”动作：目标不在前台时显示并激活，
    /// 目标已经在前台时隐藏；未运行时先启动，再补发 show 命令。
    @discardableResult
    static func show() -> Bool {
        markShowRequested()
        if isRunning {
            post(.show)
            return true
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ), NSWorkspace.shared.open(appURL) else {
            return false
        }

        for delay in [0.35, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                post(.show)
            }
        }
        return true
    }

    @discardableResult
    static func toggleOrShow() -> Bool {
        if isRunning,
           MappingStore.preferredApplicationBundleIdentifier() == bundleIdentifier {
            return send(.toggleVisibility)
        }
        return show()
    }

    /// Whether the next voice gesture should use the FloatTabs focus handoff.
    /// This is kept separate from the request itself so the caller can arm its
    /// non-blocking HID event gate before posting the asynchronous command.
    static var shouldWaitForInputFocus: Bool {
        guard isRunning else { return false }
        let ownsFocus = MappingStore.preferredApplicationBundleIdentifier() == bundleIdentifier
        return ownsFocus || hasRecentShowRequest
    }

    /// Ask FloatTabs to repair its native/WebKit input target. The request is
    /// deliberately asynchronous: the bridge never blocks the HID/event-tap
    /// thread waiting for another application. The caller owns the short
    /// fail-open deadline for the mapped Option event.
    @discardableResult
    static func requestInputFocusForVoice(
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        guard isRunning else {
            return false
        }
        guard shouldWaitForInputFocus else {
            return false
        }
        installFocusReadyObserver()
        let requestID = UUID().uuidString
        stateLock.lock()
        pendingFocusRequests[requestID] = completion
        stateLock.unlock()

        post(.focusInputForVoice, requestID: requestID)
        DispatchQueue.main.asyncAfter(deadline: .now() + focusRequestTimeout) {
            completeFocusRequest(requestID, ready: false)
        }
        return true
    }

    private static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
    }

    private static func markShowRequested() {
        stateLock.lock()
        lastShowRequestAt = Date()
        stateLock.unlock()
    }

    private static var hasRecentShowRequest: Bool {
        stateLock.lock()
        let recent = Date().timeIntervalSince(lastShowRequestAt) < presentationVoiceGrace
        stateLock.unlock()
        return recent
    }

    private static func installFocusReadyObserver() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard focusReadyObserver == nil else { return }
        focusReadyObserver = DistributedNotificationCenter.default().addObserver(
            forName: FloatTabsDirectCommand.focusReadyNotificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let requestID = notification.userInfo?["requestID"] as? String else {
                return
            }
            let ready = (notification.userInfo?["ready"] as? NSNumber)?.boolValue ?? false
            completeFocusRequest(requestID, ready: ready)
        }
    }

    private static func completeFocusRequest(_ requestID: String, ready: Bool) {
        stateLock.lock()
        let completion = pendingFocusRequests.removeValue(forKey: requestID)
        stateLock.unlock()
        completion?(ready)
    }

    private static func post(
        _ command: FloatTabsDirectCommand,
        scrollLines: Int? = nil,
        requestID: String? = nil
    ) {
        let notificationName = CFNotificationName(
            rawValue: FloatTabsDirectCommand.notificationName.rawValue as CFString
        )
        var values: [String: Any] = ["command": command.rawValue]
        if let scrollLines {
            values["scrollLines"] = NSNumber(value: scrollLines)
        }
        if let requestID {
            values["requestID"] = requestID
        }
        let userInfo = values as CFDictionary
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            notificationName,
            nil,
            userInfo,
            true
        )
    }
}

enum ApplicationLauncher {
    @discardableResult
    static func activate(bundleIdentifier: String) -> Bool {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            return running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return false }
        return NSWorkspace.shared.open(appURL)
    }

    /// 打开/激活目标程序；目标已经是前台程序时将其隐藏，形成同一个按键
    /// 的开关行为。未运行时只负责启动，不额外发送按键，避免启动阶段漏键。
    @discardableResult
    static func toggle(bundleIdentifier: String) -> Bool {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier {
                return running.hide()
            }
            return running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return false }
        return NSWorkspace.shared.open(appURL)
    }
}
