# ADR-001：以实验性方式采用 IshEmbed 作为 ARM64 Runtime

[简体中文](ADR-001-IshEmbed-Feasibility.md) | [English](../en/Decisions/ADR-001-IshEmbed-Feasibility.md) | [文档中心](../README.md)

- 状态：**已接受，仅限实验性集成**
- 日期：2026-07-21
- 修订：2026-07-23，固定自托管 `v0.4.0-abi.1` soft-shutdown 制品
- 基线：iOS 18.0、arm64
- 决策范围：runtime 可行性、供应链固定方式和发行门禁

本文记录“为什么做出这个决定”和当时证据。动态完成状态只在[路线图](../Roadmap.md)维护；精确制品事实只在[上游依赖清单](../UpstreamDependencies.md)维护。

## 背景

PocketRoot 需要一个可嵌入的 ARM64 Linux runtime：

- 启动 Alpine fakefs；
- 执行一次性命令；
- 未来提供交互式 PTY；
- 能被 Swift Package 消费；
- 能在 iOS 18 沙箱内运行；
- 供应链和发行风险可审计。

审核候选是用户 fork 的 `ish-arm64-pkg`。它把 iSH 派生 kernel 包装成 `IshEmbed` Swift Package，同时组合：

- Swift/C source；
- 预构建 static XCFramework；
- 单独分发的 RootFS；
- pinned iSH submodule；
- 进一步 nested source dependency。

该依赖年轻、pre-1.0，且 source、binary 与 RootFS 不在同一个完整发行闭环中，因此不能直接进入默认产品。

## 决策

PocketRoot 将 IshEmbed 集成在独立的 `PocketRootIshRuntime` product 后，状态为 Experimental。

另一个 Experimental product `PocketRootIshRuntimeIntegration` 负责：

- 接收调用方本地 RootFS；
- 通过 `PocketRootResources` 安全安装；
- 创建与该安装绑定的 runtime；
- 返回尚未 boot 的 `PocketRootSystem`。

两个 Experimental product 都不由默认 `PocketRoot` umbrella re-export。默认 `PocketRootSystem` 保持 placeholder。

固定 Swift Package 输入：

```text
Repository: https://github.com/jacklv-coder/ish-arm64-pkg.git
Revision:   41e5c0a8b215c18239308c787a4a4de53d685076
Product:    IshEmbed
```

固定 nested iSH gitlink：

```text
576ffaf2574310b5fb2d148aab39ddcd2b8fe67d
```

不能跟随 branch 或 moving tag。当前 prerelease tag 只用于发布身份，消费仍固定完整
revision；后续变更必须执行完整供应链更新流程。

## 备选方案

### 方案 A：直接加入默认 umbrella

拒绝。普通消费者会意外链接 arm64-only binary，并继承不可逆 shutdown 与未解决的合规义务。

### 方案 B：只保留 placeholder，等待所有门禁完成

拒绝作为唯一策略。缺少实际 adapter 会让生命周期、RootFS 和构建风险长期无法验证。

### 方案 C：在业务 App 内直接调用 IshEmbed

拒绝。会把 iSH singleton、native pointer、blocking call、RootFS 和 UI 逻辑扩散到业务层，难以测试和替换。

### 方案 D：实验性隔离并显式启用

接受。可以建立真实证据，同时让默认产品保持安全。

## 审核证据

### Package 与 binary 形态

审核 manifest 暴露 `IshEmbed`，内部包括：

- `CIshEmbed` C module；
- `IshKernel` binary target；
- `IshEmbed` Swift API/session/helper；
- RootFS-dependent integration tests。

manifest 声明 iOS 18.0，release XCFramework 只有：

| Identifier | Architecture | Platform | Binary minimum |
| --- | --- | --- | --- |
| `ios-arm64` | arm64 | iOS device | iOS 18.0 |
| `ios-arm64-simulator` | arm64 | iOS Simulator | iOS 18.0 |

没有 x86_64 Simulator 或 macOS slice。上游 package 直接在 macOS native link 会失败，因此 PocketRoot 只在 iOS 条件下依赖 binary，并为 host tests 使用 driver seam。SwiftPM manifest 不能按 destination architecture 条件化 product dependency；选择实验产品的 App target 必须在构建设置中排除 x86_64，`isAvailable` 只负责链接后的能力探测。

### 制品完整性

审核时独立计算：

| Artifact | SHA-256 |
| --- | --- |
| `libIshKernel.xcframework.zip` | `5bd6f691ed2af1e157118b26f62b962a3568ebe96a608d75f5b2f661d07e1450` |
| `IshEmbed-corresponding-source.tar.gz` | `52b10b3b1dfedf221b4af37b125cde9b5fd03cc819944ab2d77d9893f6a76122` |
| `fs.tar.gz` | `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4` |

XCFramework digest 与 upstream manifest 一致。RootFS digest 不在 upstream Swift manifest 中，因此 PocketRoot 单独提交 manifest 并 fail closed。

RootFS 源自 Alpine `3.19.1 aarch64`，原始 minirootfs SHA-256：

```text
7ef5eef3a5b1d198dfb1610cde1ef5b0755ff5d838fb1e5e1b9f42b59214820f
```

### iOS 18 可行性 spike

在 Apple Silicon、Xcode 26.1.1、Swift 6.2.1 下，最小 iOS 18 consumer：

- 完成 arm64 Simulator final link；
- 完成 unsigned arm64 device final link；
- 在 iOS 18.2 Simulator 复制审核 fakefs 到 writable sandbox；
- boot `IshInstance.shared`；
- 执行 `/bin/uname -m`；
- 得到 exit 0 和 `aarch64`。

该证据只证明固定 Simulator 路径，不证明 physical device。

### 仓库集成

PocketRoot 进一步实现：

- 完整 Experimental graph 的两个 arm64 final link；
- committed RootFS manifest；
- no-follow bounded private snapshot；
- gzip/ustar constrained extraction；
- path traversal、host symlink、duplicate、special entry 拒绝；
- fakefs layout validation；
- journal 保护、多步同卷 rename 的版本化 promotion；
- rollback，以及根据 final 是否匹配预期、backup 是否存在和旧安装事实推断的 interrupted recovery；
- real release asset CI test。

详细实现见 [RootFS 安全方案](../RootFS.md)。

### Repository native smoke

专用 smoke App 通过：

- v0.3.3 preparation；
- boot；
- `aarch64`；
- Alpine `3.19.1`；
- working directory 与 environment；
- stdout/stderr 与 exit code；
- stderr merge；
- timeout 与 post-timeout recovery；
- output limit 与 post-limit recovery；
- 返回 Swift 的 soft shutdown 与同进程 `restartRequired`。

成功 report 只在 shutdown 返回、状态为 `.terminated` 且再次执行得到
`restartRequired` 后写入。host script 主动结束测试 App，不把进程退出当成 native
lifecycle 证据。

完整清单和命令见[测试与验证](../Testing.md)。

### Private API 与 entitlement 静态检查

固定 archive 和完整 consumer binary 未发现：

- `MAP_JIT`；
- JIT entitlement；
- private framework path；
- `com.apple.private.*` entitlement。

ARM64 engine 使用预编译 gadget，不在 runtime 生成机器码。该结果不是 App Review 保证，仍需要 signed device 与最终 archive scan。

## Runtime 约束

### 进程级单例

公开 C contract 只允许一个 process-global iSH instance。PocketRoot 因此：

- 使用 process ownership gate；
- 在共享 serial executor 调用同步 native API；
- 一个 runtime 同时只允许一个 one-shot；
- lifecycle state 在 suspension 前关闭；
- active command 存在时拒绝 shutdown。

这里的 lifecycle state 是 adapter 内部状态。公开 `PocketRootSystem.state` 在 lifecycle
调用结束后发布最终状态，命令结束后只发布稳定状态；失败关闭会公开 `.failed`，但重入
命令不会泄漏 await 过程中的内部过渡态。

RootFS promotion 也不被视为一次整体原子替换。journal 不记录 phase，而是保存预期记录
和旧安装/current 数据；各次同卷 rename 后若中断，下次根据 final 是否匹配预期、backup
是否存在和旧安装事实完成提交或回滚。归档中的 `fs/` 目录本身会被提升，因此最终 `rootfs/<version>` 直接包含
`meta.db`、`data/` 和 `.pocketroot-rootfs.json`。有效版本的复用不依赖原有
`current.json` 正确；缺失或不匹配时会修复。

### Single-lifecycle soft shutdown

固定 revision 会停止 supervisor、soft-halt embedded kernel、bounded join 原生线程并
返回 Swift：

- `IshInstance.shutdown()` 成功后 PocketRoot 发布 `.terminated`；
- 调用方可以在返回后执行宿主清理；
- iSH 的进程级全局状态仍不允许同一进程再次 boot；
- active call/session 会得到 busy 或由 PocketRoot 在更高层拒绝。

新制品、revision、checksum、对应源码和 Simulator 测试已完成；签名 iPhone/iPad、
持续生命周期和故障注入仍按路线图继续，不因此把 Experimental 产品加入默认 umbrella。

### Session/PTY

审核发现上游 session shutdown 存在 native object 与 Swift raw pointer 生命周期风险；高层 `IshTerminal.close()` 也可能与无限 read pump 竞态。

因此交互实现必须先具备：

- live session registry；
- bounded reads；
- input/output/signal/resize/EOF contract；
- cancellation；
- idempotent close；
- close all sessions before shutdown；
- native pointer ownership tests。

在这些条件满足前，不采用上游高层 `IshTerminal`，也不连接 SwiftTerm。

## RootFS 与发行约束

审核 package 有 GPL 标识，但缺少完整顶层 LICENSE/NOTICE 组合。iSH submodule 有 GPL 和 `LICENSE.IOS`。Alpine RootFS 包含 GPL、Apache、MPL、MIT、BSD、Zlib 等 family，但 release asset 没有完整 license bundle、NOTICE、SBOM 或对应源码交付材料。

静态链接和 RootFS 分发保持阻塞，直到：

- PocketRoot license 兼容性确认；
- upstream notice 与修改说明完整；
- corresponding source 可提供；
- SBOM 完整；
- App Store 2.5.2 有结论。

Alpine `apk` 可下载并执行新代码，因此“把固定 RootFS 打入 App”不会自动消除 App Store downloaded-code 风险。

详见[发行与合规](../ReleaseCompliance.md)。

## 后果

正面：

- 能在窄 adapter 后持续验证真实 runtime；
- 默认客户端不链接实验 binary；
- RootFS 安装与 runtime 可独立测试；
- process-global 和 shutdown 风险进入明确 API/document contract；
- dependency update 有不可变审计流程。

代价：

- 多一个 binary supply-chain dependency；
- arm64-only native test 环境；
- 当前关闭不可逆；
- PTY 和 Demo 实际集成推迟；
- 合规工作量显著；
- production 与 distribution 保持阻塞。

## 重新审议触发条件

发生以下任一情况必须更新或新增 ADR：

- 修改 IshEmbed revision 或 nested iSH gitlink；
- 重建或镜像 XCFramework；
- 修改 RootFS version/build/package；
- 引入 soft shutdown；
- 启用 interactive PTY；
- 加入 SwiftTerm；
- 把 Experimental product 放入 umbrella；
- 开启 TestFlight、生产或公开分发；
- App Store 或许可证结论改变。

动态门禁不在 ADR 复制，统一更新[路线图](../Roadmap.md)。
