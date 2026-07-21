@available(macOS 13.0, *)
public struct PocketRootCommandRequest: Sendable, Equatable {
    public let command: String
    public let workingDirectory: String
    public let environment: [String: String]
    public let timeout: Duration
    public let mergeStandardError: Bool

    public init(
        command: String,
        workingDirectory: String = "/root",
        environment: [String: String] = [:],
        timeout: Duration = .seconds(30),
        mergeStandardError: Bool = false
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
        self.mergeStandardError = mergeStandardError
    }
}
