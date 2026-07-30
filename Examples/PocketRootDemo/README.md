# PocketRoot Demo

**Embed a local Linux Terminal and Files workspace in any iOS app.**

这是 PocketRoot 的完整 UIKit 演示 App，展示同一个本地 Linux Runtime 上的：

- Runtime 准备、启动、健康检查和关闭；
- SwiftTerm 交互式 PTY；
- Linux 文件树、文件预览和文件操作；
- Terminal 与 Files 共享会话的 Workspace；
- 命令执行和诊断状态。

Demo 通过相对路径依赖仓库根目录的 PocketRoot Swift Package，不复制 SDK 源码：

```text
Examples/PocketRootDemo/
├── Sources/PocketRootDemo/  # Demo App 源码与资源
├── Tests/                   # Demo 专属单元测试
├── project.yml              # XcodeGen 工程事实源
└── README.md
```

从仓库根目录生成并打开工程：

```bash
./Scripts/bootstrap.sh
open Examples/PocketRootDemo/PocketRootDemo.xcodeproj
```

配置经过固定校验的开发 RootFS：

```bash
./Scripts/inject-demo-rootfs.sh \
  --install-development-archive /absolute/path/to/fs.tar.gz
```

RootFS 只会注入 Debug 构建；Release 构建保持禁用。生成的
`PocketRootDemo.xcodeproj` 不提交到 Git，修改 target、scheme 或构建设置时应编辑
`project.yml`。

Xcode 会在 `Package Dependencies > PocketRoot` 下再次显示仓库目录，因为 Demo 使用
`path: ../..` 引用当前 checkout。这是同一份文件的本地 Package 视图，不是第二份 Demo，
也不会把 Demo 编译进 PocketRoot Package。

## English

This is the complete UIKit showcase for PocketRoot. It demonstrates runtime
boot and diagnostics, an interactive SwiftTerm PTY, Linux file browsing,
the shared Terminal/Files workspace, command execution, and ordered shutdown.

The app consumes the repository root as a local Swift package. Generate the
Xcode project from this directory's `project.yml` by running
`./Scripts/bootstrap.sh` at the repository root, then open
`Examples/PocketRootDemo/PocketRootDemo.xcodeproj`.

Xcode may show the repository again under `Package Dependencies > PocketRoot`.
That is another view of the same local checkout, not a copied Demo target.
