# PocketRoot notices

## 简体中文

PocketRoot 贡献者拥有版权的原创源码依据根目录 [`LICENSE`](LICENSE) 中的
MIT License 提供。MIT License 不会覆盖或重新许可第三方组件、上游源码、
预编译制品、RootFS 内容或合规证据中记录的第三方材料。

当前源码与 Swift Package 发布只包含 PocketRoot 源码和 Package 元数据，不包含
RootFS、`libIshKernel.xcframework` 镜像、App、archive、IPA 或二进制 SDK。
仓库或 Package 元数据引用的主要第三方组件包括：

- SwiftTerm，依据其上游 MIT License；仓库内副本位于
  [`ThirdPartyNotices/SwiftTerm-LICENSE.txt`](ThirdPartyNotices/SwiftTerm-LICENSE.txt)。
- Swift Argument Parser，作为解析到的上游 Package 依赖，依据 Apache-2.0。
- IshEmbed、iSH 与 `libIshKernel.xcframework`，依据各自上游许可证和
  `LICENSE.IOS` 条款；它们不因 PocketRoot 的 MIT License 被重新许可。
- Alpine RootFS 及其软件包，保持为调用方自行取得并授权的本地输入，分别适用
  其上游许可证；PocketRoot 的源码发布不包含或授权分发该 RootFS。

Runtime、App 或二进制分发仍受独立的发布门禁约束。顶层 MIT License 已确定，
不代表 RootFS、第三方二进制或完整 Runtime 组合已经获准分发。

## English

Original source code copyrighted by PocketRoot contributors is provided under
the MIT License in the repository-root [`LICENSE`](LICENSE). The MIT License
does not cover or relicense third-party components, upstream source,
prebuilt artifacts, RootFS contents, or third-party materials recorded in
compliance evidence.

The current source and Swift Package release contains PocketRoot source and
package metadata only. It does not include a RootFS,
`libIshKernel.xcframework` mirror, App, archive, IPA, or binary SDK. Principal
third-party components referenced by the repository or package metadata
include:

- SwiftTerm under its upstream MIT License; the repository copy is
  [`ThirdPartyNotices/SwiftTerm-LICENSE.txt`](ThirdPartyNotices/SwiftTerm-LICENSE.txt).
- Swift Argument Parser as a resolved upstream package dependency under
  Apache-2.0.
- IshEmbed, iSH, and `libIshKernel.xcframework` under their respective upstream
  licenses and `LICENSE.IOS` terms; PocketRoot's MIT License does not
  relicense them.
- The Alpine RootFS and its packages as a caller-obtained and
  caller-authorized local input under their respective upstream licenses.
  PocketRoot's source release neither contains nor authorizes distribution of
  that RootFS.

Runtime, App, and binary distribution remain subject to independent release
gates. Finalizing PocketRoot's top-level MIT License does not authorize
distribution of the RootFS, third-party binaries, or the complete Runtime
composition.
