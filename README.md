# PocketRoot

[简体中文](README.md) | [English](README.en.md)

PocketRoot 是面向 iOS 的可嵌入 ARM64 Linux 运行时与终端基础设施。项目使用 Swift Package 提供模块化 API，以 iSH/IshEmbed 作为实验性运行时，在 iOS 沙箱中安装经过校验的 Alpine fakefs，并执行有边界的一次性 shell 命令。

> [!WARNING]
> 真实 iSH 集成目前仍是 **实验性（Experimental）** 能力。固定的上游版本在调用 `shutdown()` 时会执行 `_exit(0)`，直接结束整个宿主 App，且不会返回 Swift。当前版本不得用于生产、TestFlight 或公开二进制分发。

## 当前能做什么

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| Swift Package 模块与公共 API | 可用 | Core、Resources、Terminal 及默认伞形产品 |
| UIKit Demo 外壳 | 可用 | 展示 System、Terminal、Commands、Diagnostics 四个入口 |
| RootFS 校验与安全安装 | 可用 | 固定大小和 SHA-256、安全解包、journal 保护的同卷 promotion、复用与中断恢复 |
| iSH 启动与一次性命令 | 实验性 | 仅 `iOS + arm64`，必须显式依赖实验产品 |
| 交互式 PTY 与 SwiftTerm | 未实现 | 会话、输入、resize、signal 和安全关闭仍在规划中 |
| 真机与公开发行 | 阻塞 | 仍需 iPhone/iPad、Xcode 16、许可证、SBOM 和 App Store 审查 |

默认 `PocketRoot` 产品不会带入真实 iSH 运行时，也不会打包或下载 RootFS。`PocketRootSystem.shared` 使用安全的占位实现；需要真实运行时的应用必须显式依赖 `PocketRootIshRuntimeIntegration`。

## 实现概览

```mermaid
flowchart LR
    A["调用方提供已审查的本地 RootFS 归档"] --> B["PocketRootResources 校验并安全安装"]
    B --> C["生成版本化 fakefs 安装目录"]
    C --> D["PocketRootIshRuntimeIntegration 组合系统"]
    D --> E["PocketRootIshRuntime 启动 IshEmbed"]
    E --> F["校验 aarch64、Alpine 身份与工作目录"]
    F --> G["通过 /bin/sh -lc 执行一次性命令"]
    G --> H["返回 exit code、signal、stdout、stderr 与 timeout"]
```

关键设计原则：

- RootFS 二进制不提交到仓库，库本身不执行网络下载。
- 上游源码、XCFramework 和 RootFS 都固定到不可变 revision 或 SHA-256。
- RootFS 在私有、同卷 staging 中解包；校验通过后，通过文件型 journal 保护的多步同卷 rename 完成可恢复、可回滚的 promotion。每次 rename 和记录写入各自具有原子性，但整个替换流程不是一次整体原子操作；当前未显式 `fsync` 文件和目录，因此不承诺突然掉电时的持久性。
- IshEmbed 是进程级单例；PocketRoot 只允许一个原生运行时所有者和一个在途命令。
- 同步原生调用在串行阻塞队列中执行，不阻塞主线程和 Swift cooperative executor。
- `boot()` 只有在固定 post-boot 命令验证 guest 架构、Alpine 身份和命令上下文后才报告 `ready`；默认 v0.3.3 组合还严格要求 Alpine `3.19.1`。
- session 建立后的 event-read loop 使用 deadline，Swift 已收集的 stdout/stderr 有产品配额；pre-exit 错误必须先确认可信 `EXITED` 才允许继续执行，否则 runtime 失败关闭并要求重启宿主。spawn 直接报告 not-running、protocol 或 broken-pipe 也视为 transport 已不可信并失败关闭。supervisor 在 guest 创建前拒绝命令的负数合成状态会保留为可恢复错误；固定 v0.3.3 的 `(exitCode: 17, signal: 0)` 与 transport broken pipe 有歧义，因此显式清理后失败关闭。当前原生 transport 的 spawn/control/terminate/close 仍可能阻塞，未读 inbox 也无独立上限，因此端到端时间界限和完整内存背压仍是开放门禁。

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
- 原生路径已在 Xcode 26.1.1 与 iOS 18.2 arm64 Simulator 验证；最低 Xcode 16 的原生行为验证仍是开放门禁。

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

当前 Demo 是 UI 和公共 API 演示外壳，不会直接启动 Alpine：

- System 与 Commands 页面连接的是占位 `PocketRootSystem.shared`。
- Terminal 页面尚未接入 PTY。
- Diagnostics 展示后续集成位置。
- 原生运行时验证使用独立的 compile spike 与 smoke App。

完整开发步骤见[快速开始](Docs/GettingStarted.md)。

## 在应用中使用实验性运行时

在 Swift Package 依赖中显式选择 `PocketRootIshRuntimeIntegration`。项目尚未发布稳定 Git tag；在首个正式版本前应固定到经过审核的完整 commit，而不是使用浮动分支。

```swift
import Foundation
import PocketRoot
import PocketRootIshRuntime
import PocketRootIshRuntimeIntegration

guard PocketRootIshRuntimeFactory.isAvailable else {
    fatalError("The native runtime requires an arm64 iOS build.")
}

let applicationSupportURL = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)

let prepared = try await PocketRootIshSystemFactory.prepareSystem(
    archiveURL: localReviewedArchiveURL,
    applicationSupportURL: applicationSupportURL
)

try await prepared.system.boot()

let result = try await prepared.system.execute(
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
2. `prepareSystem` 只校验、安装并组合系统；它不会下载 RootFS，也不会启动运行时。
3. 安装器在 `applicationSupportURL/rootfs/<version>` 下直接保存 `meta.db`、`data/` 和 `.pocketroot-rootfs.json`，不会再保留一层 `fs/`。版本目录和安装记录有效时即可复用；`current.json` 缺失或不匹配会在复用时修复。
4. `boot()` 必须显式调用；它会在同一原生串行队列执行默认健康门禁，固定 v0.3.3 factory 只有观察到 `aarch64`、Alpine `3.19.1` 和配置的 guest 工作目录后才返回 `ready`。
5. 命令通过 `/bin/sh -lc` 执行，所以 `command` 是 shell 字符串，而不是无 shell 解析的 argv API。
6. 每个请求独立设置工作目录、环境变量、超时和 stderr 合并策略。
7. 真实 `shutdown()` 会结束整个宿主 App；不要把它用于页面消失、场景切换或普通资源清理。
8. 公共调用结束后只发布稳定 state；失败关闭会公开 `.failed`，重入调用不会泄漏 runtime 内部过渡态，旧的异步快照也不能覆盖较新的失败状态。

完整的依赖选择、错误处理和生命周期约束见[应用接入指南](Docs/IntegrationGuide.md)。

## RootFS 策略

仓库只记录审核后的元数据和安全安装代码，不包含 `fs.tar.gz`：

- 固定 RootFS 清单：对应 parent IshEmbed package release `v0.3.3`
- Guest：Alpine `3.19.1 aarch64`
- 归档大小：`6,581,376` 字节
- 展开大小：`18,838,016` 字节
- SHA-256：`be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4`

固定 URL 只是清单元数据，不代表库会自动下载。许可证、NOTICE、对应源码和 SBOM 未完成前，不得把该 RootFS 加入 Package、App bundle 或公开发行物。

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
```

最后一个命令要求 Apple Silicon、iOS 18 Simulator 和精确匹配固定清单的本地归档。它验证 RootFS 准备、启动、guest 身份、命令上下文、输出、退出码、超时恢复、输出上限恢复和进程终止式关闭。详细矩阵见[测试与验证](Docs/Testing.md)。

## 文档导航

| 想了解的内容 | 文档 |
| --- | --- |
| 从整体建立技术心智模型与学习路线 | [技术学习指南](Docs/TechnicalGuide.md) |
| 产品目标、用户、场景与非目标 | [产品规划](Docs/ProductPlan.md) |
| 从零构建工程和运行 Demo | [快速开始](Docs/GettingStarted.md) |
| SwiftPM 产品选择与应用接入 | [应用接入指南](Docs/IntegrationGuide.md) |
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

PocketRoot 自身许可证仍在首个公开版本前确认中。实验性运行时链接 GPL 标识的上游代码，候选 RootFS 包含多种 copyleft 与 permissive 许可证。生产、TestFlight 和公开二进制分发保持关闭，直到真机、最低 Xcode 16 原生验证、许可证、NOTICE、对应源码、SBOM 和 App Store Review Guideline 2.5.2 均有明确结论。
