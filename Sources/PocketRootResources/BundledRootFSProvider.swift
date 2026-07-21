import Foundation

/// Locates a RootFS archive shipped in the PocketRootResources bundle.
///
/// No archive is included in the bootstrap milestone, so `rootFSArchiveURL()`
/// returns `nil` until a versioned RootFS is added to the package resources.
public struct PocketRootBundledRootFSProvider: Sendable, Equatable {
    public let resourceName: String
    public let resourceExtension: String
    public let subdirectory: String?

    public init(
        resourceName: String = "rootfs",
        resourceExtension: String = "tar.gz",
        subdirectory: String? = nil
    ) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.subdirectory = subdirectory
    }

    public func rootFSArchiveURL() -> URL? {
        Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: subdirectory
        )
    }

    public var isRootFSBundled: Bool {
        rootFSArchiveURL() != nil
    }
}

typealias BundledRootFSProvider = PocketRootBundledRootFSProvider
