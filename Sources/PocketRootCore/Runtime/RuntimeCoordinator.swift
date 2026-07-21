@available(macOS 13.0, *)
actor RuntimeCoordinator {
    private let runtime: any LinuxRuntime

    init(runtime: any LinuxRuntime) {
        self.runtime = runtime
    }

    func currentState() async -> PocketRootRuntimeState {
        await runtime.state
    }

    func boot(configuration: PocketRootConfiguration) async throws {
        try await runtime.boot(configuration: configuration)
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        try await runtime.execute(request)
    }

    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        try await runtime.makeSession(configuration: configuration)
    }

    func shutdown() async throws {
        try await runtime.shutdown()
    }
}
