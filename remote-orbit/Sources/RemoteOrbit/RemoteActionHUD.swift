import AppKit

/// A small, non-interactive overlay for confirming the action selected by a
/// physical remote button. It does not activate RemoteOrbit or run a polling
/// loop, so the current text field or web page keeps focus.
enum RemoteActionHUDState: Equatable {
    case pending
    case queued
    case success
    case failure

    var title: String {
        switch self {
        case .pending: return "识别中"
        case .queued: return "已排队"
        case .success: return "已执行"
        case .failure: return "执行失败"
        }
    }

    var color: NSColor {
        switch self {
        case .pending: return .systemYellow
        case .queued: return .systemBlue
        case .success: return .systemGreen
        case .failure: return .systemRed
        }
    }
}

final class RemoteActionHUD {
    private let panelSize = NSSize(width: 248, height: 40)
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(
        button: RemoteButton,
        gesture: String,
        action: String,
        state: RemoteActionHUDState,
        keepsPendingVisible: Bool = false
    ) {
        if Thread.isMainThread {
            present(
                button: button,
                gesture: gesture,
                action: action,
                state: state,
                keepsPendingVisible: keepsPendingVisible
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.present(
                    button: button,
                    gesture: gesture,
                    action: action,
                    state: state,
                    keepsPendingVisible: keepsPendingVisible
                )
            }
        }
    }

    /// Hide an unfinished gesture hint, for example when the HID device
    /// disconnects before sending its release edge.
    func dismiss() {
        if Thread.isMainThread {
            dismissNow()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.dismissNow()
            }
        }
    }

    private func present(
        button: RemoteButton,
        gesture: String,
        action: String,
        state: RemoteActionHUDState,
        keepsPendingVisible: Bool
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        dismissWorkItem?.cancel()

        let content = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 9
        content.layer?.masksToBounds = true
        // The visual effect is the surface. Do not add a white fill or border:
        // on dark desktops that makes the overlay look like a large opaque
        // card instead of a compact frosted-glass hint.

        let marker = NSImageView(image: markerImage(for: state))
        marker.contentTintColor = NSColor.white.withAlphaComponent(0.96)
        marker.imageScaling = .scaleProportionallyUpOrDown
        marker.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "\(button.displayName) · \(gesture)")
        title.alignment = .center
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = NSColor.white.withAlphaComponent(0.96)
        title.lineBreakMode = .byTruncatingTail

        let detail = NSTextField(labelWithString: "\(action) · \(state.title)")
        detail.alignment = .center
        detail.font = .systemFont(ofSize: 9, weight: .medium)
        detail.textColor = state.color.withAlphaComponent(0.92)
        detail.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [title, detail])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [marker, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(row)
        NSLayoutConstraint.activate([
            marker.widthAnchor.constraint(equalToConstant: 15),
            marker.heightAnchor.constraint(equalToConstant: 15),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
            row.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        panel.contentView = content
        panel.setContentSize(panelSize)
        position(panel)
        panel.orderFrontRegardless()

        // A gesture-enabled button is undecided between single, double, and
        // long press at the first down edge. Keep that pending state visible
        // until the recognizer emits a result and the action is dispatched.
        // Voice input uses the default (false) so its transient “按住” hint
        // retains the old automatic timeout.
        guard !(state == .pending && keepsPendingVisible) else { return }

        let work = DispatchWorkItem { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.panel === panel {
                self?.dismissWorkItem = nil
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: work)
    }

    private func dismissNow() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
    }

    private func markerImage(for state: RemoteActionHUDState) -> NSImage {
        let symbolName: String
        switch state {
        case .pending: symbolName = "waveform"
        case .queued: symbolName = "clock"
        case .success: symbolName = "checkmark"
        case .failure: symbolName = "exclamationmark"
        }
        return NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: state.title
        ) ?? NSImage()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.minY + 72
            )
        )
    }
}
