import PocketRoot
import PocketRootIshRuntimeIntegration
import UIKit

@main
@MainActor
final class ExternalConsumerAppDelegate:
    UIResponder,
    UIApplicationDelegate
{
    private static let rootFSName = "pocketroot-fs-v0.3.3"

    private(set) var pocketRootHost: PocketRootIshWorkspaceHost?
    private(set) var configurationError: Error?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        do {
            pocketRootHost = try Self.makePocketRootHost()
        } catch {
            configurationError = error
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = ExternalConsumerSceneDelegate.self
        return configuration
    }

    private static func makePocketRootHost() throws
        -> PocketRootIshWorkspaceHost
    {
        guard let archiveURL = Bundle.main.url(
            forResource: rootFSName,
            withExtension: "tar.gz"
        ) else {
            throw ExternalConsumerConfigurationError.rootFSMissing
        }

        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(
            "PocketRootExternalConsumer",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excludedURL = applicationSupportURL
        try excludedURL.setResourceValues(values)

        return PocketRootIshWorkspaceHost(
            runtimeConfiguration:
                PocketRootIshRuntimeControllerConfiguration(
                    archiveURL: archiveURL,
                    applicationSupportURL: applicationSupportURL,
                    workDirectory: "/"
                ),
            workspaceConfiguration: PocketRootWorkspaceConfiguration(
                terminalConfiguration: .interactive(
                    initialWorkingDirectory: "/root",
                    cursorBlinkEnabled:
                        !ProcessInfo.processInfo.arguments.contains(
                            "-PocketRootUITesting"
                        )
                ),
                initialFilePath: "/root"
            )
        )
    }
}

@MainActor
final class ExternalConsumerSceneDelegate:
    UIResponder,
    UIWindowSceneDelegate
{
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate =
                UIApplication.shared.delegate
                    as? ExternalConsumerAppDelegate
        else {
            return
        }

        let root = ExternalConsumerViewController(
            host: appDelegate.pocketRootHost,
            configurationError: appDelegate.configurationError
        )
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(
            rootViewController: root
        )
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let appDelegate =
            UIApplication.shared.delegate
                as? ExternalConsumerAppDelegate
        {
            appDelegate.pocketRootHost?.closeWorkspaces()
        }
        window = nil
    }
}

@MainActor
final class ExternalConsumerViewController: UIViewController {
    private let host: PocketRootIshWorkspaceHost?
    private let configurationError: Error?
    private let terminalButton = UIButton(type: .system)
    private let filesButton = UIButton(type: .system)
    private let shutdownButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    init(
        host: PocketRootIshWorkspaceHost?,
        configurationError: Error?
    ) {
        self.host = host
        self.configurationError = configurationError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PocketRoot Consumer"
        view.backgroundColor = .systemBackground

        configure(
            terminalButton,
            title: "Open Terminal",
            symbol: "terminal",
            action: #selector(openTerminal),
            identifier: "ExternalConsumer.terminal"
        )
        configure(
            filesButton,
            title: "Open Files",
            symbol: "folder",
            action: #selector(openFiles),
            identifier: "ExternalConsumer.files"
        )
        configure(
            shutdownButton,
            title: "Shut Down Linux",
            symbol: "power",
            action: #selector(shutdownLinux),
            identifier: "ExternalConsumer.shutdown"
        )
        shutdownButton.configuration = .bordered()
        shutdownButton.configuration?.title = "Shut Down Linux"
        shutdownButton.configuration?.image = UIImage(systemName: "power")
        shutdownButton.configuration?.imagePadding = 8

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.accessibilityIdentifier = "ExternalConsumer.status"

        let stack = UIStackView(
            arrangedSubviews: [
                terminalButton,
                filesButton,
                shutdownButton,
                statusLabel
            ]
        )
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerYAnchor
            ),
            stack.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            )
        ])

        if let host {
            host.onPhaseChange = { [weak self] phase in
                self?.render(phase)
            }
            render(host.phase)
        } else {
            renderConfigurationFailure()
        }
    }

    private func configure(
        _ button: UIButton,
        title: String,
        symbol: String,
        action: Selector,
        identifier: String
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
        button.accessibilityIdentifier = identifier
    }

    @objc private func openTerminal() {
        guard let host else {
            return
        }
        navigationController?.pushViewController(
            host.makeTerminalViewController(),
            animated: true
        )
    }

    @objc private func openFiles() {
        guard let host else {
            return
        }
        navigationController?.pushViewController(
            host.makeFilesViewController(),
            animated: true
        )
    }

    @objc private func shutdownLinux() {
        guard let host else {
            return
        }
        terminalButton.isEnabled = false
        filesButton.isEnabled = false
        shutdownButton.isEnabled = false
        Task { @MainActor [weak self] in
            do {
                try await host.shutdown()
                self?.render(host.phase)
            } catch {
                self?.statusLabel.text =
                    "Shutdown Failed: \(error.localizedDescription)"
            }
        }
    }

    private func render(_ phase: PocketRootIshRuntimePhase) {
        statusLabel.text = Self.phaseDescription(phase)
        terminalButton.isEnabled = host?.canOpenWorkspace ?? false
        filesButton.isEnabled = host?.canOpenWorkspace ?? false
        shutdownButton.isEnabled = phase == .ready
    }

    private func renderConfigurationFailure() {
        statusLabel.text =
            "Configuration Failed: "
                + (
                    configurationError?.localizedDescription
                        ?? "Unknown error"
                )
        terminalButton.isEnabled = false
        filesButton.isEnabled = false
        shutdownButton.isEnabled = false
    }

    private static func phaseDescription(
        _ phase: PocketRootIshRuntimePhase
    ) -> String {
        switch phase {
        case .unavailable:
            "Runtime Unavailable"
        case .idle:
            "Ready to Boot"
        case .preparingRootFS:
            "Preparing RootFS"
        case .booting:
            "Booting Linux"
        case .ready:
            "Runtime Ready"
        case .shuttingDown:
            "Shutting Down"
        case .terminated:
            "Runtime Terminated"
        case .failed(let message):
            "Runtime Failed: \(message)"
        }
    }
}

private enum ExternalConsumerConfigurationError: LocalizedError {
    case rootFSMissing

    var errorDescription: String? {
        "The reviewed RootFS is missing from this consumer App."
    }
}
