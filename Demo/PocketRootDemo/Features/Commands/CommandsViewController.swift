import PocketRoot
import UIKit

@MainActor
final class CommandsViewController: UIViewController {

    private let commandField = UITextField()
    private let runButton = UIButton(type: .system)
    private let outputTextView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Commands"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemBackground

        configureNavigationItem()
        configureView()
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
            do {
                let result = try await PocketRootSystem.shared.execute(request)
                self?.outputTextView.text = Self.output(from: result)
            } catch {
                self?.outputTextView.text = [
                    "Runtime is not installed yet.",
                    "",
                    error.localizedDescription
                ].joined(separator: "\n")
            }
            self?.runButton.isEnabled = true
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
