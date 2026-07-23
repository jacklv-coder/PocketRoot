import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13.0, *)
public struct PocketRootOpenAIResponsesClient: Sendable {
    private let configuration: PocketRootOpenAIResponsesConfiguration
    private let tokenProvider: PocketRootOpenAIBearerTokenProvider
    private let httpClient: any PocketRootOpenAIHTTPClient

    public init(
        configuration: PocketRootOpenAIResponsesConfiguration,
        tokenProvider: PocketRootOpenAIBearerTokenProvider
    ) throws {
        try Self.validate(configuration)
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        httpClient = PocketRootURLSessionOpenAIHTTPClient()
    }

    init(
        configuration: PocketRootOpenAIResponsesConfiguration,
        tokenProvider: PocketRootOpenAIBearerTokenProvider,
        httpClient: any PocketRootOpenAIHTTPClient
    ) throws {
        try Self.validate(configuration)
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
    }

    private static func validate(
        _ configuration: PocketRootOpenAIResponsesConfiguration
    ) throws {
        guard configuration.endpoint.scheme?.lowercased() == "https" else {
            throw PocketRootOpenAIResponsesError.invalidConfiguration(
                "endpoint must use HTTPS."
            )
        }
        guard configuration.endpoint.host != nil,
              configuration.endpoint.user == nil,
              configuration.endpoint.password == nil,
              configuration.endpoint.query == nil,
              configuration.endpoint.fragment == nil
        else {
            throw PocketRootOpenAIResponsesError.invalidConfiguration(
                "endpoint must be an absolute URL without credentials, query, or fragment."
            )
        }

        let model = configuration.model.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !model.isEmpty,
              model.utf8.count <= 256,
              model == configuration.model
        else {
            throw PocketRootOpenAIResponsesError.invalidConfiguration(
                "model must contain 1...256 UTF-8 bytes without surrounding whitespace."
            )
        }
        guard configuration.requestTimeout.isFinite,
              configuration.requestTimeout > 0
        else {
            throw PocketRootOpenAIResponsesError.invalidConfiguration(
                "requestTimeout must be finite and greater than zero."
            )
        }
        guard configuration.maximumRequestBodyBytes > 0 else {
            throw PocketRootOpenAIResponsesError.invalidConfiguration(
                "maximumRequestBodyBytes must be greater than zero."
            )
        }
        guard configuration.maximumResponseBodyBytes > 0 else {
            throw PocketRootOpenAIResponsesError.invalidConfiguration(
                "maximumResponseBodyBytes must be greater than zero."
            )
        }
    }
}

@available(macOS 13.0, *)
extension PocketRootOpenAIResponsesClient: PocketRootAgentModelClient {
    public func createResponse(
        _ request: PocketRootAgentModelRequest
    ) async throws -> PocketRootAgentModelResponse {
        try Task.checkCancellation()

        let token: String
        do {
            token = try await tokenProvider.token()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw PocketRootOpenAIResponsesError.credentialUnavailable
        }
        guard Self.isValidBearerToken(token) else {
            throw PocketRootOpenAIResponsesError.invalidCredential
        }

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.requestTimeout
        urlRequest.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        let requestBody = try Self.encodeRequest(
            request,
            model: configuration.model
        )
        guard requestBody.count <= configuration.maximumRequestBodyBytes else {
            throw PocketRootOpenAIResponsesError.requestBodyLimitExceeded(
                configuration.maximumRequestBodyBytes
            )
        }
        urlRequest.httpBody = requestBody

        let result: PocketRootOpenAIHTTPResult
        do {
            try Task.checkCancellation()
            result = try await httpClient.send(
                urlRequest,
                maximumResponseBodyBytes:
                    configuration.maximumResponseBodyBytes
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PocketRootOpenAIResponsesError {
            throw error
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled {
                throw CancellationError()
            }
            throw PocketRootOpenAIResponsesError.transport(
                error.localizedDescription
            )
        } catch {
            throw PocketRootOpenAIResponsesError.transport(
                "the request could not be completed."
            )
        }
        try Task.checkCancellation()

        guard 200 ... 299 ~= result.response.statusCode else {
            throw Self.apiError(
                statusCode: result.response.statusCode,
                data: result.data,
                credential: token
            )
        }
        return try Self.decodeResponse(
            result.data,
            credential: token
        )
    }

    private static func isValidBearerToken(_ token: String) -> Bool {
        guard !token.isEmpty else {
            return false
        }
        return token.utf8.allSatisfy { byte in
            byte >= 33 && byte <= 126
        }
    }

    private static func encodeRequest(
        _ request: PocketRootAgentModelRequest,
        model: String
    ) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "instructions": request.instructions,
            // previous_response_id needs server-side response state. Make
            // retention explicit instead of relying on the API default.
            "store": true,
            "input": inputPayload(request.input)
        ]
        if let previousResponseID = request.previousResponseID {
            payload["previous_response_id"] = previousResponseID
        }
        if !request.tools.isEmpty {
            payload["tools"] = try request.tools.map(toolPayload)
        }

        do {
            return try JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys]
            )
        } catch {
            throw PocketRootOpenAIResponsesError.invalidResponse(
                "request data could not be encoded."
            )
        }
    }

    private static func inputPayload(
        _ input: PocketRootAgentModelInput
    ) -> Any {
        switch input {
        case .user(let text):
            return text
        case .toolOutputs(let outputs):
            return outputs.map { output in
                [
                    "type": "function_call_output",
                    "call_id": output.callID,
                    "output": output.output
                ]
            }
        }
    }

    private static func toolPayload(
        _ definition: PocketRootAgentToolDefinition
    ) throws -> [String: Any] {
        guard let data = definition.parametersJSONSchema.data(using: .utf8),
              let schema = try? JSONSerialization.jsonObject(with: data),
              let object = schema as? [String: Any]
        else {
            throw PocketRootOpenAIResponsesError.invalidToolSchema(
                tool: definition.name,
                reason: "parameters must be a JSON object."
            )
        }
        guard object["type"] as? String == "object" else {
            throw PocketRootOpenAIResponsesError.invalidToolSchema(
                tool: definition.name,
                reason: "parameters must declare type 'object'."
            )
        }
        try validateStrictObjects(
            object,
            toolName: definition.name,
            path: "$"
        )
        return [
            "type": "function",
            "name": definition.name,
            "description": definition.description,
            "parameters": object,
            "strict": true
        ]
    }

    private static func validateStrictObjects(
        _ value: Any,
        toolName: String,
        path: String
    ) throws {
        guard let object = value as? [String: Any] else {
            return
        }

        let types: [String]
        if let type = object["type"] as? String {
            types = [type]
        } else if let rawTypes = object["type"] as? [Any] {
            let stringTypes = rawTypes.compactMap { $0 as? String }
            guard !rawTypes.isEmpty,
                  stringTypes.count == rawTypes.count,
                  Set(stringTypes).count == stringTypes.count
            else {
                throw PocketRootOpenAIResponsesError.invalidToolSchema(
                    tool: toolName,
                    reason: "\(path).type must be a string or unique nonempty string array."
                )
            }
            types = stringTypes
        } else if object["type"] != nil {
            throw PocketRootOpenAIResponsesError.invalidToolSchema(
                tool: toolName,
                reason: "\(path).type must be a string or unique nonempty string array."
            )
        } else {
            types = []
        }

        if types.contains("object") {
            guard object["additionalProperties"] as? Bool == false else {
                throw PocketRootOpenAIResponsesError.invalidToolSchema(
                    tool: toolName,
                    reason: "\(path) must set additionalProperties to false."
                )
            }
            guard let rawProperties = object["properties"] else {
                throw PocketRootOpenAIResponsesError.invalidToolSchema(
                    tool: toolName,
                    reason: "\(path).properties must be an object."
                )
            }
            guard let properties = rawProperties as? [String: Any] else {
                throw PocketRootOpenAIResponsesError.invalidToolSchema(
                    tool: toolName,
                    reason: "\(path).properties must be an object."
                )
            }
            guard let rawRequired = object["required"] as? [Any],
                  rawRequired.allSatisfy({ $0 is String })
            else {
                throw PocketRootOpenAIResponsesError.invalidToolSchema(
                    tool: toolName,
                    reason: "\(path).required must be a string array."
                )
            }
            let required = rawRequired.compactMap { $0 as? String }
            guard Set(required).count == required.count else {
                throw PocketRootOpenAIResponsesError.invalidToolSchema(
                    tool: toolName,
                    reason: "\(path).required must not contain duplicates."
                )
            }
            guard Set(required) == Set(properties.keys) else {
                throw PocketRootOpenAIResponsesError.invalidToolSchema(
                    tool: toolName,
                    reason: "\(path) must mark every property as required."
                )
            }

            for (name, schema) in properties {
                try validateStrictObjects(
                    schema,
                    toolName: toolName,
                    path: "\(path).properties.\(name)"
                )
            }
        }

        for keyword in [
            "$defs",
            "definitions",
            "patternProperties",
            "dependentSchemas"
        ] {
            if let schemas = object[keyword] as? [String: Any] {
                for (name, schema) in schemas {
                    try validateStrictObjects(
                        schema,
                        toolName: toolName,
                        path: "\(path).\(keyword).\(name)"
                    )
                }
            }
        }
        for keyword in ["allOf", "anyOf", "oneOf", "prefixItems"] {
            if let schemas = object[keyword] as? [Any] {
                for (index, schema) in schemas.enumerated() {
                    try validateStrictObjects(
                        schema,
                        toolName: toolName,
                        path: "\(path).\(keyword)[\(index)]"
                    )
                }
            }
        }
        for keyword in [
            "items",
            "contains",
            "not",
            "if",
            "then",
            "else",
            "propertyNames",
            "unevaluatedProperties"
        ] {
            if let schema = object[keyword] as? [String: Any] {
                try validateStrictObjects(
                    schema,
                    toolName: toolName,
                    path: "\(path).\(keyword)"
                )
            } else if keyword == "items",
                      let schemas = object[keyword] as? [Any]
            {
                for (index, schema) in schemas.enumerated() {
                    try validateStrictObjects(
                        schema,
                        toolName: toolName,
                        path: "\(path).items[\(index)]"
                    )
                }
            }
        }
    }

    private static func apiError(
        statusCode: Int,
        data: Data,
        credential: String
    ) -> PocketRootOpenAIResponsesError {
        let envelope = try? JSONDecoder().decode(
            APIErrorEnvelope.self,
            from: data
        )
        return .api(
            statusCode: statusCode,
            code: redact(envelope?.error.code, credential: credential),
            message: redact(
                envelope?.error.message,
                credential: credential
            ) ?? "The request was rejected."
        )
    }

    private static func decodeResponse(
        _ data: Data,
        credential: String
    ) throws -> PocketRootAgentModelResponse {
        let response: APIResponse
        do {
            response = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw PocketRootOpenAIResponsesError.invalidResponse(
                "response JSON did not match the expected shape."
            )
        }

        guard response.status == "completed" else {
            let detail = redact(
                response.error?.message,
                credential: credential
            )
                ?? redact(
                    response.incompleteDetails?.reason,
                    credential: credential
                )
                ?? "status was '\(response.status)'."
            throw PocketRootOpenAIResponsesError.invalidResponse(detail)
        }

        var textParts: [String] = []
        var toolCalls: [PocketRootAgentToolCall] = []
        for item in response.output {
            switch item.type {
            case "message":
                for content in item.content ?? [] {
                    switch content.type {
                    case "output_text":
                        guard let text = content.text else {
                            throw PocketRootOpenAIResponsesError.invalidResponse(
                                "an output_text item omitted text."
                            )
                        }
                        textParts.append(text)
                    case "refusal":
                        guard let refusal = content.refusal else {
                            throw PocketRootOpenAIResponsesError.invalidResponse(
                                "a refusal item omitted refusal text."
                            )
                        }
                        textParts.append(refusal)
                    default:
                        continue
                    }
                }
            case "function_call":
                guard let callID = item.callID,
                      let name = item.name,
                      let arguments = item.arguments
                else {
                    throw PocketRootOpenAIResponsesError.invalidResponse(
                        "a function_call item omitted call_id, name, or arguments."
                    )
                }
                toolCalls.append(
                    PocketRootAgentToolCall(
                        id: callID,
                        name: name,
                        argumentsJSON: arguments
                    )
                )
            default:
                continue
            }
        }

        return PocketRootAgentModelResponse(
            id: response.id,
            outputText: textParts.joined(),
            toolCalls: toolCalls
        )
    }

    private static func redact(
        _ value: String?,
        credential: String
    ) -> String? {
        value?.replacingOccurrences(
            of: credential,
            with: "[REDACTED]"
        )
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError
}

private struct APIError: Decodable {
    let message: String
    let code: String?
}

private struct APIResponse: Decodable {
    let id: String
    let status: String
    let output: [APIOutputItem]
    let error: APIError?
    let incompleteDetails: APIIncompleteDetails?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case output
        case error
        case incompleteDetails = "incomplete_details"
    }
}

private struct APIIncompleteDetails: Decodable {
    let reason: String?
}

private struct APIOutputItem: Decodable {
    let type: String
    let callID: String?
    let name: String?
    let arguments: String?
    let content: [APIContentItem]?

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case name
        case arguments
        case content
    }
}

private struct APIContentItem: Decodable {
    let type: String
    let text: String?
    let refusal: String?
}
