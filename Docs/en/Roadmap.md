# PocketRoot Roadmap

[简体中文](../Roadmap.md) | [English](Roadmap.md) | [Documentation](README.md)

This is the single source of truth for dynamic completion, engineering gates, and next-step ordering. Product intent belongs in the [Product Plan](ProductPlan.md); immutable pins belong in [Upstream Dependencies](UpstreamDependencies.md).

Status:

- **Passed**: current evidence meets the gate; future changes still regress it.
- **In progress**: implementation exists but acceptance is incomplete.
- **Not started**: no dependable implementation yet.
- **Blocked**: waiting on upstream work, hardware, legal review, or product decision.

## Current execution sequence

1. Merged the provider-agnostic bounded `PocketRootAgent` loop.
2. Completed the OpenAI Responses API transport and host-owned credential contract.
3. Completed the approval-, command-policy-, timeout-, and output-gated Linux tool.
4. Published and pinned IshEmbed `v0.4.0-abi.6`, completing the unified
   control-path deadline, one-shot Swift Task cancellation, native exit
   confirmation, and post-cancellation recovery.
5. Current: RootFS capacity preflight, the full write/promotion ENOSPC matrix,
   explicit file/directory persistence, deterministic power-loss cut points,
   the 8 MiB sustained binary-output baseline, physical forced-relaunch
   persistence, bounded physical storage-failure recovery, and bounded physical
   memory-warning recovery are complete; continue real storage-pressure/
   power-cut, jetsam, and peak-memory hardening.
6. Native Agent Loop/App composition is paused by product decision and does not block independent runtime validation.
7. Complete signed iPad smoke when hardware is available; that gate does not block the first six items.

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
- Added positive timeouts, bounded read waits, Swift result limits, and cwd/environment/stderr/exit/signal mapping.
- Added no-follow RootFS snapshots, secure gzip/ustar, fakefs validation, versioned install, reuse, replacement, rollback, and interrupted recovery.
- Passed the exact v0.3.3 real-asset test.
- Final-linked the full graph for arm64 Simulator and unsigned device.
- Booted on iOS 18.2 arm64 Simulator.
- Passed the repository 17-check native smoke, including sustained output, both stream limits, and the Simulator lifecycle peak-memory gate.
- v0.4.0-abi.6 passed the current signed 17-check smoke on an iPhone 17 Pro
  running iOS 26.1; soft shutdown returned to Swift and lifecycle peak memory
  was 84.6 MiB.
- “Jack iPhone” (iPhone 14 Pro / iOS 26.6) passed the standard 17-check path
  and the 18-check process-suspend/resume path; guest execution recovered
  after a three-second suspension, with 89.8 MiB and 89.7 MiB peaks.
- The same device passed the 18-check real UIKit background/foreground/active
  gate with its original PID, a post-activation guest command, and an 89.4 MiB peak.

This establishes the current Simulator, minimum-Xcode 16, and single-iPhone one-shot paths, not iPad, complete physical-device lifecycle, PTY, or distribution readiness.

### Gates

| Gate | Status | Exit condition |
| --- | --- | --- |
| iOS 18 baseline | Passed | Keep package, Demo, tests, and CI aligned |
| Immutable IshEmbed pin | Passed | Change only through the supply-chain update procedure |
| One-shot adapter | Passed | Preserve lifecycle, timeout, and output-limit coverage |
| One-shot command cancellation | Passed | Queued cancellation skips native entry; active cancellation confirms `EXITED`; cleanup failure remains fail-closed |
| Native transport backpressure | Passed | Bounded protocol/session/stdin/log/control queues, an 8 MiB binary-output baseline beyond the 4 MiB backlog, and a 256 MiB Simulator lifecycle `ru_maxrss` gate are integrated; physical jetsam remains under the lifecycle gate |
| End-to-end native control-path time bound | Passed | ABI.6 finite SPAWN and bounded asynchronous close/terminate are integrated; PocketRoot reuses one deadline from driver entry and retains a fixed bounded exit-confirmation window |
| iOS 18 Simulator native behavior | Passed | v0.4.0-abi.6 passed the 17-check soft-shutdown/peak-memory smoke; keep rerunning after changes |
| Secure RootFS install/recovery | Passed | Preserve real-asset, snapshot, capacity-preflight, rollback, and recovery coverage |
| RootFS/runtime composition | Passed | Keep caller-controlled, no-download, no-auto-boot |
| Default post-boot identity gate | Passed | Require aarch64, Alpine identity, optional version, and command context before ready; retain failed-slot regression coverage |
| Real Demo runtime injection | Not started | Inject one prepared system without bundling an unreviewed RootFS |
| Host-safe soft shutdown | Passed | v0.4.0-abi.6 soft-halts, joins, and returns to Swift; the process remains single-lifecycle |
| Signed iPhone | Passed | v0.4.0-abi.6 completed the 17-check one-shot/soft-shutdown/peak-memory smoke; keep rerunning after runtime changes |
| Signed iPad | Blocked | Physical boot and command smoke |
| Minimum Xcode 16 native | Passed | Xcode 16.0 / iOS 18.0 SDK completed RootFS install, Simulator/device final links, and the 17-check native smoke |
| App lifecycle and memory | In progress | Simulator and Jack iPhone have 256 MiB `ru_maxrss` gates; physical process suspend/resume, UIKit foreground/background, post-termination data recovery, and bounded App-delegate memory-warning recovery passed; add real memory-pressure/jetsam evidence |
| RootFS ENOSPC/power faults | In progress | Peak-space preflight, full ENOSPC, seven persistence barriers, deterministic power-loss cuts, and bounded capacity/ENOSPC cleanup recovery on Jack iPhone are covered; add real storage-pressure/power-cut evidence |
| License-reviewed RootFS | Blocked | The 15-package inventory, 10 source origins, SPDX SBOM, default-configuration evidence, and checksum-pinned external source-acquisition workflow are complete; add license/NOTICE and corresponding-source delivery review plus authorized approval |
| App Store 2.5.2 | Blocked | Written guest download/execute policy decision |

### Next runtime sequence

1. Keep the 8 MiB sustained-output and 256 MiB Simulator peak regressions, and
   continue real storage-pressure/power-cut and jetsam coverage.
2. When Native Agent Loop/App composition resumes, connect a prepared system
   to UI without bundling a RootFS.
3. When a signed iPad is available, repeat preparation, boot, guest, command,
   and recovery checks with recorded toolchain and entitlements.

Closing these makes one-shot execution a Developer Preview candidate.

## Milestone 3: Upper-layer lightweight agent

Status: **In progress**.

### Completed

- Added an explicit opt-in `PocketRootAgent` product outside Core and the safe umbrella.
- Added a provider-agnostic model client, non-streaming tool loop, and prior-response continuation.
- Bounded turns, calls, user input, model text, tool arguments, and tool output.
- Rejected repeated response/call IDs and preflighted each complete call batch before sequential execution.
- Returned unknown-tool and ordinary tool failures to the model as structured results.
- Rejected concurrent runs on one runner and propagated Swift Task cancellation.
- Added a native OpenAI Responses transport covering initial input, tool-output continuation, text, and function-call decoding.
- Added an async host bearer-credential contract with sanitized loader failures and no RootFS or log exposure.
- Added strict function-schema preflight, request/response body limits, and redirect rejection.
- Added explicit opt-in `PocketRootAgentRuntimeTools`; commands execute only after structural preflight, host allow/deny policy, and per-call approval.
- Bounded command, cwd, environment, timeout, and model-visible streams, with Base64 for binary output.
- Added tool-specific synchronous preflight to whole-batch runner validation and covered policy, approval, cancellation, and no-side-effect paths.

### Gates

| Gate | Status | Exit condition |
| --- | --- | --- |
| Bounded loop core | Passed | Keep package tests and strict concurrency green |
| OpenAI transport | Passed | Keep Responses request/response/function-call, strict-schema, error, and body-limit tests green |
| Credential contract | Passed | Production backend holds the long-lived OpenAI key; mobile host loads only an app-session bearer credential |
| Linux command tool | Passed | Keep approval, allow/deny policy, cwd, timeout, output, whole-batch preflight, and cancellation tests green |
| Demo/App integration | Not started | Explicit status, tool confirmation, cancellation, error, and final-text UI |
| Persistence/streaming | Not started | Retention policy, recovery, incremental events, and resource limits |

See [Lightweight Agent Loop](Agent.md). This milestone does not move agent
orchestration into `PocketRootCore` and does not install Codex CLI in the RootFS.

## Milestone 4: Interactive terminal

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

## Milestone 5: Hardening and distribution candidate

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

Agents, browser automation, MCP, cloud orchestration, and product workflows
remain outside `PocketRootCore`. The lightweight loop lives in the explicit
`PocketRootAgent` product and composes with the runtime through stable
command/session APIs.
