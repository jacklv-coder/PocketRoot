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
4. 已发布并固定 IshEmbed `v0.4.0-abi.6`，完成 control-path 统一 deadline、
   一次性命令 Swift Task 取消、native 退出确认和取消后恢复。
5. 完成最大实验工程组合 inventory/SPDX SBOM，并加入仓库外 `.app`/`.xcarchive`
   确定性扫描器；CI 已扫描 unsigned device runtime App 的文件、Mach-O、
   entitlement 与风险信号，本地 development-signed engineering archive 门禁也已
   闭环。最终发行签名/导出制品扫描和完整 SBOM 门禁继续关闭。
6. 当前：RootFS 容量预检、全写入/promotion ENOSPC、显式文件/目录持久化、确定性
   power-loss 切点矩阵、8 MiB 持续二进制输出基线、真机强制重启持久化和受限
   存储故障恢复和真机有界内存警告恢复已完成；继续真实 storage pressure/强制断电、
   jetsam 与峰值内存硬化。
7. 原生 Agent Loop/App 组合按产品决定暂停；不阻塞 runtime 独立验证。
8. 有物理 iPad 后补签名设备 smoke；该硬件门禁不阻塞前七项。

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
- repository native smoke 通过 17 项 prepare、boot、guest、持续输出、stream limit、command、recovery、shutdown 与 Simulator 生命周期峰值内存检查。
- v0.4.0-abi.6 在签名 iPhone 17 Pro（iOS 26.1）通过当前 17 项 native smoke；
  soft shutdown 返回 Swift，完整生命周期峰值 84.6 MiB。
- “Jack iPhone”（iPhone 14 Pro / iOS 26.6）通过标准 17 项和进程暂停/恢复 18 项；
  暂停 3 秒后 guest 命令恢复，峰值分别为 89.8 MiB 与 89.7 MiB。
- 同一设备通过真实 UIKit background/foreground/active 18 项门禁；原 PID 保持，
  前台恢复后 guest 命令成功，峰值 89.4 MiB。

这些证据建立了当前 Simulator、最低 Xcode 16 与单一 iPhone 的一次性命令路径，不覆盖 iPad、完整真机生命周期、PTY 或公开发行。

### 当前门禁

| 门禁 | 状态 | 退出条件 |
| --- | --- | --- |
| iOS 18 基线 | 已通过 | 持续保持 package、Demo、tests、CI 一致 |
| 不可变 IshEmbed revision | 已通过 | 只通过完整供应链更新流程变更 |
| 一次性命令 adapter | 已通过 | 保持 lifecycle、timeout、output-limit coverage |
| 一次性命令取消 | 已通过 | 队列前取消不进入 native；活动取消确认 `EXITED`；清理失败保持 fail-close |
| 原生 transport 背压 | 已通过 | 有界 protocol/session/stdin/log/control queue、跨越 4 MiB backlog 的 8 MiB 二进制输出及 256 MiB Simulator 生命周期 `ru_maxrss` 门禁均已接入；真机 jetsam 由 lifecycle 门禁维护 |
| 原生 control path 端到端时间界限 | 已通过 | ABI.6 finite SPAWN 与有界异步 close/terminate 已接入；PocketRoot 从 driver 入口复用统一 deadline，并为退出确认保留固定有界清理窗口 |
| iOS 18 Simulator 原生行为 | 已通过 | v0.4.0-abi.6 已重跑 17 项 soft-shutdown/peak-memory smoke；后续变更继续回归 |
| RootFS 安全安装与恢复 | 已通过 | 保持真实资产、snapshot、容量预检、rollback 和 recovery coverage |
| RootFS/runtime composition | 已通过 | 保持 caller-controlled、no-download、no-auto-boot |
| 默认 post-boot identity gate | 已通过 | `aarch64`、Alpine identity、可选 version 与 command context 通过后才 ready；保持失败占用槽位回归 |
| Demo 与外部宿主 runtime 接入 | 已通过 | Demo 和独立 Host App 共用公开 controller；Debug 只注入精确校验的仓库外 RootFS，Release 保持不注入 |
| 进程安全 soft shutdown | 已通过 | v0.4.0-abi.6 soft-halt/join 返回 Swift；同进程仍只允许一次 lifecycle |
| 签名 iPhone | 已通过 | v0.4.0-abi.6 完成 17 项 one-shot/soft-shutdown/peak-memory smoke；runtime 变更后继续重跑 |
| 签名 iPad | 阻塞 | physical boot 与 command smoke |
| 最低 Xcode 16 原生兼容 | 已通过 | Xcode 16.0 / iOS 18.0 SDK 完成 RootFS install、Simulator/device final-link 和 17 项 native smoke |
| App lifecycle 与内存 | 进行中 | Simulator 与 Jack iPhone 均有 256 MiB `ru_maxrss` 门禁；真机 process suspend/resume、UIKit foreground/background、强制终止后数据恢复和有界 App delegate memory-warning 回调恢复已通过；补真实 memory pressure/jetsam |
| RootFS ENOSPC/掉电 | 进行中 | 峰值空间预检、全 ENOSPC、七点持久化屏障、确定性掉电切点和 Jack iPhone 受限容量/ENOSPC 清理恢复已覆盖；补真实 storage pressure/强制断电 |
| 最大实验工程组合 inventory/SBOM | 已通过 | 保持 SwiftPM/Xcode target、ABI.6 dependency/source、外部 RootFS 15 包与 checksum 可复现；不得把它表述为最终发行 archive 扫描或发行授权 |
| unsigned 工程 App 扫描 | 已通过 | CI 临时扫描完整文件树、Mach-O、签名/entitlement、私有 framework/JIT 信号并校验文件级 SPDX；不上传输出，所有最终发行门禁保持关闭 |
| development-signed engineering archive | 已通过 | 本地生成标准 `.xcarchive`，要求 development entitlement 与有效签名，复验 clean 风险 evidence 和 SPDX；不安装/导出/上传，最终发行门禁保持关闭 |
| License-reviewed RootFS | 阻塞 | 15 包 inventory、10 source origin、SPDX SBOM、默认配置证据、10/10 origin 对应源码候选材料工程复核、78/78 初始候选和 138/138 外置 LICENSE/NOTICE payload 工程复核已完成；历史 builder 已定位、后继 schema-v4 候选完成同 host 跨调用复现，5 单元交付 inventory 与统一仓库外候选 materializer 已建立。只有 `alpine-keys` 的 MIT grant/版权声明仍未决，之后完成固定发布归档精确重建结论、完整 NOTICE/source offer、法律与交付批准 |
| App Store 2.5.2 | 阻塞 | guest download/execute policy 有书面结论 |

### 后续 runtime 执行顺序

1. **故障与资源硬化**
   保持 8 MiB sustained-output 和 256 MiB Simulator 峰值回归，继续真实 storage pressure/强制断电与 jetsam。

2. **暂停的 App 组合**
   原生 Agent Loop/App 组合恢复后，再把 prepared system 接入 UI；不把 RootFS 放进默认 target。

3. **iPad 真机基线**
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

状态：**首个 PTY/文件浏览闭环已实现；真机与 iPad 门禁进行中**。

已完成一个不依赖 Agent Loop、PTY 或 SwiftTerm 的低成本前置闭环：

- `PocketRootCommandTerminalSession` 在有界一次性命令之间保存当前工作目录；
- `ls`、`cd`、`mkdir`、`touch` 和重定向创建文件等普通 shell 操作可连续执行；
- UIKit 与 SwiftUI 宿主可把已经 boot 的 `PocketRootSystem` 直接注入终端 UI；
- 单次命令仍继承现有 timeout、取消、输出上限和 runtime fail-close 语义。

这个 facade 每次启动新的 `/bin/sh -lc`，不是 PTY；shell variable、alias 和后台 job
不会跨命令保存，`vim`、`top` 等交互程序不在当前声明范围。

本轮已完成：

1. public `PocketRootSystem.makeSession`；
2. process-wide live session registry；
3. 100 ms bounded native PTY reads 和固定 Swift event backlog；
4. stdin write/close、stdout/stderr/exit event；
5. terminal size/resize、signal/EOF；
6. 幂等 terminate、close-all-before-shutdown；
7. 固定 SwiftTerm `dd2fb8ac…` 并完成 UIKit/SwiftUI bridge；
8. NUL-framed guest 目录浏览与有界文件预览；
9. session/runtime/file-browser 单元测试与 iOS strict-concurrency 编译。

未完成门禁：

- 当前可用 signed iPhone 上持续输入、交互程序、resize、关闭/重开页面和 shutdown 顺序；
- background/foreground、内存压力和长时间输出；
- iPad 键盘、旋转、layout 和 VoiceOver 实机验证。

实现直接使用低层 `IshSession` 所有权，不使用上游高层 `IshTerminal` wrapper。

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
- 最大实验工程组合和 unsigned 工程 App 文件级 machine-readable SBOM 已完成；
  最终签名/导出发行制品 SBOM 待 archive 构建与扫描；
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
