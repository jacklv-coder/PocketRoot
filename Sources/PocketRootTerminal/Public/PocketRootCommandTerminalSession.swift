import Foundation
import PocketRootCore

public enum PocketRootCommandTerminalSessionError: Error, Sendable, Equatable {
    case invalidCommand(String)
    case commandInProgress
}

extension PocketRootCommandTerminalSessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCommand(let message):
            return "Invalid terminal command: \(message)"
        case .commandInProgress:
            return "A terminal command is already running."
        }
    }
}

/// A lightweight stateful shell facade backed by bounded one-shot commands.
///
/// This is intentionally not a PTY. Each submission runs in a fresh `/bin/sh`
/// process while the facade carries the resulting working directory into the
/// next request. It provides the minimum `ls`/`cd`/file-operation loop without
/// claiming support for interactive programs such as `vim` or `top`.
@available(macOS 13.0, *)
public actor PocketRootCommandTerminalSession {
    public let environment: [String: String]
    public let timeout: Duration
    public private(set) var workingDirectory: String

    private let executor: any PocketRootTerminalCommandExecutor
    private var commandInFlight = false

    public init(
        executor: any PocketRootTerminalCommandExecutor,
        workingDirectory: String = "/root",
        environment: [String: String] = [:],
        timeout: Duration = .seconds(30)
    ) {
        self.executor = executor
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }

    public func execute(
        _ command: String
    ) async throws -> PocketRootCommandTerminalResponse {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PocketRootCommandTerminalSessionError.invalidCommand(
                "command must not be empty."
            )
        }
        guard !command.contains("\0") else {
            throw PocketRootCommandTerminalSessionError.invalidCommand(
                "command must not contain a NUL byte."
            )
        }
        guard !commandInFlight else {
            throw PocketRootCommandTerminalSessionError.commandInProgress
        }
        commandInFlight = true
        defer {
            commandInFlight = false
        }

        let marker = "POCKETROOT_CWD_\(UUID().uuidString)"
        let wrappedCommand = Self.wrap(command: command, marker: marker)
        let result = try await executor.execute(
            PocketRootCommandRequest(
                command: wrappedCommand,
                workingDirectory: workingDirectory,
                environment: environment,
                timeout: timeout
            )
        )
        let parsed = Self.parse(
            standardOutput: result.standardOutput,
            marker: marker
        )
        if let nextWorkingDirectory = parsed.workingDirectory {
            workingDirectory = nextWorkingDirectory
        }

        return PocketRootCommandTerminalResponse(
            command: command,
            workingDirectory: workingDirectory,
            result: PocketRootCommandResult(
                exitCode: result.exitCode,
                signal: result.signal,
                standardOutput: parsed.standardOutput,
                standardError: result.standardError,
                timedOut: result.timedOut
            )
        )
    }

    private static func wrap(command: String, marker: String) -> String {
        """
        \(command)
        __pocketroot_status=$?
        __pocketroot_cwd=$(command pwd -P)
        printf '\\036%s\\037%s\\036' '\(marker)' "$__pocketroot_cwd"
        exit "$__pocketroot_status"
        """
    }

    private static func parse(
        standardOutput: Data,
        marker: String
    ) -> (standardOutput: Data, workingDirectory: String?) {
        var prefix = Data([0x1e])
        prefix.append(contentsOf: marker.utf8)
        prefix.append(0x1f)

        guard let prefixRange = standardOutput.range(
            of: prefix,
            options: .backwards
        ) else {
            return (standardOutput, nil)
        }
        let suffix = Data([0x1e])
        guard let suffixRange = standardOutput.range(
            of: suffix,
            in: prefixRange.upperBound..<standardOutput.endIndex
        ) else {
            return (standardOutput, nil)
        }

        let directoryData = standardOutput[
            prefixRange.upperBound..<suffixRange.lowerBound
        ]
        guard let directory = String(data: directoryData, encoding: .utf8),
              directory.hasPrefix("/"),
              directory.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              })
        else {
            return (standardOutput, nil)
        }

        var cleanedOutput = Data(
            standardOutput[..<prefixRange.lowerBound]
        )
        cleanedOutput.append(contentsOf: standardOutput[suffixRange.upperBound...])
        return (cleanedOutput, directory)
    }
}

public struct PocketRootCommandTerminalResponse: Sendable, Equatable {
    public let command: String
    public let workingDirectory: String
    public let result: PocketRootCommandResult

    public init(
        command: String,
        workingDirectory: String,
        result: PocketRootCommandResult
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.result = result
    }
}
