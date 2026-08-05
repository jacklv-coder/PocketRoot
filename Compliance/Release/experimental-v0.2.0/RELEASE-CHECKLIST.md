# PocketRoot v0.2.0 Release Candidate Checklist

当前状态：**Blocked / 不可发布**。

本清单把“源码/Swift Package 发布”和“不包含任何 RootFS 资产的
runtime、App 或二进制 SDK 分发”分为两条独立轨道。工程测试通过不等于获得
额外分发授权；源码轨道 Ready 不会自动解除 runtime 轨道。

## 源码与 Swift Package 发布（Ready / 已就绪）

- [x] `source-boundary-excludes-rootfs` — 源码发布不包含 RootFS 载荷
- [x] `public-api-status-declared` — 公共 API 状态已声明为 Experimental
- [x] `top-level-license-finalized` — PocketRoot 顶层许可证已确定
- [x] `contributor-policy-approved` — 贡献者与版权政策已批准
- [x] `release-notice-approved` — 源码发行 NOTICE 已批准
- [x] `source-release-authorized` — PocketRoot 源码发布已明确授权

PocketRoot 原创源码的顶层许可证已由项目所有者确定为 MIT；贡献政策与
`NOTICE.md` 同步生效。源码轨道 Ready 不授权 Runtime、RootFS、App 或二进制
分发。

## Runtime / App / 二进制分发（不含 RootFS，Blocked / 未就绪）

- [x] `runtime-top-level-license-finalized` — Runtime 分发使用的 PocketRoot 顶层许可证已确定
- [ ] `rootfs-external-input-boundary` — RootFS 保持为调用方提供的本地输入
- [ ] `release-artifact-built-and-scanned` — 最终签名导出制品已构建并扫描
- [ ] `complete-license-notice-bundle-approved` — 完整 LICENSE 与 NOTICE 交付包已批准
- [ ] `corresponding-source-delivery-approved` — 对应源码交付已批准
- [ ] `app-store-policy-approved` — App Store 可执行代码策略已批准
- [ ] `privacy-review-approved` — Runtime 隐私与数据生命周期评审已批准
- [ ] `runtime-legal-review-approved` — 完整 Runtime 分发法律评审已批准
- [ ] `runtime-distribution-authorized` — Runtime 二进制/App 分发已明确授权

RootFS 当前只能作为调用方自行取得并授权的本地输入；不得把它加入 Git、
SwiftPM、GitHub Release、TestFlight 或 App bundle。Runtime 轨道同样要求
PocketRoot 顶层许可证已确定。当前 `Scripts/scan-release-artifact.rb`
只生成工程证据；即使扫描签名 `.xcarchive`，也固定保持
`engineering-evidence-only`、`releaseSignatureValid=false` 和
`rootFSExcluded=false`。它可以把
`Compliance/Release/FinalArtifact/v0.2.0/ARTIFACT-INVENTORY.json` 与
`SBOM.spdx.json` 纳入 composition，但不能解除 runtime 门禁。后续专用最终
发布验证 schema 必须把签名、entitlement 和风险元数据绑定到被复核的制品，
并提供内容级 RootFS 排除证明；仅靠内容树摘要、路径、文件名或扩展名不足。

## 校验

```bash
ruby Scripts/generate-release-compliance.rb --check
ruby Scripts/generate-release-compliance.rb --status
ruby Scripts/generate-release-compliance.rb --require-source-ready
ruby Scripts/generate-release-compliance.rb --require-runtime-ready
```

两个 `--require-*-ready` 命令分别反映各自轨道；源码轨道当前返回成功，
Runtime 轨道仍故意返回非零状态。

## English

Current status: **Blocked / not releasable**.

This checklist separates a source/Swift Package release from runtime,
App, archive, or binary SDK distribution that excludes every RootFS asset.
Passing engineering tests is not additional distribution authorization,
and the Ready source track does not unblock the runtime track.

### Source and Swift Package release (Ready)

- [x] `source-boundary-excludes-rootfs` — Source release excludes the RootFS payload
- [x] `public-api-status-declared` — Public API status is declared experimental
- [x] `top-level-license-finalized` — Top-level PocketRoot license is finalized
- [x] `contributor-policy-approved` — Contributor and copyright policy is approved
- [x] `release-notice-approved` — Source-release notice is approved
- [x] `source-release-authorized` — PocketRoot source release is explicitly authorized

The project owner selected MIT for original PocketRoot source. The
contributor policy and `NOTICE.md` apply with it. A Ready source track
does not authorize Runtime, RootFS, App, or binary distribution.

### Runtime / App / binary distribution (RootFS excluded, Blocked)

- [x] `runtime-top-level-license-finalized` — Top-level PocketRoot license is finalized for runtime distribution
- [ ] `rootfs-external-input-boundary` — RootFS remains a caller-provided local input
- [ ] `release-artifact-built-and-scanned` — Final signed and exported artifact is built and scanned
- [ ] `complete-license-notice-bundle-approved` — Complete LICENSE and NOTICE bundle is approved
- [ ] `corresponding-source-delivery-approved` — Corresponding-source delivery is approved
- [ ] `app-store-policy-approved` — App Store executable-code policy is approved
- [ ] `privacy-review-approved` — Runtime privacy and data-lifecycle review is approved
- [ ] `runtime-legal-review-approved` — Complete runtime distribution legal review is approved
- [ ] `runtime-distribution-authorized` — Runtime binary/App distribution is explicitly authorized

The RootFS remains a caller-obtained and caller-authorized local input. Do
not add it to Git, SwiftPM, GitHub Releases, TestFlight, or an App bundle.
The runtime track also requires the finalized PocketRoot top-level
license. The current `Scripts/scan-release-artifact.rb` schema produces
engineering evidence only; even a signed `.xcarchive` remains
`engineering-evidence-only`, with `releaseSignatureValid=false` and
`rootFSExcluded=false`. Its inventory and SPDX SBOM may be included under
`Compliance/Release/FinalArtifact/v0.2.0`, but cannot open the runtime
gate. A future dedicated final-release schema must bind signature,
entitlement, and risk metadata to the reviewed artifact and provide
content-based RootFS absence evidence; a content-tree digest, path,
filename, or extension check is not sufficient.

The two `--require-*-ready` commands report their tracks independently;
the source command currently succeeds, and the Runtime command intentionally remains
nonzero.
