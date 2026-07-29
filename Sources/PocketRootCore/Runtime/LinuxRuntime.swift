@available(macOS 13.0, *)
package protocol LinuxRuntime: Sendable {
    var state: PocketRootRuntimeState { get async }

    func boot(configuration: PocketRootConfiguration) async throws
    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult
    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession
    func renameItem(
        at sourcePath: String,
        to destinationPath: String,
        timeout: Duration
    ) async throws
    func shutdown() async throws
}

@available(macOS 13.0, *)
extension LinuxRuntime {
    package func renameItem(
        at sourcePath: String,
        to destinationPath: String,
        timeout: Duration
    ) async throws {
        throw PocketRootError.unsupportedOperation(
            "This Linux Runtime does not support native guest filesystem rename."
        )
    }
}
