# 应用接入指南

[简体中文](IntegrationGuide.md) | [English](en/IntegrationGuide.md) | [文档中心](README.md)

本指南描述当前公开 API 的真实行为。它区分安全默认产品、显式 agent 产品和实验性 iSH 产品，并给出从本地 RootFS 到一次性命令结果的完整闭环。

> [!CAUTION]
> 固定的 IshEmbed 版本在 `shutdown()` 中最终调用 `_exit(0)`。在真实 iOS 构建中，`prepared.system.shutdown()` 会直接结束整个宿主 App，正常情况下不会返回 Swift。不要把它放在页面退出、scene 切换、deinit 或普通清理路径中。

## 1. 选择 Swift Package 产品

PocketRoot 暴露七个产品：

| 产品 | 用途 | 是否包含真实 iSH |
| --- | --- | --- |
| `PocketRootCore` | 状态、配置、命令、结果和错误模型 | 否 |
| `PocketRootResources` | RootFS 清单、校验、解包和安装 | 否 |
| `PocketRootTerminal` | UIKit 终端占位 UI | 否 |
| `PocketRootAgent` | provider-agnostic 有界 agent loop 与 OpenAI Responses transport | 否 |
| `PocketRoot` | 默认伞形产品，重新导出 Core、Resources 与 Terminal | 否 |
| `PocketRootIshRuntime` | 固定 IshEmbed 的实验性原生适配 | 是 |
| `PocketRootIshRuntimeIntegration` | RootFS 安装器与原生适配的组合入口 | 是 |

仅构建业务模型或 UI 时依赖 `PocketRoot`。需要 agent loop 时额外显式依赖
`PocketRootAgent`；OpenAI Responses transport 已可选使用，Linux command tool 仍按独立 PR 实现，
具体边界见[轻量 Agent Loop](Agent.md)。要启动真实 guest，至少显式依赖
`PocketRootIshRuntimeIntegration`；示例还直接读取
`PocketRootIshRuntimeFactory.isAvailable`，因此同时列出 `PocketRootIshRuntime` 产品。

项目尚未发布稳定 Git tag。远程接入应固定到经过审核的完整 commit：

```swift
dependencies: [
    .package(
        url: "https://github.com/jacklv-coder/PocketRoot.git",
        revision: "<reviewed-full-commit>"
    )
],
targets: [
    .target(
        name: "YourAppFeature",
        dependencies: [
            .product(name: "PocketRoot", package: "PocketRoot"),
            .product(name: "PocketRootIshRuntime", package: "PocketRoot"),
            .product(
                name: "PocketRootIshRuntimeIntegration",
                package: "PocketRoot"
            )
        ]
    )
]
```

在 Xcode 图形界面中：

1. 选择 **File → Add Package Dependencies**；
2. 输入 `https://github.com/jacklv-coder/PocketRoot.git`；
3. 在首个 release tag 前使用 **Commit** 规则并填入已审核完整 SHA；
4. 默认接入选择 `PocketRoot`；
5. 真实 runtime 另外选择 `PocketRootIshRuntime` 和
   `PocketRootIshRuntimeIntegration`。

本地开发可使用：

```swift
.package(path: "../PocketRoot")
```

不要在首个 release tag 之前写 `from: "0.1.0"`，也不要依赖浮动分支作为可复现的生产输入。

## 2. 平台可用性

真实 driver 只有在以下编译条件同时满足时可用：

- `os(iOS)`；
- `arch(arm64)`；
- 能导入固定的 `IshEmbed` 产品。

```swift
import PocketRootIshRuntime

guard PocketRootIshRuntimeFactory.isAvailable else {
    // 在已经能够链接本产品的构建中检查 native driver 是否可用。
    return
}
```

macOS fallback 的作用是让宿主测试可以编译 API seam，不代表 macOS 支持 Linux guest。
更重要的是，`isAvailable` 运行在 SwiftPM 选择并链接依赖之后，不能作为 x86_64
Simulator 的降级开关。链接实验产品的 App target 必须像仓库内 spike/smoke target
一样设置 `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64`，或者拆成不依赖实验产品的
独立 target。Intel Mac 不能构建当前原生 target。

## 3. 准备 RootFS

调用方负责取得一个经过许可证和来源审查的本地普通文件。PocketRoot：

- 不读取远程 URL；
- 不请求网络权限；
- 不自动下载；
- 不把 RootFS 加入 bundle；
- 不接受符号链接或特殊文件作为归档输入。

取得 Application Support 目录：

```swift
import Foundation

let applicationSupportURL = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)
```

### 把归档送入 App 沙箱

`localReviewedArchiveURL` 不是 PocketRoot 自动生成的变量。产品可以通过
Files/document picker、受控下载或开发期 Simulator 注入取得文件。对于
document picker 返回的 security-scoped URL，建议先复制到 App 自己的
Application Support，再交给 installer：

```swift
func importRootFSArchive(
    from importedURL: URL,
    applicationSupportURL: URL
) throws -> URL {
    let accessed = importedURL.startAccessingSecurityScopedResource()
    defer {
        if accessed {
            importedURL.stopAccessingSecurityScopedResource()
        }
    }

    let fileManager = FileManager.default
    let inboxURL = applicationSupportURL.appendingPathComponent(
        "RootFSInput",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: inboxURL,
        withIntermediateDirectories: true
    )

    let localURL = inboxURL
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("tar.gz")
    try fileManager.copyItem(at: importedURL, to: localURL)
    return localURL
}

let localReviewedArchiveURL = try importRootFSArchive(
    from: documentPickerURL,
    applicationSupportURL: applicationSupportURL
)
```

受控下载也应先完成到 App 自有的唯一临时/持久路径，再把该本地 URL 传入。
调用方负责网络、认证、许可证、文件保护、备份排除和清理策略。installer 会
再次要求输入为真实普通文件，并在自己的私有 staging 中建立快照。`prepareSystem`
返回后，调用方可按产品策略删除 `RootFSInput` 中的导入副本。

准备系统：

```swift
import PocketRoot
import PocketRootIshRuntimeIntegration

let prepared = try await PocketRootIshSystemFactory.prepareSystem(
    archiveURL: localReviewedArchiveURL,
    applicationSupportURL: applicationSupportURL,
    workDirectory: "/",
    maximumStandardOutputBytes: 8 * 1_024 * 1_024,
    maximumStandardErrorBytes: 4 * 1_024 * 1_024
)
```

返回值包含：

- `prepared.installation.version`：固定清单版本；
- `prepared.installation.rootFSURL`：物化后的 fakefs 目录；
- `prepared.installation.reusedExistingInstallation`：是否复用已有有效安装；
- `prepared.system`：仍处于 `.idle`、尚未启动的实验性系统。

默认安装布局：

```text
<Application Support>/
└── rootfs/
    ├── current.json
    └── v0.3.3/
        ├── .pocketroot-rootfs.json
        ├── meta.db
        └── data/
```

归档中的顶层 `fs/` 只用于输入布局校验；installer 提升的是这个目录本身，因此最终
`v0.3.3/` 下直接是上述三个条目。复用以版本目录和其中的安装记录为准；即使
`current.json` 缺失或不匹配，有效版本仍会复用，并在返回前修复该索引。

实际安全算法见 [RootFS 安全方案](RootFS.md)。

## 4. 启动运行时

```swift
let system = prepared.system

try await system.boot()

guard await system.state == .ready else {
    throw PocketRootError.runtimeFailure("Runtime did not become ready.")
}
```

`boot()` 在原生 boot 返回后自动执行固定的 post-boot identity command。`healthCheck` 省略或为 `nil` 时，只有精确的内置 `.ishEmbedV0_3_3` manifest 会自动选择同名健康配置，并严格要求 `aarch64`、`alpine` 和 `3.19.1`；自定义 manifest 默认使用不固定版本的 `.alpineARM64`，应显式传入与已审查 RootFS 对应的版本配置。架构、OS ID 和可选版本必须是非空且不含 NUL 的字符串，timeout 必须在 `(0, 60]` 秒，guest `workDirectory` 必须是无 NUL 的绝对路径；可选 `supervisorGuestPath` 也不能含 NUL，且会在占用进程槽位和进入原生 boot 前校验。

健康命令有独立的 4 KiB stdout/stderr 上限；`os-release` 作为数据由 Swift 解析，工作目录通过 argv 传入并以双方 `pwd -P` 结果比较，因此路径别名不会误判且预期值不会被插入 shell。失败发生在 native boot 之后时，runtime 保守进入 `.failed` 并消耗进程级槽位，必须重启宿主 App。该门禁是已验证 RootFS 内基础信息与命令上下文的一致性检查，不是独立的来源/安全证明，也不证明业务工具、网络或数据健康；固定 v0.3.3 transport 的同步 control write 也仍可能让检查超出配置 timeout。

IshEmbed 是进程级单例。即使创建多个 `PocketRootSystem`，同一个 App 进程中也只有一个对象能获得原生 runtime ownership。

## 5. 执行一次性命令

```swift
let result = try await system.execute(
    PocketRootCommandRequest(
        command: "printf '%s' \"$POCKETROOT_MODE\"; uname -m",
        workingDirectory: "/",
        environment: ["POCKETROOT_MODE": "integration"],
        timeout: .seconds(10),
        mergeStandardError: false
    )
)

if result.timedOut {
    // read-loop deadline 已触发且已观察到 guest EXITED；结果可能包含此前收到的部分输出。
} else if result.signal != 0 {
    // 子进程被 signal 终止。
} else if result.exitCode != 0 {
    // shell 正常退出，但返回非零状态。
}

print(result.stdout)
print(result.stderr)
```

### 命令契约

- PocketRoot 实际执行 `/bin/sh -lc <command>`。
- `command` 是 shell 字符串；来自用户或网络的输入必须由调用方正确转义，不能把它当成安全 argv API。
- 当前同一个 runtime 一次只允许一个一次性命令。
- `workingDirectory` 和 `environment` 按请求传给 guest。
- timeout 必须大于 0 且不超过 24 小时。
- 大于 0 但不足 1 毫秒的 timeout 会提升为 1 毫秒，避免上游把 0 毫秒解释为无限等待。
- session 建立并关闭 stdin 后，event-read loop 才开始计算 timeout；到期时尝试终止 session，成功返回时包含 `timedOut == true` 和已经收集的输出。
- 当前固定 v0.3.3 的 `spawn`、control write、terminate 和 close 仍可能阻塞，所以请求 timeout 不是整个 `execute()` 的端到端 watchdog；在原生 transport 硬化完成前只能把它当作实验性 read-loop deadline。
- command、cwd 和 environment key/value 不能包含 NUL；environment key 还必须非空且不含 `=`。这些输入在进入 native driver 前校验，避免 C 字符串静默截断。
- spawn 直接返回 not-running、protocol 或 broken-pipe 时，PocketRoot 无法证明原生 transport 与 guest 状态，runtime 会立即失败关闭。session 建立后的关闭 stdin、非 timeout 读取、timeout 或输出超限错误都会先终止 session；只有观察到可信 guest `EXITED` 才会恢复为 `ready`。固定 supervisor 在创建 guest 前拒绝 spawn 时会产生负数合成 exit，PocketRoot 将其作为保留来源的可恢复 runtime error，而不是 guest 退出码。固定 v0.3.3 用 `(exitCode: 17, signal: 0)` 同时表示 transport broken pipe，该歧义组合会显式请求终止后失败关闭；终止或退出确认失败也会把 runtime 锁定为 `failed`，后续启动要求重启宿主进程。
- `mergeStandardError == true` 时 stderr 合并到 stdout，`standardError` 为空。
- 默认 stdout 上限 8 MiB，stderr 上限 4 MiB；通过 `prepareSystem` 参数调整。
- 超过输出上限会终止 session，并抛出 `PocketRootError.commandOutputLimitExceeded`。
- Swift Task cancellation 尚不是完整的原生命令取消契约，不应把取消 Task 当成可靠的 native kill。

`PocketRootConfiguration.defaultWorkingDirectory` 和 `commandTimeout` 当前不会自动覆盖每个 `PocketRootCommandRequest` 的字段。需要统一策略时，请在应用层构造请求工厂。

### 结果字段

| 字段 | 语义 |
| --- | --- |
| `exitCode` | guest 进程退出码；超时时为实现定义的失败值 |
| `signal` | 终止 signal；0 表示没有映射到 signal |
| `standardOutput` | 原始 stdout `Data` |
| `standardError` | 原始 stderr `Data` |
| `stdout` / `stderr` | 使用 UTF-8 replacement decoding 的便捷字符串 |
| `timedOut` | 是否由请求 timeout 触发终止 |

## 6. 状态与错误处理

### 状态

下表描述 runtime 状态机。当前公开的 `PocketRootSystem.state` 在
`boot()`、`shutdown()`、`execute()` 返回或抛错后只发布稳定状态；调用仍在执行时，
外部轮询可能继续看到操作前的值，不能把它当作实时进度流。
命令若因无法确认 guest 退出而失败关闭，`execute()` 抛错前的内部 `.failed` 会在抛错时
同步到公开 state。
底层 `IshLinuxRuntime` 会在 suspension 前更新自己的 `.booting` / `.shuttingDown`
过渡状态来阻止重入；若 actor 重入使另一调用在这时失败，公开刷新会忽略这些过渡值。
刷新还使用递增代次：较新的刷新开始后，较早取得但延迟返回的快照会被丢弃，不能把
较新的 `.failed` 覆盖回旧状态。

| 状态 | 含义 |
| --- | --- |
| `.idle` | 已创建但尚未 boot |
| `.preparingRootFS` | 公共状态预留；当前组合工厂在返回 system 前完成安装 |
| `.booting` | 原生启动进行中 |
| `.ready` | 可接受一次性命令 |
| `.shuttingDown` | 关闭已开始，不接受新操作 |
| `.terminated` | 只在测试 driver 或未来 soft shutdown 返回时可观察 |
| `.failed(String)` | 启动或关闭失败，通常需要重启宿主 App |

### 错误

```swift
do {
    let result = try await system.execute(request)
    consume(result)
} catch let error as PocketRootError {
    switch error {
    case .runtimeNotBooted:
        // 先完成 prepare 与 boot。
        break
    case .rootFSUnavailable(let reason):
        // 本地归档或 fakefs 布局不可用。
        log(reason)
    case .invalidCommandRequest(let reason):
        // timeout 或 runtime 输出上限不合法。
        log(reason)
    case .commandOutputLimitExceeded(let stream, let limit):
        log("\(stream) exceeded \(limit) bytes")
    case .restartRequired:
        // 当前进程不能再次启动原生 runtime。
        break
    case .runtimeFailure(let reason),
         .unsupportedOperation(let reason):
        log(reason)
    }
}
```

RootFS 安装阶段还可能抛出：

- `PocketRootRootFSValidationError`；
- `PocketRootArchiveExtractionError`；
- `PocketRootRootFSInstallationError`。

不要只按本地化字符串分支；优先匹配类型和 enum case。

## 7. 关闭与宿主生命周期

当前真实 iOS 路径：

```swift
// 只在产品明确希望结束整个 App 进程时调用。
try await system.shutdown()

// 固定上游版本通常不会执行到这里。
```

重要约束：

- 关闭前必须等待在途一次性命令结束。
- 原生 `shutdown()` 最终关闭 guest PID 1，并通过 `_exit(0)` 结束宿主 App。
- 当前不能做 “shutdown 后 boot”。
- 不要在 background、scene disconnect 或 ViewController 生命周期里自动调用。
- 如果产品不能接受整个 App 退出，应暂时不调用真实 shutdown，并等待 soft-shutdown artifact。
- iOS 不鼓励应用自行终止；该行为也是默认集成和发行门禁之一。

## 8. 尚未支持的会话 API

`PocketRootSession`、`PocketRootSessionConfiguration` 和 `PocketRootSessionEvent` 目前只是 API 基础。真实 iSH driver 的 session 创建仍返回 unsupported；公共 `PocketRootSystem` 也尚未暴露交互 session 创建入口。

当前不可宣称支持：

- PTY shell；
- 持续输入和输出；
- resize；
- signal/EOF；
- SwiftTerm 连接；
- session cancellation；
- 多 session registry；
- close-before-shutdown 保证。

## 9. 使用 Terminal 占位 UI

`PocketRootTerminal` 当前可作为 UIKit 展示组件使用，但它不是 PTY：

```swift
import PocketRootTerminal

let terminalViewController = PocketRootTerminalViewController(
    configuration: PocketRootTerminalConfiguration(
        placeholderText: "Linux terminal is not connected.",
        prompt: "$ ",
        allowsInput: true,
        showsAccessoryView: true
    ),
    theme: .dark
)

terminalViewController.appendOutput("Preparing local environment…")
terminalViewController.apply(
    theme: PocketRootTerminalTheme(palette: .dark, fontSize: 16)
)

navigationController?.pushViewController(
    terminalViewController,
    animated: true
)
```

这些 UIKit 操作在 `MainActor` 上执行。`appendOutput` 只更新 transcript，
`clearOutput()` 清空显示。即使 `allowsInput == true`，当前 accessory view 也
只回显输入并提示 runtime 尚未安装，不会把命令发送给 guest。真正 terminal
必须等待 `PocketRootSession`、PTY 和 SwiftTerm gate。

## 10. 接入检查表

- [ ] deployment target 为 iOS 18.0 或更高。
- [ ] 真实运行目标是 arm64 iOS。
- [ ] Swift Package 固定到已审核完整 commit。
- [ ] 显式依赖实验产品，没有误用默认 `PocketRootSystem.shared`。
- [ ] RootFS 是本地普通文件，大小和 SHA-256 与清单匹配。
- [ ] RootFS 获取、许可和存储策略由 App 明确负责。
- [ ] `prepareSystem`、内置 boot identity gate 和业务专属健康检查按顺序执行。
- [ ] 每个命令有正数 timeout，并处理非零 exit、signal、timeout 和输出超限。
- [ ] 产品明确接受或避免进程终止式 `shutdown()`。
- [ ] 没有把 Simulator 结果当作真机或发行结论。
- [ ] 发布前完成[发行与合规](ReleaseCompliance.md)中的全部阻塞项。

## 相关文档

- [RootFS 安全方案](RootFS.md)
- [实现原理](Implementation.md)
- [测试与验证](Testing.md)
- [故障排查](Troubleshooting.md)
