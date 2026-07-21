#if canImport(UIKit)
import Foundation

@MainActor
final class TerminalBridge {
    enum State: Equatable {
        case detached
        case attached
    }

    private(set) var state: State = .detached
    private var outputHandler: ((String) -> Void)?

    func attach(outputHandler: @escaping (String) -> Void) {
        self.outputHandler = outputHandler
        state = .attached
    }

    func detach() {
        outputHandler = nil
        state = .detached
    }

    func submit(_ command: String, prompt: String) {
        guard state == .attached else {
            return
        }

        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            return
        }

        outputHandler?(prompt + trimmedCommand)
        outputHandler?("Runtime is not installed yet.")
    }
}
#endif
