# Lightweight Agent Loop

[简体中文](../Agent.md) | [English](Agent.md) | [Documentation](README.md)

`PocketRootAgent` is an optional Swift Package product above `PocketRootCore`.
It bounds orchestration between model turns and local tools. It does not install
Codex CLI, Node.js, or npm inside the Linux RootFS.

## Current boundary

The module currently provides:

- a provider-agnostic `PocketRootAgentModelClient`;
- a `user input → model response → tool calls → tool outputs → model` loop;
- at most one active run per runner;
- model-turn, tool-call, user-input, model-text, tool-argument, and tool-output limits;
- response-ID and tool-call-ID replay rejection;
- whole-batch tool-call validation before the first side effect;
- structured feedback for unknown tools and ordinary tool failures;
- Swift Task cancellation propagation.

It does not currently provide:

- an OpenAI or other provider network transport;
- API-key storage;
- a default shell tool;
- automatic approval of model-generated commands;
- streaming UI, durable conversations, multi-agent handoffs, MCP, or tracing.

Those capabilities are split into later pull requests. A Linux command tool must
define approval, working-directory, timeout, output, and command policies before
it exposes `PocketRootSystem.execute` to a model.

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
| Each tool's arguments | 64 KiB |
| Each tool's output | 64 KiB |

Applications can tighten these values through
`PocketRootAgentConfiguration`. Runner initialization validates the
configuration. Oversized model or tool data fails the run rather than being
silently truncated.

## Security principles

1. Model output is untrusted input.
2. A tool schema describes argument shape, not authorization.
3. Side-effecting handlers must perform their own authorization check.
4. Every call in a response is validated before calls execute sequentially.
5. A call ID cannot repeat within one run.
6. A runner does not admit concurrent runs.
7. API keys do not enter the RootFS or repository.

## Next work

1. Add an OpenAI Responses API transport mapping `function_call` to
   `PocketRootAgentToolCall` and local results to `function_call_output`.
2. Define a host-owned credential provider without embedding a long-lived API
   key in the App binary.
3. Add an approval- and policy-gated `PocketRootSystem` tool adapter.
4. Integrate streaming state and cancellation UI in the Demo/App.

See the [roadmap](Roadmap.md) for dynamic ordering and completion.
