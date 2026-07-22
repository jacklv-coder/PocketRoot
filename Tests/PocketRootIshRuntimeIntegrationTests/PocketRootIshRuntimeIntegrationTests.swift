import Foundation
import PocketRootCore
import PocketRootResources
import XCTest
@testable import PocketRootIshRuntimeIntegration

@available(macOS 13.0, *)
final class PocketRootIshRuntimeIntegrationTests: XCTestCase {
    func testFactoryDerivesHealthDefaultFromManifest() {
        XCTAssertEqual(
            PocketRootIshSystemFactory.defaultHealthCheck(for: .ishEmbedV0_3_3),
            .ishEmbedV0_3_3
        )

        let customManifest = PocketRootRootFSArtifactManifest(
            version: "custom-v1",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/custom.tar.gz")!,
            sha256: String(repeating: "0", count: 64)
        )
        XCTAssertEqual(
            PocketRootIshSystemFactory.defaultHealthCheck(for: customManifest),
            .alpineARM64
        )
    }

    func testFactoryPreparesArchiveAndAlignsSystemVersion() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketRootIntegrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let archiveURL = directoryURL.appendingPathComponent("rootfs.tar.gz")
        try XCTUnwrap(Data(base64Encoded: Self.archiveBase64)).write(to: archiveURL)
        let manifest = PocketRootRootFSArtifactManifest(
            version: "fixture-v1",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/rootfs.tar.gz")!,
            sha256: "4ede5b57ad2a2ee908076eaed25c3736f3ea9214cc75ba6081f1871b4716a05c",
            archiveByteCount: 171,
            expandedArchiveByteCount: 10_240
        )

        let prepared = try await PocketRootIshSystemFactory.prepareSystem(
            archiveURL: archiveURL,
            applicationSupportURL: directoryURL.appendingPathComponent(
                "Application Support/PocketRoot",
                isDirectory: true
            ),
            manifest: manifest,
            systemConfiguration: PocketRootConfiguration(
                rootFSVersion: "must-be-replaced",
                defaultWorkingDirectory: "/srv/vms/default",
                commandTimeout: .seconds(17)
            )
        )

        XCTAssertEqual(prepared.installation.version, "fixture-v1")
        let configuration = await prepared.system.configuration
        XCTAssertEqual(configuration.rootFSVersion, "fixture-v1")
        XCTAssertEqual(configuration.defaultWorkingDirectory, "/srv/vms/default")
        XCTAssertEqual(configuration.commandTimeout, .seconds(17))
        try PocketRootRootFSValidator.validateMaterializedFakeFS(
            at: prepared.installation.rootFSURL
        )
    }

    private static let archiveBase64 =
        "H4sIAAAAAAAC/+3VMQ6CMBiG4R6FE0ArtD1PDRAHjImtice3MAnK4PA3MbzPUoYmDG/4GGOjpOnMW7uc2fb88uzafL2yqoBHTOGeX6mOaYzNdUih7s+y/V3X7fc32/7eaaMqTX9xc/w+pKBw1O9/zi/6E/h9//3JOfa/ZP/LME23Oj2T1P5/dn9rbtf9TWbZ/xKW7swgAAAAAAAAAAAAAPy9F8wBBB8AKAAA"
}
