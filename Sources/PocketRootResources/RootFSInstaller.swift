import Darwin
import Foundation

public struct PocketRootRootFSInstallation: Sendable, Equatable {
    public let version: String
    public let rootFSURL: URL
    public let reusedExistingInstallation: Bool

    public init(
        version: String,
        rootFSURL: URL,
        reusedExistingInstallation: Bool
    ) {
        self.version = version
        self.rootFSURL = rootFSURL
        self.reusedExistingInstallation = reusedExistingInstallation
    }
}

public enum PocketRootRootFSInstallationError: Error, Sendable, Equatable {
    case invalidBaseDirectory(String)
    case invalidVersion(String)
    case archiveCopyLimitExceeded(UInt64)
    case insufficientStorage(requiredBytes: UInt64, availableBytes: UInt64)
    case missingArchiveRoot(String)
    case installationFailed(String)
}

extension PocketRootRootFSInstallationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseDirectory(let path):
            return "The RootFS installation base must be a local directory URL: \(path)"
        case .invalidVersion(let version):
            return "The RootFS version is not safe for use as a directory name: \(version)"
        case .archiveCopyLimitExceeded(let limit):
            return "The RootFS archive exceeds the \(limit)-byte staging limit."
        case .insufficientStorage(let requiredBytes, let availableBytes):
            return "RootFS installation requires at least \(requiredBytes) bytes of "
                + "additional storage, but only \(availableBytes) bytes are available."
        case .missingArchiveRoot(let path):
            return "The RootFS archive did not contain the required top-level fs directory at \(path)."
        case .installationFailed(let message):
            return "RootFS installation failed: \(message)"
        }
    }
}

/// Materializes a verified RootFS through a same-volume staging directory.
///
/// Installation is serialized process-wide. The caller archive is copied
/// through one no-follow descriptor into bounded private staging, then the same
/// snapshot is validated before and after extraction. A valid version is
/// reused, while replacement is promoted through a persistent transaction that
/// can commit or roll back after process interruption. PocketRoot never
/// downloads an archive from this API.
public actor PocketRootRootFSInstaller {
    static let replacementTransactionDirectoryName = ".replacement-transaction"
    static let promotionJournalFileName = "journal.json"
    static let previousInstallationDirectoryName = "previous"
    static let storageSafetyReserveByteCount: UInt64 = 16 * 1_024 * 1_024

    public let baseDirectoryURL: URL
    public let manifest: PocketRootRootFSArtifactManifest

    private let extractor: PocketRootGzipTarExtractor
    private let maximumArchiveByteCount: UInt64
    private let archiveSnapshotHandler: (@Sendable (URL) -> Void)?
    private let promotionCheckpointHandler: (
        @Sendable (RootFSInstallerPromotionCheckpoint) throws -> Void
    )?
    private let writeCheckpointHandler: (
        @Sendable (RootFSInstallerWriteCheckpoint) throws -> Void
    )?
    private let persistenceCheckpointHandler: (
        @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
    )?
    private let injectedGzipENOSPCAfterByteCount: UInt64?
    private let availableCapacityProvider: (
        @Sendable (URL) throws -> UInt64
    )?
    private let executor: RootFSInstallationExecutor

    public init(
        baseDirectoryURL: URL,
        manifest: PocketRootRootFSArtifactManifest = .ishEmbedV0_3_3,
        extractor: PocketRootGzipTarExtractor? = nil,
        maximumArchiveByteCount: UInt64? = nil
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.manifest = manifest
        self.extractor = extractor ?? PocketRootGzipTarExtractor(
            maximumExpandedArchiveByteCount: manifest.expandedArchiveByteCount
                ?? 256 * 1_024 * 1_024
        )
        self.maximumArchiveByteCount = maximumArchiveByteCount
            ?? manifest.archiveByteCount
            ?? 256 * 1_024 * 1_024
        archiveSnapshotHandler = nil
        promotionCheckpointHandler = nil
        writeCheckpointHandler = nil
        persistenceCheckpointHandler = nil
        injectedGzipENOSPCAfterByteCount = nil
        availableCapacityProvider = nil
        executor = .shared
    }

    init(
        baseDirectoryURL: URL,
        manifest: PocketRootRootFSArtifactManifest,
        extractor: PocketRootGzipTarExtractor? = nil,
        maximumArchiveByteCount: UInt64? = nil,
        testHooks: RootFSInstallerTestHooks
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.manifest = manifest
        self.extractor = extractor ?? PocketRootGzipTarExtractor(
            maximumExpandedArchiveByteCount: manifest.expandedArchiveByteCount
                ?? 256 * 1_024 * 1_024
        )
        self.maximumArchiveByteCount = maximumArchiveByteCount
            ?? manifest.archiveByteCount
            ?? 256 * 1_024 * 1_024
        archiveSnapshotHandler = testHooks.archiveSnapshotHandler
        promotionCheckpointHandler = testHooks.promotionCheckpointHandler
        writeCheckpointHandler = testHooks.writeCheckpointHandler
        persistenceCheckpointHandler =
            testHooks.persistenceCheckpointHandler
        injectedGzipENOSPCAfterByteCount =
            testHooks.injectedGzipENOSPCAfterByteCount
        availableCapacityProvider = testHooks.availableCapacityProvider
        executor = .shared
    }

    public func prepareArchive(
        at archiveURL: URL
    ) async throws -> PocketRootRootFSInstallation {
        let baseDirectoryURL = baseDirectoryURL
        let manifest = manifest
        let extractor = extractor
        let maximumArchiveByteCount = maximumArchiveByteCount
        let archiveSnapshotHandler = archiveSnapshotHandler
        let promotionCheckpointHandler = promotionCheckpointHandler
        let writeCheckpointHandler = writeCheckpointHandler
        let persistenceCheckpointHandler = persistenceCheckpointHandler
        let injectedGzipENOSPCAfterByteCount =
            injectedGzipENOSPCAfterByteCount
        let availableCapacityProvider = availableCapacityProvider

        return try await executor.perform { cancellation in
            try Self.prepareArchiveSynchronously(
                archiveURL: archiveURL,
                baseDirectoryURL: baseDirectoryURL,
                manifest: manifest,
                extractor: extractor,
                maximumArchiveByteCount: maximumArchiveByteCount,
                archiveSnapshotHandler: archiveSnapshotHandler,
                promotionCheckpointHandler: promotionCheckpointHandler,
                writeCheckpointHandler: writeCheckpointHandler,
                persistenceCheckpointHandler:
                    persistenceCheckpointHandler,
                injectedGzipENOSPCAfterByteCount:
                    injectedGzipENOSPCAfterByteCount,
                availableCapacityProvider: availableCapacityProvider,
                cancellation: cancellation
            )
        }
    }

    private static func prepareArchiveSynchronously(
        archiveURL: URL,
        baseDirectoryURL: URL,
        manifest: PocketRootRootFSArtifactManifest,
        extractor: PocketRootGzipTarExtractor,
        maximumArchiveByteCount: UInt64,
        archiveSnapshotHandler: (@Sendable (URL) -> Void)?,
        promotionCheckpointHandler: (
            @Sendable (RootFSInstallerPromotionCheckpoint) throws -> Void
        )?,
        writeCheckpointHandler: (
            @Sendable (RootFSInstallerWriteCheckpoint) throws -> Void
        )?,
        persistenceCheckpointHandler: (
            @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
        )?,
        injectedGzipENOSPCAfterByteCount: UInt64?,
        availableCapacityProvider: (
            @Sendable (URL) throws -> UInt64
        )?,
        cancellation: RootFSInstallationCancellation
    ) throws -> PocketRootRootFSInstallation {
        guard baseDirectoryURL.isFileURL else {
            throw PocketRootRootFSInstallationError.invalidBaseDirectory(
                baseDirectoryURL.absoluteString
            )
        }
        let version = try safeVersionComponent(manifest.version)
        let fileManager = FileManager.default
        guard isExistingRealDirectory(at: baseDirectoryURL) else {
            throw PocketRootRootFSInstallationError.invalidBaseDirectory(
                baseDirectoryURL.path
            )
        }
        let rootFSDirectoryURL = baseDirectoryURL
            .appendingPathComponent("rootfs", isDirectory: true)
        let finalURL = rootFSDirectoryURL
            .appendingPathComponent(version, isDirectory: true)
        let currentRecordURL = rootFSDirectoryURL
            .appendingPathComponent("current.json", isDirectory: false)
        let expectedRecord = InstallationRecord(manifest: manifest)

        try cancellation.check()
        try createRootFSDirectoryIfNeeded(at: rootFSDirectoryURL)
        let rootFSDirectoryValues = try rootFSDirectoryURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootFSDirectoryValues.isDirectory == true,
              rootFSDirectoryValues.isSymbolicLink != true
        else {
            throw PocketRootRootFSInstallationError.invalidBaseDirectory(
                rootFSDirectoryURL.path
            )
        }
        // Persist the rootfs/ directory entry itself. The API requires the
        // caller-owned base directory and its ancestors to already exist.
        try synchronizeDirectory(at: baseDirectoryURL)
        try recoverInterruptedPromotion(
            in: rootFSDirectoryURL,
            currentRecordURL: currentRecordURL,
            persistenceCheckpointHandler: persistenceCheckpointHandler
        )
        try removeStaleStagingDirectories(in: rootFSDirectoryURL)

        if isValidInstallation(at: finalURL, expectedRecord: expectedRecord) {
            try writeCurrentRecord(
                expectedRecord,
                relativePath: version,
                to: currentRecordURL,
                persistenceCheckpointHandler:
                    persistenceCheckpointHandler
            )
            return PocketRootRootFSInstallation(
                version: manifest.version,
                rootFSURL: finalURL,
                reusedExistingInstallation: true
            )
        }

        let requiredCapacity = try requiredAdditionalCapacity(
            archiveByteCount: manifest.archiveByteCount ?? maximumArchiveByteCount,
            expandedArchiveByteCount: max(
                manifest.expandedArchiveByteCount ?? 0,
                extractor.maximumExpandedArchiveByteCount
            )
        )
        let availableCapacity = try (
            availableCapacityProvider ?? volumeAvailableCapacity
        )(rootFSDirectoryURL)
        guard availableCapacity >= requiredCapacity else {
            throw PocketRootRootFSInstallationError.insufficientStorage(
                requiredBytes: requiredCapacity,
                availableBytes: availableCapacity
            )
        }

        let stagingURL = rootFSDirectoryURL.appendingPathComponent(
            ".installing-\(version)-\(UUID().uuidString)",
            isDirectory: true
        )
        let extractedURL = stagingURL.appendingPathComponent(
            "extracted",
            isDirectory: true
        )
        let stagedArchiveURL = stagingURL.appendingPathComponent(
            "archive.tar.gz",
            isDirectory: false
        )
        defer {
            try? removeItemMakingTreeAccessible(at: stagingURL)
        }

        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        try cancellation.check()
        try copyArchive(
            from: archiveURL,
            to: stagedArchiveURL,
            maximumByteCount: maximumArchiveByteCount,
            writeCheckpointHandler: writeCheckpointHandler,
            cancellation: cancellation
        )
        try PocketRootRootFSValidator.validateArchive(
            at: stagedArchiveURL,
            against: manifest
        )
        archiveSnapshotHandler?(stagedArchiveURL)
        try cancellation.check()
        try extractor.extract(
            archiveURL: stagedArchiveURL,
            to: extractedURL,
            writeCheckpointHandler: writeCheckpointHandler,
            injectedGzipENOSPCAfterByteCount:
                injectedGzipENOSPCAfterByteCount
        )
        try PocketRootRootFSValidator.validateArchive(
            at: stagedArchiveURL,
            against: manifest
        )
        try cancellation.check()

        let candidateURL = extractedURL.appendingPathComponent("fs", isDirectory: true)
        guard fileManager.fileExists(atPath: candidateURL.path) else {
            throw PocketRootRootFSInstallationError.missingArchiveRoot(candidateURL.path)
        }
        try PocketRootRootFSValidator.validateMaterializedFakeFS(at: candidateURL)
        try writeInstallationRecord(
            expectedRecord,
            to: candidateURL,
            writeCheckpointHandler: writeCheckpointHandler
        )
        try persistCandidateTree(
            at: candidateURL,
            persistenceCheckpointHandler: persistenceCheckpointHandler,
            cancellation: cancellation
        )
        try cancellation.check()

        try promote(
            candidateURL: candidateURL,
            finalURL: finalURL,
            currentRecordURL: currentRecordURL,
            record: expectedRecord,
            relativePath: version,
            promotionCheckpointHandler: promotionCheckpointHandler,
            writeCheckpointHandler: writeCheckpointHandler,
            persistenceCheckpointHandler: persistenceCheckpointHandler
        )

        return PocketRootRootFSInstallation(
            version: manifest.version,
            rootFSURL: finalURL,
            reusedExistingInstallation: false
        )
    }

    private static func safeVersionComponent(_ version: String) throws -> String {
        guard let firstScalar = version.unicodeScalars.first,
              isASCIIAlphaNumeric(firstScalar),
              version != "current.json",
              version.unicodeScalars.allSatisfy({ scalar in
                  isASCIIAlphaNumeric(scalar) || "-._".unicodeScalars.contains(scalar)
              })
        else {
            throw PocketRootRootFSInstallationError.invalidVersion(version)
        }
        return version
    }

    private static func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }

    private static func isExistingRealDirectory(at url: URL) -> Bool {
        var status = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.lstat(path, &status)
        }
        return result == 0
            && (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
    }

    private static func createRootFSDirectoryIfNeeded(at url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.mkdir(path, S_IRWXU)
        }
        guard result == 0 || errno == EEXIST else {
            throw posixFailure("create the RootFS installation directory")
        }
    }

    /// The extractor temporarily holds both the decompressed tar and its
    /// materialized payload while the private compressed snapshot is present.
    /// Keep a fixed reserve for filesystem metadata and atomic JSON side files.
    static func requiredAdditionalCapacity(
        archiveByteCount: UInt64,
        expandedArchiveByteCount: UInt64
    ) throws -> UInt64 {
        let (expandedCopies, multiplicationOverflow) =
            expandedArchiveByteCount.multipliedReportingOverflow(by: 2)
        guard !multiplicationOverflow else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "The RootFS storage requirement exceeds the supported integer range."
            )
        }
        let (payloadCapacity, payloadOverflow) =
            archiveByteCount.addingReportingOverflow(expandedCopies)
        guard !payloadOverflow else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "The RootFS storage requirement exceeds the supported integer range."
            )
        }
        let (requiredCapacity, reserveOverflow) =
            payloadCapacity.addingReportingOverflow(storageSafetyReserveByteCount)
        guard !reserveOverflow else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "The RootFS storage requirement exceeds the supported integer range."
            )
        }
        return requiredCapacity
    }

    private static func volumeAvailableCapacity(at url: URL) throws -> UInt64 {
        let values = try url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let capacity = values.volumeAvailableCapacityForImportantUsage,
              capacity >= 0
        else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "Unable to determine available storage for the RootFS volume."
            )
        }
        return UInt64(capacity)
    }

    /// Copies the caller-controlled archive into private staging through one
    /// no-follow file descriptor. The staged snapshot is the only path later
    /// hashed and extracted, closing the validation/reopen replacement window.
    private static func copyArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumByteCount: UInt64,
        writeCheckpointHandler: (
            @Sendable (RootFSInstallerWriteCheckpoint) throws -> Void
        )?,
        cancellation: RootFSInstallationCancellation
    ) throws {
        guard sourceURL.isFileURL, destinationURL.isFileURL else {
            throw PocketRootRootFSValidationError.archiveUnavailable(sourceURL.path)
        }

        let sourceDescriptor = sourceURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.open(
                path,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard sourceDescriptor >= 0 else {
            throw PocketRootRootFSValidationError.archiveUnavailable(sourceURL.path)
        }
        defer {
            Darwin.close(sourceDescriptor)
        }

        var sourceStatus = stat()
        guard fstat(sourceDescriptor, &sourceStatus) == 0,
              (sourceStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
        else {
            throw PocketRootRootFSValidationError.archiveUnavailable(sourceURL.path)
        }

        let destinationDescriptor = destinationURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard destinationDescriptor >= 0 else {
            throw posixFailure("create staged RootFS archive")
        }

        var completed = false
        defer {
            Darwin.close(destinationDescriptor)
            if !completed {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }

        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var copiedByteCount: UInt64 = 0

        while true {
            try cancellation.check()
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(sourceDescriptor, bytes.baseAddress, bytes.count)
            }
            if bytesRead < 0 {
                if errno == EINTR {
                    continue
                }
                throw posixFailure("read RootFS archive")
            }
            if bytesRead == 0 {
                break
            }

            let chunkByteCount = UInt64(bytesRead)
            guard chunkByteCount <= maximumByteCount,
                  copiedByteCount <= maximumByteCount - chunkByteCount
            else {
                throw PocketRootRootFSInstallationError.archiveCopyLimitExceeded(
                    maximumByteCount
                )
            }

            var writtenByteCount = 0
            while writtenByteCount < bytesRead {
                let bytesWritten = buffer.withUnsafeBytes { bytes in
                    Darwin.write(
                        destinationDescriptor,
                        bytes.baseAddress?.advanced(by: writtenByteCount),
                        bytesRead - writtenByteCount
                    )
                }
                if bytesWritten < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw posixFailure("write staged RootFS archive")
                }
                guard bytesWritten > 0 else {
                    throw PocketRootRootFSInstallationError.installationFailed(
                        "Unable to write staged RootFS archive: write returned zero bytes."
                    )
                }
                writtenByteCount += bytesWritten
                do {
                    try writeCheckpointHandler?(.archiveSnapshot)
                } catch {
                    throw PocketRootRootFSInstallationError.installationFailed(
                        "Unable to write staged RootFS archive: "
                            + failureDescription(error)
                    )
                }
            }
            copiedByteCount += chunkByteCount
        }

        completed = true
    }

    private static func posixFailure(
        _ operation: String,
        errorNumber: Int32 = errno
    ) -> PocketRootRootFSInstallationError {
        return .installationFailed(
            "Unable to \(operation): \(String(cString: strerror(errorNumber)))"
        )
    }

    private static func isValidInstallation(
        at rootFSURL: URL,
        expectedRecord: InstallationRecord
    ) -> Bool {
        do {
            try PocketRootRootFSValidator.validateMaterializedFakeFS(at: rootFSURL)
            let recordURL = rootFSURL.appendingPathComponent(
                ".pocketroot-rootfs.json",
                isDirectory: false
            )
            let recordValues = try recordURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard recordValues.isRegularFile == true,
                  recordValues.isSymbolicLink != true
            else {
                return false
            }
            let data = try Data(contentsOf: recordURL)
            let record = try JSONDecoder().decode(InstallationRecord.self, from: data)
            return record == expectedRecord
        } catch {
            return false
        }
    }

    private static func writeInstallationRecord(
        _ record: InstallationRecord,
        to rootFSURL: URL,
        writeCheckpointHandler: (
            @Sendable (RootFSInstallerWriteCheckpoint) throws -> Void
        )?
    ) throws {
        let recordURL = rootFSURL.appendingPathComponent(
            ".pocketroot-rootfs.json",
            isDirectory: false
        )
        do {
            try encoded(record).write(to: recordURL, options: .atomic)
            try writeCheckpointHandler?(.installationRecord)
        } catch {
            throw PocketRootRootFSInstallationError.installationFailed(
                "Unable to write the RootFS installation record: "
                    + failureDescription(error)
            )
        }
    }

    private static func writeCurrentRecord(
        _ record: InstallationRecord,
        relativePath: String,
        to url: URL,
        writeCheckpointHandler: (
            @Sendable (RootFSInstallerWriteCheckpoint) throws -> Void
        )? = nil,
        persistenceCheckpointHandler: (
            @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
        )? = nil
    ) throws {
        let current = CurrentInstallationRecord(
            version: record.version,
            sha256: record.sha256,
            relativePath: relativePath
        )
        do {
            try writeAtomicallyAndPersist(
                encoded(current),
                to: url,
                fileCheckpoint: .currentRecordFile,
                directoryCheckpoint: .currentRecordDirectory,
                persistenceCheckpointHandler:
                    persistenceCheckpointHandler,
                writeCheckpoint: {
                    try writeCheckpointHandler?(.currentRecord)
                }
            )
        } catch {
            throw PocketRootRootFSInstallationError.installationFailed(
                "Unable to write the current RootFS record: "
                    + failureDescription(error)
            )
        }
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    /// Flushes every candidate payload file and then its directories from the
    /// leaves upward. The candidate's parent is synchronized after the later
    /// rename, so no private staging path itself becomes part of the commit.
    private static func persistCandidateTree(
        at candidateURL: URL,
        persistenceCheckpointHandler: (
            @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
        )?,
        cancellation: RootFSInstallationCancellation
    ) throws {
        do {
            try persistenceCheckpointHandler?(.candidateTree)
            try synchronizeTree(
                at: candidateURL,
                cancellation: cancellation
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PocketRootRootFSInstallationError.installationFailed(
                "Unable to persist the candidate RootFS: "
                    + failureDescription(error)
            )
        }
    }

    private static func synchronizeTree(
        at directoryURL: URL,
        cancellation: RootFSInstallationCancellation
    ) throws {
        try cancellation.check()
        let directory = try openDirectoryForTreePersistence(at: directoryURL)
        var permissionsRestored = false
        defer {
            if directory.permissionsChanged && !permissionsRestored {
                Darwin.fchmod(directory.descriptor, directory.originalMode)
            }
            Darwin.close(directory.descriptor)
        }

        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        ).sorted { $0.path < $1.path }

        for itemURL in contents {
            try cancellation.check()
            let status = try fileStatusWithoutFollowingLinks(at: itemURL)
            let type = status.st_mode & mode_t(S_IFMT)
            if type == mode_t(S_IFDIR) {
                try synchronizeTree(
                    at: itemURL,
                    cancellation: cancellation
                )
            } else if type == mode_t(S_IFREG) {
                try synchronizeRegularFile(at: itemURL)
            } else {
                throw PocketRootRootFSInstallationError.installationFailed(
                    "The candidate RootFS contains an unsupported filesystem item."
                )
            }
        }
        if directory.permissionsChanged {
            guard Darwin.fchmod(
                directory.descriptor,
                directory.originalMode
            ) == 0 else {
                throw posixFailure(
                    "restore RootFS directory permissions before persistence"
                )
            }
            permissionsRestored = true
        }
        try synchronize(directory.descriptor)
    }

    private static func synchronizeRegularFile(at url: URL) throws {
        let status = try fileStatusWithoutFollowingLinks(at: url)
        guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "The candidate RootFS file changed type during persistence."
            )
        }
        let originalMode = status.st_mode & mode_t(0o7777)
        let accessibleMode = originalMode | mode_t(S_IRUSR)
        let permissionsChanged = accessibleMode != originalMode
        if permissionsChanged {
            try setPermissions(accessibleMode, at: url)
        }

        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            let error = posixFailure(
                "open a RootFS file for persistence"
            )
            if permissionsChanged {
                try? setPermissions(originalMode, at: url)
            }
            throw error
        }
        var permissionsRestored = false
        defer {
            if permissionsChanged && !permissionsRestored {
                Darwin.fchmod(descriptor, originalMode)
            }
            Darwin.close(descriptor)
        }

        var openedStatus = stat()
        guard fstat(descriptor, &openedStatus) == 0,
              (openedStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
        else {
            throw posixFailure("verify a RootFS file for persistence")
        }
        if permissionsChanged {
            guard Darwin.fchmod(descriptor, originalMode) == 0 else {
                throw posixFailure(
                    "restore RootFS file permissions before persistence"
                )
            }
            permissionsRestored = true
        }
        try fullySynchronize(descriptor)
    }

    private static func openDirectoryForTreePersistence(
        at url: URL
    ) throws -> (
        descriptor: Int32,
        originalMode: mode_t,
        permissionsChanged: Bool
    ) {
        let status = try fileStatusWithoutFollowingLinks(at: url)
        guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "The candidate RootFS directory changed type during persistence."
            )
        }
        let originalMode = status.st_mode & mode_t(0o7777)
        let accessibleMode =
            originalMode | mode_t(S_IRUSR) | mode_t(S_IXUSR)
        let permissionsChanged = accessibleMode != originalMode
        if permissionsChanged {
            try setPermissions(accessibleMode, at: url)
        }

        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            let error = posixFailure(
                "open a RootFS directory for persistence"
            )
            if permissionsChanged {
                try? setPermissions(originalMode, at: url)
            }
            throw error
        }

        var openedStatus = stat()
        guard fstat(descriptor, &openedStatus) == 0,
              (openedStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
        else {
            let error = posixFailure(
                "verify a RootFS directory for persistence"
            )
            Darwin.close(descriptor)
            if permissionsChanged {
                try? setPermissions(originalMode, at: url)
            }
            throw error
        }
        return (descriptor, originalMode, permissionsChanged)
    }

    private static func fileStatusWithoutFollowingLinks(
        at url: URL
    ) throws -> stat {
        var status = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.lstat(path, &status)
        }
        guard result == 0 else {
            throw posixFailure("inspect a RootFS item for persistence")
        }
        return status
    }

    private static func setPermissions(_ mode: mode_t, at url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.chmod(path, mode)
        }
        guard result == 0 else {
            throw posixFailure(
                "temporarily adjust RootFS permissions for persistence"
            )
        }
    }

    private static func synchronizeDirectory(at url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw posixFailure("open a RootFS directory for persistence")
        }
        defer {
            Darwin.close(descriptor)
        }

        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
        else {
            throw posixFailure("verify a RootFS directory for persistence")
        }
        try synchronize(descriptor)
    }

    private static func fullySynchronize(_ descriptor: Int32) throws {
        while Darwin.fcntl(descriptor, F_FULLFSYNC) != 0 {
            let errorNumber = errno
            if errorNumber == EINTR {
                continue
            }
            if errorNumber == EINVAL || errorNumber == ENOTSUP {
                try synchronize(descriptor)
                return
            }
            throw posixFailure(
                "fully synchronize a RootFS file",
                errorNumber: errorNumber
            )
        }
    }

    private static func synchronize(_ descriptor: Int32) throws {
        while Darwin.fsync(descriptor) != 0 {
            let errorNumber = errno
            if errorNumber == EINTR {
                continue
            }
            throw posixFailure(
                "synchronize RootFS filesystem state",
                errorNumber: errorNumber
            )
        }
    }

    private static func writeAtomicallyAndPersist(
        _ data: Data,
        to url: URL,
        fileCheckpoint: RootFSInstallerPersistenceCheckpoint,
        directoryCheckpoint: RootFSInstallerPersistenceCheckpoint,
        persistenceCheckpointHandler: (
            @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
        )?,
        writeCheckpoint: () throws -> Void
    ) throws {
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).pocketroot-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        var descriptor = temporaryURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw posixFailure("create a temporary RootFS record")
        }

        var renamed = false
        defer {
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
            if !renamed {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw posixFailure("write a temporary RootFS record")
                }
                guard written > 0 else {
                    throw PocketRootRootFSInstallationError.installationFailed(
                        "Unable to write a temporary RootFS record: write returned zero bytes."
                    )
                }
                offset += written
            }
        }
        try writeCheckpoint()
        try persistenceCheckpointHandler?(fileCheckpoint)
        try fullySynchronize(descriptor)
        Darwin.close(descriptor)
        descriptor = -1

        let renameResult = temporaryURL.withUnsafeFileSystemRepresentation {
            sourcePath in
            url.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else {
                    return Int32(-1)
                }
                return Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            throw posixFailure("atomically replace a RootFS record")
        }
        renamed = true
        try persistenceCheckpointHandler?(directoryCheckpoint)
        try synchronizeDirectory(at: url.deletingLastPathComponent())
    }

    private static func removeStaleStagingDirectories(in rootFSDirectoryURL: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootFSDirectoryURL,
            includingPropertiesForKeys: nil
        )
        var removedDirectory = false
        for url in contents where url.lastPathComponent.hasPrefix(".installing-") {
            try removeItemMakingTreeAccessible(at: url)
            removedDirectory = true
        }
        if removedDirectory {
            try synchronizeDirectory(at: rootFSDirectoryURL)
        }
    }

    /// Resolves a promotion transaction left by process termination before any
    /// staging cleanup can discard the candidate that caused it.
    private static func recoverInterruptedPromotion(
        in rootFSDirectoryURL: URL,
        currentRecordURL: URL,
        persistenceCheckpointHandler: (
            @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
        )?
    ) throws {
        let transactionURL = rootFSDirectoryURL.appendingPathComponent(
            replacementTransactionDirectoryName,
            isDirectory: true
        )
        guard itemExists(at: transactionURL) else {
            return
        }
        let transactionValues = try transactionURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard transactionValues.isDirectory == true,
              transactionValues.isSymbolicLink != true
        else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "The interrupted-promotion transaction must be a real directory."
            )
        }

        let journalURL = transactionURL.appendingPathComponent(
            promotionJournalFileName,
            isDirectory: false
        )
        // The transaction directory is created before its journal and no
        // destructive rename happens before the journal file is written. A
        // journal-less directory is therefore either pre-transaction debris
        // or post-commit cleanup debris.
        guard itemExists(at: journalURL) else {
            try removeItemAndSynchronizeParent(at: transactionURL)
            return
        }

        let journalValues = try journalURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard journalValues.isRegularFile == true,
              journalValues.isSymbolicLink != true,
              (journalValues.fileSize ?? 0) <= 1_048_576
        else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "The interrupted-promotion journal is not a trusted regular file."
            )
        }

        let journal: PromotionJournal
        do {
            journal = try JSONDecoder().decode(
                PromotionJournal.self,
                from: Data(contentsOf: journalURL)
            )
        } catch {
            throw PocketRootRootFSInstallationError.installationFailed(
                "Unable to decode the interrupted-promotion journal: \(error.localizedDescription)"
            )
        }
        let version = try safeVersionComponent(journal.version)
        guard journal.expectedRecord.version == version else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "The interrupted-promotion journal contains inconsistent versions."
            )
        }

        let finalURL = rootFSDirectoryURL.appendingPathComponent(
            version,
            isDirectory: true
        )
        if isValidInstallation(
            at: finalURL,
            expectedRecord: journal.expectedRecord
        ) {
            // The candidate rename completed. Finish the commit even if the
            // process stopped before current.json was updated.
            try writeCurrentRecord(
                journal.expectedRecord,
                relativePath: version,
                to: currentRecordURL,
                persistenceCheckpointHandler:
                    persistenceCheckpointHandler
            )
            try removeItemAndSynchronizeParent(at: transactionURL)
            return
        }

        try rollbackPromotion(
            journal: journal,
            finalURL: finalURL,
            currentRecordURL: currentRecordURL,
            transactionURL: transactionURL
        )
    }

    private static func rollbackPromotion(
        journal: PromotionJournal,
        finalURL: URL,
        currentRecordURL: URL,
        transactionURL: URL
    ) throws {
        let backupURL = transactionURL.appendingPathComponent(
            previousInstallationDirectoryName,
            isDirectory: true
        )

        if itemExists(at: backupURL) {
            if itemExists(at: finalURL) {
                try removeItemAndSynchronizeParent(at: finalURL)
            }
            try moveItemAndSynchronizeParents(
                at: backupURL,
                to: finalURL
            )
        } else if journal.hadPreviousInstallation {
            // No backup means the first rename never completed. The previous
            // installation must still occupy its original final path.
            guard itemExists(at: finalURL) else {
                throw PocketRootRootFSInstallationError.installationFailed(
                    "The previous RootFS is missing from an interrupted promotion."
                )
            }
        } else if itemExists(at: finalURL) {
            try removeItemAndSynchronizeParent(at: finalURL)
        }

        try restoreCurrentRecord(
            journal.previousCurrentRecordData,
            at: currentRecordURL
        )
        try removeItemAndSynchronizeParent(at: transactionURL)
    }

    private static func readCurrentRecordData(at url: URL) throws -> Data? {
        guard itemExists(at: url) else {
            return nil
        }
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= 65_536
        else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "current.json must be a small, real regular file."
            )
        }
        return try Data(contentsOf: url)
    }

    private static func restoreCurrentRecord(_ data: Data?, at url: URL) throws {
        if let data {
            try writeAtomicallyAndPersist(
                data,
                to: url,
                fileCheckpoint: .currentRecordFile,
                directoryCheckpoint: .currentRecordDirectory,
                persistenceCheckpointHandler: nil,
                writeCheckpoint: {}
            )
        } else if itemExists(at: url) {
            try removeItemAndSynchronizeParent(at: url)
        }
    }

    private static func moveItemAndSynchronizeParents(
        at sourceURL: URL,
        to destinationURL: URL,
        checkpoint: RootFSInstallerPersistenceCheckpoint? = nil,
        persistenceCheckpointHandler: (
            @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
        )? = nil
    ) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        if let checkpoint {
            try persistenceCheckpointHandler?(checkpoint)
        }
        let sourceParentURL = sourceURL.deletingLastPathComponent()
        let destinationParentURL = destinationURL.deletingLastPathComponent()
        try synchronizeDirectory(at: destinationParentURL)
        if destinationParentURL.standardizedFileURL !=
            sourceParentURL.standardizedFileURL
        {
            try synchronizeDirectory(at: sourceParentURL)
        }
    }

    private static func removeItemAndSynchronizeParent(at url: URL) throws {
        let parentURL = url.deletingLastPathComponent()
        try removeItemMakingTreeAccessible(at: url)
        try synchronizeDirectory(at: parentURL)
    }

    /// Candidate payload modes belong to the guest image and may deny host
    /// traversal. Cleanup first grants owner traversal only to directories
    /// that are about to be deleted; links are never followed.
    private static func removeItemMakingTreeAccessible(at url: URL) throws {
        let status = try fileStatusWithoutFollowingLinks(at: url)
        if (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
            let originalMode = status.st_mode & mode_t(0o7777)
            let removableMode =
                originalMode
                | mode_t(S_IRUSR)
                | mode_t(S_IWUSR)
                | mode_t(S_IXUSR)
            if removableMode != originalMode {
                try setPermissions(removableMode, at: url)
            }
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
            for itemURL in contents {
                let itemStatus = try fileStatusWithoutFollowingLinks(at: itemURL)
                if (itemStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
                    try makeDirectoryTreeAccessibleForRemoval(at: itemURL)
                }
            }
        }
        try FileManager.default.removeItem(at: url)
    }

    private static func makeDirectoryTreeAccessibleForRemoval(
        at directoryURL: URL
    ) throws {
        let status = try fileStatusWithoutFollowingLinks(at: directoryURL)
        guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            return
        }
        let originalMode = status.st_mode & mode_t(0o7777)
        let removableMode =
            originalMode
            | mode_t(S_IRUSR)
            | mode_t(S_IWUSR)
            | mode_t(S_IXUSR)
        if removableMode != originalMode {
            try setPermissions(removableMode, at: directoryURL)
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        for itemURL in contents {
            let itemStatus = try fileStatusWithoutFollowingLinks(at: itemURL)
            if (itemStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
                try makeDirectoryTreeAccessibleForRemoval(at: itemURL)
            }
        }
    }

    private static func itemExists(at url: URL) -> Bool {
        let parentURL = url.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: parentURL.path
        ) else {
            return false
        }
        return names.contains(url.lastPathComponent)
    }

    private static func promote(
        candidateURL: URL,
        finalURL: URL,
        currentRecordURL: URL,
        record: InstallationRecord,
        relativePath: String,
        promotionCheckpointHandler: (
            @Sendable (RootFSInstallerPromotionCheckpoint) throws -> Void
        )?,
        writeCheckpointHandler: (
            @Sendable (RootFSInstallerWriteCheckpoint) throws -> Void
        )?,
        persistenceCheckpointHandler: (
            @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
        )?
    ) throws {
        let fileManager = FileManager.default
        let rootFSDirectoryURL = finalURL.deletingLastPathComponent()
        let transactionURL = rootFSDirectoryURL.appendingPathComponent(
            replacementTransactionDirectoryName,
            isDirectory: true
        )
        guard !itemExists(at: transactionURL) else {
            throw PocketRootRootFSInstallationError.installationFailed(
                "A previous RootFS promotion transaction has not been recovered."
            )
        }

        let previousCurrentRecordData = try readCurrentRecordData(at: currentRecordURL)
        let hadPreviousInstallation = itemExists(at: finalURL)
        let journal = PromotionJournal(
            version: relativePath,
            expectedRecord: record,
            hadPreviousInstallation: hadPreviousInstallation,
            previousCurrentRecordData: previousCurrentRecordData
        )

        try fileManager.createDirectory(
            at: transactionURL,
            withIntermediateDirectories: false
        )
        let journalURL = transactionURL.appendingPathComponent(
            promotionJournalFileName,
            isDirectory: false
        )
        do {
            try writeAtomicallyAndPersist(
                encoded(journal),
                to: journalURL,
                fileCheckpoint: .promotionJournalFile,
                directoryCheckpoint: .promotionJournalDirectory,
                persistenceCheckpointHandler:
                    persistenceCheckpointHandler,
                writeCheckpoint: {
                    try writeCheckpointHandler?(.promotionJournal)
                }
            )
            try synchronizeDirectory(at: rootFSDirectoryURL)
        } catch {
            try? removeItemAndSynchronizeParent(at: transactionURL)
            throw PocketRootRootFSInstallationError.installationFailed(
                "Unable to record the RootFS promotion transaction: "
                    + failureDescription(error)
            )
        }

        let backupURL = transactionURL.appendingPathComponent(
            previousInstallationDirectoryName,
            isDirectory: true
        )

        do {
            if hadPreviousInstallation {
                try moveItemAndSynchronizeParents(
                    at: finalURL,
                    to: backupURL,
                    checkpoint: .previousInstallationRename,
                    persistenceCheckpointHandler:
                        persistenceCheckpointHandler
                )
                try promotionCheckpointHandler?(.previousInstallationMoved)
            }
            try moveItemAndSynchronizeParents(
                at: candidateURL,
                to: finalURL,
                checkpoint: .candidatePromotionRename,
                persistenceCheckpointHandler:
                    persistenceCheckpointHandler
            )
            try promotionCheckpointHandler?(.candidatePromoted)
            try writeCurrentRecord(
                record,
                relativePath: relativePath,
                to: currentRecordURL,
                writeCheckpointHandler: writeCheckpointHandler,
                persistenceCheckpointHandler:
                    persistenceCheckpointHandler
            )
        } catch {
            let promotionError = error
            do {
                try rollbackPromotion(
                    journal: journal,
                    finalURL: finalURL,
                    currentRecordURL: currentRecordURL,
                    transactionURL: transactionURL
                )
            } catch {
                throw PocketRootRootFSInstallationError.installationFailed(
                    "\(failureDescription(promotionError)); rollback also failed: "
                        + failureDescription(error)
                )
            }
            throw PocketRootRootFSInstallationError.installationFailed(
                failureDescription(promotionError)
            )
        }

        // The installation and current record are committed. If cleanup is
        // interrupted, startup recovery recognizes the valid final record and
        // removes the transaction directory.
        try? removeItemAndSynchronizeParent(at: transactionURL)
    }

    private static func failureDescription(_ error: Error) -> String {
        if case .installationFailed(let message) =
            error as? PocketRootRootFSInstallationError
        {
            return message
        }
        let cocoaError = error as NSError
        if cocoaError.domain == NSPOSIXErrorDomain,
           let errorNumber = Int32(exactly: cocoaError.code)
        {
            return String(cString: strerror(errorNumber))
        }
        if let underlyingError = cocoaError.userInfo[NSUnderlyingErrorKey] as? Error {
            let underlying = underlyingError as NSError
            if underlying.domain == NSPOSIXErrorDomain,
               let errorNumber = Int32(exactly: underlying.code)
            {
                return String(cString: strerror(errorNumber))
            }
        }
        return error.localizedDescription
    }
}

enum RootFSInstallerPromotionCheckpoint: Sendable, Equatable {
    case previousInstallationMoved
    case candidatePromoted
}

enum RootFSInstallerWriteCheckpoint: Sendable, Equatable {
    case archiveSnapshot
    case gzipOutput
    case tarPayload
    case installationRecord
    case promotionJournal
    case currentRecord
}

enum RootFSInstallerPersistenceCheckpoint: Sendable, Equatable {
    case candidateTree
    case promotionJournalFile
    case promotionJournalDirectory
    case previousInstallationRename
    case candidatePromotionRename
    case currentRecordFile
    case currentRecordDirectory
}

struct RootFSInstallerTestHooks: Sendable {
    let archiveSnapshotHandler: (@Sendable (URL) -> Void)?
    let promotionCheckpointHandler: (
        @Sendable (RootFSInstallerPromotionCheckpoint) throws -> Void
    )?
    let writeCheckpointHandler: (
        @Sendable (RootFSInstallerWriteCheckpoint) throws -> Void
    )?
    let persistenceCheckpointHandler: (
        @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
    )?
    let injectedGzipENOSPCAfterByteCount: UInt64?
    let availableCapacityProvider: (
        @Sendable (URL) throws -> UInt64
    )?

    init(
        archiveSnapshotHandler: (@Sendable (URL) -> Void)? = nil,
        promotionCheckpointHandler: (
            @Sendable (RootFSInstallerPromotionCheckpoint) throws -> Void
        )? = nil,
        writeCheckpointHandler: (
            @Sendable (RootFSInstallerWriteCheckpoint) throws -> Void
        )? = nil,
        persistenceCheckpointHandler: (
            @Sendable (RootFSInstallerPersistenceCheckpoint) throws -> Void
        )? = nil,
        injectedGzipENOSPCAfterByteCount: UInt64? = nil,
        availableCapacityProvider: (
            @Sendable (URL) throws -> UInt64
        )? = nil
    ) {
        self.archiveSnapshotHandler = archiveSnapshotHandler
        self.promotionCheckpointHandler = promotionCheckpointHandler
        self.writeCheckpointHandler = writeCheckpointHandler
        self.persistenceCheckpointHandler =
            persistenceCheckpointHandler
        self.injectedGzipENOSPCAfterByteCount =
            injectedGzipENOSPCAfterByteCount
        self.availableCapacityProvider = availableCapacityProvider
    }
}

struct InstallationRecord: Codable, Equatable {
    let version: String
    let architecture: String
    let format: String
    let sha256: String
    let archiveByteCount: UInt64?
    let expandedArchiveByteCount: UInt64?

    init(manifest: PocketRootRootFSArtifactManifest) {
        version = manifest.version
        architecture = manifest.architecture.rawValue
        format = manifest.format.rawValue
        sha256 = manifest.sha256.lowercased()
        archiveByteCount = manifest.archiveByteCount
        expandedArchiveByteCount = manifest.expandedArchiveByteCount
    }
}

struct PromotionJournal: Codable, Equatable {
    let version: String
    let expectedRecord: InstallationRecord
    let hadPreviousInstallation: Bool
    let previousCurrentRecordData: Data?
}

private struct CurrentInstallationRecord: Codable {
    let version: String
    let sha256: String
    let relativePath: String
}

private final class RootFSInstallationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        let isCancelled = isCancelled
        lock.unlock()
        if isCancelled {
            throw CancellationError()
        }
    }
}

private final class RootFSInstallationExecutor: @unchecked Sendable {
    static let shared = RootFSInstallationExecutor()

    private let queue = DispatchQueue(
        label: "com.jacklv.PocketRoot.RootFSInstallation",
        qos: .userInitiated
    )

    func perform<T: Sendable>(
        _ operation: @escaping @Sendable (RootFSInstallationCancellation) throws -> T
    ) async throws -> T {
        let cancellation = RootFSInstallationCancellation()
        if Task.isCancelled {
            cancellation.cancel()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try cancellation.check()
                        continuation.resume(returning: try operation(cancellation))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}
