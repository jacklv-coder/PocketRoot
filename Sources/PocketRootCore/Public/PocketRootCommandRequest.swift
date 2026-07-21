@available(macOS 13.0, *)
public struct PocketRootCommandRequest: Sendable, Equatable {
    public let command: String
    public let workingDirectory: String
    public let timeout: Duration

    public init(
        command: String,
        workingDirectory: String = "/root",
        timeout: Duration = .seconds(30)
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }
}
