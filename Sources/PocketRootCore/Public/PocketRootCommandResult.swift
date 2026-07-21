import Foundation

public struct PocketRootCommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data
    public let timedOut: Bool

    public init(
        exitCode: Int32,
        standardOutput: Data = Data(),
        standardError: Data = Data(),
        timedOut: Bool = false
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
    }

    public var stdout: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    public var stderr: String {
        String(decoding: standardError, as: UTF8.self)
    }
}
