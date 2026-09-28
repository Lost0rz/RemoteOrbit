// SettingsWindow.swift — RemoteOrbit Control Center window
//
// 从菜单栏打开一个 NSWindow，内嵌 SwiftUI SettingsView。
// 保持窗口单例，避免重复创建。

import AppKit
import SwiftUI

final class SettingsWindow {
    /// 单例窗口实例。
    private static var window: NSWindow?

    /// 打开设置窗口（如果已打开则前置）。
    static func open(
        store: MappingStore,
        onRecordingChanged: @escaping (Bool) -> Void = { _ in },
        initialVoiceTriggerKey: VoiceTriggerKey,
        onVoiceTriggerChanged: @escaping VoiceTriggerChangeHandler
    ) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            store: store,
            initialVoiceTriggerKey: initialVoiceTriggerKey,
            onRecordingChanged: onRecordingChanged,
            onVoiceTriggerChanged: onVoiceTriggerChanged
        )
        let hostingController = NSHostingController(rootView: settingsView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "\(ProductIdentity.name) · Control Center"
        win.minSize = NSSize(width: 1_020, height: 660)
        win.contentViewController = hostingController
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)

        window = win
    }

    /// 关闭窗口。
    static func close() {
        window?.close()
        window = nil
    }
}
