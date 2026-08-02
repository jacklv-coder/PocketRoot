# 快速开始

[简体中文](GettingStarted.md) | [English](en/GettingStarted.md) | [文档中心](README.md)

本指南帮助开发者从空目录完成源码获取、依赖解析、测试、Demo 构建和实验性运行时最终链接。真正启动 iSH 需要额外准备经过审核的本地 RootFS，普通 Demo 构建不需要该资产。

## 1. 确认开发环境

最低声明：

- Xcode 16.0 或更高版本
- iOS 18 SDK
- Swift 5.10 或更高版本
- macOS 开发机
- XcodeGen
- Homebrew（`bootstrap.sh` 在缺少 XcodeGen 时会调用它）

检查：

```bash
xcode-select -p
xcodebuild -version
swift --version
xcrun --sdk iphonesimulator --show-sdk-version
```

原生 IshEmbed 只有 arm64 iOS 真机和 arm64 Simulator 切片。Intel Mac、Rosetta 下的 x86_64 Simulator 和 macOS 进程不能运行真实 guest。链接实验产品的 App target 必须预先排除 x86_64 Simulator；运行时 `isAvailable` 无法绕过 SwiftPM 在链接前选择不到切片的问题。普通 Swift Package 宿主测试仍可在声明的 macOS 13 基线上运行。

## 2. 获取源码

```bash
git clone git@github.com:jacklv-coder/PocketRoot.git
cd PocketRoot
```

项目的 Git 远端使用 SSH。查看当前分支和远端：

```bash
git status -sb
git remote -v
```

## 3. 初始化工程

推荐：

```bash
./Scripts/bootstrap.sh
```

脚本会：

1. 检查 `xcodegen`，缺少时执行 `brew install xcodegen`。
2. 执行 `swift package resolve`。
3. 根据各自的 `project.yml` 生成完整 Demo 和两入口 Quick Start：
   `Examples/PocketRootDemo/PocketRootDemo.xcodeproj` 与
   `Examples/PocketRootQuickStartApp/PocketRootQuickStartApp.xcodeproj`。

只重新生成工程时使用：

```bash
./Scripts/generate-project.sh
```

不要手工维护 `project.pbxproj`。生成的 `.xcodeproj` 已被 `.gitignore` 忽略，
所有 target、scheme、依赖和 deployment target 变更都应写入对应示例的
`project.yml`。

## 4. 运行基础验证

```bash
./Scripts/test.sh
./Scripts/build.sh
```

- `test.sh` 执行所有 Swift Package 宿主测试。没有设置 RootFS 环境变量时，真实 release asset 用例会 skip；安装复用等路径仍由合成 fixture 测试覆盖。
- `build.sh` 构建 arm64 `PocketRootDemo` scheme；未配置 RootFS 时只完成最终链接，不启动 guest。

打开工程：

```bash
open Examples/PocketRootQuickStartApp/PocketRootQuickStartApp.xcodeproj
open Examples/PocketRootDemo/PocketRootDemo.xcodeproj
```

首次验证业务接入时运行 `PocketRootQuickStartApp`：首页只有 Terminal 和 Files
两个入口，两者都会自动准备并启动 runtime。需要查看完整诊断与底层控制时再运行
`PocketRootDemo`。

## 5. 运行真实 Demo

Demo 使用 AppDelegate、SceneDelegate、UIWindow、纯 UIKit 和 Auto Layout，包含五个 tab：

| 页面 | 当前用途 |
| --- | --- |
| System | 校验、安装固定 RootFS，启动/检查/关闭实验 runtime |
| Terminal | 使用 SwiftTerm 打开持续 PTY，默认提供 Esc/Tab/Ctrl-C/Ctrl-D/历史键；右上角也保留 Files 快捷入口 |
| Files | 浏览 `/root`；原地展开或进入目录，并创建、删除文件与目录 |
| Commands | 对同一个已启动 system 执行有界一次性命令 |
| Diagnostics | 动态显示 RootFS、iSH Runtime 与 SwiftTerm 状态 |

先把经过审核且匹配内置 v0.3.3 manifest 的归档配置到仓库外开发目录：

```bash
./Scripts/inject-demo-rootfs.sh \
  --install-development-archive /absolute/path/to/fs.tar.gz
```

该命令要求普通非符号链接文件、精确 `6,581,376` 字节和固定 SHA-256，并原子复制到
`~/Library/Application Support/PocketRootDevelopment/RootFS/`。随后重新构建并在
System 点击 **Prepare and Boot Runtime**。状态达到 `Ready` 后，Terminal 可执行
`ls`、`cd` 和文件创建；Files 右上角 `+` 可新建文件/目录，行菜单可确认删除。

也可只对一次命令行构建显式传入：

```bash
POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
  ./Scripts/build.sh
```

RootFS 缺失时 Demo 仍可编译，但显示 `RootFS Missing` 且禁用 Boot。注入仅允许
Debug；Release、TestFlight 和 App Store 分发仍由合规门禁阻止。自己的 App 接入方式
见[应用接入指南](IntegrationGuide.md)。

## 6. 验证实验性原生依赖图

对 iSH runtime、RootFS 或 Swift Package 边界做修改后运行：

```bash
./Scripts/build-runtime-spike.sh
```

脚本会重新生成工程，并把完整实验性依赖图最终链接为：

- arm64 generic iOS Simulator App；
- arm64 unsigned generic iOS device App。

成功只证明指定目标能够最终链接，不等于签名真机上已经启动 guest。

## 7. 可选：验证真实 RootFS release asset

首先根据[RootFS 安全方案](RootFS.md)获得并独立校验本地 `fs.tar.gz`。不要把归档复制到仓库或提交到 Git。

运行真实资产安装测试：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment
```

该 filtered test 使用新的临时目录，验证真实 release asset 的大小、哈希、解包布局和首次物化；它不执行第二次准备，因此不能单独证明复用。复用路径见[测试与验证](Testing.md#4-真实-release-asset-测试)。

运行 iOS 18 Simulator 原生 smoke：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh
```

也可以把归档路径作为第一个参数：

```bash
./Scripts/run-runtime-smoke.sh /path/to/fs.tar.gz
```

若要验证 `ish-arm64-pkg` 的仓库外本地双构建候选，不要修改内置 manifest，也不要把
archive 复制进仓库。把 `scripts/prepare-rootfs-candidate.sh --output` 生成的完整目录传给：

```bash
POCKETROOT_ROOTFS_CANDIDATE=/absolute/path/to/local-candidate \
  ./Scripts/run-runtime-smoke.sh
```

runner 会校验候选 JSON、receipt、identity、全部伴随摘要、精确 archive 路径以及
`distributionAuthorized=false`，再生成仅供 smoke App 使用的临时 manifest。该入口不会
下载、打包、上传或授权分发 RootFS，也不会更新正式 `.ishEmbedV0_3_3` manifest。

要求：

- Apple Silicon 宿主机；
- 可用的 iOS 18 Simulator runtime；
- 精确匹配 v0.3.3 大小和 SHA-256 的本地归档；
- 启动 App 后默认最多等待 JSON report 300 秒。

脚本默认创建临时 iPhone 16 Simulator，并在脚本退出时（成功或失败）删除该临时设备（除非
`POCKETROOT_KEEP_SIMULATOR=1`）。可以设置 `POCKETROOT_SMOKE_DEVICE`
指定现有设备；这种情况下脚本会启动设备并在运行前重装 smoke App，但结束
后不会卸载 App、删除注入数据或恢复原来的开关机状态。
`POCKETROOT_SMOKE_TIMEOUT_SECONDS` 只调整等待 JSON report 的时间，
不包含工程生成、构建、Simulator boot，也不会改变 report 之后固定 20 秒的 runner 清理检查。

对指定的现有设备，可用精确 UDID 卸载 smoke App 并一并删除其注入数据：

```bash
SMOKE_DEVICE_UDID="paste-exact-udid-here"
xcrun simctl uninstall "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke
```

如果 smoke 前设备是关机状态，再执行 `xcrun simctl shutdown "$SMOKE_DEVICE_UDID"` 恢复。不要对共享 Simulator 执行 `simctl delete`；详细清理边界见[测试与验证](Testing.md#7-原生-ios-18-simulator-smoke)。

详细覆盖见[测试与验证](Testing.md)。

在已配对、启用 Developer Mode 且具有 development provisioning 的 iOS 18+ 真机上运行同一套检查：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

本地候选的真机命令使用同一目录入口替代 `POCKETROOT_ROOTFS_ARCHIVE`：

```bash
POCKETROOT_ROOTFS_CANDIDATE=/absolute/path/to/local-candidate \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

`POCKETROOT_SMOKE_DEVICE` 可以使用 `devicectl` 接受的 CoreDevice UUID、硬件 UDID
或设备名；runner 会先验证它是 physical iOS device，再把解析出的硬件 UDID 传给
`xcodebuild`。真机 runner 默认在取回报告后卸载测试 App 和注入的 RootFS；设置
`POCKETROOT_KEEP_DEVICE_APP=1` 才会保留。不要把设备标识、provisioning profile
或本地报告提交到仓库。

需要验证真机进程暂停/恢复时，在同一命令增加
`POCKETROOT_SMOKE_LIFECYCLE=1`。runner 会在 runtime `.ready` 时按 PID 暂停
3 秒、恢复并要求新的 guest 命令成功；这不等价于 UIKit 前后台回调验证。

需要验证真实 UIKit 前后台回调时，改用互斥的
`POCKETROOT_SMOKE_UI_LIFECYCLE=1`。runner 会打开 Settings 使 App 进入后台，
再激活原进程，并要求 background、foreground、active 回调和新 guest 命令成功。

需要验证强制终止后的 RootFS/guest 数据恢复时，改用互斥的
`POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1`。runner 会在 guest 写入并同步标记后
强制终止第一个 App PID，再启动新 PID；新进程必须复用 RootFS、读回并清理标记，
随后完成标准命令、shutdown 与峰值内存门禁。

需要在不填满整台手机的前提下验证存储失败恢复时，改用互斥的
`POCKETROOT_SMOKE_STORAGE_FAILURE=1`。App 先固定注入 0 可用字节的容量预检，
再在 gzip 输出 1 字节后注入 ENOSPC；两次失败都必须清空 staging/事务残留，
随后在同一目录正常安装、boot 并完成标准 smoke。

需要验证公开 `UIApplicationDelegate` 内存警告回调到达时 runtime 的有界恢复时，
改用互斥的 `POCKETROOT_SMOKE_MEMORY_WARNING=1`。repository smoke 会在一条 guest
命令执行期间确定性调用 App delegate 回调，要求新鲜回调证据、运行中命令和后续命令
都成功，runtime 仍为 `.ready`。这不会制造真实内存压力，也不等价于 jetsam。

需要验证持续执行稳定性时，改用互斥的 `POCKETROOT_SMOKE_LONG_WORKLOAD=1`，并把
`POCKETROOT_SMOKE_TIMEOUT_SECONDS` 设为至少 `600`。该模式执行 90 次间隔 2 秒的
命令/文件写读循环，每 10 次校验 64 KiB 二进制输出，最后通过 Files API 预览完整
标记文件并执行 shutdown 与 256 MiB 峰值门禁。它是约 3 分钟的有界基线，不制造
真实内存压力，也不等价于长期后台执行或 jetsam。

## 8. 常用命令

| 目标 | 命令 |
| --- | --- |
| 解析依赖并生成工程 | `./Scripts/bootstrap.sh` |
| 仅生成 Xcode 工程 | `./Scripts/generate-project.sh` |
| Swift Package 测试 | `./Scripts/test.sh` |
| 构建默认 Demo | `./Scripts/build.sh` |
| 最终链接实验性 runtime | `./Scripts/build-runtime-spike.sh` |
| 真实 RootFS 集成测试 | `POCKETROOT_ROOTFS_ARCHIVE=... swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment` |
| iOS 18 原生 smoke | `POCKETROOT_ROOTFS_ARCHIVE=... ./Scripts/run-runtime-smoke.sh` |
| development-signed archive 扫描 | `POCKETROOT_DEVELOPMENT_TEAM=... POCKETROOT_SIGNED_ARCHIVE_OUTPUT=/absolute/new/output POCKETROOT_SPDX_SCHEMA=/absolute/schema.json ./Scripts/build-signed-engineering-archive.sh` |
| 签名真机原生 smoke | `POCKETROOT_ROOTFS_ARCHIVE=... POCKETROOT_SMOKE_DEVICE=... POCKETROOT_DEVELOPMENT_TEAM=... ./Scripts/run-runtime-device-smoke.sh` |
| 签名真机暂停/恢复 smoke | `POCKETROOT_SMOKE_LIFECYCLE=1` 加到签名真机 smoke 命令 |
| 签名真机 UIKit lifecycle smoke | `POCKETROOT_SMOKE_UI_LIFECYCLE=1` 加到签名真机 smoke 命令 |
| 签名真机强制重启持久化 smoke | `POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1` 加到签名真机 smoke 命令 |
| 签名真机受限存储故障 smoke | `POCKETROOT_SMOKE_STORAGE_FAILURE=1` 加到签名真机 smoke 命令 |
| 签名真机有界内存警告 smoke | `POCKETROOT_SMOKE_MEMORY_WARNING=1` 加到签名真机 smoke 命令 |
| 签名真机持续负载 smoke | `POCKETROOT_SMOKE_LONG_WORKLOAD=1 POCKETROOT_SMOKE_TIMEOUT_SECONDS=600` 加到签名真机 smoke 命令 |
| 双语文档和链接检查 | `./Scripts/check-docs.sh` |

## 9. 不应提交的本地内容

- `Examples/PocketRootDemo/PocketRootDemo.xcodeproj/`
- `.build/`、`.swiftpm/`、`DerivedData/`
- RootFS `fs.tar.gz` 或解包后的 fakefs
- 本地 smoke 报告
- 签名证书、provisioning profile、token 或其他凭据

## 下一步

- [应用接入指南](IntegrationGuide.md)
- [架构说明](Architecture.md)
- [测试与验证](Testing.md)
- [故障排查](Troubleshooting.md)
