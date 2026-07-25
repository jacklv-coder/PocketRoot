# RootFS v0.3.3 合规证据 / Compliance evidence

这里保存从固定 RootFS archive 可复现生成的工程证据，不保存 RootFS 本身。

This directory stores reproducible engineering evidence generated from the
pinned RootFS archive. It does not store the RootFS payload.

## 已生成 / Generated

- `PACKAGE-INVENTORY.tsv`：15 个已安装二进制包的完整 APK database 清单；
- `SBOM.spdx.json`：通过 SPDX 2.3 JSON schema 验证的 machine-readable SBOM；
- `SOURCE-INVENTORY.json`：10 个 source origin、精确 aports commit 和 build recipe
  locator；
- `LICENSE-INVENTORY.json`：声明的许可证表达式、标识符和 archive 内
  license/notice 文件检查结果；
- `RUNTIME-CONFIGURATION.json`：guest、`apk`、repository、world 和 DNS 默认配置；
- `NOTICE.md`：可复现 attribution inventory 与尚未完成事项；
- `EVIDENCE.json`：输入成员摘要、数量和明确的工程/发行状态；
- `SHA256SUMS`：上述生成文件的 SHA-256。

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

## 未解除的门禁 / Open gates

这些文件不构成完整第三方 LICENSE/NOTICE bundle、copyleft corresponding-source
bundle、法律意见或再分发授权。完整许可证文本、包级版权/notice、build recipe 与 patch、
上游源码、构建说明、App Store 2.5.2 产品策略和负责人批准仍是发行阻塞项。

These files are not a complete third-party LICENSE/NOTICE bundle, a copyleft
corresponding-source bundle, legal advice, or redistribution approval. License
texts, package-specific copyright/notice material, recipes and patches,
upstream sources, build instructions, the App Store 2.5.2 product policy, and
authorized approval remain distribution blockers.
