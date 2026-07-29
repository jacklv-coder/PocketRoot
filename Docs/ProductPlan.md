# PocketRoot 产品规划

[简体中文](ProductPlan.md) | [English](en/ProductPlan.md) | [文档中心](README.md)

## 产品愿景

**Embed a local Linux Terminal and Files workspace in any iOS app.**

PocketRoot 希望让 iPhone 和 iPad App 能够以明确、安全、可审核的方式嵌入一个本地
ARM64 Linux 工作区。接入者既可以通过 Swift API 执行有界命令，也可以直接展示共享
同一个 Linux guest 的 Terminal / Files 页面；切换页面时 Terminal 的 PTY session
保持运行。

它不是一个完整的 iSH App 分支、新的操作系统或通用虚拟化平台。PocketRoot 的重点是
把运行时、RootFS、命令、终端 UI、文件浏览和宿主 App 生命周期拆成可复用模块，并把
供应链、资源边界和发行门禁写进工程契约。

## 目标用户

### iOS 应用开发者

希望在 App 内提供离线 Linux 工具、诊断命令、开发辅助能力或受控 shell 工作流，并要求使用 Swift/Swift Concurrency 接口接入。

### Runtime 与终端组件维护者

需要一个独立于业务 UI 的模块边界，用来迭代 iSH 适配、RootFS、PTY、SwiftTerm、并发和生命周期。

### 安全、合规与发行负责人

需要准确知道应用包含哪些上游源码和二进制、RootFS 从哪里来、哈希是什么、哪些许可证义务与 App Store 风险尚未解决。

## 核心使用场景

1. **受控的一次性命令**
   App 准备经过审核的 Alpine fakefs，启动运行时，执行有超时和输出上限的 shell 命令，并取得退出码、signal、stdout 和 stderr。

2. **嵌入式交互终端**
   通过 SwiftTerm UI 适配层提供持续 PTY，支持输入、输出、窗口 resize、signal、EOF、
   取消与可预测关闭，并与 Files 页面共享同一个 Linux guest。

3. **可恢复的本地 Linux 环境**
   对固定版本 RootFS 做安全安装、校验、复用、损坏替换和中断恢复，不让半安装状态覆盖已可用环境。

4. **可审计的供应链**
   以完整 commit、nested gitlink、制品大小和 SHA-256 固定所有外部输入；升级时重新执行源码、二进制、运行时和合规审查。

5. **上层轻量 Agent**
   App 使用原生 Swift 的有界 agent loop 连接模型与显式注册的工具；Linux runtime 只执行经过宿主审批和限额的命令，不在 RootFS 中安装完整 Codex CLI。

## 用户价值

- 业务代码只依赖稳定的 PocketRoot API，不直接持有 iSH C/Swift 对象。
- 默认产品不加载实验性二进制，应用必须显式选择真实运行时。
- RootFS 的网络获取和授权策略由应用控制，PocketRoot 不隐式下载。
- 阻塞原生调用所在 executor、并发所有权、从 driver 入口覆盖 finite SPAWN、
  stdin close 与 event read 的统一 deadline、Swift 结果缓冲、native session 积压和
  control queue 都有明确边界；deadline 后的退出确认另有固定有界清理窗口。
- 构建、测试、制品哈希、限制与开放门禁可从仓库文档追溯。

## 产品边界

### 当前范围

- iOS 18 及更高版本。
- arm64 iPhone、iPad 与 arm64 iOS Simulator 构建。
- Swift Package 模块化接口。
- UIKit 演示外壳。
- 本地、调用方提供的固定 RootFS 归档。
- iSH 启动和一次性 shell 命令。
- 持续 `PocketRootSession`、SwiftTerm PTY 和 guest 文件浏览。
- provider-agnostic、有 turn/tool/input/output 边界的 `PocketRootAgent` loop。
- 默认 post-boot guest identity gate。
- 安全 RootFS 安装与恢复。
- 实验性原生最终链接和 Simulator smoke。

### 计划范围

- 应用专属 guest 工具、网络和数据健康检查。
- Demo 的真实运行时依赖注入。
- soft shutdown 的持续生命周期与故障注入验证。
- PTY/SwiftTerm 的真机与 iPad 生命周期硬化。
- 真机生命周期、内存、性能和故障注入。
- 满足许可证与发行要求后的受控分发。

### 非目标

- 在 macOS 上运行 iSH guest。
- 支持 x86_64 iOS Simulator。
- 多个并行 iSH 内核实例。
- 默认从网络下载 RootFS。
- 未经审核地执行任意外部制品。
- 把 Agent、浏览器自动化、MCP 或云端编排放入 `PocketRootCore`。
- 在 RootFS 中安装 Codex CLI 作为手机端 agent 架构。
- 把 Node.js/npm 当作必需 agent runtime 或由库自动安装；应用仍可把它们作为明确审核、
  显式安装的通用 guest package。
- 未经宿主审批就执行模型生成的 shell 命令。
- 绕过 iOS sandbox、私有 API 或 App Store 规则。
- 在合规门禁完成前提供生产、TestFlight 或公开二进制。

## 产品分层

| 层级 | 面向用户 | 产品 |
| --- | --- | --- |
| 公共模型与协调 | 所有接入者 | `PocketRootCore` |
| RootFS 资源与安装 | 管理本地归档的应用 | `PocketRootResources` |
| 终端 UI 基础 | UIKit 应用 | `PocketRootTerminal` |
| 上层 agent loop | 需要模型/工具编排的应用 | `PocketRootAgent` |
| 安全默认入口 | 只需要稳定 API 的应用 | `PocketRoot` |
| iSH 原生适配 | 实验性 runtime 维护者 | `PocketRootIshRuntime` |
| RootFS + iSH 组合 | 实验性应用接入者 | `PocketRootIshRuntimeIntegration` |

默认伞形产品只重新导出 Core、Resources 和 Terminal。`PocketRootAgent` 与两个实验性
runtime 产品必须显式添加，避免普通消费者意外引入模型编排或链接原生 IshEmbed。

## 版本阶段与验收定义

### Foundation

目标：工程、API 和 UI 边界可持续开发。

验收：

- Swift Package 产品和测试目标建立。
- iOS 18 基线统一。
- UIKit Demo、XcodeGen、脚本与 CI 可运行。
- 默认系统在没有真实 runtime 时安全失败。

### Experimental Runtime

目标：证明固定 iSH + RootFS 组合在受控条件下可运行。

验收：

- 不可变依赖和制品哈希已记录。
- RootFS 安全安装和恢复测试通过。
- arm64 Simulator 与 unsigned device 完成最终链接。
- Simulator 原生 smoke 覆盖启动、命令、边界和关闭。
- 所有未满足的真机、PTY、关闭和合规门禁保持显式。

### Developer Preview

目标：让仓库维护者在真机上持续体验完整命令和终端链路，但仍不承诺公开发行。

拟定验收：

- iPhone 与 iPad 签名运行通过。
- 最低 Xcode 16 原生验证通过。
- 默认 guest identity gate 持续通过，并补齐应用专属健康策略。
- Demo 使用统一的 prepared system 注入。
- PTY、SwiftTerm 和 App 生命周期具备最小可用闭环。
- 关闭策略有明确产品决定。

### Beta / Distribution Candidate

目标：具备外部分发候选资格。

拟定验收：

- 生命周期、内存、性能、ENOSPC、掉电和迁移测试完成。
- 依赖更新与制品重建可复现。
- 许可证、NOTICE、对应源码和 SBOM 完整。
- 安全评审与 App Store Guideline 2.5.2 有明确结论。
- 不再存在未处置的阻塞发行门禁。

具体完成状态不在本文维护，统一以[路线图](Roadmap.md)为准。

## 成功指标

在开发阶段使用可验证的工程指标，而不是下载量：

- 新接入者能只根据文档完成构建、选择产品并运行一次性命令。
- 每个外部制品都有不可变来源、大小、哈希和审计记录。
- runtime 或 RootFS 变更必须通过对应单元、真实资产、最终链接和 smoke 门禁。
- 同一故障不会破坏已验证的 RootFS 安装。
- 一次性命令取消已确认 guest 退出，8 MiB 持续二进制输出和 256 MiB Simulator
  生命周期 `ru_maxrss` 基线已通过；原生 control path 端到端 deadline 完成硬化后，
  命令不会因阻塞写入或无限输出永久占用进程；真机 jetsam 与剩余缺口保持显式门禁。
- 所有生产阻塞条件在路线图中有负责人可执行的退出条件。
- 中英文文档链接、命令和关键事实保持同步。

## 产品原则

1. **安全默认，实验显式。**
2. **调用方拥有网络和资产授权策略。**
3. **不可变输入优先于便利的浮动版本。**
4. **先证明生命周期，再接入终端 UI。**
5. **失败时保留最后一个已验证状态。**
6. **不把 Simulator 链接成功描述成真机或发行可用。**
7. **重要限制必须出现在使用示例之前。**

## 主要风险

| 风险 | 当前策略 |
| --- | --- |
| 原生 runtime 每进程只允许一次 lifecycle | soft shutdown 返回后发布 `.terminated`；再次 boot 需要新宿主进程 |
| XCFramework 平台切片有限 | 明确 arm64 支持矩阵；用真实最终链接验证 |
| RootFS 来源与许可证复杂 | 不提交、不默认打包；固定哈希；设置发行门禁 |
| iSH 是进程级单例 | 进程级 ownership gate 与串行执行器 |
| PTY 指针与关闭竞态 | 在会话注册、bounded read 和 close 顺序完成前不接 SwiftTerm |
| App Store 对下载执行代码的限制 | 单独进行 Guideline 2.5.2 评审 |
| 文档与实现漂移 | 指定事实源并执行双语文档检查 |

## 相关文档

- [路线图](Roadmap.md)
- [架构说明](Architecture.md)
- [应用接入指南](IntegrationGuide.md)
- [发行与合规](ReleaseCompliance.md)
- [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md)
