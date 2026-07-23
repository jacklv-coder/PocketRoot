# PocketRoot 路线图

[简体中文](Roadmap.md) | [English](en/Roadmap.md) | [文档中心](README.md)

本文是 PocketRoot **动态完成状态、工程门禁和下一步顺序的唯一事实源**。产品目标见[产品规划](ProductPlan.md)，固定 revision/hash 见[上游依赖清单](UpstreamDependencies.md)。

状态定义：

- **已通过**：当前验收证据满足该阶段要求，后续变更仍需回归。
- **进行中**：已有实现，但验收尚未闭环。
- **未开始**：尚无可依赖实现。
- **阻塞**：需要外部资源、上游修改、硬件、法律或产品决定。

## 当前执行序列

1. 已合并 provider-agnostic `PocketRootAgent` 有界 loop。
2. 完成 OpenAI Responses API transport 与宿主 credential contract。
3. 完成带审批、命令策略、超时和输出边界的 Linux command tool。
4. 当前：发布并固定 soft-shutdown IshEmbed 制品。
5. 把 agent、prepared runtime 和 Simulator UI 组合进 Demo/App。
6. 有物理 iPad 后补签名设备 smoke；该硬件门禁不阻塞前五项。

## 里程碑 1：工程基础

状态：**已通过**。

完成内容：

- Swift Package 模块边界；
- public runtime、command、session 和 terminal API 基础；
- placeholder runtime 与 terminal behavior；
- 纯 UIKit Demo，包含四个 tab；
- XcodeGen 工程生成和脚本；
- 文档、测试与 GitHub Actions；
- package、Demo、tests 和 CI 统一 iOS 18.0；
- macOS host tests；
- 固定 RootFS CI 校验；
- generic Simulator Demo build；
- 完整实验 runtime 的 arm64 最终链接。

工程基线：

| 项目 | 要求 |
| --- | --- |
| Xcode | 16.0+ 与 iOS 18 SDK |
| Swift Package | Swift 5.10+ |
| Deployment target | iOS 18.0 |
| Xcode project source | `project.yml` |
| Git generated project | 不提交 |

## 里程碑 2：ARM64 Linux 一次性命令

状态：**实验性，进行中**。

### 已完成的可行性基础

- 审核 `jacklv-coder/ish-arm64-pkg` 与 parent repository；
- 固定完整 package revision 和 nested iSH gitlink；
- 独立验证 XCFramework 与 RootFS hash；
- 建立 opt-in `PocketRootIshRuntime`；
- 建立 opt-in `PocketRootIshRuntimeIntegration`；
- 实现 process ownership、serial native execution 和 lifecycle reentrancy protection；
- 实现正 timeout、bounded read wait、Swift stdout/stderr 结果 limits；
- 实现 cwd、environment、stderr merge、exit 与 signal 映射；
- 实现 RootFS manifest、no-follow snapshot、安全 gzip/ustar、fakefs validation；
- 实现 versioned install、reuse、corruption replacement、rollback 和 interrupted promotion recovery；
- 对精确 v0.3.3 release archive 完成真实资产测试；
- 对 arm64 Simulator 和 unsigned device 完成完整依赖图最终链接；
- 在 iOS 18.2 arm64 Simulator boot 固定 fakefs；
- repository native smoke 通过 13 项 prepare、boot、guest、command、recovery 与 shutdown 检查。
- 在签名 iPhone 17 Pro（iOS 26.1）通过同一套 13 项 native smoke，并验证开发签名 entitlement 与 `_exit(0)` 进程退出。

这些证据建立了当前 Simulator 与单一 iPhone 的一次性命令路径，不覆盖 iPad、完整真机生命周期、最低 Xcode 16、PTY 或公开发行。

### 当前门禁

| 门禁 | 状态 | 退出条件 |
| --- | --- | --- |
| iOS 18 基线 | 已通过 | 持续保持 package、Demo、tests、CI 一致 |
| 不可变 IshEmbed revision | 已通过 | 只通过完整供应链更新流程变更 |
| 一次性命令 adapter | 已通过 | 保持 lifecycle、timeout、output-limit coverage |
| 原生 transport 背压 | 进行中 | 发布并接入具有 protocol/session/stdin/log 有界队列的新制品，再完成持续输出与内存峰值测试 |
| 原生 control path 端到端时间界限 | 进行中 | 发布并接入 nonblocking writer/有界控制操作，覆盖 spawn、terminate、close 阻塞回归 |
| iOS 18 Simulator 原生行为 | 已通过 | runtime/RootFS 变更时重跑 13 项 smoke |
| RootFS 安全安装与恢复 | 已通过 | 保持真实资产、snapshot、rollback、recovery coverage；补 ENOSPC |
| RootFS/runtime composition | 已通过 | 保持 caller-controlled、no-download、no-auto-boot |
| 默认 post-boot identity gate | 已通过 | `aarch64`、Alpine identity、可选 version 与 command context 通过后才 ready；保持失败占用槽位回归 |
| Demo 真实 runtime 注入 | 未开始 | 一个 prepared system 注入 System/Commands/Diagnostics，不打包未审查 RootFS |
| 进程安全 soft shutdown | 进行中 | fork 源码修复已合并；仍需新 XCFramework、checksum、PocketRoot pin 与生命周期重审 |
| 签名 iPhone | 已通过 | iPhone 17 Pro / iOS 26.1 / Xcode 26.1.1 的 13 项 signed smoke；runtime/RootFS/签名变化时重跑 |
| 签名 iPad | 阻塞 | physical boot 与 command smoke |
| 最低 Xcode 16 原生兼容 | 未开始 | 使用 Xcode 16 重跑 final-link 和 native behavior |
| App lifecycle 与内存 | 未开始 | foreground/background、jetsam、failure injection、persistence |
| RootFS ENOSPC/掉电 | 未开始 | storage pressure 和 transaction fault matrix |
| License-reviewed RootFS | 阻塞 | license、NOTICE、对应源码和 SBOM 完整 |
| App Store 2.5.2 | 阻塞 | guest download/execute policy 有书面结论 |

### 剩余 runtime 执行顺序

1. **发布关闭修复**
   上游 soft-shutdown 与 root `/proc` 修复已合并；发布新 XCFramework，更新 PocketRoot pin 并重跑生命周期审查。

2. **最低工具链**
   使用声明的 Xcode 16 重跑完整 final-link、RootFS install 和 native smoke。

3. **Demo 注入**
   在 command tool 完成后，把同一个 prepared system 注入 Agent、System、Commands 与 Diagnostics，不把 RootFS 放进默认 target。

4. **故障与资源硬化**
   增加 Task cancellation、ENOSPC、power-loss、storage pressure、long output 与 memory peak。

5. **iPad 真机基线**
   有签名 iPad 后重跑 prepare、boot、guest identity、streams、timeout、limit 和 failure recovery，并记录 Xcode/iPadOS/device/entitlement。

完成上述闭环后，才能把“一次性命令”提升到 Developer Preview 候选。

## 里程碑 3：上层轻量 Agent

状态：**进行中**。

### 已完成

- 新增显式 opt-in `PocketRootAgent` 产品，不进入 `PocketRootCore` 或默认伞形产品。
- 实现 provider-agnostic model client、非流式 tool loop 与上一 response ID 续接。
- 限制 turn、tool call、用户输入、模型文本、tool arguments 和 tool output。
- 拒绝重复 response/call ID；完整预检一批 calls 后再顺序执行。
- unknown tool 与普通 tool error 作为结构化结果交回模型。
- 同一 runner 拒绝并发 run，并传播 Swift Task cancellation。
- 增加原生 OpenAI Responses transport，覆盖首轮、tool output 续接、文本与 function call 解码。
- 增加宿主异步 bearer credential contract；loader 失败脱敏，credential 不进入 RootFS 或日志。
- 强制 strict function schema 预检，限制 request/response body，并禁用 HTTP 重定向。
- 新增显式 opt-in `PocketRootAgentRuntimeTools`，通过结构预检、宿主 allow/deny policy 与逐次审批后才执行命令。
- 限制 command、cwd、environment、timeout 与 model-visible streams；binary output 使用 Base64。
- 把工具级同步 preflight 纳入 runner 整批预检，并覆盖 policy、approval、cancellation 与 no-side-effect 路径。

### 门禁

| 门禁 | 状态 | 退出条件 |
| --- | --- | --- |
| 有界 loop 核心 | 已通过 | package tests 与 strict concurrency 持续通过 |
| OpenAI transport | 已通过 | 保持 Responses request/response/function-call、严格 schema、错误与 body limit 测试 |
| Credential contract | 已通过 | 生产由 backend 持有长期 OpenAI key；移动宿主只按需提供 App session bearer credential |
| Linux command tool | 已通过 | 保持审批、allow/deny policy、cwd、timeout、output、整批 preflight 与 cancellation tests |
| Demo/App 接入 | 未开始 | 明确状态、工具确认、取消、错误与最终文本 UI |
| 会话持久化/streaming | 未开始 | 数据保留策略、恢复、增量事件与资源上限 |

详细设计见[轻量 Agent Loop](Agent.md)。这个里程碑不改变 `PocketRootCore`
边界，也不要求在 RootFS 中安装 Codex CLI。

## 里程碑 4：交互式终端

状态：**未开始**。

按顺序实现：

1. public `PocketRootSystem` interactive session entry point；
2. process-wide live session registry；
3. bounded native PTY reads；
4. stdin write 与 close；
5. stdout/stderr/exit event；
6. terminal size 与 resize；
7. signal、EOF 与 cancellation；
8. close idempotency；
9. close-all-before-shutdown；
10. physical-device lifecycle tests；
11. 固定 SwiftTerm revision；
12. `TerminalBridge` 与 UIKit integration；
13. accessibility、keyboard 和 iPad layout。

在 session 指针所有权、read pump 取消和 close 顺序证明安全前，不使用上游高层 `IshTerminal` wrapper，也不加入 SwiftTerm。

验收：

- 一个 session 的生命周期可预测；
- background/foreground 不丢失 ownership；
- 关闭时没有 use-after-free 或无限 read；
- shutdown 不越过任何 live session；
- iPhone/iPad keyboard、resize、VoiceOver 可用；
- timeout/limit/cancellation 错误可恢复。

## 里程碑 5：硬化与发行候选

状态：**未开始 / 受阻塞门禁约束**。

工程：

- runtime failure recovery；
- RootFS migration 与 user data policy；
- performance、memory、battery benchmark；
- long-running workload；
- storage pressure 与 jetsam；
- dependency rebuild reproducibility；
- security 与 sandbox review；
- localization 与 accessibility；
- telemetry/privacy policy。

合规：

- PocketRoot 顶层 license；
- upstream LICENSE/NOTICE；
- corresponding source；
- machine-readable SBOM；
- artifact provenance；
- App Store 2.5.2；
- privacy manifest；
- release notes 与 known limitations。

全部阻塞发行项有明确处置后，才可以定义 Beta 或 Distribution Candidate。

## 每阶段共同要求

- 修改中英文文档；
- 更新变更日志；
- 固定依赖与 hash；
- 根据[测试矩阵](Testing.md)运行最小门禁；
- 不提交 RootFS 或未审查二进制；
- 不把 link success 描述成 runtime success；
- 不把 Simulator success 描述成 physical-device support；
- 不把技术验证描述成法律或 App Review 结论。

## 不属于 PocketRootCore 的范围

Agent、浏览器自动化、MCP、云端编排和业务工作流不进入
`PocketRootCore`。轻量 agent loop 位于显式 opt-in 的 `PocketRootAgent`，并通过稳定
command/session API 与 runtime 组合。
