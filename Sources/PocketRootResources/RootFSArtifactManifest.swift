import Foundation

/// Immutable metadata for a distributable iSH fakefs archive.
public struct PocketRootRootFSArtifactManifest: Sendable, Equatable {
    public enum Architecture: String, Sendable, Equatable {
        case arm64
    }

    public enum Format: String, Sendable, Equatable {
        case fakeFSTarGzip = "fakefs tar.gz"
    }

    /// The RootFS published with IshEmbed v0.3.3.
    public static let ishEmbedV0_3_3 = PocketRootRootFSArtifactManifest(
        version: "v0.3.3",
        architecture: .arm64,
        format: .fakeFSTarGzip,
        downloadURL: URL(
            string: "https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/fs.tar.gz"
        )!,
        sha256: "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4",
        archiveByteCount: 6_581_376,
        expandedArchiveByteCount: 18_838_016
    )

    public let version: String
    public let architecture: Architecture
    public let format: Format
    public let downloadURL: URL
    public let sha256: String
    public let archiveByteCount: UInt64?
    public let expandedArchiveByteCount: UInt64?

    public init(
        version: String,
        architecture: Architecture,
        format: Format,
        downloadURL: URL,
        sha256: String,
        archiveByteCount: UInt64? = nil,
        expandedArchiveByteCount: UInt64? = nil
    ) {
        self.version = version
        self.architecture = architecture
        self.format = format
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.archiveByteCount = archiveByteCount
        self.expandedArchiveByteCount = expandedArchiveByteCount
    }
}
