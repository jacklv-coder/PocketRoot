# PocketRoot Quick Start App

**Open a local Linux Terminal or Files screen from two buttons.**

这是面向首次接入者的最小 UIKit 示例。它只做三件事：

1. 在 App owner 中长期持有一个 `PocketRootIshWorkspaceHost`；
2. 把经过审核的 RootFS URL 与 Application Support 目录交给 host；
3. 从业务页面直接打开 SDK 提供的 Terminal 或 Files 页面。

业务入口代码只有：

```swift
navigationController?.pushViewController(
    pocketRootHost.makeTerminalViewController(),
    animated: true
)

navigationController?.pushViewController(
    pocketRootHost.makeFilesViewController(),
    animated: true
)
```

两个页面都会在首次展示时自动校验并安装 RootFS、启动 Linux。退出 Terminal
页面会关闭该页面的 PTY，但保留 runtime；之后可以继续打开 Terminal、Files 或组合
Workspace。RootFS 仍由业务 App 作为经过审核的本地资源提供，PocketRoot 不联网下载。

从仓库根目录运行：

```bash
./Scripts/bootstrap.sh
./Scripts/inject-demo-rootfs.sh \
  --install-development-archive /absolute/path/to/fs.tar.gz
open Examples/PocketRootQuickStartApp/PocketRootQuickStartApp.xcodeproj
```

用真实 iOS 18 Simulator 验证首次接入闭环：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
  ./Scripts/run-quick-start-ui-smoke.sh
```

测试从未 boot 的 App 分别打开 Files 和 Terminal，验证两个入口都会自动准备
RootFS/boot；Terminal 通过真实 PTY 创建文件后返回业务首页，再由 Files 打开并预览
同一个文件。设置 `POCKETROOT_QUICK_START_UI_DEVICE_TYPE` 可选择 iPhone 或 iPad
Simulator；`POCKETROOT_KEEP_UI_RESULT=1` 会保留失败诊断制品。

开发 RootFS 仅注入 Debug 构建。Release、TestFlight 和 App Store 分发仍受项目中的
许可证、对应源码、SBOM 与发行审查门禁约束。

## English

This is the smallest UIKit integration example. Retain one
`PocketRootIshWorkspaceHost` in the App owner, give it an app-provided reviewed
RootFS and Application Support directory, then push the host-managed Terminal
or Files screen. Each screen automatically prepares and boots Linux when first
shown. Leaving Terminal closes that screen's PTY while keeping the runtime
available for later screens. Run `Scripts/run-quick-start-ui-smoke.sh` with
`POCKETROOT_ROOTFS_ARCHIVE` to validate cold Files auto-boot and the real
Terminal-to-Files file round trip on an iPhone or iPad Simulator.
