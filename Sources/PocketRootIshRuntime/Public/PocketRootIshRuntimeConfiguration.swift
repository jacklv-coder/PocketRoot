import Foundation

/// The guest identity PocketRoot must observe before reporting the runtime as ready.
public struct PocketRootIshRuntimeHealthCheckConfiguration: Sendable, Equatable {
    public let expectedArchitecture: String
    public let expectedOperatingSystemID: String
    public let expectedOperatingSystemVersionID: String?
    public let timeout: Duration

    public init(
        expectedArchitecture: String = "aarch64",
        expectedOperatingSystemID: String = "alpine",
        expectedOperatingSystemVersionID: String? = nil,
        timeout: Duration = .seconds(5)
    ) {
        self.expectedArchitecture = expectedArchitecture
        self.expectedOperatingSystemID = expectedOperatingSystemID
        self.expectedOperatingSystemVersionID = expectedOperatingSystemVersionID
        self.timeout = timeout
    }

    /// The default identity gate for an Alpine ARM64 guest.
    public static let alpineARM64 = Self()

    /// The identity gate for the RootFS shipped with the audited IshEmbed v0.3.3 release.
    public static let ishEmbedV0_3_3 = Self(
        expectedOperatingSystemVersionID: "3.19.1"
    )
}

/// Configuration for the iSH-backed runtime adapter.
public struct PocketRootIshRuntimeConfiguration: Sendable, Equatable {
    /// A materialized iSH fakefs directory containing meta.db and data/.
    public let rootFSURL: URL
    /// An absolute guest path. Canonical aliases are accepted by the post-boot gate.
    public let workDirectory: String
    public let supervisorGuestPath: String?
    public let kernelLogFileDescriptor: Int32
    public let maximumStandardOutputBytes: Int
    public let maximumStandardErrorBytes: Int
    public let healthCheck: PocketRootIshRuntimeHealthCheckConfiguration

    public init(
        rootFSURL: URL,
        workDirectory: String = "/",
        supervisorGuestPath: String? = nil,
        kernelLogFileDescriptor: Int32 = -1,
        maximumStandardOutputBytes: Int = 8 * 1_024 * 1_024,
        maximumStandardErrorBytes: Int = 4 * 1_024 * 1_024,
        healthCheck: PocketRootIshRuntimeHealthCheckConfiguration = .alpineARM64
    ) {
        self.rootFSURL = rootFSURL
        self.workDirectory = workDirectory
        self.supervisorGuestPath = supervisorGuestPath
        self.kernelLogFileDescriptor = kernelLogFileDescriptor
        self.maximumStandardOutputBytes = maximumStandardOutputBytes
        self.maximumStandardErrorBytes = maximumStandardErrorBytes
        self.healthCheck = healthCheck
    }
}
