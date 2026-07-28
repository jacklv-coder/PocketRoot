import Foundation
import PocketRootCore

/// Describes why an interactive terminal stopped accepting input.
public enum PocketRootTerminalSessionEndReason: Sendable, Equatable {
    case exited(Int32)
    case failed(String)
}

#if canImport(UIKit) && canImport(SwiftTerm)
import SwiftTerm
import UIKit

/// A UIKit terminal that can host a real PocketRoot PTY through SwiftTerm.
@MainActor
public final class PocketRootTerminalViewController: UIViewController {
    public let configuration: PocketRootTerminalConfiguration
    public private(set) var theme: PocketRootTerminalTheme
    /// Called when the guest shell exits or the PTY connection fails.
    ///
    /// Hosts can use this callback to dismiss the terminal or offer a new
    /// session. Calling ``closeSession()`` does not invoke the callback.
    public var onSessionEnded: ((PocketRootTerminalSessionEndReason) -> Void)?

    /// Transcript support is retained for the lightweight command fallback.
    /// Interactive PTY screen state is owned by SwiftTerm.
    public var transcript: String {
        outputLines.joined(separator: "\n")
    }

    private let placeholderView = TerminalPlaceholderView()
    private let accessoryView = TerminalAccessoryView()
    private let commandBridge: TerminalBridge
    private let ptyBridge: PTYTerminalBridge?
    private var ptyTerminalView: TerminalView?
    private var outputLines: [String]

    public init(
        configuration: PocketRootTerminalConfiguration = .init(),
        theme: PocketRootTerminalTheme = .system
    ) {
        self.configuration = configuration
        self.theme = theme
        commandBridge = TerminalBridge()
        ptyBridge = nil
        outputLines = [configuration.placeholderText]
        super.init(nibName: nil, bundle: nil)
    }

    /// Creates a persistent interactive shell using the system's PTY session.
    /// When `sessionConfiguration` is `nil`, the terminal configuration's
    /// `initialWorkingDirectory` supplies the PTY working directory.
    public init(
        system: PocketRootSystem,
        sessionConfiguration: PocketRootSessionConfiguration? = nil,
        configuration: PocketRootTerminalConfiguration = .interactive(),
        theme: PocketRootTerminalTheme = .dark
    ) {
        let resolvedSessionConfiguration =
            configuration.resolvingInteractiveSessionConfiguration(
                sessionConfiguration
            )
        self.configuration = configuration
        self.theme = theme
        commandBridge = TerminalBridge()
        ptyBridge = PTYTerminalBridge(allowsInput: configuration.allowsInput) {
            try await system.makeSession(
                configuration: resolvedSessionConfiguration
            )
        }
        outputLines = []
        super.init(nibName: nil, bundle: nil)
    }

    /// Creates the bounded one-shot command fallback. Prefer the `system`
    /// initializer when a full PTY terminal is required.
    public init(
        commandExecutor: any PocketRootTerminalCommandExecutor,
        configuration: PocketRootTerminalConfiguration = .commandLine(),
        theme: PocketRootTerminalTheme = .dark
    ) {
        self.configuration = configuration
        self.theme = theme
        commandBridge = TerminalBridge(
            session: PocketRootCommandTerminalSession(
                executor: commandExecutor,
                workingDirectory: configuration.initialWorkingDirectory,
                timeout: configuration.commandTimeout
            )
        )
        ptyBridge = nil
        outputLines = [configuration.placeholderText]
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        let configuration = PocketRootTerminalConfiguration()
        self.configuration = configuration
        theme = .system
        commandBridge = TerminalBridge()
        ptyBridge = nil
        outputLines = [configuration.placeholderText]
        super.init(coder: coder)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Terminal"
        view.backgroundColor = theme.backgroundColor
        if let ptyBridge {
            setUpInteractiveTerminal(with: ptyBridge)
        } else {
            setUpCommandTerminal()
            connectCommandBridge()
            renderTranscript()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if configuration.allowsInput {
            _ = ptyTerminalView?.becomeFirstResponder()
        }
    }

    public func apply(theme: PocketRootTerminalTheme) {
        self.theme = theme
        guard isViewLoaded else {
            return
        }
        view.backgroundColor = theme.backgroundColor
        if let ptyTerminalView {
            ptyTerminalView.font = theme.font
            ptyTerminalView.nativeBackgroundColor = theme.backgroundColor
            ptyTerminalView.nativeForegroundColor = theme.foregroundColor
            ptyTerminalView.caretColor = theme.foregroundColor
        } else {
            renderTranscript()
        }
    }

    public func appendOutput(_ output: String) {
        outputLines.append(output)
        trimTranscriptIfNeeded()
        guard isViewLoaded, ptyTerminalView == nil else {
            return
        }
        renderTranscript()
    }

    public func clearOutput() {
        outputLines.removeAll()
        guard isViewLoaded, ptyTerminalView == nil else {
            return
        }
        renderTranscript()
    }

    public func cancelActiveCommand() {
        commandBridge.cancelActiveCommand()
    }

    /// Explicitly releases the guest PTY. Call this when the host permanently
    /// removes the terminal controller. The command fallback also cancels its
    /// active task and disconnects its callbacks.
    public func closeSession(
        completion: (@MainActor () -> Void)? = nil
    ) {
        commandBridge.detach()
        ptyBridge?.sessionEndHandler = nil
        if let ptyBridge {
            ptyBridge.detach(completion: completion)
        } else {
            completion?()
        }
    }

    private func setUpInteractiveTerminal(with bridge: PTYTerminalBridge) {
        let terminal = TerminalView(frame: .zero, font: theme.font)
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.nativeBackgroundColor = theme.backgroundColor
        terminal.nativeForegroundColor = theme.foregroundColor
        terminal.caretColor = theme.foregroundColor
        terminal.accessibilityLabel = "PocketRoot Terminal"
        terminal.accessibilityIdentifier = "PocketRootTerminal.pty"
        if !configuration.cursorBlinkEnabled {
            terminal.getTerminal().setCursorStyle(.steadyBlock)
        }
        if !configuration.allowsInput {
            terminal.accessibilityHint = "Read-only terminal"
        }
        view.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        ptyTerminalView = terminal
        bridge.titleHandler = { [weak self] title in
            self?.title = title.isEmpty ? "Terminal" : title
        }
        bridge.sessionEndHandler = { [weak self] reason in
            self?.onSessionEnded?(reason)
        }
        bridge.attach(to: terminal)
    }

    private func setUpCommandTerminal() {
        view.backgroundColor = .systemBackground
        accessoryView.configure(
            prompt: configuration.prompt,
            isInputEnabled: configuration.allowsInput
        )
        accessoryView.isHidden = !configuration.showsAccessoryView

        let stackView = UIStackView(
            arrangedSubviews: [placeholderView, accessoryView]
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 12

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 16
            ),
            stackView.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            stackView.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),
            stackView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            )
        ])
    }

    private func connectCommandBridge() {
        commandBridge.attach(
            outputHandler: { [weak self] output in
                self?.appendOutput(output)
            },
            inputStateHandler: { [weak self] isEnabled in
                guard let self else {
                    return
                }
                accessoryView.setInputEnabled(
                    configuration.allowsInput && isEnabled
                )
            }
        )
        accessoryView.onSubmit = { [weak self] command in
            guard let self else {
                return
            }
            commandBridge.submit(command, prompt: configuration.prompt)
        }
    }

    private func renderTranscript() {
        placeholderView.render(text: transcript, theme: theme)
    }

    private func trimTranscriptIfNeeded() {
        let limit = configuration.maximumTranscriptCharacters
        let renderedTranscript = transcript
        guard renderedTranscript.count > limit else {
            return
        }
        let notice = "[Earlier terminal output removed]\n"
        guard limit > notice.count else {
            outputLines = [String(notice.prefix(limit))]
            return
        }
        outputLines = [
            String(notice.dropLast()),
            String(renderedTranscript.suffix(limit - notice.count))
        ]
    }
}

#else

/// A host-build stand-in for the UIKit terminal controller.
@MainActor
public final class PocketRootTerminalViewController {
    public let configuration: PocketRootTerminalConfiguration
    public private(set) var theme: PocketRootTerminalTheme
    public private(set) var transcript: String
    public var onSessionEnded: ((PocketRootTerminalSessionEndReason) -> Void)?

    public init(
        configuration: PocketRootTerminalConfiguration = .init(),
        theme: PocketRootTerminalTheme = .system
    ) {
        self.configuration = configuration
        self.theme = theme
        transcript = configuration.placeholderText
    }

    public init(
        system _: PocketRootSystem,
        sessionConfiguration _: PocketRootSessionConfiguration? = nil,
        configuration: PocketRootTerminalConfiguration = .interactive(),
        theme: PocketRootTerminalTheme = .dark
    ) {
        self.configuration = configuration
        self.theme = theme
        transcript = configuration.placeholderText
    }

    public init(
        commandExecutor _: any PocketRootTerminalCommandExecutor,
        configuration: PocketRootTerminalConfiguration = .commandLine(),
        theme: PocketRootTerminalTheme = .dark
    ) {
        self.configuration = configuration
        self.theme = theme
        transcript = configuration.placeholderText
    }

    public func apply(theme: PocketRootTerminalTheme) {
        self.theme = theme
    }

    public func appendOutput(_ output: String) {
        transcript = transcript.isEmpty ? output : transcript + "\n" + output
    }

    public func clearOutput() {
        transcript = ""
    }

    public func cancelActiveCommand() {}
    public func closeSession() {}
}

#endif
