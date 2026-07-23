public struct PocketRootOpenAIBearerTokenProvider: Sendable {
    private let loadToken: @Sendable () async throws -> String

    public init(
        loadToken: @escaping @Sendable () async throws -> String
    ) {
        self.loadToken = loadToken
    }

    func token() async throws -> String {
        try await loadToken()
    }
}
