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
5. Completed the maximal Experimental engineering-composition inventory/SPDX
   SBOM and added a deterministic external `.app`/`.xcarchive` scanner. CI now
   scans the unsigned device runtime App's files, Mach-O metadata,
   entitlements, and risk signals, and the local development-signed engineering
   archive gate is complete; final release signing/export scanning and the
   complete release-artifact SBOM remain closed.
6. Current: RootFS capacity preflight, the full write/promotion ENOSPC matrix,
   explicit file/directory persistence, deterministic power-loss cut points,
   the 8 MiB sustained binary-output baseline, physical forced-relaunch
   persistence, bounded physical storage-failure recovery, and bounded physical
   memory-warning recovery are complete; continue real storage-pressure/
   power-cut, jetsam, and peak-memory hardening.
7. Native Agent Loop/App composition is paused by product decision and does not block independent runtime validation.
8. Complete signed iPad smoke when hardware is available; that gate does not block the first seven items.

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
| Demo and external-host runtime integration | Passed | The Demo and standalone Host App share the public controller; Debug injects only the exact verified external RootFS and Release remains payload-free |
| Host-safe soft shutdown | Passed | v0.4.0-abi.6 soft-halts, joins, and returns to Swift; the process remains single-lifecycle |
| Signed iPhone | Passed | v0.4.0-abi.6 completed the 17-check one-shot/soft-shutdown/peak-memory smoke; keep rerunning after runtime changes |
| Signed iPad | Blocked | Physical boot and command smoke |
| Minimum Xcode 16 native | Passed | Xcode 16.0 / iOS 18.0 SDK completed RootFS install, Simulator/device final links, and the 17-check native smoke |
| App lifecycle and memory | In progress | Simulator and Jack iPhone have 256 MiB `ru_maxrss` gates; physical process suspend/resume, UIKit foreground/background, post-termination data recovery, and bounded App-delegate memory-warning recovery passed; add real memory-pressure/jetsam evidence |
| RootFS ENOSPC/power faults | In progress | Peak-space preflight, full ENOSPC, seven persistence barriers, deterministic power-loss cuts, and bounded capacity/ENOSPC cleanup recovery on Jack iPhone are covered; add real storage-pressure/power-cut evidence |
| Maximal Experimental engineering composition inventory/SBOM | Passed | Keep SwiftPM/Xcode targets, ABI.6 dependency/source, the external RootFS's 15 packages, and checksums reproducible; never describe it as a final release-archive scan or distribution authorization |
| Unsigned engineering App scan | Passed | CI ephemerally scans the full file tree, Mach-O, signature/entitlements, private-framework/JIT signals, and validates the file-level SPDX; upload no output and keep every final-release gate closed |
| Development-signed engineering archive | Passed | Locally build a standard `.xcarchive`, require development entitlements and a valid signature, and re-verify clean risk evidence and SPDX; never install/export/upload it and keep every final-release gate closed |
| License-reviewed RootFS | Blocked | The 15-package/10-origin evidence, corresponding-source candidate material for all 10 origins, all 78 initial candidates, and all 138 external LICENSE/NOTICE payloads have checksum-bound engineering review. The historical builder is identified; a schema-v4 successor is reproducible across same-host invocations, with a five-unit delivery inventory and unified external candidate materializer. Only the `alpine-keys` MIT grant/copyright notice remains open, followed by a pinned-release exact-rebuild conclusion, complete NOTICE/source offer, legal review, delivery approval, and authorized release |
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

Status: **First PTY/files closure implemented; device and iPad gates remain**.

A low-cost precursor now works without the Agent Loop, PTY, or SwiftTerm:

- `PocketRootCommandTerminalSession` carries the current working directory
  across bounded one-shot commands.
- Ordinary `ls`, `cd`, `mkdir`, `touch`, and redirected file creation can be
  submitted consecutively.
- UIKit and SwiftUI hosts can inject an already-booted `PocketRootSystem`.
- Every command retains the existing timeout, cancellation, output-limit, and
  runtime fail-close behavior.

The facade starts a new `/bin/sh -lc` for every submission and is not a PTY.
Shell variables, aliases, and background jobs do not persist, and interactive
programs such as `vim` and `top` remain unsupported.

Completed in this closure:

1. Public `PocketRootSystem.makeSession` and live-session registry.
2. 100 ms bounded reads and fixed Swift event backlog.
3. stdin/output/exit, resize, signal, EOF, idempotent termination, and
   close-all-before-shutdown.
4. SwiftTerm pinned at `dd2fb8ac…` with UIKit and SwiftUI bridges.
5. NUL-framed guest directory browsing and bounded file preview.
6. Session/runtime/file-browser tests and strict-concurrency iOS compilation.
7. A real iOS 18 Simulator UI closure that boots and covers sustained
   SwiftTerm input/output, background/foreground, rotation resize,
   close/reopen, persistent Files preview, and ordered shutdown; Xcode 16 CI
   reruns it.
8. A repository-owned physical Host App runner that validates physical iOS,
   development signing and entitlements, reuses the same lifecycle UI test,
   and fails closed when the device OS exceeds Xcode's support range.

The remaining iPhone gate is execution under an Xcode whose device-support
range includes the selected signed device. Jack iPhone currently runs iOS 26.6
beta while the installed Xcode 26.1.1 officially supports devices through iOS
26.1; its signed build was verified, but the incompatible XCTest session is not
counted as passed. Physical interactive-program, real memory-pressure, and
long-duration output evidence remain, plus iPad keyboard, rotation, layout, and
VoiceOver verification. The implementation retains direct low-level
`IshSession` ownership and does not use the upstream high-level terminal wrapper.

Acceptance requires predictable session lifecycle, ownership across app transitions, no use-after-free or unbounded reads, shutdown behind all sessions, usable device keyboards/resize/VoiceOver, and recoverable errors.

## Milestone 5: Hardening and distribution candidate

Status: **Not started / gated**.

Engineering includes lifecycle recovery, RootFS migration/data policy, performance/memory/battery, long workloads, storage/jetsam, reproducible dependency builds, security/sandbox, localization/accessibility, and telemetry/privacy.

Compliance includes PocketRoot license, upstream LICENSE/NOTICE, corresponding
source, the already-generated maximal engineering-composition and unsigned
engineering-App file-level SBOMs, a final signed/exported built-and-scanned
release-artifact SBOM, provenance, App Store 2.5.2, privacy manifest, release
notes, and known limits.

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
