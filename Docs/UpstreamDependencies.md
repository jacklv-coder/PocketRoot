# 上游依赖与制品清单

[简体中文](UpstreamDependencies.md) | [English](en/UpstreamDependencies.md) | [文档中心](README.md)

本文是 PocketRoot 实验性 runtime 的不可变 revision、nested gitlink、制品 URL、大小和
SHA-256 的唯一事实源。branch、moving tag、未验证 release alias 和本地缓存都不是有效 pin。

审核日期：2026-07-24

## 1. IshEmbed Swift Package

| 字段 | 审核值 |
| --- | --- |
| 仓库 | `https://github.com/jacklv-coder/ish-arm64-pkg.git` |
| 完整 wrapper revision | `fe4ed63331a7e72f1d12f69296cd3c07231a4f0e` |
| Release | `v0.4.0-abi.5`（prerelease） |
| Tag peeled commit | `bcbf8ddb3ee855cd119050a9e16b55dbfe8ceec6` |
| Swift product | `IshEmbed` |
| Manifest platform | iOS 18.0 |
| Native slices | iOS arm64 device、arm64 Simulator |
| 系统链接依赖 | `sqlite3` |

`Package.swift` 与 `Package.resolved` 都固定完整 revision：

```swift
.package(
    url: "https://github.com/jacklv-coder/ish-arm64-pkg.git",
    revision: "fe4ed63331a7e72f1d12f69296cd3c07231a4f0e"
)
```

消费 revision `fe4ed63331a7e72f1d12f69296cd3c07231a4f0e` 在已发布 ABI.5
manifest 之上加入 source-only Swift deadline 修复：wrapper 从 API 入口保留绝对
budget，在 argv/env/cwd/chroot 封送后、紧贴 C 调用重新计算剩余毫秒，期限已耗尽时
不会进入 native。该 revision 的 `Package.swift` 仍通过同一 URL/checksum 固定公开且
独立验证的 ABI.5 资产；Release tag peeled commit 与 Release target 仍是
`bcbf8ddb3ee855cd119050a9e16b55dbfe8ceec6`。包仓库继续使用绝对 SSH-over-443
submodule URL；无 SSH 私钥的 GitHub CI 只在 checkout 时应用公开 HTTPS 只读重写。

## 2. iSH source gitlink

| 字段 | 审核值 |
| --- | --- |
| 仓库 | `https://github.com/jacklv-coder/ish-arm64.git` |
| Package 内路径 | `third_party/ish` |
| 完整 gitlink | `c36dfd25462737b45559eb48d4b09f799471572e` |
| 记录 branch | `embed-chroot-containment` |

对应源码归档记录 parent package revision、该 gitlink、Zig `0.16.0` 与静态 supervisor
使用的 musl 源码。重建不能用 recursive branch checkout 代替这些精确身份。

## 3. v0.4.0-abi.5 发布资产

Release：
`https://github.com/jacklv-coder/ish-arm64-pkg/releases/tag/v0.4.0-abi.5`

| Artifact | 大小 | SHA-256 | 用途 |
| --- | ---: | --- | --- |
| `libIshKernel.xcframework.zip` | 2,450,634 bytes | `9a6a2a68dd186ce81c841087fb132e08f22cd3c09e4242b4f3c903e5a74550e0` | SwiftPM binary target |
| `IshEmbed-corresponding-source.tar.gz` | 2,362,436 bytes | `17c94f5199c11942d9c8ad0b370007ef01555c894dd0b5a37974dd5e4427e1e3` | 对应源码 |

XCFramework 只有 `ios-arm64` 和 `ios-arm64-simulator` 两个 arm64 slice，minimum OS
为 iOS 18.0；没有 x86_64 Simulator 或 macOS slice。SwiftPM 用 manifest checksum
验证 zip。发布事务还验证：

- tag peeled commit、Release target 与默认分支都等于精确发布提交；
- Release 为公开 prerelease、不是 draft，且只有上述两个资产；
- 从公开 URL 重新下载后，两项 digest 与发布记录一致；
- device/simulator Mach-O、ABI 符号与 iOS 18 最终链接；
- Package.swift binaryTarget 在 arm64 iOS Simulator 的 17 个测试中 12 个通过，
  5 个因未提供 RootFS 按预期 skip，0 failure。
- PocketRoot 完整实验依赖图在 arm64 Simulator 与 unsigned device 最终链接；
- iOS 18.2 Simulator 使用固定 v0.3.3 RootFS 通过 17 项 native smoke，其中 8 MiB
  二进制 stdout 跨越 backlog 后逐字节精确、阻塞命令取消后可恢复执行，shutdown
  返回 Swift、状态为 `.terminated`，后续命令得到 `restartRequired`，完整生命周期
  `ru_maxrss` 为 154.6 MiB、低于 256 MiB 门限。
- Xcode 16.0 / iOS 18.0 SDK 在 arm64 hosted runner 上完成真实 RootFS install、
  Simulator/device final-link，并通过同一套 17 项 native smoke。

本 Release **不包含 RootFS**。

## 4. 单独固定的 Alpine RootFS

PocketRoot 的内置 RootFS manifest 仍固定 parent `v0.3.3` 的 Alpine 3.19.1 aarch64
`fs.tar.gz`；更新 runtime/XCFramework 不会隐式替换 guest 文件系统：

| 字段 | 审核值 |
| --- | --- |
| URL | `https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/fs.tar.gz` |
| 大小 | 6,581,376 bytes |
| SHA-256 | `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4` |
| Guest identity | Alpine `3.19.1`、`aarch64` |

该 archive 含 fakefs `meta.db`、`data/`、旧 `/sbin/ishsv` 与 VM template。新 runtime
在默认配置下验证并安装自己内嵌、内容寻址的 supervisor，不会把 RootFS 当作新 Release
的一部分。RootFS 仍由调用方在本地提供；library 不下载、不提交也不打包它。

Node.js/npm 不在 runtime 或 RootFS 中默认预装，但可作为调用方明确安装的通用 guest
package。Codex CLI 不属于手机端架构，IshEmbed 不提供其安装、provision 或配置路径。

## 5. 当前行为与验证边界

新制品已经进入 PocketRoot pin，并提供：

- kernel soft-halt、bounded join，`shutdown()` 返回 Swift；
- embedded bootstrap 与 guest task 线程解除内部 SIGUSR1 屏蔽，使 guest signal
  可打断 `poll`、`nanosleep` 等阻塞宿主 syscall；
- 固定 65-byte `uname` 字段的有界复制，避免长宿主 hostname 触发 fortified libc
  `SIGTRAP`；同时包含 ABI.2 的 `/proc` 生命周期锁修复；
- 每宿主进程一次有效 boot/shutdown，成功关闭后仍必须重启宿主进程才能再次 boot；
- 类型化 supervisor/transport error；正常 guest `exit 17` 不再与 broken pipe 混淆；
- 每 session 4 MiB/4096 帧 native 输出积压上限；
- 4 MiB/256 帧 control 总预算与 lifecycle reserve；
- 有限 streaming timeout 从 native SPAWN API 入口覆盖 instance/spawn gate 与
  control-queue admission；stdin close/terminate 使用保持顺序的有界异步接纳；
- 有界 stdin/log 队列、完整 session close 与无法确认清理时的 instance fail-close；
- root `/proc` 在 supervisor 启动前挂载；
- 默认 bundled supervisor 的内容摘要验证。

PocketRoot 仍保持 Experimental。尚未闭环的门禁：

- physical iPad execution；
- interactive session 的 read/close 取消契约；
- 完整 PTY、resize、signal、interactive session 生命周期；
- sustained workload、峰值内存与 jetsam；
- RootFS license/NOTICE/SBOM/对应源码；
- App Store Review Guideline 2.5.2 结论。

## 6. 依赖更新流程

任何上游变化都必须：

1. 固定完整 package commit 与所有 nested gitlink；
2. 审查相对当前 revision 的 source diff；
3. 获得可证明 source correspondence 的 artifact；
4. 独立计算并记录 size/hash；
5. 检查全部 XCFramework slice、SDK 与 minimum deployment；
6. 在 arm64 iOS Simulator 和 unsigned device 完成最终链接；
7. 重跑 host tests、native smoke、shutdown/lifecycle 与错误路径；
8. 在可用的 physical iPhone/iPad 上重跑签名验证；
9. 更新 `Package.resolved`、测试、ADR、路线图和合规材料；
10. 在 CR、CI 与 P1/P2 清零后才合并。

任何 branch、moving tag、locally cached binary 或未记录 RootFS 都不能绕过该流程。
