# PocketRoot experimental release-composition evidence

此目录记录 `0.1.0` 源码树可复现的**最大实验组合**，不是已构建、
已扫描或获准发行的 App 制品。`COMPOSITION.json` 区分默认 Demo、原生 runtime
smoke 与全部 Swift products；`SBOM.spdx.json` 汇总 PocketRoot、固定 ABI.6
IshEmbed/XCFramework、精确 iSH gitlink、静态 supervisor 使用的 musl source、
固定 SwiftTerm 与其解析依赖，以及调用方提供的外部 RootFS 和其中 15 个 Alpine 包。

默认 Demo 不包含 IshEmbed 或 RootFS。RootFS 不由库下载，也不进入默认 App。
顶层许可证、完整 LICENSE/NOTICE、对应源码交付、App Store 2.5.2、法律审查和
发行授权仍未完成。由于没有最终 archive，本目录明确保持
`completeReleaseArtifactSBOM=false`、`distributionAuthorized=false`。

校验：

```bash
ruby Scripts/generate-release-compliance.rb --check
```

## English

This directory records the reproducible **maximal experimental
composition** of the `0.1.0` source tree. It is not a built,
scanned, or authorized App artifact. `COMPOSITION.json` distinguishes the
default Demo, native-runtime smoke, and all Swift products.
`SBOM.spdx.json` combines PocketRoot, pinned ABI.6 IshEmbed/XCFramework,
the exact iSH gitlink, the musl source snapshot used by the static guest
supervisor, pinned SwiftTerm and its resolved dependency, and the
caller-provided external RootFS with its 15 Alpine packages.

The default Demo contains neither IshEmbed nor a RootFS. The library does
not download the RootFS or place it in the default App. The top-level
license, complete LICENSE/NOTICE set, corresponding-source delivery,
App Store 2.5.2 disposition, legal review, and distribution authorization
remain open. Because no final archive was scanned, this evidence keeps
`completeReleaseArtifactSBOM=false` and `distributionAuthorized=false`.
