protocol RootFSProvider: Sendable {
    func prepareRootFS(version: String) async throws -> RootFSMetadata
}
