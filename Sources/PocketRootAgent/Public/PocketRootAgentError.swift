import Foundation

public enum PocketRootAgentError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidToolDefinition(String)
    case invalidUserInput(String)
    case userInputLimitExceeded(Int)
    case runAlreadyInProgress
    case invalidModelResponse(String)
    case modelOutputLimitExceeded(Int)
    case duplicateToolCallID(String)
    case maximumTurnsExceeded(Int)
    case maximumToolCallsExceeded(Int)
    case toolArgumentsLimitExceeded(tool: String, limit: Int)
    case toolOutputLimitExceeded(tool: String, limit: Int)
}

extension PocketRootAgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid agent configuration: \(message)"
        case .invalidToolDefinition(let message):
            return "Invalid agent tool definition: \(message)"
        case .invalidUserInput(let message):
            return "Invalid agent input: \(message)"
        case .userInputLimitExceeded(let limit):
            return "Agent input exceeded the \(limit)-byte limit."
        case .runAlreadyInProgress:
            return "This agent runner already has a run in progress."
        case .invalidModelResponse(let message):
            return "Invalid model response: \(message)"
        case .modelOutputLimitExceeded(let limit):
            return "Model output exceeded the \(limit)-byte limit."
        case .duplicateToolCallID(let callID):
            return "The model repeated tool call ID '\(callID)'."
        case .maximumTurnsExceeded(let limit):
            return "The agent exceeded its \(limit)-turn limit."
        case .maximumToolCallsExceeded(let limit):
            return "The agent exceeded its \(limit)-tool-call limit."
        case .toolArgumentsLimitExceeded(let tool, let limit):
            return "Tool '\(tool)' arguments exceeded the \(limit)-byte limit."
        case .toolOutputLimitExceeded(let tool, let limit):
            return "Tool '\(tool)' exceeded its \(limit)-byte output limit."
        }
    }
}
