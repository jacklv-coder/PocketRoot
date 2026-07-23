import Foundation
import PocketRootAgent
import PocketRootCore

@available(macOS 13.0, *)
public struct PocketRootLinuxCommandTool: Sendable {
    public static let toolName = "run_linux_command"

    public let definition: PocketRootAgentToolDefinition

    private let executor: any PocketRootCommandExecuting
    private let configuration: PocketRootLinuxCommandToolConfiguration
    private let allowedWorkingDirectoryRoots: [String]
    private let policy: PocketRootLinuxCommandPolicy
    private let approval: PocketRootLinuxCommandApproval

    public init(
        executor: any PocketRootCommandExecuting,
        configuration: PocketRootLinuxCommandToolConfiguration = .init(),
        policy: PocketRootLinuxCommandPolicy,
        approval: PocketRootLinuxCommandApproval
    ) throws {
        let roots = try Self.validate(configuration: configuration)
        self.executor = executor
        self.configuration = configuration
        allowedWorkingDirectoryRoots = roots
        self.policy = policy
        self.approval = approval
        definition = Self.makeDefinition(configuration: configuration)
    }

    public var agentTool: PocketRootAgentTool {
        PocketRootAgentTool(
            definition: definition,
            preflight: { call in
                _ = try makeCommand(from: call)
            },
            handler: { call in
                try await execute(call)
            }
        )
    }

    public func execute(
        _ call: PocketRootAgentToolCall
    ) async throws -> String {
        let command = try makeCommand(from: call)
        try Task.checkCancellation()

        switch policy.evaluate(command) {
        case .allowed:
            break
        case .denied(let reason):
            return try encodeDenial(stage: "policy", reason: reason)
        }

        try Task.checkCancellation()
        let approvalDecision = await approval.request(command)
        try Task.checkCancellation()
        switch approvalDecision {
        case .approved:
            break
        case .denied(let reason):
            return try encodeDenial(stage: "approval", reason: reason)
        }

        try Task.checkCancellation()
        let result = try await executor.execute(
            PocketRootCommandRequest(
                command: command.command,
                workingDirectory: command.workingDirectory,
                environment: command.environment,
                timeout: .seconds(command.timeoutSeconds),
                mergeStandardError: command.mergeStandardError
            )
        )
        try Task.checkCancellation()

        return try encode(result)
    }

    private func makeCommand(
        from call: PocketRootAgentToolCall
    ) throws -> PocketRootLinuxCommand {
        guard call.name == Self.toolName else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "tool name must be '\(Self.toolName)'."
            )
        }
        guard !call.id.isEmpty else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "tool call ID must not be empty."
            )
        }

        let data = Data(call.argumentsJSON.utf8)
        guard data.count <= configuration.maximumArgumentsBytes else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "arguments exceeded the "
                    + "\(configuration.maximumArgumentsBytes)-byte limit."
            )
        }
        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "arguments must be a JSON object."
            )
        }
        do {
            try JSONDuplicateKeyValidator.validate(data)
        } catch JSONDuplicateKeyValidator.ValidationError.duplicateKey {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "arguments must not contain duplicate JSON object keys."
            )
        } catch {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "arguments must be a valid JSON object."
            )
        }
        guard let object = rawObject as? [String: Any] else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "arguments must be a JSON object."
            )
        }
        let expectedKeys: Set<String> = [
            "command",
            "working_directory",
            "environment",
            "timeout_seconds",
            "merge_standard_error"
        ]
        guard Set(object.keys) == expectedKeys else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "arguments must contain exactly command, working_directory, "
                    + "environment, timeout_seconds, and merge_standard_error."
            )
        }
        guard let rawEnvironment = object["environment"] as? [Any] else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "environment must be an array."
            )
        }
        for entry in rawEnvironment {
            guard let entryObject = entry as? [String: Any],
                  Set(entryObject.keys) == Set(["name", "value"])
            else {
                throw PocketRootLinuxCommandToolError.invalidToolCall(
                    "each environment entry must contain exactly name and value."
                )
            }
        }

        let arguments: Arguments
        do {
            arguments = try JSONDecoder().decode(Arguments.self, from: data)
        } catch {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "argument values did not match the required types."
            )
        }

        guard !arguments.command.isEmpty else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "command must not be empty."
            )
        }
        guard arguments.command.utf8.count
                <= configuration.maximumCommandBytes
        else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "command exceeded the \(configuration.maximumCommandBytes)-byte limit."
            )
        }
        guard !Self.containsControlCharacter(arguments.command) else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "command must be a single line without control characters."
            )
        }

        let requestedWorkingDirectory = arguments.workingDirectory.isEmpty
            ? configuration.defaultWorkingDirectory
            : arguments.workingDirectory
        guard requestedWorkingDirectory.utf8.count
                <= configuration.maximumWorkingDirectoryBytes
        else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "working directory exceeded the "
                    + "\(configuration.maximumWorkingDirectoryBytes)-byte limit."
            )
        }
        let workingDirectory = try Self.normalizedAbsolutePath(
            requestedWorkingDirectory,
            context: "working directory"
        )
        guard Self.isPath(
            workingDirectory,
            withinAny: allowedWorkingDirectoryRoots
        ) else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "working directory is outside the configured roots."
            )
        }

        guard arguments.timeoutSeconds > 0,
              arguments.timeoutSeconds
                <= configuration.maximumTimeoutSeconds
        else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "timeout_seconds must be between 1 and "
                    + "\(configuration.maximumTimeoutSeconds)."
            )
        }
        guard !arguments.mergeStandardError
                || configuration.allowsMergedStandardError
        else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "merged standard error is disabled."
            )
        }
        guard arguments.environment.count
                <= configuration.maximumEnvironmentEntries
        else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "environment exceeded the "
                    + "\(configuration.maximumEnvironmentEntries)-entry limit."
            )
        }

        var environment: [String: String] = [:]
        var environmentBytes = 0
        for entry in arguments.environment {
            guard Self.isValidEnvironmentName(entry.name) else {
                throw PocketRootLinuxCommandToolError.invalidToolCall(
                    "environment name '\(entry.name)' is invalid."
                )
            }
            guard configuration.allowedEnvironmentNames.contains(entry.name) else {
                throw PocketRootLinuxCommandToolError.invalidToolCall(
                    "environment name '\(entry.name)' is not allowed."
                )
            }
            guard environment[entry.name] == nil else {
                throw PocketRootLinuxCommandToolError.invalidToolCall(
                    "environment name '\(entry.name)' was repeated."
                )
            }
            guard entry.value.utf8.count
                    <= configuration.maximumEnvironmentValueBytes
            else {
                throw PocketRootLinuxCommandToolError.invalidToolCall(
                    "environment value for '\(entry.name)' exceeded the "
                        + "\(configuration.maximumEnvironmentValueBytes)-byte limit."
                )
            }
            guard !Self.containsControlCharacter(entry.value) else {
                throw PocketRootLinuxCommandToolError.invalidToolCall(
                    "environment value for '\(entry.name)' contains a control character."
                )
            }
            environmentBytes += entry.name.utf8.count + entry.value.utf8.count
            guard environmentBytes <= configuration.maximumEnvironmentBytes else {
                throw PocketRootLinuxCommandToolError.invalidToolCall(
                    "environment exceeded the "
                        + "\(configuration.maximumEnvironmentBytes)-byte limit."
                )
            }
            environment[entry.name] = entry.value
        }

        return PocketRootLinuxCommand(
            toolCallID: call.id,
            command: arguments.command,
            workingDirectory: workingDirectory,
            environment: environment,
            timeoutSeconds: arguments.timeoutSeconds,
            mergeStandardError: arguments.mergeStandardError
        )
    }

    private func encodeDenial(
        stage: String,
        reason: String
    ) throws -> String {
        let boundedReason = Self.utf8Prefix(reason, maximumBytes: 1_024)
        var data = try Self.encodeJSON(
            DenialEnvelope(
                status: "denied",
                stage: stage,
                reason: boundedReason
            )
        )
        if data.count > configuration.maximumToolOutputBytes {
            data = try Self.encodeJSON(
                DenialEnvelope(
                    status: "denied",
                    stage: stage,
                    reason: "The request was denied."
                )
            )
        }
        return try string(
            from: data,
            limit: configuration.maximumToolOutputBytes
        )
    }

    private func encode(
        _ result: PocketRootCommandResult
    ) throws -> String {
        var streamLimit = configuration.maximumResultStreamBytes

        while true {
            let envelope = ResultEnvelope(
                status: "completed",
                exitCode: result.exitCode,
                signal: result.signal,
                timedOut: result.timedOut,
                standardOutput: Self.streamEnvelope(
                    result.standardOutput,
                    maximumBytes: streamLimit
                ),
                standardError: Self.streamEnvelope(
                    result.standardError,
                    maximumBytes: streamLimit
                )
            )
            let data = try Self.encodeJSON(envelope)
            if data.count <= configuration.maximumToolOutputBytes {
                return try string(
                    from: data,
                    limit: configuration.maximumToolOutputBytes
                )
            }
            guard streamLimit > 0 else {
                throw PocketRootLinuxCommandToolError.outputLimitExceeded(
                    configuration.maximumToolOutputBytes
                )
            }
            streamLimit /= 2
        }
    }

    private func string(from data: Data, limit: Int) throws -> String {
        guard data.count <= limit else {
            throw PocketRootLinuxCommandToolError.outputLimitExceeded(limit)
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw PocketRootLinuxCommandToolError.outputLimitExceeded(limit)
        }
        return value
    }

    private static func streamEnvelope(
        _ data: Data,
        maximumBytes: Int
    ) -> StreamEnvelope {
        let prefix = Data(data.prefix(maximumBytes))
        if let text = String(data: prefix, encoding: .utf8) {
            return StreamEnvelope(
                encoding: "utf8",
                data: text,
                truncated: prefix.count < data.count
            )
        }
        return StreamEnvelope(
            encoding: "base64",
            data: prefix.base64EncodedString(),
            truncated: prefix.count < data.count
        )
    }

    private static func validate(
        configuration: PocketRootLinuxCommandToolConfiguration
    ) throws -> [String] {
        guard !configuration.allowedWorkingDirectoryRoots.isEmpty else {
            throw PocketRootLinuxCommandToolError.invalidConfiguration(
                "allowedWorkingDirectoryRoots must not be empty."
            )
        }
        guard configuration.maximumTimeoutSeconds > 0,
              configuration.maximumTimeoutSeconds <= 86_400
        else {
            throw PocketRootLinuxCommandToolError.invalidConfiguration(
                "maximumTimeoutSeconds must be between 1 and 86400."
            )
        }
        guard configuration.maximumArgumentsBytes > 0,
              configuration.maximumCommandBytes > 0,
              configuration.maximumWorkingDirectoryBytes > 0,
              configuration.maximumEnvironmentEntries >= 0,
              configuration.maximumEnvironmentValueBytes > 0,
              configuration.maximumEnvironmentBytes > 0,
              configuration.maximumResultStreamBytes >= 0,
              configuration.maximumToolOutputBytes >= 512
        else {
            throw PocketRootLinuxCommandToolError.invalidConfiguration(
                "byte limits must be positive, entry/stream limits must not be "
                    + "negative, and maximumToolOutputBytes must be at least 512."
            )
        }
        guard configuration.allowedEnvironmentNames.allSatisfy(
            Self.isValidEnvironmentName
        ) else {
            throw PocketRootLinuxCommandToolError.invalidConfiguration(
                "allowedEnvironmentNames contains an invalid POSIX name."
            )
        }

        let roots: [String]
        let defaultWorkingDirectory: String
        do {
            roots = try configuration.allowedWorkingDirectoryRoots.map {
                try normalizedAbsolutePath(
                    $0,
                    context: "allowed working directory root"
                )
            }
            defaultWorkingDirectory = try normalizedAbsolutePath(
                configuration.defaultWorkingDirectory,
                context: "default working directory"
            )
        } catch {
            throw PocketRootLinuxCommandToolError.invalidConfiguration(
                "working directory roots and the default must be normalized "
                    + "absolute paths without control, '.', or '..' components."
            )
        }
        guard defaultWorkingDirectory.utf8.count
                <= configuration.maximumWorkingDirectoryBytes
        else {
            throw PocketRootLinuxCommandToolError.invalidConfiguration(
                "defaultWorkingDirectory exceeded maximumWorkingDirectoryBytes."
            )
        }
        guard isPath(defaultWorkingDirectory, withinAny: roots) else {
            throw PocketRootLinuxCommandToolError.invalidConfiguration(
                "defaultWorkingDirectory must be inside an allowed root."
            )
        }
        return roots
    }

    private static func normalizedAbsolutePath(
        _ value: String,
        context: String
    ) throws -> String {
        guard value.hasPrefix("/"),
              !value.isEmpty,
              !containsControlCharacter(value)
        else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "\(context) must be an absolute path without control characters."
            )
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: true)
        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw PocketRootLinuxCommandToolError.invalidToolCall(
                "\(context) must not contain '.' or '..' components."
            )
        }
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }

    private static func isPath(
        _ path: String,
        withinAny roots: [String]
    ) -> Bool {
        roots.contains { root in
            path == root || root == "/" || path.hasPrefix(root + "/")
        }
    }

    private static func isValidEnvironmentName(_ value: String) -> Bool {
        guard let first = value.utf8.first,
              first == 95 || (65 ... 90).contains(first)
                || (97 ... 122).contains(first)
        else {
            return false
        }
        return value.utf8.dropFirst().allSatisfy {
            $0 == 95 || (48 ... 57).contains($0)
                || (65 ... 90).contains($0)
                || (97 ... 122).contains($0)
        }
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            switch $0.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                return true
            default:
                return false
            }
        }
    }

    private static func utf8Prefix(
        _ value: String,
        maximumBytes: Int
    ) -> String {
        guard value.utf8.count > maximumBytes else {
            return value
        }
        var result = ""
        result.reserveCapacity(maximumBytes)
        var resultBytes = 0
        for character in value {
            let characterBytes = String(character).utf8.count
            guard resultBytes + characterBytes <= maximumBytes else {
                break
            }
            result.append(character)
            resultBytes += characterBytes
        }
        return result
    }

    private static func encodeJSON<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func makeDefinition(
        configuration: PocketRootLinuxCommandToolConfiguration
    ) -> PocketRootAgentToolDefinition {
        PocketRootAgentToolDefinition(
            name: toolName,
            description: """
            Run one non-interactive Linux shell command after host policy and \
            explicit user approval. Use an empty working_directory for the host \
            default and an empty environment unless a listed variable is needed. \
            timeout_seconds must not exceed \
            \(configuration.maximumTimeoutSeconds).
            """,
            parametersJSONSchema: """
            {
              "type": "object",
              "properties": {
                "command": {"type": "string"},
                "working_directory": {"type": "string"},
                "environment": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "name": {"type": "string"},
                      "value": {"type": "string"}
                    },
                    "required": ["name", "value"],
                    "additionalProperties": false
                  }
                },
                "timeout_seconds": {
                  "type": "integer",
                  "minimum": 1,
                  "maximum": \(configuration.maximumTimeoutSeconds)
                },
                "merge_standard_error": {"type": "boolean"}
              },
              "required": [
                "command",
                "working_directory",
                "environment",
                "timeout_seconds",
                "merge_standard_error"
              ],
              "additionalProperties": false
            }
            """
        )
    }

}

private struct Arguments: Decodable {
    let command: String
    let workingDirectory: String
    let environment: [EnvironmentEntry]
    let timeoutSeconds: Int
    let mergeStandardError: Bool

    private enum CodingKeys: String, CodingKey {
        case command
        case workingDirectory = "working_directory"
        case environment
        case timeoutSeconds = "timeout_seconds"
        case mergeStandardError = "merge_standard_error"
    }
}

private struct EnvironmentEntry: Decodable {
    let name: String
    let value: String
}

private struct DenialEnvelope: Encodable {
    let status: String
    let stage: String
    let reason: String
}

private struct ResultEnvelope: Encodable {
    let status: String
    let exitCode: Int32
    let signal: Int32
    let timedOut: Bool
    let standardOutput: StreamEnvelope
    let standardError: StreamEnvelope

    private enum CodingKeys: String, CodingKey {
        case status
        case exitCode = "exit_code"
        case signal
        case timedOut = "timed_out"
        case standardOutput = "stdout"
        case standardError = "stderr"
    }
}

private struct StreamEnvelope: Encodable {
    let encoding: String
    let data: String
    let truncated: Bool
}

private struct JSONDuplicateKeyValidator {
    enum ValidationError: Error {
        case duplicateKey
        case invalidStructure
        case nestingLimitExceeded
    }

    private static let maximumNestingDepth = 16

    private let bytes: [UInt8]
    private var index = 0

    static func validate(_ data: Data) throws {
        var validator = Self(bytes: Array(data))
        try validator.parseValue(depth: 0)
        validator.skipWhitespace()
        guard validator.index == validator.bytes.count else {
            throw ValidationError.invalidStructure
        }
    }

    private mutating func parseValue(depth: Int) throws {
        guard depth <= Self.maximumNestingDepth else {
            throw ValidationError.nestingLimitExceeded
        }
        skipWhitespace()
        guard index < bytes.count else {
            throw ValidationError.invalidStructure
        }
        switch bytes[index] {
        case 0x7B:
            try parseObject(depth: depth)
        case 0x5B:
            try parseArray(depth: depth)
        case 0x22:
            _ = try parseString()
        default:
            try parsePrimitive()
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try consume(0x7B)
        skipWhitespace()
        if consumeIfPresent(0x7D) {
            return
        }

        var keys = Set<String>()
        while true {
            skipWhitespace()
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw ValidationError.duplicateKey
            }
            skipWhitespace()
            try consume(0x3A)
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIfPresent(0x7D) {
                return
            }
            try consume(0x2C)
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try consume(0x5B)
        skipWhitespace()
        if consumeIfPresent(0x5D) {
            return
        }

        while true {
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIfPresent(0x5D) {
                return
            }
            try consume(0x2C)
        }
    }

    private mutating func parseString() throws -> String {
        guard index < bytes.count, bytes[index] == 0x22 else {
            throw ValidationError.invalidStructure
        }
        let start = index
        index += 1

        while index < bytes.count {
            switch bytes[index] {
            case 0x22:
                index += 1
                let data = Data(bytes[start ..< index])
                guard let value = try? JSONDecoder().decode(
                    String.self,
                    from: data
                ) else {
                    throw ValidationError.invalidStructure
                }
                return value
            case 0x5C:
                index += 2
                guard index <= bytes.count else {
                    throw ValidationError.invalidStructure
                }
            default:
                index += 1
            }
        }
        throw ValidationError.invalidStructure
    }

    private mutating func parsePrimitive() throws {
        let start = index
        while index < bytes.count {
            switch bytes[index] {
            case 0x2C, 0x5D, 0x7D, 0x20, 0x09, 0x0A, 0x0D:
                guard index > start else {
                    throw ValidationError.invalidStructure
                }
                return
            default:
                index += 1
            }
        }
        guard index > start else {
            throw ValidationError.invalidStructure
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        skipWhitespace()
        guard index < bytes.count, bytes[index] == byte else {
            throw ValidationError.invalidStructure
        }
        index += 1
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else {
            return false
        }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D:
                index += 1
            default:
                return
            }
        }
    }
}
