# 故障排查

[简体中文](Troubleshooting.md) | [English](en/Troubleshooting.md) | [文档中心](README.md)

先确认问题属于哪一层：依赖解析、工程生成、默认 Demo、RootFS 安装、原生最终链接、runtime 启动、命令执行或 smoke。不要用更高层的错误掩盖更低层输入问题。

## 快速诊断

```bash
git status -sb
git remote -v
xcodebuild -version
swift --version
xcrun --sdk iphonesimulator --show-sdk-version
xcodegen version
swift package show-dependencies
```

然后运行最小相关检查：

```bash
./Scripts/check-docs.sh
./Scripts/test.sh
./Scripts/build.sh
```

## `xcodegen: command not found`

安装：

```bash
brew install xcodegen
```

或重新运行：

```bash
./Scripts/bootstrap.sh
```

`bootstrap.sh` 在缺少 XcodeGen 时会调用 Homebrew。CI 不使用浮动 Homebrew 包，而是下载固定版本并验证哈希。

## 找不到 `PocketRootDemo.xcodeproj`

生成工程：

```bash
./Scripts/generate-project.sh
```

不要从其他机器复制生成工程，也不要直接修改 `project.pbxproj`。`project.yml` 是事实源。

## Swift Package 依赖解析失败

检查：

- 当前网络能访问固定的 `ish-arm64-pkg` commit 和 parent release asset；
- `Package.swift` 中完整 revision 没被改成 branch；
- `Package.resolved` 没有非预期漂移；
- Xcode Command Line Tools 指向预期 Xcode。

重试标准流程：

```bash
swift package resolve
./Scripts/generate-project.sh
```

不要用移动 tag 或本地未记录二进制绕过失败。

## `no such module IshEmbed` 或 native runtime 不可用

真实 driver 只支持：

- iOS；
- arm64；
- `canImport(IshEmbed)`；
- 显式依赖 `PocketRootIshRuntime` / `PocketRootIshRuntimeIntegration`。

macOS、x86_64 Simulator 和默认 `PocketRoot` 产品不会提供真实 runtime。在已经链接成功的 arm64 target 中可检查：

```swift
PocketRootIshRuntimeFactory.isAvailable
```

`isAvailable` 不是构建架构选择器：SwiftPM 会先解析并链接 binary，再运行应用代码。链接实验产品的 target 必须设置 `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` 或与 portable target 分离。Intel Mac 无法构建当前原生 target；Apple Silicon 上仍要确保 destination 是 arm64 iOS Simulator，不是 Rosetta/x86_64。

## 在上游包直接运行 `swift test` 时链接失败

固定 IshEmbed manifest 声明 macOS，但 release XCFramework 没有 macOS slice。直接在上游包做 macOS native link 预期失败。

在 PocketRoot 仓库运行宿主测试；adapter seam 会使用 unsupported/injected driver。原生行为用 `build-runtime-spike.sh` 与 iOS smoke 验证。

## Demo 显示 `RootFS Missing`

Demo 已链接实验 runtime，但不会从网络下载或从仓库读取 RootFS。用固定本地归档配置
Debug 开发资产后重新构建：

```bash
./Scripts/inject-demo-rootfs.sh \
  --install-development-archive /absolute/path/to/fs.tar.gz
```

脚本会拒绝 symlink、错误大小/hash、源码树内输入和 Release 注入。成功后
Diagnostics 应先显示 `RootFS Embedded`，点击 System 的 Boot 后变为 `Installed`，
runtime 变为 `Ready`。真实应用接入流程见[应用接入指南](IntegrationGuide.md)。

## `runtimeNotBooted`

确认顺序：

1. `prepareSystem` 成功返回；
2. 使用返回的 `prepared.system`，不是 `PocketRootSystem.shared`；
3. `boot()` 成功；
4. `await system.state == .ready`；
5. 再调用 `execute`。

如果 boot 失败，保留原始 typed error 和 runtime state，并先判断失败发生在哪个边界：

- RootFS 预检（例如目录缺失、`meta.db` 是 symlink，或检查期间文件属性读取失败）发生在申请 process-global 槽位之前。这类失败统一抛 typed `rootFSUnavailable` 并保持 `idle`，修正输入或重新 prepare 后，可在同一宿主进程中重试 boot。
- 一旦已申请槽位并进入 native driver boot，该调用若失败就会保守地把全局槽位标记为 terminated。此后同一或新建 system 的 boot 都会得到 `restartRequired`，必须重启宿主 App。
- 第一次 boot 仍在执行时的并发重复调用会被拒绝；等待原调用返回，不要另起多个 system 竞争。

## “already booted” 或重复 boot

RootFS 预检失败仍可按上一节说明在同一进程重试；但一旦 system 已成功 boot，或已进入并消费
native process slot，就不能再次 boot。IshEmbed 是进程级单例，多个 system 也不能拥有多个内核。

应用应集中保存 prepared system，并让一个 lifecycle coordinator 管理它，不要让多个页面各自 prepare/boot。

## `restartRequired`

表示当前宿主进程不能再次启动 native runtime，常见原因：

- native driver boot 在占用 process-global 槽位后失败；
- 当前真实 native shutdown 或 injected driver 的 shutdown 已返回，并将 process gate 标记为 terminated；
- 其他 system 已终结全局 iSH 实例，当前 system 看到的 process gate 已是 terminated。

当前解决方式是重新启动宿主 App。不要实现 `shutdown(); boot()`。

## RootFS 大小或 SHA-256 不匹配

必须同时满足：

- 6,581,376 字节；
- `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4`。

检查：

```bash
stat -f '%z' /path/to/fs.tar.gz
shasum -a 256 /path/to/fs.tar.gz
```

可能原因：

- 下载不完整；
- 拿到不同 release；
- HTML 错误页被保存为 archive；
- 代理或缓存替换内容；
- 文件在校验前后被修改。

不要关闭验证或修改 manifest 来接受未知文件。重新从已审核来源取得，并独立计算 hash。

## RootFS 报 symlink 或非普通文件

installer 故意拒绝：

- symlink 输入；
- FIFO、socket、device；
- fakefs root/meta.db/data symlink；
- tar 内 symlink/hardlink/special node。

把真实 archive 文件复制到 App 自己控制的本地普通文件路径。不要通过 `followSymlink` 降低边界。

## “missing top-level fs” 或 fakefs 布局无效

固定 archive 必须解包为：

```text
fs/
├── meta.db
└── data/
```

不要传入 Alpine 原始 minirootfs；PocketRoot 当前接受的是 iSH fakefs archive。检查上游版本、归档格式和清单。

## RootFS 安装失败但旧版本仍存在

这是预期保护。候选只有完全校验后才 promotion；替换失败会回滚旧版本和 `current.json`。保留日志和错误，让下次 `prepareArchive` 先恢复 journal。

不要手工删除 `.replacement-transaction` 或 `current.json`，除非已经理解并备份整个安装状态；手工清理可能破坏恢复证据。

## 命令 timeout 无效

timeout 必须：

- 大于 0；
- 不超过 24 小时。

0、负数或超过 86,400 秒会抛 `invalidCommandRequest`。正数但不足 1 毫秒会 clamp 到 1 毫秒。

该 timeout 从 driver 入口建立绝对 deadline，finite `spawn` 使用剩余时间，后续
stdin close 与 event-read loop 复用同一 deadline。session 尚未建立时的 deadline
耗尽会返回 `timedOut == true`；其他 spawn/control 错误仍保留其错误语义。

使用明确边界：

```swift
PocketRootCommandRequest(
    command: "your-command",
    timeout: .seconds(30)
)
```

## 命令超时后仍有部分输出

这是设计行为。driver 在统一 deadline 到期时终止已建立的 session，并在观察到可信 guest `EXITED` 后给出 `timedOut == true` 以及此前已经接收的结果；无法确认时会失败关闭并要求重启宿主。deadline 到期后的 terminate/退出确认使用独立的固定有界清理窗口，因此 `timeout` 不是调用必须在同一时刻返回的承诺。应用必须先检查 `timedOut`，不能只看 stdout。

## `commandOutputLimitExceeded`

命令累计 stdout 或 stderr 超过 runtime 配置：

- 默认 stdout：8 MiB；
- 默认 stderr：4 MiB。

adapter 会终止当前 session 并抛 typed error。解决方向：

- 修改命令让输出分页、过滤或写入 guest 文件；
- 在风险评估后通过 `prepareSystem` 调整 limit；
- 不要设置无限上限；
- 捕获错误并允许下一条命令继续。

## “one one-shot command at a time”

当前 runtime 每次只允许一个一次性命令。并发调用中只有一个可进入 native session。

在应用层使用单个一次性命令队列，或在 UI 中禁用重复提交。交互 PTY session 可以并存，
并由 runtime registry 在 shutdown 前统一关闭；这不放宽 one-shot 限制。

## shutdown 提示 active command

等待当前 `execute` 返回后再 shutdown。PocketRoot 故意禁止 shutdown 越过仍在读写的 native session。

## shutdown 返回后无法再次 boot

这是固定 `v0.4.0-abi.6` 的 single-lifecycle 契约。shutdown 会 soft-halt/join 并返回
`.terminated`，但 iSH 进程级全局状态不允许同一宿主进程再次 boot；后续调用会得到
`restartRequired`。需要新 runtime 时重启宿主进程。参见
[ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md)。

## smoke 找不到 iOS 18 Simulator

查看：

```bash
xcrun simctl list runtimes
xcrun simctl list devices available
```

在 Xcode Settings 中安装 iOS 18 Simulator runtime。默认脚本需要 Apple Silicon，并会创建 iPhone 16 临时设备。临时设备在脚本成功或失败退出时都会被删除，除非设置 `POCKETROOT_KEEP_SIMULATOR=1`。也可指定已有 UDID：

```bash
POCKETROOT_SMOKE_DEVICE="paste-exact-udid-here" \
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh
```

目标必须运行 iOS 18.x。

对 caller-provided Simulator，脚本会 boot 设备、卸载旧 smoke App 并安装新版本；退出时只终止 App，会留下新 App、注入的 archive/report 和当前开机状态。用精确 UDID 安全清理：

```bash
SMOKE_DEVICE_UDID="paste-exact-udid-here"
xcrun simctl terminate "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke || true
xcrun simctl uninstall "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke
```

`uninstall` 会一并删除该 App 的数据容器。如果设备在 smoke 前是关机状态，可再执行 `xcrun simctl shutdown "$SMOKE_DEVICE_UDID"`。只对已确认的脚本专用临时 UDID 使用 `simctl delete`，绝不删除共享开发设备。

## 真机 smoke 签名或启动失败

真机 runner 要求 Xcode 能为 `POCKETROOT_DEVELOPMENT_TEAM` 选择有效 development profile，且目标设备已配对、启用 Developer Mode 并保持解锁。常见错误：

- `POCKETROOT_SMOKE_DEVICE did not resolve`：传入 `devicectl` 可识别的 CoreDevice UUID、
  硬件 UDID 或设备名；runner 会验证 physical iOS 属性并自动解析 Xcode destination
  所需的硬件 UDID。
- `No Account for Team`：指定的 team 没有可用 Xcode account/profile；改用实际可开发签名的 team，或先在 Xcode 完成账号与签名设置。
- `No profiles`：bundle ID 没有匹配的 development profile，或设备不在 profile 中。
- `Unable to launch ... Locked`：保持设备解锁后重跑；安装成功不代表锁屏状态允许 foreground launch。
- `Process-suspend smoke did not reach its host checkpoint`：确认 App 没有提前退出，
  并查看 runner 输出的最后 progress；不要手工伪造 resume marker。
- `UIKit-lifecycle smoke did not reach its host checkpoint` 或
  `UIKit lifecycle App did not report its background callback`：保持设备解锁，确认
  Settings 能前台启动，并检查最后 progress。
- `UIKit lifecycle activation did not preserve the smoke process PID`：原 App 被系统
  终止或重新启动，本次结果不能证明同一 runtime 跨前后台保持，必须按失败处理。
- `Forced-relaunch persistence smoke did not reach its host checkpoint`：seed 进程没有在
  guest 标记写入并 `sync` 后到达检查点；查看最后 progress，不要手工伪造。
- `Forced-relaunch seed process did not terminate` 或 verify PID 与 seed PID 相同：
  CoreDevice 没有确认旧进程结束/新进程建立，不能把本次结果当成跨进程恢复。
- `The guest marker did not survive forced App termination`：RootFS 被重新安装、同步数据
  没有保留或 fakefs 恢复失败；保留失败日志排查，不要跳过复用与标记检查。
- `The zero-capacity preflight unexpectedly installed a RootFS`：受限容量 SPI 没有进入
  生产容量预检；本次结果无效，不要改成真实填满设备。
- `Storage failure left RootFS entries`：容量或 ENOSPC 失败留下 staging、事务或安装项；
  保留失败容器排查，不能继续正常 boot 来掩盖残留。
- `Unexpected gzip ENOSPC error`：固定 1 字节故障没有从实际 gzip 写入路径返回空间错误；
  检查 SPI 映射和 C extractor，不要扩大写入量。
- `The App delegate did not expose a memory-warning callback`：smoke target 没有实现公开
  `applicationDidReceiveMemoryWarning` 回调，或当前 delegate 不是预期 App；不要改用
  private selector。
- `The injected memory-warning callback did not persist fresh evidence`：回调未到达或读取了
  旧 marker；确认独立模式和启动前 progress 重置，不要把它描述为系统内存压力。
- `The guest command did not acknowledge active execution before the callback`：guest 没有在
  5 秒内写入 fresh 启动标记；回调不会在此时注入，也不能用固定延时替代该确认。
- `The active guest command did not survive the memory-warning callback`：保留 report 与
  console 排查 runtime 连续性；该失败不能用后续命令成功掩盖。
- `... smoke launch did not return a process identifier`：当前 Xcode/CoreDevice
  没有返回受支持的 launch JSON PID；不要从人类可读输出猜 PID。
- entitlement 校验失败：不要跳过；确认 profile 的 application identifier、team identifier 和 `get-task-allow`。

runner 在成功或失败退出时默认卸载已安装的 smoke App，从而删除注入的 RootFS。设置 `POCKETROOT_KEEP_DEVICE_APP=1` 会改变这一清理行为。

## smoke 超时或没有 report

检查：

- archive 路径可读且 hash 正确；
- Simulator 能 boot；
- smoke App 是否成功安装和启动；
- timeout 是否足够；
- `simctl --console` 输出；
- App Documents 中的 `pocketroot-smoke-result.json`；
- 宿主磁盘和 Simulator storage。

临时提高 App 启动后的 JSON report 等待时间（不影响工程生成、构建、Simulator boot，也不改变 report 后固定 20 秒的 runner 清理检查）：

```bash
POCKETROOT_SMOKE_TIMEOUT_SECONDS=600 \
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh
```

不要因为超时就把 crash 或缺失 report 视为成功。

## 本地通过但 CI 失败

比较：

- Xcode/Swift/SDK；
- arm64 destination；
- `Package.resolved`；
- XcodeGen 版本；
- RootFS/XcodeGen digest；
- 生成工程是否来自最新 `project.yml`；
- 未提交文件是否被本地构建错误地引用。

CI 先运行 `./Scripts/check-docs.sh`，再执行测试与构建。`actions/checkout` 自身固定到精确 revision，但它检出的仓库内容是 workflow 事件选定的 SHA（push SHA 或 PR merge SHA）。CI 是干净 checkout，不能访问本地 archive、DerivedData、未提交工程或凭据。

## 报告问题时提供

- commit SHA 与分支；
- Xcode、Swift、SDK、macOS；
- destination 与架构；
- 执行的精确命令；
- typed error 和相关日志；
- runtime state；
- archive 版本、大小和 SHA-256（不要上传受限 archive）；
- 最小复现；
- 是否为 host test、Simulator、unsigned link 或 signed device。

不要在 issue 或日志中附带 token、签名材料、私有路径内容或未获授权的 RootFS。
