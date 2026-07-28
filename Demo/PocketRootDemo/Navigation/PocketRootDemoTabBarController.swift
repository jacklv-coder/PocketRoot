import UIKit

@MainActor
final class PocketRootDemoTabBarController: UITabBarController {
    private let runtimeStore: DemoRuntimeStore

    init(runtimeStore: DemoRuntimeStore = .shared) {
        self.runtimeStore = runtimeStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        viewControllers = [
            navigationController(
                root: SystemViewController(runtimeStore: runtimeStore),
                title: "System",
                symbolName: "cpu"
            ),
            navigationController(
                root: TerminalDemoViewController(runtimeStore: runtimeStore),
                title: "Terminal",
                symbolName: "terminal"
            ),
            navigationController(
                root: CommandsViewController(runtimeStore: runtimeStore),
                title: "Commands",
                symbolName: "chevron.left.forwardslash.chevron.right"
            ),
            navigationController(
                root: DiagnosticsViewController(runtimeStore: runtimeStore),
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
