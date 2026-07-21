# PocketRoot Roadmap

[简体中文](../Roadmap.md) | [English](Roadmap.md) | [Documentation](README.md)

This is the single source of truth for dynamic completion, engineering gates, and next-step ordering. Product intent belongs in the [Product Plan](ProductPlan.md); immutable pins belong in [Upstream Dependencies](UpstreamDependencies.md).

Status:

- **Passed**: current evidence meets the gate; future changes still regress it.
- **In progress**: implementation exists but acceptance is incomplete.
- **Not started**: no dependable implementation yet.
- **Blocked**: waiting on upstream work, hardware, legal review, or product decision.

## Milestone 1: Project foundation

Status: **Passed**.

Completed:

- Swift Package modules and public runtime/command/session/terminal foundations.
- Safe placeholder runtime and terminal behavior.
- Programmatic UIKit Demo with four tabs.
- XcodeGen, scripts, documentation, tests, and GitHub Actions.
- Unified iOS 18.0 baseline.
- Host package tests, pinned RootFS CI validation, generic Simulator Demo build, and arm64 Experimental final links.

| Baseline | Requirement |
| --- | --- |
| Xcode | 16.0+ with iOS 18 SDK |
| Swift Package | Swift 5.10+ |
| Deployment | iOS 18.0 |
| Project source | `project.yml` |
| Generated project | Not committed |

## Milestone 2: ARM64 Linux one-shot commands

Status: **Experimental, in progress**.

### Completed feasibility foundation

- Audited the user fork and parent repository.
- Pinned the full package revision and nested iSH gitlink.
- Independently verified XCFramework and RootFS hashes.
- Added opt-in runtime and integration products.
- Added process ownership, serial native execution, and lifecycle reentrancy protection.
- Added positive timeouts, bounded reads, stream limits, cwd/environment/stderr/exit/signal mapping.
- Added no-follow RootFS snapshots, secure gzip/ustar, fakefs validation, versioned install, reuse, replacement, rollback, and interrupted recovery.
- Passed the exact v0.3.3 real-asset test.
- Final-linked the full graph for arm64 Simulator and unsigned device.
- Booted on iOS 18.2 arm64 Simulator.
- Passed the repository 13-check native smoke.

This establishes the current Simulator one-shot path, not physical-device, minimum-Xcode, PTY, or distribution readiness.

### Gates

| Gate | Status | Exit condition |
| --- | --- | --- |
| iOS 18 baseline | Passed | Keep package, Demo, tests, and CI aligned |
| Immutable IshEmbed pin | Passed | Change only through the supply-chain update procedure |
| One-shot adapter | Passed | Preserve lifecycle, timeout, and output-limit coverage |
| iOS 18 Simulator native behavior | Passed | Rerun the 13-check smoke for runtime/RootFS changes |
| Secure RootFS install/recovery | Passed | Preserve real-asset/snapshot/rollback/recovery; add ENOSPC |
| RootFS/runtime composition | Passed | Keep caller-controlled, no-download, no-auto-boot |
| Default post-boot health gate | Not started | Require aarch64, Alpine identity, and command context before ready |
| Real Demo runtime injection | Not started | Inject one prepared system without bundling an unreviewed RootFS |
| Host-safe soft shutdown | Blocked | Patch fork, return kernel thread, bound joins, rebuild and audit |
| Signed iPhone | Blocked | Physical boot and command smoke |
| Signed iPad | Blocked | Physical boot and command smoke |
| Minimum Xcode 16 native | Not started | Repeat final-link and behavior |
| App lifecycle and memory | Not started | Background/foreground, jetsam, failure, persistence |
| RootFS ENOSPC/power faults | Not started | Storage-pressure transaction fault matrix |
| License-reviewed RootFS | Blocked | Complete license, NOTICE, source, and SBOM |
| App Store 2.5.2 | Blocked | Written guest download/execute policy decision |

### Next sequence

1. Run signed preparation, boot, guest, command, and recovery checks on iPhone and iPad with recorded toolchains and entitlements.
2. Decide whether host-process exit is acceptable; otherwise rebuild a soft-shutdown artifact with bounded joins and repeat audits.
3. Define the default guest context and require architecture/version/tool health before ready.
4. Repeat full final-link, install, and native smoke with minimum Xcode 16.
5. Add opt-in Demo injection of one prepared system across System, Commands, and Diagnostics.
6. Add complete cancellation, ENOSPC, power-loss, storage-pressure, long-output, and memory-peak coverage.

Closing these makes one-shot execution a Developer Preview candidate.

## Milestone 3: Interactive terminal

Status: **Not started**.

Implement in order:

1. Public interactive session entry.
2. Process-wide live-session registry.
3. Bounded native PTY reads.
4. stdin write/close.
5. output and exit events.
6. size and resize.
7. signal, EOF, and cancellation.
8. idempotent close.
9. close-all-before-shutdown.
10. physical-device lifecycle tests.
11. Pin SwiftTerm.
12. TerminalBridge/UIKit integration.
13. Accessibility, keyboard, and iPad layout.

Do not adopt the high-level upstream terminal wrapper or SwiftTerm before native pointer ownership, read cancellation, and close order are proven.

Acceptance requires predictable session lifecycle, ownership across app transitions, no use-after-free or unbounded reads, shutdown behind all sessions, usable device keyboards/resize/VoiceOver, and recoverable errors.

## Milestone 4: Hardening and distribution candidate

Status: **Not started / gated**.

Engineering includes lifecycle recovery, RootFS migration/data policy, performance/memory/battery, long workloads, storage/jetsam, reproducible dependency builds, security/sandbox, localization/accessibility, and telemetry/privacy.

Compliance includes PocketRoot license, upstream LICENSE/NOTICE, corresponding source, SBOM, provenance, App Store 2.5.2, privacy manifest, release notes, and known limits.

A Beta or Distribution Candidate can be defined only after every distribution blocker has an approved disposition.

## Shared requirements

- Update Chinese and English documentation.
- Update changelog.
- Pin dependencies and hashes.
- Run the required [test matrix](Testing.md).
- Never commit a RootFS or unreviewed binary.
- Do not describe link success as runtime success.
- Do not describe Simulator success as physical-device support.
- Do not describe technical validation as legal or App Review approval.

Agents, browser automation, MCP, cloud orchestration, and product workflows remain outside PocketRootCore.
