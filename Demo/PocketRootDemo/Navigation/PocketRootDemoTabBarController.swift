import UIKit

@MainActor
final class PocketRootDemoTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        viewControllers = [
            navigationController(
                root: SystemViewController(),
                title: "System",
                symbolName: "cpu"
            ),
            navigationController(
                root: TerminalDemoViewController(),
                title: "Terminal",
                symbolName: "terminal"
            ),
            navigationController(
                root: CommandsViewController(),
                title: "Commands",
                symbolName: "chevron.left.forwardslash.chevron.right"
            ),
            navigationController(
                root: DiagnosticsViewController(),
                title: "Diagnostics",
                symbolName: "stethoscope"
            )
        ]
    }

    private func navigationController(
        root: UIViewController,
        title: String,
        symbolName: String
    ) -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: root)
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: symbolName),
            selectedImage: nil
        )
        return navigationController
    }
}
