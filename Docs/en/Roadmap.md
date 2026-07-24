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
4. Published and pinned soft-shutdown IshEmbed `v0.4.0-abi.3`.
5. Current: finish Codex CR, CI, and PR merge for the new pin; final-link, Simulator lifecycle, and documentation are closed.
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
- Passed the repository 13-check native smoke.
- The older v0.3.3 baseline passed the same signed 13-check smoke on an iPhone
  17 Pro running iOS 26.1; v0.4.0-abi.3 still requires a signed-device rerun.

This establishes the current Simulator and single-iPhone one-shot paths, not iPad, complete physical-device lifecycle, minimum-Xcode, PTY, or distribution readiness.

### Gates

| Gate | Status | Exit condition |
| --- | --- | --- |
| iOS 18 baseline | Passed | Keep package, Demo, tests, and CI aligned |
| Immutable IshEmbed pin | Passed | Change only through the supply-chain update procedure |
| One-shot adapter | Passed | Preserve lifecycle, timeout, and output-limit coverage |
| Native transport backpressure | In progress | Bounded protocol/session/stdin/log/control queues are integrated; sustained-output and peak-memory tests remain |
| End-to-end native control-path time bound | In progress | Native control is bounded; PocketRoot's request deadline still needs to cover pre-spawn/closeStdin stages |
| iOS 18 Simulator native behavior | Passed | v0.4.0-abi.3 passed the 13-check soft-shutdown smoke; keep rerunning after changes |
| Secure RootFS install/recovery | Passed | Preserve real-asset/snapshot/rollback/recovery; add ENOSPC |
| RootFS/runtime composition | Passed | Keep caller-controlled, no-download, no-auto-boot |
| Default post-boot identity gate | Passed | Require aarch64, Alpine identity, optional version, and command context before ready; retain failed-slot regression coverage |
| Real Demo runtime injection | Not started | Inject one prepared system without bundling an unreviewed RootFS |
| Host-safe soft shutdown | Passed | v0.4.0-abi.3 soft-halts, joins, and returns to Swift; the process remains single-lifecycle |
| Signed iPhone | In progress | The v0.3.3 baseline passed; rerun is required after the v0.4.0-abi.3 runtime change |
| Signed iPad | Blocked | Physical boot and command smoke |
| Minimum Xcode 16 native | In progress | PR CI must complete the full final-link, RootFS install, and native smoke with Xcode 16.0 |
| App lifecycle and memory | Not started | Background/foreground, jetsam, failure, persistence |
| RootFS ENOSPC/power faults | Not started | Storage-pressure transaction fault matrix |
| License-reviewed RootFS | Blocked | Complete license, NOTICE, source, and SBOM |
| App Store 2.5.2 | Blocked | Written guest download/execute policy decision |

### Remaining runtime sequence

1. Local final-link, RootFS install, Simulator smoke, and dependency evidence
   are complete; finish Codex CR, Xcode 16/full CI, and PR merge.
2. Add complete cancellation, ENOSPC, power-loss, storage-pressure,
   long-output, and memory-peak coverage.
3. When Native Agent Loop/App composition resumes, connect a prepared system
   to UI without bundling a RootFS.
4. When a signed iPad is available, repeat preparation, boot, guest, command,
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
