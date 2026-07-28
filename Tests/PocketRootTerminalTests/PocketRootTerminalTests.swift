import XCTest
import PocketRootCore
@testable import PocketRootTerminal

final class PocketRootTerminalTests: XCTestCase {
    func testDefaultConfigurationDescribesPendingIntegration() {
        let configuration = PocketRootTerminalConfiguration()

        XCTAssertEqual(configuration.placeholderText, "Terminal integration pending")
        XCTAssertEqual(configuration.prompt, "$ ")
        XCTAssertFalse(configuration.allowsInput)
        XCTAssertTrue(configuration.showsAccessoryView)
        XCTAssertEqual(configuration.initialWorkingDirectory, "/root")
        XCTAssertEqual(configuration.commandTimeout, .seconds(30))
        XCTAssertEqual(configuration.maximumTranscriptCharacters, 1_048_576)
    }

    func testCustomConfigurationPreservesValues() {
        let configuration = PocketRootTerminalConfiguration(
            placeholderText: "Waiting for runtime",
            prompt: "root# ",
            allowsInput: true,
            showsAccessoryView: false,
            initialWorkingDirectory: "/work",
            commandTimeout: .seconds(12),
            maximumTranscriptCharacters: 4_096
        )

        XCTAssertEqual(configuration.placeholderText, "Waiting for runtime")
        XCTAssertEqual(configuration.prompt, "root# ")
        XCTAssertTrue(configuration.allowsInput)
        XCTAssertFalse(configuration.showsAccessoryView)
        XCTAssertEqual(configuration.initialWorkingDirectory, "/work")
        XCTAssertEqual(configuration.commandTimeout, .seconds(12))
        XCTAssertEqual(configuration.maximumTranscriptCharacters, 4_096)
    }

    func testCommandLineConfigurationEnablesBoundedInput() {
        let configuration = PocketRootTerminalConfiguration.commandLine(
            initialWorkingDirectory: "/workspace",
            commandTimeout: .seconds(8)
        )

        XCTAssertEqual(configuration.placeholderText, "PocketRoot command terminal ready")
        XCTAssertTrue(configuration.allowsInput)
        XCTAssertEqual(configuration.initialWorkingDirectory, "/workspace")
        XCTAssertEqual(configuration.commandTimeout, .seconds(8))
    }

    func testInteractiveConfigurationSuppliesPTYWorkingDirectoryByDefault() {
        let configuration = PocketRootTerminalConfiguration.interactive(
            initialWorkingDirectory: "/workspace"
        )

        let resolved = configuration
            .resolvingInteractiveSessionConfiguration(nil)

        XCTAssertEqual(resolved.workingDirectory, "/workspace")
    }

    func testExplicitPTYSessionConfigurationTakesPrecedence() {
        let configuration = PocketRootTerminalConfiguration.interactive(
            initialWorkingDirectory: "/workspace"
        )
        let explicit = PocketRootSessionConfiguration(
            shell: "/bin/ash",
            workingDirectory: "/srv",
            environment: ["CUSTOM": "value"]
        )

        let resolved = configuration
            .resolvingInteractiveSessionConfiguration(explicit)

        XCTAssertEqual(resolved, explicit)
    }

    func testThemePresetsHaveStablePalettes() {
        XCTAssertEqual(PocketRootTerminalTheme.system.palette, .system)
        XCTAssertEqual(PocketRootTerminalTheme.dark.palette, .dark)
        XCTAssertEqual(PocketRootTerminalTheme.system.fontSize, 14)
    }

    func testControllerMaintainsTranscriptWithoutLoadingUI() async {
        let transcript = await MainActor.run {
            let controller = PocketRootTerminalViewController()
            controller.appendOutput("hello")
            return controller.transcript
        }

        XCTAssertEqual(transcript, "Terminal integration pending\nhello")
    }

    func testControllerCanClearTranscript() async {
        let transcript = await MainActor.run {
            let controller = PocketRootTerminalViewController()
            controller.clearOutput()
            return controller.transcript
        }

        XCTAssertTrue(transcript.isEmpty)
    }

    func testCommandSessionCarriesWorkingDirectoryAndHidesProtocolMarker() async throws {
        let executor = TerminalExecutorStub { request in
            let marker = try Self.marker(from: request.command)
            let directory = request.workingDirectory == "/root" ? "/root/project" : "/root/project"
            var output = Data("visible output\n".utf8)
            output.append(0x1e)
            output.append(contentsOf: marker.utf8)
            output.append(0x1f)
            output.append(contentsOf: directory.utf8)
            output.append(0x1e)
            return PocketRootCommandResult(
                exitCode: 0,
                standardOutput: output
            )
        }
        let session = PocketRootCommandTerminalSession(executor: executor)

        let first = try await session.execute("cd project && ls")
        let second = try await session.execute("touch hello.txt")
        let requests = await executor.recordedRequests

        XCTAssertEqual(first.workingDirectory, "/root/project")
        XCTAssertEqual(first.result.stdout, "visible output\n")
        XCTAssertEqual(second.workingDirectory, "/root/project")
        XCTAssertEqual(requests.map(\.workingDirectory), ["/root", "/root/project"])
        XCTAssertTrue(requests[0].command.contains("cd project && ls"))
        XCTAssertTrue(requests[1].command.contains("touch hello.txt"))
    }

    func testCommandSessionPreservesDirectoryWhenMarkerIsMissing() async throws {
        let executor = TerminalExecutorStub { _ in
            PocketRootCommandResult(
                exitCode: 7,
                standardOutput: Data("shell exited early".utf8)
            )
        }
        let session = PocketRootCommandTerminalSession(
            executor: executor,
            workingDirectory: "/safe"
        )

        let response = try await session.execute("exit 7")

        XCTAssertEqual(response.workingDirectory, "/safe")
        XCTAssertEqual(response.result.stdout, "shell exited early")
        XCTAssertEqual(response.result.exitCode, 7)
    }

    func testCommandSessionCapturesPhysicalDirectoryInsteadOfMutablePWD() async throws {
        let executor = TerminalExecutorStub { request in
            let marker = try Self.marker(from: request.command)
            var output = Data([0x1e])
            output.append(contentsOf: marker.utf8)
            output.append(0x1f)
            output.append(contentsOf: "/actual/location".utf8)
            output.append(0x1e)
            return PocketRootCommandResult(exitCode: 0, standardOutput: output)
        }
        let session = PocketRootCommandTerminalSession(
            executor: executor,
            workingDirectory: "/actual"
        )

        let response = try await session.execute("PWD=/spoofed")
        let requests = await executor.recordedRequests
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(response.workingDirectory, "/actual/location")
        XCTAssertTrue(request.command.contains("command pwd -P"))
        XCTAssertFalse(request.command.contains("\"$PWD\""))
    }

    func testCommandSessionRejectsEmptyAndNULCommandsBeforeExecution() async {
        let executor = TerminalExecutorStub { _ in
            XCTFail("Invalid commands must not reach the executor.")
            return PocketRootCommandResult(exitCode: 0)
        }
        let session = PocketRootCommandTerminalSession(executor: executor)

        for command in ["  \n", "printf\0bad"] {
            do {
                _ = try await session.execute(command)
                XCTFail("Expected invalid command rejection.")
            } catch let error as PocketRootCommandTerminalSessionError {
                guard case .invalidCommand = error else {
                    return XCTFail("Unexpected terminal error: \(error)")
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        let requests = await executor.recordedRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCommandSessionRejectsConcurrentSubmission() async throws {
        let executor = SuspendingTerminalExecutor()
        let session = PocketRootCommandTerminalSession(executor: executor)
        let firstCommand = Task {
            try await session.execute("sleep 1")
        }
        await executor.waitUntilStarted()

        do {
            _ = try await session.execute("pwd")
            XCTFail("A second command must not overlap the active command.")
        } catch let error as PocketRootCommandTerminalSessionError {
            XCTAssertEqual(error, .commandInProgress)
        }

        await executor.finish()
        _ = try await firstCommand.value
    }

    @MainActor
    func testBridgeRestoresInputAfterNonCooperativeCancellation() async throws {
        let executor = SuspendingTerminalExecutor()
        let session = PocketRootCommandTerminalSession(executor: executor)
        let bridge = TerminalBridge(session: session)
        var inputStates: [Bool] = []
        bridge.attach(
            outputHandler: { _ in },
            inputStateHandler: { inputStates.append($0) }
        )

        bridge.submit("sleep 30", prompt: "$ ")
        await executor.waitUntilStarted()
        bridge.cancelActiveCommand()
        await executor.finish()

        for _ in 0..<100 where inputStates.last != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(inputStates.last, true)

        bridge.submit("pwd", prompt: "$ ")
        for _ in 0..<100 {
            if await executor.requestCount == 2 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let requestCount = await executor.requestCount
        XCTAssertEqual(requestCount, 2)
        await executor.finish()
        bridge.detach()
    }

    func testFileBrowserParsesNULFramedNamesAndSortsDirectoriesFirst() async throws {
        let executor = TerminalExecutorStub { _ in
            var output = Data()
            for field in [
                "f", "5", "z file.txt",
                "d", "0", "Folder",
                "f", "2", "line\nbreak"
            ] {
                output.append(contentsOf: field.utf8)
                output.append(0)
            }
            return PocketRootCommandResult(
                exitCode: 0,
                standardOutput: output
            )
        }
        let browser = PocketRootFileBrowser(executor: executor)

        let entries = try await browser.listDirectory(at: "/root/a'b")
        let requests = await executor.recordedRequests
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(entries.map(\.name), ["Folder", "line\nbreak", "z file.txt"])
        XCTAssertEqual(entries.map(\.kind), [.directory, .file, .file])
        XCTAssertEqual(entries[0].path, "/root/a'b/Folder")
        XCTAssertTrue(request.command.contains("'\"'\"'"))
    }

    func testFileBrowserBoundsPreviewAndReportsTruncation() async throws {
        let executor = TerminalExecutorStub { _ in
            PocketRootCommandResult(
                exitCode: 0,
                standardOutput: Data(repeating: 0x61, count: 20)
            )
        }
        let browser = PocketRootFileBrowser(executor: executor)

        let preview = try await browser.previewFile(
            at: "/root/example.txt",
            maximumBytes: 8
        )

        XCTAssertEqual(preview.data, Data(repeating: 0x61, count: 8))
        XCTAssertTrue(preview.isTruncated)
        XCTAssertEqual(preview.text, "aaaaaaaa")
    }

    func testFileBrowserRejectsRelativePathBeforeExecution() async {
        let executor = TerminalExecutorStub { _ in
            XCTFail("Invalid paths must not reach the executor.")
            return PocketRootCommandResult(exitCode: 0)
        }
        let browser = PocketRootFileBrowser(executor: executor)

        do {
            _ = try await browser.listDirectory(at: "relative")
            XCTFail("Expected invalid path rejection.")
        } catch let error as PocketRootFileBrowserError {
            XCTAssertEqual(error, .invalidPath)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await executor.recordedRequests
        XCTAssertTrue(requests.isEmpty)
    }

    private static func marker(from command: String) throws -> String {
        guard let start = command.range(of: "'POCKETROOT_CWD_"),
              let end = command[start.upperBound...].firstIndex(of: "'")
        else {
            throw MarkerError.missing
        }
        return String(command[command.index(after: start.lowerBound)..<end])
    }
}

private enum MarkerError: Error {
    case missing
}

private actor TerminalExecutorStub: PocketRootTerminalCommandExecutor {
    typealias Handler = @Sendable (
        PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult

    private let handler: Handler
    private(set) var recordedRequests: [PocketRootCommandRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        recordedRequests.append(request)
        return try await handler(request)
    }
}

private actor SuspendingTerminalExecutor: PocketRootTerminalCommandExecutor {
    private var isStarted = false
    private(set) var requestCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var commandContinuation: CheckedContinuation<
        PocketRootCommandResult,
        Never
    >?

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        isStarted = true
        requestCount += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            commandContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !isStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish() {
        commandContinuation?.resume(
            returning: PocketRootCommandResult(exitCode: 0)
        )
        commandContinuation = nil
    }
}
