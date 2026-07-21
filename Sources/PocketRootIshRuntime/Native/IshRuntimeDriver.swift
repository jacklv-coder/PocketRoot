import Foundation

struct IshDriverBootOptions: Sendable, Equatable {
    let rootFSPath: String
    let workDirectory: String
    let supervisorGuestPath: String?
    let kernelLogFileDescriptor: Int32
}

struct IshDriverCommandRequest: Sendable, Equatable {
    let arguments: [String]
    let workingDirectory: String
    let environment: [String: String]?
    let timeout: TimeInterval
    let mergeStandardError: Bool
    let maximumStandardOutputBytes: Int
    let maximumStandardErrorBytes: Int
}

struct IshDriverCommandResult: Sendable, Equatable {
    let exitCode: Int32
    let signal: Int32
    let standardOutput: Data
    let standardError: Data
    let timedOut: Bool
}

protocol IshRuntimeDriver: Sendable {
    func boot(_ options: IshDriverBootOptions) throws
    func execute(_ request: IshDriverCommandRequest) throws -> IshDriverCommandResult
    func shutdown() throws
}

enum IshRuntimeDriverError: LocalizedError, Equatable {
    case outputLimitExceeded(stream: String, limit: Int)

    var errorDescription: String? {
        switch self {
        case .outputLimitExceeded(let stream, let limit):
            return "Command \(stream) exceeded the \(limit)-byte output limit."
        }
    }
}
