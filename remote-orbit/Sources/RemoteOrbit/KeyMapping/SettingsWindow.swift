// SettingsWindow.swift — RemoteOrbit Control Center window
//
// 从菜单栏打开一个 NSWindow，内嵌 SwiftUI SettingsView。
// 保持窗口单例并维护明确的入口路由，避免重复创建或起始页漂移。

import AppKit
import Combine
import SwiftUI

enum SettingsEntryRoute: Equatable {
    case general
    case voiceShortcuts
}

struct SettingsRouteRequest: Equatable {
    let id: UUID
    let route: SettingsEntryRoute

    init(id: UUID = UUID(), route: SettingsEntryRoute) {
        self.id = id
        self.route = route
    }
}

final class SettingsNavigationModel: ObservableObject {
    @Published private(set) var routeRequest = SettingsRouteRequest(route: .general)

    func navigate(to route: SettingsEntryRoute) {
        routeRequest = SettingsRouteRequest(route: route)
    }
}

final class SettingsWindow {
    /// 单例窗口实例与路由模型。
    private static var window: NSWindow?
    private static let navigationModel = SettingsNavigationModel()

    /// 打开设置窗口（如果已存在则前置，并按请求切换到对应起始页）。
    static func open(
        store: MappingStore,
        route: SettingsEntryRoute = .general,
        onRecordingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        navigationModel.navigate(to: route)

        if let existing = window {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            store: store,
            navigation: navigationModel,
            onRecordingChanged: onRecordingChanged
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
