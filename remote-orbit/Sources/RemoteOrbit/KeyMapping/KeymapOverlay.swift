// KeymapOverlay.swift — contextual remote-control map
//
// Shows the effective mapping for the current foreground application as a
// translucent, controller-shaped reference. The remote outline mirrors the
// physical voice remote geometry; action labels are connected to the
// corresponding physical button with leader lines.

import AppKit
import SwiftUI

struct KeymapActionLine: Identifiable, Equatable {
    let id: String
    let gesture: String
    let action: String
}

struct KeymapButtonPresentation: Identifiable, Equatable {
    let button: RemoteButton
    let lines: [KeymapActionLine]

    var id: String { button.id }
}

struct KeymapPresentation: Equatable {
    let appName: String
    let scopeName: String
    let targetBundleIdentifier: String?
    let routeSource: String
    let buttons: [KeymapButtonPresentation]

    static func resolve(
        store: MappingStore,
        route: ApplicationRouteSnapshot = MappingStore.preferredApplicationRoute()
    ) -> KeymapPresentation {
        let bundleID = route.bundleIdentifier
        let appName = displayName(for: bundleID)
        let template = bundleID.flatMap { store.activeTemplate(for: $0) }
        let scopeName = template?.templateName ?? "通用映射"
        let buttons = RemoteButton.allCases.map { button in
            KeymapButtonPresentation(
                button: button,
                lines: actionLines(
                    for: button,
                    binding: store.binding(for: button, appBundleIdentifier: bundleID),
                    profile: store.gestureProfile(
                        for: button,
                        appBundleIdentifier: bundleID
                    )
                )
            )
        }

        return KeymapPresentation(
            appName: appName,
            scopeName: scopeName,
            targetBundleIdentifier: bundleID,
            routeSource: routeSourceLabel(route.source),
            buttons: buttons
        )
    }

    private static func displayName(for bundleIdentifier: String?) -> String {
        guard let bundleIdentifier else { return "通用映射" }
        if let known = AppTemplatePresetLibrary.knownApps.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            return known.displayName
        }
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first,
           let name = running.localizedName,
           !name.isEmpty {
            return name
        }
        return bundleIdentifier
    }

    private static func routeSourceLabel(_ source: String) -> String {
        switch source {
        case "frontmost": return "当前前台程序"
        case "accessibility-focus": return "当前输入焦点"
        case "cached": return "最近使用程序"
        case "global": return "通用映射"
        default: return "当前程序"
        }
    }

    static func actionLines(
        for button: RemoteButton,
        binding: ButtonBinding,
        profile: ButtonGestureProfile
    ) -> [KeymapActionLine] {
        var lines: [KeymapActionLine] = []

        if case .voiceKeyDefault = binding {
            lines.append(
                KeymapActionLine(
                    id: "\(button.rawValue)-single-voice",
                    gesture: "单击",
                    action: "输入法持续会话"
                )
            )
        } else {
            let trigger = binding.shortcutTriggerMode == .repeatWhileHeld
                ? "单击 · 重复"
                : "单击"
            lines.append(
                KeymapActionLine(
                    id: "\(button.rawValue)-single",
                    gesture: trigger,
                    action: binding.hudDisplayName
                )
            )
        }

        let hasRemoteVoiceLongPress = profile.longPressEnabled
            && profile.longPress == .voiceKeyDefault
            && profile.longPressBehavior != .none
        guard profile.usesAdvancedGestures || hasRemoteVoiceLongPress else {
            return lines
        }

        if profile.doubleTapEnabled,
           let doubleTap = profile.doubleTap,
           doubleTap.isUsableGestureAction {
            lines.append(
                KeymapActionLine(
                    id: "\(button.rawValue)-double",
                    gesture: "双击",
                    action: doubleTap.hudDisplayName
                )
            )
        }

        if profile.longPressEnabled,
           let longPress = profile.longPress,
           profile.longPressBehavior != .none,
           longPress.isUsableGestureAction || longPress == .voiceKeyDefault {
            let gesture = profile.longPressBehavior == .repeatWhileHeld
                ? "长按 · 重复"
                : "长按"
            let action = longPress == .voiceKeyDefault
                ? "遥控器语音输入"
                : longPress.hudDisplayName
            lines.append(
                KeymapActionLine(
                    id: "\(button.rawValue)-long",
                    gesture: gesture,
                    action: action
                )
            )
        }

        return lines
    }
}

private enum KeymapOverlayLayout {
    static let panelSize = NSSize(width: 600, height: 550)
    static let mapSize = CGSize(width: 600, height: 500)
    static let remoteFrame = CGRect(x: 245, y: 10, width: 110, height: 420)
}

final class KeymapOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<KeymapOverlayView>?

    func show(store: MappingStore) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.show(store: store)
            }
            return
        }

        present(KeymapPresentation.resolve(store: store))
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func present(_ presentation: KeymapPresentation) {
        let view = KeymapOverlayView(
            presentation: presentation
        )

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            hostingView?.rootView = view
        } else {
            panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: KeymapOverlayLayout.panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: KeymapOverlayLayout.panelSize)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            hostingView = hosting
            self.panel = panel
        }

        panel.setContentSize(KeymapOverlayLayout.panelSize)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        position(panel)
        panel.orderFrontRegardless()
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 34
        )
        panel.setFrameOrigin(origin)
    }
}

struct KeymapOverlayView: View {
    let presentation: KeymapPresentation

    private struct CalloutSpec: Identifiable {
        enum Side { case left, right }

        let button: RemoteButton
        let side: Side
        let y: CGFloat

        var id: String { button.id }
    }

    private let callouts: [CalloutSpec] = [
        CalloutSpec(button: .power, side: .left, y: 38),
        CalloutSpec(button: .left, side: .left, y: 110),
        CalloutSpec(button: .down, side: .left, y: 190),
        CalloutSpec(button: .back, side: .left, y: 270),
        CalloutSpec(button: .home, side: .left, y: 350),
        CalloutSpec(button: .menu, side: .left, y: 430),
        CalloutSpec(button: .microphone, side: .right, y: 38),
        CalloutSpec(button: .up, side: .right, y: 105),
        CalloutSpec(button: .ok, side: .right, y: 175),
        CalloutSpec(button: .right, side: .right, y: 245),
        CalloutSpec(button: .volumeUp, side: .right, y: 315),
        CalloutSpec(button: .volumeDown, side: .right, y: 385),
        CalloutSpec(button: .tv, side: .right, y: 455),
    ]

    private var buttonMap: [RemoteButton: KeymapButtonPresentation] {
        Dictionary(uniqueKeysWithValues: presentation.buttons.map { ($0.button, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            map
            footer
        }
        .frame(
            width: KeymapOverlayLayout.panelSize.width,
            height: KeymapOverlayLayout.panelSize.height
        )
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
    }

    private var map: some View {
        ZStack {
            leaderLines
            ForEach(callouts) { spec in
                callout(spec)
            }
            remoteBody
                .frame(
                    width: KeymapOverlayLayout.remoteFrame.width,
                    height: KeymapOverlayLayout.remoteFrame.height
                )
                .position(
                    x: KeymapOverlayLayout.remoteFrame.midX,
                    y: KeymapOverlayLayout.remoteFrame.midY
                )
        }
        .frame(width: KeymapOverlayLayout.mapSize.width, height: KeymapOverlayLayout.mapSize.height)
        .background(Color.black.opacity(0.025))
    }

    private var leaderLines: some View {
        Canvas { context, _ in
            for spec in callouts {
                let anchor = anchorPoint(for: spec.button)
                let remoteEdgeX = spec.side == .left
                    ? KeymapOverlayLayout.remoteFrame.minX
                    : KeymapOverlayLayout.remoteFrame.maxX
                let elbowX = spec.side == .left ? 180.0 : 420.0
                let cardEdgeX = spec.side == .left ? 157.0 : 443.0

                var path = Path()
                path.move(to: anchor)
                path.addLine(to: CGPoint(x: remoteEdgeX, y: anchor.y))
                path.addLine(to: CGPoint(x: elbowX, y: anchor.y))
                path.addLine(to: CGPoint(x: elbowX, y: spec.y))
                path.addLine(to: CGPoint(x: cardEdgeX, y: spec.y))
                context.stroke(
                    path,
                    with: .color(Color.black.opacity(0.30)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                )

                let dot = Path(ellipseIn: CGRect(
                    x: anchor.x - 2.5,
                    y: anchor.y - 2.5,
                    width: 5,
                    height: 5
                ))
                context.fill(dot, with: .color(Color.teal.opacity(0.95)))
            }
        }
        .allowsHitTesting(false)
    }

    private func callout(_ spec: CalloutSpec) -> some View {
        let item = buttonMap[spec.button]
            ?? KeymapButtonPresentation(
                button: spec.button,
                lines: [KeymapActionLine(
                    id: "\(spec.button.rawValue)-missing",
                    gesture: "单击",
                    action: "未配置"
                )]
            )

        return VStack(alignment: spec.side == .left ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 5) {
                if spec.side == .right { Spacer(minLength: 0) }
                Text(spec.button.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.78), radius: 1.4, y: 0.7)
                Image(systemName: symbolName(for: spec.button))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.teal.opacity(0.92))
                if spec.side == .left { Spacer(minLength: 0) }
            }

            ForEach(item.lines) { line in
                HStack(spacing: 4) {
                    if spec.side == .right { Spacer(minLength: 0) }
                    Text(line.gesture)
                        .font(.system(size: 8.7, weight: .semibold, design: .rounded))
                        .foregroundStyle(gestureColor(line.gesture))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .shadow(color: .black.opacity(0.78), radius: 1.2, y: 0.6)
                    Text(line.action)
                        .font(.system(size: 8.9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.98))
                        .lineLimit(2)
                        .multilineTextAlignment(spec.side == .left ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 96, alignment: spec.side == .left ? .trailing : .leading)
                        .layoutPriority(1)
                        .shadow(color: .black.opacity(0.78), radius: 1.2, y: 0.6)
                    if spec.side == .left { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 142, alignment: spec.side == .left ? .trailing : .leading)
        .frame(minHeight: 64, alignment: spec.side == .left ? .trailing : .leading)
        .background(Color.black.opacity(0.50))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .position(
            x: spec.side == .left ? 86 : 514,
            y: spec.y
        )
    }

    private var remoteBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.16),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.black.opacity(0.16), lineWidth: 1.25)
                )
                .shadow(color: .black.opacity(0.18), radius: 14, y: 7)

            LinearGradient(
                colors: [Color.white.opacity(0.18), .clear, Color.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            remoteButtons
        }
    }

    private var remoteButtons: some View {
        ZStack {
            remoteButton(.power, size: 22).position(x: 32, y: 30)
            remoteButton(.microphone, size: 22).position(x: 78, y: 30)

            dPad.position(x: 55, y: 106)

            remoteButton(.back, size: 25).position(x: 26, y: 190)
            volumeRocker.position(x: 82, y: 235)
            remoteButton(.home, size: 25).position(x: 26, y: 238)
            remoteButton(.menu, size: 25).position(x: 26, y: 302)
            remoteButton(.tv, size: 25).position(x: 82, y: 302)
        }
    }

    private var dPad: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.52))
                .frame(width: 98, height: 98)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.46), lineWidth: 1)
                )
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .frame(width: 64, height: 64)
            Circle()
                .fill(Color.black.opacity(0.52))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            Text("OK")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.80))
            directionSymbol("chevron.up", x: 49, y: 12)
            directionSymbol("chevron.left", x: 12, y: 49)
            directionSymbol("chevron.right", x: 86, y: 49)
            directionSymbol("chevron.down", x: 49, y: 86)
        }
        .frame(width: 98, height: 98)
    }

    private var volumeRocker: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.50))
            .frame(width: 24, height: 72)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .overlay(
                VStack(spacing: 15) {
                    Text("+")
                    Divider().overlay(Color.white.opacity(0.16)).frame(width: 15)
                    Text("−")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
            )
    }

    private func remoteButton(_ button: RemoteButton, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.50))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            if button == .volumeUp {
                Text("+")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            } else if button == .volumeDown {
                Text("−")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            } else {
                Image(systemName: symbolName(for: button))
                    .font(.system(size: size * 0.30, weight: .medium))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(.white.opacity(0.82))
    }

    private func directionSymbol(_ name: String, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white.opacity(0.76))
            .position(x: x, y: y)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(presentation.appName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: 210)
                .shadow(color: .black.opacity(0.92), radius: 2, y: 1)

            HStack(spacing: 15) {
                legend("单击", color: .cyan)
                legend("双击", color: .mint)
                legend("长按", color: .orange)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.68))
                .shadow(color: .black.opacity(0.16), radius: 0.7, y: 0.4)
        }
    }

    private func anchorPoint(for button: RemoteButton) -> CGPoint {
        switch button {
        case .power: return CGPoint(x: 277, y: 40)
        case .microphone: return CGPoint(x: 323, y: 40)
        case .up: return CGPoint(x: 300, y: 79)
        case .left: return CGPoint(x: 263, y: 116)
        case .ok: return CGPoint(x: 300, y: 116)
        case .right: return CGPoint(x: 337, y: 116)
        case .down: return CGPoint(x: 300, y: 153)
        case .back: return CGPoint(x: 271, y: 200)
        case .volumeUp: return CGPoint(x: 327, y: 218)
        case .home: return CGPoint(x: 271, y: 248)
        case .volumeDown: return CGPoint(x: 327, y: 252)
        case .menu: return CGPoint(x: 271, y: 312)
        case .tv: return CGPoint(x: 327, y: 312)
        }
    }

    private func gestureColor(_ gesture: String) -> Color {
        if gesture.contains("双击") { return .mint }
        if gesture.contains("长按") { return .orange }
        return .cyan
    }

    private func symbolName(for button: RemoteButton) -> String {
        switch button {
        case .microphone: return "mic.fill"
        case .power: return "power"
        case .up: return "chevron.up"
        case .left: return "chevron.left"
        case .ok: return "checkmark"
        case .right: return "chevron.right"
        case .down: return "chevron.down"
        case .back: return "arrow.uturn.backward"
        case .volumeUp: return "speaker.plus"
        case .home: return "house.fill"
        case .volumeDown: return "speaker.minus"
        case .menu: return "line.3.horizontal"
        case .tv: return "rectangle.on.rectangle"
        }
    }
}
