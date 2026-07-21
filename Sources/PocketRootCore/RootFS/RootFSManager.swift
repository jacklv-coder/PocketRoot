@available(macOS 13.0, *)
actor RootFSManager {
    private let provider: (any RootFSProvider)?
    private(set) var metadata: RootFSMetadata?

    init(provider: (any RootFSProvider)? = nil) {
        self.provider = provider
    }

    func prepareRootFS(
        version: String = PocketRootDefaults.rootFSVersion
    ) async throws -> RootFSMetadata {
        guard let provider else {
            throw PocketRootError.unsupportedOperation(
                "RootFS provider has not been integrated yet."
            )
        }

        let preparedMetadata = try await provider.prepareRootFS(version: version)
        metadata = preparedMetadata
        return preparedMetadata
    }

    func reset() {
        metadata = nil
    }
}
