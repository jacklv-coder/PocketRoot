# 参与 PocketRoot 开发

[简体中文](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md) | [文档中心](Docs/README.md)

感谢参与 PocketRoot。项目当前处于实验性 runtime 阶段，普通代码质量、原生生命周期、供应链和中英文文档必须在同一个变更中保持一致。

提交前请同时遵守[社区行为准则](CODE_OF_CONDUCT.md)。一般错误、接入问题和功能建议
使用仓库的结构化 [Issue 表单](https://github.com/jacklv-coder/PocketRoot/issues/new/choose)；
未修复漏洞必须按[安全策略](SECURITY.md)私下报告。

## 许可证与贡献

PocketRoot 贡献者拥有版权的原创源码依据根目录 `LICENSE` 中的 MIT License
提供。向本仓库提交 issue、patch 或 Pull Request 时，贡献者确认自己有权提交
相关内容；除非另有书面约定，有意提交并被项目接收的原创代码与文档依据同一
MIT License 提供。

提交第三方或上游材料时，不得把它们重新标记为 MIT。必须保留原始版权与许可证，
说明来源、版本、修改和分发影响，并按[上游依赖更新流程](Docs/UpstreamDependencies.md)
补齐 NOTICE、源码对应关系和 SBOM 证据。

## 1. Git 与 GitHub

代码 fetch/push 使用 SSH，不依赖 HTTPS OAuth token：

```bash
git remote set-url origin git@github.com:jacklv-coder/PocketRoot.git
```

如果当前网络阻断 SSH 22 端口，可使用 GitHub 官方 SSH 443 endpoint：

```bash
git remote set-url origin \
  ssh://git@ssh.github.com:443/jacklv-coder/PocketRoot.git
```

首次连接必须核对 GitHub 官方 host key。不要在仓库、issue、日志或 PR 中提交 private key、token、device code 或 signing material。

开发分支不要直接在 `main` 上提交。自动化/Codex 分支使用 `agent/<description>`。提交信息保持简短、可读，例如：

```text
docs: add bilingual integration guides
fix: preserve RootFS installation during rollback
feat: add bounded runtime command output
```

默认先创建 Draft PR，直到验证、文档和开放门禁描述完整。

## 2. 环境

- Xcode 16.0+ 与 iOS 18 SDK；
- Swift 5.10+；
- XcodeGen；
- Homebrew；
- 原生 runtime/smoke 需要 Apple Silicon 和 iOS 18 Simulator；
- 真机验证需要签名 iPhone/iPad。

初始化：

```bash
./Scripts/bootstrap.sh
```

## 3. 标准开发流程

1. 确认 clean base 和当前分支：

   ```bash
   git status -sb
   git pull --ff-only
   ```

2. 创建分支：

   ```bash
   git switch -c agent/short-description
   ```

3. 修改代码、测试和文档。

4. 运行与改动匹配的验证，至少：

   ```bash
   ./Scripts/check-docs.sh
   ./Scripts/test.sh
   ./Scripts/build.sh
   ```

5. runtime、RootFS、Package 或 native dependency 变更还要运行：

   ```bash
   ./Scripts/build-runtime-spike.sh

   POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
     swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment

   POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
     ./Scripts/run-runtime-smoke.sh

   POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
   POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
   POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
     ./Scripts/run-runtime-device-smoke.sh
   ```

6. 检查 scope：

   ```bash
   git status --short
   git diff --check
   git diff
   ```

7. 只 stage 本次相关文件，commit 后通过 SSH push。

8. 创建或更新 Draft PR，写清变化、原因、影响、验证和未覆盖门禁。

## 4. 架构规则

- `PocketRootCore` 不依赖 UIKit、RootFS implementation 或 IshEmbed。
- UIKit 代码使用 programmatic UIKit 与 Auto Layout。
- 不加入 storyboard、XIB 或 SwiftUI App lifecycle。
- `Examples/PocketRootDemo/project.yml` 是完整 Demo 的 Xcode project 事实源；不提交生成的 `Examples/PocketRootDemo/PocketRootDemo.xcodeproj`。
- 默认 `PocketRoot` umbrella 不导出 Experimental runtime。
- 真实 runtime 必须 opt-in。
- IshEmbed 同步调用不能运行在 main thread 或 Swift cooperative executor。
- lifecycle state 要在第一个 suspension 前关闭 reentrancy。
- process-global ownership、一个在途命令和 bounded output 不得被绕过。
- PTY pointer ownership 与 close 顺序未通过前，不连接 SwiftTerm。
- public type 使用 `PocketRoot` 前缀。
- public API、状态、错误和关键限制必须有中英文文档。

## 5. RootFS 与制品规则

禁止提交：

- `fs.tar.gz`；
- 解包后的 fakefs；
- IshKernel 的非审查副本；
- smoke 注入文件或报告；
- DerivedData/build output；
- 未记录的二进制。

任何第三方 dependency 必须固定到：

- exact version；
- full commit revision；
- 或不可变 release；

并按需要记录：

- nested gitlink；
- artifact URL；
- byte count；
- SHA-256；
- source correspondence；
- license/NOTICE/SBOM 影响。

RootFS 或 IshEmbed 更新必须遵循[上游依赖更新流程](Docs/UpstreamDependencies.md)，并更新 ADR、路线图、合规文档、manifest、tests 和中英文变更日志。

在许可证与发行审查完成前：

- 不把 RootFS 加入 bundle；
- 不镜像 release asset；
- 不默认启用 Experimental runtime；
- 不发布 TestFlight、生产或公开 binary。

## 6. 测试规则

根据[测试矩阵](Docs/Testing.md)选择门禁。

最低原则：

- bug fix 必须有能在修复前失败、修复后通过的测试；
- actor/concurrency 改动运行 strict-concurrency + warnings-as-errors；
- RootFS 改动覆盖恶意输入、rollback 与真实 asset；
- runtime 改动覆盖 injected driver 和 native smoke；
- Package/native 改动必须做真正 final link；
- Simulator 结论不能替代 signed physical-device；
- skipped real-asset test 必须在 PR 中明确说明；
- 未运行的门禁写明原因，不能写成通过。

## 7. 双语文档规则

中文是默认阅读入口，英文是成对镜像：

| 中文 | 英文 |
| --- | --- |
| `README.md` | `README.en.md` |
| `CONTRIBUTING.md` | `CONTRIBUTING.en.md` |
| `CHANGELOG.md` | `CHANGELOG.en.md` |
| `Docs/<name>.md` | `Docs/en/<name>.md` |
| `Docs/Decisions/<name>.md` | `Docs/en/Decisions/<name>.md` |

行为、API、脚本、hash、状态或 gate 改变时，必须在同一 PR 更新两种语言。

写作规则：

- API、module、path、command、state case 和 hash 保留原文并使用代码格式。
- 中文首次出现术语可写“中文（English）”。
- README 保持摘要，把动态状态放 Roadmap、hash 放 Upstream、测试证据放 Testing。
- ADR 记录决策，不复制动态 gate 表。
- 图表必须有等价文字说明。
- 相对链接必须在当前语言目录内闭环。
- 新 Markdown 不能是英文-only 文档。
- 运行：

  ```bash
  ./Scripts/check-docs.sh
  ```

## 8. Changelog

以下变化更新中英文 Changelog：

- public API；
- 行为；
- deployment/toolchain baseline；
- dependency/revision/hash；
- security boundary；
- compatibility；
- release gate；
- documentation information architecture。

使用 `Added`、`Changed`、`Fixed`、`Security`、`Deprecated`、`Removed` 分类。breaking change 必须醒目标注。

## 9. Upstream 代码

保留 upstream copyright 和 license notice。在 PR 中说明：

- exact upstream version/revision；
- nested gitlink；
- 本地修改；
- binary rebuild 方法；
- checksum；
- redistribution impact；
- source/NOTICE/SBOM 更新。

不要把 branch HEAD 或本地 cache 当作 provenance。

## 10. PR 检查表

- [ ] 变更范围单一且没有无关用户文件。
- [ ] public behavior 有测试。
- [ ] 必需构建、final-link、smoke 已运行或说明未运行原因。
- [ ] RootFS/制品未进入 Git。
- [ ] 中英文文档同步。
- [ ] `./Scripts/check-docs.sh` 通过。
- [ ] `git diff --check` 通过。
- [ ] Changelog 已更新。
- [ ] PR 描述包含影响、风险、验证和开放门禁。
- [ ] push 使用 SSH。
- [ ] 没有 token、key、签名或隐私数据。
