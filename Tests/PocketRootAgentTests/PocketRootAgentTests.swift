import Foundation
import XCTest
@testable import PocketRootAgent

@available(macOS 13.0, *)
final class PocketRootAgentTests: XCTestCase {
    func testReturnsFinalResponseWithoutExecutingTools() async throws {
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-1",
                    outputText: "Finished."
                )
            ]
        )
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration()
        )

        let result = try await runner.run(userInput: "Do the task")

        XCTAssertEqual(
            result,
            PocketRootAgentRunResult(
                finalOutput: "Finished.",
                responseID: "response-1",
                turnCount: 1,
                toolCallCount: 0
            )
        )
        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].input, .user("Do the task"))
        XCTAssertNil(requests[0].previousResponseID)
    }

    func testExecutesToolAndContinuesWithCallIDAndResponseID() async throws {
        let call = PocketRootAgentToolCall(
            id: "call-1",
            name: "lookup",
            argumentsJSON: #"{"query":"status"}"#
        )
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(id: "response-1", toolCalls: [call]),
                PocketRootAgentModelResponse(
                    id: "response-2",
                    outputText: "The status is ready."
                )
            ]
        )
        let recorder = ToolRecorder()
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration(),
            tools: [
                makeTool(name: "lookup") { call in
                    await recorder.record(call)
                    return #"{"ok":true,"status":"ready"}"#
                }
            ]
        )

        let result = try await runner.run(userInput: "Check status")

        XCTAssertEqual(result.turnCount, 2)
        XCTAssertEqual(result.toolCallCount, 1)
        XCTAssertEqual(result.finalOutput, "The status is ready.")
        let recordedCalls = await recorder.recordedCalls()
        XCTAssertEqual(recordedCalls, [call])

        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].previousResponseID, "response-1")
        XCTAssertEqual(
            requests[1].input,
            .toolOutputs([
                PocketRootAgentToolOutput(
                    callID: "call-1",
                    output: #"{"ok":true,"status":"ready"}"#
                )
            ])
        )
    }

    func testUnknownToolReturnsStructuredFailureForModelRecovery() async throws {
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-1",
                    toolCalls: [
                        PocketRootAgentToolCall(
                            id: "call-unknown",
                            name: "missing",
                            argumentsJSON: "{}"
                        )
                    ]
                ),
                PocketRootAgentModelResponse(
                    id: "response-2",
                    outputText: "I cannot use that tool."
                )
            ]
        )
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration()
        )

        let result = try await runner.run(userInput: "Try the missing tool")

        XCTAssertEqual(result.finalOutput, "I cannot use that tool.")
        let requests = await client.recordedRequests()
        guard case .toolOutputs(let outputs) = requests[1].input else {
            return XCTFail("Expected tool outputs on the continuation turn.")
        }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(outputs[0].callID, "call-unknown")
        XCTAssertTrue(outputs[0].output.contains(#""ok":false"#))
        XCTAssertTrue(outputs[0].output.contains("Unknown tool 'missing'."))
    }

    func testToolFailureReturnsStructuredFailureForModelRecovery() async throws {
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-1",
                    toolCalls: [
                        PocketRootAgentToolCall(
                            id: "call-failure",
                            name: "failing",
                            argumentsJSON: "{}"
                        )
                    ]
                ),
                PocketRootAgentModelResponse(
                    id: "response-2",
                    outputText: "The tool failed safely."
                )
            ]
        )
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration(),
            tools: [
                makeTool(name: "failing") { _ in
                    throw SyntheticError.failed
                }
            ]
        )

        let result = try await runner.run(userInput: "Run the failing tool")

        XCTAssertEqual(result.finalOutput, "The tool failed safely.")
        let requests = await client.recordedRequests()
        guard case .toolOutputs(let outputs) = requests[1].input else {
            return XCTFail("Expected a tool failure output.")
        }
        XCTAssertTrue(outputs[0].output.contains(#""ok":false"#))
        XCTAssertTrue(outputs[0].output.contains("synthetic failure"))
    }

    func testRejectsRepeatedToolCallIDBeforeSecondSideEffect() async throws {
        let repeatedCall = PocketRootAgentToolCall(
            id: "call-repeated",
            name: "counter",
            argumentsJSON: "{}"
        )
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-1",
                    toolCalls: [repeatedCall]
                ),
                PocketRootAgentModelResponse(
                    id: "response-2",
                    toolCalls: [repeatedCall]
                )
            ]
        )
        let counter = ToolCounter()
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration(),
            tools: [
                makeTool(name: "counter") { _ in
                    await counter.increment()
                    return "ok"
                }
            ]
        )

        do {
            _ = try await runner.run(userInput: "Repeat the call")
            XCTFail("A repeated call ID must fail the run.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(error, .duplicateToolCallID("call-repeated"))
        }
        let callCount = await counter.value()
        XCTAssertEqual(callCount, 1)
    }

    func testValidatesWholeToolBatchBeforeFirstSideEffect() async throws {
        let duplicateCalls = [
            PocketRootAgentToolCall(
                id: "call-duplicate",
                name: "counter",
                argumentsJSON: "{}"
            ),
            PocketRootAgentToolCall(
                id: "call-duplicate",
                name: "counter",
                argumentsJSON: "{}"
            )
        ]
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-1",
                    toolCalls: duplicateCalls
                )
            ]
        )
        let counter = ToolCounter()
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration(),
            tools: [
                makeTool(name: "counter") { _ in
                    await counter.increment()
                    return "ok"
                }
            ]
        )

        do {
            _ = try await runner.run(userInput: "Use both calls")
            XCTFail("A duplicate call ID must reject the complete batch.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(error, .duplicateToolCallID("call-duplicate"))
        }
        let callCount = await counter.value()
        XCTAssertEqual(callCount, 0)
    }

    func testTurnLimitStopsBeforeUnfinishableToolSideEffect() async throws {
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-1",
                    toolCalls: [
                        PocketRootAgentToolCall(
                            id: "call-1",
                            name: "counter",
                            argumentsJSON: "{}"
                        )
                    ]
                )
            ]
        )
        let counter = ToolCounter()
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: PocketRootAgentConfiguration(
                instructions: "Test",
                maximumTurns: 1
            ),
            tools: [
                makeTool(name: "counter") { _ in
                    await counter.increment()
                    return "ok"
                }
            ]
        )

        do {
            _ = try await runner.run(userInput: "Use the tool")
            XCTFail("A one-turn run cannot execute a tool and continue.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(error, .maximumTurnsExceeded(1))
        }
        let callCount = await counter.value()
        XCTAssertEqual(callCount, 0)
    }

    func testRejectsToolOutputOverConfiguredByteLimit() async throws {
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-1",
                    toolCalls: [
                        PocketRootAgentToolCall(
                            id: "call-1",
                            name: "large",
                            argumentsJSON: "{}"
                        )
                    ]
                )
            ]
        )
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: PocketRootAgentConfiguration(
                instructions: "Test",
                maximumToolOutputBytes: 3
            ),
            tools: [
                makeTool(name: "large") { _ in "four" }
            ]
        )

        do {
            _ = try await runner.run(userInput: "Produce output")
            XCTFail("Oversized tool output must fail the run.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(
                error,
                .toolOutputLimitExceeded(tool: "large", limit: 3)
            )
        }
    }

    func testEnforcesInputModelOutputAndToolArgumentLimits() async throws {
        let inputLimitedRunner = try PocketRootAgentRunner(
            modelClient: ScriptedModelClient(responses: []),
            configuration: PocketRootAgentConfiguration(
                instructions: "Test",
                maximumUserInputBytes: 3
            )
        )
        do {
            _ = try await inputLimitedRunner.run(userInput: "four")
            XCTFail("Oversized user input must fail before the model call.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(error, .userInputLimitExceeded(3))
        }

        let outputLimitedRunner = try PocketRootAgentRunner(
            modelClient: ScriptedModelClient(
                responses: [
                    PocketRootAgentModelResponse(
                        id: "response-output",
                        outputText: "four"
                    )
                ]
            ),
            configuration: PocketRootAgentConfiguration(
                instructions: "Test",
                maximumModelOutputBytes: 3
            )
        )
        do {
            _ = try await outputLimitedRunner.run(userInput: "ok")
            XCTFail("Oversized model output must fail.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(error, .modelOutputLimitExceeded(3))
        }

        let argumentLimitedRunner = try PocketRootAgentRunner(
            modelClient: ScriptedModelClient(
                responses: [
                    PocketRootAgentModelResponse(
                        id: "response-arguments",
                        toolCalls: [
                            PocketRootAgentToolCall(
                                id: "call-arguments",
                                name: "lookup",
                                argumentsJSON: #"{"value":"too large"}"#
                            )
                        ]
                    )
                ]
            ),
            configuration: PocketRootAgentConfiguration(
                instructions: "Test",
                maximumToolArgumentsBytes: 2
            ),
            tools: [makeTool(name: "lookup") { _ in "unused" }]
        )
        do {
            _ = try await argumentLimitedRunner.run(userInput: "lookup")
            XCTFail("Oversized tool arguments must fail.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(
                error,
                .toolArgumentsLimitExceeded(tool: "lookup", limit: 2)
            )
        }
    }

    func testRejectsRepeatedResponseID() async throws {
        let client = ScriptedModelClient(
            responses: [
                PocketRootAgentModelResponse(
                    id: "response-repeated",
                    toolCalls: [
                        PocketRootAgentToolCall(
                            id: "call-1",
                            name: "lookup",
                            argumentsJSON: "{}"
                        )
                    ]
                ),
                PocketRootAgentModelResponse(
                    id: "response-repeated",
                    outputText: "replayed"
                )
            ]
        )
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration(),
            tools: [makeTool(name: "lookup") { _ in "ok" }]
        )

        do {
            _ = try await runner.run(userInput: "Check replay handling")
            XCTFail("A repeated response ID must fail the run.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(
                error,
                .invalidModelResponse(
                    "response ID 'response-repeated' was repeated."
                )
            )
        }
    }

    func testRejectsConcurrentRunOnSameRunner() async throws {
        let responseStarted = expectation(description: "model response started")
        let gate = TestAsyncGate()
        let client = BlockingModelClient(
            responseStarted: responseStarted,
            gate: gate
        )
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration()
        )
        let firstRun = Task {
            try await runner.run(userInput: "First")
        }
        await fulfillment(of: [responseStarted], timeout: 2)

        do {
            _ = try await runner.run(userInput: "Second")
            XCTFail("A concurrent run must be rejected.")
        } catch let error as PocketRootAgentError {
            XCTAssertEqual(error, .runAlreadyInProgress)
        }

        await gate.open()
        let result = try await firstRun.value
        XCTAssertEqual(result.finalOutput, "Finished.")
    }

    func testCancellationAfterNonCooperativeModelWaitCannotReturnSuccess() async throws {
        let responseStarted = expectation(description: "model response started")
        let gate = TestAsyncGate()
        let client = BlockingModelClient(
            responseStarted: responseStarted,
            gate: gate
        )
        let runner = try PocketRootAgentRunner(
            modelClient: client,
            configuration: configuration()
        )
        let run = Task {
            try await runner.run(userInput: "Cancel me")
        }
        await fulfillment(of: [responseStarted], timeout: 2)

        run.cancel()
        await gate.open()

        do {
            _ = try await run.value
            XCTFail("A cancelled run must not return the model's final output.")
        } catch is CancellationError {
            // Expected even though the injected model client ignored cancellation.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidatesConfigurationAndToolDefinitions() {
        XCTAssertThrowsError(
            try PocketRootAgentRunner(
                modelClient: ScriptedModelClient(responses: []),
                configuration: PocketRootAgentConfiguration(
                    instructions: "Test",
                    maximumTurns: 0
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootAgentError,
                .invalidConfiguration(
                    "maximumTurns must be greater than zero."
                )
            )
        }

        let duplicateTools = [
            makeTool(name: "same") { _ in "first" },
            makeTool(name: "same") { _ in "second" }
        ]
        XCTAssertThrowsError(
            try PocketRootAgentRunner(
                modelClient: ScriptedModelClient(responses: []),
                configuration: configuration(),
                tools: duplicateTools
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootAgentError,
                .invalidToolDefinition("duplicate tool name 'same'.")
            )
        }

        let invalidSchema = PocketRootAgentTool(
            definition: PocketRootAgentToolDefinition(
                name: "invalid",
                description: "Invalid schema",
                parametersJSONSchema: "[]"
            )
        ) { _ in "unused" }
        XCTAssertThrowsError(
            try PocketRootAgentRunner(
                modelClient: ScriptedModelClient(responses: []),
                configuration: configuration(),
                tools: [invalidSchema]
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootAgentError,
                .invalidToolDefinition(
                    "tool 'invalid' must have an object JSON schema."
                )
            )
        }
    }

    private func configuration() -> PocketRootAgentConfiguration {
        PocketRootAgentConfiguration(instructions: "Complete the task safely.")
    }

    private func makeTool(
        name: String,
        handler: @escaping @Sendable (
            PocketRootAgentToolCall
        ) async throws -> String
    ) -> PocketRootAgentTool {
        PocketRootAgentTool(
            definition: PocketRootAgentToolDefinition(
                name: name,
                description: "Test tool \(name)",
                parametersJSONSchema: """
                {
                  "type": "object",
                  "properties": {},
                  "required": [],
                  "additionalProperties": false
                }
                """
            ),
            handler: handler
        )
    }
}

@available(macOS 13.0, *)
private actor ScriptedModelClient: PocketRootAgentModelClient {
    private var responses: [PocketRootAgentModelResponse]
    private var requests: [PocketRootAgentModelRequest] = []

    init(responses: [PocketRootAgentModelResponse]) {
        self.responses = responses
    }

    func createResponse(
        _ request: PocketRootAgentModelRequest
    ) async throws -> PocketRootAgentModelResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw SyntheticError.noResponse
        }
        return responses.removeFirst()
    }

    func recordedRequests() -> [PocketRootAgentModelRequest] {
        requests
    }
}

@available(macOS 13.0, *)
private actor BlockingModelClient: PocketRootAgentModelClient {
    private let responseStarted: XCTestExpectation
    private let gate: TestAsyncGate

    init(responseStarted: XCTestExpectation, gate: TestAsyncGate) {
        self.responseStarted = responseStarted
        self.gate = gate
    }

    func createResponse(
        _: PocketRootAgentModelRequest
    ) async throws -> PocketRootAgentModelResponse {
        responseStarted.fulfill()
        await gate.wait()
        return PocketRootAgentModelResponse(
            id: "response-1",
            outputText: "Finished."
        )
    }
}

private actor ToolRecorder {
    private var calls: [PocketRootAgentToolCall] = []

    func record(_ call: PocketRootAgentToolCall) {
        calls.append(call)
    }

    func recordedCalls() -> [PocketRootAgentToolCall] {
        calls
    }
}

private actor ToolCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private actor TestAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private enum SyntheticError: LocalizedError {
    case failed
    case noResponse

    var errorDescription: String? {
        switch self {
        case .failed:
            return "synthetic failure"
        case .noResponse:
            return "no scripted response"
        }
    }
}
