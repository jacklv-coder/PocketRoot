# PocketRoot Host App

这是一个仓库内 Demo 之外的独立 iOS 宿主，用于验证业务 App 只通过公开 Swift
Package 产品即可完成：

1. 校验并安装调用方提供的 RootFS；
2. boot 同一个 iSH runtime；
3. 打开可交互 SwiftTerm PTY；
4. 浏览同一个 guest 的 `/root` 文件夹；
5. 先关闭所有终端 session，再有序 shutdown runtime。

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

该测试在临时 iOS 18 Simulator 中 Boot，向 SwiftTerm PTY 输入命令创建文件，并覆盖
持续输出、前后台、旋转 resize、关闭/重开终端、Files 预览与有序 shutdown。可用
`POCKETROOT_HOST_UI_SMOKE_DEVICE=<Simulator-UDID>` 复用已有模拟器。

用签名真机运行同一生命周期测试：

```bash
POCKETROOT_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-host-app-device-ui-smoke.sh
```

设备必须已配对、启用 Developer Mode，且其系统版本在已安装 Xcode 的 device-support
范围内。Team ID 使用开发证书 subject 的 `OU`。

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

This runs the real Simulator UI closure: boot, sustained SwiftTerm PTY input
and output, background/foreground, rotation resize, terminal close/reopen,
Files preview, and ordered shutdown. Set `POCKETROOT_HOST_UI_SMOKE_DEVICE` to
reuse an existing Simulator. Use `run-host-app-device-ui-smoke.sh` with
`POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE` and the development certificate
subject's `OU` team ID for the signed-device form; the device OS must be within
the installed Xcode device-support range.
