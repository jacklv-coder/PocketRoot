import Foundation

/// Configuration for the iSH-backed runtime adapter.
public struct PocketRootIshRuntimeConfiguration: Sendable, Equatable {
    /// A materialized iSH fakefs directory containing meta.db and data/.
    public let rootFSURL: URL
    public let workDirectory: String
    public let supervisorGuestPath: String?
    public let kernelLogFileDescriptor: Int32
    public let maximumStandardOutputBytes: Int
    public let maximumStandardErrorBytes: Int

    public init(
        rootFSURL: URL,
        workDirectory: String = "/",
        supervisorGuestPath: String? = nil,
        kernelLogFileDescriptor: Int32 = -1,
        maximumStandardOutputBytes: Int = 8 * 1_024 * 1_024,
        maximumStandardErrorBytes: Int = 4 * 1_024 * 1_024
    ) {
        self.rootFSURL = rootFSURL
        self.workDirectory = workDirectory
        self.supervisorGuestPath = supervisorGuestPath
        self.kernelLogFileDescriptor = kernelLogFileDescriptor
        self.maximumStandardOutputBytes = maximumStandardOutputBytes
        self.maximumStandardErrorBytes = maximumStandardErrorBytes
    }
}
