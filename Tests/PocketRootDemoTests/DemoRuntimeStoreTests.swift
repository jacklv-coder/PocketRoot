import Foundation
import XCTest
@testable import PocketRootDemo

@MainActor
final class DemoRuntimeStoreTests: XCTestCase {
    func testMissingRootFSKeepsRuntimeUnbootable() throws {
        let fixture = try makeBundle(includesRootFS: false)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let store = DemoRuntimeStore(
            bundle: fixture.bundle,
            runtimeAvailable: true,
            applicationSupportURL: fixture.directory
                .appendingPathComponent("ApplicationSupport", isDirectory: true)
        )

        XCTAssertEqual(store.phase, .rootFSMissing)
        XCTAssertFalse(store.canBoot)
        XCTAssertNil(store.readySystem)
        XCTAssertEqual(
            store.rootFSStatus,
            DemoDiagnosticStatus(text: "Missing", isReady: false)
        )
        XCTAssertEqual(
            store.runtimeStatus,
            DemoDiagnosticStatus(text: "Available", isReady: true)
        )
    }

    func testEmbeddedRootFSMakesDebugRuntimeBootable() throws {
        let fixture = try makeBundle(includesRootFS: true)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let store = DemoRuntimeStore(
            bundle: fixture.bundle,
            runtimeAvailable: true,
            applicationSupportURL: fixture.directory
                .appendingPathComponent("ApplicationSupport", isDirectory: true)
        )

        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(store.canBoot)
        XCTAssertNotNil(store.rootFSArchiveURL)
        XCTAssertEqual(
            store.rootFSStatus,
            DemoDiagnosticStatus(text: "Embedded", isReady: true)
        )
    }

    func testUnavailableNativeRuntimeFailsClosedEvenWithRootFS() throws {
        let fixture = try makeBundle(includesRootFS: true)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let store = DemoRuntimeStore(
            bundle: fixture.bundle,
            runtimeAvailable: false,
            applicationSupportURL: fixture.directory
                .appendingPathComponent("ApplicationSupport", isDirectory: true)
        )

        XCTAssertEqual(store.phase, .runtimeUnavailable)
        XCTAssertFalse(store.canBoot)
        XCTAssertEqual(
            store.runtimeStatus,
            DemoDiagnosticStatus(text: "Unavailable", isReady: false)
        )
    }

    func testPreparationFailureRemainsRetryableBeforeRuntimeCreation() async throws {
        let fixture = try makeBundle(
            includesRootFS: true,
            rootFSIsDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let store = DemoRuntimeStore(
            bundle: fixture.bundle,
            runtimeAvailable: true,
            applicationSupportURL: fixture.directory
                .appendingPathComponent("ApplicationSupport", isDirectory: true)
        )

        await store.boot()

        guard case .failed = store.phase else {
            return XCTFail("An invalid fixture archive should fail preparation.")
        }
        XCTAssertNil(store.system)
        XCTAssertTrue(store.canBoot)
    }

    func testRejectedShutdownPreservesUnderlyingReadyState() {
        let phase = DemoRuntimeStore.reconciledPhase(
            for: .ready,
            hasInstallation: true,
            fallbackFailure: "Wait for the active command to finish."
        )

        XCTAssertEqual(phase, .ready)
    }

    func testFatalRuntimeStateReconcilesToFailure() {
        let phase = DemoRuntimeStore.reconciledPhase(
            for: .failed("transport unavailable"),
            hasInstallation: true
        )

        XCTAssertEqual(phase, .failed("transport unavailable"))
    }

    func testEndedTerminalOffersANewSession() {
        XCTAssertEqual(
            TerminalDemoViewController.sessionEndedMessage(for: .exited(0)),
            "The terminal session ended. Open a new terminal to continue."
        )
        XCTAssertEqual(
            TerminalDemoViewController.sessionEndedMessage(for: .exited(7)),
            "The terminal session exited with code 7.\nOpen a new terminal to continue."
        )
        XCTAssertEqual(
            TerminalDemoViewController.sessionEndedMessage(for: .failed("PTY unavailable")),
            [
                "The terminal session failed:",
                "PTY unavailable",
                "Open a new terminal to try again."
            ].joined(separator: "\n")
        )
    }

    func testFailedTerminalChecksRuntimeBeforeOfferingANewSession() {
        XCTAssertEqual(
            TerminalDemoViewController.sessionFailureCheckingMessage(
                for: .failed("transport unavailable")
            ),
            [
                "The terminal session failed:",
                "transport unavailable",
                "Checking runtime state…"
            ].joined(separator: "\n")
        )
    }

    private func makeBundle(
        includesRootFS: Bool,
        rootFSIsDirectory: Bool = false
    ) throws -> (bundle: Bundle, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let info = [
            "CFBundleIdentifier": "com.jacklv.PocketRootDemoTests.\(UUID().uuidString)",
            "CFBundleName": "PocketRootDemoFixture",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1"
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: directory.appendingPathComponent("Info.plist"))

        if includesRootFS {
            let archiveURL = directory
                .appendingPathComponent(DemoRuntimeStore.rootFSResourceName)
                .appendingPathExtension(DemoRuntimeStore.rootFSResourceExtension)
            if rootFSIsDirectory {
                try FileManager.default.createDirectory(
                    at: archiveURL,
                    withIntermediateDirectories: false
                )
            } else {
                try Data("fixture".utf8).write(to: archiveURL)
            }
        }

        guard let bundle = Bundle(url: directory) else {
            XCTFail("Unable to create the fixture bundle.")
            throw CocoaError(.fileReadUnknown)
        }
        return (bundle, directory)
    }
}
