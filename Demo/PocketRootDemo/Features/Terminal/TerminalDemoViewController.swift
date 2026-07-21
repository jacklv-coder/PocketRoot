import UIKit

@MainActor
final class TerminalDemoViewController: PlaceholderViewController {

    init() {
        super.init(
            title: "Terminal",
            message: "Terminal integration pending",
            symbolName: "terminal"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }
}
