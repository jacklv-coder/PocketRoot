# 轻量 Agent Loop

[简体中文](Agent.md) | [English](en/Agent.md) | [文档中心](README.md)

`PocketRootAgent` 是位于 `PocketRootCore` 之上的可选 Swift Package 产品。它负责模型回合与
本地工具之间的有界调度，不在 Linux RootFS 中安装 Codex CLI、Node.js 或 npm。

## 当前边界

本模块当前提供：

- provider-agnostic `PocketRootAgentModelClient`；
- 原生 `PocketRootOpenAIResponsesClient`，把 loop 映射到 OpenAI Responses API；
- 宿主异步提供 bearer credential 的 `PocketRootOpenAIBearerTokenProvider`；
- `user input → model response → tool calls → tool outputs → model` 循环；
- 同一个 runner 最多一个进行中的 run；
- model turn、tool call、用户输入、模型文本、tool arguments 和 tool output 上限；
- model 生成的 response/call ID 字节上限与 tool name 格式/长度校验；
- response ID 与 tool call ID 防重放；
- 整批 tool call 预检，避免后一个畸形 call 让前一个先产生副作用；
- unknown tool 与普通 tool error 的结构化失败回传；
- Swift Task cancellation 传播。

本模块当前不提供：

- credential 存储或登录 UI；
- 默认 shell tool；
- 自动批准模型产生的命令；
- 流式 UI、会话持久化、多 Agent、handoff、MCP 或 tracing。

其余能力按路线图拆成独立 PR。特别是 Linux command tool 必须先定义审批、工作目录、超时、
输出和允许命令策略，不能把 `PocketRootSystem.execute` 无条件暴露给模型。

## 核心协议

模型 client 接收：

- 固定 instructions；
- 首轮 user input，或后续 `PocketRootAgentToolOutput`；
- tool definitions；
- 上一轮 response ID。

模型返回：

- 非空 response ID；
- 最终文本；或
- 带唯一 call ID、tool name 与 JSON object arguments 的 tool calls。

Runner 只在没有 tool calls 时接受最终文本。若最后一个允许回合仍请求工具，runner 会在
执行该工具前返回 `maximumTurnsExceeded`，避免产生一个永远无法交回模型的副作用。

## 默认资源边界

| 边界 | 默认值 |
| --- | --- |
| model turns | 8 |
| tool calls | 16 |
| user input | 64 KiB |
| model text | 256 KiB |
| 单个 response/call ID | 256 bytes |
| tool name | 64 ASCII bytes |
| 单个 tool arguments | 64 KiB |
| 单个 tool output | 64 KiB |
| OpenAI request body | 2 MiB |
| OpenAI response body | 2 MiB |

应用可以通过 `PocketRootAgentConfiguration` 收紧这些值。配置必须在 runner 初始化时通过
验证；OpenAI transport 的 request/response body 上限由
`PocketRootOpenAIResponsesConfiguration` 独立配置。超过边界会使本次 run 失败，不会静默截断。

## OpenAI Responses transport

`PocketRootOpenAIResponsesClient` 是非流式 `PocketRootAgentModelClient` 实现。模型 ID 由
应用显式传入，library 不固定或自动切换“最新模型”。transport 会：

- 使用 HTTPS `POST`，拒绝 URL 中的 credential、query 与 fragment，并禁用自动重定向；
- 把首轮文本和后续 `function_call_output` 编码为 Responses API `input`；
- 把 `function_call.call_id/name/arguments` 映射为本地 tool call；
- 通过 `previous_response_id` 续接工具回合；
- 强制 `strict: true`，并在网络请求前检查每层 object schema 的
  `additionalProperties: false` 与完整 `required`；
- 流式读取 HTTP body，在超过配置上限时取消读取；
- 对 credential loader error 做脱敏，不把 bearer token 写进错误或日志；
- 不自动 retry，避免调用方把不确定结果误当成同一次请求。

最小组合：

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

生产移动 App 不应嵌入或下发长期 OpenAI API key。推荐让自有 backend 持有 OpenAI key，
移动端 endpoint 指向兼容的 backend proxy，并由 token provider 提供 App 会话 credential。
默认 `api.openai.com` endpoint 只让宿主显式选择直连方式；library 不读取环境变量、Keychain
或 RootFS。

当前 transport 显式发送 `store: true`，因为 agent 的工具续接依赖
`previous_response_id`。OpenAI Responses 默认保留策略因此适用。需要 `store: false` 或
Zero Data Retention 的应用不能使用这一状态模式；后续必须实现完整 response output（包括
reasoning item）的本地历史回放后再开放该选项。

## 安全原则

1. 模型输出是不可信输入。
2. tool schema 只描述参数形状，不等于动作授权。
3. 有副作用的工具必须在 handler 内再次执行授权检查。
4. 一个 response 内的全部 calls 先验证、后顺序执行。
5. call ID 不允许在同一 run 中重复，避免重放副作用。
6. 同一个 runner 不并发运行，避免共享模型状态或 Linux runtime 交错。
7. 长期 API key 不进入移动 App、RootFS 或仓库；生产请求通过自有 backend。
8. Responses 的 server-side state/data retention 必须由产品明确接受。

## 下一步

1. 增加带审批与命令策略的 `PocketRootSystem` tool adapter。
2. 发布并固定 soft-shutdown IshEmbed 制品。
3. 在 Demo/App 中组合 agent、prepared runtime、状态与取消 UI。
4. 后续独立设计 streaming、`store: false` 历史回放与会话持久化。

动态顺序和完成状态以[路线图](Roadmap.md)为准。
