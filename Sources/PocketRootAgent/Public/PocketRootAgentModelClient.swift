public enum PocketRootAgentModelInput: Sendable, Equatable {
    case user(String)
    case toolOutputs([PocketRootAgentToolOutput])
}

public struct PocketRootAgentModelRequest: Sendable, Equatable {
    public let instructions: String
    public let input: PocketRootAgentModelInput
    public let tools: [PocketRootAgentToolDefinition]
    public let previousResponseID: String?

    public init(
        instructions: String,
        input: PocketRootAgentModelInput,
        tools: [PocketRootAgentToolDefinition],
        previousResponseID: String? = nil
    ) {
        self.instructions = instructions
        self.input = input
        self.tools = tools
        self.previousResponseID = previousResponseID
    }
}

public struct PocketRootAgentModelResponse: Sendable, Equatable {
    public let id: String
    public let outputText: String
    public let toolCalls: [PocketRootAgentToolCall]

    public init(
        id: String,
        outputText: String = "",
        toolCalls: [PocketRootAgentToolCall] = []
    ) {
        self.id = id
        self.outputText = outputText
        self.toolCalls = toolCalls
    }
}

@available(macOS 13.0, *)
public protocol PocketRootAgentModelClient: Sendable {
    func createResponse(
        _ request: PocketRootAgentModelRequest
    ) async throws -> PocketRootAgentModelResponse
}
