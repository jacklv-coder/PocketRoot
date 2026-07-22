import Foundation
import XCTest
@testable import PocketRootResources

final class PocketRootResourcesTests: XCTestCase {
    func testPinnedIshEmbedRootFSManifest() {
        let manifest = PocketRootRootFSArtifactManifest.ishEmbedV0_3_3

        XCTAssertEqual(manifest.version, "v0.3.3")
        XCTAssertEqual(manifest.architecture, .arm64)
        XCTAssertEqual(manifest.format, .fakeFSTarGzip)
        XCTAssertEqual(manifest.format.rawValue, "fakefs tar.gz")
        XCTAssertEqual(
            manifest.downloadURL.absoluteString,
            "https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/fs.tar.gz"
        )
        XCTAssertEqual(
            manifest.sha256,
            "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
        )
        XCTAssertEqual(manifest.archiveByteCount, 6_581_376)
        XCTAssertEqual(manifest.expandedArchiveByteCount, 18_838_016)
    }

    func testBundledProviderFailsExplicitlyWhileAssetIsGated() async {
        let baseURL: URL
        do {
            baseURL = try makeTemporaryDirectory()
        } catch {
            return XCTFail("Unable to create fixture: \(error)")
        }
        let provider = PocketRootBundledRootFSProvider(
            resourceName: "intentionally-missing-rootfs"
        )
        let installer = PocketRootRootFSInstaller(baseDirectoryURL: baseURL)

        do {
            _ = try await provider.prepareRootFS(using: installer)
            XCTFail("No distribution RootFS should be bundled yet.")
        } catch let error as PocketRootBundledRootFSProviderError {
            XCTAssertEqual(
                error,
                .resourceMissing(
                    name: "intentionally-missing-rootfs",
                    resourceExtension: "tar.gz",
                    subdirectory: nil
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testArchiveValidationAcceptsMatchingSHA256() throws {
        #if canImport(CryptoKit)
        let archiveURL = try makeTemporaryFile(contents: Data("abc".utf8))
        let manifest = PocketRootRootFSArtifactManifest(
            version: "test",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/rootfs.tar.gz")!,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )

        XCTAssertTrue(PocketRootRootFSValidator.supportsSHA256Validation)
        XCTAssertNoThrow(
            try PocketRootRootFSValidator.validateArchive(
                at: archiveURL,
                against: manifest
            )
        )
        #else
        XCTAssertFalse(PocketRootRootFSValidator.supportsSHA256Validation)
        #endif
    }

    func testArchiveValidationReportsDigestMismatch() throws {
        #if canImport(CryptoKit)
        let archiveURL = try makeTemporaryFile(contents: Data("abc".utf8))
        let manifest = PocketRootRootFSArtifactManifest(
            version: "test",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/rootfs.tar.gz")!,
            sha256: String(repeating: "0", count: 64)
        )

        XCTAssertThrowsError(
            try PocketRootRootFSValidator.validateArchive(
                at: archiveURL,
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootRootFSValidationError,
                .sha256Mismatch(
                    expected: String(repeating: "0", count: 64),
                    actual: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                )
            )
        }
        #endif
    }

    func testArchiveValidationRejectsUnexpectedSizeBeforeHashing() throws {
        let archiveURL = try makeTemporaryFile(contents: Data("abc".utf8))
        let manifest = PocketRootRootFSArtifactManifest(
            version: "test",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/rootfs.tar.gz")!,
            sha256: "unused",
            archiveByteCount: 4
        )

        XCTAssertThrowsError(
            try PocketRootRootFSValidator.validateArchive(
                at: archiveURL,
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootRootFSValidationError,
                .archiveSizeMismatch(expected: 4, actual: 3)
            )
        }
    }

    func testArchiveValidationRejectsMissingFile() {
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        XCTAssertThrowsError(
            try PocketRootRootFSValidator.validateArchive(at: archiveURL)
        ) { error in
            XCTAssertEqual(
                error as? PocketRootRootFSValidationError,
                .archiveUnavailable(archiveURL.path)
            )
        }
    }

    func testArchiveValidationRejectsSymbolicLink() throws {
        let realArchiveURL = try makeTemporaryFile(contents: Data("abc".utf8))
        let symbolicLinkURL = realArchiveURL.deletingLastPathComponent()
            .appendingPathComponent("linked-rootfs.tar.gz")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: realArchiveURL
        )

        XCTAssertThrowsError(
            try PocketRootRootFSValidator.validateArchive(at: symbolicLinkURL)
        ) { error in
            XCTAssertEqual(
                error as? PocketRootRootFSValidationError,
                .archiveUnavailable(symbolicLinkURL.path)
            )
        }
    }

    func testMaterializedFakeFSValidationAcceptsRequiredLayout() throws {
        let rootURL = try makeFakeFSFixture()

        XCTAssertNoThrow(
            try PocketRootRootFSValidator.validateMaterializedFakeFS(at: rootURL)
        )
    }

    func testMaterializedFakeFSValidationRejectsMissingMetadataDatabase() throws {
        let rootURL = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("data", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try PocketRootRootFSValidator.validateMaterializedFakeFS(at: rootURL)
        ) { error in
            XCTAssertEqual(
                error as? PocketRootRootFSValidationError,
                .invalidFakeFS(
                    path: rootURL.path,
                    reason: "meta.db is missing or is not a file"
                )
            )
        }
    }

    func testMaterializedFakeFSValidationRejectsNonDirectoryDataPath() throws {
        let rootURL = try makeTemporaryDirectory()
        _ = FileManager.default.createFile(
            atPath: rootURL.appendingPathComponent("meta.db").path,
            contents: Data()
        )
        _ = FileManager.default.createFile(
            atPath: rootURL.appendingPathComponent("data").path,
            contents: Data()
        )

        XCTAssertThrowsError(
            try PocketRootRootFSValidator.validateMaterializedFakeFS(at: rootURL)
        ) { error in
            XCTAssertEqual(
                error as? PocketRootRootFSValidationError,
                .invalidFakeFS(
                    path: rootURL.path,
                    reason: "data is missing or is not a directory"
                )
            )
        }
    }

    func testMaterializedFakeFSValidationRejectsSymbolicLinkMetadata() throws {
        let rootURL = try makeFakeFSFixture()
        let metadataURL = rootURL.appendingPathComponent("meta.db")
        let realMetadataURL = rootURL.appendingPathComponent("real-meta.db")
        try FileManager.default.removeItem(at: metadataURL)
        _ = FileManager.default.createFile(atPath: realMetadataURL.path, contents: Data())
        try FileManager.default.createSymbolicLink(
            at: metadataURL,
            withDestinationURL: realMetadataURL
        )

        XCTAssertThrowsError(
            try PocketRootRootFSValidator.validateMaterializedFakeFS(at: rootURL)
        ) { error in
            XCTAssertEqual(
                error as? PocketRootRootFSValidationError,
                .invalidFakeFS(
                    path: rootURL.path,
                    reason: "meta.db must be a real regular file"
                )
            )
        }
    }

    func testGzipTarExtractorCreatesAuditableFakeFSLayout() throws {
        let archiveURL = try makeTemporaryFile(
            contents: try XCTUnwrap(Data(base64Encoded: Self.validFakeFSArchiveBase64))
        )
        let destinationURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("extracted", isDirectory: true)

        try PocketRootGzipTarExtractor().extract(
            archiveURL: archiveURL,
            to: destinationURL
        )

        let fakeFSURL = destinationURL.appendingPathComponent("fs", isDirectory: true)
        XCTAssertNoThrow(
            try PocketRootRootFSValidator.validateMaterializedFakeFS(at: fakeFSURL)
        )
        XCTAssertEqual(
            try Data(
                contentsOf: fakeFSURL.appendingPathComponent("data/hello.txt")
            ),
            Data("hello".utf8)
        )
    }

    func testGzipTarExtractorRejectsPathTraversalAndCleansDestination() throws {
        let archiveURL = try makeTemporaryFile(
            contents: try XCTUnwrap(Data(base64Encoded: Self.traversalArchiveBase64))
        )
        let directoryURL = archiveURL.deletingLastPathComponent()
        let destinationURL = directoryURL.appendingPathComponent("extracted", isDirectory: true)

        XCTAssertThrowsError(
            try PocketRootGzipTarExtractor().extract(
                archiveURL: archiveURL,
                to: destinationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootArchiveExtractionError,
                .unsafePath("../escape")
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directoryURL.appendingPathComponent("escape").path
            )
        )
    }

    func testGzipTarExtractorRejectsHostSymlinkEntries() throws {
        let archiveURL = try makeTemporaryFile(
            contents: try XCTUnwrap(Data(base64Encoded: Self.symlinkArchiveBase64))
        )
        let destinationURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("extracted", isDirectory: true)

        XCTAssertThrowsError(
            try PocketRootGzipTarExtractor().extract(
                archiveURL: archiveURL,
                to: destinationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootArchiveExtractionError,
                .unsupportedEntryType(path: "fs/link", type: 50)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testGzipTarExtractorRejectsDuplicateDirectories() throws {
        let archiveURL = try makeTemporaryFile(
            contents: try XCTUnwrap(Data(base64Encoded: Self.duplicateDirectoryArchiveBase64))
        )
        let destinationURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("extracted", isDirectory: true)

        XCTAssertThrowsError(
            try PocketRootGzipTarExtractor().extract(
                archiveURL: archiveURL,
                to: destinationURL
            )
        ) { error in
            guard case .fileSystemFailure(let message) =
                error as? PocketRootArchiveExtractionError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("duplicate entry"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testGzipTarExtractorRejectsCaseAliasedDirectoriesOnInsensitiveVolume() throws {
        let probeURL = try makeTemporaryDirectory()
        let lowercaseProbeURL = probeURL.appendingPathComponent(
            "pocketroot-case-probe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: lowercaseProbeURL,
            withIntermediateDirectories: false
        )
        guard FileManager.default.fileExists(
            atPath: probeURL.appendingPathComponent(
                "POCKETROOT-CASE-PROBE",
                isDirectory: true
            ).path
        ) else {
            throw XCTSkip("The test volume is case-sensitive.")
        }

        let archiveURL = try makeTemporaryFile(
            contents: try XCTUnwrap(
                Data(base64Encoded: Self.caseAliasedDirectoryArchiveBase64)
            )
        )
        let destinationURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("extracted", isDirectory: true)

        XCTAssertThrowsError(
            try PocketRootGzipTarExtractor().extract(
                archiveURL: archiveURL,
                to: destinationURL
            )
        ) { error in
            guard case .fileSystemFailure(let message) =
                error as? PocketRootArchiveExtractionError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("duplicate directory target"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testGzipTarExtractorRejectsSymbolicLinkSource() throws {
        let realArchiveURL = try makeValidFakeFSArchiveFile()
        let symbolicLinkURL = realArchiveURL.deletingLastPathComponent()
            .appendingPathComponent("linked-rootfs.tar.gz")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: realArchiveURL
        )
        let destinationURL = realArchiveURL.deletingLastPathComponent()
            .appendingPathComponent("extracted", isDirectory: true)

        XCTAssertThrowsError(
            try PocketRootGzipTarExtractor().extract(
                archiveURL: symbolicLinkURL,
                to: destinationURL
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootArchiveExtractionError,
                .sourceUnavailable(symbolicLinkURL.path)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testGzipTarExtractorEnforcesExpandedSizeLimit() throws {
        let archiveURL = try makeTemporaryFile(
            contents: try XCTUnwrap(Data(base64Encoded: Self.validFakeFSArchiveBase64))
        )
        let destinationURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("extracted", isDirectory: true)

        XCTAssertThrowsError(
            try PocketRootGzipTarExtractor(
                maximumExpandedArchiveByteCount: 512
            ).extract(archiveURL: archiveURL, to: destinationURL)
        ) { error in
            XCTAssertEqual(
                error as? PocketRootArchiveExtractionError,
                .expandedSizeLimitExceeded(512)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testRootFSInstallerInstallsThenReusesVerifiedVersion() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let baseURL = try makeTemporaryDirectory()
        let installer = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: makeFixtureManifest(version: "fixture-v1")
        )

        let first = try await installer.prepareArchive(at: archiveURL)
        XCTAssertFalse(first.reusedExistingInstallation)
        XCTAssertEqual(first.version, "fixture-v1")
        XCTAssertEqual(
            first.rootFSURL,
            baseURL.appendingPathComponent("rootfs/fixture-v1", isDirectory: true)
        )
        try PocketRootRootFSValidator.validateMaterializedFakeFS(at: first.rootFSURL)

        let unavailableArchiveURL = baseURL.appendingPathComponent("missing.tar.gz")
        let second = try await installer.prepareArchive(at: unavailableArchiveURL)
        XCTAssertTrue(second.reusedExistingInstallation)
        XCTAssertEqual(second.rootFSURL, first.rootFSURL)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: baseURL.appendingPathComponent("rootfs/current.json").path
            )
        )
    }

    func testRootFSInstallerExtractsTheValidatedPrivateSnapshot() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let baseURL = try makeTemporaryDirectory()
        let manifest = makeFixtureManifest(version: "fixture-v1")
        let installer = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: manifest,
            testHooks: RootFSInstallerTestHooks(
                archiveSnapshotHandler: { _ in
                    try! Data("replaced-after-validation".utf8).write(
                        to: archiveURL,
                        options: .atomic
                    )
                }
            )
        )

        let installation = try await installer.prepareArchive(at: archiveURL)

        XCTAssertEqual(
            try Data(
                contentsOf: installation.rootFSURL.appendingPathComponent(
                    "data/hello.txt"
                )
            ),
            Data("hello".utf8)
        )
        XCTAssertThrowsError(
            try PocketRootRootFSValidator.validateArchive(
                at: archiveURL,
                against: manifest
            )
        )
    }

    func testRootFSInstallerBoundsThePrivateArchiveSnapshot() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let baseURL = try makeTemporaryDirectory()
        let installer = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: makeFixtureManifest(version: "fixture-v1"),
            maximumArchiveByteCount: 170
        )

        do {
            _ = try await installer.prepareArchive(at: archiveURL)
            XCTFail("An archive larger than the staging limit must fail.")
        } catch {
            XCTAssertEqual(
                error as? PocketRootRootFSInstallationError,
                .archiveCopyLimitExceeded(170)
            )
        }

        let rootFSDirectoryURL = baseURL.appendingPathComponent(
            "rootfs",
            isDirectory: true
        )
        let names = try FileManager.default.contentsOfDirectory(
            atPath: rootFSDirectoryURL.path
        )
        XCTAssertFalse(names.contains(where: { $0.hasPrefix(".installing-") }))
    }

    func testRootFSInstallerRecoversPreviousVersionBeforeStagingCleanup() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let baseURL = try makeTemporaryDirectory()
        let manifest = makeFixtureManifest(version: "fixture-v1")
        let installer = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: manifest
        )
        let first = try await installer.prepareArchive(at: archiveURL)
        let rootFSDirectoryURL = baseURL.appendingPathComponent(
            "rootfs",
            isDirectory: true
        )
        let currentRecordURL = rootFSDirectoryURL.appendingPathComponent("current.json")
        let previousCurrentRecordData = try Data(contentsOf: currentRecordURL)
        let transactionURL = try makePromotionTransaction(
            rootFSDirectoryURL: rootFSDirectoryURL,
            manifest: manifest,
            hadPreviousInstallation: true,
            previousCurrentRecordData: previousCurrentRecordData
        )
        try FileManager.default.moveItem(
            at: first.rootFSURL,
            to: transactionURL.appendingPathComponent(
                PocketRootRootFSInstaller.previousInstallationDirectoryName,
                isDirectory: true
            )
        )
        let staleStagingURL = rootFSDirectoryURL.appendingPathComponent(
            ".installing-fixture-v1-interrupted",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: staleStagingURL,
            withIntermediateDirectories: false
        )

        let recovered = try await installer.prepareArchive(
            at: baseURL.appendingPathComponent("archive-is-no-longer-available.tar.gz")
        )

        XCTAssertTrue(recovered.reusedExistingInstallation)
        XCTAssertEqual(recovered.rootFSURL, first.rootFSURL)
        XCTAssertEqual(try Data(contentsOf: currentRecordURL), previousCurrentRecordData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: transactionURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleStagingURL.path))
    }

    func testRootFSInstallerCompletesInterruptedCandidateCommit() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let sourceBaseURL = try makeTemporaryDirectory()
        let targetBaseURL = try makeTemporaryDirectory()
        let manifest = makeFixtureManifest(version: "fixture-v1")
        let sourceInstaller = PocketRootRootFSInstaller(
            baseDirectoryURL: sourceBaseURL,
            manifest: manifest
        )
        let source = try await sourceInstaller.prepareArchive(at: archiveURL)

        let targetRootFSDirectoryURL = targetBaseURL.appendingPathComponent(
            "rootfs",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: targetRootFSDirectoryURL,
            withIntermediateDirectories: true
        )
        let transactionURL = try makePromotionTransaction(
            rootFSDirectoryURL: targetRootFSDirectoryURL,
            manifest: manifest,
            hadPreviousInstallation: false,
            previousCurrentRecordData: nil
        )
        let targetFinalURL = targetRootFSDirectoryURL.appendingPathComponent(
            manifest.version,
            isDirectory: true
        )
        try FileManager.default.copyItem(at: source.rootFSURL, to: targetFinalURL)

        let targetInstaller = PocketRootRootFSInstaller(
            baseDirectoryURL: targetBaseURL,
            manifest: manifest
        )
        let recovered = try await targetInstaller.prepareArchive(
            at: targetBaseURL.appendingPathComponent("missing.tar.gz")
        )

        XCTAssertTrue(recovered.reusedExistingInstallation)
        XCTAssertEqual(recovered.rootFSURL, targetFinalURL)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: targetRootFSDirectoryURL.appendingPathComponent(
                    "current.json"
                ).path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: transactionURL.path))
    }

    func testRootFSInstallerRejectsReservedVersionNames() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()

        for version in ["current.json", ".installing-fixture", "版本1"] {
            let installer = PocketRootRootFSInstaller(
                baseDirectoryURL: try makeTemporaryDirectory(),
                manifest: makeFixtureManifest(version: version)
            )

            do {
                _ = try await installer.prepareArchive(at: archiveURL)
                XCTFail("Reserved version \(version) must be rejected.")
            } catch {
                XCTAssertEqual(
                    error as? PocketRootRootFSInstallationError,
                    .invalidVersion(version)
                )
            }
        }
    }

    func testRootFSInstallerReplacesCorruptVersionOnlyAfterValidation() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let baseURL = try makeTemporaryDirectory()
        let installer = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: makeFixtureManifest(version: "fixture-v1")
        )

        let first = try await installer.prepareArchive(at: archiveURL)
        try FileManager.default.removeItem(
            at: first.rootFSURL.appendingPathComponent("meta.db")
        )

        let repaired = try await installer.prepareArchive(at: archiveURL)
        XCTAssertFalse(repaired.reusedExistingInstallation)
        XCTAssertEqual(
            try Data(contentsOf: repaired.rootFSURL.appendingPathComponent("meta.db")),
            Data("metadata".utf8)
        )
    }

    func testRootFSInstallerRollsBackAPromotionFailure() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let baseURL = try makeTemporaryDirectory()
        let manifest = makeFixtureManifest(version: "fixture-v1")
        let initialInstaller = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: manifest
        )
        let initial = try await initialInstaller.prepareArchive(at: archiveURL)
        let currentRecordURL = baseURL.appendingPathComponent("rootfs/current.json")
        let originalCurrentRecord = try Data(contentsOf: currentRecordURL)
        let markerURL = initial.rootFSURL.appendingPathComponent("user-data-marker")
        try Data("preserve-me".utf8).write(to: markerURL)
        try FileManager.default.removeItem(
            at: initial.rootFSURL.appendingPathComponent("meta.db")
        )

        let failingInstaller = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: manifest,
            testHooks: RootFSInstallerTestHooks(
                promotionCheckpointHandler: { checkpoint in
                    if checkpoint == .previousInstallationMoved {
                        throw PocketRootRootFSInstallationError.installationFailed(
                            "Injected promotion failure."
                        )
                    }
                }
            )
        )

        do {
            _ = try await failingInstaller.prepareArchive(at: archiveURL)
            XCTFail("The injected promotion failure must escape.")
        } catch let error as PocketRootRootFSInstallationError {
            guard case .installationFailed = error else {
                return XCTFail("Unexpected installation error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: markerURL), Data("preserve-me".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: initial.rootFSURL.appendingPathComponent("meta.db").path
            )
        )
        XCTAssertEqual(try Data(contentsOf: currentRecordURL), originalCurrentRecord)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: baseURL.appendingPathComponent(
                    "rootfs/\(PocketRootRootFSInstaller.replacementTransactionDirectoryName)"
                ).path
            )
        )
    }

    func testRootFSInstallerFailedUpgradePreservesCurrentInstallation() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let baseURL = try makeTemporaryDirectory()
        let firstInstaller = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: makeFixtureManifest(version: "fixture-v1")
        )
        let first = try await firstInstaller.prepareArchive(at: archiveURL)
        let currentURL = baseURL.appendingPathComponent("rootfs/current.json")
        let originalCurrentRecord = try Data(contentsOf: currentURL)

        let invalidUpgradeManifest = PocketRootRootFSArtifactManifest(
            version: "fixture-v2",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/rootfs.tar.gz")!,
            sha256: String(repeating: "0", count: 64),
            archiveByteCount: 171,
            expandedArchiveByteCount: 10_240
        )
        let upgradeInstaller = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: invalidUpgradeManifest
        )

        do {
            _ = try await upgradeInstaller.prepareArchive(at: archiveURL)
            XCTFail("A digest mismatch must reject the upgrade.")
        } catch let error as PocketRootRootFSValidationError {
            guard case .sha256Mismatch = error else {
                return XCTFail("Unexpected validation error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: currentURL), originalCurrentRecord)
        try PocketRootRootFSValidator.validateMaterializedFakeFS(at: first.rootFSURL)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: baseURL.appendingPathComponent("rootfs/fixture-v2").path
            )
        )
    }

    func testConcurrentRootFSPreparationPerformsOneInstallation() async throws {
        let archiveURL = try makeValidFakeFSArchiveFile()
        let baseURL = try makeTemporaryDirectory()
        let installer = PocketRootRootFSInstaller(
            baseDirectoryURL: baseURL,
            manifest: makeFixtureManifest(version: "fixture-v1")
        )

        async let first = installer.prepareArchive(at: archiveURL)
        async let second = installer.prepareArchive(at: archiveURL)
        let results = try await [first, second]

        XCTAssertEqual(
            results.map(\.reusedExistingInstallation).filter { !$0 }.count,
            1
        )
        XCTAssertEqual(results[0].rootFSURL, results[1].rootFSURL)
    }

    func testPinnedReleaseArchiveWhenProvidedByEnvironment() async throws {
        guard let archivePath = ProcessInfo.processInfo.environment[
            "POCKETROOT_ROOTFS_ARCHIVE"
        ] else {
            throw XCTSkip("Set POCKETROOT_ROOTFS_ARCHIVE for the release-asset integration test.")
        }

        let archiveURL = URL(fileURLWithPath: archivePath)
        try PocketRootRootFSValidator.validateArchive(at: archiveURL)
        let installer = PocketRootRootFSInstaller(
            baseDirectoryURL: try makeTemporaryDirectory()
        )
        let installation = try await installer.prepareArchive(at: archiveURL)
        try PocketRootRootFSValidator.validateMaterializedFakeFS(
            at: installation.rootFSURL
        )
        XCTAssertFalse(installation.reusedExistingInstallation)
    }

    private func makeFakeFSFixture() throws -> URL {
        let rootURL = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("data", isDirectory: true),
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(
            atPath: rootURL.appendingPathComponent("meta.db").path,
            contents: Data()
        )
        return rootURL
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketRootResourcesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeTemporaryFile(contents: Data) throws -> URL {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("rootfs.tar.gz")
        try contents.write(to: fileURL)
        return fileURL
    }

    private func makeValidFakeFSArchiveFile() throws -> URL {
        try makeTemporaryFile(
            contents: try XCTUnwrap(Data(base64Encoded: Self.validFakeFSArchiveBase64))
        )
    }

    private func makeFixtureManifest(
        version: String
    ) -> PocketRootRootFSArtifactManifest {
        PocketRootRootFSArtifactManifest(
            version: version,
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/rootfs.tar.gz")!,
            sha256: "4ede5b57ad2a2ee908076eaed25c3736f3ea9214cc75ba6081f1871b4716a05c",
            archiveByteCount: 171,
            expandedArchiveByteCount: 10_240
        )
    }

    private func makePromotionTransaction(
        rootFSDirectoryURL: URL,
        manifest: PocketRootRootFSArtifactManifest,
        hadPreviousInstallation: Bool,
        previousCurrentRecordData: Data?
    ) throws -> URL {
        let transactionURL = rootFSDirectoryURL.appendingPathComponent(
            PocketRootRootFSInstaller.replacementTransactionDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: transactionURL,
            withIntermediateDirectories: false
        )
        let journal = PromotionJournal(
            version: manifest.version,
            expectedRecord: InstallationRecord(manifest: manifest),
            hadPreviousInstallation: hadPreviousInstallation,
            previousCurrentRecordData: previousCurrentRecordData
        )
        try JSONEncoder().encode(journal).write(
            to: transactionURL.appendingPathComponent(
                PocketRootRootFSInstaller.promotionJournalFileName
            ),
            options: .atomic
        )
        return transactionURL
    }

    private static let validFakeFSArchiveBase64 =
        "H4sIAAAAAAAC/+3VMQ6CMBiG4R6FE0ArtD1PDRAHjImtice3MAnK4PA3MbzPUoYmDG/4GGOjpOnMW7uc2fb88uzafL2yqoBHTOGeX6mOaYzNdUih7s+y/V3X7fc32/7eaaMqTX9xc/w+pKBw1O9/zi/6E/h9//3JOfa/ZP/LME23Oj2T1P5/dn9rbtf9TWbZ/xKW7swgAAAAAAAAAAAAAPy9F8wBBB8AKAAA"
    private static let traversalArchiveBase64 =
        "H4sIAAAAAAAC/+3NPQqDQBgE0O8onsAIu5jzbNQ++HN/11Rin4DkvWaGaaZtH9MylPcU39NVfc6frK5ZpVM/9mdKOZoufmBb1jLXy/hPrzIGAAAAAAAAAAAA97MDz0AGZgAoAAA="
    private static let symlinkArchiveBase64 =
        "H4sIAAAAAAAC/+3OuwmEQAAE0C3lKvB/14+ggigKt9q/i6HGBsJ7yUw2M8R8HpcpPKlIfk1zZnLNey/Lov6GT5Vl+bpvcez6587tcWv/aT4AAAAAAAAAAADAexzHriFiACgAAA=="
    private static let duplicateDirectoryArchiveBase64 =
        "H4sIAKjkYGoAA0sr1megNTAAAnNTUzANBOg0FraZMVC5ginNXQYEpcUliUVAK+lh1yAEaaPxP6LjfxSMglEwcgEA5ciDeAAIAAA="
    private static let caseAliasedDirectoryArchiveBase64 =
        "H4sIAG3oYGoAA0sr1megNTAAAnNTUzANBOg0FraZMVC5ginNXQYEpcUliUVAK+lh1yAEbsGDMv6NRuN/FIyCUTAKaAsAkTbGfQAIAAA="
}
