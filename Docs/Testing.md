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
| Simulator 原生 smoke | `./Scripts/run-runtime-smoke.sh` | Apple Silicon + iOS 18 Simulator + archive | prepare、boot、命令边界和 soft shutdown 返回 | 其他工具链、真机或发行可用 |
| 物理设备原生 smoke | `./Scripts/run-runtime-device-smoke.sh` | 签名 iOS 18+ iPhone/iPad + archive | 同一 17 项检查、可选进程暂停/恢复、UIKit 前后台、强制重启持久化、受限存储故障或有界内存警告恢复，development entitlement 与 shutdown 返回 | 真实 storage/memory pressure、断电、jetsam、iPad 或发行可用 |
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
- 验证缺失 base directory 被拒绝，mode `000` 文件/目录在持久化后恢复原权限，且同版本
  损坏替换能清除受限权限 backup/transaction；
- 用合成 fixture 验证容量不足在 staging 前拒绝、刚好满足容量预算、自定义 extractor
  较大上限、低空间升级保留旧版本；
- 用合成 fixture 在 snapshot、gzip 部分输出、tar payload、安装记录、promotion
  journal、`current.json` 和两个破坏性 promotion checkpoint 注入 ENOSPC，验证部分
  gzip 输出删除、staging/transaction 清理、旧安装保留和 current 数据回滚；
- 在候选树、journal 文件/目录、旧版本 rename、新候选 rename 和 current 文件/目录七个
  持久化屏障注入 I/O failure，并构造 journal-only、backup、candidate/final 掉电切点；
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
- 活动命令取消后保持 ready、取消清理失败时 fail-close，以及已取消的排队命令不进入
  native driver；
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

### 17 项检查

1. 安装固定 v0.3.3 RootFS；
2. boot 到 `ready`；
3. `/bin/uname -m` 返回 `aarch64`；
4. `/etc/alpine-release` 返回 `3.19.1`；
5. command working directory 为 `/`；
6. environment 正确传入；
7. stdout/stderr 分离且 exit code 7 保留；
8. stderr merge 正确；
9. 单条命令产生 8 MiB 二进制 stdout，跨越 4 MiB native backlog 后字节数与内容仍精确；
10. 100 ms timeout；
11. timeout 后下一条命令成功；
12. 再输出 64 KiB 时触发 8 MiB stdout limit；
13. 64-byte stderr limit；该命令成功进入 native 也证明 stdout 超限后已恢复；
14. stderr output-limit termination 后下一条命令成功；
15. 取消阻塞中的 `sleep`，确认 native termination 后执行下一条命令成功；
16. shutdown 返回 Swift，状态变为 `.terminated`，随后命令得到 `restartRequired`；
17. 完整 smoke 生命周期的进程 `ru_maxrss` 不超过 256 MiB，随后 App 主动成功结束。

真机设置 `POCKETROOT_SMOKE_LIFECYCLE=1` 时增加第 18 项：runtime 为 `.ready` 时，
host 按 launch 返回的 PID 暂停 App 进程 3 秒，再恢复并写入一次性继续标记；App 必须
执行新的 guest 命令、保持 `.ready`，随后完成同一 shutdown/peak-memory 门禁。这是
进程级 suspend/resume 证据，不等价于 UIKit foreground/background 回调。

真机改设互斥的 `POCKETROOT_SMOKE_UI_LIFECYCLE=1` 时，第 18 项验证真实 UIKit
生命周期：host 打开 Settings 使 App 后台化，等待 `applicationDidEnterBackground`，
再激活原 PID，并要求 `applicationWillEnterForeground`、`applicationDidBecomeActive`
按序到达；随后新 guest 命令、`.ready`、shutdown 和 peak-memory 门禁都必须成功。

真机改设互斥的 `POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1` 时，第 18 项验证强制
重启持久化。第一进程在 guest 写入固定标记并执行 `sync`，host 只在收到新检查点后
按 PID 发送 SIGKILL；第二次 launch 必须返回不同 PID，安装器必须报告复用现有 RootFS，
guest 标记必须可读且可清理，然后继续完成标准命令、shutdown 和 peak-memory 门禁。
host 会在第二次 launch 前再次清空 report/progress，旧证据不能冒充通过。

真机改设互斥的 `POCKETROOT_SMOKE_STORAGE_FAILURE=1` 时增加两项，共 19 项。
第 1 项把安装器可用容量固定为 0，要求在 staging 前返回类型化
`insufficientStorage`；第 2 项复用真实 snapshot/gzip 路径，但固定在 gzip 输出
1 字节后返回 ENOSPC。每次失败后 `rootfs/` 必须为空，随后同一目录正常安装、
boot 并完成标准 17 项。这是受限故障注入，不会填满整台设备，也不等价于真实
storage pressure 或物理断电。

真机改设互斥的 `POCKETROOT_SMOKE_MEMORY_WARNING=1` 时增加第 18 项。App 在一条
guest 命令执行期间确定性调用公开
`UIApplicationDelegate.applicationDidReceiveMemoryWarning(_:)` 回调；检查必须看到
新鲜回调文件、运行中命令完整输出、后续新命令成功和 runtime `.ready`，然后完成
相同 shutdown/peak-memory 门禁。这是 repository-owned 回调注入，不会制造真实
memory pressure，也不能证明系统低内存通知、jetsam 或重启恢复。

第 9 项证明持续二进制输出可以被 Swift 持续消费，不会因 4 MiB native backlog
本身而截断或损坏。第 17 项在 Simulator 上约束包含 RootFS 准备、8 MiB 输出、
超限恢复、取消与 shutdown 的完整进程峰值；它不是物理设备 jetsam 证明。第 10 项
通过 ABI.6 finite SPAWN 路径运行，并证明统一 deadline 到期、确认 session `EXITED`
后仍可恢复。上游 deterministic lifecycle 测试另行覆盖 instance/spawn/control gate
过期与阻塞 writer 下的有界 close/terminate。

成功 report 只在 shutdown 返回、状态为 `.terminated` 且再次执行得到
`restartRequired` 后写入；host 脚本读取成功证据后主动停止空闲 smoke App 并等待
console client 结束。shutdown 前的 crash 不会产生成功 report，不能冒充通过。

该脚本既可作为仓库维护的本地门禁，也由最低工具链 GitHub Actions job 调用。

2026-07-24，`v0.4.0-abi.6` 与 wrapper revision `38d25d6` 在 iOS 18.2 arm64
Simulator 通过全部 17 项；8 MiB binary stdout 逐字节精确，完整生命周期峰值为
156.5 MiB（门限 256 MiB），shutdown
记录为 `returned, terminated, restart required`。

仓库的最低工具链 job 会在 arm64 macOS runner 上明确选择 Xcode 16.0 与 iOS 18.0
SDK，完成固定 RootFS 首次物化、arm64 Simulator/unsigned device final-link，并在
iOS 18.0 Simulator 执行同一套 17 项 native smoke。

### 签名 iPhone/iPad runner

物理设备 runner 使用明确的设备引用与 Apple team ID，避免误装到其他设备：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

在同一套门禁上增加真机进程暂停/恢复：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_LIFECYCLE=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

验证真实 UIKit 后台/前台回调时使用独立模式：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_UI_LIFECYCLE=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

验证强制终止后的 RootFS/guest 数据恢复时使用独立模式：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

验证不会填满设备的受限容量/ENOSPC 清理恢复时使用独立模式：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_STORAGE_FAILURE=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

验证不会制造真实内存压力的有界内存警告恢复时使用独立模式：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_MEMORY_WARNING=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

runner 接受 `devicectl` 可识别的 CoreDevice UUID、硬件 UDID 或设备名，先通过官方
JSON 输出验证 physical iOS 属性并解析硬件 UDID，再用于 `xcodebuild` 与后续
`devicectl` 操作。设备必须已配对、启用 Developer Mode 且能用 development profile
签名。runner 生成并签名 `PocketRootIshRuntimeSmoke`，验证 application identifier
与 `get-task-allow`，安装 App、把固定 archive 复制到 App data container 并取回
JSON report。标准、受限存储故障和有界内存警告模式使用 attached launch；三种互斥的
host-control 模式使用 launch
JSON 返回的 PID。进程模式驱动 suspend/resume；UIKit 模式打开 Settings 后重新激活
同一 PID；强制重启持久化模式终止 seed PID 并要求 verify PID 不同。默认结束后终止
进程、卸载 smoke App 并删除其 RootFS 数据；只有显式设置
`POCKETROOT_KEEP_DEVICE_APP=1` 才保留 App。

2026-07-24 使用 Xcode 26.1.1、签名 iPhone 17 Pro / iOS 26.1、development
provisioning 和 v0.4.0-abi.6 runtime pin 完成重跑。设备生成的 `success: true`
报告通过全部 17 项；8 MiB binary stdout 逐字节一致，timeout/output-limit/cancellation
后均恢复，soft shutdown 记录为 `returned, terminated, restart required`，完整生命周期
峰值为 84.6 MiB（门禁 256 MiB）。仓库不提交设备标识、profile 或本地报告。这关闭
当前 signed iPhone one-shot/soft-shutdown/peak-memory smoke 基线，不代表 iPad、
foreground/background、真机 jetsam、storage pressure 或强制断电门禁完成。

同日，“Jack iPhone”（iPhone 14 Pro / iOS 26.6）通过标准 17 项和进程暂停/恢复
18 项两条路径。暂停 3 秒后 runtime 保持 `.ready` 且新 guest 命令成功；生命周期
模式峰值 89.7 MiB，标准模式峰值 89.8 MiB。这个结果证明 process suspend/resume
恢复，不声明 UIKit foreground/background、jetsam 或长期后台执行已通过。

随后同一 Jack iPhone 通过真实 UIKit 18 项路径：Settings 触发后台回调，重新激活
保持原 PID，foreground/active 回调按序到达，新 guest 命令成功，峰值 89.4 MiB。
公共 runner 重构后，标准 17 项和进程暂停/恢复 18 项也分别以 82.7 MiB 回归通过。
这些结果仍不声明 jetsam、memory warning、长期后台执行或 iPad 已通过。

2026-07-25，同一 Jack iPhone 通过强制重启持久化 18 项路径：seed 进程在 guest
写入并 `sync` 标记后被 host 按 PID 发送 SIGKILL，verify 进程使用不同 PID、报告
复用现有 RootFS、读回并清理标记，随后完成全部标准命令与 soft shutdown；峰值
51.8 MiB。
同次公共 runner 回归中，标准 17 项、进程暂停/恢复 18 项和 UIKit 18 项分别以
90.2、89.9、87.1 MiB 通过。这证明同步 guest 数据可跨强制 App 终止恢复，不声明
jetsam、storage pressure、真实强制断电或 iPad 已通过。

同日，同一 Jack iPhone 通过受限存储故障 19 项路径：容量预检以 0 可用字节在
staging 前拒绝，gzip 在输出 1 字节后返回 ENOSPC；两次失败后 `rootfs/` 均无残留，
随后同一目录正常安装、boot、完成标准命令与 soft shutdown，峰值 91.2 MiB。
这证明生产安装/解压路径在真机容器内的受限容量与 ENOSPC 清理恢复，不证明整机
磁盘接近耗尽、真实 storage pressure、物理强制断电或 iPad。

同日，同一 Jack iPhone 通过有界内存警告 18 项路径：guest 先写入 fresh 启动确认
标记，公开 App delegate 回调随后在该命令执行期间被确定性调用；新鲜回调证据、
运行中命令、后续命令、
`.ready`、soft shutdown 和 256 MiB 峰值门禁全部通过，峰值 90.8 MiB；同次默认
17 项回归也以 89.9 MiB 通过。该结果只证明 repository 回调注入下的 runtime
连续性，不证明真实 memory pressure、系统低内存通知或 jetsam。

## 8. GitHub Actions

`.github/workflows/ci.yml` 的标准 job 在 macOS runner 上：

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

最低工具链 job 另外固定选择 Xcode 16.0 / iOS 18.0 SDK，验证真实 RootFS install、
安装 iOS 18.0 Simulator runtime、完成 Simulator/device final-link，并执行 17 项原生
smoke。CI 的 Simulator 结果不证明签名真机或发行可用。

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

当前 signed iPhone 一次性命令、进程暂停/恢复、UIKit 前后台与强制重启持久化基线
已通过；iPad 与其余 resource 项仍以[路线图](Roadmap.md)为准。

## 11. 结果表达规则

可以说：

- “Swift Package tests 通过”；
- “完整图在 arm64 Simulator/device destination 最终链接”；
- “iOS 18.2 arm64 Simulator smoke 通过”；
- “Xcode 16.0 / iOS 18.0 SDK 完成 RootFS install、两个 final-link 和 17 项 smoke”；
- “iPhone 17 Pro / iOS 26.1 signed one-shot smoke 通过”。
- “Jack iPhone（iPhone 14 Pro / iOS 26.6）通过 18 项 process suspend/resume smoke”。
- “Jack iPhone（iPhone 14 Pro / iOS 26.6）通过 18 项真实 UIKit lifecycle smoke”。
- “Jack iPhone（iPhone 14 Pro / iOS 26.6）通过 18 项强制重启持久化 smoke”。
- “Jack iPhone（iPhone 14 Pro / iOS 26.6）通过 19 项受限存储故障恢复 smoke”。
- “Jack iPhone（iPhone 14 Pro / iOS 26.6）通过 18 项有界内存警告恢复 smoke”。

不能由这些结果推导：

- “支持所有 Simulator”；
- “已完成 iPad 或完整真机 lifecycle”；
- “可以 TestFlight/生产分发”；
- “App Store 审核一定通过”。

每项结论必须附带实际环境和未覆盖边界。
