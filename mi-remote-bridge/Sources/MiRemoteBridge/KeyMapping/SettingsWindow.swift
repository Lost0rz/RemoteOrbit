// SettingsWindow.swift — NSWindow 包装器
//
// 从菜单栏打开一个 NSWindow，内嵌 SwiftUI SettingsView。
// 保持窗口单例，避免重复创建。

import AppKit
import SwiftUI

final class SettingsWindow {
    /// 单例窗口实例。
    private static var window: NSWindow?

    /// 打开设置窗口（如果已打开则前置）。
    static func open(store: MappingStore) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(store: store)
        let hostingController = NSHostingController(rootView: settingsView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "按键映射设置"
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
