# PocketRoot v0.1.0 Release Candidate Checklist

当前状态：**Blocked / 不可发布**。

本清单把“源码/Swift Package 发布”和“包含 runtime、RootFS、App 或二进制
SDK 的分发”分为两条独立轨道。工程测试通过不等于获得分发授权；源码轨道未来
变为 Ready 也不会自动解除 runtime 轨道。

## 源码与 Swift Package 发布（Blocked / 未就绪）

- [x] `source-boundary-excludes-rootfs` — 源码发布不包含 RootFS 载荷
- [x] `public-api-status-declared` — 公共 API 状态已声明为 Experimental
- [ ] `top-level-license-finalized` — PocketRoot 顶层许可证已确定
- [ ] `contributor-policy-approved` — 贡献者与版权政策已批准
- [ ] `release-notice-approved` — 源码发行 NOTICE 已批准
- [ ] `source-release-authorized` — PocketRoot 源码发布已明确授权

第一项需要项目所有者明确选择 SPDX 许可证并替换当前不授予复制、修改或分发
权限的 `LICENSE`。生成器不会替项目所有者选择许可证。

## Runtime / RootFS / App / 二进制分发（Blocked / 未就绪）

- [x] `rootfs-external-input-boundary` — RootFS 保持为调用方提供的本地输入
- [ ] `release-artifact-built-and-scanned` — 最终签名导出制品已构建并扫描
- [ ] `complete-license-notice-bundle-approved` — 完整 LICENSE 与 NOTICE 交付包已批准
- [ ] `corresponding-source-delivery-approved` — 对应源码交付已批准
- [ ] `app-store-policy-approved` — App Store 可执行代码策略已批准
- [ ] `privacy-review-approved` — Runtime 隐私与数据生命周期评审已批准
- [ ] `runtime-legal-review-approved` — 完整 Runtime 分发法律评审已批准
- [ ] `runtime-distribution-authorized` — Runtime 二进制/App 分发已明确授权

RootFS 当前只能作为调用方自行取得并授权的本地输入；不得把它加入 Git、
SwiftPM、GitHub Release、TestFlight 或 App bundle。

## 校验

```bash
ruby Scripts/generate-release-compliance.rb --check
ruby Scripts/generate-release-compliance.rb --status
ruby Scripts/generate-release-compliance.rb --require-source-ready
ruby Scripts/generate-release-compliance.rb --require-runtime-ready
```

后两个命令在对应轨道仍被阻塞时故意返回非零状态。

## English

Current status: **Blocked / not releasable**.

This checklist separates a source/Swift Package release from any
distribution containing a runtime, RootFS, App, archive, or binary SDK.
Passing engineering tests is not distribution authorization, and a future
Ready source track would not unblock the runtime track.

### Source and Swift Package release (Blocked)

- [x] `source-boundary-excludes-rootfs` — Source release excludes the RootFS payload
- [x] `public-api-status-declared` — Public API status is declared experimental
- [ ] `top-level-license-finalized` — Top-level PocketRoot license is finalized
- [ ] `contributor-policy-approved` — Contributor and copyright policy is approved
- [ ] `release-notice-approved` — Source-release notice is approved
- [ ] `source-release-authorized` — PocketRoot source release is explicitly authorized

The project owner must select an SPDX license and replace the current
no-permission `LICENSE`. The generator will not choose a license.

### Runtime / RootFS / App / binary distribution (Blocked)

- [x] `rootfs-external-input-boundary` — RootFS remains a caller-provided local input
- [ ] `release-artifact-built-and-scanned` — Final signed and exported artifact is built and scanned
- [ ] `complete-license-notice-bundle-approved` — Complete LICENSE and NOTICE bundle is approved
- [ ] `corresponding-source-delivery-approved` — Corresponding-source delivery is approved
- [ ] `app-store-policy-approved` — App Store executable-code policy is approved
- [ ] `privacy-review-approved` — Runtime privacy and data-lifecycle review is approved
- [ ] `runtime-legal-review-approved` — Complete runtime distribution legal review is approved
- [ ] `runtime-distribution-authorized` — Runtime binary/App distribution is explicitly authorized

The RootFS remains a caller-obtained and caller-authorized local input. Do
not add it to Git, SwiftPM, GitHub Releases, TestFlight, or an App bundle.
