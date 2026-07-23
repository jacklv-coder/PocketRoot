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
    case nativeOutputLimitExceeded(maximumBytes: Int, maximumFrames: Int)
    case supervisorCommandRejected(String)
    case sessionTerminationUnconfirmed(String)

    var requiresRuntimeRestart: Bool {
        switch self {
        case .nativeOutputLimitExceeded, .sessionTerminationUnconfirmed:
            return true
        case .outputLimitExceeded, .supervisorCommandRejected:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .outputLimitExceeded(let stream, let limit):
            return "Command \(stream) exceeded the \(limit)-byte output limit."
        case .nativeOutputLimitExceeded(let maximumBytes, let maximumFrames):
            return "The native session backlog exceeded its bounded "
                + "\(maximumBytes)-byte or \(maximumFrames)-frame limit."
        case .supervisorCommandRejected(let message):
            return "The guest supervisor rejected the command before execution "
                + "(\(message))."
        case .sessionTerminationUnconfirmed(let reason):
            return "Guest process termination could not be confirmed: \(reason)"
        }
    }
}

enum IshRuntimeTransportPolicy {
    private static let terminalSpawnErrorCodes: Set<Int32> = [-9, -11, -17]

    static func terminalSpawnFailure(
        code: Int32,
        message: String
    ) -> IshRuntimeDriverError? {
        guard terminalSpawnErrorCodes.contains(code) else {
            return nil
        }
        return .sessionTerminationUnconfirmed(
            "spawning the guest command failed because the native transport "
                + "is no longer trustworthy (IshError \(code): \(message))"
        )
    }

    static func validateAuthoritativeExit(
        exitCode: Int32,
        signal: Int32
    ) throws {
        // The pinned v4 transport returns protocol and supervisor failures as
        // typed IshError values. EXITED is reserved for guest wait status, so a
        // negative payload is a protocol-integrity failure rather than a guest
        // result.
        guard exitCode >= 0 else {
            throw IshRuntimeDriverError.sessionTerminationUnconfirmed(
                "the native transport reported invalid guest exit code "
                    + "\(exitCode) with signal \(signal)"
            )
        }
    }
}
