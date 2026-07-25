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
  distfile URL 和 SHA-512/规范化目录 SHA-256；
- `LICENSE-INVENTORY.json`：声明的许可证表达式、标识符和 archive 内
  license/notice 文件检查结果；
- `RUNTIME-CONFIGURATION.json`：guest、`apk`、repository、world 和 DNS 默认配置；
- `NOTICE.md`：可复现 attribution inventory 与尚未完成事项；
- `EVIDENCE.json`：输入成员摘要、数量和明确的工程/发行状态；
- `SHA256SUMS`：上述生成文件的 SHA-256。

`SOURCE-ACQUISITION.json` pins the aports snapshots and upstream distfiles
needed to assemble an external source-review directory. It is an acquisition
manifest, not a committed source archive or redistribution grant.

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
校验 aports archive SHA-512、解包后的规范化目录 SHA-256 和所有 upstream
distfile SHA-512，并以临时目录完成后原子提升：

To prepare local review material, choose a new absolute directory outside the
repository. The script verifies each aports archive and canonical extracted
tree plus every upstream distfile before atomically promoting the result:

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

## 未解除的门禁 / Open gates

这些文件不构成完整第三方 LICENSE/NOTICE bundle、经审查的 copyleft
corresponding-source 交付、法律意见或再分发授权。源码获取清单已完整覆盖固定
inventory，但生成出的外置审查目录仍需核对许可证文本、包级版权/notice、修改说明、
构建完整性与源码提供方式；App Store 2.5.2 产品策略和负责人批准仍是发行阻塞项。

These files are not a complete third-party LICENSE/NOTICE bundle, reviewed
copyleft corresponding-source delivery, legal advice, or redistribution
approval. The acquisition manifest completely covers the pinned inventory, but
its external review directory still requires review of license texts,
package-specific copyright/notices, modifications, build completeness, and
source-offer mechanics. The App Store 2.5.2 product policy and authorized
approval also remain distribution blockers.
