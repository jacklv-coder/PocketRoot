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
`38d25d6f8726145e7e988172f12000020d89a638`、`v0.4.0-abi.6` release commit
`38d25d6f8726145e7e988172f12000020d89a638` 与 iSH gitlink
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

release archive 自身没有完整 license bundle 或 NOTICE set，也没有随附
machine-readable SBOM。仓库现在从固定 archive 可复现生成 15 个已安装二进制包、
10 个 source origin、SPDX 2.3 JSON SBOM、声明许可证/attribution inventory 和
`apk`、repository、DNS 默认配置快照。archive 内没有发现可识别的
LICENSE/COPYING/NOTICE 文件。仓库另有与 inventory 一一对应、固定 checksum 的
aports snapshot/upstream distfile 获取清单和仓库外 materializer，并固定了覆盖
全部 10 个 source origin 的 28 个 license、attribution、声明与内联 notice 候选。
第二个仓库外工具从已验证 source-review 目录提取这些候选；固定结果清单记录
28/28 个候选均已工程复核，`libc-dev`、`zlib` 的索引项已关闭，另外 8 个 source
origin 仍有逐包未决项。仓库现已为这 8 个 origin 固定外置候选包：13 份远端
许可证/attribution 材料、47 份 aports 补充文件和全部既有复核证据；工具可在
仓库外原子生成并复验。固定结果清单把工程复核绑定到精确的 88 文件 payload
tree；`apk-tools`、`openssl`、`pax-utils` 的候选材料工程项已关闭，另外 5 个
origin 仍需补逐包材料。修改与构建完整性、源码提供方式和法律审查仍未完成，
不能视为完整 NOTICE 或已批准的对应源码交付。

## 当前仓库保护

- RootFS archive 不提交、不默认打包。
- `Sources/PocketRootResources/Resources` 只有合规提示。
- IshEmbed 固定到完整 commit。
- nested iSH gitlink 单独记录。
- XCFramework 与 RootFS SHA-256 单独记录。
- 默认伞形产品不导出实验 runtime。
- composition 只接受调用方本地 archive，不下载。
- CI 下载 RootFS 仅用于校验和测试，不把它保存为发行 artifact。
- CI 从固定 archive 重新生成并比对
  [`Compliance/RootFS/v0.3.3`](../Compliance/RootFS/v0.3.3/README.md) 的包清单、
  SPDX SBOM、来源 locator、源码获取清单、license/NOTICE 候选索引与工程复核
  结果、许可证声明和默认配置证据。
- CI 离线测试仓库外 source-review materializer 的 checksum、路径隔离和安全解包；
  不上传生成的源码材料。
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

- [x] 从固定 APK database 生成完整 package inventory。
- [x] 生成并通过 SPDX 2.3 JSON schema 校验的 machine-readable SBOM。
- [x] 对固定的 28 个 license/NOTICE 候选完成 checksum-bound 工程复核。
- [x] 为剩余 8 个 source origin 建立 checksum-bound 外置候选包索引与可复验
  materializer；payload 不提交且批准门禁保持关闭。
- [x] 对外置候选包的 88 个 payload 完成 checksum-bound 工程复核并固定结果；
  3 个 origin 的候选材料工程项关闭，5 个仍需补逐包材料。
- [ ] 收集 license text 和 NOTICE。
- [ ] 建立 copyleft corresponding source bundle。
- [x] 固定 DNS、repository 和 package-manager 默认配置事实。
- [ ] 决定保留、限制、代理或禁用 guest package manager/network 的产品策略。
- [x] 当前决定 archive 由调用方作为外部本地输入；若改为 bundle 或按需资源须重审。
- [x] 更新 manifest、hash 和 CI 可复现测试证据。

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
