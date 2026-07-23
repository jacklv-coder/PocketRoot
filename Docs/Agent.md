# 轻量 Agent Loop

[简体中文](Agent.md) | [English](en/Agent.md) | [文档中心](README.md)

`PocketRootAgent` 是位于 `PocketRootCore` 之上的可选 Swift Package 产品。它负责模型回合与
本地工具之间的有界调度，不在 Linux RootFS 中安装 Codex CLI、Node.js 或 npm。

## 当前边界

本模块当前提供：

- provider-agnostic `PocketRootAgentModelClient`；
- `user input → model response → tool calls → tool outputs → model` 循环；
- 同一个 runner 最多一个进行中的 run；
- model turn、tool call、用户输入、模型文本、tool arguments 和 tool output 上限；
- model 生成的 response/call ID 字节上限与 tool name 格式/长度校验；
- response ID 与 tool call ID 防重放；
- 整批 tool call 预检，避免后一个畸形 call 让前一个先产生副作用；
- unknown tool 与普通 tool error 的结构化失败回传；
- Swift Task cancellation 传播。

本模块当前不提供：

- OpenAI 或其他 provider 的网络 transport；
- API key 存储；
- 默认 shell tool；
- 自动批准模型产生的命令；
- 流式 UI、会话持久化、多 Agent、handoff、MCP 或 tracing。

这些能力按路线图拆成独立 PR。特别是 Linux command tool 必须先定义审批、工作目录、超时、
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

应用可以通过 `PocketRootAgentConfiguration` 收紧这些值。配置必须在 runner 初始化时通过
验证；模型或工具输出超过边界会使本次 run 失败，不会静默截断。

## 安全原则

1. 模型输出是不可信输入。
2. tool schema 只描述参数形状，不等于动作授权。
3. 有副作用的工具必须在 handler 内再次执行授权检查。
4. 一个 response 内的全部 calls 先验证、后顺序执行。
5. call ID 不允许在同一 run 中重复，避免重放副作用。
6. 同一个 runner 不并发运行，避免共享模型状态或 Linux runtime 交错。
7. API key 不进入 RootFS，也不提交到仓库。

## 下一步

1. 实现 OpenAI Responses API transport，把 `function_call` 映射为
   `PocketRootAgentToolCall`，把本地结果映射为 `function_call_output`。
2. 定义宿主负责的 credential provider，不在 App 二进制中硬编码长期 API key。
3. 增加带审批与命令策略的 `PocketRootSystem` tool adapter。
4. 在 Demo/App 中接入流式状态与取消 UI。

动态顺序和完成状态以[路线图](Roadmap.md)为准。
