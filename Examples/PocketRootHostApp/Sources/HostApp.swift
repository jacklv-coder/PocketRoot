import PocketRoot
import PocketRootIshRuntimeIntegration
import UIKit

@main
@MainActor
final class HostAppDelegate: UIResponder, UIApplicationDelegate {
    var runtimeController: PocketRootIshRuntimeController?

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = HostSceneDelegate.self
        return configuration
    }
}

@MainActor
final class HostSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? HostAppDelegate
        else {
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(
            rootViewController: HostViewController(runtimeOwner: appDelegate)
        )
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let navigationController =
            window?.rootViewController as? UINavigationController,
           let hostViewController =
            navigationController.viewControllers.first as? HostViewController
        {
            hostViewController.closeActiveTerminal()
        }
        window = nil
    }
}

@MainActor
final class HostViewController: UIViewController {
    private static let rootFSName = "pocketroot-fs-v0.3.3"

    private let statusLabel = UILabel()
    private let bootButton = UIButton(type: .system)
    private let terminalButton = UIButton(type: .system)
    private let filesButton = UIButton(type: .system)

    private unowned let runtimeOwner: HostAppDelegate
    private weak var activeTerminal: PocketRootTerminalViewController?

    private var runtimeController: PocketRootIshRuntimeController? {
        runtimeOwner.runtimeController
    }

    init(runtimeOwner: HostAppDelegate) {
        self.runtimeOwner = runtimeOwner
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PocketRoot Host"
        view.backgroundColor = .systemBackground
        configureView()
        if let runtimeController {
            bind(to: runtimeController)
        } else {
            render(phase: .idle)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let activeTerminal,
           navigationController?.topViewController !== activeTerminal
        {
            activeTerminal.closeSession()
            self.activeTerminal = nil
        }
        if let runtimeController {
            Task {
                await runtimeController.refreshRuntimeState()
            }
        }
    }

    func closeActiveTerminal() {
        activeTerminal?.closeSession()
        activeTerminal = nil
    }

    private func configureView() {
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.accessibilityIdentifier = "PocketRootHost.status"

        configure(
            bootButton,
            title: "Boot Reviewed RootFS",
            symbol: "power",
            action: #selector(bootRuntime)
        )
        bootButton.accessibilityIdentifier = "PocketRootHost.boot"
        configure(
            terminalButton,
            title: "Open Terminal",
            symbol: "terminal",
            action: #selector(openTerminal)
        )
        terminalButton.accessibilityIdentifier = "PocketRootHost.terminal"
        configure(
            filesButton,
            title: "Open Files",
            symbol: "folder",
            action: #selector(openFiles)
        )
        filesButton.accessibilityIdentifier = "PocketRootHost.files"

        let stack = UIStackView(
            arrangedSubviews: [
                statusLabel,
                bootButton,
                terminalButton,
                filesButton
            ]
        )
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            )
        ])
    }

    private func configure(
        _ button: UIButton,
        title: String,
        symbol: String,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc
    private func bootRuntime() {
        guard let archiveURL = Bundle.main.url(
            forResource: Self.rootFSName,
            withExtension: "tar.gz"
        ) else {
            presentMessage(
                title: "RootFS Missing",
                message: "Configure the reviewed Debug RootFS before booting."
            )
            return
        }

        do {
            let controller: PocketRootIshRuntimeController
            if let runtimeController {
                controller = runtimeController
            } else {
                controller = PocketRootIshRuntimeController(
                    configuration: PocketRootIshRuntimeControllerConfiguration(
                        archiveURL: archiveURL,
                        applicationSupportURL: try applicationSupportURL(),
                        workDirectory: "/"
                    )
                )
                runtimeOwner.runtimeController = controller
                bind(to: controller, refreshRuntimeState: false)
            }
            Task {
                do {
                    try await controller.boot()
                } catch {
                    presentMessage(
                        title: "Boot Failed",
                        message: error.localizedDescription
                    )
                }
            }
        } catch {
            presentMessage(
                title: "Storage Unavailable",
                message: error.localizedDescription
            )
        }
    }

    @objc
    private func openTerminal() {
        guard let system = runtimeController?.readySystem else {
            return
        }
        let terminal = PocketRootTerminalViewController(
            system: system,
            configuration: .interactive(
                initialWorkingDirectory: "/root",
                cursorBlinkEnabled: !isUITesting
            ),
            theme: .dark
        )
        let controller = runtimeController
        terminal.onSessionEnded = { [weak terminal, weak controller] reason in
            terminal?.title = Self.sessionEndTitle(reason)
            if case .failed = reason {
                Task {
                    await controller?.refreshRuntimeState()
                }
            }
        }
        activeTerminal = terminal
        navigationController?.pushViewController(terminal, animated: true)
    }

    @objc
    private func openFiles() {
        guard let system = runtimeController?.readySystem else {
            return
        }
        let files = PocketRootFileBrowserViewController(
            system: system,
            initialPath: "/root"
        )
        navigationController?.pushViewController(files, animated: true)
    }

    private func render(phase: PocketRootIshRuntimePhase) {
        statusLabel.text = "Runtime: \(Self.phaseDescription(phase))"
        let isReady = phase == .ready
        bootButton.isEnabled = runtimeController?.canBoot ?? true
        terminalButton.isEnabled = isReady
        filesButton.isEnabled = isReady
    }

    private func bind(
        to controller: PocketRootIshRuntimeController,
        refreshRuntimeState: Bool = true
    ) {
        controller.onPhaseChange = { [weak self] phase in
            self?.render(phase: phase)
        }
        render(phase: controller.phase)
        if refreshRuntimeState {
            Task {
                await controller.refreshRuntimeState()
            }
        }
    }

    private func applicationSupportURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = baseURL.appendingPathComponent(
            "PocketRootHostApp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        return url
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-PocketRootUITesting")
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static func phaseDescription(
        _ phase: PocketRootIshRuntimePhase
    ) -> String {
        switch phase {
        case .unavailable: "Unavailable"
        case .idle: "Ready to Boot"
        case .preparingRootFS: "Preparing RootFS"
        case .booting: "Booting"
        case .ready: "Ready"
        case .shuttingDown: "Shutting Down"
        case .terminated: "Restart App"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private static func sessionEndTitle(
        _ reason: PocketRootTerminalSessionEndReason
    ) -> String {
        switch reason {
        case .exited(let code): "Terminal Exited (\(code))"
        case .failed: "Terminal Failed"
        }
    }
}
