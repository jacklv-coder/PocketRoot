#if canImport(SwiftUI) && canImport(UIKit)
import PocketRootCore
import PocketRootTerminal
import SwiftUI
import UIKit

/// A one-screen UIKit integration that prepares RootFS, boots iSH, and embeds
/// the persistent Terminal/Files workspace owned by its process-lifetime host.
@available(iOS 18.0, *)
@MainActor
public final class PocketRootIshWorkspaceViewController: UIViewController {
    public let host: PocketRootIshWorkspaceHost

    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private let statusStack = UIStackView()
    private var workspaceController: PocketRootWorkspaceViewController?
    private var hasRequestedBoot = false
    private var wasAttachedToParent = false
    private var isDetached = false

    init(host: PocketRootIshWorkspaceHost) {
        self.host = host
        super.init(nibName: nil, bundle: nil)
        host.register(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "PocketRoot"
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "PocketRootIshWorkspace"
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
        guard let workspaceController else {
            completion?()
            return
        }
        workspaceController.closeSession(completion: completion)
    }

    func runtimePhaseDidChange(_ phase: PocketRootIshRuntimePhase) {
        guard isViewLoaded, !isDetached else {
            return
        }
        render(phase)
        if phase == .ready, let system = host.readySystem {
            installWorkspaceIfNeeded(system: system)
        }
    }

    func detach() {
        guard !isDetached else {
            return
        }
        isDetached = true
        let host = host
        closeSession { [weak self, weak host] in
            guard let self else {
                return
            }
            host?.unregister(self)
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
        if let system = host.readySystem {
            installWorkspaceIfNeeded(system: system)
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
                self.installWorkspaceIfNeeded(system: system)
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

    private func installWorkspaceIfNeeded(system: PocketRootSystem) {
        guard workspaceController == nil, !isDetached else {
            return
        }
        let workspace = PocketRootWorkspaceViewController(
            system: system,
            configuration: host.workspaceConfiguration
        )
        workspace.loadViewIfNeeded()
        navigationItem.titleView = workspace.navigationItem.titleView
        workspace.onTerminalSessionEnded = { [weak self] reason in
            guard let self else {
                return
            }
            if case .failed = reason {
                Task {
                    await self.host.refreshRuntimeState()
                }
            }
        }
        addChild(workspace)
        workspace.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(workspace.view)
        NSLayoutConstraint.activate([
            workspace.view.topAnchor.constraint(equalTo: view.topAnchor),
            workspace.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            workspace.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            workspace.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        workspace.didMove(toParent: self)
        workspaceController = workspace
        statusStack.isHidden = true
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
        statusStack.isHidden = workspaceController != nil
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
}

@available(iOS 18.0, *)
public extension PocketRootIshWorkspaceHost {
    /// Creates a workspace screen that automatically prepares and boots this
    /// process-lifetime host.
    func makeViewController() -> PocketRootIshWorkspaceViewController {
        PocketRootIshWorkspaceViewController(host: self)
    }
}
#endif
