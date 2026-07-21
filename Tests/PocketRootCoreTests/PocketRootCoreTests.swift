import Foundation
import XCTest
@testable import PocketRootCore

@available(macOS 13.0, *)
final class PocketRootCoreTests: XCTestCase {
    func testCommandRequestUsesDocumentedDefaults() {
        let request = PocketRootCommandRequest(command: "uname -m")

        XCTAssertEqual(request.command, "uname -m")
        XCTAssertEqual(request.workingDirectory, "/root")
        XCTAssertEqual(request.environment, [:])
        XCTAssertEqual(request.timeout, .seconds(30))
        XCTAssertFalse(request.mergeStandardError)
    }

    func testCommandResultDecodesStandardStreams() {
        let result = PocketRootCommandResult(
            exitCode: 7,
            signal: 15,
            standardOutput: Data("stdout".utf8),
            standardError: Data("stderr".utf8),
            timedOut: true
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.signal, 15)
        XCTAssertEqual(result.stdout, "stdout")
        XCTAssertEqual(result.stderr, "stderr")
        XCTAssertTrue(result.timedOut)
    }

    func testConfigurationUsesPocketRootDefaults() {
        let configuration = PocketRootConfiguration()

        XCTAssertEqual(configuration.rootFSVersion, PocketRootDefaults.rootFSVersion)
        XCTAssertEqual(configuration.defaultWorkingDirectory, "/root")
        XCTAssertEqual(configuration.commandTimeout, PocketRootDefaults.commandTimeout)
    }

    func testPlaceholderSystemReportsUnsupportedBoot() async {
        let system = PocketRootSystem()

        do {
            try await system.boot()
            XCTFail("Placeholder boot should fail")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .unsupportedOperation("Linux Runtime has not been integrated yet.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let state = await system.state
        XCTAssertEqual(state, .idle)
    }

    func testPlaceholderSystemRejectsCommandsAndCanShutdown() async throws {
        let system = PocketRootSystem()

        do {
            _ = try await system.execute(PocketRootCommandRequest(command: "true"))
            XCTFail("Placeholder execution should fail")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .runtimeNotBooted)
            XCTAssertEqual(error.localizedDescription, "Linux Runtime is not booted.")
        }

        try await system.shutdown()
        let state = await system.state
        XCTAssertEqual(state, .idle)
    }

    func testSystemDelegatesToInjectedRuntime() async throws {
        let runtime = StubLinuxRuntime()
        let system = PocketRootSystem(runtime: runtime)

        try await system.boot()
        let bootedState = await system.state
        XCTAssertEqual(bootedState, .ready)

        let result = try await system.execute(
            PocketRootCommandRequest(command: "printf ready")
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "ready")

        try await system.shutdown()
        let shutdownState = await system.state
        XCTAssertEqual(shutdownState, .idle)
    }

    func testSystemRefreshesStateWhenShutdownFails() async throws {
        let runtime = FailingShutdownRuntime()
        let system = PocketRootSystem(runtime: runtime)

        try await system.boot()

        do {
            try await system.shutdown()
            XCTFail("The injected runtime should fail shutdown.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .runtimeFailure("Synthetic shutdown failure."))
        }

        let state = await system.state
        XCTAssertEqual(state, .failed("Synthetic shutdown failure."))
    }

    func testRootFSManagerRequiresAProvider() async {
        let manager = RootFSManager()

        do {
            _ = try await manager.prepareRootFS()
            XCTFail("RootFS preparation should fail without a provider")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .unsupportedOperation("RootFS provider has not been integrated yet.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRootFSManagerStoresPreparedMetadata() async throws {
        let expected = RootFSMetadata(
            version: "1",
            rootURL: URL(fileURLWithPath: "/tmp/pocketroot-rootfs")
        )
        let manager = RootFSManager(provider: StubRootFSProvider(metadata: expected))

        let prepared = try await manager.prepareRootFS(version: "1")
        let stored = await manager.metadata

        XCTAssertEqual(prepared, expected)
        XCTAssertEqual(stored, expected)
    }
}

@available(macOS 13.0, *)
private actor StubLinuxRuntime: LinuxRuntime {
    private(set) var state: PocketRootRuntimeState = .idle

    func boot(configuration: PocketRootConfiguration) async throws {
        state = .ready
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        guard state == .ready else {
            throw PocketRootError.runtimeNotBooted
        }

        return PocketRootCommandResult(
            exitCode: 0,
            standardOutput: Data("ready".utf8)
        )
    }

    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        StubSession(configuration: configuration)
    }

    func shutdown() async throws {
        state = .idle
    }
}

@available(macOS 13.0, *)
private actor FailingShutdownRuntime: LinuxRuntime {
    private(set) var state: PocketRootRuntimeState = .idle

    func boot(configuration: PocketRootConfiguration) async throws {
        state = .ready
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func shutdown() async throws {
        state = .failed("Synthetic shutdown failure.")
        throw PocketRootError.runtimeFailure("Synthetic shutdown failure.")
    }
}

@available(macOS 13.0, *)
private struct StubSession: PocketRootSession {
    let configuration: PocketRootSessionConfiguration
    let events: AsyncStream<PocketRootSessionEvent>

    init(configuration: PocketRootSessionConfiguration) {
        self.configuration = configuration
        events = AsyncStream { continuation in
            continuation.finish()
        }
    }

    func write(_ data: Data) async throws {}

    func terminate() async {}
}

private struct StubRootFSProvider: RootFSProvider {
    let metadata: RootFSMetadata

    func prepareRootFS(version: String) async throws -> RootFSMetadata {
        metadata
    }
}
