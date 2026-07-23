import Foundation

public enum PocketRootLinuxCommandToolError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidToolCall(String)
    case outputLimitExceeded(Int)
}

extension PocketRootLinuxCommandToolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid Linux command tool configuration: \(message)"
        case .invalidToolCall(let message):
            return "Invalid Linux command tool call: \(message)"
        case .outputLimitExceeded(let limit):
            return "Linux command tool output exceeded the \(limit)-byte limit."
        }
    }
}
