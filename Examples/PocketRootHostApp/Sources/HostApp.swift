import PocketRoot
import PocketRootIshRuntimeIntegration
import UIKit

@main
@MainActor
final class HostAppDelegate: UIResponder, UIApplicationDelegate {
    private static let uiTestImportFixtureName =
        "pocketroot-system-file-ui-fixture.txt"
    private static let uiTestImportFixtureContents =
        "PocketRoot system file transfer UI fixture\n"

    var workspaceHost: PocketRootIshWorkspaceHost?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("-PocketRootUITesting") {
            prepareSystemFileUITestFixture()
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
        configuration.delegateClass = HostSceneDelegate.self
        return configuration
    }

    private func prepareSystemFileUITestFixture() {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            assertionFailure("The UI test Documents directory is unavailable.")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: documentsURL,
                withIntermediateDirectories: true
            )
            try Data(Self.uiTestImportFixtureContents.utf8).write(
                to: documentsURL.appendingPathComponent(
                    Self.uiTestImportFixtureName,
                    isDirectory: false
                ),
                options: .atomic
            )
        } catch {
            assertionFailure(
                "Unable to prepare the system file UI test fixture: \(error)"
            )
        }
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
            hostViewController.closeActiveInteractiveSurfaces()
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
    private let workspaceButton = UIButton(type: .system)
    private let integratedWorkspaceButton = UIButton(type: .system)
    private let shutdownButton = UIButton(type: .system)

    private unowned let runtimeOwner: HostAppDelegate
    private var activeTerminal: PocketRootTerminalViewController?
    private var activeWorkspace: PocketRootWorkspaceViewController?
    private var isClosingTerminal = false
    private var isClosingWorkspace = false
    private var isShutdownRequested = false

    private var workspaceHost: PocketRootIshWorkspaceHost? {
        runtimeOwner.workspaceHost
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
        if let workspaceHost {
            bind(to: workspaceHost)
        } else {
            render(phase: .idle)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let activeTerminal,
           navigationController?.topViewController !== activeTerminal
        {
            closeActiveTerminal()
        }
        if let activeWorkspace,
           navigationController?.topViewController !== activeWorkspace
        {
            closeActiveWorkspace()
        }
        if let workspaceHost {
            Task {
                await workspaceHost.refreshRuntimeState()
            }
        }
    }

    func closeActiveTerminal(completion: (() -> Void)? = nil) {
        guard let terminal = activeTerminal else {
            completion?()
            return
        }
        activeTerminal = nil
        isClosingTerminal = true
        terminalButton.accessibilityValue = "Session Closing"
        render(phase: workspaceHost?.phase ?? .idle)
        terminal.closeSession { [weak self] in
            if let self {
                isClosingTerminal = false
                terminalButton.accessibilityValue = "Session Closed"
                render(phase: workspaceHost?.phase ?? .idle)
            }
            completion?()
        }
    }

    func closeActiveWorkspace(completion: (() -> Void)? = nil) {
        guard let workspace = activeWorkspace else {
            completion?()
            return
        }
        activeWorkspace = nil
        isClosingWorkspace = true
        workspaceButton.accessibilityValue = "Session Closing"
        render(phase: workspaceHost?.phase ?? .idle)
        workspace.closeSession { [weak self] in
            if let self {
                isClosingWorkspace = false
                workspaceButton.accessibilityValue = "Session Closed"
                render(phase: workspaceHost?.phase ?? .idle)
            }
            completion?()
        }
    }

    func closeActiveInteractiveSurfaces(
        completion: (() -> Void)? = nil
    ) {
        closeActiveTerminal { [weak self] in
            guard let self else {
                completion?()
                return
            }
            closeActiveWorkspace { [weak self] in
                guard let self else {
                    completion?()
                    return
                }
                guard let workspaceHost = self.workspaceHost else {
                    completion?()
                    return
                }
                workspaceHost.closeWorkspaces(completion: completion)
            }
        }
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
        configure(
            workspaceButton,
            title: "Open Workspace",
            symbol: "rectangle.split.2x1",
            action: #selector(openWorkspace)
        )
        workspaceButton.accessibilityIdentifier = "PocketRootHost.workspace"
        configure(
            integratedWorkspaceButton,
            title: "Open Integrated Workspace",
            symbol: "shippingbox.and.arrow.backward",
            action: #selector(openIntegratedWorkspace)
        )
        integratedWorkspaceButton.accessibilityIdentifier =
            "PocketRootHost.integratedWorkspace"
        configure(
            shutdownButton,
            title: "Shutdown Runtime",
            symbol: "power.circle",
            action: #selector(shutdownRuntime)
        )
        shutdownButton.accessibilityIdentifier = "PocketRootHost.shutdown"

        let stack = UIStackView(
            arrangedSubviews: [
                statusLabel,
                bootButton,
                terminalButton,
                filesButton,
                workspaceButton,
                integratedWorkspaceButton,
                shutdownButton
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
        guard let workspaceHost = resolveWorkspaceHost() else {
            return
        }

        Task {
            do {
                try await workspaceHost.boot()
            } catch {
                presentMessage(
                    title: "Boot Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    @objc
    private func openTerminal() {
        guard !isClosingTerminal,
              let system = workspaceHost?.readySystem
        else {
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
        let host = workspaceHost
        terminal.onSessionEnded = { [weak terminal, weak host] reason in
            terminal?.title = Self.sessionEndTitle(reason)
            if case .failed = reason {
                Task {
                    await host?.refreshRuntimeState()
                }
            }
        }
        activeTerminal = terminal
        terminalButton.accessibilityValue = "Session Open"
        navigationController?.pushViewController(terminal, animated: true)
    }

    @objc
    private func openFiles() {
        guard let system = workspaceHost?.readySystem else {
            return
        }
        let files = PocketRootFileBrowserViewController(
            system: system,
            initialPath: "/root"
        )
        navigationController?.pushViewController(files, animated: true)
    }

    @objc
    private func openWorkspace() {
        guard !isClosingWorkspace,
              let system = workspaceHost?.readySystem
        else {
            return
        }
        let workspace = PocketRootWorkspaceViewController(
            system: system,
            configuration: PocketRootWorkspaceConfiguration(
                terminalConfiguration: .interactive(
                    initialWorkingDirectory: "/root",
                    cursorBlinkEnabled: !isUITesting
                )
            )
        )
        let host = workspaceHost
        workspace.onTerminalSessionEnded = {
            [weak workspace, weak host] reason in
            workspace?.title = Self.sessionEndTitle(reason)
            if case .failed = reason {
                Task {
                    await host?.refreshRuntimeState()
                }
            }
        }
        activeWorkspace = workspace
        workspaceButton.accessibilityValue = "Session Open"
        navigationController?.pushViewController(workspace, animated: true)
    }

    @objc
    private func openIntegratedWorkspace() {
        guard let workspaceHost = resolveWorkspaceHost() else {
            return
        }
        navigationController?.pushViewController(
            workspaceHost.makeViewController(),
            animated: true
        )
    }

    @objc
    private func shutdownRuntime() {
        guard !isClosingTerminal,
              !isClosingWorkspace,
              !isShutdownRequested,
              let workspaceHost
        else {
            return
        }
        isShutdownRequested = true
        render(phase: workspaceHost.phase)
        closeActiveInteractiveSurfaces { [weak self] in
            Task {
                do {
                    try await workspaceHost.shutdown()
                } catch {
                    self?.isShutdownRequested = false
                    self?.render(phase: workspaceHost.phase)
                    self?.presentMessage(
                        title: "Shutdown Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func render(phase: PocketRootIshRuntimePhase) {
        statusLabel.text = "Runtime: \(Self.phaseDescription(phase))"
        let isReady = phase == .ready
        bootButton.isEnabled = workspaceHost?.canBoot ?? true
        terminalButton.isEnabled = isReady && !isClosingTerminal
        filesButton.isEnabled = isReady
        workspaceButton.isEnabled = isReady && !isClosingWorkspace
        integratedWorkspaceButton.isEnabled =
            workspaceHost?.canOpenWorkspace
                ?? (phase != .unavailable
                    && phase != .shuttingDown
                    && phase != .terminated)
        shutdownButton.isEnabled =
            isReady
                && !isClosingTerminal
                && !isClosingWorkspace
                && !isShutdownRequested
    }

    private func bind(
        to workspaceHost: PocketRootIshWorkspaceHost,
        refreshRuntimeState: Bool = true
    ) {
        workspaceHost.onPhaseChange = { [weak self] phase in
            self?.render(phase: phase)
        }
        render(phase: workspaceHost.phase)
        if refreshRuntimeState {
            Task {
                await workspaceHost.refreshRuntimeState()
            }
        }
    }

    private func resolveWorkspaceHost() -> PocketRootIshWorkspaceHost? {
        if let workspaceHost {
            return workspaceHost
        }
        guard let archiveURL = Bundle.main.url(
            forResource: Self.rootFSName,
            withExtension: "tar.gz"
        ) else {
            presentMessage(
                title: "RootFS Missing",
                message: "Configure the reviewed Debug RootFS before booting."
            )
            return nil
        }
        do {
            let host = PocketRootIshWorkspaceHost(
                runtimeConfiguration:
                    PocketRootIshRuntimeControllerConfiguration(
                        archiveURL: archiveURL,
                        applicationSupportURL: try applicationSupportURL(),
                        workDirectory: "/"
                    ),
                workspaceConfiguration: PocketRootWorkspaceConfiguration(
                    terminalConfiguration: .interactive(
                        initialWorkingDirectory: "/root",
                        cursorBlinkEnabled: !isUITesting
                    )
                )
            )
            runtimeOwner.workspaceHost = host
            bind(to: host, refreshRuntimeState: false)
            return host
        } catch {
            presentMessage(
                title: "Storage Unavailable",
                message: error.localizedDescription
            )
            return nil
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
