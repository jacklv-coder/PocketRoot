# 变更日志

[简体中文](CHANGELOG.md) | [English](CHANGELOG.en.md) | [文档中心](Docs/README.md)

PocketRoot 的重要变化记录在这里。首个公开版本发布后遵循 Semantic Versioning。当前所有内容属于 `Unreleased`。

## Unreleased

### Added

- 建立 `PocketRootCore`、`PocketRootTerminal`、`PocketRootResources` 和 `PocketRoot` Swift Package 产品。
- 新增显式 opt-in `PocketRootAgent` 产品，提供 provider-agnostic、有 turn/tool/input/output 上限、ID 防重放、整批预检、顺序工具执行与取消传播的轻量 agent loop；不安装 Codex CLI，也不默认暴露 shell。
- 为 `PocketRootAgent` 增加原生 OpenAI Responses API transport、宿主 bearer credential contract、strict function schema 预检、连续回合映射、脱敏错误与有界 HTTP request/response body。
- 新增显式 opt-in `PocketRootAgentRuntimeTools` 产品；Linux 命令必须通过整批工具级预检、宿主 allow/deny policy 与逐次审批，并受 cwd、environment、timeout 和 model-visible output 配额约束。
- 建立纯 UIKit Demo，包含 System、Terminal、Commands、Diagnostics。
- 加入 XcodeGen `project.yml`、工程生成、测试和构建脚本。
- 加入 placeholder runtime、terminal API 基础与单元测试。
- 统一 package、Demo、tests 和 CI 的 iOS 18.0 deployment baseline。
- 固定 Experimental `PocketRootIshRuntime` 到 IshEmbed wrapper revision `fe4ed63331a7e72f1d12f69296cd3c07231a4f0e` 与 `v0.4.0-abi.5` XCFramework。
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
- 加入 repository-owned iOS 18 native smoke App 和 runner，覆盖 17 项 prepare、boot、guest、8 MiB 持续二进制输出、stdout/stderr 超限、command、取消、recovery、shutdown 与 256 MiB Simulator 生命周期峰值内存门禁。
- 加入签名 iPhone/iPad smoke runner，通过 `devicectl` 安装、注入固定 RootFS、取回报告并校验 development entitlement；iPhone 17 Pro / iOS 26.1 基线已通过。
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
- native `shutdown()` 现在 soft-halt/join 后返回 `.terminated`；同一宿主进程仍只允许一次 lifecycle。
- IshEmbed 更新到 ABI.5：有限 streaming SPAWN 从 native API 入口覆盖 instance/spawn
  gate 与 control-queue admission，stdin close/terminate 使用有界异步接纳。PocketRoot
  driver 在 SPAWN 前建立统一 deadline 并把剩余时间传入 native，后续 close/read/terminate
  复用同一 deadline；同时保留 ABI.4 的 signal mask、ABI.3 的 `uname` 有界复制和
  ABI.2 的 `/proc` 生命周期锁修复，公共 C ABI 与 Swift API 不变。
- 一次性命令支持 Swift Task 取消：排队命令可在 native entry 前取消；活动命令会终止
  session，并在确认可信 `EXITED` 后返回 `CancellationError`。清理无法确认时 runtime
  失败关闭，成功取消后保持 ready。
- CI 增加并通过最低 Xcode 16.0 的完整 final-link、RootFS install 与 native smoke 门禁；
  Node.js/npm 仍只是调用方可选的 guest package，Codex CLI 不属于手机端安装路径。
- 记录自托管 XCFramework 与对应源码资产、精确大小/hash、nested iSH gitlink 和 RootFS 独立 pin。
- 一次性命令和 boot 的可选 supervisor 路径在进入 native driver 前拒绝含 NUL 的 C 字符串输入；命令环境还拒绝歧义 key。
- v4 transport 将 supervisor rejection、broken pipe 与 native backlog overflow 作为
  类型化错误；正常 guest `exit 17` 可返回，负数 `EXITED` 失败关闭。PocketRoot 同时
  映射 native backlog limit；因 void close 无法证明清理是否升级为 instance fail-close，
  该路径会保守关闭 process gate。
- RootFS boot 预检期间的文件属性读取错误统一映射为 typed `rootFSUnavailable`，并在申请原生进程槽位前保持 `idle`。
- process gate 使用显式 UUID 比较确认当前 owner，并以独立回归测试拒绝其他 runtime 的 claim 与 ownership 检查。
- ustar extractor 现在也登记文件/目录条目隐式创建的父目录，并拒绝后续重复目录项和文件系统等价目录目标；RootFS journal 文档明确不承诺未显式 `fsync` 的掉电持久性。
- RootFS 新安装和升级在创建 staging 前按压缩 snapshot、临时 tar、展开 payload
  与 16 MiB 余量计算同卷新增空间；不足时返回 typed 错误，且不为本次安装触碰有效旧版本。
  snapshot、gzip 部分输出、tar payload、安装记录、promotion journal、`current.json`
  和两个破坏性 promotion checkpoint 的 ENOSPC 注入验证了临时文件清理、旧版本保留
  与 `current.json` 回滚；POSIX 写入错误使用稳定系统描述。
- RootFS promotion 现在在 rename 前以 `F_FULLFSYNC`（不支持时回退 `fsync`）持久化
  候选文件树和安装记录，原子写入并持久化 journal/`current.json`，且在每次跨目录
  rename 后同步源与目标父目录。七个同步屏障的 I/O failure 矩阵以及 journal-only、
  backup、candidate 三类断电切点验证 commit/rollback；真机强制断电和 storage pressure
  仍单独验证。安装根必须由调用方预先创建；mode `000` 候选条目在私有 staging 中临时
  获得刷盘所需权限，并通过 descriptor 恢复原 mode 后再同步；staging/backup 删除会先
  让仅待删除目录可遍历，避免受限 mode 泄漏 transaction。
- `PocketRootSystem` 现在在 lifecycle/command 成功或抛错后刷新稳定公开 state；失败关闭立即公开 `.failed`，重入调用不会泄漏 lifecycle 过渡态，并用刷新代次阻止较旧快照覆盖较新的失败状态。
- 原生 spike/smoke target 显式排除 x86_64 Simulator；文档明确 `isAvailable` 是链接后的探针，不能替代 arm64-only binary 的构建架构约束。
- 原生 smoke runner 按稳定 runtime identifier 自动选择 iOS 18 Simulator，不再依赖 `simctl` 输出的最后一列，并加入多格式 fixture 回归测试。
- 原生 smoke App 以 iOS 18+ 版本下限取代仅允许 18.x 的错误限制，并把设备 family、系统名和版本写入报告。

### Security

- RootFS 归档仍不提交、不打包、不由 library 下载。
- 生产、TestFlight 与公开 binary distribution 在 license、NOTICE、对应源码、SBOM、真机和 App Store 2.5.2 门禁完成前保持阻塞。
