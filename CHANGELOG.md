# 变更日志

[简体中文](CHANGELOG.md) | [English](CHANGELOG.en.md) | [文档中心](Docs/README.md)

PocketRoot 的重要变化记录在这里。首个公开版本发布后遵循 Semantic Versioning。当前所有内容属于 `Unreleased`。

## Unreleased

### Added

- 建立 `PocketRootCore`、`PocketRootTerminal`、`PocketRootResources` 和 `PocketRoot` Swift Package 产品。
- 建立纯 UIKit Demo，包含 System、Terminal、Commands、Diagnostics。
- 加入 XcodeGen `project.yml`、工程生成、测试和构建脚本。
- 加入 placeholder runtime、terminal API 基础与单元测试。
- 统一 package、Demo、tests 和 CI 的 iOS 18.0 deployment baseline。
- 固定 Experimental `PocketRootIshRuntime` 到 IshEmbed revision `6f96f02c71830914c2a608258a26a8ef0833d026`。
- 加入 Experimental `PocketRootIshRuntimeIntegration`，组合调用方本地 RootFS 与原生 runtime。
- 加入 process-wide ownership、serial native execution、lifecycle reentrancy protection。
- 加入一次性命令的 cwd、environment、stderr merge、exit、signal、timeout 和 stream mapping。
- 加入默认 post-boot identity gate；使用固定命令和 NUL framing，在 `ready` 前验证 guest 架构、Alpine 身份、可选版本与工作目录。
- 加入正 timeout、bounded native reads、默认 8 MiB stdout 与 4 MiB stderr limit。
- 加入 v0.3.3 RootFS immutable manifest、streaming SHA-256 和 byte limits。
- 加入 zlib gzip 与 constrained ustar extractor，拒绝 traversal、link、special node 和 duplicate。
- 加入 fakefs layout validation、versioned install、verified reuse，以及 journal 保护、可恢复/可回滚的同卷 promotion。
- 加入真实 release archive integration test。
- 加入完整 Experimental graph 的 arm64 Simulator 与 unsigned device final-link gate。
- 加入 repository-owned iOS 18 native smoke App 和 runner，覆盖 13 项 prepare、boot、guest、command、recovery 与 shutdown。
- 提交精确 SwiftPM resolution 到 `Package.resolved`。
- 加入 IshEmbed 可行性 [ADR-001](Docs/Decisions/ADR-001-IshEmbed-Feasibility.md)。
- 加入不可变 [上游依赖与制品清单](Docs/UpstreamDependencies.md)。
- 加入中文优先、英文镜像的双语文档体系：
  - [文档中心](Docs/README.md)
  - [产品规划](Docs/ProductPlan.md)
  - [快速开始](Docs/GettingStarted.md)
  - [应用接入指南](Docs/IntegrationGuide.md)
  - [架构说明](Docs/Architecture.md)
  - [实现原理](Docs/Implementation.md)
  - [RootFS 安全方案](Docs/RootFS.md)
  - [测试与验证](Docs/Testing.md)
  - [故障排查](Docs/Troubleshooting.md)
  - [路线图](Docs/Roadmap.md)
  - [发行与合规](Docs/ReleaseCompliance.md)
- 加入文档成对、中文覆盖和相对链接自动检查。

### Changed

- `README.md` 改为中文主入口，并提供完整产品状态、实现概览、接入示例、RootFS 策略和文档导航。
- 现有 Architecture、Roadmap、Upstream、ADR、Contributing、Changelog 改为中文主文档与英文镜像。
- 明确文档事实源：Roadmap 管动态状态，Upstream 管 revision/hash，Testing 管证据，ADR 管冻结决策。
- Git 贡献流程明确使用 SSH fetch/push。
- 明确默认 `PocketRootSystem.shared` 是 placeholder，真实 system 必须保存 `prepareSystem` 返回实例。
- 明确固定 native `shutdown()` 为进程终止式行为，不应作为普通 UI cleanup。
- 记录已合并但尚无可固定制品的 native ABI 候选；PocketRoot 当前 revision 与二进制行为保持不变。

### Security

- RootFS 归档仍不提交、不打包、不由 library 下载。
- 生产、TestFlight 与公开 binary distribution 在 license、NOTICE、对应源码、SBOM、真机和 App Store 2.5.2 门禁完成前保持阻塞。
