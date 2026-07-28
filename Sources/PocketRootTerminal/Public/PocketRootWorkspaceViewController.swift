#if canImport(SwiftUI) && canImport(SwiftTerm) && canImport(UIKit)
import PocketRootCore
import SwiftUI
import SwiftTerm
import UIKit

/// A ready-to-embed UIKit workspace with persistent Terminal and Files tabs.
///
/// The terminal session remains alive while the user switches to Files. It is
/// closed when the workspace is permanently removed from its navigation or
/// presentation hierarchy, or when the host calls ``closeSession(completion:)``.
@available(iOS 18.0, *)
@MainActor
public final class PocketRootWorkspaceViewController:
    UITabBarController,
    UITabBarControllerDelegate
{
    public let configuration: PocketRootWorkspaceConfiguration

    /// Called when the guest shell exits or the PTY connection fails.
    public var onTerminalSessionEnded:
        ((PocketRootTerminalSessionEndReason) -> Void)?

    private let terminalController: PocketRootTerminalViewController
    private let filesController: PocketRootFileBrowserViewController
    private let surfaceControl = UISegmentedControl(
        items: ["Terminal", "Files"]
    )
    private var wasAttachedToParent = false
    private var didRequestAutomaticClose = false

    public init(
        system: PocketRootSystem,
        configuration: PocketRootWorkspaceConfiguration = .init()
    ) {
        self.configuration = configuration
        terminalController = PocketRootTerminalViewController(
            system: system,
            sessionConfiguration:
                configuration.terminalSessionConfiguration,
            configuration: configuration.terminalConfiguration,
            theme: configuration.terminalTheme
        )
        filesController = PocketRootFileBrowserViewController(
            system: system,
            initialPath: configuration.initialFilePath
        )
        super.init(nibName: nil, bundle: nil)

        terminalController.tabBarItem = UITabBarItem(
            title: "Terminal",
            image: UIImage(systemName: "terminal"),
            selectedImage: UIImage(systemName: "terminal.fill")
        )
        terminalController.tabBarItem.accessibilityIdentifier =
            "PocketRootWorkspace.terminal"
        filesController.tabBarItem = UITabBarItem(
            title: "Files",
            image: UIImage(systemName: "folder"),
            selectedImage: UIImage(systemName: "folder.fill")
        )
        filesController.tabBarItem.accessibilityIdentifier =
            "PocketRootWorkspace.files"
        viewControllers = [terminalController, filesController]
        selectedIndex = configuration.initialSurface.rawValue
        delegate = self

        terminalController.onSessionEnded = { [weak self] reason in
            self?.onTerminalSessionEnded?(reason)
        }
    }

    @MainActor @preconcurrency required dynamic init?(coder _: NSCoder) {
        nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "PocketRoot"
        view.accessibilityIdentifier = "PocketRootWorkspace"
        surfaceControl.selectedSegmentIndex = selectedIndex
        surfaceControl.accessibilityIdentifier =
            "PocketRootWorkspace.surface"
        surfaceControl.addTarget(
            self,
            action: #selector(surfaceSelectionChanged),
            for: .valueChanged
        )
        navigationItem.titleView = surfaceControl
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent
                || isBeingDismissed
                || navigationController?.isBeingDismissed == true
        else {
            return
        }
        requestAutomaticClose()
    }

    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil {
            wasAttachedToParent = true
        } else if wasAttachedToParent {
            requestAutomaticClose()
        }
    }

    /// Selects Terminal or Files without recreating either child controller.
    public func select(_ surface: PocketRootWorkspaceSurface) {
        guard !didRequestAutomaticClose || surface == .files else {
            return
        }
        if didRequestAutomaticClose {
            selectedIndex = 0
        } else {
            selectedIndex = surface.rawValue
        }
        surfaceControl.selectedSegmentIndex = surface.rawValue
    }

    public func tabBarController(
        _: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        surfaceControl.selectedSegmentIndex =
            viewController === terminalController
                ? PocketRootWorkspaceSurface.terminal.rawValue
                : PocketRootWorkspaceSurface.files.rawValue
    }

    /// Closes the workspace's terminal session.
    ///
    /// Hosts should await the completion before shutting down the shared
    /// runtime. Repeated calls join the same bounded close operation.
    public func closeSession(
        completion: (@MainActor () -> Void)? = nil
    ) {
        if !didRequestAutomaticClose {
            retireTerminalSurface()
        }
        didRequestAutomaticClose = true
        terminalController.closeSession(completion: completion)
    }

    private func requestAutomaticClose() {
        guard !didRequestAutomaticClose else {
            return
        }
        closeSession()
    }

    private func retireTerminalSurface() {
        surfaceControl.setEnabled(
            false,
            forSegmentAt: PocketRootWorkspaceSurface.terminal.rawValue
        )
        surfaceControl.selectedSegmentIndex =
            PocketRootWorkspaceSurface.files.rawValue
        viewControllers = [filesController]
        selectedIndex = 0
    }

    @objc private func surfaceSelectionChanged() {
        guard let surface = PocketRootWorkspaceSurface(
            rawValue: surfaceControl.selectedSegmentIndex
        ) else {
            return
        }
        select(surface)
    }
}
#endif
