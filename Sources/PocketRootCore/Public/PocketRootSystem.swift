@available(macOS 13.0, *)
public actor PocketRootSystem {
    public static let shared = PocketRootSystem()

    public let configuration: PocketRootConfiguration
    /// The latest stable runtime state.
    ///
    /// Each read reconciles with the runtime so failures reported by a
    /// persistent session after `makeSession()` returns are visible without
    /// requiring another system operation.
    public var state: PocketRootRuntimeState {
        get async {
            await refreshPublishedStableState()
            return publishedState
        }
    }

    private let coordinator: RuntimeCoordinator
    private var publishedState: PocketRootRuntimeState = .idle
    private var stateRefreshGeneration: UInt64 = 0

    public init(configuration: PocketRootConfiguration = PocketRootConfiguration()) {
        self.configuration = configuration
        coordinator = RuntimeCoordinator(runtime: PlaceholderLinuxRuntime())
    }

    package init(
        configuration: PocketRootConfiguration = PocketRootConfiguration(),
        runtime: any LinuxRuntime
    ) {
        self.configuration = configuration
        coordinator = RuntimeCoordinator(runtime: runtime)
    }

    public func boot() async throws {
        do {
            try await coordinator.boot(configuration: configuration)
            await refreshPublishedStableState()
        } catch {
            await refreshPublishedStableState()
            throw error
        }
    }

    public func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        do {
            let result = try await coordinator.execute(request)
            await refreshPublishedStableState()
            return result
        } catch {
            await refreshPublishedStableState()
            throw error
        }
    }

    /// Creates a persistent interactive shell session backed by the runtime PTY.
    ///
    /// The system must be booted before this method is called. The returned
    /// session remains owned by the runtime until it exits or is terminated.
    public func makeSession(
        configuration: PocketRootSessionConfiguration = .init()
    ) async throws -> any PocketRootSession {
        do {
            let session = try await coordinator.makeSession(
                configuration: configuration
            )
            await refreshPublishedStableState()
            return session
        } catch {
            await refreshPublishedStableState()
            throw error
        }
    }

    public func shutdown() async throws {
        do {
            try await coordinator.shutdown()
            await refreshPublishedStableState()
        } catch {
            await refreshPublishedStableState()
            throw error
        }
    }

    private func refreshPublishedStableState() async {
        stateRefreshGeneration &+= 1
        let refreshGeneration = stateRefreshGeneration
        let currentState = await coordinator.currentState()

        // Actor reentrancy lets a newer operation observe and publish a later
        // runtime state while this lookup is suspended. Never let the older
        // snapshot overwrite that newer publication when it eventually resumes.
        guard refreshGeneration == stateRefreshGeneration else {
            return
        }

        switch currentState {
        case .idle, .ready, .terminated, .failed:
            publishedState = currentState
        case .preparingRootFS, .booting, .shuttingDown:
            // A lifecycle call can be suspended while this actor admits a
            // reentrant command. Keep transient runtime states internal; the
            // owning lifecycle call publishes its stable result when it ends.
            break
        }
    }
}
