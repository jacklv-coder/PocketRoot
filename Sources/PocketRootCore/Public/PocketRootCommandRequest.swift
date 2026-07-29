import Foundation

@available(macOS 13.0, *)
public struct PocketRootCommandRequest: Sendable, Equatable {
    public let command: String
    public let workingDirectory: String
    public let environment: [String: String]
    public let timeout: Duration
    public let mergeStandardError: Bool
    /// Bounded bytes delivered to the command before stdin is closed.
    ///
    /// Delivery is not transactional: cancellation, timeout, or a transport
    /// error may occur after a prefix was delivered. Use guest-side staging
    /// before an atomic commit when partial input must not become visible.
    public let standardInput: Data

    public init(
        command: String,
        workingDirectory: String = "/root",
        environment: [String: String] = [:],
        timeout: Duration = .seconds(30),
        mergeStandardError: Bool = false,
        standardInput: Data = Data()
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
        self.mergeStandardError = mergeStandardError
        self.standardInput = standardInput
    }
}
