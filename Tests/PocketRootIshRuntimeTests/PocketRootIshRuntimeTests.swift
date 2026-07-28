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
        XCTAssertEqual(configuration.healthCheck, .alpineARM64)
        XCTAssertEqual(
            PocketRootIshRuntimeHealthCheckConfiguration.ishEmbedV0_3_3,
            .init(expectedOperatingSystemVersionID: "3.19.1")
        )
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

    func testRootFSPreflightIOFailureMapsToTypedErrorWithoutConsumingSlot() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let secondRootFSURL = try makeFakeFSFixture()
        let processGate = IshProcessGate()
        let driver = FakeIshRuntimeDriver()
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: processGate,
            rootFSValidator: { _ in
                throw FakeIshRuntimeError.rootFSReadFailed
            }
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A RootFS preflight I/O failure must reject boot.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .rootFSUnavailable(
                    "Unable to validate the fakefs at \(rootFSURL.path): "
                        + "Synthetic RootFS attribute read failure."
                )
            )
        }

        let failedPreflightState = await runtime.state
        XCTAssertEqual(failedPreflightState, .idle)
        XCTAssertEqual(driver.snapshot.bootCallCount, 0)

        let secondRuntime = IshLinuxRuntime(
            configuration: .init(rootFSURL: secondRootFSURL),
            driver: FakeIshRuntimeDriver(),
            processGate: processGate
        )
        try await secondRuntime.boot(configuration: PocketRootConfiguration())
        let secondRuntimeState = await secondRuntime.state
        XCTAssertEqual(secondRuntimeState, .ready)
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

        let healthSnapshot = driver.snapshot
        XCTAssertEqual(healthSnapshot.healthCheckCallCount, 1)
        XCTAssertEqual(
            healthSnapshot.healthCheckRequest,
            IshRuntimeHealthCheck.makeRequest(
                configuration: .alpineARM64,
                workingDirectory: "/"
            )
        )

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

    func testBootFailsClosedWhenGuestIdentityDoesNotMatch() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(
            healthResult: makeHealthResult(architecture: "x86_64")
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("Boot must not report ready for the wrong guest architecture.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure(
                    "Post-boot guest architecture mismatch: "
                        + "expected \"aarch64\", found \"x86_64\"."
                )
            )
        }

        let failedState = await runtime.state
        XCTAssertEqual(failedState, .failed(
            "Post-boot guest architecture mismatch: expected \"aarch64\", found \"x86_64\"."
        ))
        XCTAssertEqual(driver.snapshot.healthCheckCallCount, 1)

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A failed post-boot gate consumes the process-global runtime slot.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .restartRequired)
        }
    }

    func testBootFailsClosedWhenGuestHealthCheckTimesOut() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(
            healthResult: IshDriverCommandResult(
                exitCode: -1,
                signal: 0,
                standardOutput: Data(),
                standardError: Data(),
                timedOut: true
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("Boot must not report ready after a timed-out guest health check.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure("Post-boot guest health check timed out.")
            )
        }
        let failedState = await runtime.state
        XCTAssertEqual(
            failedState,
            .failed("Post-boot guest health check timed out.")
        )
    }

    func testPinnedHealthGateRejectsTheWrongAlpineVersion() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(
            healthResult: makeHealthResult(operatingSystemVersionID: "3.20.0")
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(
                rootFSURL: rootFSURL,
                healthCheck: .ishEmbedV0_3_3
            ),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("The pinned RootFS health gate must require Alpine 3.19.1.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure(
                    "Post-boot guest operating system version mismatch: "
                        + "expected \"3.19.1\", found \"3.20.0\"."
                )
            )
        }
    }

    func testHealthGateParsesOSReleaseAsDataWithoutExecutingIt() throws {
        let result = makeHealthResult(
            osRelease: """
            NAME="Alpine Linux"
            ID="alpine"
            VERSION_ID='3.19.1'
            POCKETROOT_PAYLOAD=$(exit 99)
            """
        )

        XCTAssertNoThrow(
            try IshRuntimeHealthCheck.validate(
                result,
                configuration: .ishEmbedV0_3_3,
                workingDirectory: "/"
            )
        )
        XCTAssertFalse(IshRuntimeHealthCheck.shellCommand.contains(". /etc/os-release"))
        XCTAssertTrue(IshRuntimeHealthCheck.shellCommand.contains("/bin/uname -m"))
        XCTAssertTrue(IshRuntimeHealthCheck.shellCommand.contains("/bin/cat /etc/os-release"))
    }

    func testHealthGateRejectsWrongOperatingSystemAndWorkingDirectory() throws {
        XCTAssertThrowsError(
            try IshRuntimeHealthCheck.validate(
                makeHealthResult(operatingSystemID: "ubuntu"),
                configuration: .alpineARM64,
                workingDirectory: "/"
            )
        ) { error in
            XCTAssertEqual(
                error as? IshRuntimeHealthCheckError,
                .identityMismatch(field: "operating system", expected: "alpine", actual: "ubuntu")
            )
        }

        XCTAssertThrowsError(
            try IshRuntimeHealthCheck.validate(
                makeHealthResult(workingDirectory: "/wrong", canonicalWorkingDirectory: "/srv"),
                configuration: .alpineARM64,
                workingDirectory: "/srv/../srv"
            )
        ) { error in
            XCTAssertEqual(
                error as? IshRuntimeHealthCheckError,
                .identityMismatch(field: "working directory", expected: "/srv", actual: "/wrong")
            )
        }
    }

    func testHealthGateAcceptsCanonicalWorkingDirectoryAlias() throws {
        XCTAssertNoThrow(
            try IshRuntimeHealthCheck.validate(
                makeHealthResult(
                    workingDirectory: "/srv/app",
                    canonicalWorkingDirectory: "/srv/app"
                ),
                configuration: .alpineARM64,
                workingDirectory: "/srv/./app/"
            )
        )
    }

    func testHealthGateRejectsInvalidUTF8AndDuplicateOSReleaseKeys() throws {
        var invalidUTF8 = Data("aarch64\0".utf8)
        invalidUTF8.append(0xFF)
        invalidUTF8.append(Data("\0/\0/\0".utf8))
        let invalidUTF8Result = IshDriverCommandResult(
            exitCode: 0,
            signal: 0,
            standardOutput: invalidUTF8,
            standardError: Data(),
            timedOut: false
        )

        XCTAssertThrowsError(
            try IshRuntimeHealthCheck.validate(
                invalidUTF8Result,
                configuration: .alpineARM64,
                workingDirectory: "/"
            )
        ) { error in
            XCTAssertEqual(error as? IshRuntimeHealthCheckError, .malformedResponse)
        }

        XCTAssertThrowsError(
            try IshRuntimeHealthCheck.validate(
                makeHealthResult(osRelease: "ID=alpine\nID=ubuntu\nVERSION_ID=3.19.1"),
                configuration: .ishEmbedV0_3_3,
                workingDirectory: "/"
            )
        ) { error in
            XCTAssertEqual(error as? IshRuntimeHealthCheckError, .malformedResponse)
        }
    }

    func testHealthGateRejectsNonzeroAndSignaledCommands() throws {
        for (result, expected) in [
            (
                IshDriverCommandResult(
                    exitCode: 65,
                    signal: 0,
                    standardOutput: Data(),
                    standardError: Data(),
                    timedOut: false
                ),
                IshRuntimeHealthCheckError.commandFailed(
                    "guest health command exited with status 65"
                )
            ),
            (
                IshDriverCommandResult(
                    exitCode: -1,
                    signal: 9,
                    standardOutput: Data(),
                    standardError: Data(),
                    timedOut: false
                ),
                IshRuntimeHealthCheckError.commandFailed(
                    "guest health command terminated with signal 9"
                )
            ),
        ] {
            XCTAssertThrowsError(
                try IshRuntimeHealthCheck.validate(
                    result,
                    configuration: .alpineARM64,
                    workingDirectory: "/"
                )
            ) { error in
                XCTAssertEqual(error as? IshRuntimeHealthCheckError, expected)
            }
        }
    }

    func testHealthGateRejectsMalformedNULFraming() throws {
        let malformed = IshDriverCommandResult(
            exitCode: 0,
            signal: 0,
            standardOutput: Data(
                ["aarch64", "alpine", "3.19.1", "/"].joined(separator: "\0").utf8
            ),
            standardError: Data(),
            timedOut: false
        )

        XCTAssertThrowsError(
            try IshRuntimeHealthCheck.validate(
                malformed,
                configuration: .ishEmbedV0_3_3,
                workingDirectory: "/"
            )
        ) { error in
            XCTAssertEqual(error as? IshRuntimeHealthCheckError, .malformedResponse)
        }
    }

    func testInvalidHealthConfigurationDoesNotConsumeProcessSlot() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver()
        let runtime = IshLinuxRuntime(
            configuration: .init(
                rootFSURL: rootFSURL,
                healthCheck: .init(expectedArchitecture: "", timeout: .seconds(5))
            ),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("An invalid health-check configuration must be rejected.")
        } catch let error as PocketRootError {
            guard case .runtimeFailure(let message) = error else {
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
            XCTAssertTrue(message.contains("Invalid post-boot health-check configuration"))
        }

        let idleState = await runtime.state
        XCTAssertEqual(idleState, .idle)
        XCTAssertEqual(driver.snapshot.bootCallCount, 0)
        XCTAssertEqual(driver.snapshot.healthCheckCallCount, 0)
    }

    func testRelativeHealthWorkingDirectoryDoesNotConsumeProcessSlot() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver()
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL, workDirectory: "relative/path"),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A relative guest working directory must be rejected before native boot.")
        } catch let error as PocketRootError {
            guard case .runtimeFailure(let message) = error else {
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
            XCTAssertTrue(message.contains("guest working directory must be an absolute path"))
        }

        let state = await runtime.state
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(driver.snapshot.bootCallCount, 0)
    }

    func testNULSupervisorPathDoesNotConsumeProcessSlot() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver()
        let runtime = IshLinuxRuntime(
            configuration: .init(
                rootFSURL: rootFSURL,
                supervisorGuestPath: "/sbin/ish\0sv"
            ),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A NUL-containing supervisor path must be rejected before native boot.")
        } catch let error as PocketRootError {
            guard case .runtimeFailure(let message) = error else {
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
            XCTAssertTrue(message.contains("supervisor guest path must not contain a NUL byte"))
        }

        let state = await runtime.state
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(driver.snapshot.bootCallCount, 0)
        XCTAssertEqual(driver.snapshot.healthCheckCallCount, 0)
    }

    func testHealthOutputLimitFailureConsumesProcessSlot() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(
            healthError: IshRuntimeDriverError.outputLimitExceeded(
                stream: "stdout",
                limit: IshRuntimeHealthCheck.maximumOutputBytes
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("An oversized health response must fail boot.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .commandOutputLimitExceeded(
                    stream: "stdout",
                    limit: IshRuntimeHealthCheck.maximumOutputBytes
                )
            )
        }

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A native health-check failure consumes the process slot.")
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

    func testRuntimeRejectsAmbiguousCStringInputsBeforeCallingDriver() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver()
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        let requests = [
            PocketRootCommandRequest(command: "printf before\0after"),
            PocketRootCommandRequest(command: "true", workingDirectory: "/tmp\0/root"),
            PocketRootCommandRequest(command: "true", environment: ["BAD\0KEY": "value"]),
            PocketRootCommandRequest(command: "true", environment: ["BAD=KEY": "value"]),
            PocketRootCommandRequest(command: "true", environment: ["": "value"]),
            PocketRootCommandRequest(command: "true", environment: ["KEY": "before\0after"]),
        ]

        for request in requests {
            do {
                _ = try await runtime.execute(request)
                XCTFail("Ambiguous C-string input must be rejected.")
            } catch let error as PocketRootError {
                guard case .invalidCommandRequest = error else {
                    return XCTFail("Unexpected PocketRoot error: \(error)")
                }
            }
        }

        XCTAssertNil(driver.snapshot.commandRequest)
        let state = await runtime.state
        XCTAssertEqual(state, .ready)
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

    func testProcessGateComparesClaimedOwnerIdentifiers() async throws {
        let processGate = IshProcessGate()
        let ownerID = UUID()
        let unrelatedOwnerID = UUID()

        try await processGate.claim(for: ownerID)

        do {
            try await processGate.claim(for: unrelatedOwnerID)
            XCTFail("A different identifier must not reclaim the process gate.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure(
                    "The process-global IshEmbed instance is owned by another PocketRoot system."
                )
            )
        }

        do {
            try await processGate.requireOwnership(for: unrelatedOwnerID)
            XCTFail("A different identifier must not pass the ownership check.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure(
                    "This PocketRoot system does not own the process-global IshEmbed instance."
                )
            )
        }

        try await processGate.requireOwnership(for: ownerID)
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

    func testTaskCancellationStopsActiveCommandAndKeepsRuntimeReady() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let commandStarted = expectation(description: "cancellable command started")
        let cancellationObserved = expectation(
            description: "native driver observed cancellation"
        )
        let driver = FakeIshRuntimeDriver(
            result: IshDriverCommandResult(
                exitCode: 0,
                signal: 0,
                standardOutput: Data("after-cancellation".utf8),
                standardError: Data(),
                timedOut: false
            ),
            commandStarted: commandStarted,
            cancellationCommand: "sleep 30",
            cancellationObserved: cancellationObserved
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        let command = Task {
            try await runtime.execute(
                PocketRootCommandRequest(command: "sleep 30")
            )
        }
        await fulfillment(of: [commandStarted], timeout: 2)
        command.cancel()
        await fulfillment(of: [cancellationObserved], timeout: 2)

        do {
            _ = try await command.value
            XCTFail("A cancelled native command must not return success.")
        } catch is CancellationError {
            // Expected after the native driver confirms command cleanup.
        }

        let stateAfterCancellation = await runtime.state
        XCTAssertEqual(stateAfterCancellation, .ready)
        let recovery = try await runtime.execute(
            PocketRootCommandRequest(command: "printf after-cancellation")
        )
        XCTAssertEqual(recovery.standardOutput, Data("after-cancellation".utf8))
    }

    func testCancellationCleanupFailureFailsRuntimeClosed() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let commandStarted = expectation(description: "cancellable command started")
        let cancellationObserved = expectation(
            description: "native driver observed cancellation"
        )
        let driver = FakeIshRuntimeDriver(
            commandStarted: commandStarted,
            cancellationCommand: "sleep 30",
            cancellationObserved: cancellationObserved,
            cancellationError: IshRuntimeDriverError.sessionTerminationUnconfirmed(
                "synthetic cancellation cleanup failure"
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        let command = Task {
            try await runtime.execute(
                PocketRootCommandRequest(command: "sleep 30")
            )
        }
        await fulfillment(of: [commandStarted], timeout: 2)
        command.cancel()
        await fulfillment(of: [cancellationObserved], timeout: 2)

        do {
            _ = try await command.value
            XCTFail("Unconfirmed cancellation cleanup must fail closed.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure(
                    "Guest process termination could not be confirmed: "
                        + "synthetic cancellation cleanup failure"
                )
            )
        }

        let state = await runtime.state
        XCTAssertEqual(
            state,
            .failed(
                "Guest process termination could not be confirmed: "
                    + "synthetic cancellation cleanup failure"
            )
        )
    }

    func testCancelledQueuedCommandNeverEntersNativeDriver() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let executor = BlockingIshExecutor(
            label: "PocketRootIshRuntimeTests.queuedCancellation"
        )
        let driver = FakeIshRuntimeDriver()
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            executor: executor
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        let blockerStarted = expectation(description: "executor blocker started")
        let releaseBlocker = DispatchSemaphore(value: 0)
        let blocker = Task {
            try await executor.perform {
                blockerStarted.fulfill()
                releaseBlocker.wait()
            }
        }
        await fulfillment(of: [blockerStarted], timeout: 2)

        let command = Task {
            try await runtime.execute(
                PocketRootCommandRequest(command: "must-not-run")
            )
        }
        command.cancel()
        releaseBlocker.signal()
        try await blocker.value

        do {
            _ = try await command.value
            XCTFail("A cancelled queued command must not enter the driver.")
        } catch is CancellationError {
            // Expected before the queued native operation starts.
        }
        XCTAssertNil(driver.snapshot.commandRequest)
        let state = await runtime.state
        XCTAssertEqual(state, .ready)
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

    func testNativeBacklogLimitMapsToPublicErrorAndFailsClosed() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(
            executeError: IshRuntimeDriverError.nativeOutputLimitExceeded(
                maximumBytes: 4 * 1_024 * 1_024,
                maximumFrames: 4_096
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        do {
            _ = try await runtime.execute(PocketRootCommandRequest(command: "yes"))
            XCTFail("The native backlog limit should be surfaced.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure(
                    "The native session backlog exceeded its bounded "
                        + "4194304-byte or 4096-frame limit."
                )
            )
        }

        let state = await runtime.state
        guard case .failed = state else {
            return XCTFail("Native backlog overflow should fail the runtime closed.")
        }

        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A fail-closed runtime should require a restart.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .restartRequired)
        }
    }

    func testSupervisorCommandRejectionPreservesProvenanceAndReadyState() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeIshRuntimeDriver(
            executeError: IshRuntimeDriverError.supervisorCommandRejected(
                "IshError -15: supervisor reported error"
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        do {
            _ = try await runtime.execute(PocketRootCommandRequest(command: "true"))
            XCTFail("A supervisor ERROR must not appear as a guest exit result.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure(
                    "The guest supervisor rejected the command before execution "
                        + "(IshError -15: supervisor reported error)."
                )
            )
        }

        let state = await runtime.state
        XCTAssertEqual(state, .ready)
    }

    func testUnconfirmedTerminationFailsClosedAndRequiresRestart() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let secondRootFSURL = try makeFakeFSFixture()
        let processGate = IshProcessGate()
        let executor = BlockingIshExecutor(label: "PocketRootIshRuntimeTests.failClosed")
        let driver = FakeIshRuntimeDriver(
            executeError: IshRuntimeDriverError.sessionTerminationUnconfirmed(
                "synthetic missing EXITED event"
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            executor: executor,
            processGate: processGate
        )
        let secondRuntime = IshLinuxRuntime(
            configuration: .init(rootFSURL: secondRootFSURL),
            driver: FakeIshRuntimeDriver(),
            executor: executor,
            processGate: processGate
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        do {
            _ = try await runtime.execute(PocketRootCommandRequest(command: "sleep 30"))
            XCTFail("Unconfirmed process exit must fail closed.")
        } catch let error as PocketRootError {
            XCTAssertEqual(
                error,
                .runtimeFailure(
                    "Guest process termination could not be confirmed: "
                        + "synthetic missing EXITED event"
                )
            )
        }

        let state = await runtime.state
        XCTAssertEqual(
            state,
            .failed(
                "Guest process termination could not be confirmed: "
                    + "synthetic missing EXITED event"
            )
        )
        do {
            try await runtime.boot(configuration: PocketRootConfiguration())
            XCTFail("A runtime with an unconfirmed guest process must require restart.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .restartRequired)
        }
        do {
            try await secondRuntime.boot(configuration: PocketRootConfiguration())
            XCTFail("The shared process gate must reject a second runtime after fail-close.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .restartRequired)
        }
    }

    func testTransportPolicyAcceptsGuestExit17AndRejectsNegativeExit() throws {
        XCTAssertNoThrow(
            try IshRuntimeTransportPolicy.validateAuthoritativeExit(
                exitCode: 17,
                signal: 0
            )
        )

        XCTAssertThrowsError(
            try IshRuntimeTransportPolicy.validateAuthoritativeExit(
                exitCode: -12,
                signal: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? IshRuntimeDriverError,
                .sessionTerminationUnconfirmed(
                    "the native transport reported invalid guest exit code "
                        + "-12 with signal 0"
                )
            )
        }

        XCTAssertNoThrow(
            try IshRuntimeTransportPolicy.validateAuthoritativeExit(
                exitCode: 0,
                signal: 0
            )
        )
        XCTAssertNoThrow(
            try IshRuntimeTransportPolicy.validateAuthoritativeExit(
                exitCode: 17,
                signal: 15
            )
        )
    }

    func testTerminalSpawnTransportFailuresMapToFailClosedError() {
        for code in [-9, -11, -17] as [Int32] {
            guard case .sessionTerminationUnconfirmed(let reason) =
                IshRuntimeTransportPolicy.terminalSpawnFailure(
                    code: code,
                    message: "synthetic transport loss"
                )
            else {
                return XCTFail("IshError \(code) must fail the runtime closed.")
            }
            XCTAssertTrue(reason.contains("IshError \(code)"))
        }

        XCTAssertNil(
            IshRuntimeTransportPolicy.terminalSpawnFailure(
                code: -13,
                message: "invalid argument"
            )
        )
    }

    func testBrokenPipeIsSessionLocalAfterSpawn() {
        XCTAssertNil(
            IshRuntimeTransportPolicy.terminalSessionOperationFailure(
                code: -17,
                message: "stdin is already closed"
            )
        )
        for code in [-9, -11] as [Int32] {
            XCTAssertNotNil(
                IshRuntimeTransportPolicy.terminalSessionOperationFailure(
                    code: code,
                    message: "synthetic transport loss"
                )
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

    func testInteractiveSessionStreamsPTYAndForwardsControls() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driverSession = FakeInteractiveDriverSession()
        let driver = FakeInteractiveDriver(session: driverSession)
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        let configuration = PocketRootSessionConfiguration(
            shell: "/bin/ash",
            shellArguments: ["-il"],
            workingDirectory: "/root/project",
            environment: ["CUSTOM": "value"],
            initialTerminalSize: .init(rows: 40, columns: 120)
        )
        let session = try await runtime.makeSession(configuration: configuration)
        var events = session.events.makeAsyncIterator()
        let startedEvent = await events.next()
        XCTAssertEqual(startedEvent, .started)

        driverSession.enqueue(.standardOutput(Data("ready".utf8)))
        let outputEvent = await events.next()
        XCTAssertEqual(
            outputEvent,
            .standardOutput(Data("ready".utf8))
        )

        try await session.write(Data("ls\r".utf8))
        try await session.resize(to: .init(rows: 30, columns: 90))
        try await session.sendSignal(2)
        try await session.closeInput()
        await session.terminate()

        let exitEvent = await events.next()
        let finishedEvent = await events.next()
        XCTAssertEqual(exitEvent, .exited(0))
        XCTAssertNil(finishedEvent)
        let request = try XCTUnwrap(driver.sessionRequest)
        XCTAssertEqual(request.arguments, ["/bin/ash", "-il"])
        XCTAssertEqual(request.workingDirectory, "/root/project")
        XCTAssertEqual(request.environment["CUSTOM"], "value")
        XCTAssertEqual(request.environment["SHELL"], "/bin/ash")
        XCTAssertEqual(request.environment["TERM"], "xterm-256color")
        XCTAssertEqual(request.initialTerminalSize, .init(rows: 40, columns: 120))

        let snapshot = driverSession.snapshot
        XCTAssertEqual(snapshot.writes, [Data("ls\r".utf8)])
        XCTAssertEqual(snapshot.sizes, [.init(rows: 30, columns: 90)])
        XCTAssertEqual(snapshot.signals, [2])
        XCTAssertTrue(snapshot.didCloseInput)
        XCTAssertTrue(snapshot.didTerminate)
        XCTAssertTrue(snapshot.didClose)
    }

    func testShutdownTerminatesInteractiveSessionsBeforeNativeShutdown() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driverSession = FakeInteractiveDriverSession()
        let driver = FakeInteractiveDriver(session: driverSession)
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())
        _ = try await runtime.makeSession(configuration: .init())

        try await runtime.shutdown()

        XCTAssertTrue(driverSession.snapshot.didTerminate)
        XCTAssertTrue(driverSession.snapshot.didClose)
        XCTAssertTrue(driver.didShutdown)
        XCTAssertTrue(driver.shutdownObservedClosedSession)
        let state = await runtime.state
        XCTAssertEqual(state, .terminated)
    }

    func testShutdownAbortsWhenInteractiveExitIsUnconfirmed() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driverSession = FakeInteractiveDriverSession(
            terminationError: .sessionTerminationUnconfirmed(
                "synthetic missing EXITED event"
            )
        )
        let driver = FakeInteractiveDriver(session: driverSession)
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())
        _ = try await runtime.makeSession(configuration: .init())

        do {
            try await runtime.shutdown()
            XCTFail("Native shutdown must not run without an authoritative session exit.")
        } catch let error as PocketRootError {
            XCTAssertEqual(error, .restartRequired)
        }

        XCTAssertFalse(driver.didShutdown)
        XCTAssertTrue(driverSession.snapshot.didClose)
        guard case .failed = await runtime.state else {
            return XCTFail("An unconfirmed terminal exit must fail the runtime closed.")
        }
    }

    func testInteractiveOutputBufferIsByteBoundedAndPreservesFailure() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driverSession = FakeInteractiveDriverSession()
        let driver = FakeInteractiveDriver(session: driverSession)
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())
        let session = try await runtime.makeSession(configuration: .init())

        let nativeFrame = Data(repeating: 0x61, count: 1_024 * 1_024)
        for _ in 0..<5 {
            driverSession.enqueue(.standardOutput(nativeFrame))
        }

        for _ in 0..<200 {
            if case .failed = await runtime.state {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .failed = await runtime.state else {
            return XCTFail("A full PTY event buffer must fail the session closed.")
        }

        var iterator = session.events.makeAsyncIterator()
        var retainedOutputBytes = 0
        var maximumChunkBytes = 0
        var sawFailure = false
        while let event = await iterator.next() {
            switch event {
            case .standardOutput(let data), .standardError(let data):
                retainedOutputBytes += data.count
                maximumChunkBytes = max(maximumChunkBytes, data.count)
            case .failed:
                sawFailure = true
            case .started, .exited:
                break
            }
        }

        XCTAssertLessThanOrEqual(retainedOutputBytes, 4 * 1_024 * 1_024)
        XCTAssertLessThanOrEqual(maximumChunkBytes, 16 * 1_024)
        XCTAssertTrue(sawFailure)
        XCTAssertTrue(driverSession.snapshot.didClose)
    }

    func testInteractiveTransportFailureFailsRuntimeClosed() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driverSession = FakeInteractiveDriverSession()
        let driver = FakeInteractiveDriver(session: driverSession)
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())
        let session = try await runtime.makeSession(configuration: .init())
        var events = session.events.makeAsyncIterator()
        let startedEvent = await events.next()
        XCTAssertEqual(startedEvent, .started)

        driverSession.failRead(
            IshRuntimeDriverError.nativeOutputLimitExceeded(
                maximumBytes: 4 * 1_024 * 1_024,
                maximumFrames: 4_096
            )
        )

        guard case .failed = await events.next() else {
            return XCTFail("Expected the PTY stream to fail.")
        }
        guard case .failed = await runtime.state else {
            return XCTFail("A terminal transport failure must fail the runtime closed.")
        }
        XCTAssertTrue(driverSession.snapshot.didClose)
    }

    func testFatalInteractiveFailureTerminatesEveryPeerSession() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let failingSession = FakeInteractiveDriverSession()
        let peerSession = FakeInteractiveDriverSession()
        let driver = FakeInteractiveDriver(
            sessions: [failingSession, peerSession]
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())
        let failed = try await runtime.makeSession(configuration: .init())
        _ = try await runtime.makeSession(configuration: .init())
        var failedEvents = failed.events.makeAsyncIterator()
        let started = await failedEvents.next()
        XCTAssertEqual(started, .started)

        failingSession.failRead(
            IshRuntimeDriverError.nativeOutputLimitExceeded(
                maximumBytes: 4 * 1_024 * 1_024,
                maximumFrames: 4_096
            )
        )

        guard case .failed = await failedEvents.next() else {
            return XCTFail("Expected the first PTY stream to fail.")
        }
        guard case .failed = await runtime.state else {
            return XCTFail("A fatal PTY failure must fail the runtime closed.")
        }
        XCTAssertTrue(failingSession.snapshot.didClose)
        XCTAssertTrue(peerSession.snapshot.didTerminate)
        XCTAssertTrue(peerSession.snapshot.didClose)
    }

    func testInteractiveSupervisorRejectionClosesOnlyTheSession() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driverSession = FakeInteractiveDriverSession()
        let driver = FakeInteractiveDriver(session: driverSession)
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())
        let session = try await runtime.makeSession(configuration: .init())
        var events = session.events.makeAsyncIterator()
        let started = await events.next()
        XCTAssertEqual(started, .started)

        driverSession.failRead(
            IshRuntimeDriverError.supervisorCommandRejected(
                "synthetic session rejection"
            )
        )

        guard case .failed = await events.next() else {
            return XCTFail("Expected the rejected PTY session to close.")
        }
        let state = await runtime.state
        XCTAssertEqual(state, .ready)
        XCTAssertTrue(driverSession.snapshot.didClose)

        try await runtime.shutdown()
        XCTAssertTrue(driver.didShutdown)
    }

    func testInteractiveSpawnFailureFailsRuntimeClosed() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let driver = FakeInteractiveDriver(
            session: FakeInteractiveDriverSession(),
            makeSessionError: .sessionTerminationUnconfirmed(
                "synthetic spawn transport failure"
            )
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        do {
            _ = try await runtime.makeSession(configuration: .init())
            XCTFail("Expected the synthetic PTY spawn failure.")
        } catch let error as PocketRootError {
            guard case .runtimeFailure = error else {
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
        }
        guard case .failed = await runtime.state else {
            return XCTFail("A PTY spawn transport failure must fail the runtime closed.")
        }
    }

    func testShutdownRejectsConcurrentInteractiveSessionCreation() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let creationGate = BlockingSessionCreationGate()
        let driverSession = FakeInteractiveDriverSession()
        let driver = FakeInteractiveDriver(
            session: driverSession,
            creationGate: creationGate
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        let creation = Task {
            try await runtime.makeSession(configuration: .init())
        }
        await creationGate.waitUntilStarted()
        defer {
            creationGate.release()
        }

        do {
            try await runtime.shutdown()
            XCTFail("Shutdown must not pass an unregistered native session.")
        } catch let error as PocketRootError {
            guard case .runtimeFailure(let message) = error else {
                return XCTFail("Unexpected PocketRoot error: \(error)")
            }
            XCTAssertTrue(message.contains("session creation"))
        }
        XCTAssertFalse(driver.didShutdown)

        creationGate.release()
        let session = try await creation.value
        await session.terminate()
        try await runtime.shutdown()
        XCTAssertTrue(driver.didShutdown)
    }

    func testCanceledInteractiveCreationClosesUnreturnedNativeSession() async throws {
        let rootFSURL = try makeFakeFSFixture()
        let creationGate = BlockingSessionCreationGate()
        let driverSession = FakeInteractiveDriverSession()
        let driver = FakeInteractiveDriver(
            session: driverSession,
            creationGate: creationGate
        )
        let runtime = IshLinuxRuntime(
            configuration: .init(rootFSURL: rootFSURL),
            driver: driver,
            executor: BlockingIshExecutor(
                label: "PocketRootIshRuntimeTests.cancelSessionCreation"
            ),
            processGate: IshProcessGate()
        )
        try await runtime.boot(configuration: PocketRootConfiguration())

        let creation = Task {
            try await runtime.makeSession(configuration: .init())
        }
        await creationGate.waitUntilStarted()
        creation.cancel()
        creationGate.release()

        do {
            _ = try await creation.value
            XCTFail("Canceled PTY creation must not return a live session.")
        } catch is CancellationError {
            // The native spawn completed, then was closed before cancellation
            // propagated to the caller.
        }

        XCTAssertTrue(driverSession.snapshot.didClose)
        try await runtime.shutdown()
        XCTAssertTrue(driver.didShutdown)
        XCTAssertTrue(driver.shutdownObservedClosedSession)
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

    private func makeHealthResult(
        architecture: String = "aarch64",
        operatingSystemID: String = "alpine",
        operatingSystemVersionID: String = "3.19.1",
        osRelease: String? = nil,
        workingDirectory: String = "/",
        canonicalWorkingDirectory: String? = nil
    ) -> IshDriverCommandResult {
        let release = osRelease ?? """
            ID=\(operatingSystemID)
            VERSION_ID=\(operatingSystemVersionID)
            """
        let payload = [
            architecture,
            release,
            workingDirectory,
            canonicalWorkingDirectory ?? workingDirectory,
        ].joined(separator: "\0") + "\0"
        return IshDriverCommandResult(
            exitCode: 0,
            signal: 0,
            standardOutput: Data(payload.utf8),
            standardError: Data(),
            timedOut: false
        )
    }
}

private final class FakeIshRuntimeDriver: IshRuntimeDriver, @unchecked Sendable {
    struct Snapshot {
        let bootOptions: IshDriverBootOptions?
        let healthCheckRequest: IshDriverCommandRequest?
        let commandRequest: IshDriverCommandRequest?
        let didShutdown: Bool
        let calledOnMainThread: Bool
        let bootCallCount: Int
        let healthCheckCallCount: Int
    }

    private let lock = NSLock()
    private let result: IshDriverCommandResult
    private let healthResult: IshDriverCommandResult
    private let healthError: Error?
    private let bootError: Error?
    private let executeError: Error?
    private let bootStarted: XCTestExpectation?
    private let bootBlocker: DispatchSemaphore?
    private let commandStarted: XCTestExpectation?
    private let commandBlocker: DispatchSemaphore?
    private let cancellationCommand: String?
    private let cancellationObserved: XCTestExpectation?
    private let cancellationError: Error?
    private var bootOptions: IshDriverBootOptions?
    private var healthCheckRequest: IshDriverCommandRequest?
    private var commandRequest: IshDriverCommandRequest?
    private var didShutdown = false
    private var calledOnMainThread = false
    private var bootCallCount = 0
    private var healthCheckCallCount = 0

    init(
        result: IshDriverCommandResult = IshDriverCommandResult(
            exitCode: 0,
            signal: 0,
            standardOutput: Data(),
            standardError: Data(),
            timedOut: false
        ),
        healthResult: IshDriverCommandResult? = nil,
        healthError: Error? = nil,
        bootError: Error? = nil,
        executeError: Error? = nil,
        bootStarted: XCTestExpectation? = nil,
        bootBlocker: DispatchSemaphore? = nil,
        commandStarted: XCTestExpectation? = nil,
        commandBlocker: DispatchSemaphore? = nil,
        cancellationCommand: String? = nil,
        cancellationObserved: XCTestExpectation? = nil,
        cancellationError: Error? = nil
    ) {
        self.result = result
        self.healthResult = healthResult ?? Self.defaultHealthResult
        self.healthError = healthError
        self.bootError = bootError
        self.executeError = executeError
        self.bootStarted = bootStarted
        self.bootBlocker = bootBlocker
        self.commandStarted = commandStarted
        self.commandBlocker = commandBlocker
        self.cancellationCommand = cancellationCommand
        self.cancellationObserved = cancellationObserved
        self.cancellationError = cancellationError
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            bootOptions: bootOptions,
            healthCheckRequest: healthCheckRequest,
            commandRequest: commandRequest,
            didShutdown: didShutdown,
            calledOnMainThread: calledOnMainThread,
            bootCallCount: bootCallCount,
            healthCheckCallCount: healthCheckCallCount
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
        try execute(request, cancellation: nil)
    }

    func execute(
        _ request: IshDriverCommandRequest,
        cancellation: IshCommandCancellation
    ) throws -> IshDriverCommandResult {
        try execute(request, cancellation: Optional(cancellation))
    }

    private func execute(
        _ request: IshDriverCommandRequest,
        cancellation: IshCommandCancellation?
    ) throws -> IshDriverCommandResult {
        if request.arguments.count == 5,
           Array(request.arguments.prefix(3))
            == ["/bin/sh", "-c", IshRuntimeHealthCheck.shellCommand] {
            lock.lock()
            healthCheckRequest = request
            healthCheckCallCount += 1
            calledOnMainThread = calledOnMainThread || Thread.isMainThread
            lock.unlock()
            if let healthError {
                throw healthError
            }
            return healthResult
        }

        lock.lock()
        commandRequest = request
        calledOnMainThread = calledOnMainThread || Thread.isMainThread
        lock.unlock()
        if cancellationCommand == nil
            || request.arguments.last == cancellationCommand
        {
            commandStarted?.fulfill()
        }
        if request.arguments.last == cancellationCommand,
           let cancellation
        {
            while !cancellation.isCancelled {
                Thread.sleep(forTimeInterval: 0.001)
            }
            cancellationObserved?.fulfill()
            if let cancellationError {
                throw cancellationError
            }
            try cancellation.check()
        }
        commandBlocker?.wait()
        if let executeError {
            throw executeError
        }
        return result
    }

    private static let defaultHealthResult = IshDriverCommandResult(
        exitCode: 0,
        signal: 0,
        standardOutput: Data(
            (["aarch64", "ID=alpine\nVERSION_ID=3.19.1", "/", "/"]
                .joined(separator: "\0") + "\0").utf8
        ),
        standardError: Data(),
        timedOut: false
    )

    func shutdown() throws {
        lock.lock()
        didShutdown = true
        calledOnMainThread = calledOnMainThread || Thread.isMainThread
        lock.unlock()
    }
}

private enum FakeIshRuntimeError: LocalizedError {
    case bootFailed
    case rootFSReadFailed

    var errorDescription: String? {
        switch self {
        case .bootFailed:
            return "Synthetic native boot failure."
        case .rootFSReadFailed:
            return "Synthetic RootFS attribute read failure."
        }
    }
}

private final class FakeInteractiveDriver: IshRuntimeDriver, @unchecked Sendable {
    private let lock = NSLock()
    private let sessions: [FakeInteractiveDriverSession]
    private let creationGate: BlockingSessionCreationGate?
    private let makeSessionError: IshRuntimeDriverError?
    private var nextSessionIndex = 0
    private(set) var sessionRequest: IshDriverSessionRequest?
    private(set) var didShutdown = false
    private(set) var shutdownObservedClosedSession = false

    init(
        session: FakeInteractiveDriverSession,
        creationGate: BlockingSessionCreationGate? = nil,
        makeSessionError: IshRuntimeDriverError? = nil
    ) {
        sessions = [session]
        self.creationGate = creationGate
        self.makeSessionError = makeSessionError
    }

    init(
        sessions: [FakeInteractiveDriverSession],
        creationGate: BlockingSessionCreationGate? = nil,
        makeSessionError: IshRuntimeDriverError? = nil
    ) {
        precondition(!sessions.isEmpty)
        self.sessions = sessions
        self.creationGate = creationGate
        self.makeSessionError = makeSessionError
    }

    func boot(_ options: IshDriverBootOptions) throws {}

    func execute(_ request: IshDriverCommandRequest) throws -> IshDriverCommandResult {
        IshDriverCommandResult(
            exitCode: 0,
            signal: 0,
            standardOutput: Data(
                (["aarch64", "ID=alpine\nVERSION_ID=3.19.1", "/", "/"]
                    .joined(separator: "\0") + "\0").utf8
            ),
            standardError: Data(),
            timedOut: false
        )
    }

    func makeSession(
        _ request: IshDriverSessionRequest
    ) throws -> any IshRuntimeDriverSession {
        creationGate?.block()
        if let makeSessionError {
            throw makeSessionError
        }
        lock.lock()
        sessionRequest = request
        let session = sessions[min(nextSessionIndex, sessions.count - 1)]
        nextSessionIndex += 1
        lock.unlock()
        return session
    }

    func shutdown() throws {
        lock.lock()
        didShutdown = true
        shutdownObservedClosedSession = sessions.allSatisfy {
            $0.snapshot.didClose
        }
        lock.unlock()
    }
}

private final class FakeInteractiveDriverSession:
    IshRuntimeDriverSession,
    @unchecked Sendable
{
    struct Snapshot {
        let writes: [Data]
        let sizes: [PocketRootTerminalSize]
        let signals: [Int32]
        let didCloseInput: Bool
        let didTerminate: Bool
        let didClose: Bool
    }

    private let condition = NSCondition()
    private let terminationError: IshRuntimeDriverError?
    private var events: [IshDriverSessionEvent] = []
    private var readError: Error?
    private var writes: [Data] = []
    private var sizes: [PocketRootTerminalSize] = []
    private var signals: [Int32] = []
    private var didCloseInput = false
    private var didTerminate = false
    private var didClose = false

    init(terminationError: IshRuntimeDriverError? = nil) {
        self.terminationError = terminationError
    }

    var snapshot: Snapshot {
        condition.lock()
        defer { condition.unlock() }
        return Snapshot(
            writes: writes,
            sizes: sizes,
            signals: signals,
            didCloseInput: didCloseInput,
            didTerminate: didTerminate,
            didClose: didClose
        )
    }

    func enqueue(_ event: IshDriverSessionEvent) {
        condition.lock()
        events.append(event)
        condition.signal()
        condition.unlock()
    }

    func failRead(_ error: Error) {
        condition.lock()
        readError = error
        condition.signal()
        condition.unlock()
    }

    func read(timeout: TimeInterval) throws -> IshDriverSessionEvent? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while events.isEmpty, readError == nil, !didClose, Date() < deadline {
            condition.wait(until: deadline)
        }
        if let readError {
            self.readError = nil
            throw readError
        }
        return events.isEmpty ? nil : events.removeFirst()
    }

    func write(_ data: Data) throws {
        condition.lock()
        writes.append(data)
        condition.unlock()
    }

    func resize(to size: PocketRootTerminalSize) throws {
        condition.lock()
        sizes.append(size)
        condition.unlock()
    }

    func sendSignal(_ signal: Int32) throws {
        condition.lock()
        signals.append(signal)
        condition.unlock()
    }

    func closeInput() throws {
        condition.lock()
        didCloseInput = true
        condition.unlock()
    }

    func terminate() throws {
        condition.lock()
        if let terminationError {
            condition.unlock()
            throw terminationError
        }
        guard !didTerminate else {
            condition.unlock()
            return
        }
        didTerminate = true
        events.append(.exited(exitCode: 0, signal: 15))
        condition.signal()
        condition.unlock()
    }

    func close() {
        condition.lock()
        didClose = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class BlockingSessionCreationGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var didStart = false
    private var isReleased = false

    func block() {
        condition.lock()
        didStart = true
        condition.broadcast()
        while !isReleased {
            condition.wait()
        }
        condition.unlock()
    }

    func waitUntilStarted() async {
        await Task.detached { [self] in
            waitUntilStartedBlocking()
        }.value
    }

    private func waitUntilStartedBlocking() {
        condition.lock()
        while !didStart {
            condition.wait()
        }
        condition.unlock()
    }

    func release() {
        condition.lock()
        isReleased = true
        condition.broadcast()
        condition.unlock()
    }
}
