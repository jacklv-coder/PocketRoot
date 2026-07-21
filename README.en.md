# PocketRoot

[简体中文](README.md) | [English](README.en.md)

PocketRoot provides embeddable ARM64 Linux runtime and terminal foundations for iOS. Its Swift Package modules can securely install a verified Alpine fakefs and, through the Experimental iSH/IshEmbed adapter, execute bounded one-shot shell commands inside the iOS sandbox.

> [!WARNING]
> Native iSH integration is **Experimental**. The pinned upstream build calls `_exit(0)` during `shutdown()`, terminating the entire host app without returning to Swift. This version is not approved for production, TestFlight, or public binary distribution.

## Capability status

| Capability | Status | Notes |
| --- | --- | --- |
| Swift Package modules and public API | Available | Core, Resources, Terminal, and safe umbrella |
| UIKit Demo shell | Available | System, Terminal, Commands, and Diagnostics entry points |
| RootFS verification and safe install | Available | Fixed digest, secure extraction, journal-protected same-volume promotion, reuse, recovery |
| iSH boot and one-shot commands | Experimental | `iOS + arm64` and explicit products only |
| Interactive PTY and SwiftTerm | Not implemented | Session input, resize, signal, and safe close remain planned |
| Physical devices and distribution | Blocked | iPhone/iPad, Xcode 16, license, SBOM, and App Store gates remain |

The default `PocketRoot` product does not include native iSH and never bundles or downloads a RootFS. `PocketRootSystem.shared` uses a safe placeholder. Real runtime applications explicitly depend on `PocketRootIshRuntimeIntegration`.

## Implementation overview

```mermaid
flowchart LR
    A["Caller-owned reviewed local RootFS archive"] --> B["PocketRootResources verifies and installs"]
    B --> C["Versioned fakefs directory"]
    C --> D["PocketRootIshRuntimeIntegration composes a system"]
    D --> E["PocketRootIshRuntime boots IshEmbed"]
    E --> F["/bin/sh -lc executes a bounded command"]
    F --> G["exit, signal, stdout, stderr, timeout"]
```

Design principles:

- The RootFS payload is not committed; the library performs no network download.
- Source, XCFramework, and RootFS inputs are pinned by immutable revision or digest.
- Extraction occurs in private same-volume staging. A durable journal protects the multi-step, same-volume rename promotion so it can recover or roll back. Each rename and record write is atomic on its own; the replacement sequence as a whole is not one atomic operation.
- IshEmbed is process-global: one native owner and one in-flight command.
- Synchronous native work runs on a serial blocking executor away from the main and Swift cooperative executors.
- The event-read loop uses a deadline after session establishment, and Swift applies product budgets to collected stdout/stderr. In the pinned native transport, spawn/control/terminate/close may still block and the unread inbox has no independent ceiling, so end-to-end time bounds and complete memory backpressure remain open gates.

See [Architecture](Docs/en/Architecture.md), [Implementation](Docs/en/Implementation.md), and [RootFS Security](Docs/en/RootFS.md).

## Requirements

- macOS on Apple Silicon for native work
- Xcode 16.0+ with iOS 18 SDK
- Swift 5.10+
- iOS 18.0+
- Homebrew and XcodeGen

macOS 13 is a host-test declaration, not a supported guest platform. IshEmbed has arm64 iOS device and arm64 Simulator slices only. Native behavior has been validated with Xcode 26.1.1 and iOS 18.2 arm64 Simulator; minimum-Xcode native validation remains open.

## Build from source

```bash
git clone git@github.com:jacklv-coder/PocketRoot.git
cd PocketRoot

./Scripts/bootstrap.sh
./Scripts/test.sh
./Scripts/build.sh
open PocketRootDemo.xcodeproj
```

`bootstrap.sh` resolves packages and generates the project with XcodeGen. The generated project is ignored; `project.yml` is authoritative.

The current Demo is a UI/public-API shell, not an Alpine-running app. System and Commands use the placeholder shared system, Terminal has no PTY, and Diagnostics exposes future seams. Native validation uses dedicated compile and smoke targets.

See [Getting Started](Docs/en/GettingStarted.md).

## Experimental application use

Select `PocketRootIshRuntimeIntegration` explicitly. No stable Git tag exists yet, so remote consumers must pin a reviewed full commit rather than a moving branch.

```swift
import Foundation
import PocketRoot
import PocketRootIshRuntime
import PocketRootIshRuntimeIntegration

guard PocketRootIshRuntimeFactory.isAvailable else {
    fatalError("The native runtime requires an arm64 iOS build.")
}

let applicationSupportURL = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)

let prepared = try await PocketRootIshSystemFactory.prepareSystem(
    archiveURL: localReviewedArchiveURL,
    applicationSupportURL: applicationSupportURL
)

try await prepared.system.boot()

let result = try await prepared.system.execute(
    PocketRootCommandRequest(
        command: "/bin/uname -m",
        workingDirectory: "/",
        timeout: .seconds(30)
    )
)

print(result.exitCode)
print(result.stdout)
print(result.stderr)
```

Contract:

1. `archiveURL` is a caller-owned reviewed local regular file.
2. Preparation verifies, installs, and composes; it does not download or boot.
3. `applicationSupportURL/rootfs/<version>` directly contains `meta.db`, `data/`, and `.pocketroot-rootfs.json`; there is no retained `fs/` layer. A valid version directory and installation record can be reused even when `current.json` is missing or mismatched; reuse repairs it.
4. Boot is explicit.
5. Commands run through `/bin/sh -lc` and are shell strings, not argv-safe APIs.
6. Each request owns cwd, environment, timeout, and stderr policy.
7. Native shutdown ends the entire host app; never use it for routine view/scene cleanup.
8. `PocketRootSystem.state` refreshes only after `boot()` / `shutdown()` returns or throws. The runtime's internal `.booting` / `.shuttingDown` transitions are not a public real-time progress stream.

See the [Integration Guide](Docs/en/IntegrationGuide.md).

## RootFS policy

The repository records metadata and secure install code, not `fs.tar.gz`:

- RootFS manifest corresponding to parent IshEmbed package release `v0.3.3`
- Alpine `3.19.1 aarch64`
- archive size `6,581,376` bytes
- expanded tar size `18,838,016` bytes
- SHA-256 `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4`

The pinned URL is metadata, not an automatic download. Do not add the payload to a Package/App bundle before license, NOTICE, corresponding-source, and SBOM review.

## Validation

```bash
./Scripts/check-docs.sh
./Scripts/test.sh
./Scripts/build.sh
./Scripts/build-runtime-spike.sh

POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment

POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh
```

The native smoke requires Apple Silicon, iOS 18 Simulator, and the exact local archive. It covers preparation, guest identity, command context, streams, exit, timeout/output-limit recovery, and process-terminal shutdown. See [Testing](Docs/en/Testing.md).

## Documentation

| Topic | Document |
| --- | --- |
| System-wide mental model and learning path | [Technical Learning Guide](Docs/en/TechnicalGuide.md) |
| Users, use cases, MVP, and non-goals | [Product Plan](Docs/en/ProductPlan.md) |
| Checkout, build, and Demo | [Getting Started](Docs/en/GettingStarted.md) |
| Product selection and API use | [Integration Guide](Docs/en/IntegrationGuide.md) |
| Modules, concurrency, lifecycle | [Architecture](Docs/en/Architecture.md) |
| Source-level flows | [Implementation](Docs/en/Implementation.md) |
| RootFS threat model and recovery | [RootFS Security](Docs/en/RootFS.md) |
| Test layers and native smoke | [Testing](Docs/en/Testing.md) |
| Common failures | [Troubleshooting](Docs/en/Troubleshooting.md) |
| Dynamic gates and next work | [Roadmap](Docs/en/Roadmap.md) |
| Revisions, gitlinks, and hashes | [Upstream Dependencies](Docs/en/UpstreamDependencies.md) |
| License and distribution | [Release and Compliance](Docs/en/ReleaseCompliance.md) |
| IshEmbed decision | [ADR-001](Docs/en/Decisions/ADR-001-IshEmbed-Feasibility.md) |
| Development workflow | [Contributing](CONTRIBUTING.en.md) |
| Changes | [Changelog](CHANGELOG.en.md) |

See the [Documentation Hub](Docs/en/README.md).

## License and release

PocketRoot's first-public-release license policy is still being finalized. The Experimental runtime links GPL-identified upstream code and the candidate RootFS contains multiple copyleft and permissive licenses. Production, TestFlight, and public distribution remain blocked until physical-device and minimum-Xcode native validation, license, NOTICE, corresponding source, SBOM, and App Store 2.5.2 gates have explicit dispositions.
