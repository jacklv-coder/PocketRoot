import Foundation

public enum PocketRootOpenAIResponsesError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidToolSchema(tool: String, reason: String)
    case credentialUnavailable
    case invalidCredential
    case invalidHTTPResponse
    case requestBodyLimitExceeded(Int)
    case responseBodyLimitExceeded(Int)
    case api(statusCode: Int, code: String?, message: String)
    case invalidResponse(String)
    case transport(String)
}

extension PocketRootOpenAIResponsesError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid OpenAI Responses configuration: \(message)"
        case .invalidToolSchema(let tool, let reason):
            return "Invalid schema for OpenAI tool '\(tool)': \(reason)"
        case .credentialUnavailable:
            return "The OpenAI bearer credential could not be loaded."
        case .invalidCredential:
            return "The OpenAI bearer credential is empty or malformed."
        case .invalidHTTPResponse:
            return "The OpenAI endpoint returned an invalid HTTP response."
        case .requestBodyLimitExceeded(let limit):
            return "The OpenAI request exceeded the \(limit)-byte body limit."
        case .responseBodyLimitExceeded(let limit):
            return "The OpenAI response exceeded the \(limit)-byte body limit."
        case .api(let statusCode, let code, let message):
            let codeSuffix = code.map { " (\($0))" } ?? ""
            return "OpenAI API error \(statusCode)\(codeSuffix): \(message)"
        case .invalidResponse(let message):
            return "Invalid OpenAI Responses payload: \(message)"
        case .transport(let message):
            return "OpenAI transport failed: \(message)"
        }
    }
}
