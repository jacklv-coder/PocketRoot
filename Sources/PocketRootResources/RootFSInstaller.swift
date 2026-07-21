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

    public let baseDirectoryURL: URL
    public let manifest: PocketRootRootFSArtifactManifest

    private let extractor: PocketRootGzipTarExtractor
    private let maximumArchiveByteCount: UInt64
    private let archiveSnapshotHandler: (@Sendable (URL) -> Void)?
    private let promotionCheckpointHandler: (
        @Sendable (RootFSInstallerPromotionCheckpoint) throws -> Void
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

        return try await executor.perform { cancellation in
            try Self.prepareArchiveSynchronously(
                archiveURL: archiveURL,
                baseDirectoryURL: baseDirectoryURL,
                manifest: manifest,
                extractor: extractor,
                maximumArchiveByteCount: maximumArchiveByteCount,
                archiveSnapshotHandler: archiveSnapshotHandler,
                promotionCheckpointHandler: promotionCheckpointHandler,
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
        cancellation: RootFSInstallationCancellation
    ) throws -> PocketRootRootFSInstallation {
        guard baseDirectoryURL.isFileURL else {
            throw PocketRootRootFSInstallationError.invalidBaseDirectory(
                baseDirectoryURL.absoluteString
            )
        }
        let version = try safeVersionComponent(manifest.version)
        let fileManager = FileManager.default
        let rootFSDirectoryURL = baseDirectoryURL
            .appendingPathComponent("rootfs", isDirectory: true)
        let finalURL = rootFSDirectoryURL
            .appendingPathComponent(version, isDirectory: true)
        let currentRecordURL = rootFSDirectoryURL
            .appendingPathComponent("current.json", isDirectory: false)
        let expectedRecord = InstallationRecord(manifest: manifest)

        try cancellation.check()
        try fileManager.createDirectory(
            at: rootFSDirectoryURL,
            withIntermediateDirectories: true
        )
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
        try recoverInterruptedPromotion(
            in: rootFSDirectoryURL,
            currentRecordURL: currentRecordURL
        )
        try removeStaleStagingDirectories(in: rootFSDirectoryURL)

        if isValidInstallation(at: finalURL, expectedRecord: expectedRecord) {
            try writeCurrentRecord(
                expectedRecord,
                relativePath: version,
                to: currentRecordURL
            )
            return PocketRootRootFSInstallation(
                version: manifest.version,
                rootFSURL: finalURL,
                reusedExistingInstallation: true
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
            try? fileManager.removeItem(at: stagingURL)
        }

        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        try cancellation.check()
        try copyArchive(
            from: archiveURL,
            to: stagedArchiveURL,
            maximumByteCount: maximumArchiveByteCount,
            cancellation: cancellation
        )
        try PocketRootRootFSValidator.validateArchive(
            at: stagedArchiveURL,
            against: manifest
        )
        archiveSnapshotHandler?(stagedArchiveURL)
        try cancellation.check()
        try extractor.extract(archiveURL: stagedArchiveURL, to: extractedURL)
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
        try writeInstallationRecord(expectedRecord, to: candidateURL)
        try cancellation.check()

        try promote(
            candidateURL: candidateURL,
            finalURL: finalURL,
            currentRecordURL: currentRecordURL,
            record: expectedRecord,
            relativePath: version,
            promotionCheckpointHandler: promotionCheckpointHandler
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

    /// Copies the caller-controlled archive into private staging through one
    /// no-follow file descriptor. The staged snapshot is the only path later
    /// hashed and extracted, closing the validation/reopen replacement window.
    private static func copyArchive(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumByteCount: UInt64,
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
            }
            copiedByteCount += chunkByteCount
        }

        completed = true
    }

    private static func posixFailure(
        _ operation: String
    ) -> PocketRootRootFSInstallationError {
        let errorNumber = errno
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
        to rootFSURL: URL
    ) throws {
        let recordURL = rootFSURL.appendingPathComponent(
            ".pocketroot-rootfs.json",
            isDirectory: false
        )
        try encoded(record).write(to: recordURL, options: .atomic)
    }

    private static func writeCurrentRecord(
        _ record: InstallationRecord,
        relativePath: String,
        to url: URL
    ) throws {
        let current = CurrentInstallationRecord(
            version: record.version,
            sha256: record.sha256,
            relativePath: relativePath
        )
        try encoded(current).write(to: url, options: .atomic)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static func removeStaleStagingDirectories(in rootFSDirectoryURL: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootFSDirectoryURL,
            includingPropertiesForKeys: nil
        )
        for url in contents where url.lastPathComponent.hasPrefix(".installing-") {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Resolves a promotion transaction left by process termination before any
    /// staging cleanup can discard the candidate that caused it.
    private static func recoverInterruptedPromotion(
        in rootFSDirectoryURL: URL,
        currentRecordURL: URL
    ) throws {
        let fileManager = FileManager.default
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
        // destructive rename happens before the journal is durable. A
        // journal-less directory is therefore either pre-transaction debris
        // or post-commit cleanup debris.
        guard itemExists(at: journalURL) else {
            try fileManager.removeItem(at: transactionURL)
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
                to: currentRecordURL
            )
            try fileManager.removeItem(at: transactionURL)
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
        let fileManager = FileManager.default
        let backupURL = transactionURL.appendingPathComponent(
            previousInstallationDirectoryName,
            isDirectory: true
        )

        if itemExists(at: backupURL) {
            if itemExists(at: finalURL) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: backupURL, to: finalURL)
        } else if journal.hadPreviousInstallation {
            // No backup means the first rename never completed. The previous
            // installation must still occupy its original final path.
            guard itemExists(at: finalURL) else {
                throw PocketRootRootFSInstallationError.installationFailed(
                    "The previous RootFS is missing from an interrupted promotion."
                )
            }
        } else if itemExists(at: finalURL) {
            try fileManager.removeItem(at: finalURL)
        }

        try restoreCurrentRecord(
            journal.previousCurrentRecordData,
            at: currentRecordURL
        )
        try fileManager.removeItem(at: transactionURL)
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
            try data.write(to: url, options: .atomic)
        } else if itemExists(at: url) {
            try FileManager.default.removeItem(at: url)
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
            try encoded(journal).write(to: journalURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: transactionURL)
            throw PocketRootRootFSInstallationError.installationFailed(
                "Unable to record the RootFS promotion transaction: \(error.localizedDescription)"
            )
        }

        let backupURL = transactionURL.appendingPathComponent(
            previousInstallationDirectoryName,
            isDirectory: true
        )

        do {
            if hadPreviousInstallation {
                try fileManager.moveItem(at: finalURL, to: backupURL)
                try promotionCheckpointHandler?(.previousInstallationMoved)
            }
            try fileManager.moveItem(at: candidateURL, to: finalURL)
            try promotionCheckpointHandler?(.candidatePromoted)
            try writeCurrentRecord(
                record,
                relativePath: relativePath,
                to: currentRecordURL
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
                    "\(promotionError.localizedDescription); rollback also failed: \(error.localizedDescription)"
                )
            }
            throw PocketRootRootFSInstallationError.installationFailed(
                promotionError.localizedDescription
            )
        }

        // The installation and current record are committed. If cleanup is
        // interrupted, startup recovery recognizes the valid final record and
        // removes the transaction directory.
        try? fileManager.removeItem(at: transactionURL)
    }
}

enum RootFSInstallerPromotionCheckpoint: Sendable, Equatable {
    case previousInstallationMoved
    case candidatePromoted
}

struct RootFSInstallerTestHooks: Sendable {
    let archiveSnapshotHandler: (@Sendable (URL) -> Void)?
    let promotionCheckpointHandler: (
        @Sendable (RootFSInstallerPromotionCheckpoint) throws -> Void
    )?

    init(
        archiveSnapshotHandler: (@Sendable (URL) -> Void)? = nil,
        promotionCheckpointHandler: (
            @Sendable (RootFSInstallerPromotionCheckpoint) throws -> Void
        )? = nil
    ) {
        self.archiveSnapshotHandler = archiveSnapshotHandler
        self.promotionCheckpointHandler = promotionCheckpointHandler
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
