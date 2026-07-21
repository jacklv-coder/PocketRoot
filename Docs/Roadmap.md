# PocketRoot Roadmap

## Milestone 1: Project foundation

- Swift Package module boundaries
- Public runtime, command, session, and terminal API foundations
- Placeholder runtime and terminal behavior
- Programmatic UIKit demo with four tabs
- XcodeGen generation, scripts, documentation, and tests
- Unified iOS 18.0 deployment target
- macOS CI for package tests, pinned RootFS validation, project generation,
  generic Simulator builds, and arm64 Experimental-runtime final links

### Engineering baseline

- Xcode 16.0 or newer with the iOS 18 SDK
- Swift 5.10 or newer for Swift Package Manager
- iOS 18.0 as the minimum supported deployment target
- `project.yml` as the committed Xcode project source of truth

## Milestone 2: ARM64 Linux runtime

Status: **Experimental — in progress**.

### Completed feasibility gates

- Audited `jacklv-coder/ish-arm64-pkg` and its parent repository
- Pinned the exact package revision and nested iSH gitlink
- Verified XCFramework and RootFS release hashes
- Added the opt-in `PocketRootIshRuntime` module boundary
- Added the opt-in `PocketRootIshRuntimeIntegration` composition boundary
- Established process-wide ownership, serialized boot, bounded one-shot
  commands, and terminal-shutdown semantics
- Added a versioned RootFS manifest, secure extractor, fakefs validator, and
  recoverable atomic installer
- Installed and revalidated the exact v0.3.3 RootFS release archive
- Final-linked the full integration graph for iOS 18 arm64 Simulator and
  unsigned device destinations
- Booted the audited fakefs on an iOS 18.2 Simulator
- Verified `/bin/uname -m` exits 0 and returns `aarch64`
- Passed the repository-owned PocketRoot adapter smoke on an iOS 18.2 arm64
  Simulator: 13 checks cover the v0.3.3 RootFS, boot, Alpine identity, command
  context, streams and exit status, timeout and output-limit recovery, and the
  terminal shutdown that ends the host App process through pinned iSH
  `_exit(0)` behavior

The independent spike and repository adapter smoke establish the Simulator
path. They do not satisfy the Xcode 16, physical-device, PTY, or
production-distribution gates, and the smoke is not a CI claim.

### Current gate status

| Gate | Status | Next exit condition |
| --- | --- | --- |
| iOS 18 baseline | Passed | Keep package, demo, tests, and CI aligned |
| Immutable IshEmbed revision | Passed | Change only through the audited update procedure |
| Experimental one-shot adapter foundation | Passed | Preserve lifecycle, timeout, and output-limit unit coverage |
| Native adapter behavior on iOS 18 Simulator | Passed | Preserve the 13-check repository smoke and rerun it for runtime or RootFS changes |
| RootFS manifest and installer foundation | Passed | Preserve real-asset, private-snapshot, rollback, and interrupted-promotion coverage; add ENOSPC testing |
| Runtime/RootFS composition | Passed | Keep preparation caller-controlled and Experimental |
| Host-process-safe native shutdown | Blocked | Patch the embed fork to stop the kernel thread without `_exit`, bound native joins, rebuild the XCFramework, and repeat the audit |
| Default VM and post-boot health check | Not started | Verify `aarch64`, Alpine version, and command context before reporting ready |
| Demo native smoke path | Not started | Inject one prepared system into all screens without bundling an unreviewed asset |
| License-reviewed RootFS | Blocked | Complete licenses, NOTICE, corresponding source, and SBOM |
| Interactive PocketRootSession | Not started | Bounded reads, input, output, signal, resize, cancellation, and safe close |
| SwiftTerm bridge | Not started | Pin only after the PTY ownership contract is stable |
| Physical iPhone and iPad | Blocked | Signed boot and `aarch64` smoke tests on both device classes |
| App lifecycle and memory | Not started | Foreground/background, jetsam, failure injection, and persistence tests |
| Xcode 16 native-runtime compatibility | Not started | Repeat final-link and smoke checks with the minimum supported toolchain |
| App Store 2.5.2 disposition | Blocked | Review guest package download and execution behavior |

### Next implementation sequence

1. Repeat the repository smoke suite in signed builds on a physical iPhone and
   iPad, including
   cold launch, background/foreground, low-memory, and failed-boot recovery.
2. Decide whether process-terminal shutdown is an acceptable product contract;
   otherwise patch and rebuild the upstream embed artifact so shutdown returns
   without ending the App, and add bounded native-join tests.
3. Define the default VM/command context and add a post-boot health contract;
   do not report `ready` until guest architecture and Alpine identity pass.
4. Repeat the complete native final-link and adapter smoke with the declared
   minimum Xcode 16 toolchain.
5. Add an opt-in Demo smoke configuration that injects the same prepared system
   into System, Commands, and Diagnostics without bundling an unreviewed RootFS.
6. Extend cancellation, ENOSPC, and power-loss fault injection, then measure
   command-output and RootFS memory peaks.
7. Add a session registry, bounded native reads, input, signal, resize, EOF,
   cancellation, and close-before-shutdown guarantees.
8. Pin and integrate SwiftTerm only after the PTY lifecycle contract passes on
   physical hardware.
9. Complete license/NOTICE/SBOM, corresponding-source, sandbox, security, and
   App Store policy reviews before enabling any binary distribution.

See [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md) and
[Upstream Dependencies](UpstreamDependencies.md) for the evidence behind these
gates.

## Milestone 3: Hardening

- Runtime lifecycle recovery, cancellation, and failure injection
- RootFS migration and storage policy
- Performance and memory benchmarks
- Accessibility and localization review
- Security and sandbox review
- Dependency update and artifact reproducibility checks
- Distribution review remains gated by the Milestone 2 compliance decisions

Agent, browser automation, and MCP capabilities are intentionally outside the
scope of PocketRootCore.
