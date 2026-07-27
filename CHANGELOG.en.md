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
- A reproducible pinned-RootFS compliance generator, CI comparison, and pinned
  official-schema validation covering
  the 15-package inventory, 10 source origins, SPDX 2.3 JSON SBOM,
  declared-license/attribution inventories, and default `apk`, repository, and
  DNS configuration; complete LICENSE/NOTICE and corresponding-source bundles
  remain distribution blockers.
- A checksum-bound `LICENSE-REVIEW-RESULTS.json` and strict validator. All 32
  pinned RootFS license/NOTICE candidates have engineering review results;
  eight source origins retain package-level open items, and legal and
  redistribution gates remain closed.
- A checksum-bound `LICENSE-NOTICE-CANDIDATES.json`, strict validator, and
  outside-repository atomic materializer for the eight remaining RootFS source
  origins. It indexes 13 remote license/attribution payloads, 47 aports files,
  and the 32 existing evidence files for complete re-verification without
  committing payloads or opening engineering, legal, or redistribution gates.
- `LICENSE-NOTICE-REVIEW-RESULTS.json` and a strict external payload-tree
  verifier. All 92 candidate payloads now have checksum-bound engineering
  review. The pinned upstream `alpine-keys` GPL-to-MIT license-decision commit
  is included while its package-level copyright notice remains open. The
  `ca-certificates` generator is byte-identical to curl commit `3fdc4bdb`, and
  that exact revision's curl license is pinned while trust-store review stays
  open. The pinned BusyBox configuration now binds enabled bzip2 support to
  its exact source license, confirms that enabled ash arithmetic links
  `shell/math.c`, which retains complete MIT and BSD-3-Clause notices, and
  confirms that the installed `env`, `echo`, `logger`, and `cal` applets link
  `coreutils/env.c`, `coreutils/echo.c`, `sysklogd/logger.c`, and
  `util-linux/cal.c`, respectively, while `ping` and `ping6` share
  `networking/ping.c`, and `traceroute` and `traceroute6` share
  `networking/traceroute.c`; each retains its complete BSD notice, including
  the original BSD/LBL notice for traceroute. The desktop `od` build includes
  `coreutils/od.c` and `coreutils/od_bloaty.c`, while `hexdump` and `hd` share
  `util-linux/hexdump.c` and use `libbb/dump.c`, covering the complete Regents
  BSD terms, FSF attribution, and GPL declarations. Other inline notices stay open;
  `apk-tools`, `openssl`, and `pax-utils` have no remaining
  candidate-material engineering items, five origins still need
  package-specific material, and
  legal and redistribution gates remain closed.
- Strict external download-cache input for the RootFS source-review
  materializer. A cache replaces network transport only: inputs remain
  size-bounded and symlink/overlap-rejected, with pinned SHA-512 and canonical
  extracted-aports-tree verification; v2 receipts distinguish network from
  cache acquisition instead of fabricating a selected URL, and ambiguous
  legacy v1 bundles must be regenerated through cache mode.
- arm64 Simulator and unsigned-device final-link gates for the full Experimental graph.
- Repository iOS 18 native smoke covering 17 preparation, boot, guest, 8 MiB sustained binary-output, stdout/stderr overflow, command, cancellation, recovery, shutdown, and 256 MiB Simulator lifecycle peak-memory checks.
- A repository-external, unapproved RootFS double-build candidate path for the
  native smoke. It verifies candidate provenance, receipt, identity, companion
  digests, and `distributionAuthorized=false` before creating an ephemeral
  sidecar. The extractor discards bounded PAX control headers before guest path
  materialization while retaining traversal rejection for real entries.
- A signed iPhone/iPad runner that installs through `devicectl`, injects the pinned RootFS, retrieves the report, and verifies development entitlements; the iPhone 17 Pro / iOS 26.1 baseline passed.
- A signed-device forced-relaunch persistence gate that terminates a seed PID with SIGKILL after syncing guest data, then requires a new verification PID to reuse the RootFS, recover and clean the data, and complete the standard shutdown and memory checks.
- A signed-device bounded storage-failure gate that fixes capacity at zero and injects ENOSPC after one gzip-output byte, requires both failures to leave no installation residue, then recovers in the same directory and completes the standard smoke.
- A signed-device bounded memory-warning gate that deterministically invokes the public App-delegate callback during an active guest command and requires fresh callback evidence, the active and later commands, `.ready`, shutdown, and peak-memory gates to pass without claiming real memory pressure or jetsam.
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
- The signed-device runner now accepts a CoreDevice UUID, hardware UDID, or
  device name recognized by `devicectl`, validates physical iOS properties
  through the supported JSON output, and passes the resolved hardware UDID to
  `xcodebuild` and later device operations.
- v0.4.0-abi.6 passed the current 17-check native smoke on a signed iPhone
  17 Pro running iOS 26.1; soft shutdown returned to Swift and lifecycle peak
  memory was 84.6 MiB.
- The physical runner adds an explicit `POCKETROOT_SMOKE_LIFECYCLE=1` mode that
  suspends/resumes the App by the launch-JSON PID and requires a post-resume
  guest command plus shutdown. Jack iPhone (iPhone 14 Pro / iOS 26.6) passed
  all 18 checks with an 89.7 MiB peak.
- The mutually exclusive `POCKETROOT_SMOKE_UI_LIFECYCLE=1` mode uses Settings
  to produce a real UIKit background/foreground transition, requires the
  original PID and ordered App-delegate callbacks, and executes a new guest
  command after activation. Jack iPhone passed all 18 checks at an 89.4 MiB peak.

### Security

- RootFS payloads remain uncommitted, unbundled, and never downloaded by the library.
- Production, TestFlight, and public binary distribution remain blocked pending license, NOTICE, source, SBOM, physical-device, and App Store 2.5.2 gates.
