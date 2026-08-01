## Scope / 范围

<!-- What focused problem does this PR solve? / 这个 PR 解决哪个范围明确的问题？ -->

## Behavior and risk / 行为与风险

<!-- Describe public behavior, compatibility, concurrency, security, RootFS, upstream, and release-gate impact. / 说明公共行为、兼容性、并发、安全、RootFS、上游和发行门禁影响。 -->

## Validation / 验证

<!-- List exact commands and results. State skipped hardware or real-asset gates explicitly. / 列出准确命令和结果；明确说明未运行的硬件或真实资产门禁。 -->

## Checklist / 检查表

- [ ] The scope is focused and contains no unrelated files. / 范围单一且没有无关文件。
- [ ] Public behavior has regression coverage. / 公共行为有回归覆盖。
- [ ] Relevant tests, builds, final links, and smoke checks passed or are explicitly marked not run. / 相关测试、构建、最终链接和 smoke 已通过，或明确标记未运行。
- [ ] No RootFS, App, IPA, XCFramework mirror, credentials, signing material, or private data is committed. / 未提交 RootFS、App、IPA、XCFramework 镜像、凭据、签名材料或隐私数据。
- [ ] Chinese and English documentation remain paired. / 中英文文档保持成对一致。
- [ ] Changelog and dynamic roadmap status are updated when applicable. / 适用时已更新 Changelog 和动态路线图状态。
- [ ] `./Scripts/check-docs.sh` and `git diff --check` pass. / 文档与 diff 检查通过。
- [ ] Simulator evidence is not described as physical-device support, and engineering validation is not described as distribution approval. / 未把 Simulator 证据描述为真机支持，也未把工程验证描述为分发授权。
