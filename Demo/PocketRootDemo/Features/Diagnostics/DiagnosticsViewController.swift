import UIKit

@MainActor
final class DiagnosticsViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Diagnostics"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemGroupedBackground

        configureView()
    }

    private func configureView() {
        let rows = [
            statusRow(name: "Package", status: "Ready", isReady: true),
            statusRow(name: "UIKit Demo", status: "Ready", isReady: true),
            statusRow(name: "RootFS", status: "Pending", isReady: false),
            statusRow(name: "iSH Runtime", status: "Pending", isReady: false),
            statusRow(name: "SwiftTerm", status: "Pending", isReady: false)
        ]

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

    private func statusRow(name: String, status: String, isReady: Bool) -> UIView {
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.adjustsFontForContentSizeCategory = true

        let statusLabel = UILabel()
        statusLabel.text = status
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = isReady ? .systemGreen : .systemOrange
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
        return row
    }
}
