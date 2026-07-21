# PocketRoot

Embeddable ARM64 Linux runtime and terminal foundations for iOS.

## Status

PocketRoot is currently under active development. The IshEmbed-backed ARM64
runtime is **Experimental** and is not approved for production or binary
distribution.

The project currently provides:

- A reusable Swift Package structure
- A pure UIKit demo app for iPhone and iPad
- Runtime and terminal API foundations
- XcodeGen-based project generation
- Unit tests for the placeholder, RootFS, composition, and runtime boundaries

The opt-in `PocketRootIshRuntime` product implements the pinned iSH adapter for
boot, bounded one-shot commands, and terminal shutdown. The separate
`PocketRootIshRuntimeIntegration` product composes that adapter with a verified,
versioned RootFS installer. The default `PocketRootSystem` remains a safe
placeholder, no Alpine RootFS is bundled or downloaded by the library, and
interactive PTY and SwiftTerm integration are not implemented.

An independent feasibility spike and the repository-owned PocketRoot adapter
smoke both pass on an iOS 18.2 arm64 Simulator. The adapter smoke completed 13
checks covering the pinned v0.3.3 RootFS, boot, guest identity and command
context, stream and exit handling, timeout and output-limit recovery, and the
pinned iSH terminal-shutdown behavior. Physical iPhone and iPad execution,
RootFS distribution, Xcode 16 native-runtime compatibility, interactive PTY,
license/NOTICE/SBOM review, and App Store 2.5.2 disposition remain release
gates. RootFS archive validation, secure extraction, atomic installation,
reuse, corruption replacement, and rollback are implemented and tested,
including against the pinned release archive.
See [ADR-001](Docs/Decisions/ADR-001-IshEmbed-Feasibility.md) for the decision
and current gate status.

## Architecture

- UIKit demo application using AppDelegate, SceneDelegate, and UIWindow
- Swift Package modularization
- PocketRootCore
- PocketRootTerminal
- PocketRootResources
- PocketRootIshRuntime (Experimental and opt-in)
- PocketRootIshRuntimeIntegration (Experimental and opt-in)
- PocketRoot umbrella product

See [Architecture](Docs/Architecture.md) for module boundaries,
[Roadmap](Docs/Roadmap.md) for the integration sequence, and
[Upstream Dependencies](Docs/UpstreamDependencies.md) for immutable revisions
and artifact hashes.

## Requirements

- Xcode 16.0 or newer with the iOS 18 SDK for the package and Demo
- Swift 5.10 or newer (the package manifest compatibility baseline)
- iOS 18.0 or newer on deployment targets
- XcodeGen

The native IshEmbed path has been validated with Xcode 26.1.1. Compatibility
with the minimum Xcode 16 toolchain remains an explicit native-runtime gate.

## Build

    brew install xcodegen
    ./Scripts/bootstrap.sh
    ./Scripts/test.sh
    ./Scripts/build.sh
    ./Scripts/build-runtime-spike.sh
    POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz ./Scripts/run-runtime-smoke.sh
    open PocketRootDemo.xcodeproj

The generated Xcode project is intentionally ignored. Update project.yml and
regenerate instead of editing project.pbxproj by hand.

## Experimental composition

Applications that already possess a reviewed local archive can opt in without
changing the safe default system:

```swift
import PocketRootIshRuntimeIntegration

let prepared = try await PocketRootIshSystemFactory.prepareSystem(
    archiveURL: archiveURL,
    applicationSupportURL: applicationSupportURL
)
try await prepared.system.boot()
```

Preparation validates and installs the archive but never downloads it or boots
the irreversible process-global runtime. The caller owns those policy choices.
At the currently pinned upstream revision, `prepared.system.shutdown()` ends
the entire host App with `_exit(0)` and does not return to Swift. The native
product remains Experimental until that process-terminal contract is either
accepted explicitly or replaced by a rebuilt artifact with soft shutdown.

## Continuous integration

GitHub Actions runs on macOS and verifies the package tests, downloads and
validates the exact pinned RootFS release archive, installs XcodeGen, generates
`PocketRootDemo.xcodeproj`, builds the Demo for a generic iOS Simulator, and
final-links the complete Experimental integration graph for arm64 Simulator
and unsigned arm64 device destinations.

Native IshEmbed validation requires an arm64 iOS destination. The upstream
XCFramework has no macOS or x86_64 Simulator slice, so host-only tests exercise
the adapter seam rather than the native runtime.

The repository-owned native adapter smoke is a separate local gate, not a
GitHub Actions claim. On an Apple Silicon host with an iOS 18 Simulator and the
audited local archive, run:

    POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz ./Scripts/run-runtime-smoke.sh

The script verifies the pinned archive before injecting it into a dedicated
smoke App; the library itself still neither bundles nor downloads the RootFS.

## License

The licensing policy is being finalized before the first public release. See
LICENSE for the current notice.

The Experimental runtime links GPL-identified upstream code and the candidate
RootFS contains components under several copyleft and permissive licenses.
Public binary distribution is blocked until PocketRoot's license is confirmed
compatible and complete license, NOTICE, corresponding-source, and SBOM
material is available. App Store Review Guideline 2.5.2 is a separate open gate
because the guest package manager can download and execute additional code.
