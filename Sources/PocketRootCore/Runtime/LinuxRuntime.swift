@available(macOS 13.0, *)
protocol LinuxRuntime: Sendable {
    var state: PocketRootRuntimeState { get async }

    func boot(configuration: PocketRootConfiguration) async throws
    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult
    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession
    func shutdown() async throws
}
