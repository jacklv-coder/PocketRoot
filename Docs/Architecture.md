# PocketRoot Architecture

## Overview

PocketRoot separates reusable runtime capabilities from the UIKit demo. The
default system deliberately remains a placeholder, while separately consumable
Experimental products provide the pinned IshEmbed adapter and its verified
RootFS composition path.

## Supported baseline

- Deployment target: iOS 18.0 for the package, demo app, and demo tests
- Development environment: Xcode 16.0 or newer with the iOS 18 SDK for Core and Demo
- Package toolchain: Swift 5.10 or newer
- Xcode language mode: Swift 5, with targeted strict-concurrency checking

The macOS 13 package declaration is a host-only compatibility floor so package
tests can run on macOS. It is not a supported application deployment target.
The native IshEmbed binary is available only for arm64 iOS device and arm64
Simulator builds; it has no macOS or x86_64 Simulator slice.
The native path has been validated with Xcode 26.1.1; minimum-toolchain native
compatibility still requires an explicit Xcode 16 validation run.

## Modules

### PocketRootCore

Owns the public runtime, command, session, configuration, RootFS abstraction,
state, and error APIs. It uses Foundation and Swift Concurrency only and never
imports UIKit.

The package-scoped LinuxRuntime protocol isolates the iSH adapter. The initial
PlaceholderLinuxRuntime reports that integration is unavailable. RootFSProvider
similarly isolates bundled or application-provided filesystem implementations.

### PocketRootTerminal

Owns the public terminal configuration, theme, and UIKit view controller. Its
placeholder UI establishes the embedding contract without taking a SwiftTerm
dependency. UIKit code is main-actor isolated.

### PocketRootResources

Owns the immutable RootFS artifact manifest, streaming SHA-256 validation,
secure gzip/ustar extraction, fakefs layout validation, and recoverable atomic
installation. Versioned installations are promoted only after validation;
failed replacement preserves the previous current installation. Caller-owned
archives are copied with a bounded no-follow descriptor into private staging,
and the snapshot is hashed before and after extraction. A persistent promotion
transaction finishes or rolls back interrupted renames before stale staging is
cleaned. No RootFS is bundled or downloaded by the library while distribution
review remains open.

### CPocketRootArchiveSupport

Provides the narrow zlib-backed gzip streaming primitive used by
PocketRootResources. It creates decompression output exclusively, enforces an
expanded-byte ceiling, removes partial output on failure, and exposes no public
client API.

### PocketRootIshRuntime (Experimental)

Owns the opt-in adapter from PocketRootCore's package-scoped `LinuxRuntime`
contract to the exact pinned `IshEmbed` product. The adapter validates that a
materialized fakefs contains `meta.db` and `data/`, moves blocking native calls
onto a process-wide serial queue, enforces one process owner and one command at
a time, maps boot and one-shot command results, caps both output streams, and
treats shutdown as terminal for the current app process.

This product is intentionally not part of the PocketRoot umbrella product.
The repository-owned one-shot adapter smoke passes on an iOS 18.2 arm64
Simulator. Interactive sessions, physical-device validation, minimum-Xcode
native validation, and distribution compliance remain gated. Unsupported hosts
use a non-native driver so host tests can exercise the adapter contract without
linking the iOS XCFramework.

### PocketRootIshRuntimeIntegration (Experimental)

Owns the opt-in composition entry point that accepts a caller-supplied local
archive, materializes it through PocketRootResources, aligns the runtime
configuration with the manifest version, and returns one prepared
PocketRootSystem. Preparation does not download an archive and does not boot
the runtime, keeping network and lifecycle policy under the application.

### PocketRoot

Provides the umbrella import used by clients and the Demo. It re-exports Core,
Terminal, and Resources while keeping both Experimental runtime products
explicitly opt-in.

### PocketRootDemo

Uses AppDelegate, SceneDelegate, and UIWindow with four UIKit navigation stacks:
System, Terminal, Commands, and Diagnostics. It demonstrates only public package
APIs and contains no runtime implementation.

## Concurrency

PocketRootSystem is an actor and serializes lifecycle and command operations.
Runtime-facing values conform to Sendable where appropriate. All UIKit types
and UI mutations are isolated to MainActor.

IshEmbed itself is process-global and exposes synchronous calls. The
Experimental adapter uses a process-wide ownership gate and serial blocking
executor so native calls neither run on the main thread nor occupy Swift's
cooperative executor. Lifecycle state is closed before suspension so concurrent
boot, command, and shutdown requests cannot overtake each other. One-shot reads
are bounded by a positive timeout of at most 24 hours plus independent stdout
and stderr limits (8 MiB and 4 MiB by default). Native shutdown is irreversible
in the pinned artifact: guest PID 1 ultimately calls `_exit(0)`, ending the
entire host App before the Swift call can return. The `.terminated` state and
post-shutdown `restartRequired` behavior are therefore observable only with
injected drivers or a future soft-shutdown upstream build. Replacing this
process-terminal behavior is an explicit gate before default integration.

Interactive integration must add a live-session registry and bounded reads,
then close every session before native shutdown. The upstream high-level
`IshTerminal` wrapper is not used while its close/read ownership remains
unproven.

## Project generation

project.yml is the source of truth. PocketRootDemo.xcodeproj is generated by
XcodeGen and is not maintained or committed manually.

The macOS CI job runs package tests, validates and installs the exact pinned
RootFS archive, installs and invokes XcodeGen, builds the generated Demo for a
generic iOS Simulator, and final-links a minimal app containing the complete
Experimental integration graph for arm64 Simulator and unsigned arm64 device
destinations. Physical-device execution remains mandatory for runtime-specific
ARM64 milestones.

Host tests cover the unsupported-driver and adapter seams. Native runtime tests
must target an arm64 iOS Simulator; testing the upstream package directly on
macOS cannot link because its released XCFramework has no macOS slice.

`PocketRootIshRuntimeSmoke` is a repository-owned local smoke App rather than a
CI step. `Scripts/run-runtime-smoke.sh` verifies and injects the caller-supplied
pinned v0.3.3 archive, builds the complete adapter graph, and runs 13 checks on
an iOS 18 Simulator: RootFS preparation; boot; `aarch64`; Alpine 3.19.1; working
directory and environment; split and merged standard error with exit-code
preservation; a 100 ms timeout followed by recovery; a 64-byte output limit
followed by recovery; and native shutdown. The shutdown check persists its
report first, then verifies that the pinned iSH `_exit(0)` path terminates the
host App process as designed. This evidence does not cover GitHub Actions,
Xcode 16, or physical iPhone and iPad execution.

## Integration seams

- PocketRootIshRuntime for the pinned, Experimental iSH adapter
- PocketRootIshRuntimeIntegration for opt-in RootFS/runtime composition
- PocketRootRootFSInstaller for verified Alpine ARM64 materialization
- PocketRootSession for long-running process I/O
- TerminalBridge for a pinned SwiftTerm adapter

The accepted runtime decision, immutable revisions, hashes, and open gates are
recorded in
[ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md) and
[Upstream Dependencies](UpstreamDependencies.md).
