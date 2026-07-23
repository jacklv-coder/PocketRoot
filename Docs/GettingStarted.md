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
3. 根据 `project.yml` 生成 `PocketRootDemo.xcodeproj`。

只重新生成工程时使用：

```bash
./Scripts/generate-project.sh
```

不要手工维护 `project.pbxproj`。生成的 `PocketRootDemo.xcodeproj` 已被 `.gitignore` 忽略，所有 target、scheme、依赖和 deployment target 变更都应写入 `project.yml`。

## 4. 运行基础验证

```bash
./Scripts/test.sh
./Scripts/build.sh
```

- `test.sh` 执行所有 Swift Package 宿主测试。没有设置 RootFS 环境变量时，真实 release asset 用例会 skip；安装复用等路径仍由合成 fixture 测试覆盖。
- `build.sh` 构建默认 `PocketRootDemo` scheme，目标是 generic iOS Simulator，不执行原生 guest。

打开工程：

```bash
open PocketRootDemo.xcodeproj
```

在 Xcode 中选择 `PocketRootDemo` scheme 和任意 iOS 18 Simulator 后运行。

## 5. 理解当前 Demo

Demo 使用 AppDelegate、SceneDelegate、UIWindow、纯 UIKit 和 Auto Layout，包含四个 tab：

| 页面 | 当前用途 |
| --- | --- |
| System | 展示 `PocketRootSystem.shared` 的占位启动/关闭状态 |
| Terminal | 展示终端 UI 外壳，尚未连接 PTY |
| Commands | 展示命令请求界面，但默认 shared system 没有真实 runtime |
| Diagnostics | 展示 RootFS、iSH 和 SwiftTerm 后续集成位置 |

因此看到 “Runtime is not installed yet” 或占位错误是当前设计，而不是构建失败。Demo target 只依赖安全的 `PocketRoot` 伞形产品，不依赖实验性的 `PocketRootIshRuntimeIntegration`。

若要在自己的 App 中运行真实命令，请继续阅读[应用接入指南](IntegrationGuide.md)。Demo 的真实运行时注入仍在[路线图](Roadmap.md)中。

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
POCKETROOT_SMOKE_DEVICE=<physical-device-udid> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

真机 runner 默认在取回报告后卸载测试 App 和注入的 RootFS；设置 `POCKETROOT_KEEP_DEVICE_APP=1` 才会保留。不要把 UDID、provisioning profile 或本地报告提交到仓库。

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
| 签名真机原生 smoke | `POCKETROOT_ROOTFS_ARCHIVE=... POCKETROOT_SMOKE_DEVICE=... POCKETROOT_DEVELOPMENT_TEAM=... ./Scripts/run-runtime-device-smoke.sh` |
| 双语文档和链接检查 | `./Scripts/check-docs.sh` |

## 9. 不应提交的本地内容

- `PocketRootDemo.xcodeproj/`
- `.build/`、`.swiftpm/`、`DerivedData/`
- RootFS `fs.tar.gz` 或解包后的 fakefs
- 本地 smoke 报告
- 签名证书、provisioning profile、token 或其他凭据

## 下一步

- [应用接入指南](IntegrationGuide.md)
- [架构说明](Architecture.md)
- [测试与验证](Testing.md)
- [故障排查](Troubleshooting.md)
