#if canImport(SwiftUI) && canImport(UIKit)
import PocketRootCore
import SwiftUI

/// A SwiftUI wrapper around ``PocketRootTerminalViewController``.
@available(iOS 18.0, *)
public struct PocketRootTerminalView: UIViewControllerRepresentable {
    public typealias UIViewControllerType = UIViewController

    private enum Backend {
        case interactive(PocketRootSystem, PocketRootSessionConfiguration)
        case command(any PocketRootTerminalCommandExecutor)
    }

    private let backend: Backend
    private let configuration: PocketRootTerminalConfiguration
    private let theme: PocketRootTerminalTheme
    private let onSessionEnded:
        ((PocketRootTerminalSessionEndReason) -> Void)?

    fileprivate struct HostSignature: Equatable {
        enum BackendSignature: Equatable {
            case interactive(
                ObjectIdentifier,
                PocketRootSessionConfiguration
            )
            case command(ObjectIdentifier)
        }

        let backend: BackendSignature
        let configuration: PocketRootTerminalConfiguration
    }

    /// Creates a persistent PTY terminal rendered by SwiftTerm. When
    /// `sessionConfiguration` is `nil`, `configuration.initialWorkingDirectory`
    /// supplies the PTY working directory.
    public init(
        system: PocketRootSystem,
        sessionConfiguration: PocketRootSessionConfiguration? = nil,
        configuration: PocketRootTerminalConfiguration = .interactive(),
        theme: PocketRootTerminalTheme = .dark,
        onSessionEnded:
            ((PocketRootTerminalSessionEndReason) -> Void)? = nil
    ) {
        backend = .interactive(
            system,
            configuration.resolvingInteractiveSessionConfiguration(
                sessionConfiguration
            )
        )
        self.configuration = configuration
        self.theme = theme
        self.onSessionEnded = onSessionEnded
    }

    /// Creates the bounded one-shot command fallback.
    public init(
        commandExecutor: any PocketRootTerminalCommandExecutor,
        configuration: PocketRootTerminalConfiguration = .commandLine(),
        theme: PocketRootTerminalTheme = .dark,
        onSessionEnded:
            ((PocketRootTerminalSessionEndReason) -> Void)? = nil
    ) {
        backend = .command(commandExecutor)
        self.configuration = configuration
        self.theme = theme
        self.onSessionEnded = onSessionEnded
    }

    public func makeUIViewController(
        context _: Context
    ) -> UIViewController {
        PocketRootTerminalHostingController(
            signature: hostSignature,
            terminalController: makeTerminalViewController(),
            onSessionEnded: onSessionEnded
        )
    }

    public func updateUIViewController(
        _ viewController: UIViewController,
        context _: Context
    ) {
        guard let viewController =
            viewController as? PocketRootTerminalHostingController
        else {
            return
        }
        let signature = hostSignature
        if viewController.signature == signature {
            viewController.apply(
                theme: theme,
                onSessionEnded: onSessionEnded
            )
        } else {
            viewController.replace(
                signature: signature,
                terminalController: makeTerminalViewController(),
                onSessionEnded: onSessionEnded
            )
        }
    }

    public static func dismantleUIViewController(
        _ viewController: UIViewController,
        coordinator _: Void
    ) {
        (viewController as? PocketRootTerminalHostingController)?
            .closeSession()
    }

    private var hostSignature: HostSignature {
        switch backend {
        case .interactive(let system, let sessionConfiguration):
            return HostSignature(
                backend: .interactive(
                    ObjectIdentifier(system),
                    sessionConfiguration
                ),
                configuration: configuration
            )
        case .command(let executor):
            return HostSignature(
                backend: .command(ObjectIdentifier(executor)),
                configuration: configuration
            )
        }
    }

    private func makeTerminalViewController() -> PocketRootTerminalViewController {
        switch backend {
        case .interactive(let system, let sessionConfiguration):
            return PocketRootTerminalViewController(
                system: system,
                sessionConfiguration: sessionConfiguration,
                configuration: configuration,
                theme: theme
            )
        case .command(let executor):
            return PocketRootTerminalViewController(
                commandExecutor: executor,
                configuration: configuration,
                theme: theme
            )
        }
    }
}

@available(iOS 18.0, *)
@MainActor
private final class PocketRootTerminalHostingController: UIViewController {
    fileprivate private(set) var signature:
        PocketRootTerminalView.HostSignature
    private var terminalController: PocketRootTerminalViewController

    init(
        signature: PocketRootTerminalView.HostSignature,
        terminalController: PocketRootTerminalViewController,
        onSessionEnded:
            ((PocketRootTerminalSessionEndReason) -> Void)?
    ) {
        self.signature = signature
        self.terminalController = terminalController
        super.init(nibName: nil, bundle: nil)
        terminalController.onSessionEnded = onSessionEnded
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        install(terminalController)
    }

    fileprivate func apply(
        theme: PocketRootTerminalTheme,
        onSessionEnded:
            ((PocketRootTerminalSessionEndReason) -> Void)?
    ) {
        terminalController.onSessionEnded = onSessionEnded
        terminalController.apply(theme: theme)
    }

    fileprivate func replace(
        signature: PocketRootTerminalView.HostSignature,
        terminalController: PocketRootTerminalViewController,
        onSessionEnded:
            ((PocketRootTerminalSessionEndReason) -> Void)?
    ) {
        let previous = self.terminalController
        previous.closeSession()
        if isViewLoaded {
            previous.willMove(toParent: nil)
            previous.view.removeFromSuperview()
            previous.removeFromParent()
        }
        self.signature = signature
        self.terminalController = terminalController
        terminalController.onSessionEnded = onSessionEnded
        if isViewLoaded {
            install(terminalController)
        }
    }

    fileprivate func closeSession() {
        terminalController.closeSession()
    }

    private func install(_ controller: PocketRootTerminalViewController) {
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
    }
}
#endif
