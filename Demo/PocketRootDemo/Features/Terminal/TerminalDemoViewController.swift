import PocketRoot
import UIKit

@MainActor
final class TerminalDemoViewController: UIViewController, DemoRuntimeStoreObserver {
    private let runtimeStore: DemoRuntimeStore
    private let statusLabel = UILabel()
    private let bootButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let placeholderStack = UIStackView()
    private var terminalController: PocketRootTerminalViewController?
    private var sessionEndReason: PocketRootTerminalSessionEndReason?
    private var isObserving = false

    init(runtimeStore: DemoRuntimeStore) {
        self.runtimeStore = runtimeStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Terminal"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground
        configurePlaceholder()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !isObserving else {
            return
        }
        isObserving = true
        runtimeStore.addObserver(self)
        Task {
            await runtimeStore.refreshRuntimeState()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        runtimeStore.removeObserver(self)
        isObserving = false
    }

    func demoRuntimeStoreDidChange(_ store: DemoRuntimeStore) {
        guard let system = store.readySystem else {
            sessionEndReason = nil
            removeTerminal()
            renderPlaceholder(for: store)
            return
        }
        if let sessionEndReason {
            renderEndedSession(sessionEndReason)
            return
        }
        installTerminalIfNeeded(system: system)
    }

    private func configurePlaceholder() {
        let imageView = UIImageView(image: UIImage(systemName: "terminal"))
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48)
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Prepare and Boot Runtime"
        configuration.image = UIImage(systemName: "power")
        configuration.imagePadding = 8
        bootButton.configuration = configuration
        bootButton.addTarget(self, action: #selector(performPrimaryAction), for: .touchUpInside)

        placeholderStack.addArrangedSubview(imageView)
        placeholderStack.addArrangedSubview(activityIndicator)
        placeholderStack.addArrangedSubview(statusLabel)
        placeholderStack.addArrangedSubview(bootButton)
        placeholderStack.axis = .vertical
        placeholderStack.alignment = .center
        placeholderStack.spacing = 18
        placeholderStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderStack)

        NSLayoutConstraint.activate([
            placeholderStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            placeholderStack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            placeholderStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor
            ),
            placeholderStack.trailingAnchor.constraint(
                lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor
            ),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

    private func renderPlaceholder(for store: DemoRuntimeStore) {
        placeholderStack.isHidden = false
        navigationItem.rightBarButtonItem = nil
        activityIndicator.stopAnimating()
        bootButton.isHidden = true
        bootButton.configuration?.title = "Prepare and Boot Runtime"

        switch store.phase {
        case .rootFSMissing:
            statusLabel.text = [
                "RootFS is not embedded in this Debug build.",
                "Rebuild with POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE set to the reviewed archive."
            ].joined(separator: "\n")
        case .runtimeUnavailable:
            statusLabel.text = "The arm64 iSH runtime is unavailable in this build."
        case .idle:
            statusLabel.text = "The embedded RootFS is ready. Boot the runtime to open a persistent shell."
            bootButton.isHidden = false
            bootButton.isEnabled = true
        case .preparingRootFS:
            statusLabel.text = "Verifying and installing RootFS…"
            activityIndicator.startAnimating()
        case .booting:
            statusLabel.text = "Booting Alpine Linux…"
            activityIndicator.startAnimating()
        case .shuttingDown:
            statusLabel.text = "Shutting down the runtime…"
            activityIndicator.startAnimating()
        case .terminated:
            statusLabel.text = "The runtime has shut down. Restart the App to boot again."
        case .failed(let message):
            statusLabel.text = "Runtime failed:\n\(message)"
            bootButton.isHidden = !store.canBoot
            bootButton.isEnabled = store.canBoot
            bootButton.configuration?.title = "Retry Prepare and Boot"
        case .ready:
            break
        }
    }

    private func installTerminalIfNeeded(system: PocketRootSystem) {
        sessionEndReason = nil
        placeholderStack.isHidden = true
        configureFilesButton()
        guard terminalController == nil else {
            return
        }

        let terminalController = PocketRootTerminalViewController(
            system: system,
            configuration: .interactive(initialWorkingDirectory: "/root"),
            theme: .dark
        )
        terminalController.onSessionEnded = { [weak self, weak terminalController] reason in
            guard let self,
                  let terminalController,
                  self.terminalController === terminalController
            else {
                return
            }
            self.removeTerminal()
            self.sessionEndReason = reason
            if case .failed = reason {
                self.renderEndedSession(reason, isReconcilingRuntime: true)
                Task { [weak self] in
                    guard let self else {
                        return
                    }
                    await runtimeStore.refreshRuntimeState()
                }
            } else {
                self.renderEndedSession(reason)
            }
        }
        addChild(terminalController)
        terminalController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalController.view)
        NSLayoutConstraint.activate([
            terminalController.view.topAnchor.constraint(equalTo: view.topAnchor),
            terminalController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        terminalController.didMove(toParent: self)
        self.terminalController = terminalController
    }

    private func removeTerminal() {
        guard let terminalController else {
            return
        }
        terminalController.onSessionEnded = nil
        terminalController.closeSession()
        terminalController.willMove(toParent: nil)
        terminalController.view.removeFromSuperview()
        terminalController.removeFromParent()
        self.terminalController = nil
    }

    private func renderEndedSession(
        _ reason: PocketRootTerminalSessionEndReason,
        isReconcilingRuntime: Bool = false
    ) {
        placeholderStack.isHidden = false
        if isReconcilingRuntime {
            navigationItem.rightBarButtonItem = nil
            activityIndicator.startAnimating()
            statusLabel.text = Self.sessionFailureCheckingMessage(for: reason)
        } else {
            configureFilesButton()
            activityIndicator.stopAnimating()
            statusLabel.text = Self.sessionEndedMessage(for: reason)
        }
        bootButton.configuration?.title = "Open New Terminal"
        bootButton.isHidden = isReconcilingRuntime
        bootButton.isEnabled =
            !isReconcilingRuntime && runtimeStore.readySystem != nil
    }

    private func configureFilesButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Files",
            image: UIImage(systemName: "folder"),
            target: self,
            action: #selector(openFiles)
        )
    }

    static func sessionEndedMessage(
        for reason: PocketRootTerminalSessionEndReason
    ) -> String {
        switch reason {
        case .exited(0):
            return "The terminal session ended. Open a new terminal to continue."
        case .exited(let exitCode):
            return [
                "The terminal session exited with code \(exitCode).",
                "Open a new terminal to continue."
            ].joined(separator: "\n")
        case .failed(let message):
            return [
                "The terminal session failed:",
                message,
                "Open a new terminal to try again."
            ].joined(separator: "\n")
        }
    }

    static func sessionFailureCheckingMessage(
        for reason: PocketRootTerminalSessionEndReason
    ) -> String {
        guard case .failed(let message) = reason else {
            return sessionEndedMessage(for: reason)
        }
        return [
            "The terminal session failed:",
            message,
            "Checking runtime state…"
        ].joined(separator: "\n")
    }

    @objc
    private func performPrimaryAction() {
        if sessionEndReason != nil, let system = runtimeStore.readySystem {
            installTerminalIfNeeded(system: system)
            return
        }
        Task {
            await runtimeStore.boot()
        }
    }

    @objc
    private func openFiles() {
        guard let system = runtimeStore.readySystem else {
            return
        }
        let filesController = PocketRootFileBrowserViewController(
            system: system,
            initialPath: "/root"
        )
        navigationController?.pushViewController(filesController, animated: true)
    }
}
