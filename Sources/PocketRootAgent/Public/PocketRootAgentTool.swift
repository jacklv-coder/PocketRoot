import Foundation

public struct PocketRootAgentToolDefinition: Sendable, Equatable {
    public let name: String
    public let description: String
    public let parametersJSONSchema: String

    public init(
        name: String,
        description: String,
        parametersJSONSchema: String
    ) {
        self.name = name
        self.description = description
        self.parametersJSONSchema = parametersJSONSchema
    }
}

public struct PocketRootAgentToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }

    public func decodeArguments<Value: Decodable>(
        _ type: Value.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        try decoder.decode(type, from: Data(argumentsJSON.utf8))
    }
}

public struct PocketRootAgentToolOutput: Sendable, Equatable {
    public let callID: String
    public let output: String

    public init(callID: String, output: String) {
        self.callID = callID
        self.output = output
    }
}

@available(macOS 13.0, *)
public struct PocketRootAgentTool: Sendable {
    public let definition: PocketRootAgentToolDefinition

    private let preflightHandler: @Sendable (
        PocketRootAgentToolCall
    ) throws -> Void
    private let handler: @Sendable (PocketRootAgentToolCall) async throws -> String

    public init(
        definition: PocketRootAgentToolDefinition,
        preflight: @escaping @Sendable (
            PocketRootAgentToolCall
        ) throws -> Void = { _ in },
        handler: @escaping @Sendable (
            PocketRootAgentToolCall
        ) async throws -> String
    ) {
        self.definition = definition
        preflightHandler = preflight
        self.handler = handler
    }

    func preflight(_ call: PocketRootAgentToolCall) throws {
        try preflightHandler(call)
    }

    func execute(_ call: PocketRootAgentToolCall) async throws -> String {
        try await handler(call)
    }
}
