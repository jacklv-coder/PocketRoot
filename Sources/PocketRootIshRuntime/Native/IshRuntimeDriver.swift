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
    case supervisorCommandRejected(syntheticExitCode: Int32)
    case ambiguousTransportExitMarker
    case sessionTerminationUnconfirmed(String)

    var errorDescription: String? {
        switch self {
        case .outputLimitExceeded(let stream, let limit):
            return "Command \(stream) exceeded the \(limit)-byte output limit."
        case .supervisorCommandRejected(let syntheticExitCode):
            return "The guest supervisor rejected the command before execution "
                + "(synthetic exit code \(syntheticExitCode))."
        case .ambiguousTransportExitMarker:
            return "The pinned transport reported its ambiguous broken-pipe EXITED marker."
        case .sessionTerminationUnconfirmed(let reason):
            return "Guest process termination could not be confirmed: \(reason)"
        }
    }
}

enum IshRuntimeTransportPolicy {
    private static let terminalSpawnErrorCodes: Set<Int32> = [-9, -11, -17]

    // ish_read_event in the pinned v0.3.3 transport synthesizes this pair when
    // the supervisor pipe breaks. Because the Swift event cannot distinguish
    // it from a guest `exit 17`, the pair is never treated as authoritative.
    static let ambiguousBrokenPipeExitCode: Int32 = 17

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
        guard exitCode != ambiguousBrokenPipeExitCode || signal != 0 else {
            throw IshRuntimeDriverError.ambiguousTransportExitMarker
        }
        // The pinned host translates supervisor ERROR frames into
        // EXITED(-errno, 0). Guest wait status cannot produce a negative exit
        // code, so preserve this as a recoverable supervisor rejection rather
        // than exposing it as a normal guest result.
        guard exitCode >= 0 else {
            throw IshRuntimeDriverError.supervisorCommandRejected(
                syntheticExitCode: exitCode
            )
        }
    }
}
