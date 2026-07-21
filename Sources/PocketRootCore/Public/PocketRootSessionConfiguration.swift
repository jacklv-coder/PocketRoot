public struct PocketRootSessionConfiguration: Sendable, Equatable {
    public let shell: String
    public let workingDirectory: String
    public let environment: [String: String]

    public init(
        shell: String = "/bin/sh",
        workingDirectory: String = "/root",
        environment: [String: String] = [:]
    ) {
        self.shell = shell
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}
