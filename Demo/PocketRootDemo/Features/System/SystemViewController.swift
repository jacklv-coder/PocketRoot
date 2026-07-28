import UIKit

@MainActor
final class SystemViewController: UIViewController, DemoRuntimeStoreObserver {
    private let runtimeStore: DemoRuntimeStore
    private let runtimeValueLabel = UILabel()
    private let rootFSValueLabel = UILabel()
    private let architectureValueLabel = UILabel()
    private let bootButton = UIButton(type: .system)
    private let healthCheckButton = UIButton(type: .system)
    private let shutdownButton = UIButton(type: .system)
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
        title = "System"
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
        runtimeValueLabel.text = store.phase.displayName
        rootFSValueLabel.text = store.rootFSStatus.text
        architectureValueLabel.text = store.phase == .ready ? "aarch64" : "—"

        bootButton.isEnabled = store.canBoot
        healthCheckButton.isEnabled = store.readySystem != nil
        shutdownButton.isEnabled = store.canShutdown

        switch store.phase {
        case .rootFSMissing:
            bootButton.configuration?.title = "RootFS Not Embedded"
        case .preparingRootFS:
            bootButton.configuration?.title = "Preparing RootFS…"
        case .booting:
            bootButton.configuration?.title = "Booting…"
        case .ready:
            bootButton.configuration?.title = "Runtime Ready"
        case .runtimeUnavailable:
            bootButton.configuration?.title = "Runtime Unavailable"
        case .terminated:
            bootButton.configuration?.title = "Restart App to Boot Again"
        case .failed:
            bootButton.configuration?.title = store.canBoot
                ? "Retry Prepare and Boot"
                : "Boot Failed"
        case .idle, .shuttingDown:
            bootButton.configuration?.title = "Prepare and Boot Runtime"
        }
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
            title: "Prepare and Boot Runtime",
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
            action: #selector(confirmShutdown)
        )
        shutdownButton.tintColor = .systemRed

        let buttonStack = UIStackView(arrangedSubviews: [
            bootButton,
            healthCheckButton,
            shutdownButton
        ])
        buttonStack.axis = .vertical
        buttonStack.spacing = DemoConstants.itemSpacing

        let noteLabel = UILabel()
        noteLabel.text = [
            "The reviewed RootFS is installed on first boot.",
            "After Shutdown, restart the App before booting again."
        ].joined(separator: "\n")
        noteLabel.font = .preferredFont(forTextStyle: .footnote)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel,
            statusStack,
            buttonStack,
            noteLabel
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
        Task {
            await runtimeStore.boot()
        }
    }

    @objc
    private func runHealthCheck() {
        Task { [weak self] in
            guard let self else {
                return
            }
            await runtimeStore.refreshRuntimeState()
            let alert = UIAlertController(
                title: "Runtime Health",
                message: "Current state: \(runtimeStore.phase.displayName)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    @objc
    private func confirmShutdown() {
        let alert = UIAlertController(
            title: "Shutdown Runtime?",
            message: "The embedded runtime cannot boot again until this App process restarts.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Shutdown", style: .destructive) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          let failure = await runtimeStore.shutdown()
                    else {
                        return
                    }
                    presentShutdownFailure(failure)
                }
            }
        )
        present(alert, animated: true)
    }

    private func presentShutdownFailure(_ failure: String) {
        let alert = UIAlertController(
            title: "Shutdown Not Completed",
            message: [
                failure,
                "",
                "Finish the active command or terminal session, then try again."
            ].joined(separator: "\n"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
