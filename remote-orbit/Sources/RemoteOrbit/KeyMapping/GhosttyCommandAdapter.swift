import AppKit
import ApplicationServices

/// 尝试通过 Ghostty 的菜单命令执行语义动作，而不是依赖用户当前设置的
/// 快捷键。Ghostty 没有向 RemoteOrbit 暴露统一的本地命令协议时，这个适配器作为
/// best-effort 路径工作；找不到菜单项时由 KeyInjector 回退到默认快捷键。
enum GhosttyCommandAdapter {
    static let bundleIdentifier = "com.mitchellh.ghostty"

    @discardableResult
    static func execute(_ action: ButtonAction) -> Bool {
        guard MappingStore.isApplicationActuallyFocused(bundleIdentifier),
              let application = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == bundleIdentifier
              }),
              AXIsProcessTrusted()
        else { return false }

        guard let titles = menuTitles(for: action),
              let menuBar = attributeElement(
                  AXUIElementCreateApplication(application.processIdentifier),
                  kAXMenuBarAttribute as CFString
              ),
              let item = findMenuItem(in: menuBar, titles: titles, depth: 8),
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        else { return false }
        return true
    }

    private static func menuTitles(for action: ButtonAction) -> [String]? {
        switch action {
        case .ghosttyNewTab:
            return ["New Tab", "New Tab…", "新建标签", "新建标签页"]
        case .ghosttyNewWindow:
            return ["New Window", "新建窗口"]
        case .ghosttyPreviousTab:
            return ["Previous Tab", "Show Previous Tab", "上一个标签", "上一个标签页"]
        case .ghosttyNextTab:
            return ["Next Tab", "Show Next Tab", "下一个标签", "下一个标签页"]
        case .ghosttyCloseSurface:
            return ["Close Surface", "Close Tab", "Close Window", "Close", "关闭当前 surface", "关闭标签"]
        case .ghosttyCloseTab:
            return ["Close Tab", "关闭标签", "关闭标签页"]
        case .ghosttyCloseWindow:
            return ["Close Window", "关闭窗口"]
        case .ghosttyNewSplitRight:
            return ["New Split Right", "Split Right", "向右新建分屏", "向右分屏"]
        case .ghosttyNewSplitDown:
            return ["New Split Down", "Split Down", "向下新建分屏", "向下分屏"]
        case .ghosttyPreviousSplit:
            return ["Select Previous Split", "Previous Split", "上一个分屏"]
        case .ghosttyNextSplit:
            return ["Select Next Split", "Next Split", "下一个分屏"]
        case .ghosttyToggleSplitZoom:
            return ["Zoom Split", "Toggle Split Zoom", "缩放分屏"]
        case .ghosttyEqualizeSplits:
            return ["Equalize Splits", "均分分屏"]
        case .ghosttyClearScreen:
            return ["Clear", "Clear Screen", "清屏"]
        case .ghosttyCommandPalette:
            return ["Command Palette", "Command Palette…", "命令面板"]
        case .ghosttySearch:
            return ["Search", "Find", "Find…", "搜索", "查找"]
        case .ghosttyFindNext:
            return ["Find Next", "查找下一个"]
        case .ghosttyFindPrevious:
            return ["Find Previous", "查找上一个"]
        case .ghosttyIncreaseFontSize:
            return ["Increase Font Size", "Bigger", "增大字体", "放大"]
        case .ghosttyDecreaseFontSize:
            return ["Decrease Font Size", "Smaller", "减小字体", "缩小"]
        case .ghosttyResetFontSize:
            return ["Reset Font Size", "Actual Size", "重置字体"]
        case .ghosttyToggleFullScreen:
            return ["Enter Full Screen", "Exit Full Screen", "Toggle Full Screen", "进入全屏", "退出全屏"]
        case .ghosttyOpenConfig:
            return ["Settings…", "Open Configuration", "设置…", "打开配置"]
        case .ghosttyReloadConfig:
            return ["Reload Configuration", "重新加载配置"]
        default:
            return nil
        }
    }

    private static func attributeElement(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> AXUIElement? {
        guard let value = attributeValue(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = attributeValue(element, kAXChildrenAttribute as CFString),
              let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func title(of element: AXUIElement) -> String? {
        attributeValue(element, kAXTitleAttribute as CFString) as? String
    }

    private static func attributeValue(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func findMenuItem(
        in element: AXUIElement,
        titles: [String],
        depth: Int
    ) -> AXUIElement? {
        if let currentTitle = title(of: element),
           titles.contains(where: { normalized($0) == normalized(currentTitle) }) {
            return element
        }
        guard depth > 0 else { return nil }
        for child in children(of: element) {
            if let match = findMenuItem(in: child, titles: titles, depth: depth - 1) {
                return match
            }
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
