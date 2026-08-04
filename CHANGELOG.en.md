# Changelog

[简体中文](CHANGELOG.md) | [English](CHANGELOG.en.md) | [Documentation](Docs/en/README.md)

All notable PocketRoot changes are recorded here. Semantic Versioning begins with the first public release.

## Unreleased

### Changed

- Tiered the CI UI matrix by platform: ordinary PRs and default manual runs
  execute the external consumer, Quick Start iPhone, and Host App iPhone;
  `main` pushes keep the same routine iPhone baseline. After several larger
  feature blocks, or for a release candidate, explicitly add iPad on the target
  branch with `workflow_dispatch`/`include_ipad=true`. Small development steps
  use targeted tests, so the full platform matrix no longer repeats on every
  merge.
- Host App Files UI smoke now waits for the expected rename, delete, or share
  action to enter the accessibility tree after pressing a file or directory.
  If the first synthesized press does not open the menu, it retries once with
  newly validated App and entry frames, then fails closed with frame evidence
  instead of tapping a context-menu button that does not yet exist. File and
  folder creation also dismisses system keyboard onboarding before submitting
  a freshly validated Create frame at most twice, then stops the test if the
  expected entry never appears instead of cascading into missing-disclosure
  failures. Integrated-workspace verification now writes per-run unique guest
  contents and treats their exact file preview as authoritative when terminal
  accessibility text lags, and the document-picker flow rechecks whether
  Browse already restored the Host destination before interacting with a
  disappearing local-location cell. Host and Quick Start keyboard cleanup now
  taps validated snapshot frames and gives onboarding UI a bounded dismissal
  window instead of targeting elements that disappear during XCTest
  interruption handling. The shared UI runner also recognizes an XCTest
  Accessibility-load timeout before any test method runs as Simulator
  infrastructure failure, restarting only its own temporary Simulator for one
  bounded retry; caller-owned devices, ordinary assertions, and a second
  failure still fail closed immediately.
- Host App iPad file-creation smoke no longer semantically taps `New File` or
  `New Folder` directly in a popover. It revalidates the App and action frames,
  performs a bounded physical-coordinate retry, and attaches the accessibility
  hierarchy plus final frames if the name field never appears. Entering the
  local document-picker location now also re-queries its target before every
  attempt, using the sidebar item first and a newly resolved text frame inside
  that row second. Both attempts dispatch only through captured App
  coordinates while waiting for either Host navigation state or the Host
  container. If neither completes the transition, hierarchy evidence is kept
  without asking a disappearing system cell to resolve and perform its own
  action.
- Files export now follows the UIKit presentation contract by showing
  `UIActivityViewController` in a popover on iPad and adapting to a sheet only
  in compact-width environments such as iPhone. This avoids the former iPad
  modal path getting stuck with a dimmed background while the share content
  remains below the screen. The temporary export directory is now removed by
  the `UIActivityViewController` completion callback, so it is not deleted
  while the popover hands the URL to the `Save to Files` document picker; it
  is still cleaned up after completion, cancellation, or dismissal. A
  dedicated iPad export UI smoke now verifies the platform activity UI, the
  `Save to Files` action, and the actual document-picker handoff without
  depending on system file import, while the system round-trip activates its
  share menu action through a freshly validated physical frame.
- Tightened the untagged `v0.2.0` source-candidate audit:
  `--allow-source-blocked` accepts only final source-release authorization as
  unsatisfied, and fails on any pinned-gate-set, NOTICE, license, public API
  status, or source-boundary drift. CI and the trusted tag workflow upload only
  a JSON verification report with the commit, archive SHA-256, file counts,
  and exact blockers—not the temporary source tar, RootFS, App, or binaries.
- Split the minimum-Xcode 16 gate into an independent native-runtime job and a
  five-way `fail-fast: false` UI matrix for the public-SHA external consumer,
  Quick Start iPhone/iPad, and Host App iPhone/iPad. Every isolated runner
  re-verifies the RootFS, XcodeGen, Xcode 16, and iOS 18 runtime through one
  repository-owned composite action without transferring an unreviewed App or
  DerivedData; each lane has a collision-free failure artifact. A runner-owned
  Simulator that explicitly disappears from Xcode destinations is recreated
  with the same runtime/device type for one bounded retry; caller-owned devices
  and assertion failures are never retried. Coverage is unchanged while PR
  wall-clock time no longer accumulates every UI smoke serially.

## 0.2.0 - Unreleased

### Added

- Interactive SwiftTerm PTYs now show an iPhone-friendly Esc, Tab, Ctrl-C,
  Ctrl-D, history up/down, and keyboard-dismiss key row by default; hosts can
  hide it with `showsAccessoryView: false`. Unit tests pin every emitted byte, and the Host
  App lifecycle smoke launches BusyBox `top`, observes live output, and uses
  Ctrl-C to recover the shell.
- Bilingual security and community-conduct policies, support routing,
  structured bug/integration/feature Issue forms, and a pull request checklist.
  Documentation validation now requires these open-source collaboration files
  and complete root-level Chinese/English mirrors.

### Changed

- RootFS delivery-candidate output bounding now tolerates macOS `EPERM` from a
  process-group exit race only after Open3 confirms the child has exited and a
  signal-zero probe confirms the whole group is gone. Surviving or unsignalable
  descendants still fail closed, while CI can reliably reap an already-exited
  command instead of leaking a platform exception.
- The Host App system-file import/share UI smoke no longer queries the SwiftUI
  toolbar Actions button's `hittable` state directly. Xcode 16 iPhone/iPad
  Simulators can briefly report infinite-origin, zero-sized App and button
  accessibility frames while a system controller dismisses. The test now
  re-queries the element, waits for finite App/button frames whose button center
  is inside the App, taps through the captured App coordinate, and confirms the
  menu opened. A missed tap receives one clean App relaunch retry, and an
  unobserved share sheet uses the same fail-closed recovery instead of trusting
  underlying host geometry.
- The physical Host App UI runner no longer treats a device-OS versus iOS-SDK
  minor-version comparison as Xcode's device-support range. `xcodebuild` with
  the exact destination provides the authoritative result. Earlier Xcode
  26.1.1 attempts timed out during the automation-mode handshake; Xcode 26.6
  subsequently development-signed and passed the complete lifecycle XCTest on
  Jack iPhone / iOS 26.6, including BusyBox `top`, Ctrl-C,
  background/foreground, rotation resize, PTY reopen, persistent Files preview,
  and ordered shutdown.
- Upgraded the three-minute signed-device workload into a configurable
  Simulator/physical stability gate. One PTY stays open for 20...600 cycles,
  streams a uniquely delimited 64 KiB zero-byte payload every tenth cycle,
  verifies its exact length and content, and is cross-checked through one-shot
  commands and Files. It must survive a midway stdout-limit failure. The
  collector retains only its latest 1 MiB, post-warm-up `phys_footprint` growth
  is capped at 64 MiB, and samples/lifecycle peak remain capped at 256 MiB. The
  minimum-toolchain CI runs a 30×250-ms path; the old variable remains an alias.
  This bounded baseline is not real pressure, jetsam, power-cut, or sustained
  background-execution evidence.
- Jack iPhone (iPhone 14 Pro / iOS 26.6) completed the default 90×2-second
  physical stability gate with Xcode 26.6. All 20 checks passed while one PTY
  remained active for 90 file cycles, 576 KiB of uniquely delimited zero-byte
  output, stdout-limit recovery, and a Files preview. Post-warm-up
  `phys_footprint` growth was 0.0 MiB and the lifecycle peak was 83.2 MiB.
  This evidence is still not real storage pressure, forced power loss, jetsam,
  or background-longevity coverage.
- The Host App iPad system-file round-trip UI smoke no longer reads
  `ActivityListView.frame` after the share sheet may have disappeared. It now
  takes one fallible snapshot and dismisses only through an app-corner point
  verified outside that snapshot frame, eliminating the XCTest race caused by
  a system accessibility node vanishing between queries while preserving the
  relaunch recovery path when no safe point exists.
- Split the Host App Files/Workspace and PTY lifecycle UI smoke phases across
  independent Simulators and `xcodebuild` invocations, retaining phase
  checkpoints, `.xcresult`, test output, and PocketRoot Simulator logs on
  failure while keeping a ten-minute hard limit per test. The system-file
  round trip now uses one 60-second state loop for the Host fixture, a local
  location, or an interactive `Browse` transition instead of mistaking an early
  navigation bar for readiness. If the picker is still on Recents, it taps the
  `Browse` tab, which can enter the Xcode 16 accessibility tree late; a picker
  already in the Host folder does not return until the fixture file is actually
  visible. Fixture selection uses a verified current frame and retries once if
  iOS 18.0 leaves the picker open after reporting a synthesized tap. The helper
  returns an explicit success state so a failed navigation or selection ends
  the test case without cascading taps and secondary failures. The PTY size
  probe likewise refocuses and resends only once when the first synthesized
  command's unique marker remains absent for 15 seconds; the final 30-second
  assertion still exposes a real terminal-input or resize synchronization
  failure. The shared
  UI runner restarts and retries
  exactly once only when its own temporary Simulator test runner was not
  registered with FrontBoard; caller-supplied shared Simulators are not
  restarted, and assertion, timeout, and other build failures still fail
  immediately. If retry or restart fails, both attempt logs and available
  `.xcresult` bundles are retained.
- The native Xcode 16 lane validates the real RootFS install before downloading
  the multi-gigabyte Simulator runtime, preserving the disk headroom enforced
  by the installer while UI lanes retain the shared one-step setup.

## 0.1.0 - 2026-07-31

### Added

- A `v0.1.0` source-tag audit that validates version authorization, release
  documents, and source readiness inside the selected Git ref's isolated
  snapshot; rejects RootFS, App/IPA/XCFramework, compressed/archive, native,
  and unknown binary payloads; the trusted `main` release workflow requires an
  annotated tag and resolves the exact SwiftPM version from an external consumer.
- Version-based upstream pins for the same audited commits—
  IshEmbed `0.4.0-abi.9.1` and the SwiftTerm mirror
  `1.15.0-pocketroot.1`—so an external App can resolve PocketRoot at `0.1.0`.
  Both package tags are locked by GitHub immutable Releases, and the release
  gate rechecks their peeled commits.
- Fail-closed `v0.1.0` two-track release gates. Machine-readable status, a
  bilingual checklist, and CI status separate source/Swift Package release
  from runtime/App/binary distribution that excludes every RootFS asset; each
  requires explicit authorization, and passing engineering tests never unblocks
  distribution or authorizes RootFS distribution. Runtime readiness now also
  requires the top-level license and dedicated final-release evidence; the
  current engineering scanner cannot make runtime Ready even for a signed
  `.xcarchive`. A future schema must bind signature/entitlement/risk metadata
  to the reviewed artifact and provide content-based RootFS absence evidence.
- Swift Package products for Core, Terminal, Resources, and the safe umbrella.
- An explicit opt-in `PocketRootAgent` product with a provider-agnostic lightweight loop, turn/tool/input/output bounds, ID replay rejection, whole-batch validation, sequential tool execution, and cancellation propagation; it neither installs Codex CLI nor exposes a default shell tool.
- A native OpenAI Responses API transport for `PocketRootAgent` with host-owned bearer credentials, strict function-schema preflight, continuation mapping, sanitized failures, and bounded HTTP request/response bodies.
- An explicit opt-in `PocketRootAgentRuntimeTools` product whose Linux commands require whole-batch tool preflight, host allow/deny policy, and per-call approval, with cwd, environment, timeout, and model-visible output bounds.
- Programmatic UIKit Demo with System, Terminal, Files, Commands, and Diagnostics.
- A real Demo composition connecting Experimental iSH, SwiftTerm PTY,
  Commands, and Files, with Debug-only size/digest-verified external RootFS
  injection, shared runtime lifecycle, and dynamic Diagnostics; Release never
  injects the asset.
- XcodeGen project source, generation, test, and build scripts.
- Placeholder runtime, terminal API foundations, and unit tests.
- A lightweight command terminal that does not depend on the Agent Loop or a
  PTY. It carries the working directory across bounded one-shot commands for
  consecutive `ls`, `cd`, and file operations, exposes UIKit and SwiftUI UI
  backed by an injected `PocketRootSystem`, serializes and cancels commands,
  and bounds transcript size.
- Full `PocketRootSystem.makeSession` support with a real IshEmbed PTY,
  bounded reads, input, resize, signal/EOF, idempotent termination,
  live-session registry, and close-all-before-shutdown. Session creation is
  interlocked with shutdown, fatal transport failures fail the runtime closed,
  finite native admission prevents unbounded termination controls, Swift output
  is chunked into a 4 MiB cap while preserving terminal events, and native
  shutdown requires authoritative session exits. Canceled creation closes any
  unreturned native session, while recoverable supervisor/EOF errors remain
  session-local.
- SwiftTerm pinned at `dd2fb8ac…` with UIKit/SwiftUI terminal pages, plus a
  NUL-framed guest folder page with lazy inline tree expansion, directory
  navigation, bounded text/binary previews up to 512 KiB, file/folder creation,
  atomic no-replace rename, and confirmation-gated recursive deletion. Rename
  uses the native IshEmbed `v0.4.0-abi.9` guest operation rather than a shell
  check-then-move sequence.
- Binary `standardInput` for one-shot commands with a 1 MiB default cap, plus
  system-document import and share-sheet export in the Files UI and actor API.
  Import bytes never enter shell text: stdin writes a private same-directory
  staging file and ABI.9 atomically commits it without replacement; failure
  and cancellation perform best-effort cleanup, while export checks size both
  before and after reading.
- Public UIKit/SwiftUI Workspace composition surfaces for an already-booted
  system. Terminal and Files stay alive across switches, removal closes the
  PTY, and the Host App UI smoke verifies file creation, preview, and return to
  the same session.
- A process-retained `PocketRootIshWorkspaceHost` and integrated UIKit/SwiftUI
  entry points. A caller-supplied local RootFS and Application Support location
  are enough to prepare, boot, and open Workspace; concurrent boot is
  coalesced, removal closes only the PTY, and explicit shutdown closes every
  host-created workspace first.
- Direct Terminal and Files entry points on `PocketRootIshWorkspaceHost`.
  Screens prepare and boot automatically without consumer-side `readySystem`
  polling. A two-button `Examples/PocketRootQuickStartApp` is final-linked in
  CI and its pinned Debug RootFS is verified. iPhone/iPad UI smoke covers cold
  Files and Terminal auto-boot and previews a real PTY-created file through
  Files; Quick Start and Host App share one bounded Simulator runner.
- An External Consumer acceptance App materialized outside the repository.
  Local runs use the current package path, while PR CI resolves the head's full
  SHA through its public Git URL, bundles the reviewed RootFS as a
  caller-owned resource, and verifies Terminal file creation,
  background/foreground recovery, Files preview, and explicit shutdown.
- Unified iOS 18 deployment baseline.
- Experimental `PocketRootIshRuntime` pinned to IshEmbed release revision `38d25d6f8726145e7e988172f12000020d89a638` and the `v0.4.0-abi.6` XCFramework.
- Experimental `PocketRootIshRuntime` upgraded to IshEmbed release revision
  `37231ab667b380eb86a5fbcf961e31af4d50cebb` and the `v0.4.0-abi.7`
  XCFramework, with public atomic no-replace guest rename through
  `PocketRootSystem.renameItem`.
- Experimental `PocketRootIshRuntime` upgraded to IshEmbed release revision
  `2419f736b271beb52a699b2f780027cf280472b8` and the `v0.4.0-abi.9`
  XCFramework, bounding finite-session stdin write/close under the same SPAWN
  absolute deadline.
- Experimental `PocketRootIshRuntimeIntegration` composing caller-local RootFS installation and native runtime.
- A public `PocketRootIshRuntimeController` and standalone
  `Examples/PocketRootHostApp`, allowing a consumer to share one booted system
  between SwiftTerm PTY and guest Files using only Swift Package APIs. CI
  builds the host and verifies its Debug RootFS while Release remains
  payload-free.
- An iOS 18 Simulator Host App UI smoke covering real SwiftTerm PTY file
  creation and sustained output, background/foreground, rotation resize,
  terminal close/reopen, persistent Files preview, and ordered shutdown.
  Cursor blinking is configurable for deterministic UI automation. The runner
  can select iPhone or iPad device types, CI executes the same complete suite
  on iPhone 16 and iPad (10th generation), and Files deletion uses an alert
  that is stable across size classes. The standalone Host App example exposes
  Documents through system Files, seeds a deterministic file only under the
  explicit UI-test launch argument, and verifies the document-picker import,
  share-sheet save, guest deletion, re-import, and content round trip.
- A development-signed physical Host App UI runner that validates physical
  iOS, the exact Xcode destination, signing, and entitlements before reusing
  the same lifecycle test, with App and diagnostic cleanup by default.
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
- A reproducible maximal Experimental engineering-composition inventory and
  SPDX 2.3 JSON SBOM that distinguishes the default Demo, native-runtime smoke,
  and all Swift products, and binds ABI.9 IshEmbed/XCFramework, iSH, supervisor
  musl source, the external RootFS, and its 15 packages. CI compares generated
  output and validates the SBOM against the pinned official schema. This
  evidence does not scan a final archive; the complete release-artifact SBOM
  and distribution-authorization gates remain closed.
- A deterministic external `.app`/`.xcarchive` artifact scanner. It bounds file
  count/size, rejects symlinks and special files, records per-file digests,
  Mach-O architectures/dependencies/undefined symbols, codesign entitlements,
  and private-framework/private-entitlement/JIT/`MAP_JIT` signals, then
  atomically emits and byte-reverifies an inventory, file-level SPDX 2.3 SBOM,
  and checksums. CI scans the ephemeral unsigned device runtime App, requires
  clean risk signals, and schema-validates the SBOM without uploading the App
  or evidence. Final signed/exported artifacts, their complete SBOM, and
  distribution authorization remain closed.
- A local development-signed engineering `.xcarchive` build/scan gate. It
  handles real archive plists containing `CreationDate`, creates a standard
  installable smoke archive, and verifies development entitlements, signature,
  risk signals, deterministic evidence, and the SPDX schema. The runner never
  installs, exports, or uploads an App; final release signing/export and
  distribution authorization remain closed.
- A checksum-bound `LICENSE-REVIEW-RESULTS.json` and strict validator. All 78
  pinned RootFS license/NOTICE candidates have engineering review results;
  eight source origins retain package-level open items, and legal and
  redistribution gates remain closed.
- A checksum-bound `LICENSE-NOTICE-CANDIDATES.json`, strict validator, and
  outside-repository atomic materializer for the eight remaining RootFS source
  origins. It indexes 13 remote license/attribution payloads, 47 aports files,
  and the 78 existing evidence files for complete re-verification without
  committing payloads or opening engineering, legal, or redistribution gates.
- `LICENSE-NOTICE-REVIEW-RESULTS.json` and a strict external payload-tree
  verifier. All 138 candidate payloads now have checksum-bound engineering
  review. The pinned upstream `alpine-keys` GPL-to-MIT license-decision commit
  is included while its package-level copyright notice remains open. The
  `ca-certificates` generator is byte-identical to curl commit `3fdc4bdb`, and
  that exact revision's curl license is pinned. The pinned Mozilla
  `certdata.txt` reproducibly generates a bundle byte-identical to the RootFS
  installed file, closing the trust-store candidate-material engineering
  item. The pinned BusyBox configuration now binds enabled bzip2 support to
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
  BSD terms, FSF attribution, and GPL declarations. `expand` and `unexpand`
  share `coreutils/expand.c`, while `fold` links `coreutils/fold.c`; both
  sources retain FSF copyright, GPLv2-or-later declarations, and BusyBox port
  attribution. `cut`, `sort`, and `uniq` link their corresponding `coreutils`
  sources, each retaining its GPLv2-or-later declaration and original
  attribution. The remaining BusyBox review applies the 33 pinned aports
  patches and configuration to derive 487 compilation units and a 562-file
  include closure, then pins the 41 files retaining independent third-party
  terms or provenance. BusyBox evidence increases to 60 files and its broad
  engineering item closes. The pinned `alpine-baselayout` aports snapshot and
  netbase 6.4 copyright complete package-origin/notice inspection. The musl
  `COPYRIGHT`, three installed helper license headers, notice-free `ldconfig`
  and generated `ldd`, and three aports patches complete its third-party
  closure review. `alpine-baselayout`, `apk-tools`, `busybox`,
  `ca-certificates`, `musl`, `openssl`, and `pax-utils` have no remaining
  candidate-material engineering items. Only `alpine-keys`, whose upstream
  package lacks an MIT grant and copyright notice, remains open; legal and
  redistribution gates remain closed.
- Strict external download-cache input for the RootFS source-review
  materializer. A cache replaces network transport only: inputs remain
  size-bounded and symlink/overlap-rejected, with pinned SHA-512 and canonical
  extracted-aports-tree verification; v2 receipts distinguish network from
  cache acquisition instead of fabricating a selected URL, and ambiguous
  legacy v1 bundles must be regenerated through cache mode.
- Checksum-bound `CORRESPONDING-SOURCE-REVIEW-RESULTS.json` and a strict
  validator covering all 10 source origins, 130 canonical aports entries, and
  nine upstream distfiles. The external materializer now emits a schema-v3
  receipt and binds `SOURCE-INVENTORY.json`, the review results, the complete
  typed tree, and checksums. Rebuild-environment/toolchain review, legal
  review, source-offer mechanics, delivery approval, and redistribution gates
  remain open.
- Reproducible `REBUILD-ENVIRONMENT-REVIEW.json` and
  `SOURCE-DELIVERY-INVENTORY.json` evidence. It identifies the historical
  v0.3.3 builder and nested iSH while keeping its exact release environment
  and published-archive rebuild unverified; separately, it records a
  schema-v4 successor byte-reproduced across two independent invocations and
  four total builds. A five-unit delivery inventory covers both builders, the
  Alpine input, all ten origins' source material, and modification disclosure,
  while materialization, source-offer, legal, delivery, and redistribution
  gates remain closed.
- A unified external RootFS delivery-candidate materializer and independent
  verifier. It first revalidates the corresponding-source and LICENSE/NOTICE
  candidates, then emits commit-addressed deterministic tar files for the
  historical and successor builders plus initialized submodules from pinned
  Git objects. Shared dependencies are stored once, and case-distinct Linux
  paths cannot collide on the host. It binds the Alpine input,
  corresponding-source candidate, license-review evidence, LICENSE/NOTICE
  candidate, modification disclosure, and compliance evidence, then
  atomically emits a receipt, typed tree, and `SHA256SUMS`. Independent
  verification reruns both lower-level verifiers from the candidate itself.
  It copies neither `.git` nor untracked files, commits no output, and keeps
  source-offer, legal, delivery, redistribution, and `distributionAuthorized`
  gates closed.
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

- Finalized MIT as the top-level license for original PocketRoot source and
  added a bilingual `NOTICE.md` plus an MIT inbound-contribution policy. The
  `v0.1.0` source/Swift Package track is now Ready; Runtime, App, binary, and
  RootFS distribution remain fail-closed, and MIT does not relicense any
  third-party component or artifact.
- Host App iPad file-import UI smoke now scrolls the target file row into the
  List's valid visible frame before tapping or pressing it, avoiding false
  Xcode 16 failures when `isHittable` computes an invalid activation point for
  an offscreen SwiftUI row.
- Host App iPad UI smoke now locates the system share sheet by accessibility
  identifier across element types, avoiding false XCTest failures when iOS 18
  exposes `ActivityListView` through a different automation type.
- Moved the complete Demo, its tests, and its XcodeGen source into the
  self-contained `Examples/PocketRootDemo` tree. Project generation and build
  scripts now use that public example path instead of mixing Demo and package
  sources at the repository root.
- Release-composition generation and the SPDX SBOM now cover the direct
  SwiftTerm pin, its resolved-but-unlinked `swift-argument-parser` dependency,
  the MIT notice, and the Terminal target graph. PTY strictly honors
  `allowsInput=false`; SwiftUI closes and recreates the hosted session when its
  backend/session/terminal configuration changes, while theme-only updates stay
  in place.
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
