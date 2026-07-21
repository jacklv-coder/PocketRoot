import Foundation
import PocketRootCore

#if canImport(UIKit)
import UIKit

/// A UIKit terminal host that presents a placeholder until SwiftTerm and the
/// Linux runtime are integrated.
@MainActor
public final class PocketRootTerminalViewController: UIViewController {
    public let configuration: PocketRootTerminalConfiguration
    public private(set) var theme: PocketRootTerminalTheme

    public var transcript: String {
        outputLines.joined(separator: "\n")
    }

    private let terminalView = TerminalPlaceholderView()
    private let accessoryView = TerminalAccessoryView()
    private let bridge = TerminalBridge()
    private var outputLines: [String]

    public init(
        configuration: PocketRootTerminalConfiguration = .init(),
        theme: PocketRootTerminalTheme = .system
    ) {
        self.configuration = configuration
        self.theme = theme
        outputLines = [configuration.placeholderText]
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        let configuration = PocketRootTerminalConfiguration()
        self.configuration = configuration
        theme = .system
        outputLines = [configuration.placeholderText]
        super.init(coder: coder)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        connectBridge()
        render()
    }

    public func apply(theme: PocketRootTerminalTheme) {
        self.theme = theme
        guard isViewLoaded else {
            return
        }
        render()
    }

    public func appendOutput(_ output: String) {
        outputLines.append(output)
        guard isViewLoaded else {
            return
        }
        render()
    }

    public func clearOutput() {
        outputLines.removeAll()
        guard isViewLoaded else {
            return
        }
        render()
    }

    private func setUpView() {
        title = "Terminal"
        view.backgroundColor = .systemBackground

        accessoryView.configure(
            prompt: configuration.prompt,
            isInputEnabled: configuration.allowsInput
        )
        accessoryView.isHidden = !configuration.showsAccessoryView

        let stackView = UIStackView(arrangedSubviews: [terminalView, accessoryView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 12

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func connectBridge() {
        bridge.attach { [weak self] output in
            self?.appendOutput(output)
        }
        accessoryView.onSubmit = { [weak self] command in
            guard let self else {
                return
            }
            bridge.submit(command, prompt: configuration.prompt)
        }
    }

    private func render() {
        terminalView.render(text: transcript, theme: theme)
    }
}

#else

/// A host-build stand-in for the UIKit controller. The package supports iOS,
/// while this definition keeps `swift test` useful on non-UIKit build hosts.
@MainActor
public final class PocketRootTerminalViewController {
    public let configuration: PocketRootTerminalConfiguration
    public private(set) var theme: PocketRootTerminalTheme
    public private(set) var transcript: String

    public init(
        configuration: PocketRootTerminalConfiguration = .init(),
        theme: PocketRootTerminalTheme = .system
    ) {
        self.configuration = configuration
        self.theme = theme
        transcript = configuration.placeholderText
    }

    public func apply(theme: PocketRootTerminalTheme) {
        self.theme = theme
    }

    public func appendOutput(_ output: String) {
        if transcript.isEmpty {
            transcript = output
        } else {
            transcript += "\n" + output
        }
    }

    public func clearOutput() {
        transcript = ""
    }
}

#endif
