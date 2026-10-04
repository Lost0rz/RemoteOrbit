import AppKit
import Foundation

struct FrontmostApplicationIdentity: Equatable {
    let bundleIdentifier: String
    let processIdentifier: Int32

    init?(bundleIdentifier: String?, processIdentifier: Int32) {
        guard let bundleIdentifier,
              !bundleIdentifier.isEmpty,
              processIdentifier > 0 else {
            return nil
        }
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }

    init?(application: NSRunningApplication?) {
        guard let application else { return nil }
        self.init(
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier
        )
    }
}

final class FrontmostApplicationTransitionReporter {
    private let authority: any DiagnosticAuthority
    private var previousIdentity: FrontmostApplicationIdentity?

    init(authority: any DiagnosticAuthority) {
        self.authority = authority
    }

    func establishBaseline(_ identity: FrontmostApplicationIdentity?) {
        previousIdentity = identity
    }

    func observe(_ identity: FrontmostApplicationIdentity?) {
        guard let identity else { return }
        guard let previousIdentity else {
            self.previousIdentity = identity
            return
        }
        guard previousIdentity != identity else { return }

        self.previousIdentity = identity
        guard let input = try? DiagnosticEventInput(
            eventType: "application.frontmost.transition",
            subsystem: "application.frontmost",
            category: "transition",
            severity: .info,
            sourceComponent: "frontmost_application_observer",
            payload: [
                "previous_bundle_identifier": .string(previousIdentity.bundleIdentifier),
                "previous_process_id": .unsignedInteger(UInt64(previousIdentity.processIdentifier)),
                "current_bundle_identifier": .string(identity.bundleIdentifier),
                "current_process_id": .unsignedInteger(UInt64(identity.processIdentifier)),
            ]
        ) else { return }
        authority.emit(input)
    }
}

final class FrontmostApplicationDiagnosticsObserver {
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private let reporter: FrontmostApplicationTransitionReporter
    private var observerTokens: [NSObjectProtocol] = []
    private var isRunning = false

    init(
        workspace: NSWorkspace = .shared,
        authority: any DiagnosticAuthority = DiagnosticAuthorityService.shared
    ) {
        self.workspace = workspace
        self.notificationCenter = workspace.notificationCenter
        self.reporter = FrontmostApplicationTransitionReporter(authority: authority)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let notifications: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ]
        observerTokens = notifications.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.observeFrontmostApplication()
            }
        }
        observeFrontmostApplication(establishingBaseline: true)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
    }

    private func observeFrontmostApplication(establishingBaseline: Bool = false) {
        let identity = FrontmostApplicationIdentity(application: workspace.frontmostApplication)
        if establishingBaseline {
            reporter.establishBaseline(identity)
        } else {
            reporter.observe(identity)
        }
    }
}
