# PocketRoot experimental release-composition evidence

此目录记录 `0.1.0` 源码树可复现的**最大实验组合**，不是已构建、
已扫描或获准发行的 App 制品。`COMPOSITION.json` 区分默认 Demo、独立宿主示例、
原生 runtime smoke 与全部 Swift products；`SBOM.spdx.json` 汇总 PocketRoot、固定 ABI.9
IshEmbed/XCFramework、精确 iSH gitlink、静态 supervisor 使用的 musl source、
固定 SwiftTerm 与其解析依赖，以及调用方提供的外部 RootFS 和其中 15 个 Alpine 包。
`READINESS.json` 和 `RELEASE-CHECKLIST.md` 把源码/Swift Package 发布与
不含 RootFS 资产的 runtime/App/二进制分发拆成两个独立、默认关闭的轨道。

默认 Demo 显式链接 IshEmbed，但仓库不包含 RootFS；只有本地 Debug 构建可把
精确固定的仓库外资产注入 App，Release 明确跳过。RootFS 不由库下载。
PocketRoot 原创源码已依据 MIT 获准发布；Runtime 的完整 LICENSE/NOTICE、
对应源码交付、App Store 2.5.2、法律审查和发行授权仍未完成。由于没有最终
archive，本目录明确保持
`completeReleaseArtifactSBOM=false`、`distributionAuthorized=false`。
`finalArtifactEvidence.status=not-provided` 还会阻止 Runtime 轨道在没有精确
制品清单、SBOM 和人工复核 SHA-256 的情况下变为 Ready。

校验：

```bash
ruby Scripts/generate-release-compliance.rb --check
ruby Scripts/generate-release-compliance.rb --status
```

## English

This directory records the reproducible **maximal experimental
composition** of the `0.1.0` source tree. It is not a built,
scanned, or authorized App artifact. `COMPOSITION.json` distinguishes the
default Demo, standalone host example, native-runtime smoke, and all
Swift products.
`SBOM.spdx.json` combines PocketRoot, pinned ABI.9 IshEmbed/XCFramework,
the exact iSH gitlink, the musl source snapshot used by the static guest
supervisor, pinned SwiftTerm and its resolved dependency, and the
caller-provided external RootFS with its 15 Alpine packages.
`READINESS.json` and `RELEASE-CHECKLIST.md` split source/Swift Package
release from runtime/App/binary distribution that excludes every RootFS
asset into two independent, fail-closed tracks.

The default Demo explicitly links IshEmbed, but the repository contains
no RootFS. Only a local Debug build may inject the exact pinned external
asset; Release skips it. The library never downloads the RootFS. The
original PocketRoot source is authorized for release under MIT. The Runtime's
complete LICENSE/NOTICE set, corresponding-source delivery, App Store 2.5.2
disposition, legal review, and distribution authorization remain open.
Because no final archive was scanned, this evidence keeps
`completeReleaseArtifactSBOM=false` and `distributionAuthorized=false`.
`finalArtifactEvidence.status=not-provided` also prevents the runtime
track from becoming Ready without an exact artifact inventory, SPDX SBOM,
and code-reviewed artifact SHA-256.
