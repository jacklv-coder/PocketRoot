# PocketRoot 文档中心

[简体中文](README.md) | [English](en/README.md) | [返回项目首页](../README.md)

**Embed a local Linux Terminal and Files workspace in any iOS app.**

这里是 PocketRoot 的中文主文档入口。目标是让产品、应用接入者和维护者不阅读源码，也能回答三个问题：

1. PocketRoot 要解决什么问题，当前边界在哪里？
2. RootFS、iSH 运行时和命令执行是怎样实现的？
3. 如何构建工程、接入 Swift Package、验证改动并处理常见错误？

## 推荐阅读路线

### 产品与项目负责人

1. [产品规划](ProductPlan.md)：目标用户、核心场景、价值、非目标和版本定义。
2. [路线图](Roadmap.md)：当前完成度、开放门禁和后续优先级。
3. [发行与合规](ReleaseCompliance.md)：许可证、RootFS、SBOM 与 App Store 限制。
4. [v0.1.0 发布说明](Releases/0.1.0.md)：首个源码版本的能力、接入方式与发布边界。
5. [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md)：为什么当前只以实验性方式采用 IshEmbed。

### 应用接入者

1. [快速开始](GettingStarted.md)：环境准备、克隆、构建和 Demo 说明。
2. [应用接入指南](IntegrationGuide.md)：选择 Swift Package 产品并完成 `prepare → boot → execute`。
3. [轻量 Agent Loop](Agent.md)：上层模型/工具循环、资源边界与安全原则。
4. [RootFS 安全方案](RootFS.md)：归档来源、校验、安装、存储和恢复。
5. [故障排查](Troubleshooting.md)：架构、哈希、状态、超时和关闭问题。

### 工程维护者

1. [技术学习指南](TechnicalGuide.md)：先建立三个仓库、模块、调用链和验证方法的整体心智模型。
2. [架构说明](Architecture.md)：模块边界、依赖方向、并发和生命周期。
3. [实现原理](Implementation.md)：端到端调用链、源码地图与关键不变量。
4. [测试与验证](Testing.md)：单元测试、真实资产测试、最终链接、CI 和 smoke。
5. [上游依赖清单](UpstreamDependencies.md)：不可变 revision、gitlink、制品哈希和更新流程。
6. [贡献指南](../CONTRIBUTING.md)：分支、提交、验证和中英文同步规则。
7. [变更日志](../CHANGELOG.md)：已发布与尚未发布的行为和 API 变化。

## 文档职责

| 文档 | 唯一负责的事实 |
| --- | --- |
| [技术学习指南](TechnicalGuide.md) | 跨仓库心智模型、源码入口、验证映射与推荐学习顺序 |
| [产品规划](ProductPlan.md) | 用户、场景、价值、MVP 与非目标 |
| [路线图](Roadmap.md) | 动态完成状态、门禁和下一步 |
| [架构说明](Architecture.md) | 当前模块、依赖、并发与生命周期设计 |
| [实现原理](Implementation.md) | 源码到行为的端到端映射 |
| [应用接入指南](IntegrationGuide.md) | 对外使用方式、API 语义和示例 |
| [轻量 Agent Loop](Agent.md) | 上层 agent loop 协议、资源边界、安全原则与后续拆分 |
| [RootFS 安全方案](RootFS.md) | RootFS 输入边界、安装算法和存储模型 |
| [测试与验证](Testing.md) | 测试命令、环境、覆盖范围和证据 |
| [上游依赖清单](UpstreamDependencies.md) | revision、gitlink、URL、大小和哈希 |
| [发行与合规](ReleaseCompliance.md) | 许可证、NOTICE、对应源码、SBOM 与商店门禁 |
| [版本发布说明](Releases/0.1.0.md) | 版本能力、Swift Package 接入、发布边界与已知限制 |
| [ADR](Decisions/ADR-001-IshEmbed-Feasibility.md) | 已冻结的技术决策、理由与后果 |
| [变更日志](../CHANGELOG.md) | 每次版本或未发布变更 |

当摘要与事实源冲突时，以代码、`Package.resolved`、制品清单和上表指定的事实源为准。

## 当前状态摘要

- 最低部署版本：iOS 18.0。
- 默认 `PocketRoot` 产品：可构建，使用占位 Linux 运行时，不包含真实 iSH。
- `PocketRootIshRuntime` 与 `PocketRootIshRuntimeIntegration`：实验性、显式启用。
- `PocketRootAgent`：provider-agnostic 有界 agent loop 与 OpenAI Responses transport。
- `PocketRootAgentRuntimeTools`：显式 opt-in 的 policy 与逐次审批保护命令 adapter。
- RootFS：安全安装、15 包 inventory、SPDX SBOM、默认配置证据和 10/10 origin
  对应源码候选材料工程复核已完成；二进制未提交、未打包、未由库下载，完整
  license/NOTICE、源码提供/交付与法律批准仍阻塞发行。
- iOS 18.2 arm64 Simulator：原生 smoke 已通过。
- 默认 boot identity gate：已验证 `aarch64`、Alpine 身份、可选版本与 guest 工作目录后才 ready。
- 交互 PTY、SwiftTerm 与 guest 文件浏览已实现并通过单元/Simulator 编译；signed iPhone
  一次性命令、Xcode 16 和 soft shutdown 基线已通过，新增 PTY 的真机生命周期、iPad
  和公开发行仍未完成或被阻塞。

最新动态状态只在[路线图](Roadmap.md)维护。

## 语言与维护规则

- 现有路径是简体中文主文档；英文镜像位于 [`Docs/en/`](en/README.md)。
- 根目录使用 `README.md / README.en.md`、`CONTRIBUTING.md / CONTRIBUTING.en.md` 和 `CHANGELOG.md / CHANGELOG.en.md` 成对维护。
- 修改行为、API、哈希、脚本或门禁时，必须在同一个 PR 中同步对应中英文文档。
- API、模块、路径、命令、状态 case 和哈希保持代码原文；专业术语首次出现使用“中文（English）”。
- 图表必须同时有文字说明，不能把关键约束只放在图中。
- 运行 `./Scripts/check-docs.sh` 检查成对文档、中文覆盖和相对链接。

## 术语约定

| 中文 | 英文 | 说明 |
| --- | --- | --- |
| 实验性 | Experimental | 表示必须显式启用且不具备发行承诺 |
| 一次性命令 | one-shot command | 启动子进程、收集有界输出并等待退出 |
| 单生命周期关闭 | single-lifecycle shutdown | soft shutdown 返回，但同一宿主进程不能再次 boot |
| 软关闭 | soft shutdown | 不结束宿主进程、完成原生线程清理后返回 Swift |
| 最终链接 | final link | 生成可执行 App，区别于只生成静态归档 |
| 制品 | artifact | XCFramework、RootFS 等外部输入 |
| `arm64` | `arm64` | Apple 平台构建架构 |
| `aarch64` | `aarch64` | Linux guest 返回的架构名 |
| `fakefs` | `fakefs` | iSH 使用的 `meta.db + data/` 文件系统布局 |
