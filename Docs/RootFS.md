# RootFS 安全方案

[简体中文](RootFS.md) | [English](en/RootFS.md) | [文档中心](README.md)

RootFS 是 PocketRoot 的外部供应链输入，不是普通测试 fixture。仓库提交的是不可变清单、校验和安全安装代码，不提交、镜像或默认打包 RootFS 二进制。

> [!WARNING]
> 固定 v0.3.3 归档已有可复现 package inventory、SPDX SBOM 和默认配置证据，但许可证文本、包级 NOTICE、对应源码 bundle 与发行批准仍未闭环。以下 URL 与命令用于审计和本地开发，不构成公开再分发授权。应用必须先完成自己的法律与发行审查。

## 1. 固定清单

`PocketRootRootFSArtifactManifest.ishEmbedV0_3_3` 记录：

| 字段 | 值 |
| --- | --- |
| 版本 | `v0.3.3` |
| 架构 | `arm64` |
| 格式 | iSH `fakefs tar.gz` |
| Guest | Alpine `3.19.1 aarch64` |
| 上游 URL | `https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/fs.tar.gz` |
| 压缩大小 | `6,581,376` 字节 |
| 展开 tar 大小 | `18,838,016` 字节 |
| SHA-256 | `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4` |

`downloadURL` 只是清单元数据。`PocketRootRootFSInstaller` 和组合 factory 都不会读取它或发起下载。

更完整的来源、上游 commit 和许可证事实见[上游依赖清单](UpstreamDependencies.md)。

## 2. 资产所有权边界

调用方负责：

- 决定是否允许网络获取；
- 取得合法、经过审核的 archive；
- 把 archive 放入 App 可访问的本地路径；
- 处理用户同意、缓存、删除和数据保留策略；
- 确认许可证、NOTICE、对应源码与 SBOM；
- 在 manifest 变更时重新审核。

PocketRoot 负责：

- 确认输入是本地普通文件；
- 固定大小和 SHA-256；
- 把调用方路径隔离成私有 snapshot；
- 安全解包；
- 校验 fakefs 布局；
- 版本化、journal 保护的同卷 promotion；
- 复用、可回滚替换与中断恢复。

PocketRoot 不负责：

- 下载、更新或选择最新版本；
- 证明调用方拥有再分发权；
- 对 archive 内每个 guest 文件单独签名；
- 在每次安装时执行 SQLite `integrity_check`；
- 在当前版本中完成 VM 数据迁移或用户数据备份。

## 3. 本地获取与独立验证

仅在完成资产使用审查后，开发者可以把文件下载到仓库外的本地路径：

```bash
ROOTFS_ARCHIVE=/absolute/path/outside-the-repository/fs-v0.3.3.tar.gz

curl --fail --location --retry 3 \
  --output "$ROOTFS_ARCHIVE" \
  "https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/fs.tar.gz"

test "$(stat -f '%z' "$ROOTFS_ARCHIVE")" = "6581376"

printf '%s  %s\n' \
  'be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4' \
  "$ROOTFS_ARCHIVE" \
  | shasum -a 256 --check
```

仓库中的 [`Compliance/RootFS/v0.3.3`](../Compliance/RootFS/v0.3.3/README.md)
包含从这个精确 archive 生成的 15 个二进制包清单、10 个 source origin、SPDX 2.3
JSON SBOM、声明许可证清单、attribution inventory、`apk`/repository/DNS 配置快照和
输入摘要。生成器先验证大小与 SHA-256，再只读取固定的小型元数据成员：

```bash
ruby Scripts/generate-rootfs-compliance.rb \
  --archive "$ROOTFS_ARCHIVE" \
  --check
```

这完成的是可复现的工程事实记录。archive 内没有随附可识别的
LICENSE/COPYING/NOTICE 文件；完整第三方许可证/NOTICE bundle、build recipe/patch、
上游源码和构建说明组成的对应源码 bundle 仍是独立发行门禁。

不要把归档放入 `Sources/PocketRootResources/Resources`、Demo resources 或 Git LFS。合规完成前，`PocketRootBundledRootFSProvider` 的资源查找预期返回 `nil`。

把 Files/document picker 或受控下载结果复制进 App sandbox，并生成
`localReviewedArchiveURL` 的完整 Swift 示例见[应用接入指南](IntegrationGuide.md#把归档送入-app-沙箱)。

## 4. 公共 API

### 通过组合 factory

推荐应用路径：

```swift
let prepared = try await PocketRootIshSystemFactory.prepareSystem(
    archiveURL: localReviewedArchiveURL,
    applicationSupportURL: applicationSupportURL
)

print(prepared.installation.version)
print(prepared.installation.rootFSURL)
print(prepared.installation.reusedExistingInstallation)
```

### 只使用安装器

不需要立即创建 runtime 时：

```swift
import PocketRootResources

let installer = PocketRootRootFSInstaller(
    baseDirectoryURL: applicationSupportURL,
    manifest: .ishEmbedV0_3_3
)

let installation = try await installer.prepareArchive(
    at: localReviewedArchiveURL
)
```

`baseDirectoryURL` 必须是调用方已经创建的真实本地目录。installer 会创建并持久化其下的
`rootfs/`，但不会递归创建并承诺未知祖先目录的掉电持久性。

### Bundled provider

`PocketRootBundledRootFSProvider` 只查找 `Bundle.module` 中明确加入的资源。当前仓库没有 archive，因此：

- `isRootFSBundled == false`；
- `rootFSArchiveURL() == nil`；
- `prepareRootFS` 抛出 `resourceMissing`。

只有发行审查通过、清单和合规材料一并更新后，才能改变这个行为。

## 5. 威胁模型

安装器防护的主要风险：

| 风险 | 防护 |
| --- | --- |
| 调用方传入 symlink、FIFO 或设备文件 | `O_NOFOLLOW` + `fstat` regular-file 检查 |
| 校验后原路径被替换 | 只解包私有 snapshot，并在前后校验同一文件 |
| archive 过大导致磁盘/内存耗尽 | 压缩、展开、payload 和 entry count 上限 |
| 新安装峰值空间明显不足 | staging 前按 snapshot、临时 tar、payload 和 16 MiB 余量预检同卷容量 |
| 中途 ENOSPC 留下半文件或破坏旧安装 | snapshot/gzip/tar/record/journal/current 故障矩阵、staging cleanup 和 promotion rollback |
| 突然掉电导致 journal、rename 与 current 顺序漂移 | 候选树、记录文件和相关父目录的显式持久化屏障；按 journal/final/backup 推断恢复 |
| tar 绝对路径或 `..` 逃逸 | UTF-8 相对路径规范化与 destination containment |
| symlink/hardlink 绕过目标目录 | 拒绝 link 和特殊 entry type |
| 重复文件或目录覆盖 | 隐式父目录也登记为 archive target；拒绝后续映射到同一路径或同一文件系统目标的重复 entry |
| 候选布局不是 iSH fakefs | 要求真实 `fs/meta.db` 与 `fs/data/` |
| 替换中途失败破坏旧版本 | persistent transaction + rollback |
| 进程在 rename 中途退出 | 下次准备时读取 journal，根据 final 是否匹配预期、backup 是否存在以及旧安装事实完成 commit 或恢复 |
| 多任务同时安装 | 进程级串行 installation executor |

不在当前保证范围：

- 恶意但哈希已经被错误清单认可的内容；
- guest 内运行时漏洞；
- App 自己下载阶段的 TLS、认证或缓存策略；
- 真机存储压力、强制断电实证、jetsam 与持续内存峰值；
- 许可证合规；
- 用户生成 VM 数据的迁移与备份。

## 6. 安装步骤

```mermaid
flowchart TD
    A["调用方本地普通文件"] --> B["O_NOFOLLOW + fstat"]
    B --> C["同卷私有 staging snapshot"]
    C --> D["大小 + SHA-256"]
    D --> E["zlib 流式 gzip"]
    E --> F["受限 ustar 解包"]
    F --> G["再次校验 snapshot"]
    G --> H["验证 fs/meta.db + fs/data"]
    H --> I["写安装记录并持久化候选树"]
    I --> J["持久化 journal"]
    J --> K["同卷 rename + 同步父目录"]
    K --> L["原子更新并持久化 current.json"]
```

### 输入 snapshot

- 仅在目标版本不能安全复用时预检容量；有效现有版本不要求重新安装空间。
- 新安装预算为压缩 archive 上限、两倍展开上限和 16 MiB；自定义 extractor 比
  manifest 更宽时采用两者较大的展开上限。两份展开预算分别覆盖 gzip 生成的临时 tar，
  以及 tar 仍存在时写出的 payload。
- 容量不足返回 `insufficientStorage(requiredBytes:availableBytes:)`，且发生在
  本次新 staging 或 replacement transaction 创建前。
- 源文件只打开一次。
- 目标使用 exclusive create。
- snapshot 权限仅允许当前用户。
- 复制时检查 archive byte ceiling 和任务取消。
- staging 与最终目录位于同一 base volume。

### 解包边界

gzip 层使用 zlib streaming。tar 层只支持项目需要的 ustar subset：

- 普通文件；
- 目录；
- 可忽略内容的 PAX 扩展记录。

拒绝：

- 符号链接；
- 硬链接；
- character/block device；
- FIFO；
- 绝对路径；
- 路径中的 `.` 或 `..`；
- 重复目标；
- header checksum 错误；
- 非 UTF-8 路径；
- 超出条目、payload 或展开大小上限。

### fakefs 校验

最终 archive 顶层必须存在 `fs/`：

```text
fs/
├── meta.db    # 真实普通文件
└── data/      # 真实目录
```

root、`meta.db`、`data/` 都不能是 symlink。完整 guest 内容由 archive SHA-256 保证，不逐文件重新散列。

安装器验证 `extracted/fs` 后，把这个 `fs/` 目录本身作为候选提升到
`rootfs/<version>`。因此 `fs/` 是归档格式的一部分，不会成为最终安装中的额外目录层。

## 7. 存储和复用

```text
applicationSupportURL/
└── rootfs/
    ├── current.json
    ├── .installing-<uuid>/
    ├── .replacement-transaction/
    │   ├── journal.json
    │   └── previous/
    └── v0.3.3/
        ├── .pocketroot-rootfs.json
        ├── meta.db
        └── data/
```

复用需要同时满足：

- 版本目录存在；
- fakefs 布局仍有效；
- 版本内安装记录与 manifest 匹配。

`current.json` 只是当前版本索引，不参与判断版本目录本身是否可复用。它缺失、内容不匹配
或指向其他版本时，只要目标版本目录及其安装记录有效，installer 仍会复用并在返回前原子
重写 `current.json`。

如果版本内容损坏或版本内记录漂移，installer 从新 snapshot 生成候选并替换。promotion
失败时回滚到最后一个旧版本，并恢复 promotion 开始前的 `current.json` 数据状态。

容量预检读取 `rootfs/` 所在卷的 important-usage 可用容量。它防止已知 manifest 在明显
空间不足时开始写入，但不预留空间；其他进程仍可能在预检后消耗容量。因此中途文件系统
错误仍依赖 staging cleanup、promotion rollback 和下次启动 recovery。确定性 ENOSPC
注入覆盖 snapshot、gzip 部分 tar、tar payload、安装记录、journal 和 current record；
每个失败点都验证旧安装和原始 `current.json` 保持不变，且 staging/transaction 不残留。

## 8. 中断恢复

replacement journal **不记录 phase**。它保存目标版本、预期安装记录、promotion 开始时是否
存在旧安装，以及旧 `current.json` 的原始数据。下次 `prepareArchive` 在清理 staging 之前，
根据 final 是否匹配预期记录、backup 是否存在以及旧安装事实推断恢复动作：

- final 与预期安装记录匹配 → 候选 rename 已完成，重写 `current.json` 并删除 transaction；
- final 无效且 `previous/` 存在 → 移除无效 final，把 backup rename 回 final，并恢复旧 current 数据；
- journal 声明曾有旧安装但没有 backup → 第一次 rename 尚未完成，要求旧安装仍在 final，再恢复旧 current 数据；
- 原本没有旧安装且 final 无效 → 移除残留 final，并恢复或删除 current record。

transaction 目录存在但 journal 文件尚未写入时，不会有破坏性 rename；这种无 journal 的残留
可直接清理。恢复完成后再清理 `previous/`、journal 与 transaction 目录。

恢复操作本身也要求路径保持在 installation root 内，并避免跟随 symlink。各次同卷 rename
和 JSON 原子写入分别具备原子性，但多步 promotion 整体不是单次原子替换；安全性来自先写
journal、失败回滚与下次准备时的状态推断恢复。

promotion 前，installer 从叶到根对候选树的普通文件执行 `F_FULLFSYNC`（文件系统不支持时
回退 `fsync`），再同步目录。journal 和 `current.json` 通过私有临时文件完整写入、同步、
原子 rename 和父目录同步提交；每次跨目录 rename 后同步源、目标父目录。顺序保证 journal
在破坏性 rename 前持久化，候选内容在成为 final 前持久化，`current.json` 在清理 transaction
前持久化。rollback 和 recovery 的 rename、记录恢复与删除同样同步相关父目录。

确定性 fault matrix 覆盖候选树、journal 文件/目录、旧版本 rename、新候选 rename 和
`current.json` 文件/目录七个持久化屏障；另外构造 journal-only、旧版本已进入 backup、
候选已成为 final 等掉电切点状态，验证能够推断 rollback 或 commit。这建立了实现和宿主
文件系统层面的持久化顺序保证；真机强制断电后的硬件/文件系统实证仍单独维护。

## 9. 测试边界

已覆盖：

- 固定 manifest；
- 大小和 SHA-256；
- 安全解包和恶意 tar entry；
- 安装、复用、损坏替换；
- 不存在的 base directory 拒绝，以及 mode `000` 候选条目持久化后权限保持；
- caller-path replacement；
- bounded copy；
- 并发准备；
- promotion failure rollback；
- 安装前容量不足、刚好满足容量预算，以及低空间升级保持旧版本；
- snapshot、gzip 部分输出、tar payload、安装记录、journal 和 current record 的
  ENOSPC cleanup/rollback；
- 旧安装已移动和候选已提升两个破坏性 checkpoint 的 ENOSPC rollback；
- 七个文件/目录持久化屏障的同步失败 rollback；
- journal-only、backup 和 candidate/final 断电切点的 interrupted rollback/commit；
- 精确 v0.3.3 release asset 集成。

仍需：

- 大归档持续内存峰值；
- 真机 storage pressure；
- 真机强制断电实证；
- 用户 VM 数据迁移；
- 合规材料完整性自动检查。

命令见[测试与验证](Testing.md)。

## 10. 更新 RootFS 的规则

任何新版本必须：

1. 固定上游源码 commit 与所有 nested gitlink；
2. 记录原始 Alpine minirootfs 来源和 digest；
3. 审查 build script 与本地修改；
4. 独立计算 archive 大小、展开上限和 SHA-256；
5. 审查 fakefs 布局和 guest package；
6. 更新 manifest 与测试；
7. 运行真实资产测试、最终链接、Simulator 和真机 smoke；
8. 重新生成许可证、NOTICE、对应源码和 SBOM；
9. 更新[上游依赖清单](UpstreamDependencies.md)、[ADR](Decisions/ADR-001-IshEmbed-Feasibility.md)和[发行与合规](ReleaseCompliance.md)。

移动 tag、branch、缓存文件或未记录的本地 archive 都不能替代这个过程。
