@available(macOS 13.0, *)
public struct PocketRootLinuxCommandToolConfiguration: Sendable, Equatable {
    public let defaultWorkingDirectory: String
    public let allowedWorkingDirectoryRoots: [String]
    public let allowedEnvironmentNames: Set<String>
    public let maximumTimeoutSeconds: Int
    public let maximumArgumentsBytes: Int
    public let maximumCommandBytes: Int
    public let maximumWorkingDirectoryBytes: Int
    public let maximumEnvironmentEntries: Int
    public let maximumEnvironmentValueBytes: Int
    public let maximumEnvironmentBytes: Int
    public let maximumResultStreamBytes: Int
    public let maximumToolOutputBytes: Int
    public let allowsMergedStandardError: Bool

    public init(
        defaultWorkingDirectory: String = "/root",
        allowedWorkingDirectoryRoots: [String] = ["/root"],
        allowedEnvironmentNames: Set<String> = [],
        maximumTimeoutSeconds: Int = 30,
        maximumArgumentsBytes: Int = 64 * 1_024,
        maximumCommandBytes: Int = 4 * 1_024,
        maximumWorkingDirectoryBytes: Int = 1 * 1_024,
        maximumEnvironmentEntries: Int = 16,
        maximumEnvironmentValueBytes: Int = 4 * 1_024,
        maximumEnvironmentBytes: Int = 8 * 1_024,
        maximumResultStreamBytes: Int = 16 * 1_024,
        maximumToolOutputBytes: Int = 60 * 1_024,
        allowsMergedStandardError: Bool = false
    ) {
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.allowedWorkingDirectoryRoots = allowedWorkingDirectoryRoots
        self.allowedEnvironmentNames = allowedEnvironmentNames
        self.maximumTimeoutSeconds = maximumTimeoutSeconds
        self.maximumArgumentsBytes = maximumArgumentsBytes
        self.maximumCommandBytes = maximumCommandBytes
        self.maximumWorkingDirectoryBytes = maximumWorkingDirectoryBytes
        self.maximumEnvironmentEntries = maximumEnvironmentEntries
        self.maximumEnvironmentValueBytes = maximumEnvironmentValueBytes
        self.maximumEnvironmentBytes = maximumEnvironmentBytes
        self.maximumResultStreamBytes = maximumResultStreamBytes
        self.maximumToolOutputBytes = maximumToolOutputBytes
        self.allowsMergedStandardError = allowsMergedStandardError
    }
}
