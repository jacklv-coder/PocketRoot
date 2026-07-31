# 应用接入指南

[简体中文](IntegrationGuide.md) | [English](en/IntegrationGuide.md) | [文档中心](README.md)

本指南描述当前公开 API 的真实行为。它区分安全默认产品、显式 agent 产品和实验性 iSH 产品，并给出从本地 RootFS 到一次性命令结果的完整闭环。

> [!CAUTION]
> 固定的 `v0.4.0-abi.9` 会 soft-halt 并 join embedded kernel，然后从
> `prepared.system.shutdown()` 返回 Swift。成功后同一宿主进程不能再次 boot；不要把它
> 放在页面退出、scene 切换、deinit 或无意触发的普通清理路径中。

## 1. 选择 Swift Package 产品

PocketRoot 暴露八个产品：

| 产品 | 用途 | 是否包含真实 iSH |
| --- | --- | --- |
| `PocketRootCore` | 状态、配置、命令、结果和错误模型 | 否 |
| `PocketRootResources` | RootFS 清单、校验、解包和安装 | 否 |
| `PocketRootTerminal` | UIKit/SwiftUI SwiftTerm PTY、guest 文件浏览与命令 fallback | 否 |
| `PocketRootAgent` | provider-agnostic 有界 agent loop 与 OpenAI Responses transport | 否 |
| `PocketRootAgentRuntimeTools` | 审批与策略保护的 Linux command adapter | 否 |
| `PocketRoot` | 默认伞形产品，重新导出 Core、Resources 与 Terminal | 否 |
| `PocketRootIshRuntime` | 固定 IshEmbed 的实验性原生适配 | 是 |
| `PocketRootIshRuntimeIntegration` | RootFS 安装器与原生适配的组合入口 | 是 |

仅构建业务模型或 UI 时依赖 `PocketRoot`。需要 agent loop 时额外显式依赖
`PocketRootAgent`；需要把已准备的 system 作为审批保护的命令工具交给 agent 时，再显式依赖
`PocketRootAgentRuntimeTools`。具体门禁见[轻量 Agent Loop](Agent.md)。要启动真实 guest，至少显式依赖
`PocketRootIshRuntimeIntegration`。只有直接使用底层 runtime factory 时才需要再显式选择
`PocketRootIshRuntime`；推荐的宿主控制器不需要业务 App 直接导入它。

首个源码版本为 `v0.1.0`。公共 API 仍处于 Experimental 阶段，因此远程接入建议
固定精确版本，避免自动接收后续可能包含破坏性 API 调整的 `0.x` 版本：

```swift
dependencies: [
    .package(
        url: "https://github.com/jacklv-coder/PocketRoot.git",
        exact: "0.1.0"
    )
],
targets: [
    .target(
        name: "YourAppFeature",
        dependencies: [
            .product(name: "PocketRoot", package: "PocketRoot"),
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
3. 选择 **Exact Version** 并填写 `0.1.0`；
4. 默认接入选择 `PocketRoot`；
5. 真实 runtime 另外选择 `PocketRootIshRuntimeIntegration`。

本地开发可使用：

```swift
.package(path: "../PocketRoot")
```

不要依赖浮动分支；Experimental `0.x` 阶段也不建议使用会自动接收后续 minor 版本的
`from: "0.1.0"`。源码 tag 不包含 RootFS、App、IPA、XCFramework 镜像或二进制 SDK，
也不解除 Runtime 分发门禁。

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

### 推荐：一个宿主控制器完成最小闭环

业务 App 应在 App/Scene owner 中长期保留一个 `PocketRootIshWorkspaceHost`。宿主只需
提供本地已审核 RootFS 归档和 Application Support 目录；它会合并并发 boot，自动完成
RootFS 准备与 runtime boot，并直接创建 Terminal、Files 或组合 Workspace 页面：

```swift
import PocketRoot
import PocketRootIshRuntimeIntegration

let pocketRootHost = PocketRootIshWorkspaceHost(
    runtimeConfiguration: PocketRootIshRuntimeControllerConfiguration(
        archiveURL: localReviewedArchiveURL,
        applicationSupportURL: applicationSupportURL,
        workDirectory: "/"
    ),
    workspaceConfiguration: PocketRootWorkspaceConfiguration(
        terminalConfiguration: .interactive(
            initialWorkingDirectory: "/root"
        ),
        initialFilePath: "/root",
        allowsFileOperations: true
    )
)

navigationController?.pushViewController(
    pocketRootHost.makeTerminalViewController(),
    animated: true
)

navigationController?.pushViewController(
    pocketRootHost.makeFilesViewController(),
    animated: true
)
```

两个直接入口都不要求业务层先 boot 或轮询 `readySystem`。Terminal 页面离开层级时只
关闭自己的 PTY，runtime 会保留给之后的 Terminal、Files 或 Workspace。需要一个页面
同时包含两个 tab 时使用 `pocketRootHost.makeViewController()`；切换到 Files 时同一个
PTY 会继续保持。

若整个 Workspace 的 Files tab 只允许浏览和预览，在
`PocketRootWorkspaceConfiguration` 中设置 `allowsFileOperations: false`；
SwiftUI 与 UIKit Workspace 会使用同一个只读边界。

宿主明确结束 Linux 能力时调用 `try await pocketRootHost.shutdown()`，它会先等待该 host
创建的全部页面关闭 PTY，再 shutdown process-global runtime。不要在 SwiftUI
`body` 中反复创建 host；SwiftUI 使用长期保留的同一个 host：

```swift
PocketRootIshWorkspaceView(host: pocketRootHost)
```

Host 不会下载或选择 RootFS，也不会安装 Node.js、npm、Codex CLI 或 Agent Loop。
只有 Terminal / Files 两个入口的最小 XcodeGen 宿主位于
[`Examples/PocketRootQuickStartApp`](../Examples/PocketRootQuickStartApp)；完整生命周期
宿主位于 [`Examples/PocketRootHostApp`](../Examples/PocketRootHostApp)。两者只依赖公开
Swift Package 产品，不读取 Demo 内部代码；CI 会真实编译并核对注入的 RootFS。

### 外部消费者验收

仓库内示例使用本地 package path，适合阅读和迭代；发布接入还需要证明一个不在
PocketRoot 源码树中的新 App 能独立解析和使用公共产品。验收夹具位于
[`Tests/Integration/ExternalConsumerApp`](../Tests/Integration/ExternalConsumerApp)，
runner 会把它复制到系统临时目录、把调用方提供的 RootFS 作为 App 资源加入临时工程，
然后执行一条真实 UI 流程：

1. 打开 Terminal，等待自动安装 RootFS 并 boot；
2. 通过持续 PTY 创建文件；
3. 进入后台并恢复，确认同一 Terminal 会话仍在；
4. 从 Files 打开并预览该文件；
5. 显式 shutdown，确认三个入口全部进入终态。

验证当前本地 checkout：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
POCKETROOT_EXTERNAL_CONSUMER_PACKAGE_PATH="$PWD" \
  ./Scripts/run-external-consumer-ui-smoke.sh
```

验证公开仓库中的精确 commit：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
POCKETROOT_EXTERNAL_CONSUMER_REPOSITORY_URL=https://github.com/jacklv-coder/PocketRoot.git \
POCKETROOT_EXTERNAL_CONSUMER_REVISION=<40-character-reviewed-sha> \
  ./Scripts/run-external-consumer-ui-smoke.sh
```

远程模式只接受公开 HTTPS Git URL 和完整小写 SHA，不能退化为 tag、branch 或版本
range。PR CI 使用贡献者 head 仓库的公开 `clone_url` 与 head SHA，因此 fork PR 也验证
实际提交。临时 App 只选择 `PocketRoot` 和 `PocketRootIshRuntimeIntegration`，不读取
仓库内 Demo 工程或 RootFS 注入脚本。测试完成后默认删除临时 App 和 Simulator；
设置 `POCKETROOT_KEEP_EXTERNAL_CONSUMER_APP=1` 或
`POCKETROOT_KEEP_UI_RESULT=1` 可保留诊断材料。

这项验收证明公共 SwiftPM 边界与最小 UI/生命周期闭环可接入，不授权重新分发测试
RootFS，也不解除 TestFlight、App Store、许可证、对应源码或最终制品门禁。

### 较低层宿主生命周期

需要分别组织 Boot、Terminal 和 Files 控件的 App 可继续长期保留
`PocketRootIshRuntimeController`，在 `readySystem` 非空后把同一个 system 传入各页面；
PTY 页面离开时调用 `closeSession()`，致命 session 失败后调用
`await runtimeController.refreshRuntimeState()`。

### 底层手动生命周期

如果产品需要自行管理 prepared system，可以继续直接使用组合 factory：

```swift
let system = prepared.system

try await system.boot()

guard await system.state == .ready else {
    throw PocketRootError.runtimeFailure("Runtime did not become ready.")
}
```

`boot()` 在原生 boot 返回后自动执行固定的 post-boot identity command。`healthCheck` 省略或为 `nil` 时，只有精确的内置 `.ishEmbedV0_3_3` manifest 会自动选择同名健康配置，并严格要求 `aarch64`、`alpine` 和 `3.19.1`；自定义 manifest 默认使用不固定版本的 `.alpineARM64`，应显式传入与已审查 RootFS 对应的版本配置。架构、OS ID 和可选版本必须是非空且不含 NUL 的字符串，timeout 必须在 `(0, 60]` 秒，guest `workDirectory` 必须是无 NUL 的绝对路径；可选 `supervisorGuestPath` 也不能含 NUL，且会在占用进程槽位和进入原生 boot 前校验。

健康命令有独立的 4 KiB stdout/stderr 上限；`os-release` 作为数据由 Swift 解析，工作目录通过 argv 传入并以双方 `pwd -P` 结果比较，因此路径别名不会误判且预期值不会被插入 shell。失败发生在 native boot 之后时，runtime 保守进入 `.failed` 并消耗进程级槽位，必须重启宿主 App。该门禁是已验证 RootFS 内基础信息与命令上下文的一致性检查，不是独立的来源/安全证明，也不证明业务工具、网络或数据健康。健康 timeout 从 driver 入口覆盖 finite SPAWN、stdin close 与 event read；终止确认另有固定有界清理窗口。

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
- driver 入口建立统一 timeout deadline；finite SPAWN 使用剩余时间，stdin close 和
  event-read loop 复用同一 deadline。到期时尝试终止 session，成功返回时包含
  `timedOut == true` 和已经收集的输出。
- native control queue、session backlog 与 lifecycle reserve 已有界；deadline 到期后的
  terminate 与权威 `EXITED` 确认使用独立的固定有界清理窗口。
- command、cwd 和 environment key/value 不能包含 NUL；environment key 还必须非空且不含 `=`。这些输入在进入 native driver 前校验，避免 C 字符串静默截断。
- spawn 直接返回 not-running、protocol 或 broken-pipe 时，PocketRoot 无法证明
  transport 与 guest 状态，runtime 会立即失败关闭。session 建立后的关闭 stdin、非
  timeout 读取、请求 timeout 或产品输出超限都会终止并确认退出。v4 transport 将
  supervisor rejection、broken pipe 与 native backlog overflow 作为类型化错误；
  guest `exit 17` 是合法结果，负数 `EXITED` 是协议完整性失败。native backlog overflow
  会请求有界 session 清理并保留 byte/frame 来源，但 void `session.close()` 无法向 Swift
  证明是否升级成 instance fail-close，所以 PocketRoot 会终结 process gate 并要求重启。
- `mergeStandardError == true` 时 stderr 合并到 stdout，`standardError` 为空。
- 默认 stdout 上限 8 MiB，stderr 上限 4 MiB；通过 `prepareSystem` 参数调整。
- 超过输出上限会终止 session，并抛出 `PocketRootError.commandOutputLimitExceeded`。
- 取消执行命令的 Swift Task 会请求终止 native session；只有确认可信 `EXITED` 后才抛
  `CancellationError`，成功取消后 runtime 保持 `.ready`。无法确认清理时会抛 runtime
  failure 并失败关闭。取消不回滚命令此前已经产生的副作用。

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

下表描述 runtime 状态机。每次读取 `PocketRootSystem.state` 都会与底层 runtime
对账，因此 `makeSession()` 返回后异步发生的 PTY 致命失败也能被观察到。它只发布稳定
状态；调用仍在执行时，外部轮询可能继续看到操作前的值，不能把它当作实时进度流。
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
| `.terminated` | v0.4.0-abi.9 soft shutdown 成功返回；同进程不能再次 boot |
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
// 等待所有命令结束后显式关闭这一进程唯一的 iSH lifecycle。
try await system.shutdown()
assert(await system.state == .terminated)
```

重要约束：

- 关闭前必须等待在途一次性命令结束。
- 原生 `shutdown()` 关闭 guest PID 1、soft-halt kernel、bounded join 后返回 Swift。
- 当前不能做 “shutdown 后 boot”。
- 不要在 background、scene disconnect 或 ViewController 生命周期里无意自动调用。
- shutdown 返回后可以完成宿主资源清理，但若还需要 Linux runtime，必须新建宿主进程。

## 8. 交互式 PTY 会话

已经 boot 的 `PocketRootSystem` 可创建持续存在的 PTY shell：

```swift
let session = try await system.makeSession(
    configuration: PocketRootSessionConfiguration(
        shell: "/bin/sh",
        shellArguments: ["-il"],
        workingDirectory: "/root"
    )
)

let outputTask = Task {
    for await event in session.events {
        switch event {
        case .standardOutput(let data), .standardError(let data):
            print(String(decoding: data, as: UTF8.self), terminator: "")
        case .exited(let code):
            print("exit: \(code)")
        case .failed(let message):
            print("failed: \(message)")
        case .started:
            break
        }
    }
}

try await session.write(Data("mkdir -p demo && cd demo\r".utf8))
try await session.resize(to: .init(rows: 32, columns: 100))
try await session.sendSignal(2) // SIGINT; TTY 路径转换成 Ctrl+C
try await session.closeInput() // EOF
await session.terminate()
_ = await outputTask.value
```

会话使用 IshEmbed 分配的真实 PTY，shell 状态、`cd`、环境变量和前台 job 在会话内持续
存在。native read 每 100 ms 有界轮询；Swift 事件流把输出切成 16 KiB，最多缓冲
4 MiB，并确保 `.failed/.exited` 终态不会被满缓冲丢弃；consumer 跟不上时会失败关闭，
而不是无界增长。默认 `SHELL` 与配置的 shell executable 一致，调用方显式
环境值优先。`terminate()` 使用有限 native admission、幂等并等待权威退出；session 创建
期间 shutdown 会明确拒绝而不会越过未登记的 native handle。致命 transport failure 会
同步让 runtime 进入 failed/restart-required。`system.shutdown()` 只有在全部 live
session 权威退出、关闭并注销后，才会关闭 guest PID 1 和 kernel。取消中的 session
创建会关闭已经生成但尚未返回的 native handle；可恢复的 supervisor 拒绝和 EOF 后操作
只结束或报错当前 session，不会把整个 runtime 误标为 restart-required。

`PocketRootCommandTerminalSession` 仍保留为不需要 PTY 的一次性命令 fallback，但不是
默认终端路径。

## 9. 接入终端与文件夹页面

如果宿主已经自行准备并 boot 完 `system`，可以使用更低层 Workspace 直接打开持续 PTY
和文件浏览；切换页面不会重建终端 session：

```swift
import PocketRootTerminal

let workspace = PocketRootWorkspaceViewController(
    system: system,
    configuration: .init(
        terminalConfiguration: .interactive(
            initialWorkingDirectory: "/root"
        ),
        initialFilePath: "/root"
    )
)
navigationController?.pushViewController(workspace, animated: true)
```

宿主只注入已经 ready 的 system；Workspace 不负责安装 RootFS、boot 或 shutdown。
页面退出时会关闭其 PTY，宿主主动关闭 runtime 时也可以先调用
`workspace.closeSession(completion:)`。UIKit 顶部分段控件和底部 Tab 都可以在不销毁
子页面的情况下切换 Terminal/Files。

如果只需要单独的终端页面，UIKit 也可以直接打开 SwiftTerm PTY：

```swift
import PocketRootTerminal

let terminalViewController = PocketRootTerminalViewController(
    system: system,
    configuration: .interactive(initialWorkingDirectory: "/root"),
    theme: .dark
)
terminalViewController.onSessionEnded = { [weak terminalViewController] _ in
    // shell 执行 exit 或 PTY 失败后，关闭页面或向用户提供“新建终端”入口。
    terminalViewController?.navigationController?.popViewController(animated: true)
}

navigationController?.pushViewController(
    terminalViewController,
    animated: true
)
```

省略 `sessionConfiguration` 时，PTY 使用
`configuration.initialWorkingDirectory`；如需自定义 shell、环境或终端尺寸，可以显式
传入 `sessionConfiguration`，此时该完整会话配置优先。
`cursorBlinkEnabled` 默认为 `true`；无动画截图或 UI 自动化可将它设为 `false`，不影响
PTY 输入、输出和会话生命周期。

文件夹页面使用同一个 system，并通过 NUL-framed 目录协议安全处理空格和换行文件名：

```swift
let filesViewController = PocketRootFileBrowserViewController(
    system: system,
    initialPath: "/root",
    allowsFileOperations: true
)
navigationController?.pushViewController(filesViewController, animated: true)
```

文件夹行的左侧箭头会按需读取并在当前列表原地展开子目录；点击文件夹图标或名称则进入
独立目录页面。两个交互共用相同的有界命令协议和路径校验，不会直接访问宿主 App
sandbox 中的 RootFS 存储结构。右上角 `+` 创建空文件或目录；长按或左滑条目可以
重命名、删除或分享导出普通文件；同一菜单的 `Import File` 使用系统文件选择器导入。
目录删除会显示递归删除确认。只读业务场景传入
`allowsFileOperations: false`。

不使用现成页面时，也可以直接调用同一个 actor API：

```swift
let files = PocketRootFileBrowser(system: system)
try await files.createFile(named: "notes.txt", in: "/root")
try await files.createDirectory(named: "Sources", in: "/root")
try await files.renameItem(at: "/root/notes.txt", to: "README.txt")
try await files.importFile(
    data: Data("hello\n".utf8),
    named: "imported.txt",
    in: "/root"
)
let exported = try await files.exportFile(at: "/root/imported.txt")
try await files.deleteItem(at: "/root/Sources", recursively: true)
```

名称必须是 1–255 个 UTF-8 字节，且不能是 `.`、`..`，也不能包含 `/` 或 NUL。
所有 guest 参数都经过校验；创建和重命名不会覆盖现有条目；`/` 不能被重命名或删除；
非空目录只有显式传入 `recursively: true` 才能删除。重命名使用 IshEmbed
`v0.4.0-abi.9` 中的原子 `RENAME_NOREPLACE` 等价实现，不执行存在竞态的 shell
check-then-move。导入和导出默认最多 1 MiB；导入字节通过
`PocketRootCommandRequest.standardInput` 传递，不进入 shell 文本，先写入目标目录内
权限为 `0600` 的随机 staging 文件，再通过相同的原生 no-replace rename 提交。目标
已存在时不会覆盖，写入、取消或提交失败会执行有界的尽力清理。导出只接受普通文件，
在 guest `stat` 与 Swift 收到数据后都校验上限。

SwiftUI 的组合入口更简洁：

```swift
import PocketRootTerminal
import SwiftUI

struct LinuxTerminalScreen: View {
    let system: PocketRootSystem

    var body: some View {
        PocketRootWorkspaceView(
            system: system,
            configuration: .init(initialFilePath: "/root")
        )
    }
}
```

SwiftTerm 负责 ANSI/VT、软键盘、选择、滚动和辅助功能语义；bridge 按序转发按键，
同步字符行列 resize，并把 guest 输出流送入 terminal。guest 的 OSC 52 剪贴板读写默认
拒绝，HTTP/HTTPS 链接只有在用户点击后才交给系统打开。文件页支持目录导航和最多
512 KiB 的有界文本/二进制预览及基础 guest 文件管理；只有显式导入/导出会经系统
document picker/share sheet 跨越 host 与 guest 边界，不提供任意宿主 App 沙箱浏览。

自定义 configuration 使用 `allowsInput: false` 时，PTY 仍显示和持续接收 guest 输出，
但 bridge 会丢弃键盘、粘贴等所有 host-to-guest 输入，也不会自动拉起键盘。SwiftUI
包装层以 system/executor 引用、session configuration 和 terminal configuration 作为
展示身份；这些输入变化时会先关闭旧会话并重建控制器，只有 theme 变化时原地更新。

## 10. 接入检查表

- [ ] deployment target 为 iOS 18.0 或更高。
- [ ] 真实运行目标是 arm64 iOS。
- [ ] Swift Package 固定到已审核完整 commit。
- [ ] 显式依赖实验产品，没有误用默认 `PocketRootSystem.shared`。
- [ ] RootFS 是本地普通文件，大小和 SHA-256 与清单匹配。
- [ ] RootFS 获取、许可和存储策略由 App 明确负责。
- [ ] `prepareSystem`、内置 boot identity gate 和业务专属健康检查按顺序执行。
- [ ] Terminal 与 Files 页面注入的是同一个已 boot、由应用持有的 system。
- [ ] 每个命令有正数 timeout，并处理非零 exit、signal、timeout 和输出超限。
- [ ] 页面永久移除时调用 `closeSession()`，或由 SwiftUI dismantle 自动回收 PTY。
- [ ] UIKit 通过 `onSessionEnded` 处理 shell `exit`/PTY 失败，并提供关闭或新建终端入口。
- [ ] 只读页面明确设置 `allowsInput: false`，并接受切换 backend/configuration 会重建会话。
- [ ] 产品接受 shutdown 后同一宿主进程不能再次 boot 的单 lifecycle 契约。
- [ ] 没有把 Simulator 结果当作真机或发行结论。
- [ ] 发布前完成[发行与合规](ReleaseCompliance.md)中的全部阻塞项。

## 相关文档

- [RootFS 安全方案](RootFS.md)
- [实现原理](Implementation.md)
- [测试与验证](Testing.md)
- [故障排查](Troubleshooting.md)
