@available(macOS 13.0, *)
actor PlaceholderLinuxRuntime: LinuxRuntime {
    private(set) var state: PocketRootRuntimeState = .idle

    func boot(configuration: PocketRootConfiguration) async throws {
        throw PocketRootError.unsupportedOperation(
            "Linux Runtime has not been integrated yet."
        )
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        throw PocketRootError.runtimeNotBooted
    }

    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        throw PocketRootError.runtimeNotBooted
    }

    func shutdown() async throws {
        state = .idle
    }
}
