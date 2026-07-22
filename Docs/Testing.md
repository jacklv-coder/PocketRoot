# 测试与验证

[简体中文](Testing.md) | [English](en/Testing.md) | [文档中心](README.md)

PocketRoot 把验证分成宿主逻辑、真实 RootFS、iOS 构建、完整原生最终链接和运行时行为五层。任何单层成功都不能替代其他层。

## 1. 验证层级

| 层级 | 入口 | 环境 | 证明什么 | 不证明什么 |
| --- | --- | --- | --- | --- |
| Swift Package 单元测试 | `./Scripts/test.sh` | macOS | Core、Resources、Terminal、adapter seam 和 composition 行为 | 原生 XCFramework 能运行 |
| 真实 RootFS 资产测试 | 带环境变量的 filtered test | macOS | 精确 release archive 可校验并完成首次物化 | 已有安装可复用或 iSH 能 boot |
| 默认 Demo 构建 | `./Scripts/build.sh` | Xcode + iOS SDK | 伞形产品和 UIKit Demo 可构建 | 实验 runtime 已链接 |
| 原生最终链接 | `./Scripts/build-runtime-spike.sh` | Apple toolchain | 完整实验依赖图可生成 iOS 可执行文件 | 真机或 guest 行为 |
| 原生 smoke | `./Scripts/run-runtime-smoke.sh` | Apple Silicon + iOS 18 Simulator + archive | prepare、boot、命令边界和固定 shutdown 行为 | 真机、Xcode 16 或发行可用 |
| 物理设备验证 | 手工/后续自动化 | 签名 iPhone/iPad | sandbox、lifecycle、memory 与实际硬件行为 | 合规与 App Review |
| 文档检查 | `./Scripts/check-docs.sh` | macOS/Linux shell | 中英文成对、中文覆盖和相对链接 | 技术实现正确 |

## 2. 宿主 Swift Package 测试

```bash
./Scripts/test.sh
```

等价于：

```bash
swift test
```

主要覆盖：

### PocketRootCoreTests

- command request/configuration 默认值和 command result stream 解码；
- placeholder boot/execute/shutdown；
- injected runtime 委托，以及 execute 失败关闭、shutdown 失败后的公开状态同步、重入命令不泄漏过渡态和旧快照不能覆盖较新失败状态；
- RootFS manager 必须有 provider 以及 prepared metadata 保存。

### PocketRootResourcesTests

- 固定 manifest 与受门禁的 bundled provider；
- archive 存在性、symlink 拒绝、字节数和 SHA-256；
- fakefs 所需 `meta.db` / `data` 布局以及 metadata symlink 拒绝；
- gzip/ustar 正常解包、path traversal 清理、显式/隐式父目录重复以及大小写不敏感卷上的目录别名拒绝、archive symlink entry/源路径拒绝和 expanded-byte 上限；
- 用合成 fixture 验证首次安装与复用、私有 archive snapshot 隔离与字节上限；
- 用合成 fixture 验证保留名版本、损坏版本替换、失败升级/提升回滚、中断事务恢复和并发时只安装一次；
- 可选的精确 release asset 首次物化。

### PocketRootIshRuntimeTests

通过 injected driver 测试，不链接 native iOS binary：

- 默认配置和 macOS native-slice 可用性 fallback；
- 缺失 fakefs、symlinked `meta.db` 和文件属性读取失败的 typed boot 预检，且失败不占用进程槽位；
- boot options 以及 `/bin/sh -lc` 命令的 cwd、environment、stderr merge、stream、exit 和 signal 映射；
- boot 前 execute 拒绝、timeout 边界校验和亚毫秒 clamp、含 NUL/歧义环境 key 的请求拒绝；
- process-global ownership（含不同 UUID 的直接 claim/ownership 拒绝）、native boot 失败后占用槽位、并发 boot/reentrancy；
- 默认/自定义 manifest 的健康配置选择，post-boot identity request、错误架构/OS/版本/cwd、规范化 cwd 别名、timeout、signal/exit、output limit、无效 UTF-8、重复 os-release 键、畸形 NUL framing，以及无效配置、相对 cwd、含 NUL supervisor 路径不占槽位；
- active one-shot command 与 shutdown 顺序、output-limit error 映射、supervisor 负数合成状态保留来源且保持 ready、共享 process gate 的退出无法确认失败关闭、terminal spawn transport error 映射，以及固定 transport 歧义 broken-pipe marker 拒绝；
- injected-driver shutdown 后的 terminated / `restartRequired` contract。

### Integration 与 Terminal tests

- RootFS/runtime configuration 对齐；
- prepare 不自动 boot；
- terminal placeholder 配置、theme、transcript 与 clear 行为。

普通 `swift test` 没有 `POCKETROOT_ROOTFS_ARCHIVE` 时，会 skip 精确 release archive 用例；这不是失败。安装复用、替换、回滚和并发路径由合成 fixture 测试覆盖。

## 3. 严格并发与警告

在涉及 public Sendable、actor 或 native executor 的改动中额外运行：

```bash
swift build \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors
```

Package manifest 仍保持 Swift 5.10 兼容基线；这个命令用于提前暴露更严格的并发问题。

## 4. 真实 release asset 测试

先根据 [RootFS 安全方案](RootFS.md)独立确认本地 archive。

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment
```

该用例要求：

- 6,581,376 字节；
- 固定 SHA-256；
- 能通过安全 extractor；
- 结果是有效 fakefs；
- installation record 与首次物化路径正确。

该 filtered test 每次使用新的临时安装目录，只断言真实 release asset 的首次物化，不断言第二次准备的复用。复用行为由 `testRootFSInstallerInstallsThenReusesVerifiedVersion` 等合成 fixture 用例覆盖。测试读取本地路径，不由 library 下载。

## 5. 默认 Demo 构建

```bash
./Scripts/bootstrap.sh
./Scripts/build.sh
```

`build.sh` 目标：

- project：`PocketRootDemo.xcodeproj`；
- scheme：`PocketRootDemo`；
- destination：`generic/platform=iOS Simulator`；
- code signing：关闭。

它验证默认安全伞形产品和 UIKit 层。因为 Demo 没依赖 `PocketRootIshRuntimeIntegration`，不能用该结果声称 IshEmbed 已最终链接。

## 6. 完整实验依赖图最终链接

```bash
./Scripts/build-runtime-spike.sh
```

脚本生成工程，并构建 `PocketRootIshRuntimeCompileSpike`：

1. `generic/platform=iOS Simulator`，强制 `ARCHS=arm64`；
2. `generic/platform=iOS`，强制 `ARCHS=arm64`、关闭 code signing。

最终可执行 App 包含：

- `PocketRootIshRuntimeIntegration`；
- `PocketRootIshRuntime`；
- `PocketRootResources`；
- zlib 与 sqlite3；
- IshEmbed；
- IshKernel XCFramework。

这一步区别于只生成 static archive，能发现 unresolved native symbol 和缺失 slice。unsigned device link 仍不等于签名真机执行。

## 7. 原生 iOS 18 Simulator smoke

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh
```

或：

```bash
./Scripts/run-runtime-smoke.sh /path/to/fs.tar.gz
```

环境要求：

- Apple Silicon；
- 已安装 iOS 18 Simulator runtime；
- 固定 v0.3.3 archive；
- `xcodegen` 和 Xcode CLI 可用。

可选变量：

| 变量 | 作用 |
| --- | --- |
| `POCKETROOT_ROOTFS_ARCHIVE` | archive 路径；也可使用第一个参数 |
| `POCKETROOT_SMOKE_DEVICE` | 指定现有 Simulator UDID |
| `POCKETROOT_SMOKE_TIMEOUT_SECONDS` | 启动 App 后等待 JSON report 的秒数，默认 300；不含工程生成、构建、Simulator boot 和 report 后固定 20 秒进程退出检查 |
| `POCKETROOT_KEEP_SIMULATOR` | 设为 `1` 时保留脚本创建的临时 Simulator |

未指定设备时，脚本创建临时 iPhone 16 Simulator，构建、安装和启动 smoke
App，把 archive 注入 Documents，等待 JSON report，并在脚本退出时（成功或失败）删除临时
设备（除非显式保留）。指定已有 Simulator 时，脚本会启动它并在运行前卸载
旧 smoke App、安装新版本；结束时只终止运行中的 App，不卸载新 App、不删除
注入数据，也不恢复设备原来的开关机状态。

自动创建设备时，脚本从 `simctl list runtimes available` 的整行中识别稳定的
`com.apple.CoreSimulator.SimRuntime.iOS-18-*` 标识，不依赖其列位置；fixture 回归测试覆盖
标准输出、带 `(available)` 后缀、多运行时和无匹配四种格式。

要从指定的已有设备中安全清理 smoke App 及其数据，使用精确 UDID：

```bash
SMOKE_DEVICE_UDID="paste-exact-udid-here"
xcrun simctl terminate "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke || true
xcrun simctl uninstall "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke
```

如果该设备在执行 smoke 前是关机状态，可再手工恢复：

```bash
xcrun simctl shutdown "$SMOKE_DEVICE_UDID"
```

只有在确认某个 UDID 对应脚本专用临时设备时，才对它执行 `simctl delete`；不要删除共享的开发 Simulator。

### 13 项检查

1. 安装固定 v0.3.3 RootFS；
2. boot 到 `ready`；
3. `/bin/uname -m` 返回 `aarch64`；
4. `/etc/alpine-release` 返回 `3.19.1`；
5. command working directory 为 `/`；
6. environment 正确传入；
7. stdout/stderr 分离且 exit code 7 保留；
8. stderr merge 正确；
9. 100 ms timeout；
10. timeout 后下一条命令成功；
11. 64-byte stdout limit；
12. output-limit termination 后下一条命令成功；
13. shutdown 请求触发宿主 App 进程退出。

第 9 项证明已经建立的 session 在 event-read loop 中观察到 deadline 后可以恢复；它不覆盖此前的同步 spawn/control write，也不证明 terminate/close 具有相同端到端硬时限。该缺口在[路线图](Roadmap.md)中作为原生 control path 门禁维护。

最后一项先原子写入 report，再调用 native shutdown。host 脚本要求 attached `simctl --console` 进程在限定时间内以成功状态结束，因此普通 crash 不能冒充通过。

该 smoke 是仓库维护的本地门禁，不在 GitHub Actions 中运行。

## 8. GitHub Actions

`.github/workflows/ci.yml` 在 macOS runner 上：

1. 使用固定 revision 的 `actions/checkout` action，由它检出当前 workflow 事件的 commit SHA（push SHA 或 PR merge SHA）；
2. 运行 `./Scripts/check-docs.sh`；
3. 报告 Xcode、Swift 和 iOS Simulator SDK；
4. 运行 `swift test`；
5. 下载精确 v0.3.3 archive；
6. 先检查字节数和 SHA-256；
7. 运行真实资产 filtered test；
8. 下载固定 XcodeGen 版本并校验 SHA-256；
9. 生成 Xcode 工程；
10. 构建默认 Demo；
11. 最终链接 arm64 Simulator runtime App；
12. 最终链接 unsigned arm64 device runtime App。

CI 不执行原生 boot，不证明真机，也不取代本地 smoke。

## 9. 改动与最小验证矩阵

| 改动 | 必须运行 |
| --- | --- |
| Core public API 或 actor | `swift test` + strict concurrency build |
| RootFS manifest/validator/extractor/installer | `swift test` + 真实 archive test + runtime final-link + native smoke |
| IshRuntime lifecycle/command/driver | `swift test` + strict build + runtime final-link + native smoke |
| Package.swift 或 native dependency | `swift test` + Demo build + 两个 arm64 final-link + native smoke |
| project.yml 或 Demo | regenerate + Demo build |
| smoke App/runner | shell syntax + 实际 smoke |
| terminal placeholder | terminal tests + Demo build |
| PTY/SwiftTerm（未来） | unit + final-link + Simulator + signed iPhone/iPad lifecycle |
| 文档 | `./Scripts/check-docs.sh` |
| 上游 revision/RootFS | 全部测试 + 供应链与合规重审 |

## 10. 真机门禁

正式宣称 device 可用前至少记录：

- Xcode 与 iOS 版本；
- iPhone 与 iPad 型号；
- 签名和 entitlement；
- cold boot；
- prepare/reuse/corruption recovery；
- guest architecture 与版本；
- command streams、timeout、limit；
- foreground/background；
- low-memory/jetsam；
- failed boot recovery；
- shutdown 产品契约；
- storage pressure 与 ENOSPC；
- 测试日志和制品 hash。

当前未完成项以[路线图](Roadmap.md)为准。

## 11. 结果表达规则

可以说：

- “Swift Package tests 通过”；
- “完整图在 arm64 Simulator/device destination 最终链接”；
- “iOS 18.2 arm64 Simulator smoke 通过”。

不能由这些结果推导：

- “支持所有 Simulator”；
- “Xcode 16 原生行为已验证”；
- “已在 iPhone/iPad 真机运行”；
- “可以 TestFlight/生产分发”；
- “App Store 审核一定通过”。

每项结论必须附带实际环境和未覆盖边界。
