# 上游依赖与制品清单

[简体中文](UpstreamDependencies.md) | [English](en/UpstreamDependencies.md) | [文档中心](README.md)

本文是 PocketRoot 实验性 runtime **不可变 revision、nested gitlink、制品 URL、大小和 SHA-256 的权威且唯一事实源**。其他文档为便于接入、安全核验或故障排查而复制的数值只是本文的引用快照；如有冲突，以本文和 committed manifest 为准。branch、未验证 tag、moving release alias 和本地缓存不能作为有效 pin。

审核日期：2026-07-21

## 1. IshEmbed Swift Package

| 字段 | 审核值 |
| --- | --- |
| 使用的仓库 | `https://github.com/jacklv-coder/ish-arm64-pkg.git` |
| Fork parent | `https://github.com/Lolendor/ish-arm64-pkg.git` |
| 完整 revision | `6f96f02c71830914c2a608258a26a8ef0833d026` |
| Parent release 对应 | `v0.3.3` peeled commit |
| 审核时 fork tags | 无 |
| 审核时 fork releases | 无 |
| Swift product | `IshEmbed` |
| Manifest platform | iOS 14、macOS 12 |
| 实际 native binary support | iOS arm64 device、arm64 Simulator |
| 系统链接依赖 | `sqlite3` |

`Package.swift` 使用完整 revision：

```swift
.package(
    url: "https://github.com/jacklv-coder/ish-arm64-pkg.git",
    revision: "6f96f02c71830914c2a608258a26a8ef0833d026"
)
```

该 revision 与 parent `v0.3.3` peeled commit 相同。审核时用户 fork 没有 tag 或 release，因此不能对该 fork 使用 `from: "0.3.3"`。

固定 fork 仍从 parent repository 的 `v0.3.3` GitHub Release 下载 binary target。fork Git source 并没有镜像 release asset，仓库内 release script 也硬编码 parent repository。当前依赖已固定，但尚未自托管。

## 2. iSH source submodule

| 字段 | 审核值 |
| --- | --- |
| 仓库 | `https://github.com/Lolendor/ish-arm64.git` |
| Package 内路径 | `third_party/ish` |
| 完整 gitlink | `2f075626049d989dc9ac350a35c09f0b18930ffc` |
| 记录 branch | `embed-chroot-containment` |

审核时记录 branch 已比固定 gitlink 前进两个 commit。那些 commit 不在 `v0.3.3` XCFramework 中，不能在没有新 source/binary audit 时替换。

iSH submodule 递归声明其他 source dependency，包括：

- `ish-app/libapps`；
- `libarchive/libarchive`；
- Linux headers submodule（配置 `update = none`）。

可复现 source archive 必须记录所有 gitlink，不能只做 recursive branch checkout。

## 3. Binary artifacts

Source release：

`https://github.com/Lolendor/ish-arm64-pkg/releases/tag/v0.3.3`

| Artifact | 审核大小 | SHA-256 | 用途 |
| --- | ---: | --- | --- |
| `libIshKernel.xcframework.zip` | 2,121,180 bytes | `f747c2e85c3b6082e102fb45aa62797f52146a3bc5eb1a0c386b74bc156d4fca` | SwiftPM binary target |
| `fs.tar.gz` | 6,581,376 bytes | `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4` | candidate fakefs seed |

XCFramework slice：

| Library identifier | 架构 | Platform variant | Binary minimum OS |
| --- | --- | --- | --- |
| `ios-arm64` | arm64 | iOS device | 14.0 |
| `ios-arm64-simulator` | arm64 | iOS Simulator | 14.0 |

没有 x86_64 Simulator 或 macOS library。object load command 记录 SDK 26.2。完整 consumer 在 Xcode 26.1.1、iOS 18 deployment target 上完成独立最终链接。

SwiftPM 校验 XCFramework checksum；PocketRoot 另外校验 RootFS。调用方、bundle 或 CI 提供的制品只要大小或 digest 不匹配 committed manifest，就 fail closed。

## 4. Alpine RootFS

审核 fakefs 基于 Alpine `3.19.1 aarch64`。build script 使用的官方 minirootfs：

```text
alpine-minirootfs-3.19.1-aarch64.tar.gz
SHA-256 7ef5eef3a5b1d198dfb1610cde1ef5b0755ff5d838fb1e5e1b9f42b59214820f
```

上游 build script 允许 `ALPINE_SHA256` 为空；这种配置只记录下载结果 digest，而不是验证预期值。任何 PocketRoot-controlled rebuild 必须显式设置并验证上述 digest，或经过独立审查的新 digest。

release archive 包含：

- fakefs `meta.db` 与 `data/`；
- guest `/sbin/ishsv` supervisor；
- `/srv/vms/.template` 下重复 VM template。

对审核后解包的 `meta.db` 执行 SQLite `PRAGMA integrity_check`，结果为 `ok`。当前 installer 每次安装不重复该检查；运行时内容真实性由固定 archive SHA-256 保证。

### Guest package 与许可证 family

| Components | 声明 license family |
| --- | --- |
| Alpine baselayout、apk-tools、BusyBox、scanelf | GPL-2.0-only |
| musl-utils | MIT、BSD-2-Clause、GPL-2.0-or-later |
| musl、Alpine keys | MIT/BSD variants |
| OpenSSL libraries | Apache-2.0 |
| CA certificate bundle | MPL-2.0、MIT |
| zlib | Zlib |

archive 不含完整 license bundle、NOTICE set 或 machine-readable SBOM。公开分发还必须提供适用 copyleft package 的对应源码。

build script 还会向 base filesystem 和 VM template 写入 public DNS resolver。产品集成必须在发行前决定：

- 保持该行为；
- runtime 动态派生 resolver；
- 或暴露用户控制策略。

## 5. 验证记录

对固定输入已完成：

- fork relationship 与 commit identity；
- release asset digest；
- XCFramework architecture 与 minimum version；
- 完整 PocketRoot integration graph 的 arm64 iOS 18 Simulator final link；
- 同一 graph 的 unsigned arm64 device final link；
- 真实 release archive validation、secure extraction、journal 保护的同卷 promotion 和 materialized fakefs validation；
- caller-path replacement isolation；
- promotion rollback；
- interrupted commit/rollback recovery；
- iOS 18.2 Simulator fakefs boot；
- repository-owned native adapter smoke。

native smoke 通过 13 项：

1. verified v0.3.3 RootFS preparation；
2. boot；
3. `aarch64`；
4. Alpine `3.19.1`；
5. working directory；
6. environment；
7. split stdout/stderr 与 exit 7；
8. merged stderr；
9. 100 ms timeout；
10. post-timeout recovery；
11. 64-byte stdout limit；
12. post-limit recovery；
13. process-terminal shutdown。

最后一项在 shutdown 前持久化 report；host script 确认固定 iSH `_exit(0)` 路径让 smoke App process 以成功状态结束。

详细测试语义只在[测试与验证](Testing.md)维护。

## 6. 尚未通过

- signed physical iPhone build 与 execution；
- physical iPad execution；
- host-process-safe native shutdown；
- 声明的 minimum Xcode 16 native final-link 与 behavior；
- 完整 PTY、signal、resize、cancellation 与 shutdown lifecycle；
- sustained workload memory 与 jetsam；
- 完整 license/NOTICE/SBOM/corresponding-source；
- App Store Review Guideline 2.5.2 结论。

固定 artifact 的 shutdown 故意到达 `_exit(0)`。任何 soft-shutdown replacement 都必须：

- 重建 XCFramework；
- 记录新 revision 与 checksum；
- 限制 thread joins；
- 重新做 source/binary audit；
- 重跑 Simulator 和 physical-device lifecycle。

动态门禁状态见[路线图](Roadmap.md)。

## 7. 依赖更新流程

任何上游变化都是供应链变更，必须：

1. 解析完整不可变 package commit 和所有 nested gitlink；
2. 审查相对当前 revision 的 source diff；
3. 重建或取得能证明 source correspondence 的 artifact；
4. 独立计算并记录所有 artifact size/hash；
5. 检查每个 XCFramework slice、SDK 和 minimum deployment；
6. 在 minimum iOS Simulator runtime final-link 与 boot；
7. 在 physical iPhone/iPad 重跑 boot、command、PTY、cancellation、shutdown；
8. 生成 license、NOTICE、corresponding-source 与 SBOM；
9. 更新 `Package.resolved`、manifest 与测试；
10. 更新 [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md)、[路线图](Roadmap.md)和[发行与合规](ReleaseCompliance.md)。

任何 branch、moving tag、locally cached binary 或 unrecorded RootFS 都不能绕过该流程。
