# PocketRoot

[简体中文](README.md) | [English](README.en.md)

**Embed a local Linux Terminal and Files workspace in any iOS app.**

[![CI](https://github.com/jacklv-coder/PocketRoot/actions/workflows/ci.yml/badge.svg)](https://github.com/jacklv-coder/PocketRoot/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange)
![Status](https://img.shields.io/badge/status-Experimental-yellow)

PocketRoot 是面向 iPhone 和 iPad App 的本地 Linux Workspace SDK。它把基于 iSH
的 ARM64 Linux runtime、SwiftTerm 交互终端、guest 文件浏览、RootFS 安装与 Swift
生命周期 API 组合成可嵌入的 Swift Package。整个环境在 App 沙箱内本地运行，不依赖
远程 shell，不要求越狱，也不会安装 Codex CLI。

## 接入后直接获得什么

- **Terminal**：完整 PTY 会话，支持输入、持续输出、resize、signal、EOF 与有序关闭。
- **Files**：浏览 Linux guest 目录、创建/删除文件与目录，并进行有界预览。
- **Workspace**：在 Terminal 与 Files 间切换，同时保持同一个终端 session。
- **Linux Runtime**：在 iOS 沙箱内准备、启动并管理基于 iSH 的 Alpine ARM64 环境。
- **RootFS 生命周期**：校验、安装、复用、恢复调用方提供的已审查 RootFS 归档。
- **Swift API 与现成 UI**：执行有界命令，或直接展示 UIKit / SwiftUI Workspace 页面。

PocketRoot 的定位不是另一个终端 App，也不是新的操作系统：它是让现有 iOS App
嵌入本地 Linux Terminal + Files 工作区的 SDK。可以先查看
[最小宿主 App](Examples/PocketRootHostApp)和[应用接入指南](Docs/IntegrationGuide.md)。

> [!WARNING]
> 真实 iSH 集成目前仍是 **实验性（Experimental）** 能力。固定的
> `v0.4.0-abi.6` 已支持返回 Swift 的 soft shutdown，但每个宿主进程仍只允许一次有效
> boot/shutdown；iPad、持续负载和发行合规门禁尚未闭环。当前版本不得用于
> 生产、TestFlight 或公开二进制分发。

## 当前能做什么

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| Swift Package 模块与公共 API | 可用 | Core、Resources、Terminal、Agent、Agent Runtime Tools 及默认伞形产品 |
| UIKit Demo 外壳 | 可用 | 展示 System、Terminal、Files、Commands、Diagnostics 五个入口 |
| RootFS 校验与安全安装 | 可用 | 固定大小和 SHA-256、安全解包、journal 保护的同卷 promotion、复用与中断恢复 |
| iSH 启动与一次性命令 | 实验性 | 仅 `iOS + arm64`；支持确认 guest 退出的一次性命令取消 |
| 终端与文件浏览 | 可接入 / 实验性 | UIKit/SwiftUI 注入已 boot system；SwiftTerm 持续 PTY 支持输入、resize、signal/EOF，文件页支持树形展开、导航、有界预览及基础文件管理 |
| 轻量 agent loop | 核心、OpenAI transport 与审批命令工具可用 | Agent 与 Runtime Tools 均显式 opt-in；不安装 Codex CLI，不自动批准 shell |
| 交互式 PTY 与 SwiftTerm | 已实现，待扩大真机验证 | public session、bounded read、输入、resize、signal/EOF、registry 与 close-before-shutdown 已接通；Simulator 已通过 PTY 持续输入/输出、前后台、旋转、关闭/重开、Files 预览与有序 shutdown |
| 真机与公开发行 | 部分通过 / 阻塞 | iPhone 一次性命令门禁与 signed Host build 已通过；Host UI runner 已就绪，但 Jack iPhone 的 iOS 26.6 beta 超出本机 Xcode 26.1.1 设备支持范围，另需兼容工具链实跑、真实 storage pressure、iPad、jetsam/断电、最终制品与合规门禁 |

默认 `PocketRoot` 产品不会带入 agent loop 或真实 iSH 运行时，也不会打包或下载 RootFS。
需要 agent 的应用显式依赖 `PocketRootAgent`；只有需要审批命令 adapter 时才额外依赖
`PocketRootAgentRuntimeTools`；需要真实运行时的应用显式依赖
`PocketRootIshRuntimeIntegration`。`PocketRootSystem.shared` 仍使用安全的占位实现。

## 最短 UI 接入

业务 App 长期保留一个 `PocketRootIshWorkspaceHost`，然后直接打开集成页面。页面会
准备本地 RootFS、boot runtime，并展示共享同一个 Linux guest 的 Terminal / Files
Workspace；切换到 Files 时 Terminal 的 PTY session 会继续保持：

```swift
import PocketRoot
import PocketRootIshRuntimeIntegration

let host = PocketRootIshWorkspaceHost(
    runtimeConfiguration: .init(
        archiveURL: localReviewedRootFSURL,
        applicationSupportURL: applicationSupportURL
    )
)

navigationController?.pushViewController(
    host.makeViewController(),
    animated: true
)
```

`localReviewedRootFSURL` 必须是 App 已合法取得并完成审查的本地归档。PocketRoot
当前不会从网络下载、选择或公开分发 RootFS。SwiftUI 使用同一个长期保留的 host：

```swift
PocketRootIshWorkspaceView(host: host)
```

## 实现概览

```mermaid
flowchart LR
    A["调用方提供已审查的本地 RootFS 归档"] --> B["PocketRootResources 校验并安全安装"]
    B --> C["生成版本化 fakefs 安装目录"]
    C --> D["PocketRootIshRuntimeIntegration 组合系统"]
    D --> E["PocketRootIshRuntime 启动 IshEmbed"]
    E --> F["校验 aarch64、Alpine 身份与工作目录"]
    F --> G["一次性命令或持续 PTY session"]
    G --> H["SwiftTerm 终端 / guest 文件浏览 / 有界结果"]
```

关键设计原则：

- RootFS 二进制不提交到仓库，库本身不执行网络下载。
- 上游源码、XCFramework 和 RootFS 都固定到不可变 revision 或 SHA-256。
- RootFS 在私有、同卷 staging 中解包；校验通过后先持久化候选树，再通过已持久化 journal、逐次目录同步和原子 `current.json` 完成可恢复、可回滚的 promotion。整个替换仍不是一次整体原子操作，但明确的文件/目录同步顺序和断电切点恢复矩阵保证可推断 commit 或 rollback；真机强制断电实证仍是独立门禁。
- IshEmbed 是进程级单例；PocketRoot 只允许一个原生运行时所有者和一个在途一次性命令，并登记所有 live PTY session。
- 同步原生调用在串行阻塞队列中执行，不阻塞主线程和 Swift cooperative executor。
- 取消一次性命令会终止 native session，确认 guest `EXITED` 后才返回；成功后 runtime
  可继续使用，无法确认清理则失败关闭。取消不回滚此前副作用。
- `boot()` 只有在固定 post-boot 命令验证 guest 架构、Alpine 身份和命令上下文后才报告 `ready`；内置 v0.3.3 RootFS 清单还严格要求 Alpine `3.19.1`。
- 请求 timeout 从 driver 入口建立统一 deadline，覆盖 finite native SPAWN、
  stdin-close admission 和 event-read loop；终止后的权威 `EXITED` 确认另有固定有界清理窗口。
  Swift 结果有独立 stdout/stderr 配额，native transport 另有每 session 4 MiB/4096 帧
  输出积压、4 MiB/256 帧 control 总预算及 lifecycle reserve。8 MiB 二进制 stdout
  smoke 会跨越 native backlog 并逐字节验证结果；完整 Simulator smoke 生命周期还要求
  进程 `ru_maxrss` 不超过 256 MiB。该门禁不是物理设备 jetsam 证据。supervisor/transport
  failure 以类型化错误返回，正常 guest `exit 17` 不再与 broken pipe 混淆；无法确认退出
  时 PocketRoot 仍失败关闭。

完整实现见[架构说明](Docs/Architecture.md)、[实现原理](Docs/Implementation.md)和 [RootFS 安全方案](Docs/RootFS.md)。

## 环境要求

- macOS 开发机；原生 IshEmbed 构建与 smoke 需要 Apple Silicon
- Xcode 16.0 或更高版本，并安装 iOS 18 SDK
- Swift 5.10 或更高版本
- iOS 18.0 或更高版本
- Homebrew 与 XcodeGen

说明：

- macOS 13 仅是运行 Swift Package 宿主测试的最低声明，不是受支持的 Linux 运行时平台。
- IshEmbed XCFramework 只有 arm64 iOS 真机和 arm64 iOS Simulator 切片，不支持 x86_64 Simulator 或 macOS。链接实验产品的 App target 必须在选择 Swift Package 产品前就排除 x86_64 Simulator；`isAvailable` 是已成功链接后的运行时探针，不能挽救缺失切片的 target。
- 原生路径已在 Xcode 16.0 / iOS 18.0 SDK 和 Xcode 26.1.1 / iOS 18.2
  arm64 Simulator 验证；两套环境都完成最终链接和 17 项 native smoke。

## 从源码开始

```bash
git clone git@github.com:jacklv-coder/PocketRoot.git
cd PocketRoot

./Scripts/bootstrap.sh
./Scripts/test.sh
./Scripts/build.sh
open PocketRootDemo.xcodeproj
```

`bootstrap.sh` 会解析 Swift Package 并通过 XcodeGen 生成工程。`PocketRootDemo.xcodeproj` 不提交到 Git；`project.yml` 才是工程事实源。

Demo 已接通实验性 iSH、SwiftTerm PTY、Commands 和 Files 页面。RootFS 不提交到
仓库；首次运行前把固定归档配置为本机 Debug 开发资产：

```bash
./Scripts/inject-demo-rootfs.sh \
  --install-development-archive /absolute/path/to/fs.tar.gz
./Scripts/build.sh
open PocketRootDemo.xcodeproj
```

注入脚本严格校验 v0.3.3 的 `6,581,376` 字节与固定 SHA-256。Debug 构建把它复制到
App Bundle，首次点击 Boot 时再由 installer 校验并安装。未配置时 Demo 仍可构建并
明确显示 `RootFS Missing`；Release 不注入 RootFS，分发门禁保持关闭。

完整开发步骤见[快速开始](Docs/GettingStarted.md)。

## 在应用中使用实验性运行时

在 Swift Package 依赖中显式选择 `PocketRootIshRuntimeIntegration`。项目尚未发布稳定 Git tag；在首个正式版本前应固定到经过审核的完整 commit，而不是使用浮动分支。

```swift
import Foundation
import PocketRoot
import PocketRootIshRuntimeIntegration

let applicationSupportURL = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)

let runtimeController = PocketRootIshRuntimeController(
    configuration: PocketRootIshRuntimeControllerConfiguration(
        archiveURL: localReviewedArchiveURL,
        applicationSupportURL: applicationSupportURL
    )
)

_ = try await runtimeController.boot()

let result = try await runtimeController.execute(
    PocketRootCommandRequest(
        command: "/bin/uname -m",
        workingDirectory: "/",
        timeout: .seconds(30)
    )
)

print("exit:", result.exitCode)
print("stdout:", result.stdout)
print("stderr:", result.stderr)
```

这个流程具有以下语义：

1. `archiveURL` 必须指向调用方已经获得并完成授权审查的本地普通文件。
2. `runtimeController.boot()` 依次完成校验、安装、组合与显式 boot；它不会下载 RootFS。
3. 安装器在 `applicationSupportURL/rootfs/<version>` 下直接保存 `meta.db`、`data/` 和 `.pocketroot-rootfs.json`，不会再保留一层 `fs/`。版本目录和安装记录有效时即可复用；`current.json` 缺失或不匹配会在复用时修复。
4. `boot()` 必须显式调用；它会在同一原生串行队列执行默认健康门禁，内置 v0.3.3 RootFS 清单只有观察到 `aarch64`、Alpine `3.19.1` 和配置的 guest 工作目录后才返回 `ready`。
5. 命令通过 `/bin/sh -lc` 执行，所以 `command` 是 shell 字符串，而不是无 shell 解析的 argv API。
6. 每个请求独立设置工作目录、环境变量、超时和 stderr 合并策略。
7. 真实 `shutdown()` 会 soft-halt 并 join 原生 kernel 后返回；成功后状态为 `.terminated`，同一宿主进程不能再次 boot。
8. 公共调用结束后只发布稳定 state；失败关闭会公开 `.failed`，重入调用不会泄漏 runtime 内部过渡态，旧的异步快照也不能覆盖较新的失败状态。

可直接编译的独立宿主见
[`Examples/PocketRootHostApp`](Examples/PocketRootHostApp)；完整依赖选择、错误处理和
生命周期约束见[应用接入指南](Docs/IntegrationGuide.md)。

## RootFS 策略

仓库只记录审核后的元数据和安全安装代码，不包含 `fs.tar.gz`：

- 固定 RootFS 清单：对应 parent IshEmbed package release `v0.3.3`
- Guest：Alpine `3.19.1 aarch64`
- 归档大小：`6,581,376` 字节
- 展开大小：`18,838,016` 字节
- SHA-256：`be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4`

固定 URL 只是清单元数据，不代表库会自动下载。仓库已从固定归档生成 RootFS 包清单与 SPDX SBOM，完成全部 10 个 source origin（130 个规范化 aports 条目、9 个上游 distfile）的对应源码候选材料工程复核，并完成 78 个初始候选及 138 个外置 LICENSE/NOTICE payload 的 checksum-bound 工程复核；除缺少上游 MIT grant/版权声明的 `alpine-keys` 外，其余 7 个许可证候选 origin 的工程项均已关闭。历史 builder 源码已定位，但固定发布归档的精确环境/重建未验证；schema-v4 后继候选已在同 host 两次独立调用、共四次构建中复现，5 单元源码交付 inventory 与统一仓库外候选 materializer 也已建立，但不替换当前 pin。仓库另有可复现的最大实验组合 inventory/SPDX SBOM；CI 临时扫描 unsigned device runtime App，本地 runner 还构建并扫描 development-signed engineering `.xcarchive`，两者都复验完整文件树、Mach-O、签名/entitlement、风险信号和文件级 SPDX 2.3 SBOM，且不上传输出。它们不是最终发行签名/导出 archive 的扫描结果。完整 NOTICE/source offer、交付批准、法律复核和完整发行物 SBOM 未完成前，不得把该 RootFS 加入 Package、App bundle 或公开发行物。

## 验证命令

```bash
./Scripts/test.sh
./Scripts/check-docs.sh
./Scripts/build.sh
./Scripts/build-runtime-spike.sh

POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment

POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh

POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SIGNED_ARCHIVE_OUTPUT=/absolute/new/archive-scan \
POCKETROOT_SPDX_SCHEMA=/absolute/spdx-2.3-schema.json \
  ./Scripts/build-signed-engineering-archive.sh

POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh

POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-host-app-device-ui-smoke.sh
```

signed archive runner 只在 Mac 上生成并扫描 development-signed
`.xcarchive`，不安装、导出或上传。两个 smoke runner 都要求 Apple Silicon 和精确
匹配固定清单的本地归档；前者使用 iOS 18 Simulator，后者要求已配对、已启用
Developer Mode 且可开发签名的 iOS 18+ 真机。真机引用可以是 `devicectl` 接受的
CoreDevice UUID、硬件 UDID 或设备名；runner 会先验证 physical iOS 属性并解析硬件
UDID。它们验证 RootFS 准备、启动、guest 身份、命令上下文、输出、退出码、超时
恢复、输出上限恢复和返回 Swift 的 soft shutdown。详细矩阵见
[测试与验证](Docs/Testing.md)。

## 文档导航

| 想了解的内容 | 文档 |
| --- | --- |
| 从整体建立技术心智模型与学习路线 | [技术学习指南](Docs/TechnicalGuide.md) |
| 产品目标、用户、场景与非目标 | [产品规划](Docs/ProductPlan.md) |
| 从零构建工程和运行 Demo | [快速开始](Docs/GettingStarted.md) |
| SwiftPM 产品选择与应用接入 | [应用接入指南](Docs/IntegrationGuide.md) |
| 轻量 agent loop、边界与后续 transport | [轻量 Agent Loop](Docs/Agent.md) |
| 模块、并发与生命周期设计 | [架构说明](Docs/Architecture.md) |
| 端到端流程与源码地图 | [实现原理](Docs/Implementation.md) |
| RootFS 校验、安装和恢复 | [RootFS 安全方案](Docs/RootFS.md) |
| 测试层级、CI 和原生 smoke | [测试与验证](Docs/Testing.md) |
| 常见错误与定位方式 | [故障排查](Docs/Troubleshooting.md) |
| 当前里程碑与发布门禁 | [路线图](Docs/Roadmap.md) |
| 上游 revision、gitlink 和哈希 | [上游依赖清单](Docs/UpstreamDependencies.md) |
| 许可证与发行限制 | [发行与合规](Docs/ReleaseCompliance.md) |
| IshEmbed 采用决策 | [ADR-001](Docs/Decisions/ADR-001-IshEmbed-Feasibility.md) |
| 如何参与开发 | [贡献指南](CONTRIBUTING.md) |
| 已发生的变更 | [变更日志](CHANGELOG.md) |

完整阅读路线见[文档中心](Docs/README.md)。

## 许可证与发行状态

PocketRoot 自身许可证仍在首个公开版本前确认中。实验性运行时链接 GPL 标识的上游代码，候选 RootFS 包含多种 copyleft 与 permissive 许可证。RootFS 包级、最大实验工程组合和 unsigned 工程 App 文件级 SPDX SBOM 已生成，但生产、TestFlight 和公开二进制分发保持关闭，直到完整真机生命周期、许可证、NOTICE、对应源码、最终签名/导出制品扫描后的完整发行物 SBOM 和 App Store Review Guideline 2.5.2 均有明确结论。
