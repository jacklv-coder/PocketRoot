import Foundation

@MainActor
final class TerminalBridge {
    enum State: Equatable {
        case detached
        case attached
    }

    private(set) var state: State = .detached
    private let session: PocketRootCommandTerminalSession?
    private var outputHandler: ((String) -> Void)?
    private var inputStateHandler: ((Bool) -> Void)?
    private var commandTask: Task<Void, Never>?

    init(session: PocketRootCommandTerminalSession? = nil) {
        self.session = session
    }

    func attach(
        outputHandler: @escaping (String) -> Void,
        inputStateHandler: @escaping (Bool) -> Void
    ) {
        self.outputHandler = outputHandler
        self.inputStateHandler = inputStateHandler
        state = .attached
    }

    func detach() {
        commandTask?.cancel()
        commandTask = nil
        outputHandler = nil
        inputStateHandler = nil
        state = .detached
    }

    func submit(_ command: String, prompt: String) {
        guard state == .attached, commandTask == nil else {
            return
        }

        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            return
        }

        outputHandler?(prompt + trimmedCommand)
        guard let session else {
            outputHandler?("Runtime is not connected.")
            return
        }

        inputStateHandler?(false)
        commandTask = Task { [weak self] in
            defer {
                if let self, self.state == .attached {
                    self.inputStateHandler?(true)
                    self.commandTask = nil
                }
            }
            do {
                let response = try await session.execute(trimmedCommand)
                guard !Task.isCancelled else {
                    return
                }
                if !response.result.stdout.isEmpty {
                    self?.outputHandler?(response.result.stdout)
                }
                if !response.result.stderr.isEmpty {
                    self?.outputHandler?(response.result.stderr)
                }
                if response.result.timedOut {
                    self?.outputHandler?("Command timed out.")
                } else if response.result.exitCode != 0 {
                    self?.outputHandler?("Exit code: \(response.result.exitCode)")
                }
            } catch is CancellationError {
                self?.outputHandler?("Command cancelled.")
            } catch {
                self?.outputHandler?("Error: \(error.localizedDescription)")
            }
        }
    }

    func cancelActiveCommand() {
        commandTask?.cancel()
    }
}
