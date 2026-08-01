# PocketRoot 安全策略

[简体中文](SECURITY.md) | [English](SECURITY.en.md) | [贡献指南](CONTRIBUTING.md)

## 支持范围

PocketRoot 当前公开支持 `v0.1.x` 源码与 `main` 分支的安全报告。原生 iSH runtime、
RootFS installer、PTY、Files、Workspace 和可选 Agent 组件仍是 Experimental；这表示
API 可能变化，并不降低对内存安全、路径校验、权限边界、凭据处理和供应链问题的重视。

Runtime、App、TestFlight、App Store 和二进制 SDK 分发尚未获准。安全报告或修复不会
自动解除[发行门禁](Docs/ReleaseCompliance.md)。

## 私下报告漏洞

请不要为尚未修复的安全问题创建公开 Issue、Discussion 或 Pull Request。发送邮件至
GitHub 仓库所有者公开的安全联系地址
[`jacklvapple@gmail.com`](mailto:jacklvapple@gmail.com)，主题以
`[PocketRoot Security]` 开头。

报告尽量包含：

- 受影响的 PocketRoot 版本、完整 commit 和所选 Swift Package product；
- iOS、Xcode、设备或 Simulator 架构；
- 最小复现步骤、预期结果、实际结果与安全影响；
- 已脱敏的日志、调用栈或最小源码补丁；
- 是否涉及上游 IshEmbed/iSH、SwiftTerm 或调用方提供的 RootFS。

不要发送真实 token、签名材料、设备标识、个人数据、RootFS 归档、App/IPA/
XCFramework 或其他未经授权的二进制。若最小复现必须使用制品，请先只描述制品类型、
大小与 SHA-256，等待维护者给出安全传输方式。

维护者目标是在 3 个工作日内确认收到，并在 7 个工作日内给出初步分级或补充信息
请求；这是响应目标，不是修复时限或服务等级承诺。请在维护者确认修复版本和披露时间
之前保持私密。

## 披露与修复

维护者会核对影响范围、复现条件、第三方归属和现有发行边界。确认的问题会在不扩大
利用面的前提下修复、测试并记录；需要上游修复时会协调对应项目。公开披露应包含受
影响版本、缓解方式和修复版本，但不得包含凭据、个人数据或不必要的可利用载荷。

一般使用问题、非敏感 bug 和功能请求请使用仓库的结构化
[Issue 表单](https://github.com/jacklv-coder/PocketRoot/issues/new/choose)。
