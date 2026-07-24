# 发行与合规

[简体中文](ReleaseCompliance.md) | [English](en/ReleaseCompliance.md) | [文档中心](README.md)

本文记录 PocketRoot 当前的发行边界和退出条件，不构成法律意见。精确依赖和制品事实见[上游依赖清单](UpstreamDependencies.md)，动态工程状态见[路线图](Roadmap.md)。

## 当前结论

PocketRoot 的实验性 iSH runtime、XCFramework 和候选 RootFS 当前仅用于本地研发和受控技术验证。

以下行为保持阻塞：

- 生产使用；
- TestFlight 分发；
- App Store 提交；
- 公开或私有二进制 SDK 分发；
- 把 RootFS 加入 Swift Package、Demo 或 App bundle；
- 镜像未完成合规材料的 XCFramework 或 RootFS；
- 宣称已经满足 GPL、NOTICE、对应源码或 SBOM 义务。

默认 `PocketRoot` 产品不包含真实 iSH 或 RootFS，但 PocketRoot 自身首个公开 release 的许可证策略仍需正式确认。

## 发行组成

一个启用真实 runtime 的 App 可能同时包含：

1. PocketRoot Swift 源码；
2. `ish-arm64-pkg` Swift Package 源码；
3. 预编译 `IshKernel` XCFramework；
4. iSH 派生源码及 nested submodule；
5. Alpine fakefs archive；
6. guest 内安装的 GPL、Apache、MPL、MIT、BSD、Zlib 等组件；
7. 应用自己的下载、缓存、命令和 UI 逻辑。

合规评审必须覆盖整个组合，不能只检查根目录 `LICENSE`。

## 已知许可证事实

### IshEmbed 与 iSH

审核时：

- package repository 含 GPL SPDX 标识，并声明遵循 GPL-3.0；
- 仓库缺少完整顶层 LICENSE/NOTICE 组合；
- pinned iSH submodule 有自己的 GPL license text 和 `LICENSE.IOS`；
- release XCFramework 是静态二进制输入；
- source-to-binary correspondence 必须进一步固化并可提供。

当前审计记录固定 IshEmbed wrapper revision
`fe4ed63331a7e72f1d12f69296cd3c07231a4f0e`、`v0.4.0-abi.5` release commit
`bcbf8ddb3ee855cd119050a9e16b55dbfe8ceec6` 与 iSH gitlink
`c36dfd25462737b45559eb48d4b09f799471572e`，并在上游依赖清单中记录 XCFramework
和 corresponding-source 资产的大小与摘要。Release 已提供对应源码资产，但产品级
RootFS 合规材料和完整可分发组合仍未闭环，因此不会解除发行阻塞。

### Alpine RootFS

固定 archive 中的 package license family 包括：

| 组件示例 | 声明许可证 |
| --- | --- |
| Alpine baselayout、apk-tools、BusyBox、scanelf | GPL-2.0-only |
| musl-utils | MIT、BSD-2-Clause、GPL-2.0-or-later |
| musl、Alpine keys | MIT/BSD variants |
| OpenSSL libraries | Apache-2.0 |
| CA certificates | MPL-2.0 与 MIT |
| zlib | Zlib |

release archive 没有完整 license bundle、NOTICE set 或 machine-readable SBOM。copyleft package 的对应源码可用性也必须建立。

## 当前仓库保护

- RootFS archive 不提交、不默认打包。
- `Sources/PocketRootResources/Resources` 只有合规提示。
- IshEmbed 固定到完整 commit。
- nested iSH gitlink 单独记录。
- XCFramework 与 RootFS SHA-256 单独记录。
- 默认伞形产品不导出实验 runtime。
- composition 只接受调用方本地 archive，不下载。
- CI 下载 RootFS 仅用于校验和测试，不把它保存为发行 artifact。
- README、API 注释和 ADR 明确标注 Experimental 与 shutdown 风险。

这些工程措施降低意外分发风险，但不替代法律审查。

## App Store Guideline 2.5.2

独立于开源许可证，App Store 还需要评估 guest 下载和执行代码的能力。

Alpine `apk` 可以下载、安装和执行新增代码。即使初始 RootFS 已打包并审核，也不自动消除 Guideline 2.5.2 风险。

发行决定至少要明确：

- 用户是否能执行任意 shell；
- guest 是否保留 package manager 和网络；
- 能下载哪些内容；
- 新代码是否改变 App 功能；
- 是否限制命令、仓库、包或解释执行；
- 产品面向开发、教育、远程管理还是普通消费者；
- App Review 如何描述；
- 是否需要禁用、代理或策略化 `apk`。

当前没有结论，因此保持阻塞。

## 私有 API、entitlement 与 JIT

已完成的静态检查没有在 release archive 或完整 consumer binary 中发现：

- `MAP_JIT`；
- JIT entitlement；
- private framework path；
- `com.apple.private.*` entitlement。

当前 ARM64 engine 使用预编译 gadget，而不是运行时生成机器码。

这只是固定制品的静态证据和 Simulator 证据，不是 App Review 保证。仍需：

- signed iPhone/iPad；
- 最终 entitlement 检查；
- archive/export 后 binary scan；
- runtime network、filesystem 与 process 行为审计。

## 数据与隐私

引入 Linux guest 后，发行评审还应覆盖：

- RootFS 和 VM 数据存放位置；
- iCloud/iTunes backup exclusion 策略；
- guest 命令访问的 App 文件边界；
- command、stdout、stderr 和 kernel log 的日志保留；
- 用户输入、环境变量和 secret；
- network permission 与 guest DNS；
- 删除 App、清除环境和迁移版本时的数据生命周期；
- crash report 是否包含命令或私有路径。

当前代码不提供完整产品级 privacy policy。

## 发行前必须完成

### PocketRoot 自身

- [ ] 选择并提交完整顶层许可证。
- [ ] 明确贡献者和版权政策。
- [ ] 生成 release notice。
- [ ] 标记 public API stability 和 semantic version。

### IshEmbed / iSH

- [ ] 记录每个 source commit 与 nested gitlink。
- [ ] 保证 XCFramework 可对应到可重建源码。
- [ ] 保存构建脚本、toolchain 和 checksum。
- [ ] 汇总 LICENSE、NOTICE 和修改说明。
- [ ] 评估静态链接义务。
- [ ] 提供所需对应源码。

### RootFS

- [ ] 生成完整 package inventory。
- [ ] 生成 machine-readable SBOM。
- [ ] 收集 license text 和 NOTICE。
- [ ] 建立 copyleft corresponding source bundle。
- [ ] 审查 DNS、repository 和 package-manager 默认配置。
- [ ] 决定 archive 是 bundle、按需资源还是外部输入。
- [ ] 更新 manifest、hash 和测试证据。

### Apple 平台

- [x] Xcode 16 minimum-toolchain RootFS install、native final-link 与 17 项 smoke。
- [x] signed iPhone 一次性命令 smoke。
- [ ] signed iPad smoke 与完整 iPhone/iPad lifecycle。
- [x] Simulator 完整 smoke 生命周期 `ru_maxrss` 不超过 256 MiB。
- [ ] foreground/background、真机 jetsam、storage pressure。
- [ ] entitlement、private API、JIT 与 archive scan。
- [ ] Guideline 2.5.2 书面结论。
- [ ] 隐私清单、网络与数据保留评审。
- [x] 记录 soft shutdown 返回与同进程不可再次 boot 的 single-lifecycle 契约。

### 交付材料

- [ ] LICENSE bundle。
- [ ] NOTICE。
- [ ] corresponding-source location 与获取说明。
- [ ] SBOM。
- [ ] dependency/revision/hash inventory。
- [ ] 安全与已知限制。
- [ ] RootFS 更新和删除策略。
- [ ] App Review notes。
- [ ] 可复现构建记录。

只有所有阻塞项有明确、经负责人批准的处置，才能改变发行状态。

## 允许的研发活动

在不再分发受限制制品的前提下，可进行：

- 本地 Swift Package 测试；
- CI 临时下载、校验并在 job 内测试；
- unsigned generic device final-link；
- iOS Simulator smoke；
- 受控 signed physical-device engineering validation；
- 源码和制品审计；
- 合规材料生成。

测试结果和 archive 不应作为公开 release artifact 上传。

## 变更审查触发条件

以下变化必须重新打开供应链和合规审查：

- IshEmbed revision、iSH gitlink 或 XCFramework；
- RootFS 版本、package、build script 或 DNS 默认值；
- 新的 terminal、network 或 package-install 功能；
- 新的分发渠道；
- shutdown 或 process 模型；
- SwiftTerm 或其他第三方依赖；
- license 或 App Store guideline 变化。

更新时同时修改：

- [上游依赖清单](UpstreamDependencies.md)
- [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md)
- [路线图](Roadmap.md)
- [变更日志](../CHANGELOG.md)
- 本文中英文版本

## 责任边界

工程维护者负责记录事实、维护降低意外打包风险的控制，并提供可复现证据。最终许可证解释和分发决定应由有权限的法律、合规与产品负责人作出。
