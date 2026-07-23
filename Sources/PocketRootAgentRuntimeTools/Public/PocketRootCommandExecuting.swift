import PocketRootCore

@available(macOS 13.0, *)
public protocol PocketRootCommandExecuting: Sendable {
    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult
}

@available(macOS 13.0, *)
extension PocketRootSystem: PocketRootCommandExecuting {}
