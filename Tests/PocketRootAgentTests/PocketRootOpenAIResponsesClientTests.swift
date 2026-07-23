import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import PocketRootAgent

@available(macOS 13.0, *)
final class PocketRootOpenAIResponsesClientTests: XCTestCase {
    func testEncodesFirstTurnAndDecodesTextAndFunctionCalls() async throws {
        let recorder = OpenAIRequestRecorder()
        let response = try makeHTTPResult(
            statusCode: 200,
            body: """
            {
              "id": "resp_123",
              "status": "completed",
              "output": [
                {
                  "type": "message",
                  "role": "assistant",
                  "content": [
                    {"type": "output_text", "text": "Checking "}
                  ]
                },
                {
                  "type": "message",
                  "role": "assistant",
                  "content": [
                    {"type": "output_text", "text": "now."}
                  ]
                },
                {
                  "type": "function_call",
                  "call_id": "call_123",
                  "name": "lookup",
                  "arguments": "{\\"query\\":\\"status\\"}"
                }
              ]
            }
            """
        )
        let client = try makeClient(
            recorder: recorder,
            result: response
        )
        let schema = """
        {
          "type": "object",
          "properties": {
            "query": {"type": "string"}
          },
          "required": ["query"],
          "additionalProperties": false
        }
        """

        let modelResponse = try await client.createResponse(
            PocketRootAgentModelRequest(
                instructions: "Use tools when needed.",
                input: .user("Check status"),
                tools: [
                    PocketRootAgentToolDefinition(
                        name: "lookup",
                        description: "Looks up status.",
                        parametersJSONSchema: schema
                    )
                ]
            )
        )

        XCTAssertEqual(
            modelResponse,
            PocketRootAgentModelResponse(
                id: "resp_123",
                outputText: "Checking now.",
                toolCalls: [
                    PocketRootAgentToolCall(
                        id: "call_123",
                        name: "lookup",
                        argumentsJSON: #"{"query":"status"}"#
                    )
                ]
            )
        )

        let requests = await recorder.requests()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-token"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        XCTAssertEqual(request.timeoutInterval, 12)

        let payload = try jsonObject(request.httpBody)
        XCTAssertEqual(payload["model"] as? String, "gpt-test")
        XCTAssertEqual(
            payload["instructions"] as? String,
            "Use tools when needed."
        )
        XCTAssertEqual(payload["input"] as? String, "Check status")
        XCTAssertEqual(payload["store"] as? Bool, true)
        XCTAssertNil(payload["previous_response_id"])

        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["type"] as? String, "function")
        XCTAssertEqual(tools[0]["name"] as? String, "lookup")
        XCTAssertEqual(tools[0]["description"] as? String, "Looks up status.")
        XCTAssertEqual(tools[0]["strict"] as? Bool, true)
        let parameters = try XCTUnwrap(
            tools[0]["parameters"] as? [String: Any]
        )
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
    }

    func testEncodesContinuationWithPreviousResponseAndToolOutputs() async throws {
        let recorder = OpenAIRequestRecorder()
        let client = try makeClient(
            recorder: recorder,
            result: try makeHTTPResult(
                statusCode: 200,
                body: """
                {
                  "id": "resp_2",
                  "status": "completed",
                  "output": [
                    {
                      "type": "message",
                      "content": [
                        {"type": "output_text", "text": "Done."}
                      ]
                    }
                  ]
                }
                """
            )
        )

        _ = try await client.createResponse(
            PocketRootAgentModelRequest(
                instructions: "Continue.",
                input: .toolOutputs([
                    PocketRootAgentToolOutput(
                        callID: "call_1",
                        output: #"{"ok":true}"#
                    ),
                    PocketRootAgentToolOutput(
                        callID: "call_2",
                        output: "finished"
                    )
                ]),
                tools: [],
                previousResponseID: "resp_1"
            )
        )

        let recordedRequests = await recorder.requests()
        let request = try XCTUnwrap(recordedRequests.first)
        let payload = try jsonObject(request.httpBody)
        XCTAssertEqual(payload["previous_response_id"] as? String, "resp_1")
        XCTAssertNil(payload["tools"])

        let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["type"] as? String, "function_call_output")
        XCTAssertEqual(input[0]["call_id"] as? String, "call_1")
        XCTAssertEqual(input[0]["output"] as? String, #"{"ok":true}"#)
        XCTAssertEqual(input[1]["call_id"] as? String, "call_2")
        XCTAssertEqual(input[1]["output"] as? String, "finished")
    }

    func testRejectsNonStrictToolSchemaBeforeNetworkRequest() async throws {
        let recorder = OpenAIRequestRecorder()
        let client = try makeClient(
            recorder: recorder,
            result: try makeHTTPResult(
                statusCode: 200,
                body: completedResponse()
            )
        )

        do {
            _ = try await client.createResponse(
                PocketRootAgentModelRequest(
                    instructions: "Test.",
                    input: .user("Test"),
                    tools: [
                        PocketRootAgentToolDefinition(
                            name: "unsafe",
                            description: "Missing strict constraints.",
                            parametersJSONSchema: """
                            {
                              "type": "object",
                              "properties": {
                                "value": {"type": "string"}
                              }
                            }
                            """
                        )
                    ]
                )
            )
            XCTFail("A non-strict schema must be rejected locally.")
        } catch let error as PocketRootOpenAIResponsesError {
            XCTAssertEqual(
                error,
                .invalidToolSchema(
                    tool: "unsafe",
                    reason: "$ must set additionalProperties to false."
                )
            )
        }
        let requests = await recorder.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testRejectsNullableAndMalformedObjectSchemasBeforeNetwork() async throws {
        let invalidSchemas: [(String, String)] = [
            (
                """
                {
                  "type": "object",
                  "properties": {
                    "nested": {
                      "type": ["object", "null"],
                      "properties": {}
                    }
                  },
                  "required": ["nested"],
                  "additionalProperties": false
                }
                """,
                "$.properties.nested must set additionalProperties to false."
            ),
            (
                """
                {
                  "type": "object",
                  "properties": [],
                  "required": [],
                  "additionalProperties": false
                }
                """,
                "$.properties must be an object."
            ),
            (
                """
                {
                  "type": "object",
                  "properties": {},
                  "required": "none",
                  "additionalProperties": false
                }
                """,
                "$.required must be a string array."
            )
        ]

        for (schema, expectedReason) in invalidSchemas {
            let recorder = OpenAIRequestRecorder()
            let client = try makeClient(
                recorder: recorder,
                result: try makeHTTPResult(
                    statusCode: 200,
                    body: completedResponse()
                )
            )
            do {
                _ = try await client.createResponse(
                    PocketRootAgentModelRequest(
                        instructions: "Test.",
                        input: .user("Test"),
                        tools: [
                            PocketRootAgentToolDefinition(
                                name: "strict_test",
                                description: "Tests strict schemas.",
                                parametersJSONSchema: schema
                            )
                        ]
                    )
                )
                XCTFail("Malformed strict schema must be rejected locally.")
            } catch let error as PocketRootOpenAIResponsesError {
                XCTAssertEqual(
                    error,
                    .invalidToolSchema(
                        tool: "strict_test",
                        reason: expectedReason
                    )
                )
            }
            let requests = await recorder.requests()
            XCTAssertEqual(requests.count, 0)
        }
    }

    func testMapsAPIErrorsWithoutIncludingCredential() async throws {
        let recorder = OpenAIRequestRecorder()
        let client = try makeClient(
            recorder: recorder,
            token: "do-not-leak",
            result: try makeHTTPResult(
                statusCode: 429,
                body: """
                {
                  "error": {
                    "message": "Credential do-not-leak reached a rate limit.",
                    "type": "rate_limit_error",
                    "code": "do-not-leak_rate_limit_exceeded"
                  }
                }
                """
            )
        )

        do {
            _ = try await client.createResponse(basicRequest())
            XCTFail("A non-success status must fail.")
        } catch let error as PocketRootOpenAIResponsesError {
            XCTAssertEqual(
                error,
                .api(
                    statusCode: 429,
                    code: "[REDACTED]_rate_limit_exceeded",
                    message: "Credential [REDACTED] reached a rate limit."
                )
            )
            XCTAssertFalse(error.localizedDescription.contains("do-not-leak"))
        }
    }

    func testCredentialFailureIsSanitizedAndSkipsNetwork() async throws {
        let recorder = OpenAIRequestRecorder()
        let unusedResult = try makeHTTPResult(
            statusCode: 200,
            body: completedResponse()
        )
        let client = try PocketRootOpenAIResponsesClient(
            configuration: configuration(),
            tokenProvider: PocketRootOpenAIBearerTokenProvider {
                throw SecretCredentialError(message: "secret-value")
            },
            httpClient: MockOpenAIHTTPClient { request, _ in
                await recorder.record(request)
                return unusedResult
            }
        )

        do {
            _ = try await client.createResponse(basicRequest())
            XCTFail("A credential loader failure must stop the request.")
        } catch let error as PocketRootOpenAIResponsesError {
            XCTAssertEqual(error, .credentialUnavailable)
            XCTAssertFalse(error.localizedDescription.contains("secret-value"))
        }
        let requests = await recorder.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testCancellationAfterNonCooperativeCredentialLoadSkipsNetwork() async throws {
        let tokenLoadStarted = expectation(
            description: "credential load started"
        )
        let tokenGate = OpenAITestAsyncGate()
        let recorder = OpenAIRequestRecorder()
        let unusedResult = try makeHTTPResult(
            statusCode: 200,
            body: completedResponse()
        )
        let client = try PocketRootOpenAIResponsesClient(
            configuration: configuration(),
            tokenProvider: PocketRootOpenAIBearerTokenProvider {
                tokenLoadStarted.fulfill()
                await tokenGate.wait()
                return "test-token"
            },
            httpClient: MockOpenAIHTTPClient { request, _ in
                await recorder.record(request)
                return unusedResult
            }
        )
        let requestTask = Task {
            try await client.createResponse(basicRequest())
        }
        await fulfillment(of: [tokenLoadStarted], timeout: 2)

        requestTask.cancel()
        await tokenGate.open()

        do {
            _ = try await requestTask.value
            XCTFail("A canceled request must not reach the HTTP client.")
        } catch is CancellationError {
            // Expected even though the credential provider ignored cancellation.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let requests = await recorder.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testCredentialURLCancellationPropagatesAsTaskCancellation() async throws {
        let recorder = OpenAIRequestRecorder()
        let unusedResult = try makeHTTPResult(
            statusCode: 200,
            body: completedResponse()
        )
        let client = try PocketRootOpenAIResponsesClient(
            configuration: configuration(),
            tokenProvider: PocketRootOpenAIBearerTokenProvider {
                throw URLError(.cancelled)
            },
            httpClient: MockOpenAIHTTPClient { request, _ in
                await recorder.record(request)
                return unusedResult
            }
        )

        do {
            _ = try await client.createResponse(basicRequest())
            XCTFail("Credential URL cancellation must remain cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let requests = await recorder.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testRejectsMalformedCredentials() async throws {
        for token in ["", "contains space", "contains\nnewline"] {
            let recorder = OpenAIRequestRecorder()
            let client = try makeClient(
                recorder: recorder,
                token: token,
                result: try makeHTTPResult(
                    statusCode: 200,
                    body: completedResponse()
                )
            )

            do {
                _ = try await client.createResponse(basicRequest())
                XCTFail("Malformed credential '\(token)' must be rejected.")
            } catch let error as PocketRootOpenAIResponsesError {
                XCTAssertEqual(error, .invalidCredential)
            }
            let requests = await recorder.requests()
            XCTAssertEqual(requests.count, 0)
        }
    }

    func testRejectsIncompleteAndMalformedResponses() async throws {
        let incompleteClient = try makeClient(
            recorder: OpenAIRequestRecorder(),
            result: try makeHTTPResult(
                statusCode: 200,
                body: """
                {
                  "id": "resp_incomplete",
                  "status": "incomplete",
                  "incomplete_details": {"reason": "max_output_tokens"},
                  "output": []
                }
                """
            )
        )
        do {
            _ = try await incompleteClient.createResponse(basicRequest())
            XCTFail("An incomplete response must not be treated as final.")
        } catch let error as PocketRootOpenAIResponsesError {
            XCTAssertEqual(
                error,
                .invalidResponse("max_output_tokens")
            )
        }

        let malformedClient = try makeClient(
            recorder: OpenAIRequestRecorder(),
            result: try makeHTTPResult(
                statusCode: 200,
                body: """
                {
                  "id": "resp_bad_call",
                  "status": "completed",
                  "output": [
                    {"type": "function_call", "name": "lookup"}
                  ]
                }
                """
            )
        )
        do {
            _ = try await malformedClient.createResponse(basicRequest())
            XCTFail("A malformed function call must be rejected.")
        } catch let error as PocketRootOpenAIResponsesError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    "a function_call item omitted call_id, name, or arguments."
                )
            )
        }

        let failedClient = try makeClient(
            recorder: OpenAIRequestRecorder(),
            token: "private-token",
            result: try makeHTTPResult(
                statusCode: 200,
                body: """
                {
                  "id": "resp_failed",
                  "status": "failed",
                  "error": {
                    "message": "Credential private-token was rejected.",
                    "code": "invalid_api_key"
                  },
                  "output": []
                }
                """
            )
        )
        do {
            _ = try await failedClient.createResponse(basicRequest())
            XCTFail("A failed response must not be treated as completed.")
        } catch let error as PocketRootOpenAIResponsesError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    "Credential [REDACTED] was rejected."
                )
            )
            XCTAssertFalse(error.localizedDescription.contains("private-token"))
        }
    }

    func testDecodesRefusalAsFinalText() async throws {
        let client = try makeClient(
            recorder: OpenAIRequestRecorder(),
            result: try makeHTTPResult(
                statusCode: 200,
                body: """
                {
                  "id": "resp_refusal",
                  "status": "completed",
                  "output": [
                    {
                      "type": "message",
                      "content": [
                        {
                          "type": "refusal",
                          "refusal": "I cannot help with that."
                        }
                      ]
                    }
                  ]
                }
                """
            )
        )

        let response = try await client.createResponse(basicRequest())

        XCTAssertEqual(response.id, "resp_refusal")
        XCTAssertEqual(response.outputText, "I cannot help with that.")
        XCTAssertEqual(response.toolCalls, [])
    }

    func testPropagatesResponseBodyLimitAndValidatesConfiguration() async throws {
        let client = try PocketRootOpenAIResponsesClient(
            configuration: configuration(),
            tokenProvider: tokenProvider(),
            httpClient: MockOpenAIHTTPClient { _, limit in
                throw PocketRootOpenAIResponsesError
                    .responseBodyLimitExceeded(limit)
            }
        )
        do {
            _ = try await client.createResponse(basicRequest())
            XCTFail("The response body limit must be preserved.")
        } catch let error as PocketRootOpenAIResponsesError {
            XCTAssertEqual(error, .responseBodyLimitExceeded(8_192))
        }

        XCTAssertThrowsError(
            try PocketRootOpenAIResponsesClient(
                configuration: PocketRootOpenAIResponsesConfiguration(
                    model: "gpt-test",
                    endpoint: URL(string: "http://example.com/v1/responses")!
                ),
                tokenProvider: tokenProvider()
            )
        ) { error in
            XCTAssertEqual(
                error as? PocketRootOpenAIResponsesError,
                .invalidConfiguration("endpoint must use HTTPS.")
            )
        }
        XCTAssertThrowsError(
            try PocketRootOpenAIResponsesClient(
                configuration: PocketRootOpenAIResponsesConfiguration(
                    model: " "
                ),
                tokenProvider: tokenProvider()
            )
        )

        let requestRecorder = OpenAIRequestRecorder()
        let requestLimitedUnusedResult = try makeHTTPResult(
            statusCode: 200,
            body: completedResponse()
        )
        let requestLimitedClient = try PocketRootOpenAIResponsesClient(
            configuration: PocketRootOpenAIResponsesConfiguration(
                model: "gpt-test",
                endpoint: URL(string: "https://example.com/v1/responses")!,
                maximumRequestBodyBytes: 1
            ),
            tokenProvider: tokenProvider(),
            httpClient: MockOpenAIHTTPClient { request, _ in
                await requestRecorder.record(request)
                return requestLimitedUnusedResult
            }
        )
        do {
            _ = try await requestLimitedClient.createResponse(basicRequest())
            XCTFail("An oversized request must fail before network I/O.")
        } catch let error as PocketRootOpenAIResponsesError {
            XCTAssertEqual(error, .requestBodyLimitExceeded(1))
        }
        let requestLimitedRequests = await requestRecorder.requests()
        XCTAssertEqual(requestLimitedRequests.count, 0)
    }

    private func makeClient(
        recorder: OpenAIRequestRecorder,
        token: String = "test-token",
        result: PocketRootOpenAIHTTPResult
    ) throws -> PocketRootOpenAIResponsesClient {
        try PocketRootOpenAIResponsesClient(
            configuration: configuration(),
            tokenProvider: tokenProvider(token),
            httpClient: MockOpenAIHTTPClient { request, limit in
                XCTAssertEqual(limit, 8_192)
                await recorder.record(request)
                return result
            }
        )
    }

    private func configuration() -> PocketRootOpenAIResponsesConfiguration {
        PocketRootOpenAIResponsesConfiguration(
            model: "gpt-test",
            endpoint: URL(string: "https://example.com/v1/responses")!,
            requestTimeout: 12,
            maximumResponseBodyBytes: 8_192
        )
    }

    private func tokenProvider(
        _ token: String = "test-token"
    ) -> PocketRootOpenAIBearerTokenProvider {
        PocketRootOpenAIBearerTokenProvider { token }
    }

    private func basicRequest() -> PocketRootAgentModelRequest {
        PocketRootAgentModelRequest(
            instructions: "Test.",
            input: .user("Hello"),
            tools: []
        )
    }

    private func completedResponse() -> String {
        """
        {
          "id": "resp_done",
          "status": "completed",
          "output": [
            {
              "type": "message",
              "content": [
                {"type": "output_text", "text": "Done."}
              ]
            }
          ]
        }
        """
    }

    private func makeHTTPResult(
        statusCode: Int,
        body: String
    ) throws -> PocketRootOpenAIHTTPResult {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/v1/responses")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return PocketRootOpenAIHTTPResult(
            data: Data(body.utf8),
            response: response
        )
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}

@available(macOS 13.0, *)
private struct MockOpenAIHTTPClient: PocketRootOpenAIHTTPClient {
    let handler: @Sendable (
        URLRequest,
        Int
    ) async throws -> PocketRootOpenAIHTTPResult

    init(
        handler: @escaping @Sendable (
            URLRequest,
            Int
        ) async throws -> PocketRootOpenAIHTTPResult
    ) {
        self.handler = handler
    }

    func send(
        _ request: URLRequest,
        maximumResponseBodyBytes: Int
    ) async throws -> PocketRootOpenAIHTTPResult {
        try await handler(request, maximumResponseBodyBytes)
    }
}

@available(macOS 13.0, *)
private actor OpenAIRequestRecorder {
    private var recordedRequests: [URLRequest] = []

    func record(_ request: URLRequest) {
        recordedRequests.append(request)
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }
}

private actor OpenAITestAsyncGate {
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
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private struct SecretCredentialError: Error {
    let message: String
}
