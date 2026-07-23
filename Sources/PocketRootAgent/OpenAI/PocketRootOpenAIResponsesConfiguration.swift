import Foundation

public struct PocketRootOpenAIResponsesConfiguration: Sendable, Equatable {
    public let endpoint: URL
    public let model: String
    public let requestTimeout: TimeInterval
    public let maximumRequestBodyBytes: Int
    public let maximumResponseBodyBytes: Int

    public init(
        model: String,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        requestTimeout: TimeInterval = 60,
        maximumRequestBodyBytes: Int = 2 * 1_024 * 1_024,
        maximumResponseBodyBytes: Int = 2 * 1_024 * 1_024
    ) {
        self.endpoint = endpoint
        self.model = model
        self.requestTimeout = requestTimeout
        self.maximumRequestBodyBytes = maximumRequestBodyBytes
        self.maximumResponseBodyBytes = maximumResponseBodyBytes
    }
}
