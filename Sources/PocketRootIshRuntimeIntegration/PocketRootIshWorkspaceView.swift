#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI entry point for a process-retained ``PocketRootIshWorkspaceHost``.
///
/// Keep the host in application or scene state; recreating it from `body`
/// would lose lifecycle ownership of the process-global runtime.
@available(iOS 18.0, *)
public struct PocketRootIshWorkspaceView: UIViewControllerRepresentable {
    public typealias UIViewControllerType =
        PocketRootIshWorkspaceViewController

    private let host: PocketRootIshWorkspaceHost

    public init(host: PocketRootIshWorkspaceHost) {
        self.host = host
    }

    public func makeUIViewController(
        context _: Context
    ) -> PocketRootIshWorkspaceViewController {
        host.makeViewController()
    }

    public func updateUIViewController(
        _: PocketRootIshWorkspaceViewController,
        context _: Context
    ) {}

    public static func dismantleUIViewController(
        _ viewController: PocketRootIshWorkspaceViewController,
        coordinator _: Void
    ) {
        viewController.detach()
    }
}
#endif
