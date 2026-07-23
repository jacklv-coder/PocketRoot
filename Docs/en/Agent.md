# Lightweight Agent Loop

[简体中文](../Agent.md) | [English](Agent.md) | [Documentation](README.md)

`PocketRootAgent` is an optional Swift Package product above `PocketRootCore`.
It bounds orchestration between model turns and local tools. It does not install
Codex CLI, Node.js, or npm inside the Linux RootFS.

## Current boundary

The module currently provides:

- a provider-agnostic `PocketRootAgentModelClient`;
- a native `PocketRootOpenAIResponsesClient` mapping the loop to the OpenAI Responses API;
- host-loaded bearer credentials through `PocketRootOpenAIBearerTokenProvider`;
- a `user input → model response → tool calls → tool outputs → model` loop;
- at most one active run per runner;
- model-turn, tool-call, user-input, model-text, tool-argument, and tool-output limits;
- byte limits for model-generated response/call IDs plus tool-name format and length validation;
- response-ID and tool-call-ID replay rejection;
- whole-batch tool-call validation before the first side effect;
- structured feedback for unknown tools and ordinary tool failures;
- Swift Task cancellation propagation;
- an explicit opt-in `PocketRootAgentRuntimeTools` product with host policy,
  per-call approval, and bounded `run_linux_command`;
- tool-specific synchronous preflight as part of whole-batch validation.

It does not currently provide:

- credential storage or sign-in UI;
- automatic approval of model-generated commands;
- streaming UI, durable conversations, multi-agent handoffs, MCP, or tracing.

The command tool is not a default capability. An application must explicitly
select the runtime-tools product, provide an allow/deny policy, and implement
human approval for every policy-allowed request. The library has no automatic
approval implementation.

## Core protocol

The model client receives fixed instructions, either initial user input or
subsequent `PocketRootAgentToolOutput` values, tool definitions, and the prior
response ID.

The model returns a nonempty response ID and either final text or tool calls
with unique call IDs, tool names, and JSON-object arguments.

The runner accepts final text only when there are no tool calls. If the last
available turn requests a tool, the runner returns `maximumTurnsExceeded`
before executing it, avoiding a side effect whose result can never be returned
to the model.

## Default resource bounds

| Boundary | Default |
| --- | --- |
| Model turns | 8 |
| Tool calls | 16 |
| User input | 64 KiB |
| Model text | 256 KiB |
| Each response/call ID | 256 bytes |
| Tool name | 64 ASCII bytes |
| Each tool's arguments | 64 KiB |
| Each tool's output | 64 KiB |
| OpenAI request body | 2 MiB |
| OpenAI response body | 2 MiB |
| Command text | 4 KiB |
| Command timeout | 30 seconds |
| Command environment | 16 entries / 8 KiB |
| Returned stdout / stderr | 16 KiB each |
| Encoded command result | 60 KiB |

Applications can tighten these values through
`PocketRootAgentConfiguration`. Runner initialization validates the
configuration. `PocketRootOpenAIResponsesConfiguration` independently controls
transport request/response body limits. Oversized data fails the run rather
than being silently truncated.
Command stdout/stderr is the explicit exception: the command tool returns a
`truncated` marker to keep its encoded output inside its separate budget.

## OpenAI Responses transport

`PocketRootOpenAIResponsesClient` is a non-streaming
`PocketRootAgentModelClient`. The application explicitly selects a model ID;
the library neither pins nor silently changes a "latest" model. The transport:

- sends HTTPS POST requests, rejects endpoint credentials/query/fragment, and disables redirects;
- encodes initial text and subsequent `function_call_output` items;
- maps `function_call.call_id/name/arguments` into local calls;
- continues tool turns with `previous_response_id`;
- forces `strict: true` and preflights every object schema for
  `additionalProperties: false` and complete `required` fields;
- reads the HTTP body incrementally and stops at the configured limit;
- sanitizes credential-loader failures and never logs bearer tokens;
- performs no automatic retry.

```swift
import PocketRootAgent

let modelClient = try PocketRootOpenAIResponsesClient(
    configuration: PocketRootOpenAIResponsesConfiguration(
        model: "your-reviewed-model-id",
        endpoint: URL(string: "https://your-backend.example/v1/responses")!
    ),
    tokenProvider: PocketRootOpenAIBearerTokenProvider {
        try await appSession.loadBearerToken()
    }
)

let runner = try PocketRootAgentRunner(
    modelClient: modelClient,
    configuration: PocketRootAgentConfiguration(
        instructions: "Follow the app's tool and approval policy."
    )
)
```

Do not embed or deliver a long-lived OpenAI API key in a production mobile
application. Keep it on an application backend, point the mobile endpoint at a
compatible backend proxy, and let the token provider load an app-session
credential. The default `api.openai.com` endpoint only supports an explicit
host choice to connect directly; the library reads no environment variable,
Keychain item, or RootFS file.

The transport explicitly sends `store: true` because tool continuation uses
`previous_response_id`; OpenAI Responses retention therefore applies.
Applications requiring `store: false` or Zero Data Retention cannot use this
state mode. Supporting that policy requires a later local-history implementation
that replays every response output item, including reasoning items.

## Approval-gated Linux command tool

`PocketRootAgentRuntimeTools` separately depends on `PocketRootAgent` and
`PocketRootCore`; it is not part of the safe umbrella.
`PocketRootLinuxCommandTool` always:

1. strictly decodes arguments and rejects unknown fields, control characters,
   duplicate variables, and variables outside the host allowlist;
2. normalizes the absolute working directory and enforces timeout, cwd,
   environment, stderr-merge, and byte limits;
3. synchronously preflights every tool in the same model response;
4. applies the application command policy;
5. passes the final immutable `PocketRootLinuxCommand` to per-call application approval;
6. invokes `PocketRootSystem.execute` only after `.approved`.

```swift
import PocketRootAgent
import PocketRootAgentRuntimeTools

let commandTool = try PocketRootLinuxCommandTool(
    executor: prepared.system,
    configuration: PocketRootLinuxCommandToolConfiguration(
        defaultWorkingDirectory: "/root",
        allowedWorkingDirectoryRoots: ["/root"],
        allowedEnvironmentNames: ["LANG"],
        maximumTimeoutSeconds: 15
    ),
    policy: .exactCommands(["uname -m", "pwd"]),
    approval: PocketRootLinuxCommandApproval { command in
        await approvalPresenter.request(command)
            ? .approved
            : .denied(reason: "The user denied this command.")
    }
)

let runner = try PocketRootAgentRunner(
    modelClient: modelClient,
    configuration: agentConfiguration,
    tools: [commandTool.agentTool]
)
```

Policy and approval are separate gates: a policy rejection does not interrupt
the user, while policy allowance is not approval. `exactCommands` performs
whole-string equality only. Custom policies must treat shell text as untrusted
input. A working-directory root is a lexical request constraint, not a guest
sandbox; `/bin/sh -lc` commands retain every path permission of the guest user.

The tool truncates stdout/stderr to its budgets, then emits bounded JSON using
UTF-8 or binary-safe Base64. Native collection limits still come from
`PocketRootIshRuntimeConfiguration`; tool limits bound model-visible results
but do not turn the pinned transport's blocking or inbox backpressure gaps into
hard limits. Cancellation after approval but before execution skips the
command. Once the currently non-cancellable native `execute()` has started,
cancellation can suppress its successful result but cannot undo side effects.

## Security principles

1. Model output is untrusted input.
2. A tool schema describes argument shape, not authorization.
3. Side-effecting handlers must perform their own policy and per-call approval.
4. Every call in a response is validated before calls execute sequentially.
5. A call ID cannot repeat within one run.
6. A runner does not admit concurrent runs.
7. Long-lived API keys do not enter the mobile App, RootFS, or repository; production requests use an application backend.
8. The product must explicitly accept Responses server-side state and retention.

## Next work

1. Release and pin the soft-shutdown IshEmbed artifact.
2. Compose the agent, prepared runtime, approval, state, and cancellation UI in the Demo/App.
3. Design streaming, `store: false` history replay, and durable conversations separately.

See the [roadmap](Roadmap.md) for dynamic ordering and completion.
