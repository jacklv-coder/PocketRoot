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
        XCTAssertTrue(configuration.cursorBlinkEnabled)
    }

    func testCustomConfigurationPreservesValues() {
        let configuration = PocketRootTerminalConfiguration(
            placeholderText: "Waiting for runtime",
            prompt: "root# ",
            allowsInput: true,
            showsAccessoryView: false,
            initialWorkingDirectory: "/work",
            commandTimeout: .seconds(12),
            maximumTranscriptCharacters: 4_096,
            cursorBlinkEnabled: false
        )

        XCTAssertEqual(configuration.placeholderText, "Waiting for runtime")
        XCTAssertEqual(configuration.prompt, "root# ")
        XCTAssertTrue(configuration.allowsInput)
        XCTAssertFalse(configuration.showsAccessoryView)
        XCTAssertEqual(configuration.initialWorkingDirectory, "/work")
        XCTAssertEqual(configuration.commandTimeout, .seconds(12))
        XCTAssertEqual(configuration.maximumTranscriptCharacters, 4_096)
        XCTAssertFalse(configuration.cursorBlinkEnabled)
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
            initialWorkingDirectory: "/workspace",
            cursorBlinkEnabled: false
        )

        let resolved = configuration
            .resolvingInteractiveSessionConfiguration(nil)

        XCTAssertEqual(resolved.workingDirectory, "/workspace")
        XCTAssertFalse(configuration.cursorBlinkEnabled)
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

    func testWorkspaceConfigurationDefaultsToInteractiveRootTerminal() {
        let configuration = PocketRootWorkspaceConfiguration()

        XCTAssertEqual(
            configuration.terminalConfiguration,
            .interactive()
        )
        XCTAssertNil(configuration.terminalSessionConfiguration)
        XCTAssertEqual(configuration.terminalTheme, .dark)
        XCTAssertEqual(configuration.initialFilePath, "/root")
        XCTAssertEqual(configuration.initialSurface, .terminal)
        XCTAssertTrue(configuration.allowsFileOperations)
        XCTAssertEqual(
            PocketRootWorkspaceSurface.allCases,
            [.terminal, .files]
        )
    }

    func testWorkspaceConfigurationPreservesCustomSurfaces() {
        let session = PocketRootSessionConfiguration(
            shell: "/bin/ash",
            workingDirectory: "/workspace",
            environment: ["TERM": "xterm-256color"]
        )
        let configuration = PocketRootWorkspaceConfiguration(
            terminalConfiguration: .interactive(
                initialWorkingDirectory: "/fallback",
                cursorBlinkEnabled: false
            ),
            terminalSessionConfiguration: session,
            terminalTheme: PocketRootTerminalTheme(
                palette: .system,
                fontSize: 17
            ),
            initialFilePath: "/workspace",
            initialSurface: .files,
            allowsFileOperations: false
        )

        XCTAssertEqual(
            configuration.terminalSessionConfiguration,
            session
        )
        XCTAssertFalse(
            configuration.terminalConfiguration.cursorBlinkEnabled
        )
        XCTAssertEqual(configuration.terminalTheme.fontSize, 17)
        XCTAssertEqual(configuration.initialFilePath, "/workspace")
        XCTAssertEqual(configuration.initialSurface, .files)
        XCTAssertFalse(configuration.allowsFileOperations)
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

    func testFileBrowserCreatesFileAndDirectoryWithQuotedAbsolutePaths() async throws {
        let executor = TerminalExecutorStub { _ in
            PocketRootCommandResult(exitCode: 0)
        }
        let browser = PocketRootFileBrowser(executor: executor)

        let filePath = try await browser.createFile(
            named: "it's ready.txt",
            in: "/root/project"
        )
        let directoryPath = try await browser.createDirectory(
            named: "New Folder",
            in: "/root/project"
        )
        let requests = await executor.recordedRequests

        XCTAssertEqual(filePath, "/root/project/it's ready.txt")
        XCTAssertEqual(directoryPath, "/root/project/New Folder")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.workingDirectory), ["/", "/"])
        XCTAssertTrue(requests[0].command.contains(
            "'/root/project/it'\"'\"'s ready.txt'"
        ))
        XCTAssertTrue(requests[0].command.contains("set -C"))
        XCTAssertTrue(requests[1].command.contains(
            "mkdir -- '/root/project/New Folder'"
        ))
    }

    func testFileBrowserRejectsInvalidNamesBeforeExecution() async {
        let executor = TerminalExecutorStub { _ in
            XCTFail("Invalid names must not reach the executor.")
            return PocketRootCommandResult(exitCode: 0)
        }
        let browser = PocketRootFileBrowser(executor: executor)

        for name in ["", ".", "..", "nested/name", "nul\0name"] {
            do {
                _ = try await browser.createFile(named: name, in: "/root")
                XCTFail("Expected invalid name rejection for \(name.debugDescription).")
            } catch let error as PocketRootFileBrowserError {
                XCTAssertEqual(error, .invalidName)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        let oversizedName = String(repeating: "é", count: 128)
        do {
            _ = try await browser.createDirectory(
                named: oversizedName,
                in: "/root"
            )
            XCTFail("Expected UTF-8 byte length rejection.")
        } catch let error as PocketRootFileBrowserError {
            XCTAssertEqual(error, .invalidName)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await executor.recordedRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testFileBrowserProtectsGuestRootFromDelete() async {
        let executor = TerminalExecutorStub { _ in
            XCTFail("Protected paths must not reach the executor.")
            return PocketRootCommandResult(exitCode: 0)
        }
        let browser = PocketRootFileBrowser(executor: executor)

        do {
            try await browser.deleteItem(at: "/", recursively: true)
            XCTFail("Expected protected path rejection.")
        } catch let error as PocketRootFileBrowserError {
            XCTAssertEqual(error, .protectedPath)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await executor.recordedRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testFileBrowserRequiresExplicitRecursiveDirectoryDeletion() async throws {
        let executor = TerminalExecutorStub { _ in
            PocketRootCommandResult(exitCode: 0)
        }
        let browser = PocketRootFileBrowser(executor: executor)

        try await browser.deleteItem(at: "/root/empty")
        try await browser.deleteItem(at: "/root/project", recursively: true)
        let requests = await executor.recordedRequests

        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].command.contains(
            "rmdir -- '/root/empty'"
        ))
        XCTAssertFalse(requests[0].command.contains("rm -rf --"))
        XCTAssertTrue(requests[1].command.contains(
            "rm -rf -- '/root/project'"
        ))
    }

    func testFileBrowserRenamesThroughNativeNoReplaceCapability() async throws {
        let executor = TerminalExecutorStub { _ in
            XCTFail("Rename must not execute a shell command.")
            return PocketRootCommandResult(exitCode: 0)
        }
        let renamer = FileRenameExecutorStub()
        let browser = PocketRootFileBrowser(
            executor: executor,
            renameExecutor: renamer,
            timeout: .seconds(7)
        )

        let path = try await browser.renameItem(
            at: "/root/project/old name.txt",
            to: "new name.txt"
        )

        XCTAssertEqual(path, "/root/project/new name.txt")
        let requests = await executor.recordedRequests
        XCTAssertTrue(requests.isEmpty)
        let calls = await renamer.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].sourcePath, "/root/project/old name.txt")
        XCTAssertEqual(calls[0].destinationPath, "/root/project/new name.txt")
        XCTAssertEqual(calls[0].timeout, .seconds(7))
    }

    func testFileBrowserRenameDoesNotReplaceExistingDestination() async {
        let executor = TerminalExecutorStub { _ in
            PocketRootCommandResult(exitCode: 0)
        }
        let renamer = FileRenameExecutorStub(
            error: PocketRootError.fileDestinationExists(
                "/root/project/existing.txt"
            )
        )
        let browser = PocketRootFileBrowser(
            executor: executor,
            renameExecutor: renamer
        )

        do {
            _ = try await browser.renameItem(
                at: "/root/project/source.txt",
                to: "existing.txt"
            )
            XCTFail("An existing destination must not be replaced.")
        } catch let error as PocketRootFileBrowserError {
            XCTAssertEqual(
                error,
                .destinationExists("/root/project/existing.txt")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFileBrowserRenameValidatesBeforeNativeAdmission() async {
        let executor = TerminalExecutorStub { _ in
            PocketRootCommandResult(exitCode: 0)
        }
        let renamer = FileRenameExecutorStub()
        let browser = PocketRootFileBrowser(
            executor: executor,
            renameExecutor: renamer
        )

        do {
            _ = try await browser.renameItem(at: "/", to: "root")
            XCTFail("The guest root must not be renamed.")
        } catch let error as PocketRootFileBrowserError {
            XCTAssertEqual(error, .protectedPath)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await browser.renameItem(
                at: "/root/source.txt",
                to: "nested/name"
            )
            XCTFail("A rename target must be a single valid item name.")
        } catch let error as PocketRootFileBrowserError {
            XCTAssertEqual(error, .invalidName)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let calls = await renamer.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testFileTreeExpandsDirectoriesInlineAtTheExpectedDepth() {
        let project = PocketRootFileEntry(
            name: "project",
            path: "/root/project",
            kind: .directory,
            size: 0
        )
        let readme = PocketRootFileEntry(
            name: "README.md",
            path: "/root/README.md",
            kind: .file,
            size: 128
        )
        let sources = PocketRootFileEntry(
            name: "Sources",
            path: "/root/project/Sources",
            kind: .directory,
            size: 0
        )
        let main = PocketRootFileEntry(
            name: "main.swift",
            path: "/root/project/Sources/main.swift",
            kind: .file,
            size: 64
        )
        var tree = PocketRootFileTreeState()
        tree.replaceRootEntries([project, readme])
        tree.replaceChildren([sources], of: project.path)
        tree.replaceChildren([main], of: sources.path)

        tree.expand(project.path)
        tree.expand(sources.path)

        XCTAssertEqual(
            tree.visibleRows,
            [
                PocketRootFileTreeRow(entry: project, depth: 0),
                PocketRootFileTreeRow(entry: sources, depth: 1),
                PocketRootFileTreeRow(entry: main, depth: 2),
                PocketRootFileTreeRow(entry: readme, depth: 0)
            ]
        )
    }

    func testFileTreeCollapseHidesDescendantsWithoutDiscardingCache() {
        let directory = PocketRootFileEntry(
            name: "folder",
            path: "/root/folder",
            kind: .directory,
            size: 0
        )
        let file = PocketRootFileEntry(
            name: "file.txt",
            path: "/root/folder/file.txt",
            kind: .file,
            size: 1
        )
        var tree = PocketRootFileTreeState()
        tree.replaceRootEntries([directory])
        tree.replaceChildren([file], of: directory.path)
        tree.expand(directory.path)

        tree.collapse(directory.path)

        XCTAssertEqual(
            tree.visibleRows,
            [PocketRootFileTreeRow(entry: directory, depth: 0)]
        )
        XCTAssertTrue(tree.hasLoadedChildren(of: directory.path))

        tree.expand(directory.path)

        XCTAssertEqual(tree.visibleRows.map(\.entry), [directory, file])
    }

    func testFileTreeRefreshClearsCachedChildrenBeforePreservingExpansion() {
        let directory = PocketRootFileEntry(
            name: "folder",
            path: "/root/folder",
            kind: .directory,
            size: 0
        )
        let staleFile = PocketRootFileEntry(
            name: "stale.txt",
            path: "/root/folder/stale.txt",
            kind: .file,
            size: 1
        )
        var tree = PocketRootFileTreeState()
        tree.replaceRootEntries([directory])
        tree.replaceChildren([staleFile], of: directory.path)
        tree.expand(directory.path)

        let refreshedTree = tree.refreshSnapshot(rootEntries: [directory])

        XCTAssertTrue(refreshedTree.isExpanded(directory.path))
        XCTAssertFalse(refreshedTree.hasLoadedChildren(of: directory.path))
        XCTAssertEqual(refreshedTree.visibleRows.map(\.entry), [directory])

        XCTAssertTrue(tree.isExpanded(directory.path))
        XCTAssertTrue(tree.hasLoadedChildren(of: directory.path))
        XCTAssertEqual(tree.visibleRows.map(\.entry), [directory, staleFile])
    }

    func testFileTreeCanceledLoadsReturnDirectoriesToCollapsedState() {
        let project = PocketRootFileEntry(
            name: "project",
            path: "/root/project",
            kind: .directory,
            size: 0
        )
        let sources = PocketRootFileEntry(
            name: "Sources",
            path: "/root/project/Sources",
            kind: .directory,
            size: 0
        )
        var tree = PocketRootFileTreeState()
        tree.replaceRootEntries([project])
        tree.replaceChildren([sources], of: project.path)
        tree.expand(project.path)
        tree.expand(sources.path)

        tree.collapse(directoriesAt: [project.path, sources.path])

        XCTAssertFalse(tree.isExpanded(project.path))
        XCTAssertFalse(tree.isExpanded(sources.path))

        tree.expand(project.path)

        XCTAssertEqual(tree.visibleRows.map(\.entry), [project, sources])
        XCTAssertFalse(tree.isExpanded(sources.path))
        XCTAssertFalse(tree.hasLoadedChildren(of: sources.path))
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

private actor FileRenameExecutorStub: PocketRootFileRenameExecutor {
    struct Call: Sendable {
        let sourcePath: String
        let destinationPath: String
        let timeout: Duration
    }

    private let error: PocketRootError?
    private(set) var calls: [Call] = []

    init(error: PocketRootError? = nil) {
        self.error = error
    }

    func renameItem(
        at sourcePath: String,
        to destinationPath: String,
        timeout: Duration
    ) async throws {
        calls.append(
            Call(
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                timeout: timeout
            )
        )
        if let error {
            throw error
        }
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
