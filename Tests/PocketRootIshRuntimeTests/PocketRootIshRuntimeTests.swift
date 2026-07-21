import Foundation
import PocketRootCore
import XCTest
@testable import PocketRootIshRuntime

@available(macOS 13.0, *)
final class PocketRootIshRuntimeTests: XCTestCase {
    func testConfigurationPreservesFakeFSLocation() {
        let url = URL(fileURLWithPath: "/tmp/PocketRootFakeFS")
        let configuration = PocketRootIshRuntimeConfiguration(rootFSURL: url)

        XCTAssertEqual(configuration.rootFSURL, url)
        XCTAssertEqual(configuration.workDirectory, "/")
        XCTAssertNil(configuration.supervisorGuestPath)
        XCTAssertEqual(configuration.kernelLogFileDescriptor, -1)
        XCTAssertEqual(configuration.maximumStandardOutputBytes, 8 * 1_024 * 1_024)
        XCTAssertEqual(configuration.maximumStandardErrorBytes, 4 * 1_024 * 1_024)
    }

    func testBootRejectsInvalidFakeFS() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: missingURL),
            driver: FakeIshRuntimeDriver()
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("Boot should reject a missing fakefs directory.")
        } catch let error as PocketRootError {
            guard case .rootFSUnavailable = error else {
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let state = await runtime.state
        XCTAssertEqual(state, .idle)
    }

    func testRuntimeMapsBootCommandAndTerminalShutdownSemantics() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(
            result: IshDriverCommandResult(
                exitCode: 7,
                signal: 15,
                standardOutput: Data("stdout".utf8),
                standardError: Data("stderr".utf8),
                timedOut: false
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(
                rootFSURL: rootFSURL,
                workDirectory: "/",
                supervisorGuestPath: "/sbin/ishsv",
                kernelLogFileDescriptor: 9
            ),
            driver: driver
        )

        try await runtime.boot(configuration: PocketRootConfiguration())
        let readyState = await runtime.state
        XCTAssertEqual(readyState, .ready)

        let result = try await runtime.execute(
            PocketRootCommandRequest(
                command: "printf ready",
                workingDirectory: "/root",
                environment: ["POCKETROOT_TEST": "1"],
                timeout: .milliseconds(1_500),
                mergeStandardError: true
            )
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.signal, 15)
        XCTAssertEqual(result.stdout, "stdout")
        XCTAssertEqual(result.stderr, "stderr")

        let snapshot = driver.snapshot
        XCTAssertEqual(
            snapshot.bootOptions,
            IshDriverBootOptions(
                rootFSPath: rootFSURL.path,
                workDirectory: "/",
                supervisorGuestPath: "/sbin/ishsv",
                kernelLogFileDescriptor: 9
            )
        )
        XCTAssertEqual(
            snapshot.commandRequest,
            IshDriverCommandRequest(
                arguments: ["/bin/sh", "-lc", "printf ready"],
                workingDirectory: "/root",
                environment: ["POCKETROOT_TEST": "1"],
                timeout: 1.5,
                mergeStandardError: true,
                maximumStandardOutputBytes: 8 * 1_024 * 1_024,
                maximumStandardErrorBytes: 4 * 1_024 * 1_024
            )
        )
        XCTAssertFalse(snapshot.calledOnMainThread)

        try await runtime.shutdown()
        let terminatedState = await runtime.state
        XCTAssertEqual(terminatedState, .terminated)
        XCTAssertTrue(driver.snapshot.didShutdown)

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A terminated iSH process cannot boot again.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .restartRequired)
        }
    }

    func testExecuteBeforeBootIsRejected() async {
        let rootFSURL: URL
        do {
            rootFSURL = try makeFakeFSFixture()
        } catch {
            return XCTFail("Unable to create fixture: \(error)")
        }

        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: FakeIshRuntimeDriver()
        )

        do {
            _ = try await runtime.execute(
                PocketRootCommandRequest(command: "true")
            )
            XCTFail("Execution should require a booted runtime.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .runtimeNotBooted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRuntimeRejectsTimeoutsThatWouldDisableNativeTimeout() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: FakeIshRuntimeDriver()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        for timeout in [Duration.zero, .seconds(-1), .seconds(86_401)] {
            do {
                _ = try await runtime.execute(
                    PocketRootCommandRequest(command: "sleep 1", timeout: timeout)
                )
                XCTFail("Invalid timeout \(timeout) should be rejected.")
            } catch let error as PocketRootError {
                XCTAssertEqual(
                    error,
                    .invalidCommandRequest(
                        "timeout must be greater than zero and no longer than 24 hours."
                    )
                )
            }
        }
    }

    func testRuntimeClampsSubMillisecondTimeoutToOneMillisecond() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver()
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        _ = try await runtime.execute(
            PocketRootCommandRequest(command: "true", timeout: .nanoseconds(1))
        )

        XCTAssertEqual(driver.snapshot.commandRequest?.timeout, 0.001)
    }

    func testOnlyTheOwningRuntimeCanCallTheProcessGlobalDriver() async throws {
        let firstRootFS = try makeFakeFSFixture()
        let secondRootFS = try makeFakeFSFixture()
        let firstDriver = FakeIshRuntimeDriver()
        let secondDriver = FakeIshRuntimeDriver()
        let processGate = IshProcessGate()
        let executor = BlockingIshExecutor(label: "PocketRootIshRuntimeTests.shared")
        let firstRuntime = IshLinuxRuntime(
            configuration: .init(rootFSURL: firstRootFS),
            driver: firstDriver,
            executor: executor,
            processGate: processGate
        )
        let secondRuntime = IshLinuxRuntime(
            configuration: .init(rootFSURL: secondRootFS),
            driver: secondDriver,
            executor: executor,
            processGate: processGate
        )

        try await firstRuntime.boot(configuration: PocketRootConfiguration())

        do {
            try await secondRuntime.boot(configuration: PocketRootConfiguration())
            XCTFail("A second runtime must not claim the process-global instance.")
        } catch let error as PocketRootError {
            guard case .runtimeFailure(let message) = error else {
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
            XCTAssertTrue(message.contains("owned by another"))
        }

        try await secondRuntime.shutdown()
        XCTAssertFalse(secondDriver.snapshot.didShutdown)
        XCTAssertFalse(firstDriver.snapshot.didShutdown)

        try await firstRuntime.shutdown()
        XCTAssertTrue(firstDriver.snapshot.didShutdown)
    }

    func testFailedNativeBootConsumesTheProcessSlotConservatively() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(bootError: FakeIshRuntimeError.bootFailed)
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("The fake driver should fail boot.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .runtimeFailure("Synthetic native boot failure."))
        }

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A failed native boot must not be retried in-process.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .restartRequired)
        }

        do {
            try await runtime.shutdown()
            XCTFail("Shutdown cannot recover a consumed process slot.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .restartRequired)
        }
        XCTAssertFalse(driver.snapshot.didShutdown)
    }

    func testConcurrentBootCannotEnterNativeDriverTwice() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let bootStarted = expectation(description: "native boot started")
        let releaseBoot = DispatchSemaphore(value: 0)
        let driver = FakeIshRuntimeDriver(
            bootStarted: bootStarted,
            bootBlocker: releaseBoot
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )

        let firstBoot = Task {
            try await runtime.boot(configuration: PocketRootConfiguration())
        }
        await fulfillment(of: [bootStarted], timeout: 2)

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A reentrant boot must be rejected before native admission.")
        } catch let error as PocketRootError {
            guard case .runtimeFailure = error else {
                releaseBoot.signal()
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
        }

        releaseBoot.signal()
        try await firstBoot.value
        XCTAssertEqual(driver.snapshot.bootCallCount, 1)
    }

    func testShutdownCannotOvertakeActiveOneShotCommand() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let commandStarted = expectation(description: "native command started")
        let releaseCommand = DispatchSemaphore(value: 0)
        let driver = FakeIshRuntimeDriver(
            commandStarted: commandStarted,
            commandBlocker: releaseCommand
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        let command = Task {
            try await runtime.execute(PocketRootCommandRequest(command: "sleep 1"))
        }
        await fulfillment(of: [commandStarted], timeout: 2)

        do {
            try await runtime.shutdown()
            XCTFail("Shutdown must not overtake the active native command.")
        } catch let error as PocketRootError {
            guard case .runtimeFailure(let message) = error else {
                releaseCommand.signal()
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
            XCTAssertTrue(message.contains("active one-shot command"))
        }
        XCTAssertFalse(driver.snapshot.didShutdown)

        releaseCommand.signal()
        _ = try await command.value
        try await runtime.shutdown()
        XCTAssertTrue(driver.snapshot.didShutdown)
    }

    func testDriverOutputLimitErrorMapsToPublicError() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(
            executeError: IshRuntimeDriverError.outputLimitExceeded(
                stream: "stdout",
                limit: 64
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(
                rootFSURL: rootFSURL,
                maximumStandardOutputBytes: 64
            ),
            driver: driver
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        do {
            _ = try await runtime.execute(PocketRootCommandRequest(command: "yes"))
            XCTFail("The output limit should be surfaced through PocketRootError.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .commandOutputLimitExceeded(stream: "stdout", limit: 64)
            )
        }
    }

    func testBootRejectsSymlinkedMetadataBeforeConsumingProcessSlot() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let metadataURL = rootFSURL.appendingPathComponent("meta.db")
        let realMetadataURL = rootFSURL.appendingPathComponent("real-meta.db")
        try FileManager.default.removeItem(at: metadataURL)
        _ = FileManager.default.createFile(atPath: realMetadataURL.path, contents: Data())
        try FileManager.default.createSymbolicLink(
            at: metadataURL,
            withDestinationURL: realMetadataURL
        )
        let driver = FakeIshRuntimeDriver()
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A symlinked metadata database must fail preflight.")
        } catch let error as PocketRootError {
            guard case .rootFSUnavailable = error else {
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
        }
        XCTAssertEqual(driver.snapshot.bootCallCount, 0)
        let state = await runtime.state
        XCTAssertEqual(state, .idle)
    }

    func testHostAvailabilityReflectsMissingNativeSlice() {
        #if os(macOS)
        XCTAssertFalse(PocketRootIshRuntimeFactory.isAvailable)
        #endif
    }

    private func makeFakeFSFixture() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketRootTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("data", isDirectory: true),
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(
            atPath: rootURL.appendingPathComponent("meta.db").path,
            contents: Data()
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }
}

private final class FakeIshRuntimeDriver: IshRuntimeDriver, @unchecked Sendable {
    struct Snapshot {
        let bootOptions: IshDriverBootOptions?
        let commandRequest: IshDriverCommandRequest?
        let didShutdown: Bool
        let calledOnMainThread: Bool
        let bootCallCount: Int
    }

    private let lock = NSLock()
    private let result: IshDriverCommandResult
    private let bootError: Error?
    private let executeError: Error?
    private let bootStarted: XCTestExpectation?
    private let bootBlocker: DispatchSemaphore?
    private let commandStarted: XCTestExpectation?
    private let commandBlocker: DispatchSemaphore?
    private var bootOptions: IshDriverBootOptions?
    private var commandRequest: IshDriverCommandRequest?
    private var didShutdown = false
    private var calledOnMainThread = false
    private var bootCallCount = 0

    init(
        result: IshDriverCommandResult = IshDriverCommandResult(
            exitCode: 0,
            signal: 0,
            standardOutput: Data(),
            standardError: Data(),
            timedOut: false
        ),
        bootError: Error? = nil,
        executeError: Error? = nil,
        bootStarted: XCTestExpectation? = nil,
        bootBlocker: DispatchSemaphore? = nil,
        commandStarted: XCTestExpectation? = nil,
        commandBlocker: DispatchSemaphore? = nil
    ) {
        self.result = result
        self.bootError = bootError
        self.executeError = executeError
        self.bootStarted = bootStarted
        self.bootBlocker = bootBlocker
        self.commandStarted = commandStarted
        self.commandBlocker = commandBlocker
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            bootOptions: bootOptions,
            commandRequest: commandRequest,
            didShutdown: didShutdown,
            calledOnMainThread: calledOnMainThread,
            bootCallCount: bootCallCount
        )
    }

    func boot(_ options: IshDriverBootOptions) throws {
        lock.lock()
        bootOptions = options
        bootCallCount += 1
        calledOnMainThread = calledOnMainThread || Thread.isMainThread
        lock.unlock()
        bootStarted?.fulfill()
        bootBlocker?.wait()
        if let bootError {
            throw bootError
        }
    }

    func execute(_ request: IshDriverCommandRequest) throws -> IshDriverCommandResult {
        lock.lock()
        commandRequest = request
        calledOnMainThread = calledOnMainThread || Thread.isMainThread
        lock.unlock()
        commandStarted?.fulfill()
        commandBlocker?.wait()
        if let executeError {
            throw executeError
        }
        return result
    }

    func shutdown() throws {
        lock.lock()
        didShutdown = true
        calledOnMainThread = calledOnMainThread || Thread.isMainThread
        lock.unlock()
    }
}

private enum FakeIshRuntimeError: LocalizedError {
    case bootFailed

    var errorDescription: String? {
        "Synthetic native boot failure."
    }
}
