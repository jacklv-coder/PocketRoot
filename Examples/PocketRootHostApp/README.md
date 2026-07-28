# PocketRoot Host App

这是一个仓库内 Demo 之外的独立 iOS 宿主，用于验证业务 App 只通过公开 Swift
Package 产品即可完成：

1. 校验并安装调用方提供的 RootFS；
2. boot 同一个 iSH runtime；
3. 打开可交互 SwiftTerm PTY；
4. 浏览同一个 guest 的 `/root` 文件夹。

它只依赖 `PocketRoot` 和 `PocketRootIshRuntimeIntegration`，不复制或导入 Demo
内部实现。工程文件由本目录的 `project.yml` 生成：

```bash
./Scripts/inject-demo-rootfs.sh \
  --install-development-archive /absolute/path/to/fs.tar.gz

cd Examples/PocketRootHostApp
xcodegen generate --spec project.yml
open PocketRootHostApp.xcodeproj
```

也可以只对一次 Debug 构建传入：

```bash
POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
  xcodebuild \
    -project PocketRootHostApp.xcodeproj \
    -scheme PocketRootHostApp \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build
```

注入脚本只接受固定 v0.3.3 的精确字节数和 SHA-256。Release 构建始终跳过 RootFS；
本示例不是发行授权。

从仓库根目录可运行真实模拟器 UI 闭环：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
  ./Scripts/run-host-app-ui-smoke.sh
```

该测试在临时 iOS 18 Simulator 中 Boot，向 SwiftTerm PTY 输入命令创建文件，再从
Files 页面进入目录并核对文件预览。可用
`POCKETROOT_HOST_UI_SMOKE_DEVICE=<Simulator-UDID>` 复用已有模拟器。

## English

This standalone iOS host proves that a consumer can validate and install a
caller-provided RootFS, boot one shared iSH runtime, open an interactive
SwiftTerm PTY, and browse `/root` using only the public `PocketRoot` and
`PocketRootIshRuntimeIntegration` products. Generate the project from
`project.yml` with XcodeGen. The commands above configure the reviewed
development RootFS or provide it to one Debug build. Release builds always
skip RootFS injection; this example is not distribution authorization.

From the repository root, run:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
  ./Scripts/run-host-app-ui-smoke.sh
```

This runs the real Simulator UI closure: boot, type a file-creation command
into the SwiftTerm PTY, navigate through Files, and verify the preview. Set
`POCKETROOT_HOST_UI_SMOKE_DEVICE` to reuse an existing Simulator.
