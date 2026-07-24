# Changelog

[简体中文](CHANGELOG.md) | [English](CHANGELOG.en.md) | [Documentation](Docs/en/README.md)

All notable PocketRoot changes are recorded here. Semantic Versioning begins with the first public release. Everything below is currently Unreleased.

## Unreleased

### Added

- Swift Package products for Core, Terminal, Resources, and the safe umbrella.
- An explicit opt-in `PocketRootAgent` product with a provider-agnostic lightweight loop, turn/tool/input/output bounds, ID replay rejection, whole-batch validation, sequential tool execution, and cancellation propagation; it neither installs Codex CLI nor exposes a default shell tool.
- A native OpenAI Responses API transport for `PocketRootAgent` with host-owned bearer credentials, strict function-schema preflight, continuation mapping, sanitized failures, and bounded HTTP request/response bodies.
- An explicit opt-in `PocketRootAgentRuntimeTools` product whose Linux commands require whole-batch tool preflight, host allow/deny policy, and per-call approval, with cwd, environment, timeout, and model-visible output bounds.
- Programmatic UIKit Demo with System, Terminal, Commands, and Diagnostics.
- XcodeGen project source, generation, test, and build scripts.
- Placeholder runtime, terminal API foundations, and unit tests.
- Unified iOS 18 deployment baseline.
- Experimental `PocketRootIshRuntime` pinned to IshEmbed release revision `38d25d6f8726145e7e988172f12000020d89a638` and the `v0.4.0-abi.6` XCFramework.
- Experimental `PocketRootIshRuntimeIntegration` composing caller-local RootFS installation and native runtime.
- Process ownership, serial native execution, and lifecycle reentrancy protection.
- One-shot cwd, environment, stderr merge, exit, signal, timeout, and stream mapping.
- A default post-boot identity gate using a fixed command and NUL framing; ready now requires matching guest architecture, Alpine identity, optional version, and working directory.
- Positive timeout validation, bounded reads, and default 8 MiB/4 MiB stream limits.
- Immutable v0.3.3 manifest, streaming SHA-256, and byte limits.
- zlib gzip and constrained ustar extraction with traversal/link/special/duplicate rejection.
- fakefs validation, versioned installation, verified reuse, and journal-protected same-volume promotion with rollback and interrupted recovery.
- Real release-archive integration test.
- arm64 Simulator and unsigned-device final-link gates for the full Experimental graph.
- Repository iOS 18 native smoke covering 17 preparation, boot, guest, 8 MiB sustained binary-output, stdout/stderr overflow, command, cancellation, recovery, shutdown, and 256 MiB Simulator lifecycle peak-memory checks.
- A signed iPhone/iPad runner that installs through `devicectl`, injects the pinned RootFS, retrieves the report, and verifies development entitlements; the iPhone 17 Pro / iOS 26.1 baseline passed.
- Exact SwiftPM resolution in `Package.resolved`.
- IshEmbed [ADR-001](Docs/en/Decisions/ADR-001-IshEmbed-Feasibility.md) and immutable [upstream inventory](Docs/en/UpstreamDependencies.md).
- Chinese-primary, English-mirror documentation for product planning, getting started, integration, architecture, implementation, RootFS, testing, troubleshooting, roadmap, and compliance.
- Automated documentation pair, Chinese coverage, and relative-link checks.

### Changed

- `README.md` is the Chinese primary entry with status, implementation, usage, RootFS policy, and navigation; `README.en.md` is its English mirror.
- Architecture, Roadmap, Upstream, ADR, Contributing, and Changelog now have Chinese primary and English mirror documents.
- Roadmap owns dynamic status, Upstream owns pins/hashes, Testing owns evidence, and ADRs own frozen decisions.
- Contribution Git fetch/push uses SSH.
- Documentation now states that the default shared system is a placeholder and applications must retain the system returned by composition.
- Native shutdown now soft-halts, joins, and returns `.terminated`; the host process still permits one lifecycle.
- IshEmbed moves to ABI.6. Finite streaming SPAWN covers the native
  instance/spawn gates and control-queue admission from API entry. Stdin close
  reuses the original SPAWN deadline, while terminate uses bounded lifecycle
  admission. The PocketRoot driver creates one deadline before SPAWN, passes
  the remaining duration into native, and reuses the product deadline for
  close/read; timeout termination and trusted `EXITED` confirmation use a
  separate fixed cleanup window. ABI.4's signal-mask fix, ABI.3's bounded
  uname copies, and ABI.2's `/proc` lifecycle-lock fix remain; the public C ABI
  and Swift API are unchanged.
- One-shot commands support Swift Task cancellation. Queued commands may cancel
  before native entry; active commands terminate their session and return
  `CancellationError` only after trusted `EXITED`. Unconfirmed cleanup fails
  closed, while successful cancellation leaves the runtime ready.
- CI adds and passes a minimum-Xcode 16.0 full final-link, RootFS-install, and
  native-smoke gate. Node.js/npm remain optional caller-managed guest packages; Codex CLI is
  not part of the mobile installation path.
- The self-hosted XCFramework and corresponding-source assets, exact size/hash, nested iSH gitlink, and separate RootFS pin are recorded.
- One-shot commands and the optional boot supervisor path reject NUL-containing C-string inputs before entering the native driver; command environments also reject ambiguous keys.
- Wire v4 returns supervisor rejection, broken pipe, and native backlog overflow
  as typed errors. Normal guest exit 17 is returned; negative `EXITED` fails
  closed. PocketRoot maps native backlog limits and conservatively closes its
  process gate because the void close ABI cannot report instance fail-close.
- RootFS attribute-read failures during boot preflight map to typed `rootFSUnavailable` and leave the runtime idle before the native process slot is claimed.
- The process gate now compares owner UUIDs explicitly, with a direct regression test rejecting another runtime's claim and ownership check.
- The ustar extractor now records parent directories implicitly created by file/directory entries and rejects later duplicate entries or filesystem-equivalent directory targets; RootFS journal documentation no longer promises power-loss durability without explicit `fsync`.
- New RootFS installs and upgrades now preflight same-volume additional space
  for the compressed snapshot, temporary tar, materialized payload, and a
  16 MiB reserve before creating staging. Insufficient capacity returns a
  typed error without touching a valid prior version for the new install.
  ENOSPC injection across snapshot, partial gzip output, tar payload,
  installation-record, promotion-journal, `current.json`, and both destructive
  promotion checkpoints verifies temporary cleanup, prior-version preservation,
  and current-record rollback; POSIX write failures use stable system messages.
- RootFS promotion now persists the candidate tree and installation record with
  `F_FULLFSYNC` (`fsync` fallback), atomically persists journal/`current.json`,
  and synchronizes source and destination parents after each cross-directory
  rename. A seven-barrier I/O-failure matrix plus journal-only, backup, and
  candidate power-loss cut points verifies commit/rollback; physical-device
  power-cut and storage-pressure evidence remains separate. The caller must
  pre-create the installation base; mode `000` candidate entries temporarily
  gain staging-only flush access and restore their original mode through the
  open descriptor before synchronization. Staging/backup cleanup makes only
  the soon-to-be-deleted directories traversable so restricted modes cannot
  leak a transaction.
- `PocketRootSystem` now refreshes stable public state after lifecycle/command success or failure, immediately publishes `.failed` after fail-close, hides transient lifecycle state from reentrant calls, and generations state refreshes so an older snapshot cannot overwrite a newer failure.
- Native spike/smoke targets explicitly exclude x86_64 Simulator, and documentation clarifies that `isAvailable` is a post-link probe rather than a substitute for the arm64-only binary's build constraint.
- The native smoke runner now selects an iOS 18 Simulator by its stable runtime identifier instead of the final `simctl` output field, with fixture regression tests for multiple output formats.
- The native smoke App now enforces an iOS 18+ lower bound instead of incorrectly requiring 18.x and records device family, system name, and version in its report.

### Security

- RootFS payloads remain uncommitted, unbundled, and never downloaded by the library.
- Production, TestFlight, and public binary distribution remain blocked pending license, NOTICE, source, SBOM, physical-device, and App Store 2.5.2 gates.
