import UIKit

@MainActor
final class DiagnosticsViewController: UIViewController, DemoRuntimeStoreObserver {
    private struct StatusLabels {
        let value: UILabel
        let row: UIView
    }

    private let runtimeStore: DemoRuntimeStore
    private var statusLabels: [String: StatusLabels] = [:]
    private var isObserving = false

    init(runtimeStore: DemoRuntimeStore) {
        self.runtimeStore = runtimeStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Diagnostics"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemGroupedBackground
        configureView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !isObserving else {
            return
        }
        isObserving = true
        runtimeStore.addObserver(self)
        Task {
            await runtimeStore.refreshRuntimeState()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        runtimeStore.removeObserver(self)
        isObserving = false
    }

    func demoRuntimeStoreDidChange(_ store: DemoRuntimeStore) {
        update(name: "Package", status: .init(text: "Ready", isReady: true))
        update(name: "UIKit Demo", status: .init(text: "Ready", isReady: true))
        update(name: "RootFS", status: store.rootFSStatus)
        update(name: "iSH Runtime", status: store.runtimeStatus)
        update(name: "SwiftTerm", status: .init(text: "Linked", isReady: true))
    }

    private func configureView() {
        let names = ["Package", "UIKit Demo", "RootFS", "iSH Runtime", "SwiftTerm"]
        let rows = names.map(makeStatusRow)

        let stackView = UIStackView(arrangedSubviews: rows)
        stackView.axis = .vertical
        stackView.spacing = 1
        stackView.layer.cornerRadius = 12
        stackView.clipsToBounds = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: DemoConstants.contentInsets.top
            ),
            stackView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: DemoConstants.contentInsets.leading
            ),
            stackView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -DemoConstants.contentInsets.trailing
            )
        ])
    }

    private func makeStatusRow(name: String) -> UIView {
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.adjustsFontForContentSizeCategory = true

        let statusLabel = UILabel()
        statusLabel.text = "Checking"
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [nameLabel, statusLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.spacing = DemoConstants.itemSpacing
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 14,
            leading: 16,
            bottom: 14,
            trailing: 16
        )
        row.backgroundColor = .secondarySystemGroupedBackground
        statusLabels[name] = StatusLabels(value: statusLabel, row: row)
        return row
    }

    private func update(name: String, status: DemoDiagnosticStatus) {
        guard let labels = statusLabels[name] else {
            return
        }
        labels.value.text = status.text
        labels.value.textColor = status.isReady ? .systemGreen : .systemOrange
        labels.row.accessibilityValue = status.text
    }
}
