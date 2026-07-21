@available(macOS 13.0, *)
public struct PocketRootConfiguration: Sendable, Equatable {
    public let rootFSVersion: String
    public let defaultWorkingDirectory: String
    public let commandTimeout: Duration

    public init(
        rootFSVersion: String = PocketRootDefaults.rootFSVersion,
        defaultWorkingDirectory: String = "/root",
        commandTimeout: Duration = PocketRootDefaults.commandTimeout
    ) {
        self.rootFSVersion = rootFSVersion
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.commandTimeout = commandTimeout
    }
}
