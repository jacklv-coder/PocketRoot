# 轻量 Agent Loop

[简体中文](Agent.md) | [English](en/Agent.md) | [文档中心](README.md)

`PocketRootAgent` 是位于 `PocketRootCore` 之上的可选 Swift Package 产品。它负责模型回合与
本地工具之间的有界调度，不在 Linux RootFS 中安装 Codex CLI。Node.js/npm 可作为应用
显式审核和安装的通用 guest package，但不是此 agent loop 的必需 runtime。

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
- Swift Task cancellation 传播；
- 显式 opt-in `PocketRootAgentRuntimeTools` 产品，提供带宿主策略、逐次审批和资源边界的
  `run_linux_command` adapter；
- 工具级同步 preflight 纳入整批 call 预检。

本模块当前不提供：

- credential 存储或登录 UI；
- 自动批准模型产生的命令；
- 流式 UI、会话持久化、多 Agent、handoff、MCP 或 tracing。

命令工具不是默认能力：应用必须显式依赖 runtime-tools 产品、提供 allow/deny policy，
并为每次已获 policy 允许的请求实现人工审批。library 没有“自动同意”实现。

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
| command text | 4 KiB |
| command timeout | 30 seconds |
| command environment | 16 entries / 8 KiB |
| returned stdout / stderr | each 16 KiB |
| encoded command result | 60 KiB |

应用可以通过 `PocketRootAgentConfiguration` 收紧这些值。配置必须在 runner 初始化时通过
验证；OpenAI transport 的 request/response body 上限由
`PocketRootOpenAIResponsesConfiguration` 独立配置。超过边界会使本次 run 失败，不会静默截断。
命令工具的 stdout/stderr 是例外：它会显式返回 `truncated` 标记，以保证编码后的 tool
output 留在单独配置的上限内。

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

## 审批保护的 Linux 命令工具

`PocketRootAgentRuntimeTools` 单独依赖 `PocketRootAgent` 与 `PocketRootCore`，不进入默认
伞形产品。`PocketRootLinuxCommandTool` 的执行顺序固定为：

1. 严格解码参数，拒绝未知字段、控制字符、重复或未允许的环境变量；
2. 规范化绝对工作目录，并执行 timeout、cwd、environment、stderr merge 和字节上限；
3. 对同一 model response 的全部工具执行同步 preflight；
4. 调用 App 提供的 command policy；
5. policy 允许后，把最终且不会再修改的 `PocketRootLinuxCommand` 交给 App 逐次审批；
6. 只有 `.approved` 才调用 `PocketRootSystem.execute`。

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

policy 与审批是两个独立门禁：policy 拒绝时不会打扰用户；policy 允许不代表已获审批。
`exactCommands` 只做完整字符串匹配，自定义 policy 必须把 shell 字符串视为不可信输入。
工作目录 root 是请求级词法限制，不是 guest 沙箱；命令仍由 `/bin/sh -lc` 执行，可以访问
guest 中该用户有权访问的其他路径。

stdout/stderr 先按工具配额截断，再以 UTF-8 或 binary-safe Base64 放入有界 JSON。
更底层的 native 收集上限仍由 `PocketRootIshRuntimeConfiguration` 决定；工具配额只限制交给
模型的结果，不会把固定 native transport 尚未解决的阻塞或 inbox 背压变成硬界限。
Swift Task 在审批后、执行前取消时不会启动命令；命令已进入 native `execute()` 后，
取消会终止 session，并在确认 guest `EXITED` 后返回。无法确认清理时 runtime 失败关闭。
取消不能撤销已经发生的文件、网络或其他副作用。

## 安全原则

1. 模型输出是不可信输入。
2. tool schema 只描述参数形状，不等于动作授权。
3. 有副作用的工具必须在 handler 内再次执行 policy 与逐次审批。
4. 一个 response 内的全部 calls 先验证、后顺序执行。
5. call ID 不允许在同一 run 中重复，避免重放副作用。
6. 同一个 runner 不并发运行，避免共享模型状态或 Linux runtime 交错。
7. 长期 API key 不进入移动 App、RootFS 或仓库；生产请求通过自有 backend。
8. Responses 的 server-side state/data retention 必须由产品明确接受。

## 下一步

原生 Agent Loop 与进一步 App 组合当前按产品决定暂停，不属于本轮 runtime pin。
恢复后再独立设计 agent UI、streaming、`store: false` 历史回放与会话持久化。

动态顺序和完成状态以[路线图](Roadmap.md)为准。
