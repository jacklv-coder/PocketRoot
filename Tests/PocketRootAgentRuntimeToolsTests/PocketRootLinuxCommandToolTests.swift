import Foundation
import PocketRootAgent
@testable import PocketRootAgentRuntimeTools
import PocketRootCore
import XCTest

@available(macOS 13.0, *)
final class PocketRootLinuxCommandToolTests: XCTestCase {
    func testDefinitionUsesAFlatStrictSchema() throws {
        let tool = try makeTool()
        let schema = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(tool.definition.parametersJSONSchema.utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)

        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertEqual(
            Set(required),
            Set([
                "command",
                "working_directory",
                "environment",
                "timeout_seconds",
                "merge_standard_error"
            ])
        )
        let properties = try XCTUnwrap(
            schema["properties"] as? [String: Any]
        )
        let environment = try XCTUnwrap(
            properties["environment"] as? [String: Any]
        )
        let items = try XCTUnwrap(environment["items"] as? [String: Any])
        XCTAssertEqual(items["additionalProperties"] as? Bool, false)
        XCTAssertEqual(
            Set(try XCTUnwrap(items["required"] as? [String])),
            Set(["name", "value"])
        )
    }

    func testPolicyDenialSkipsApprovalAndExecution() async throws {
        let approvalRecorder = ApprovalRecorder()
        let commandRecorder = CommandRecorder()
        let tool = try makeTool(
            recorder: commandRecorder,
            policy: .denyAll,
            approval: PocketRootLinuxCommandApproval { command in
                await approvalRecorder.record(command)
                return .approved
            }
        )

        let output = try await tool.execute(validCall())
        let json = try jsonObject(output)

        XCTAssertEqual(json["status"] as? String, "denied")
        XCTAssertEqual(json["stage"] as? String, "policy")
        let approvalCount = await approvalRecorder.commands().count
        let commandCount = await commandRecorder.requests().count
        XCTAssertEqual(approvalCount, 0)
        XCTAssertEqual(commandCount, 0)
    }

    func testApprovalDenialReceivesNormalizedRequestAndSkipsExecution() async throws {
        let approvalRecorder = ApprovalRecorder()
        let commandRecorder = CommandRecorder()
        let tool = try makeTool(
            recorder: commandRecorder,
            configuration: configuration(),
            policy: .exactCommands(["printf ok"]),
            approval: PocketRootLinuxCommandApproval { command in
                await approvalRecorder.record(command)
                return .denied(reason: "Not now.")
            }
        )

        let output = try await tool.execute(
            validCall(
                workingDirectory: "/work//project",
                environment: [["name": "MODE", "value": "test"]]
            )
        )
        let json = try jsonObject(output)

        XCTAssertEqual(json["status"] as? String, "denied")
        XCTAssertEqual(json["stage"] as? String, "approval")
        XCTAssertEqual(json["reason"] as? String, "Not now.")
        let approvedCommands = await approvalRecorder.commands()
        XCTAssertEqual(approvedCommands.count, 1)
        XCTAssertEqual(approvedCommands[0].workingDirectory, "/work/project")
        XCTAssertEqual(approvedCommands[0].environment, ["MODE": "test"])
        let commandCount = await commandRecorder.requests().count
        XCTAssertEqual(commandCount, 0)
    }

    func testApprovedCommandMapsExactRequestAndStructuredResult() async throws {
        let approvalRecorder = ApprovalRecorder()
        let commandRecorder = CommandRecorder(
            result: PocketRootCommandResult(
                exitCode: 7,
                signal: 9,
                standardOutput: Data("hello".utf8),
                standardError: Data([0xFF]),
                timedOut: true
            )
        )
        let tool = try makeTool(
            recorder: commandRecorder,
            configuration: configuration(allowsMergedStandardError: true),
            policy: .exactCommands(["printf ok"]),
            approval: PocketRootLinuxCommandApproval { command in
                await approvalRecorder.record(command)
                return .approved
            }
        )

        let output = try await tool.execute(
            validCall(
                workingDirectory: "",
                environment: [["name": "MODE", "value": "test value"]],
                timeoutSeconds: 12,
                mergeStandardError: true
            )
        )
        let json = try jsonObject(output)

        XCTAssertEqual(json["status"] as? String, "completed")
        XCTAssertEqual(json["exit_code"] as? Int, 7)
        XCTAssertEqual(json["signal"] as? Int, 9)
        XCTAssertEqual(json["timed_out"] as? Bool, true)
        let stdout = try XCTUnwrap(json["stdout"] as? [String: Any])
        XCTAssertEqual(stdout["encoding"] as? String, "utf8")
        XCTAssertEqual(stdout["data"] as? String, "hello")
        XCTAssertEqual(stdout["truncated"] as? Bool, false)
        let stderr = try XCTUnwrap(json["stderr"] as? [String: Any])
        XCTAssertEqual(stderr["encoding"] as? String, "base64")
        XCTAssertEqual(stderr["data"] as? String, "/w==")

        let requests = await commandRecorder.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].command, "printf ok")
        XCTAssertEqual(requests[0].workingDirectory, "/work")
        XCTAssertEqual(requests[0].environment, ["MODE": "test value"])
        XCTAssertEqual(requests[0].timeout, .seconds(12))
        XCTAssertEqual(requests[0].mergeStandardError, true)
        let approvalCount = await approvalRecorder.commands().count
        XCTAssertEqual(approvalCount, 1)
    }

    func testInvalidArgumentsFailBeforePolicyApprovalOrExecution() async throws {
        let approvalRecorder = ApprovalRecorder()
        let commandRecorder = CommandRecorder()
        let policyRecorder = SynchronousPolicyRecorder()
        let tool = try makeTool(
            recorder: commandRecorder,
            configuration: configuration(),
            policy: PocketRootLinuxCommandPolicy { command in
                policyRecorder.record(command)
                return .allowed
            },
            approval: PocketRootLinuxCommandApproval { command in
                await approvalRecorder.record(command)
                return .approved
            }
        )

        let invalidCalls = [
            validCall(command: "printf ok\nrm -rf /"),
            validCall(workingDirectory: "/work/../etc"),
            validCall(workingDirectory: "/etc"),
            validCall(environment: [["name": "SECRET", "value": "x"]]),
            validCall(
                environment: [
                    ["name": "MODE", "value": "one"],
                    ["name": "MODE", "value": "two"]
                ]
            ),
            validCall(timeoutSeconds: 31),
            validCall(mergeStandardError: true),
            PocketRootAgentToolCall(
                id: "call_unknown",
                name: PocketRootLinuxCommandTool.toolName,
                argumentsJSON: """
                {
                  "command": "printf ok",
                  "working_directory": "/work",
                  "environment": [],
                  "timeout_seconds": 5,
                  "merge_standard_error": false,
                  "unexpected": true
                }
                """
            ),
            PocketRootAgentToolCall(
                id: "call_duplicate_root_key",
                name: PocketRootLinuxCommandTool.toolName,
                argumentsJSON: """
                {
                  "command": "printf ok",
                  "comm\\u0061nd": "printf shadowed",
                  "working_directory": "/work",
                  "environment": [],
                  "timeout_seconds": 5,
                  "merge_standard_error": false
                }
                """
            ),
            PocketRootAgentToolCall(
                id: "call_duplicate_environment_key",
                name: PocketRootLinuxCommandTool.toolName,
                argumentsJSON: """
                {
                  "command": "printf ok",
                  "working_directory": "/work",
                  "environment": [
                    {"name": "MODE", "name": "MODE", "value": "test"}
                  ],
                  "timeout_seconds": 5,
                  "merge_standard_error": false
                }
                """
            )
        ]

        for call in invalidCalls {
            do {
                _ = try await tool.execute(call)
                XCTFail("Invalid call \(call.id) must be rejected.")
            } catch is PocketRootLinuxCommandToolError {
                // Expected.
            }
        }

        XCTAssertEqual(policyRecorder.commands.count, 0)
        let approvalCount = await approvalRecorder.commands().count
        let commandCount = await commandRecorder.requests().count
        XCTAssertEqual(approvalCount, 0)
        XCTAssertEqual(commandCount, 0)
    }

    func testRunnerPreflightsWholeCommandBatchBeforeFirstSideEffect() async throws {
        let approvalRecorder = ApprovalRecorder()
        let commandRecorder = CommandRecorder()
        let commandTool = try makeTool(
            recorder: commandRecorder,
            policy: .exactCommands(["printf ok"]),
            approval: PocketRootLinuxCommandApproval { command in
                await approvalRecorder.record(command)
                return .approved
            }
        )
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-1",
                    toolCalls: [
                        validCall(command: "printf ok"),
                        validCall(command: "printf bad\ncommand")
                    ]
                )
            ]
        )
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: PocketRootAgentConfiguration(
                instructions: "Test command preflight."
            ),
            tools: [commandTool.agentTool]
        )

        do {
            _ = try await runner.run(userInput: "Run both commands")
            XCTFail("A malformed later command must reject the whole batch.")
        } catch is PocketRootLinuxCommandToolError {
            // Expected.
        }

        let approvalCount = await approvalRecorder.commands().count
        let commandCount = await commandRecorder.requests().count
        XCTAssertEqual(approvalCount, 0)
        XCTAssertEqual(commandCount, 0)
    }

    func testCancellationAfterNonCooperativeApprovalSkipsExecution() async throws {
        let gate = AsyncGate()
        let commandRecorder = CommandRecorder()
        let tool = try makeTool(
            recorder: commandRecorder,
            policy: .exactCommands(["printf ok"]),
            approval: PocketRootLinuxCommandApproval { _ in
                await gate.wait()
                return .approved
            }
        )

        let call = validCall()
        let task = Task {
            try await tool.execute(call)
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Cancellation must win after approval returns.")
        } catch is CancellationError {
            // Expected.
        }
        let commandCount = await commandRecorder.requests().count
        XCTAssertEqual(commandCount, 0)
    }

    func testCancellationAfterNonCooperativeExecutionDoesNotReturnSuccess() async throws {
        let gate = AsyncGate()
        let commandRecorder = CommandRecorder(gate: gate)
        let tool = try makeTool(
            recorder: commandRecorder,
            policy: .exactCommands(["printf ok"]),
            approval: PocketRootLinuxCommandApproval { _ in .approved }
        )

        let call = validCall()
        let task = Task {
            try await tool.execute(call)
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("A cancelled command must not return a successful tool result.")
        } catch is CancellationError {
            // Expected.
        }
        let commandCount = await commandRecorder.requests().count
        XCTAssertEqual(commandCount, 1)
    }

    func testResultEncodingStaysWithinBudgetAndMarksTruncation() async throws {
        let bytes = Data(repeating: 0, count: 1_024)
        let commandRecorder = CommandRecorder(
            result: PocketRootCommandResult(
                exitCode: 0,
                standardOutput: bytes,
                standardError: bytes
            )
        )
        let tool = try makeTool(
            recorder: commandRecorder,
            configuration: PocketRootLinuxCommandToolConfiguration(
                defaultWorkingDirectory: "/work",
                allowedWorkingDirectoryRoots: ["/work"],
                maximumResultStreamBytes: 1_024,
                maximumToolOutputBytes: 512
            ),
            policy: .exactCommands(["printf ok"]),
            approval: PocketRootLinuxCommandApproval { _ in .approved }
        )

        let output = try await tool.execute(
            validCall(workingDirectory: "/work")
        )
        XCTAssertLessThanOrEqual(output.utf8.count, 512)
        let json = try jsonObject(output)
        let stdout = try XCTUnwrap(json["stdout"] as? [String: Any])
        let stderr = try XCTUnwrap(json["stderr"] as? [String: Any])
        XCTAssertEqual(stdout["truncated"] as? Bool, true)
        XCTAssertEqual(stderr["truncated"] as? Bool, true)
    }

    func testRejectsUnsafeConfiguration() {
        let executor = MockCommandExecutor { _ in PocketRootCommandResult(exitCode: 0) }
        let approval = PocketRootLinuxCommandApproval { _ in .approved }

        XCTAssertThrowsError(
            try PocketRootLinuxCommandTool(
                executor: executor,
                configuration: PocketRootLinuxCommandToolConfiguration(
                    defaultWorkingDirectory: "/work",
                    allowedWorkingDirectoryRoots: []
                ),
                policy: .denyAll,
                approval: approval
            )
        )
        XCTAssertThrowsError(
            try PocketRootLinuxCommandTool(
                executor: executor,
                configuration: PocketRootLinuxCommandToolConfiguration(
                    defaultWorkingDirectory: "/etc",
                    allowedWorkingDirectoryRoots: ["/work"]
                ),
                policy: .denyAll,
                approval: approval
            )
        )
        XCTAssertThrowsError(
            try PocketRootLinuxCommandTool(
                executor: executor,
                configuration: PocketRootLinuxCommandToolConfiguration(
                    allowedEnvironmentNames: ["BAD-NAME"]
                ),
                policy: .denyAll,
                approval: approval
            )
        )
    }

    private func makeTool(
        recorder: CommandRecorder = CommandRecorder(),
        configuration: PocketRootLinuxCommandToolConfiguration = .init(),
        policy: PocketRootLinuxCommandPolicy = .denyAll,
        approval: PocketRootLinuxCommandApproval = .init({ _ in .approved })
    ) throws -> PocketRootLinuxCommandTool {
        try PocketRootLinuxCommandTool(
            executor: MockCommandExecutor { request in
                await recorder.execute(request)
            },
            configuration: configuration,
            policy: policy,
            approval: approval
        )
    }

    private func configuration(
        allowsMergedStandardError: Bool = false
    ) -> PocketRootLinuxCommandToolConfiguration {
        PocketRootLinuxCommandToolConfiguration(
            defaultWorkingDirectory: "/work",
            allowedWorkingDirectoryRoots: ["/work"],
            allowedEnvironmentNames: ["MODE"],
            maximumTimeoutSeconds: 30,
            allowsMergedStandardError: allowsMergedStandardError
        )
    }

    private func validCall(
        command: String = "printf ok",
        workingDirectory: String = "/root",
        environment: [[String: String]] = [],
        timeoutSeconds: Int = 5,
        mergeStandardError: Bool = false
    ) -> PocketRootAgentToolCall {
        let object: [String: Any] = [
            "command": command,
            "working_directory": workingDirectory,
            "environment": environment,
            "timeout_seconds": timeoutSeconds,
            "merge_standard_error": mergeStandardError
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return PocketRootAgentToolCall(
            id: UUID().uuidString,
            name: PocketRootLinuxCommandTool.toolName,
            argumentsJSON: String(decoding: data, as: UTF8.self)
        )
    }

    private func jsonObject(_ output: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(output.utf8)
            ) as? [String: Any]
        )
    }
}

@available(macOS 13.0, *)
private struct MockCommandExecutor: PocketRootCommandExecuting {
    let handler: @Sendable (
        PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult

    init(
        _ handler: @escaping @Sendable (
            PocketRootCommandRequest
        ) async throws -> PocketRootCommandResult
    ) {
        self.handler = handler
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        try await handler(request)
    }
}

@available(macOS 13.0, *)
private actor CommandRecorder {
    private var recordedRequests: [PocketRootCommandRequest] = []
    private let result: PocketRootCommandResult
    private let gate: AsyncGate?

    init(
        result: PocketRootCommandResult = PocketRootCommandResult(exitCode: 0),
        gate: AsyncGate? = nil
    ) {
        self.result = result
        self.gate = gate
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async -> PocketRootCommandResult {
        recordedRequests.append(request)
        if let gate {
            await gate.wait()
        }
        return result
    }

    func requests() -> [PocketRootCommandRequest] {
        recordedRequests
    }
}

@available(macOS 13.0, *)
private actor ApprovalRecorder {
    private var recordedCommands: [PocketRootLinuxCommand] = []

    func record(_ command: PocketRootLinuxCommand) {
        recordedCommands.append(command)
    }

    func commands() -> [PocketRootLinuxCommand] {
        recordedCommands
    }
}

@available(macOS 13.0, *)
private actor AsyncGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilEntered() async {
        while !entered {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@available(macOS 13.0, *)
private final class SynchronousPolicyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCommands: [PocketRootLinuxCommand] = []

    var commands: [PocketRootLinuxCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommands
    }

    func record(_ command: PocketRootLinuxCommand) {
        lock.lock()
        recordedCommands.append(command)
        lock.unlock()
    }
}

@available(macOS 13.0, *)
private actor ScriptedModelClient: PocketRootAgentModelClient {
    private var responses: [PocketRootAgentModelResponse]

    init(responses: [PocketRootAgentModelResponse]) {
        self.responses = responses
    }

    func createResponse(
        _ request: PocketRootAgentModelRequest
    ) async throws -> PocketRootAgentModelResponse {
        guard !responses.isEmpty else {
            throw TestModelError.noResponse
        }
        return responses.removeFirst()
    }
}

private enum TestModelError: Error {
    case noResponse
}
