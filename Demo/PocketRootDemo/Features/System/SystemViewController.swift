import PocketRoot
import UIKit

@MainActor
final class SystemViewController: UIViewController {

    private let runtimeValueLabel = UILabel()
    private let rootFSValueLabel = UILabel()
    private let architectureValueLabel = UILabel()
    private let bootButton = UIButton(type: .system)
    private let healthCheckButton = UIButton(type: .system)
    private let shutdownButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "System"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemGroupedBackground

        configureView()
        refreshRuntimeState()
    }

    private func configureView() {
        let titleLabel = UILabel()
        titleLabel.text = "PocketRoot"
        titleLabel.font = .preferredFont(forTextStyle: .title1)
        titleLabel.adjustsFontForContentSizeCategory = true

        let statusStack = UIStackView(arrangedSubviews: [
            makeStatusRow(title: "Runtime", valueLabel: runtimeValueLabel),
            makeStatusRow(title: "RootFS", valueLabel: rootFSValueLabel),
            makeStatusRow(title: "Guest Architecture", valueLabel: architectureValueLabel)
        ])
        statusStack.axis = .vertical
        statusStack.spacing = DemoConstants.itemSpacing

        configureButton(
            bootButton,
            title: "Boot Runtime",
            symbolName: "power",
            action: #selector(bootRuntime)
        )
        configureButton(
            healthCheckButton,
            title: "Health Check",
            symbolName: "heart.text.square",
            action: #selector(runHealthCheck)
        )
        configureButton(
            shutdownButton,
            title: "Shutdown",
            symbolName: "stop.circle",
            action: #selector(shutdownRuntime)
        )
        shutdownButton.tintColor = .systemRed

        let buttonStack = UIStackView(arrangedSubviews: [
            bootButton,
            healthCheckButton,
            shutdownButton
        ])
        buttonStack.axis = .vertical
        buttonStack.spacing = DemoConstants.itemSpacing

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel,
            statusStack,
            buttonStack
        ])
        contentStack.axis = .vertical
        contentStack.spacing = DemoConstants.sectionSpacing
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = DemoConstants.contentInsets
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func makeStatusRow(title: String, valueLabel: UILabel) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = DemoConstants.itemSpacing
        return row
    }

    private func configureButton(
        _ button: UIButton,
        title: String,
        symbolName: String,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbolName)
        configuration.imagePadding = 8
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc
    private func bootRuntime() {
        setButtonsEnabled(false)
        Task { [weak self] in
            do {
                try await PocketRootSystem.shared.boot()
            } catch {
                self?.presentError(error)
            }
            self?.setButtonsEnabled(true)
            self?.refreshRuntimeState()
        }
    }

    @objc
    private func runHealthCheck() {
        Task { [weak self] in
            let state = await PocketRootSystem.shared.state
            self?.refreshRuntimeState(state)

            let alert = UIAlertController(
                title: "Runtime Health",
                message: "Current state: \(Self.description(for: state))",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }

    @objc
    private func shutdownRuntime() {
        setButtonsEnabled(false)
        Task { [weak self] in
            do {
                try await PocketRootSystem.shared.shutdown()
            } catch {
                self?.presentError(error)
            }
            self?.setButtonsEnabled(true)
            self?.refreshRuntimeState()
        }
    }

    private func refreshRuntimeState() {
        Task { [weak self] in
            let state = await PocketRootSystem.shared.state
            self?.refreshRuntimeState(state)
        }
    }

    private func refreshRuntimeState(_ state: PocketRootRuntimeState) {
        runtimeValueLabel.text = Self.description(for: state)
        rootFSValueLabel.text = "Not Installed"
        architectureValueLabel.text = "Unknown"
    }

    private func setButtonsEnabled(_ isEnabled: Bool) {
        bootButton.isEnabled = isEnabled
        healthCheckButton.isEnabled = isEnabled
        shutdownButton.isEnabled = isEnabled
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "PocketRoot",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static func description(for state: PocketRootRuntimeState) -> String {
        switch state {
        case .idle:
            "Not Installed"
        case .preparingRootFS:
            "Preparing RootFS"
        case .booting:
            "Booting"
        case .ready:
            "Ready"
        case .shuttingDown:
            "Shutting Down"
        case .failed(let message):
            "Failed: \(message)"
        }
    }
}
