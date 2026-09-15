import AppKit
import Foundation

/// FloatTabs 的本地语义命令。它和 FloatTabs 端的枚举保持同名与同值，
/// 但两个工程不共享源码，避免 RemoteOrbit 必须依赖 FloatTabs 的构建产物。
enum FloatTabsDirectCommand: String, Equatable {
    case show = "show"
    case toggleVisibility = "toggleVisibility"
    case selectSlot = "selectSlot"
    case nextSlot = "nextSlot"
    case previousSlot = "previousSlot"
    case addWebApp = "addWebApp"
    case zoomIn = "zoomIn"
    case zoomOut = "zoomOut"
    case resetZoom = "resetZoom"
    case addressBar = "addressBar"
    case returnHome = "returnHome"
    case togglePrimaryFocus = "togglePrimaryFocus"
    case scrollUp = "scrollUp"
    case scrollDown = "scrollDown"
    case reload = "reload"
    case cancelScroll = "cancelScroll"
    case focusInputForVoice = "focusInputForVoice"
    case settings = "settings"
    case togglePin = "togglePin"
    case setResidency = "setResidency"

    static let notificationName = Notification.Name(
        "com.lost0rz.FloatTabs.external-command.v1"
    )
    static let focusReadyNotificationName = Notification.Name(
        "com.lost0rz.FloatTabs.focus-ready.v1"
    )
}

enum FloatTabsCommandClient {
    static let bundleIdentifier = "com.lost0rz.FloatTabs"
    static let protocolVersion = 3
    private static let stateLock = NSLock()
    private static var lastShowRequestAt = Date.distantPast
    private static var focusReadyObserver: NSObjectProtocol?
    private static var pendingFocusRequests: [String: (Bool, String) -> Void] = [:]
    private static let presentationVoiceGrace: TimeInterval = 1.25
    // A focus repair normally completes in one or two WebKit turns. Do not
    // sacrifice the start of speech if the page has no compatible composer.
    private static let focusRequestTimeout: TimeInterval = 0.30

    /// 向正在运行的 FloatTabs 发送命令。命令本身不携带快捷键，因此 FloatTabs
    /// 用户修改自己的快捷键后，RemoteOrbit 预设仍然有效。
    @discardableResult
    static func send(
        _ command: FloatTabsDirectCommand,
        scrollLines: Int? = nil,
        slotIndex: Int? = nil,
        residencyPolicy: String? = nil
    ) -> Bool {
        guard isRunning else { return false }
        post(
            command,
            scrollLines: scrollLines,
            slotIndex: slotIndex,
            residencyPolicy: residencyPolicy
        )
        return true
    }

    /// 全局“打开 / 显示 / 隐藏 FloatTabs”动作：只有 FloatTabs 确实是
    /// macOS 当前前台应用时才隐藏；其他应用或跨屏切换场景一律走 show，
    /// 让 FloatTabs 重新根据当前调用位置定位。
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
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier
        if isRunning,
           shouldToggleVisibility(
               frontmostBundleIdentifier: frontmostBundleIdentifier
           ) {
            return send(.toggleVisibility)
        }
        return show()
    }

    /// Accessibility focus can remain attached to a stale WebKit element for
    /// one or more run-loop turns after a Space/display change. It is suitable
    /// for routing app commands, but not for deciding whether a summon should
    /// hide FloatTabs. Hiding is allowed only when WindowServer reports the
    /// FloatTabs application itself as frontmost.
    static func shouldToggleVisibility(frontmostBundleIdentifier: String?) -> Bool {
        frontmostBundleIdentifier == bundleIdentifier
    }

    /// Whether the next voice gesture should use the FloatTabs focus handoff.
    /// This is kept separate from the request itself so the caller can arm its
    /// non-blocking voice session before posting the asynchronous command.
    static func shouldPrepareInputFocus(for targetBundleIdentifier: String?) -> Bool {
        guard isRunning else { return false }
        let ownsFocus = targetBundleIdentifier == bundleIdentifier
        return ownsFocus || hasRecentShowRequest
    }

    /// Ask FloatTabs to repair its native/WebKit input target. The request is
    /// deliberately asynchronous: RemoteOrbit never blocks the HID/event-tap
    /// thread waiting for another application. The voice session owns its
    /// synthetic Option lifetime independently of this request.
    @discardableResult
    static func requestInputFocusForVoice(
        gestureID: UUID,
        completion: @escaping (Bool, String) -> Void
    ) -> Bool {
        guard isRunning else {
            return false
        }
        installFocusReadyObserver()
        let requestID = gestureID.uuidString
        stateLock.lock()
        pendingFocusRequests[requestID] = completion
        stateLock.unlock()

        post(.focusInputForVoice, requestID: requestID)
        DispatchQueue.main.asyncAfter(deadline: .now() + focusRequestTimeout) {
            completeFocusRequest(
                requestID,
                ready: false,
                reason: "response-timeout"
            )
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
            let responseVersion = (notification.userInfo?["protocolVersion"] as? NSNumber)?.intValue
                ?? 1
            let reason = notification.userInfo?["reason"] as? String
                ?? (ready ? "ready" : "unknown")
            guard responseVersion == protocolVersion else {
                completeFocusRequest(
                    requestID,
                    ready: false,
                    reason: "protocol-mismatch-\(responseVersion)"
                )
                return
            }
            completeFocusRequest(requestID, ready: ready, reason: reason)
        }
    }

    private static func completeFocusRequest(
        _ requestID: String,
        ready: Bool,
        reason: String
    ) {
        stateLock.lock()
        let completion = pendingFocusRequests.removeValue(forKey: requestID)
        stateLock.unlock()
        completion?(ready, reason)
    }

    private static func post(
        _ command: FloatTabsDirectCommand,
        scrollLines: Int? = nil,
        requestID: String? = nil,
        slotIndex: Int? = nil,
        residencyPolicy: String? = nil
    ) {
        let notificationName = CFNotificationName(
            rawValue: FloatTabsDirectCommand.notificationName.rawValue as CFString
        )
        var values: [String: Any] = [
            "command": command.rawValue,
            "protocolVersion": NSNumber(value: protocolVersion),
        ]
        if let scrollLines {
            values["scrollLines"] = NSNumber(value: scrollLines)
        }
        if let requestID {
            values["requestID"] = requestID
        }
        if let slotIndex {
            values["slotIndex"] = NSNumber(value: slotIndex)
        }
        if let residencyPolicy {
            values["residencyPolicy"] = residencyPolicy
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
