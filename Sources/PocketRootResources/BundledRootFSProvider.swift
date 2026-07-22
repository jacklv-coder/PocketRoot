import Foundation

public enum PocketRootBundledRootFSProviderError: Error, Sendable, Equatable {
    case resourceMissing(
        name: String,
        resourceExtension: String,
        subdirectory: String?
    )
}

extension PocketRootBundledRootFSProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .resourceMissing(let name, let resourceExtension, let subdirectory):
            let location = subdirectory.map { " in \($0)" } ?? ""
            return "Bundled RootFS resource \(name).\(resourceExtension) is missing\(location)."
        }
    }
}

/// Locates a RootFS archive shipped in the PocketRootResources bundle.
///
/// No archive is included while compliance review remains open, so
/// `rootFSArchiveURL()` returns `nil` until a reviewed, versioned RootFS is
/// deliberately added to the package resources.
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

    /// Installs the bundled archive with the supplied verified installer.
    /// PocketRoot currently ships no archive, so callers receive a typed error
    /// until compliance-reviewed assets are deliberately added.
    public func prepareRootFS(
        using installer: PocketRootRootFSInstaller
    ) async throws -> PocketRootRootFSInstallation {
        guard let archiveURL = rootFSArchiveURL() else {
            throw PocketRootBundledRootFSProviderError.resourceMissing(
                name: resourceName,
                resourceExtension: resourceExtension,
                subdirectory: subdirectory
            )
        }
        return try await installer.prepareArchive(at: archiveURL)
    }
}

typealias BundledRootFSProvider = PocketRootBundledRootFSProvider
