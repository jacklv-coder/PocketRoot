import Foundation

public enum PocketRootError: Error, Sendable, Equatable {
    case runtimeNotBooted
    case rootFSUnavailable(String)
    case runtimeFailure(String)
    case restartRequired
    case invalidCommandRequest(String)
    case commandOutputLimitExceeded(stream: String, limit: Int)
    case fileDestinationExists(String)
    case guestFileSystemFailure(code: Int32, path: String)
    case unsupportedOperation(String)
}

extension PocketRootError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .runtimeNotBooted:
            return "Linux Runtime is not booted."
        case .rootFSUnavailable(let message):
            return "RootFS is unavailable: \(message)"
        case .runtimeFailure(let message):
            return "Linux Runtime failed: \(message)"
        case .restartRequired:
            return "Linux Runtime has terminated. Restart the host app before booting again."
        case .invalidCommandRequest(let message):
            return "Invalid command request: \(message)"
        case .commandOutputLimitExceeded(let stream, let limit):
            return "Command \(stream) exceeded the \(limit)-byte output limit."
        case .fileDestinationExists(let path):
            return "An item already exists at \(path)."
        case .guestFileSystemFailure(let code, let path):
            return "The guest filesystem operation failed for \(path) with errno \(code)."
        case let .unsupportedOperation(message):
            return message
        }
    }
}
