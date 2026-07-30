#if canImport(SwiftUI) && canImport(UIKit)
import PocketRootCore
import PocketRootTerminal
import SwiftUI
import UIKit

/// A host-managed UIKit screen that prepares RootFS, boots iSH, and embeds a
/// Terminal, Files browser, or combined workspace.
@available(iOS 18.0, *)
@MainActor
public final class PocketRootIshWorkspaceViewController: UIViewController {
    public let host: PocketRootIshWorkspaceHost

    fileprivate enum Content {
        case workspace
        case terminal
        case files

        var title: String {
            switch self {
            case .workspace:
                "PocketRoot"
            case .terminal:
                "Terminal"
            case .files:
                "Files"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .workspace:
                "PocketRootIshWorkspace"
            case .terminal:
                "PocketRootIshTerminal"
            case .files:
                "PocketRootIshFiles"
            }
        }
    }

    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private let statusStack = UIStackView()
    private let content: Content
    private var contentController: UIViewController?
    private var workspaceController: PocketRootWorkspaceViewController?
    private var terminalController: PocketRootTerminalViewController?
    private var hasRequestedBoot = false
    private var wasAttachedToParent = false
    private var isDetached = false

    fileprivate init(
        host: PocketRootIshWorkspaceHost,
        content: Content
    ) {
        self.host = host
        self.content = content
        super.init(nibName: nil, bundle: nil)
        host.register(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = content.title
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = content.accessibilityIdentifier
        configureStatusView()
        render(host.phase)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isDetached else {
            return
        }
        Task { [weak self] in
            guard let self else {
                return
            }
            await host.refreshRuntimeState()
            startIfNeeded()
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isPermanentlyLeavingHierarchy else {
            return
        }
        detach()
    }

    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil {
            wasAttachedToParent = true
        } else if wasAttachedToParent {
            detach()
        }
    }

    /// Closes only this screen's PTY. The host runtime remains ready for a
    /// later workspace until ``PocketRootIshWorkspaceHost.shutdown()``.
    public func closeSession(
        completion: (@MainActor () -> Void)? = nil
    ) {
        if let workspaceController {
            workspaceController.closeSession(completion: completion)
        } else if let terminalController {
            terminalController.closeSession(completion: completion)
        } else {
            completion?()
        }
    }

    func runtimePhaseDidChange(_ phase: PocketRootIshRuntimePhase) {
        guard isViewLoaded, !isDetached else {
            return
        }
        render(phase)
        if phase == .ready,
           host.canOpenWorkspace,
           let system = host.readySystem
        {
            installContentIfNeeded(system: system)
        }
    }

    func detach() {
        guard !isDetached else {
            return
        }
        isDetached = true
        let host = host
        closeSession { [self, host] in
            host.unregister(self)
        }
    }

    private func configureStatusView() {
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.accessibilityIdentifier = "PocketRootIshWorkspace.status"

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Retry"
        configuration.image = UIImage(systemName: "arrow.clockwise")
        configuration.imagePadding = 8
        retryButton.configuration = configuration
        retryButton.accessibilityIdentifier = "PocketRootIshWorkspace.retry"
        retryButton.addTarget(
            self,
            action: #selector(retryBoot),
            for: .touchUpInside
        )

        statusStack.addArrangedSubview(activityIndicator)
        statusStack.addArrangedSubview(statusLabel)
        statusStack.addArrangedSubview(retryButton)
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 16
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusStack.centerYAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerYAnchor
            ),
            statusStack.centerXAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerXAnchor
            ),
            statusStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor
            ),
            statusStack.trailingAnchor.constraint(
                lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor
            )
        ])
    }

    private func startIfNeeded() {
        guard !isDetached else {
            return
        }
        guard host.canOpenWorkspace else {
            render(host.phase)
            return
        }
        if let system = host.readySystem {
            installContentIfNeeded(system: system)
            return
        }
        guard host.canBoot, !hasRequestedBoot else {
            render(host.phase)
            return
        }
        hasRequestedBoot = true
        render(host.phase)
        let host = host
        Task { [weak self] in
            do {
                let system = try await host.boot()
                guard let self, !self.isDetached else {
                    return
                }
                self.installContentIfNeeded(system: system)
            } catch {
                guard let self, !self.isDetached else {
                    return
                }
                self.hasRequestedBoot = false
                self.render(
                    host.phase,
                    failure: error.localizedDescription
                )
            }
        }
    }

    private func installContentIfNeeded(system: PocketRootSystem) {
        guard contentController == nil,
              !isDetached,
              host.canOpenWorkspace,
              host.readySystem === system
        else {
            return
        }

        let controller: UIViewController
        switch content {
        case .workspace:
            let workspace = PocketRootWorkspaceViewController(
                system: system,
                configuration: host.workspaceConfiguration
            )
            workspace.loadViewIfNeeded()
            navigationItem.titleView = workspace.navigationItem.titleView
            workspace.onTerminalSessionEnded = makeSessionEndHandler()
            workspaceController = workspace
            controller = workspace
        case .terminal:
            let configuration = host.workspaceConfiguration
            let terminal = PocketRootTerminalViewController(
                system: system,
                sessionConfiguration:
                    configuration.terminalSessionConfiguration,
                configuration: configuration.terminalConfiguration,
                theme: configuration.terminalTheme
            )
            terminal.onSessionEnded = makeSessionEndHandler()
            terminalController = terminal
            controller = terminal
        case .files:
            controller = PocketRootFileBrowserViewController(
                system: system,
                initialPath: host.workspaceConfiguration.initialFilePath,
                allowsFileOperations:
                    host.workspaceConfiguration.allowsFileOperations
            )
        }

        controller.loadViewIfNeeded()
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        contentController = controller
        statusStack.isHidden = true
    }

    private func makeSessionEndHandler() -> (
        PocketRootTerminalSessionEndReason
    ) -> Void {
        { [weak self] reason in
            guard let self else {
                return
            }
            title = Self.sessionEndTitle(reason)
            if case .failed = reason {
                Task {
                    await self.host.refreshRuntimeState()
                }
            }
        }
    }

    private func render(
        _ phase: PocketRootIshRuntimePhase,
        failure: String? = nil
    ) {
        let description: String
        switch phase {
        case .unavailable:
            description = "iSH runtime unavailable"
        case .idle:
            description = "Ready to prepare RootFS"
        case .preparingRootFS:
            description = "Preparing RootFS…"
        case .booting:
            description = "Booting Linux…"
        case .ready:
            description = "Ready"
        case .shuttingDown:
            description = "Shutting down…"
        case .terminated:
            description = "Runtime terminated; restart the App"
        case .failed(let message):
            description = "Boot failed: \(failure ?? message)"
        }
        statusLabel.text = description
        statusStack.isHidden = contentController != nil
        switch phase {
        case .preparingRootFS, .booting, .shuttingDown:
            activityIndicator.startAnimating()
        default:
            activityIndicator.stopAnimating()
        }
        retryButton.isHidden = !host.canBoot
    }

    private var isPermanentlyLeavingHierarchy: Bool {
        var controller: UIViewController? = self
        while let current = controller {
            if current.isMovingFromParent || current.isBeingDismissed {
                return true
            }
            controller = current.parent
        }
        return false
    }

    @objc private func retryBoot() {
        hasRequestedBoot = false
        startIfNeeded()
    }

    private static func sessionEndTitle(
        _ reason: PocketRootTerminalSessionEndReason
    ) -> String {
        switch reason {
        case .exited(let code):
            "Terminal Exited (\(code))"
        case .failed:
            "Terminal Failed"
        }
    }
}

@available(iOS 18.0, *)
public extension PocketRootIshWorkspaceHost {
    /// Creates a workspace screen that automatically prepares and boots this
    /// process-lifetime host.
    func makeViewController() -> PocketRootIshWorkspaceViewController {
        PocketRootIshWorkspaceViewController(
            host: self,
            content: .workspace
        )
    }

    /// Creates a full PTY Terminal screen that automatically prepares and
    /// boots this process-lifetime host. Removing the screen closes only its
    /// terminal session, leaving the runtime ready for another screen.
    func makeTerminalViewController()
        -> PocketRootIshWorkspaceViewController
    {
        PocketRootIshWorkspaceViewController(
            host: self,
            content: .terminal
        )
    }

    /// Creates a Files screen that automatically prepares and boots this
    /// process-lifetime host.
    func makeFilesViewController()
        -> PocketRootIshWorkspaceViewController
    {
        PocketRootIshWorkspaceViewController(
            host: self,
            content: .files
        )
    }
}
#endif
