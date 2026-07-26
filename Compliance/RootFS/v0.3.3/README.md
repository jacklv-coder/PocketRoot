# RootFS v0.3.3 合规证据 / Compliance evidence

这里保存从固定 RootFS archive 可复现生成的工程证据，不保存 RootFS 本身。

This directory stores reproducible engineering evidence generated from the
pinned RootFS archive. It does not store the RootFS payload.

## 已生成 / Generated

- `PACKAGE-INVENTORY.tsv`：15 个已安装二进制包的完整 APK database 清单；
- `SBOM.spdx.json`：通过 SPDX 2.3 JSON schema 验证的 machine-readable SBOM；
- `SOURCE-INVENTORY.json`：10 个 source origin、精确 aports commit 和 build recipe
  locator；
- `SOURCE-ACQUISITION.json`：与 inventory 一一对应的 aports snapshot、upstream
  distfile URL 和 SHA-512，以及覆盖条目类型、路径、普通文件权限位与内容的规范化目录
  SHA-256；
- `LICENSE-INVENTORY.json`：声明的许可证表达式、标识符和 archive 内
  license/notice 文件检查结果；
- `LICENSE-REVIEW.json`：覆盖 10 个 source origin 的 21 个候选许可证文本、
  attribution、声明与内联 notice 的路径、大小、SHA-256 和逐包未决审查项；
- `LICENSE-REVIEW-RESULTS.json`：对全部 21 个候选的 checksum-bound 工程复核
  结论、coverage 和未决项处置；不表示法律或再分发批准；
- `LICENSE-NOTICE-CANDIDATES.json`：为剩余 8 个 source origin 固定 8 份远端
  许可证/attribution 材料、46 份 aports 补充文件及现有 21 份复核证据的外置候选包；
  payload 不提交，工程、法律和再分发门禁保持关闭；
- `RUNTIME-CONFIGURATION.json`：guest、`apk`、repository、world 和 DNS 默认配置；
- `NOTICE.md`：可复现 attribution inventory 与尚未完成事项；
- `EVIDENCE.json`：输入成员摘要、数量和明确的工程/发行状态；
- `SHA256SUMS`：上述生成文件的 SHA-256。

`SOURCE-ACQUISITION.json` pins the aports snapshots and upstream distfiles
needed to assemble an external source-review directory. It is an acquisition
manifest, not a committed source archive or redistribution grant.
`LICENSE-REVIEW.json` pins 21 unreviewed candidate evidence files across all
10 source origins; it is an engineering review index, not legal approval.
`LICENSE-REVIEW-RESULTS.json` records the engineering review of all 21 pinned
candidates. Two source origins have no remaining indexed review items; eight
still have package-specific open items. `LICENSE-NOTICE-CANDIDATES.json`
indexes an external candidate bundle for those eight origins: 8 pinned remote
license/attribution payloads, 46 supplemental aports files, and the existing
21 reviewed evidence files. It neither commits those payloads nor approves
engineering, legal, or redistribution gates.

## 重新生成 / Regenerate

先把经授权使用的固定 archive 放在仓库外，再运行：

Keep an authorized copy of the pinned archive outside the repository, then run:

```bash
ruby Scripts/generate-rootfs-compliance.rb \
  --archive /absolute/path/outside-the-repository/fs.tar.gz
```

只校验而不改写文件：

Check committed output without rewriting it:

```bash
ruby Scripts/generate-rootfs-compliance.rb \
  --archive /absolute/path/outside-the-repository/fs.tar.gz \
  --check
```

生成器会先验证固定大小和 SHA-256，只读取 archive 中已知的小型元数据成员，不展开
RootFS 到仓库。CI 对同一个固定 release archive 执行 `--check`。

The generator verifies the pinned size and SHA-256 first, reads only known
small metadata members, and does not extract the RootFS into the repository.
CI runs `--check` against the same pinned release archive, verifies the pinned
official SPDX 2.3 schema digest, and validates `SBOM.spdx.json` with
the repository-owned validator and the integrity-locked `ajv@8.20.0`
dependency tree. Node.js/npm are host CI tools for that validation only; they
are not installed in the App or RootFS.

只校验源码获取清单与固定 package/source inventory 是否一致：

Validate the source-acquisition manifest against the pinned package/source
inventory without downloading:

```bash
ruby Scripts/prepare-rootfs-source-bundle.rb --validate-only
```

如审查人员需要本地材料，可生成到一个尚不存在、位于仓库外的绝对路径。脚本会依次
校验 aports archive SHA-512、解包后的规范化目录 SHA-256（包括普通文件权限位）
和所有 upstream distfile SHA-512，并以临时目录完成后原子提升：

To prepare local review material, choose a new absolute directory outside the
repository. The script verifies each aports archive and canonical extracted
tree—including regular-file permission bits—plus every upstream distfile
before atomically promoting the result:

```bash
ruby Scripts/prepare-rootfs-source-bundle.rb \
  --output /absolute/new/path/outside-the-repository/rootfs-v0.3.3-source-review

ruby Scripts/prepare-rootfs-source-bundle.rb \
  --verify /absolute/new/path/outside-the-repository/rootfs-v0.3.3-source-review
```

`--verify` 同时核对所有普通文件摘要、目录集合和符号链接目标。该输出不会被 App、
Git 或 CI artifact 自动打包或上传。

`--verify` checks every regular-file digest, the directory set, and symbolic
link targets. The output is never automatically bundled into the App,
committed to Git, or uploaded as a CI artifact.

在已有外置 source-review 目录的基础上，可校验逐包候选清单，或提取到另一个
尚不存在的仓库外目录：

Given that external source-review directory, validate the package-level
candidate index or extract it into another new directory outside the repository:

```bash
ruby Scripts/prepare-rootfs-license-review.rb --validate-only

ruby Scripts/prepare-rootfs-license-review.rb \
  --source-bundle /absolute/rootfs-v0.3.3-source-review \
  --output /absolute/new/rootfs-v0.3.3-license-review

ruby Scripts/prepare-rootfs-license-review.rb \
  --source-bundle /absolute/rootfs-v0.3.3-source-review \
  --verify /absolute/rootfs-v0.3.3-license-review

ruby Scripts/rootfs-license-review-results.rb
```

工具只提取 `LICENSE-REVIEW.json` 固定的候选文件，并再次核对大小、SHA-256、
路径全集、无符号链接/特殊节点边界。结果清单证明 21 个候选已完成工程复核；
外置输出仍不是可直接随产品发行的 NOTICE bundle。

The tool extracts only candidates pinned by `LICENSE-REVIEW.json`, then
rechecks byte counts, SHA-256 digests, the exact path set, and the no-symlink/
special-node boundary. The results manifest proves engineering review of all
21 candidates; the external output is still not a product-ready NOTICE bundle.

剩余 8 个 source origin 的材料可继续组装为外置候选包。先校验清单；实际物化
必须同时提供已经通过 `--verify` 的 source-review 和 license-review 目录，以及
一个尚不存在的仓库外输出路径：

The remaining eight origins can be assembled into an external candidate
bundle. Validate the manifest first. Materialization requires source-review
and license-review directories that already pass `--verify`, plus a new output
path outside the repository:

```bash
ruby Scripts/rootfs-license-notice-candidates.rb
ruby Scripts/prepare-rootfs-license-notice-bundle.rb --validate-only

ruby Scripts/prepare-rootfs-license-notice-bundle.rb \
  --source-bundle /absolute/rootfs-v0.3.3-source-review \
  --license-review /absolute/rootfs-v0.3.3-license-review \
  --output /absolute/new/rootfs-v0.3.3-license-notice-candidates

ruby Scripts/prepare-rootfs-license-notice-bundle.rb \
  --source-bundle /absolute/rootfs-v0.3.3-source-review \
  --license-review /absolute/rootfs-v0.3.3-license-review \
  --verify /absolute/rootfs-v0.3.3-license-notice-candidates
```

远端材料由固定 URL、字节数和 SHA-256 约束；可选 `--download-cache` 只读取以
`cacheKey` 命名的本地普通文件并再次校验。输出包含候选 NOTICE、receipt 和
`SHA256SUMS`，但仍是工程审查输入，不是产品 NOTICE、法律意见或再分发批准。

Remote payloads are pinned by URL, byte count, and SHA-256. An optional
`--download-cache` reads only local regular files named by each `cacheKey` and
revalidates them. The output includes a candidate NOTICE, receipt, and
`SHA256SUMS`; it remains engineering-review input, not a product NOTICE, legal
advice, or redistribution approval.

## 未解除的门禁 / Open gates

这些文件不构成完整第三方 LICENSE/NOTICE bundle、经审查的 copyleft
corresponding-source 交付、法律意见或再分发授权。源码获取清单已完整覆盖固定
inventory，21 个候选也都有工程复核结果；`libc-dev`、`zlib` 已关闭索引项，另外
8 个 source origin 的新候选材料仍需工程/法律复核和包级版权/notice 确认。修改说明、构建完整性、
源码提供方式、App Store 2.5.2 产品策略和负责人批准仍是发行阻塞项。

These files are not a complete third-party LICENSE/NOTICE bundle, reviewed
copyleft corresponding-source delivery, legal advice, or redistribution
approval. The acquisition manifest completely covers the pinned inventory and
all 21 indexed candidates have engineering review results. `libc-dev` and
`zlib` have no remaining indexed items; eight source origins still need
engineering/legal review of the newly indexed candidates and package-specific
notice follow-up. Modification, build
completeness, source-offer mechanics, legal review, App Store 2.5.2 product
policy, and authorized approval remain distribution blockers.
