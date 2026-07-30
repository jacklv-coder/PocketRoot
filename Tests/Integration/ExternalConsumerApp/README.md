# PocketRoot External Consumer acceptance

This is a CI acceptance fixture, not another shipped Demo or a production App
template. `Scripts/run-external-consumer-ui-smoke.sh` copies these sources into
a temporary directory outside the PocketRoot checkout, renders
`project.yml.template` with either a local package path or a public Git URL plus
an exact revision, and adds the caller-supplied RootFS only to that temporary
App.

The single UI test verifies the external consumer boundary end to end:

1. Terminal auto-boots and creates a guest file through the real PTY.
2. The same session accepts a fresh PTY command after a background and
   foreground transition.
3. Files opens and previews the same guest file.
4. Explicit shutdown returns to Swift and disables further entry.

No RootFS archive or generated Xcode project belongs in this directory.
Distribution remains blocked by the repository's release-compliance gates.

## 中文说明

这是 CI 使用的外部消费者验收夹具，不是第四个发布 Demo，也不是可直接上架的 App
模板。runner 会把源码复制到 PocketRoot 仓库之外的临时目录，再用本地 package path
或“公开 Git URL + 精确 SHA”生成工程，并且只把调用方提供的 RootFS 放入临时测试
App。单条 UI 测试覆盖 Terminal 自动启动、真实 PTY 建文件、前后台恢复、Files 预览
和显式 shutdown。这里不得提交 RootFS 或生成的 Xcode 工程。
