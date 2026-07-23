import Foundation

public struct PocketRootAgentRunResult: Sendable, Equatable {
    public let finalOutput: String
    public let responseID: String
    public let turnCount: Int
    public let toolCallCount: Int

    public init(
        finalOutput: String,
        responseID: String,
        turnCount: Int,
        toolCallCount: Int
    ) {
        self.finalOutput = finalOutput
        self.responseID = responseID
        self.turnCount = turnCount
        self.toolCallCount = toolCallCount
    }
}

@available(macOS 13.0, *)
public actor PocketRootAgentRunner {
    private let modelClient: any PocketRootAgentModelClient
    private let configuration: PocketRootAgentConfiguration
    private let toolsByName: [String: PocketRootAgentTool]
    private let toolDefinitions: [PocketRootAgentToolDefinition]
    private var runInProgress = false

    public init(
        modelClient: any PocketRootAgentModelClient,
        configuration: PocketRootAgentConfiguration,
        tools: [PocketRootAgentTool] = []
    ) throws {
        try Self.validate(configuration: configuration, tools: tools)
        self.modelClient = modelClient
        self.configuration = configuration
        toolsByName = Dictionary(
            uniqueKeysWithValues: tools.map { ($0.definition.name, $0) }
        )
        toolDefinitions = tools.map(\.definition)
    }

    public func run(userInput: String) async throws -> PocketRootAgentRunResult {
        guard !runInProgress else {
            throw PocketRootAgentError.runAlreadyInProgress
        }
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PocketRootAgentError.invalidUserInput(
                "user input must not be empty."
            )
        }
        guard userInput.utf8.count <= configuration.maximumUserInputBytes else {
            throw PocketRootAgentError.userInputLimitExceeded(
                configuration.maximumUserInputBytes
            )
        }

        runInProgress = true
        defer {
            runInProgress = false
        }

        var input = PocketRootAgentModelInput.user(userInput)
        var previousResponseID: String?
        var seenResponseIDs = Set<String>()
        var seenToolCallIDs = Set<String>()
        var totalToolCalls = 0

        for turn in 1 ... configuration.maximumTurns {
            try Task.checkCancellation()
            let response = try await modelClient.createResponse(
                PocketRootAgentModelRequest(
                    instructions: configuration.instructions,
                    input: input,
                    tools: toolDefinitions,
                    previousResponseID: previousResponseID
                )
            )
            try Task.checkCancellation()

            guard !response.id.isEmpty else {
                throw PocketRootAgentError.invalidModelResponse(
                    "response ID must not be empty."
                )
            }
            guard seenResponseIDs.insert(response.id).inserted else {
                throw PocketRootAgentError.invalidModelResponse(
                    "response ID '\(response.id)' was repeated."
                )
            }
            guard response.outputText.utf8.count
                <= configuration.maximumModelOutputBytes
            else {
                throw PocketRootAgentError.modelOutputLimitExceeded(
                    configuration.maximumModelOutputBytes
                )
            }

            if response.toolCalls.isEmpty {
                guard !response.outputText.isEmpty else {
                    throw PocketRootAgentError.invalidModelResponse(
                        "a response without tool calls must include output text."
                    )
                }
                return PocketRootAgentRunResult(
                    finalOutput: response.outputText,
                    responseID: response.id,
                    turnCount: turn,
                    toolCallCount: totalToolCalls
                )
            }

            guard turn < configuration.maximumTurns else {
                throw PocketRootAgentError.maximumTurnsExceeded(
                    configuration.maximumTurns
                )
            }

            totalToolCalls += response.toolCalls.count
            guard totalToolCalls <= configuration.maximumToolCalls else {
                throw PocketRootAgentError.maximumToolCallsExceeded(
                    configuration.maximumToolCalls
                )
            }

            // Validate the complete batch before the first handler runs. A
            // malformed later call must not leave earlier side effects behind.
            var validatedCallIDs = seenToolCallIDs
            for call in response.toolCalls {
                try Self.validate(
                    call: call,
                    maximumArgumentsBytes: configuration.maximumToolArgumentsBytes,
                    seenIDs: &validatedCallIDs
                )
            }
            seenToolCallIDs = validatedCallIDs

            var outputs: [PocketRootAgentToolOutput] = []
            outputs.reserveCapacity(response.toolCalls.count)

            for call in response.toolCalls {
                try Task.checkCancellation()

                let output: String
                if let tool = toolsByName[call.name] {
                    do {
                        output = try await tool.execute(call)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        output = Self.failureOutput(
                            "Tool '\(call.name)' failed: \(error.localizedDescription)"
                        )
                    }
                } else {
                    output = Self.failureOutput(
                        "Unknown tool '\(call.name)'."
                    )
                }
                try Task.checkCancellation()

                guard output.utf8.count <= configuration.maximumToolOutputBytes else {
                    throw PocketRootAgentError.toolOutputLimitExceeded(
                        tool: call.name,
                        limit: configuration.maximumToolOutputBytes
                    )
                }
                outputs.append(
                    PocketRootAgentToolOutput(callID: call.id, output: output)
                )
            }

            previousResponseID = response.id
            input = .toolOutputs(outputs)
        }

        throw PocketRootAgentError.maximumTurnsExceeded(
            configuration.maximumTurns
        )
    }

    private static func validate(
        configuration: PocketRootAgentConfiguration,
        tools: [PocketRootAgentTool]
    ) throws {
        guard configuration.maximumTurns > 0 else {
            throw PocketRootAgentError.invalidConfiguration(
                "maximumTurns must be greater than zero."
            )
        }
        guard configuration.maximumToolCalls >= 0 else {
            throw PocketRootAgentError.invalidConfiguration(
                "maximumToolCalls must not be negative."
            )
        }
        guard configuration.maximumUserInputBytes > 0 else {
            throw PocketRootAgentError.invalidConfiguration(
                "maximumUserInputBytes must be greater than zero."
            )
        }
        guard configuration.maximumModelOutputBytes > 0 else {
            throw PocketRootAgentError.invalidConfiguration(
                "maximumModelOutputBytes must be greater than zero."
            )
        }
        guard configuration.maximumToolArgumentsBytes > 0 else {
            throw PocketRootAgentError.invalidConfiguration(
                "maximumToolArgumentsBytes must be greater than zero."
            )
        }
        guard configuration.maximumToolOutputBytes > 0 else {
            throw PocketRootAgentError.invalidConfiguration(
                "maximumToolOutputBytes must be greater than zero."
            )
        }

        var names = Set<String>()
        for tool in tools {
            let definition = tool.definition
            guard Self.isValidToolName(definition.name) else {
                throw PocketRootAgentError.invalidToolDefinition(
                    "tool names must contain 1...64 ASCII letters, digits, '_' or '-'."
                )
            }
            guard names.insert(definition.name).inserted else {
                throw PocketRootAgentError.invalidToolDefinition(
                    "duplicate tool name '\(definition.name)'."
                )
            }
            guard !definition.description.isEmpty else {
                throw PocketRootAgentError.invalidToolDefinition(
                    "tool '\(definition.name)' must have a description."
                )
            }
            guard let schemaData = definition.parametersJSONSchema.data(using: .utf8),
                  let schema = try? JSONSerialization.jsonObject(with: schemaData),
                  schema is [String: Any]
            else {
                throw PocketRootAgentError.invalidToolDefinition(
                    "tool '\(definition.name)' must have an object JSON schema."
                )
            }
        }
    }

    private static func validate(
        call: PocketRootAgentToolCall,
        maximumArgumentsBytes: Int,
        seenIDs: inout Set<String>
    ) throws {
        guard !call.id.isEmpty else {
            throw PocketRootAgentError.invalidModelResponse(
                "tool call ID must not be empty."
            )
        }
        guard !call.name.isEmpty else {
            throw PocketRootAgentError.invalidModelResponse(
                "tool call name must not be empty."
            )
        }
        guard seenIDs.insert(call.id).inserted else {
            throw PocketRootAgentError.duplicateToolCallID(call.id)
        }
        guard call.argumentsJSON.utf8.count <= maximumArgumentsBytes else {
            throw PocketRootAgentError.toolArgumentsLimitExceeded(
                tool: call.name,
                limit: maximumArgumentsBytes
            )
        }
        guard let argumentsData = call.argumentsJSON.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(
                  with: argumentsData
              ),
              arguments is [String: Any]
        else {
            throw PocketRootAgentError.invalidModelResponse(
                "tool call '\(call.id)' arguments must be a JSON object."
            )
        }
    }

    private static func isValidToolName(_ name: String) -> Bool {
        guard 1 ... 64 ~= name.utf8.count else {
            return false
        }
        return name.utf8.allSatisfy { byte in
            switch byte {
            case 45, 48 ... 57, 65 ... 90, 95, 97 ... 122:
                return true
            default:
                return false
            }
        }
    }

    private static func failureOutput(_ message: String) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: ["ok": false, "error": message],
            options: [.sortedKeys]
        )
        return data.map { String(decoding: $0, as: UTF8.self) }
            ?? #"{"error":"tool failed","ok":false}"#
    }
}
