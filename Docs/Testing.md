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
| Simulator 原生 smoke | `./Scripts/run-runtime-smoke.sh` | Apple Silicon + iOS 18 Simulator + archive | prepare、boot、命令边界和 soft shutdown 返回 | 真机、Xcode 16 或发行可用 |
| 物理设备原生 smoke | `./Scripts/run-runtime-device-smoke.sh` | 签名 iOS 18+ iPhone/iPad + archive | 同一 13 项检查、development entitlement 与 shutdown 返回 | 完整 lifecycle、memory、iPad 或发行可用 |
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
- active one-shot command 与 shutdown 顺序、Swift output-limit 与 native byte/frame backlog error 映射、
  类型化 supervisor rejection 保留来源并保持 ready、guest exit 17 回归、负数
  `EXITED` 拒绝、共享 process gate 的退出无法确认失败关闭和 terminal spawn error 映射；
- injected-driver shutdown 后的 terminated / `restartRequired` contract。

### PocketRootAgentTests

- 首轮最终文本与 tool call 后续 response ID/call ID 回传；
- unknown tool 与普通 tool failure 的结构化恢复；
- 重复 response ID、跨轮重复 call ID 与同批重复 call ID 拒绝；
- 整批 call 预检先于任何 tool side effect；
- turn、tool call、用户输入、模型文本、ID/name、arguments 和 output 边界；
- 同一 runner 并发拒绝、最后一轮不执行无法回传结果的 tool；
- 配置、tool name 与 JSON object schema 校验。
- OpenAI 首轮与 `previous_response_id`/`function_call_output` 请求映射；
- Responses 文本、多个 function call、refusal、incomplete 与畸形 payload 解码；
- strict schema 本地预检、HTTPS endpoint、request/response body 上限；
- bearer credential 缺失/畸形/loader error 脱敏，非 2xx API error 映射且错误不含 token。

### PocketRootAgentRuntimeToolsTests

- strict command schema 与未知字段拒绝；
- command policy 拒绝不触发审批，审批拒绝不触发 runtime；
- 审批看到规范化后的最终 cwd、environment、timeout 与 stderr merge 请求；
- 整批工具级 preflight 在第一条副作用前拒绝后续畸形命令；
- command/cwd/environment/timeout/output 配额、UTF-8/Base64 结果与截断标记；
- 非协作审批返回后的取消不执行命令，非协作执行返回后的取消不回传成功。

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
| `POCKETROOT_SMOKE_TIMEOUT_SECONDS` | 启动 App 后等待 JSON report 的秒数，默认 300；不含工程生成、构建、Simulator boot 和 report 后固定 20 秒 runner 清理检查 |
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
13. shutdown 返回 Swift，状态变为 `.terminated`，随后 smoke App 主动成功结束。

第 9 项证明已经建立的 session 在 event-read loop 中观察到 deadline 后可以恢复；它不覆盖此前的同步 spawn/control write，也不证明 terminate/close 具有相同端到端硬时限。该缺口在[路线图](Roadmap.md)中作为原生 control path 门禁维护。

成功 report 只在 shutdown 返回、状态为 `.terminated` 且再次执行得到
`restartRequired` 后写入；host 脚本读取成功证据后主动停止空闲 smoke App 并等待
console client 结束。shutdown 前的 crash 不会产生成功 report，不能冒充通过。

2026-07-24，`v0.4.0-abi.3` 在 iOS 18.2 arm64 Simulator 通过全部 13 项；shutdown
记录为 `returned, terminated, restart required`。

该 smoke 是仓库维护的本地门禁，不在 GitHub Actions 中运行。

### 签名 iPhone/iPad runner

物理设备 runner 使用明确的设备 UDID 与 Apple team ID，避免误装到其他设备：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-udid> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

runner 要求设备已配对、启用 Developer Mode 且能用 development profile 签名。它生成并签名 `PocketRootIshRuntimeSmoke`，验证 application identifier 与 `get-task-allow`，通过 `devicectl` 安装 App、把固定 archive 复制到 App data container、attached launch 并取回 JSON report。默认结束后卸载 smoke App 并删除其 RootFS 数据；只有显式设置 `POCKETROOT_KEEP_DEVICE_APP=1` 才保留。

2026-07-23 的签名 iPhone 记录使用旧 v0.3.3 runtime 基线；它证明设备 runner、archive
与签名链路，但 runtime pin 变化后必须用 v0.4.0-abi.3 重跑，不能作为新 soft shutdown
的真机证据。

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
| Agent loop/model/tool contract | `swift test` + strict build + 文档检查 |
| Package.swift 或 native dependency | `swift test` + Demo build + 两个 arm64 final-link + native smoke |
| project.yml 或 Demo | regenerate + Demo build |
| smoke App/runner | shell syntax + Simulator smoke + 可用时 signed device smoke |
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

当前 signed iPhone 一次性命令基线已通过；iPad 与其余 lifecycle/resource 项仍以[路线图](Roadmap.md)为准。

## 11. 结果表达规则

可以说：

- “Swift Package tests 通过”；
- “完整图在 arm64 Simulator/device destination 最终链接”；
- “iOS 18.2 arm64 Simulator smoke 通过”。
- “iPhone 17 Pro / iOS 26.1 signed one-shot smoke 通过”。

不能由这些结果推导：

- “支持所有 Simulator”；
- “Xcode 16 原生行为已验证”；
- “已完成 iPad 或完整真机 lifecycle”；
- “可以 TestFlight/生产分发”；
- “App Store 审核一定通过”。

每项结论必须附带实际环境和未覆盖边界。
