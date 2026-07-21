@available(macOS 13.0, *)
public actor PocketRootSystem {
    public static let shared = PocketRootSystem()

    public let configuration: PocketRootConfiguration
    public private(set) var state: PocketRootRuntimeState = .idle

    private let coordinator: RuntimeCoordinator

    public init(configuration: PocketRootConfiguration = PocketRootConfiguration()) {
        self.configuration = configuration
        coordinator = RuntimeCoordinator(runtime: PlaceholderLinuxRuntime())
    }

    init(
        configuration: PocketRootConfiguration = PocketRootConfiguration(),
        runtime: any LinuxRuntime
    ) {
        self.configuration = configuration
        coordinator = RuntimeCoordinator(runtime: runtime)
    }

    public func boot() async throws {
        do {
            try await coordinator.boot(configuration: configuration)
            state = await coordinator.currentState()
        } catch {
            state = await coordinator.currentState()
            throw error
        }
    }

    public func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        try await coordinator.execute(request)
    }

    public func shutdown() async throws {
        try await coordinator.shutdown()
        state = await coordinator.currentState()
    }
}
