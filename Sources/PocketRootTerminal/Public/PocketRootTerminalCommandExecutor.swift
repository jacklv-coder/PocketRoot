import PocketRootCore

/// The bounded command capability required by the lightweight terminal UI.
///
/// `PocketRootSystem` conforms directly. Hosts can also provide a small adapter
/// for tests or for an application-owned runtime coordinator. Executors are
/// reference types so SwiftUI can distinguish a replaced backend from a theme
/// update without restarting a stable command session.
@available(macOS 13.0, *)
public protocol PocketRootTerminalCommandExecutor: AnyObject, Sendable {
    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult
}

/// The native no-replace rename capability used by the Files UI.
@available(macOS 13.0, *)
public protocol PocketRootFileRenameExecutor: AnyObject, Sendable {
    func renameItem(
        at sourcePath: String,
        to destinationPath: String,
        timeout: Duration
    ) async throws
}

@available(macOS 13.0, *)
extension PocketRootSystem:
    PocketRootTerminalCommandExecutor,
    PocketRootFileRenameExecutor
{}
