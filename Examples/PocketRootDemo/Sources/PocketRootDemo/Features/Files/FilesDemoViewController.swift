import PocketRoot
import UIKit

@MainActor
final class FilesDemoViewController: UIViewController, DemoRuntimeStoreObserver {
    private let runtimeStore: DemoRuntimeStore
    private let statusLabel = UILabel()
    private let bootButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let placeholderStack = UIStackView()
    private var filesController: PocketRootFileBrowserViewController?
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
        title = "Files"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground
        configurePlaceholder()
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
        guard let system = store.readySystem else {
            removeFiles()
            renderPlaceholder(for: store)
            return
        }
        installFilesIfNeeded(system: system)
    }

    private func configurePlaceholder() {
        let imageView = UIImageView(image: UIImage(systemName: "folder"))
        imageView.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 48)
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Prepare and Boot Runtime"
        configuration.image = UIImage(systemName: "power")
        configuration.imagePadding = 8
        bootButton.configuration = configuration
        bootButton.addTarget(
            self,
            action: #selector(bootRuntime),
            for: .touchUpInside
        )

        placeholderStack.addArrangedSubview(imageView)
        placeholderStack.addArrangedSubview(activityIndicator)
        placeholderStack.addArrangedSubview(statusLabel)
        placeholderStack.addArrangedSubview(bootButton)
        placeholderStack.axis = .vertical
        placeholderStack.alignment = .center
        placeholderStack.spacing = 18
        placeholderStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderStack)

        NSLayoutConstraint.activate([
            placeholderStack.centerYAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerYAnchor
            ),
            placeholderStack.centerXAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerXAnchor
            ),
            placeholderStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor
            ),
            placeholderStack.trailingAnchor.constraint(
                lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor
            ),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

    private func renderPlaceholder(for store: DemoRuntimeStore) {
        placeholderStack.isHidden = false
        activityIndicator.stopAnimating()
        bootButton.isHidden = true
        bootButton.isEnabled = false
        bootButton.configuration?.title = "Prepare and Boot Runtime"

        switch store.phase {
        case .rootFSMissing:
            statusLabel.text = [
                "RootFS is not embedded in this Debug build.",
                "Rebuild with POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE set to the reviewed archive."
            ].joined(separator: "\n")
        case .runtimeUnavailable:
            statusLabel.text = "The arm64 iSH runtime is unavailable in this build."
        case .idle:
            statusLabel.text =
                "The embedded RootFS is ready. Boot the runtime to browse Linux files."
            bootButton.isHidden = false
            bootButton.isEnabled = true
        case .preparingRootFS:
            statusLabel.text = "Verifying and installing RootFS…"
            activityIndicator.startAnimating()
        case .booting:
            statusLabel.text = "Booting Alpine Linux…"
            activityIndicator.startAnimating()
        case .ready:
            statusLabel.text = "Opening Linux files…"
            activityIndicator.startAnimating()
        case .shuttingDown:
            statusLabel.text = "Shutting down the runtime…"
            activityIndicator.startAnimating()
        case .terminated:
            statusLabel.text =
                "The runtime has shut down. Restart the App to boot again."
        case .failed(let message):
            statusLabel.text = "Runtime failed:\n\(message)"
            bootButton.isHidden = !store.canBoot
            bootButton.isEnabled = store.canBoot
            bootButton.configuration?.title = "Retry Prepare and Boot"
        }
    }

    private func installFilesIfNeeded(system: PocketRootSystem) {
        placeholderStack.isHidden = true
        guard filesController == nil else {
            return
        }

        let filesController = PocketRootFileBrowserViewController(
            system: system,
            initialPath: "/root"
        )
        addChild(filesController)
        filesController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filesController.view)
        NSLayoutConstraint.activate([
            filesController.view.topAnchor.constraint(equalTo: view.topAnchor),
            filesController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filesController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filesController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        filesController.didMove(toParent: self)
        self.filesController = filesController
    }

    private func removeFiles() {
        guard let filesController else {
            return
        }
        filesController.willMove(toParent: nil)
        filesController.view.removeFromSuperview()
        filesController.removeFromParent()
        self.filesController = nil
    }

    @objc
    private func bootRuntime() {
        Task {
            await runtimeStore.boot()
        }
    }
}
