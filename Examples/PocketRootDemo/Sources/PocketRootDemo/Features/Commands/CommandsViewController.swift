import PocketRoot
import UIKit

@MainActor
final class CommandsViewController: UIViewController, DemoRuntimeStoreObserver {

    private let runtimeStore: DemoRuntimeStore
    private let commandField = UITextField()
    private let runButton = UIButton(type: .system)
    private let outputTextView = UITextView()
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
        title = "Commands"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemBackground

        configureNavigationItem()
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
        runButton.isEnabled = store.readySystem != nil
        commandField.isEnabled = store.readySystem != nil
        if store.readySystem == nil, !store.phase.displayName.isEmpty {
            outputTextView.text = "Runtime: \(store.phase.displayName)"
        }
    }

    private func configureNavigationItem() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear",
            style: .plain,
            target: self,
            action: #selector(clearOutput)
        )
    }

    private func configureView() {
        commandField.borderStyle = .roundedRect
        commandField.placeholder = "Enter a command"
        commandField.text = "uname -a"
        commandField.font = .preferredFont(forTextStyle: .body)
        commandField.adjustsFontForContentSizeCategory = true
        commandField.autocapitalizationType = .none
        commandField.autocorrectionType = .no
        commandField.returnKeyType = .go
        commandField.accessibilityLabel = "Command"
        commandField.addTarget(self, action: #selector(runCommand), for: .editingDidEndOnExit)

        var runConfiguration = UIButton.Configuration.filled()
        runConfiguration.title = "Run"
        runConfiguration.image = UIImage(systemName: "play.fill")
        runConfiguration.imagePadding = 8
        runButton.configuration = runConfiguration
        runButton.addTarget(self, action: #selector(runCommand), for: .touchUpInside)

        let inputStack = UIStackView(arrangedSubviews: [commandField, runButton])
        inputStack.axis = .horizontal
        inputStack.spacing = DemoConstants.itemSpacing
        inputStack.alignment = .fill
        runButton.setContentHuggingPriority(.required, for: .horizontal)

        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.backgroundColor = .secondarySystemBackground
        outputTextView.font = .preferredFont(forTextStyle: .body)
        outputTextView.adjustsFontForContentSizeCategory = true
        outputTextView.layer.cornerRadius = 10
        outputTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        outputTextView.text = "Command output will appear here."
        outputTextView.accessibilityLabel = "Command output"

        let stackView = UIStackView(arrangedSubviews: [inputStack, outputTextView])
        stackView.axis = .vertical
        stackView.spacing = DemoConstants.itemSpacing
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
            ),
            stackView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -DemoConstants.contentInsets.bottom
            )
        ])
    }

    @objc
    private func runCommand() {
        view.endEditing(true)

        guard let command = commandField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !command.isEmpty
        else {
            outputTextView.text = "Enter a command before running."
            return
        }

        runButton.isEnabled = false
        outputTextView.text = "Running…"

        let request = PocketRootCommandRequest(command: command)
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let result = try await runtimeStore.execute(request)
                outputTextView.text = Self.output(from: result)
            } catch {
                outputTextView.text = error.localizedDescription
            }
            runButton.isEnabled = runtimeStore.readySystem != nil
        }
    }

    @objc
    private func clearOutput() {
        outputTextView.text = ""
    }

    private static func output(from result: PocketRootCommandResult) -> String {
        var sections: [String] = []
        if !result.stdout.isEmpty {
            sections.append(result.stdout)
        }
        if !result.stderr.isEmpty {
            sections.append(result.stderr)
        }
        sections.append("Exit code: \(result.exitCode)")
        if result.timedOut {
            sections.append("Timed out")
        }
        return sections.joined(separator: "\n")
    }
}
