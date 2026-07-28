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

## English

This standalone iOS host proves that a consumer can validate and install a
caller-provided RootFS, boot one shared iSH runtime, open an interactive
SwiftTerm PTY, and browse `/root` using only the public `PocketRoot` and
`PocketRootIshRuntimeIntegration` products. Generate the project from
`project.yml` with XcodeGen. The commands above configure the reviewed
development RootFS or provide it to one Debug build. Release builds always
skip RootFS injection; this example is not distribution authorization.
