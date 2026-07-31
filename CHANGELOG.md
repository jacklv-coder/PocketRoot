# 变更日志

[简体中文](CHANGELOG.md) | [English](CHANGELOG.en.md) | [文档中心](Docs/README.md)

PocketRoot 的重要变化记录在这里。首个公开版本发布后遵循 Semantic Versioning。当前所有内容属于 `Unreleased`。

## Unreleased

### Added

- 新增 `v0.1.0` fail-closed 双轨发布闸门：机器可读状态、双语检查清单和 CI 状态
  把源码/Swift Package 发布与不含 RootFS 资产的 runtime/App/二进制分发分开；
  两条轨道均需显式授权，工程测试通过不会自动解除分发阻塞，也不会授权 RootFS
  分发。
- 建立 `PocketRootCore`、`PocketRootTerminal`、`PocketRootResources` 和 `PocketRoot` Swift Package 产品。
- 新增显式 opt-in `PocketRootAgent` 产品，提供 provider-agnostic、有 turn/tool/input/output 上限、ID 防重放、整批预检、顺序工具执行与取消传播的轻量 agent loop；不安装 Codex CLI，也不默认暴露 shell。
- 为 `PocketRootAgent` 增加原生 OpenAI Responses API transport、宿主 bearer credential contract、strict function schema 预检、连续回合映射、脱敏错误与有界 HTTP request/response body。
- 新增显式 opt-in `PocketRootAgentRuntimeTools` 产品；Linux 命令必须通过整批工具级预检、宿主 allow/deny policy 与逐次审批，并受 cwd、environment、timeout 和 model-visible output 配额约束。
- 建立纯 UIKit Demo，包含 System、Terminal、Files、Commands、Diagnostics。
- Demo 显式接通实验 iSH、SwiftTerm PTY、Commands 与 Files；加入仓库外固定 RootFS
  的 Debug-only 大小/hash 校验注入、共享 runtime 生命周期和动态 Diagnostics，
  Release 构建保持不注入。
- 加入 XcodeGen `project.yml`、工程生成、测试和构建脚本。
- 加入 placeholder runtime、terminal API 基础与单元测试。
- 加入不依赖 Agent Loop 或 PTY 的轻量命令终端：在有界一次性命令之间保存
  working directory，支持连续 `ls`、`cd` 和文件操作，提供可注入
  `PocketRootSystem` 的 fallback API、命令串行化、取消和 transcript 上限。
- 加入完整交互入口 `PocketRootSystem.makeSession`：真实 IshEmbed PTY、bounded read、
  输入、resize、signal/EOF、幂等终止、live-session registry 与
  close-all-before-shutdown；session 创建与 shutdown 互锁，致命 transport failure
  会同步失败关闭 runtime，有限 native admission 避免终止控制无界阻塞；Swift 输出
  缓冲以 16 KiB 分块限制到 4 MiB 并保留终态，native shutdown 只在权威退出后执行；
  取消创建会关闭未返回的 native session，可恢复的 supervisor/EOF 错误只关闭当前会话。
- 固定 SwiftTerm `dd2fb8ac…`，提供 UIKit/SwiftUI 终端页面；加入 NUL-framed guest
  文件夹页面、按需树形原地展开、目录导航、最多 512 KiB 的有界文本/二进制预览，
  以及创建文件/目录、原子无覆盖重命名和确认后递归删除。重命名直接使用
  IshEmbed `v0.4.0-abi.9` 中的 guest 原生能力，不经过 shell 检查再移动。
- 一次性命令新增默认 1 MiB 上限的二进制 `standardInput`；Files 页面和 actor API
  新增系统文件导入与分享导出。导入内容不拼接进 shell，而是经 stdin 写入同目录私有
  staging，再由 ABI.9 中的原子 no-replace rename 提交；失败与取消会尽力清理 staging，
  导出在读取前后均执行大小门禁。
- 加入公开 UIKit/SwiftUI Workspace 组合入口：一个已 boot system 可直接打开持续
  Terminal 与 Files，跨页面不重建 PTY，退出时关闭 session；Host App UI smoke
  验证终端创建文件、Files 预览和切回后的同一会话。
- 加入进程级 `PocketRootIshWorkspaceHost` 与 UIKit/SwiftUI 一体化入口：调用方提供
  本地 RootFS 与 Application Support 即可自动 prepare、boot 和打开 Workspace；
  并发 boot 合并，页面退出只关闭 PTY，显式 shutdown 先关闭全部 host Workspace。
- 为 `PocketRootIshWorkspaceHost` 加入独立 Terminal 与 Files 公共入口；页面自动
  prepare/boot，无需业务层轮询 `readySystem`。新增只有两个按钮的
  `Examples/PocketRootQuickStartApp`，并在 CI 中最终链接和核对固定 Debug RootFS；
  iPhone/iPad UI smoke 从冷启动分别验证 Files 与 Terminal 自动 boot，并确认真实
  PTY 创建的文件可由 Files 预览。Quick Start 与 Host App 复用同一个有界 Simulator
  runner。
- 加入仓库外生成的 External Consumer 验收 App；本地可指向当前 package path，
  PR CI 则通过公开 Git URL 固定到 head 完整 SHA，使用调用方资源方式打包已审核
  RootFS，并验证 Terminal 创建文件、前后台恢复、Files 预览与显式 shutdown。
- 统一 package、Demo、tests 和 CI 的 iOS 18.0 deployment baseline。
- 固定 Experimental `PocketRootIshRuntime` 到 IshEmbed release revision `38d25d6f8726145e7e988172f12000020d89a638` 与 `v0.4.0-abi.6` XCFramework。
- 将 Experimental `PocketRootIshRuntime` 升级到 IshEmbed release revision
  `37231ab667b380eb86a5fbcf961e31af4d50cebb` 与 `v0.4.0-abi.7` XCFramework，
  并公开 `PocketRootSystem.renameItem` 的原子 no-replace guest 重命名。
- 将 Experimental `PocketRootIshRuntime` 升级到 IshEmbed release revision
  `2419f736b271beb52a699b2f780027cf280472b8` 与 `v0.4.0-abi.9` XCFramework，
  让有限 session 的 stdin write/close 复用同一 SPAWN 绝对 deadline。
- 加入 Experimental `PocketRootIshRuntimeIntegration`，组合调用方本地 RootFS 与原生 runtime。
- 加入公开 `PocketRootIshRuntimeController` 和独立
  `Examples/PocketRootHostApp`：业务 App 只通过 Swift Package API 即可共享 boot 后
  system，打开 SwiftTerm PTY 与 guest 文件页面；CI 编译宿主并核对 Debug RootFS，
  Release 继续保持不注入。
- 加入 Host App 的 iOS 18 Simulator UI smoke：通过真实 SwiftTerm PTY 输入创建文件，
  并覆盖持续输出、前后台、旋转 resize、关闭/重开、Files 预览与有序 shutdown；
  光标闪烁可配置关闭以支持确定性 UI 自动化。runner 可选择 iPhone/iPad 设备类型，
  CI 在 iPhone 16 与 iPad（第 10 代）上运行同一完整套件；Files 删除确认改用
  跨 size class 稳定的 alert。独立 Host App 示例的 Documents 通过系统 Files
  可见，测试仅在显式 UI-test 启动参数下生成固定文件，并自动验证 document picker
  导入、share sheet 保存、guest 删除、再次导入和内容一致的完整 round-trip。
- 加入 development-signed Host App 真机 UI runner：验证 physical iOS、设备/Xcode
  支持范围、签名与 entitlement，再复用同一生命周期测试；默认清理 App 和诊断制品。
- 加入 process-wide ownership、serial native execution、lifecycle reentrancy protection。
- 加入一次性命令的 cwd、environment、stderr merge、exit、signal、timeout 和 stream mapping。
- 加入默认 post-boot identity gate；使用固定命令和 NUL framing，在 `ready` 前验证 guest 架构、Alpine 身份、可选版本与工作目录。
- 加入正 timeout、bounded native reads、默认 8 MiB stdout 与 4 MiB stderr limit。
- 加入 v0.3.3 RootFS immutable manifest、streaming SHA-256 和 byte limits。
- 加入 zlib gzip 与 constrained ustar extractor，拒绝 traversal、link、special node 和 duplicate。
- 加入 fakefs layout validation、versioned install、verified reuse，以及 journal 保护、可恢复/可回滚的同卷 promotion。
- 加入真实 release archive integration test。
- 加入固定 RootFS 的可复现合规证据生成器、CI 比对与固定官方 schema 验证，提交 15 包 inventory、
  10 个 source origin、SPDX 2.3 JSON SBOM、许可证声明/attribution inventory
  和 `apk`、repository、DNS 默认配置快照；完整 LICENSE/NOTICE 与对应源码 bundle
  仍保持发行阻塞。
- 加入可复现的最大实验工程组合 inventory 与 SPDX 2.3 JSON SBOM，区分默认 Demo、
  原生 runtime smoke 和全部 Swift products，绑定 ABI.9 IshEmbed/XCFramework、
  iSH、supervisor musl source、外部 RootFS 及其中 15 个包；CI 比对生成结果并
  使用固定官方 schema 校验。该证据未扫描最终 archive，完整发行物 SBOM 与发行授权
  门禁保持关闭。
- 加入仓库外 `.app`/`.xcarchive` 确定性制品扫描器：限制文件数量/大小并拒绝
  symlink/special file，记录逐文件摘要、Mach-O 架构/依赖/未定义符号、
  codesign entitlement、private framework/private entitlement/JIT/`MAP_JIT`
  信号，原子生成 inventory、文件级 SPDX 2.3 SBOM 与校验和并支持逐字节复验。
  CI 扫描临时 unsigned device runtime App、要求风险信号为空并校验 SBOM，但不上传
  App 或证据；最终签名/导出制品、完整发行物 SBOM 与分发授权仍保持关闭。
- 加入本地 development-signed engineering `.xcarchive` 构建/扫描门禁：修复包含
  `CreationDate` 的真实 archive plist 解析，生成标准 installable smoke archive，
  验证 development entitlement、签名、风险信号、确定性复验与 SPDX schema。
  runner 不安装、导出或上传 App；最终发行签名/导出制品与分发授权仍保持关闭。
- 加入 checksum-bound `LICENSE-REVIEW-RESULTS.json` 和严格验证器；78/78 个固定
  RootFS license/NOTICE 候选已完成工程复核，8 个 source origin 仍有包级未决项，
  法律与再分发门禁保持关闭。
- 为剩余 8 个 RootFS source origin 加入 checksum-bound
  `LICENSE-NOTICE-CANDIDATES.json`、严格验证器和仓库外原子 materializer；索引
  13 份远端许可证/attribution 材料、47 份 aports 文件与 78 份既有证据，支持完整
  复验，但不提交 payload，也不解除工程、法律或再分发门禁。
- 加入 `LICENSE-NOTICE-REVIEW-RESULTS.json` 和严格外置 payload-tree 复验器；
  138/138 个候选 payload 已完成 checksum-bound 工程复核；新增固定
  `alpine-keys` GPL→MIT 上游许可判定提交，但仍保留包级版权声明缺口；
  `ca-certificates` 生成脚本与 curl 提交 `3fdc4bdb` 字节一致并固定该精确
  revision 的 curl 授权文本；固定 Mozilla `certdata.txt` 可复现生成与 RootFS
  安装文件逐字节一致的证书束，trust-store 候选材料工程项关闭；
  BusyBox 固定配置确认 bzip2 与源包内精确授权绑定，确认启用的 ash 算术模块
  链入保留完整 MIT 与 BSD-3-Clause notices 的 `shell/math.c`，并确认已安装的
  `env`、`echo`、`logger` 与 `cal` applet 分别链入保留完整 BSD notice 的
  `coreutils/env.c`、`coreutils/echo.c`、`sysklogd/logger.c` 与
  `util-linux/cal.c`，`ping` 与 `ping6` 共同链入 `networking/ping.c`，
  `traceroute` 与 `traceroute6` 共同链入保留完整原始 BSD/LBL notice 的
  `networking/traceroute.c`；`od` 的 desktop 构建链入 `coreutils/od.c` 与
  `coreutils/od_bloaty.c`，`hexdump`/`hd` 共同链入 `util-linux/hexdump.c`
  并使用 `libbb/dump.c`，覆盖完整 Regents BSD 条款、FSF attribution 与 GPL
  声明；`expand`/`unexpand` 共同链入 `coreutils/expand.c`，`fold` 链入
  `coreutils/fold.c`，两份源码均保留 FSF 版权、GPLv2-or-later 声明与 BusyBox
  改写署名；`cut`、`sort`、`uniq` 分别链入对应 `coreutils` 源码，三份源码均
  保留 GPLv2-or-later 声明与原作者署名。其余 BusyBox 审查按固定 33 个 aports
  补丁和配置生成 487 个编译单元、562 文件 include 闭包，并固定其中 41 份仍含
  独立第三方条款或 provenance 的源码；BusyBox 证据增至 60 份，总括工程项关闭。
  `alpine-baselayout` 的固定 aports 快照与 netbase 6.4 copyright 完成包级来源/
  notice 核对；musl `COPYRIGHT`、三个已安装辅助工具许可头、无额外 notice 的
  `ldconfig`/生成 `ldd` 及三个 aports patch 完成第三方闭包复核。
  `alpine-baselayout`、`apk-tools`、`busybox`、`ca-certificates`、`musl`、
  `openssl`、`pax-utils` 的候选材料工程项关闭；只有缺少上游 MIT grant/版权声明的
  `alpine-keys` 仍未决，法律和再分发门禁保持关闭。
- RootFS source-review materializer 新增严格仓库外下载缓存输入；缓存只替代网络
  传输，仍逐项限制大小、拒绝 symlink/重叠路径、核对固定 SHA-512，并重新验证
  解包后的 canonical aports tree；v2 receipt 会明确区分网络与缓存获取，不伪造
  selected URL，来源含糊的旧 v1 bundle 需通过缓存模式重新生成。
- 加入 checksum-bound `CORRESPONDING-SOURCE-REVIEW-RESULTS.json` 与严格验证器，
  完成 10/10 source origin、130 个规范化 aports 条目和 9 个上游 distfile 的
  对应源码候选材料工程复核。仓库外 materializer 升级为 schema v3，会把
  `SOURCE-INVENTORY.json`、审查结果、完整 typed tree 与摘要一起绑定并复验；
  重建环境/toolchain、法律审查、源码提供机制、交付批准和再分发门禁保持关闭。
- 加入可复现的 `REBUILD-ENVIRONMENT-REVIEW.json` 与
  `SOURCE-DELIVERY-INVENTORY.json`：定位 v0.3.3 历史 builder 及嵌套 iSH，
  明确其精确发布环境/归档重建仍未验证；同时记录 schema-v4 后继候选在两次独立
  调用、共四次构建中的同 host 字节级复现，以及历史/后继 builder、Alpine 输入、
  10-origin 源码材料和修改披露组成的 5 单元交付清单。材料化、source offer、法律、
  交付和再分发门禁保持关闭。
- 加入统一仓库外 RootFS 交付候选 materializer 与独立 verifier：先复验对应源码和
  LICENSE/NOTICE 候选，再从固定 Git object 为历史/后继 builder 及已初始化
  submodule 生成按 commit 内容寻址的 deterministic tar；共享依赖只保存一次，
  大小写不同的 Linux 路径不会在 host 上覆盖。工具绑定 Alpine 输入、对应源码、
  license-review evidence、LICENSE/NOTICE 候选、修改披露与合规证据，并原子生成
  receipt、typed tree 和 `SHA256SUMS`；独立复验会从候选内部重跑两条下层
  verifier。不复制 `.git`/未跟踪文件、不提交输出，source offer、法律、交付、再分发与
  `distributionAuthorized` 门禁保持关闭。
- 加入完整 Experimental graph 的 arm64 Simulator 与 unsigned device final-link gate。
- 加入 repository-owned iOS 18 native smoke App 和 runner，覆盖 17 项 prepare、boot、guest、8 MiB 持续二进制输出、stdout/stderr 超限、command、取消、recovery、shutdown 与 256 MiB Simulator 生命周期峰值内存门禁。
- native smoke 新增仓库外、未授权 RootFS 双构建候选入口：校验候选 provenance、
  receipt、identity、伴随摘要与 `distributionAuthorized=false` 后才生成临时 sidecar；
  解包器会在 guest 路径物化前丢弃有界 PAX 控制头，同时继续拒绝真实 traversal。
- 加入签名 iPhone/iPad smoke runner，通过 `devicectl` 安装、注入固定 RootFS、取回报告并校验 development entitlement；iPhone 17 Pro / iOS 26.1 基线已通过。
- 加入签名真机强制重启持久化门禁：guest 标记同步后以 SIGKILL 终止 seed PID，新 verify PID 必须复用 RootFS、恢复并清理数据，再完成标准 shutdown 与内存检查。
- 加入签名真机受限存储故障门禁：容量预检固定注入 0 可用字节，gzip 固定在 1 字节输出后注入 ENOSPC；两次失败都必须无安装残留，随后同目录正常恢复并完成标准 smoke。
- 加入签名真机有界内存警告门禁：在运行中 guest 命令期间确定性调用公开 App delegate 回调，要求新鲜回调证据、运行中与后续命令、`.ready`、shutdown 和峰值内存门禁通过；不声明真实 memory pressure 或 jetsam。
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

- Host App iPad UI smoke 通过跨元素类型的 accessibility identifier 定位系统分享面板，
  避免 iOS 18 将 `ActivityListView` 暴露为不同自动化类型时出现 XCTest 假失败。
- 将完整 Demo 与专属测试、XcodeGen 配置整理到自包含的
  `Examples/PocketRootDemo`；工程生成和构建脚本统一使用该公开示例路径，避免把
  Demo 与 Swift Package SDK 源码混在仓库根层级。
- SwiftTerm 加入后，发行组合生成器与 SPDX SBOM 同步覆盖直接 pin、解析得到但未链接的
  `swift-argument-parser`、SwiftTerm MIT notice 和 Terminal target 图；PTY 现在严格
  执行 `allowsInput=false`，SwiftUI 在 backend/session/terminal configuration 变化时
  关闭旧会话并重建控制器，theme-only 更新保持原会话。
- `README.md` 改为中文主入口，并提供完整产品状态、实现概览、接入示例、RootFS 策略和文档导航。
- 现有 Architecture、Roadmap、Upstream、ADR、Contributing、Changelog 改为中文主文档与英文镜像。
- 明确文档事实源：Roadmap 管动态状态，Upstream 管 revision/hash，Testing 管证据，ADR 管冻结决策。
- Git 贡献流程明确使用 SSH fetch/push。
- 明确默认 `PocketRootSystem.shared` 是 placeholder，真实 system 必须保存 `prepareSystem` 返回实例。
- native `shutdown()` 现在 soft-halt/join 后返回 `.terminated`；同一宿主进程仍只允许一次 lifecycle。
- IshEmbed 更新到 ABI.6：有限 streaming SPAWN 从 native API 入口覆盖 instance/spawn
  gate 与 control-queue admission；stdin close 复用原始 SPAWN deadline，terminate
  使用有界 lifecycle 接纳。PocketRoot driver 在 SPAWN 前建立统一 deadline 并把剩余
  时间传入 native，close/read 复用产品期限，超时后的 terminate/`EXITED` 确认使用独立
  的固定有界清理窗口；同时保留 ABI.4 的 signal mask、ABI.3 的 `uname` 有界复制和
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
- 签名真机 runner 现在接受 `devicectl` 可识别的 CoreDevice UUID、硬件 UDID 或设备名，
  通过官方 JSON 输出验证 physical iOS 属性，并把解析出的硬件 UDID 传给 `xcodebuild`
  和后续设备操作。
- v0.4.0-abi.6 在签名 iPhone 17 Pro / iOS 26.1 上通过当前 17 项 native smoke；
  soft shutdown 返回 Swift，完整生命周期峰值为 84.6 MiB。
- 真机 runner 增加显式 `POCKETROOT_SMOKE_LIFECYCLE=1` 模式：按 launch JSON PID
  暂停/恢复 App，并要求恢复后的 guest 命令和 shutdown 成功；Jack iPhone
  （iPhone 14 Pro / iOS 26.6）通过 18 项，峰值 89.7 MiB。
- 真机 runner 增加互斥的 `POCKETROOT_SMOKE_UI_LIFECYCLE=1` 模式：用 Settings
  触发真实 UIKit 后台/前台切换，要求原 PID 不变、三项 App delegate 回调按序到达，
  且恢复后的 guest 命令成功；Jack iPhone 通过 18 项，峰值 89.4 MiB。

### Security

- RootFS 归档仍不提交、不打包、不由 library 下载。
- 生产、TestFlight 与公开 binary distribution 在 license、NOTICE、对应源码、SBOM、真机和 App Store 2.5.2 门禁完成前保持阻塞。
