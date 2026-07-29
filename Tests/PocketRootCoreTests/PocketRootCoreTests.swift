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

        try await system.renameItem(
            at: "/root/before.txt",
            to: "/root/after.txt",
            timeout: .seconds(3)
        )
        let rename = await runtime.lastRename
        XCTAssertEqual(rename?.sourcePath, "/root/before.txt")
        XCTAssertEqual(rename?.destinationPath, "/root/after.txt")
        XCTAssertEqual(rename?.timeout, .seconds(3))

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

    func testSystemRefreshesStateWhenExecuteFailsClosed() async throws {
        let runtime = FailingExecuteRuntime()
        let system = PocketRootSystem(runtime: runtime)

        try await system.boot()

        do {
            _ = try await system.execute(PocketRootCommandRequest(command: "sleep 30"))
            XCTFail("The injected runtime should fail the command closed.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .runtimeFailure("Synthetic unconfirmed guest exit."))
        }

        let state = await system.state
        XCTAssertEqual(state, .failed("Synthetic unconfirmed guest exit."))
    }

    func testSystemStateReadObservesAsynchronousRuntimeFailure() async throws {
        let runtime = AsynchronouslyFailingRuntime()
        let system = PocketRootSystem(runtime: runtime)

        try await system.boot()
        let readyState = await system.state
        XCTAssertEqual(readyState, .ready)

        await runtime.failAfterSessionCreation()

        let failedState = await system.state
        XCTAssertEqual(
            failedState,
            .failed("Synthetic asynchronous PTY failure.")
        )
    }

    func testReentrantExecuteDoesNotPublishTransientBootState() async throws {
        let bootStarted = expectation(description: "boot entered its suspension")
        let bootGate = TestAsyncGate()
        let runtime = SuspendingBootRuntime(bootStarted: bootStarted, bootGate: bootGate)
        let system = PocketRootSystem(runtime: runtime)

        let bootTask = Task {
            try await system.boot()
        }
        await fulfillment(of: [bootStarted], timeout: 2)

        do {
            _ = try await system.execute(PocketRootCommandRequest(command: "true"))
            XCTFail("A command admitted during boot must fail.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .runtimeFailure("Synthetic boot is still in progress."))
        }

        let stateWhileBooting = await system.state
        XCTAssertEqual(stateWhileBooting, .idle)

        await bootGate.open()
        try await bootTask.value
        let readyState = await system.state
        XCTAssertEqual(readyState, .ready)
    }

    func testStaleCommandRefreshCannotOverwriteNewerFailedState() async throws {
        let staleStateCaptured = expectation(description: "stale ready state captured")
        let staleStateGate = TestAsyncGate()
        let runtime = StaleStateReadRuntime(
            staleStateCaptured: staleStateCaptured,
            staleStateGate: staleStateGate
        )
        let system = PocketRootSystem(runtime: runtime)

        try await system.boot()

        let staleCommand = Task {
            try await system.execute(PocketRootCommandRequest(command: "capture-stale-state"))
        }
        await fulfillment(of: [staleStateCaptured], timeout: 2)

        do {
            _ = try await system.execute(PocketRootCommandRequest(command: "fail-closed"))
            XCTFail("The second command should fail closed.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .runtimeFailure("Synthetic concurrent failure."))
        }

        let failedState = await system.state
        XCTAssertEqual(failedState, .failed("Synthetic concurrent failure."))

        await staleStateGate.open()
        _ = try await staleCommand.value

        let finalState = await system.state
        XCTAssertEqual(finalState, .failed("Synthetic concurrent failure."))
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
    struct Rename: Sendable {
        let sourcePath: String
        let destinationPath: String
        let timeout: Duration
    }

    private(set) var state: PocketRootRuntimeState = .idle
    private(set) var lastRename: Rename?

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

    func renameItem(
        at sourcePath: String,
        to destinationPath: String,
        timeout: Duration
    ) async throws {
        guard state == .ready else {
            throw PocketRootError.runtimeNotBooted
        }
        lastRename = Rename(
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            timeout: timeout
        )
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
private actor FailingExecuteRuntime: LinuxRuntime {
    private(set) var state: PocketRootRuntimeState = .idle

    func boot(configuration: PocketRootConfiguration) async throws {
        state = .ready
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        state = .failed("Synthetic unconfirmed guest exit.")
        throw PocketRootError.runtimeFailure("Synthetic unconfirmed guest exit.")
    }

    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func shutdown() async throws {
        throw PocketRootError.restartRequired
    }
}

@available(macOS 13.0, *)
private actor AsynchronouslyFailingRuntime: LinuxRuntime {
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
        StubSession(configuration: configuration)
    }

    func shutdown() async throws {
        state = .terminated
    }

    func failAfterSessionCreation() {
        state = .failed("Synthetic asynchronous PTY failure.")
    }
}

@available(macOS 13.0, *)
private actor SuspendingBootRuntime: LinuxRuntime {
    private(set) var state: PocketRootRuntimeState = .idle

    private let bootStarted: XCTestExpectation
    private let bootGate: TestAsyncGate

    init(bootStarted: XCTestExpectation, bootGate: TestAsyncGate) {
        self.bootStarted = bootStarted
        self.bootGate = bootGate
    }

    func boot(configuration: PocketRootConfiguration) async throws {
        state = .booting
        bootStarted.fulfill()
        await bootGate.wait()
        state = .ready
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        throw PocketRootError.runtimeFailure("Synthetic boot is still in progress.")
    }

    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func shutdown() async throws {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }
}

@available(macOS 13.0, *)
private actor StaleStateReadRuntime: LinuxRuntime {
    private var storedState: PocketRootRuntimeState = .idle
    private var suspendNextStateRead = false

    private let staleStateCaptured: XCTestExpectation
    private let staleStateGate: TestAsyncGate

    init(staleStateCaptured: XCTestExpectation, staleStateGate: TestAsyncGate) {
        self.staleStateCaptured = staleStateCaptured
        self.staleStateGate = staleStateGate
    }

    var state: PocketRootRuntimeState {
        get async {
            let snapshot = storedState
            guard suspendNextStateRead else {
                return snapshot
            }

            suspendNextStateRead = false
            staleStateCaptured.fulfill()
            await staleStateGate.wait()
            return snapshot
        }
    }

    func boot(configuration: PocketRootConfiguration) async throws {
        storedState = .ready
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        switch request.command {
        case "capture-stale-state":
            suspendNextStateRead = true
            return PocketRootCommandResult(exitCode: 0)
        case "fail-closed":
            storedState = .failed("Synthetic concurrent failure.")
            throw PocketRootError.runtimeFailure("Synthetic concurrent failure.")
        default:
            throw PocketRootError.unsupportedOperation("Unexpected test command.")
        }
    }

    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func shutdown() async throws {
        storedState = .idle
    }
}

private actor TestAsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
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

    func resize(to size: PocketRootTerminalSize) async throws {}

    func sendSignal(_ signal: Int32) async throws {}

    func closeInput() async throws {}

    func terminate() async {}
}

private struct StubRootFSProvider: RootFSProvider {
    let metadata: RootFSMetadata

    func prepareRootFS(version: String) async throws -> RootFSMetadata {
        metadata
    }
}
