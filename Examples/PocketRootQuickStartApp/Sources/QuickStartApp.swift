import PocketRoot
import PocketRootIshRuntimeIntegration
import UIKit

@main
@MainActor
final class QuickStartAppDelegate: UIResponder, UIApplicationDelegate {
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
        configuration.delegateClass = QuickStartSceneDelegate.self
        return configuration
    }

    private static func makePocketRootHost() throws
        -> PocketRootIshWorkspaceHost
    {
        guard let archiveURL = Bundle.main.url(
            forResource: rootFSName,
            withExtension: "tar.gz"
        ) else {
            throw QuickStartConfigurationError.rootFSMissing
        }

        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PocketRoot", isDirectory: true)
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
                )
        )
    }
}

@MainActor
final class QuickStartSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate =
                UIApplication.shared.delegate as? QuickStartAppDelegate
        else {
            return
        }

        let root = QuickStartViewController(
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
}

@MainActor
final class QuickStartViewController: UIViewController {
    private let host: PocketRootIshWorkspaceHost?
    private let configurationError: Error?

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
        title = "PocketRoot"
        view.backgroundColor = .systemBackground

        let terminalButton = makeButton(
            title: "Open Terminal",
            symbol: "terminal",
            action: #selector(openTerminal)
        )
        terminalButton.accessibilityIdentifier =
            "PocketRootQuickStart.terminal"
        let filesButton = makeButton(
            title: "Open Files",
            symbol: "folder",
            action: #selector(openFiles)
        )
        filesButton.accessibilityIdentifier = "PocketRootQuickStart.files"

        let statusLabel = UILabel()
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = configurationError?.localizedDescription
            ?? "Each screen prepares and boots the local Linux runtime when opened."

        let stack = UIStackView(
            arrangedSubviews: [
                terminalButton,
                filesButton,
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

        terminalButton.isEnabled = host != nil
        filesButton.isEnabled = host != nil
    }

    private func makeButton(
        title: String,
        symbol: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
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
}

private enum QuickStartConfigurationError: LocalizedError {
    case rootFSMissing

    var errorDescription: String? {
        "The reviewed RootFS is missing from this App build."
    }
}
