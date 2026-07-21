import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

public enum PocketRootRootFSValidationError: Error, Sendable, Equatable {
    case archiveUnavailable(String)
    case archiveSizeMismatch(expected: UInt64, actual: UInt64)
    case sha256Unavailable
    case sha256Mismatch(expected: String, actual: String)
    case invalidFakeFS(path: String, reason: String)
}

extension PocketRootRootFSValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .archiveUnavailable(let path):
            return "The RootFS archive is not a readable local file: \(path)"
        case .archiveSizeMismatch(let expected, let actual):
            return "RootFS archive size mismatch. Expected \(expected) bytes, got \(actual)."
        case .sha256Unavailable:
            return "SHA-256 validation requires CryptoKit on this platform."
        case .sha256Mismatch(let expected, let actual):
            return "RootFS SHA-256 mismatch. Expected \(expected), got \(actual)."
        case .invalidFakeFS(let path, let reason):
            return "Invalid materialized fakefs at \(path): \(reason)"
        }
    }
}

/// Validates local RootFS artifacts without downloading or extracting them.
public enum PocketRootRootFSValidator {
    public static var supportsSHA256Validation: Bool {
        #if canImport(CryptoKit)
        true
        #else
        false
        #endif
    }

    /// Verifies that a local archive matches the digest pinned by its manifest.
    public static func validateArchive(
        at archiveURL: URL,
        against manifest: PocketRootRootFSArtifactManifest = .ishEmbedV0_3_3
    ) throws {
        var isDirectory: ObjCBool = false
        guard archiveURL.isFileURL,
              FileManager.default.fileExists(
                atPath: archiveURL.path,
                isDirectory: &isDirectory
              ),
              !isDirectory.boolValue
        else {
            throw PocketRootRootFSValidationError.archiveUnavailable(archiveURL.path)
        }
        let archiveValues = try archiveURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard archiveValues.isRegularFile == true,
              archiveValues.isSymbolicLink != true
        else {
            throw PocketRootRootFSValidationError.archiveUnavailable(archiveURL.path)
        }

        if let expectedByteCount = manifest.archiveByteCount {
            let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
            let actualByteCount = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard actualByteCount == expectedByteCount else {
                throw PocketRootRootFSValidationError.archiveSizeMismatch(
                    expected: expectedByteCount,
                    actual: actualByteCount
                )
            }
        }

        let actualDigest = try sha256HexDigest(of: archiveURL)
        let expectedDigest = manifest.sha256.lowercased()
        guard actualDigest == expectedDigest else {
            throw PocketRootRootFSValidationError.sha256Mismatch(
                expected: expectedDigest,
                actual: actualDigest
            )
        }
    }

    /// Verifies the minimum directory layout required by IshEmbed fakefs.
    public static func validateMaterializedFakeFS(at rootURL: URL) throws {
        var rootIsDirectory: ObjCBool = false
        guard rootURL.isFileURL,
              FileManager.default.fileExists(
                atPath: rootURL.path,
                isDirectory: &rootIsDirectory
              ),
              rootIsDirectory.boolValue
        else {
            throw invalidFakeFS(rootURL, reason: "the root path is not a directory")
        }
        let rootValues = try rootURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw invalidFakeFS(rootURL, reason: "the root path must be a real directory")
        }

        let metadataURL = rootURL.appendingPathComponent("meta.db", isDirectory: false)
        var metadataIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: metadataURL.path,
            isDirectory: &metadataIsDirectory
        ), !metadataIsDirectory.boolValue else {
            throw invalidFakeFS(rootURL, reason: "meta.db is missing or is not a file")
        }
        let metadataValues = try metadataURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard metadataValues.isRegularFile == true,
              metadataValues.isSymbolicLink != true
        else {
            throw invalidFakeFS(rootURL, reason: "meta.db must be a real regular file")
        }

        let dataURL = rootURL.appendingPathComponent("data", isDirectory: true)
        var dataIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: dataURL.path,
            isDirectory: &dataIsDirectory
        ), dataIsDirectory.boolValue else {
            throw invalidFakeFS(rootURL, reason: "data is missing or is not a directory")
        }
        let dataValues = try dataURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard dataValues.isDirectory == true, dataValues.isSymbolicLink != true else {
            throw invalidFakeFS(rootURL, reason: "data must be a real directory")
        }
    }

    private static func invalidFakeFS(
        _ rootURL: URL,
        reason: String
    ) -> PocketRootRootFSValidationError {
        .invalidFakeFS(path: rootURL.path, reason: reason)
    }

    private static func sha256HexDigest(of archiveURL: URL) throws -> String {
        #if canImport(CryptoKit)
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: archiveURL)
        } catch {
            throw PocketRootRootFSValidationError.archiveUnavailable(archiveURL.path)
        }
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        while let chunk = try fileHandle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { byte in
            String(format: "%02x", byte)
        }.joined()
        #else
        throw PocketRootRootFSValidationError.sha256Unavailable
        #endif
    }
}
