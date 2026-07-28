public struct PocketRootSessionConfiguration: Sendable, Equatable {
    public let shell: String
    public let shellArguments: [String]
    public let workingDirectory: String
    public let environment: [String: String]
    public let initialTerminalSize: PocketRootTerminalSize

    public init(
        shell: String = "/bin/sh",
        shellArguments: [String] = ["-il"],
        workingDirectory: String = "/root",
        environment: [String: String] = [:],
        initialTerminalSize: PocketRootTerminalSize = .init()
    ) {
        self.shell = shell
        self.shellArguments = shellArguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.initialTerminalSize = initialTerminalSize
    }
}

/// The character-cell and optional pixel size of an interactive terminal.
public struct PocketRootTerminalSize: Sendable, Equatable {
    public let rows: UInt16
    public let columns: UInt16
    public let pixelWidth: UInt16
    public let pixelHeight: UInt16

    public init(
        rows: UInt16 = 24,
        columns: UInt16 = 80,
        pixelWidth: UInt16 = 0,
        pixelHeight: UInt16 = 0
    ) {
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
