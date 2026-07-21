import Foundation

public enum PocketRootError: Error, Sendable, Equatable {
    case runtimeNotBooted
    case unsupportedOperation(String)
}

extension PocketRootError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .runtimeNotBooted:
            return "Runtime is not installed yet."
        case let .unsupportedOperation(message):
            return message
        }
    }
}
