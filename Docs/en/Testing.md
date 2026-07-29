# Testing and Validation

[简体中文](../Testing.md) | [English](Testing.md) | [Documentation](README.md)

PocketRoot separates host logic, real RootFS, iOS build, native final-link, and runtime behavior evidence. No layer substitutes for another.

## Matrix

| Layer | Entry | Proves | Does not prove |
| --- | --- | --- | --- |
| Package tests | `./Scripts/test.sh` | Core, Resources, Terminal, adapter seam, composition | Native runtime execution |
| Real asset test | Filtered test with archive env | Exact release archive validates and materializes once | Existing-installation reuse or iSH boot |
| Demo build | `./Scripts/build.sh` | Experimental runtime, SwiftTerm, and UIKit final-link as an arm64 App; optional pinned RootFS injection into Debug | Guest execution, physical-device behavior, distribution |
| Native final link | `./Scripts/build-runtime-spike.sh` | Full graph forms arm64 executables | Physical or guest behavior |
| Engineering App/archive scan | `ruby Scripts/scan-release-artifact.rb` | Deterministic external `.app`/`.xcarchive` file hashes, Mach-O, signature/entitlement risk signals, and file-level SPDX | Final exported artifact, dependency-license completeness, or distribution authorization |
| Development-signed archive gate | `./Scripts/build-signed-engineering-archive.sh` | Standard `.xcarchive`, development entitlements, clean risk signals, deterministic re-verification, and SPDX schema validation | IPA export, release signing, installation, upload, or distribution authorization |
| Simulator native smoke | `./Scripts/run-runtime-smoke.sh` | Prepare, boot, command bounds, returning soft shutdown | Other toolchains, physical devices, distribution |
| Host App UI smoke | `./Scripts/run-host-app-ui-smoke.sh` | Public-host boot, SwiftTerm PTY, lifecycle, Workspace session persistence, Files create/delete/preview, and ordered shutdown on an iOS 18 Simulator | Physical keyboards, iPad, distribution |
| Physical Host App UI smoke | `./Scripts/run-host-app-device-ui-smoke.sh` | The same lifecycle UI test on a development-signed iPhone/iPad, including signature and development entitlements | iPad, real pressure, distribution |
| Physical native smoke | `./Scripts/run-runtime-device-smoke.sh` | Same 17 checks with optional process suspend/resume, UIKit lifecycle, forced-relaunch persistence, bounded storage-failure recovery, or bounded memory-warning recovery; development entitlements and returning soft shutdown | Real storage/memory pressure, power cut, jetsam, iPad, distribution |
| Documentation | `./Scripts/check-docs.sh` | Pairs, Chinese coverage, relative links | Implementation correctness |

## Package tests

```bash
./Scripts/test.sh
```

Coverage includes the following relevant boundaries:

- Core tests cover request/configuration defaults, result-stream decoding, placeholder lifecycle behavior, injected-runtime delegation, public-state refresh after fail-closed execute and failed shutdown, rejection of transient-state publication by a reentrant command, rejection of stale refresh overwrite after a newer failure, plus RootFS-provider/metadata coordination.
- Resources tests cover the pinned manifest and gated bundled provider; archive existence, symlink rejection, byte count, and SHA-256; required fakefs layout and metadata-symlink rejection; successful gzip/ustar extraction, traversal cleanup, explicit-directory-after-implicit-parent rejection, duplicate-directory and case-aliased-directory rejection on insensitive volumes, archive symlink entry/source rejection, and the expanded-byte limit.
- Synthetic Resources fixtures cover first install and reuse, private
  archive-snapshot isolation and byte bounds, pre-staging insufficient-capacity
  rejection, rejection of a missing installation base, preservation of mode
  `000` candidate entries across persistence, cleanup of a permission-restricted
  backup/transaction during same-version replacement, exact-budget acceptance,
  wider custom-extractor budgeting,
  and low-space upgrade preservation. ENOSPC injection across snapshot,
  partial gzip output, tar payload, installation record, promotion journal,
  `current.json`, and both destructive promotion checkpoints verifies partial
  gzip cleanup, staging/transaction removal, prior-install preservation, and
  current-record rollback. I/O failures at the candidate tree, journal
  file/directory, both promotion renames, and current-record file/directory
  verify all seven persistence barriers. Journal-only, backup, and
  candidate/final power-loss cut-point states verify inferred rollback or
  commit. Fixtures also cover reserved versions,
  corrupt replacement, failed upgrade/promotion rollback, interrupted
  transaction recovery, and a single installation under concurrent
  preparation.
- Injected runtime tests cover configuration and host availability, fakefs
  preflight, boot/command mapping, identity gates, timeout and C-string
  validation, ownership and concurrent admission, active-command shutdown,
  Swift output-limit and native byte/frame backlog error mapping, typed recoverable supervisor rejection,
  valid guest exit 17, rejection of negative `EXITED`, unconfirmed-exit
  fail-close, terminal spawn errors, active-command cancellation with recovery,
  cancellation-cleanup fail-close, queued cancellation before native entry,
  and terminated/`restartRequired`.
- Agent tests cover direct final text, response/call ID continuation, structured unknown-tool and ordinary-tool failures, repeated response/call IDs, whole-batch validation before side effects, turn/call/input/model/identifier/name/argument/output limits, rejection of concurrent runs and unfinishable last-turn tools, plus configuration, name, and object-schema validation. OpenAI transport tests cover initial and continuation request mapping, text/function-call/refusal/incomplete/malformed response decoding, strict schema preflight, HTTPS and body limits, credential sanitization, and non-2xx errors without token exposure.
- Agent runtime-tool tests cover the strict command schema, unknown-field rejection, policy and approval no-side-effect paths, normalized final approval requests, whole-batch tool-specific preflight, command/cwd/environment/timeout/output bounds, UTF-8/Base64 result encoding and truncation, plus cancellation after non-cooperative approval and execution.
- Integration and Terminal tests cover preparation/configuration alignment,
  PTY creation/events/input/resize/signal/EOF/termination and close-before-
  shutdown, NUL-framed file browsing and preview bounds, plus fallback
  command-terminal cwd/marker/input and theme/transcript behavior.

The real release-asset test skips when `POCKETROOT_ROOTFS_ARCHIVE` is unset. Reuse, replacement, rollback, and concurrency are covered by synthetic fixtures.

For concurrency-sensitive work:

```bash
swift build \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors
```

## Real asset

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment
```

This requires the exact size and SHA-256, validates the extracted fakefs, and asserts a first materialization in a fresh temporary install directory. It does not perform a second preparation or prove reuse; `testRootFSInstallerInstallsThenReusesVerifiedVersion` covers that path with a synthetic fixture. The library never downloads the input.

## Demo and native links

```bash
./Scripts/bootstrap.sh
./Scripts/build.sh
./Scripts/build-runtime-spike.sh
```

The Demo build final-links the Experimental runtime, SwiftTerm, and UIKit as an
arm64 App. With the pinned RootFS configured, its Debug build phase also
validates and injects the archive; without it, the App still builds and reports
`RootFS Missing`. The runtime spike separately final-links the full graph for
arm64 generic Simulator and unsigned generic device. None of these builds proves
guest execution, signed hardware behavior, or distribution readiness.

## Native smoke

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh
```

Requirements: Apple Silicon, iOS 18 Simulator, XcodeGen, and the exact v0.3.3
archive. The archive may be the first argument.
`POCKETROOT_ROOTFS_CANDIDATE` instead selects the complete repository-external
directory produced by `ish-arm64-pkg`'s candidate command. Candidate mode
requires `distributionAuthorized=false`, two byte-identical builds, a fixed
source revision, receipt, identity, and matching companion digests. Its
ephemeral sidecar affects only the repository-owned smoke App; public defaults
and the formal `.ishEmbedV0_3_3` manifest remain unchanged. Bounded PAX control
headers are discarded before guest path validation; every real following entry
still passes traversal, duplicate, link, and materialization checks.
`POCKETROOT_SMOKE_DEVICE` selects an existing device.
`POCKETROOT_SMOKE_TIMEOUT_SECONDS` changes only the default 300-second JSON
report wait after App launch. It does not bound project generation, the build,
Simulator boot, or the fixed 20-second post-report runner-cleanup check. A
script-created Simulator is deleted on script exit unless
`POCKETROOT_KEEP_SIMULATOR=1`. A caller-supplied Simulator is booted, has the
old smoke App uninstalled before the new one is installed, and retains the new
App, injected data, and resulting boot state after the script terminates it.

When creating a device, the runner locates the stable
`com.apple.CoreSimulator.SimRuntime.iOS-18-*` identifier anywhere on the
matching `simctl list runtimes available` line instead of relying on its field
position. Fixture regression tests cover standard output, an `(available)`
suffix, multiple runtimes, and no match.

To safely remove the smoke App and its data from a caller-supplied device, use
the exact UDID:

```bash
SMOKE_DEVICE_UDID="paste-exact-udid-here"
xcrun simctl terminate "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke || true
xcrun simctl uninstall "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke
```

If the device was shut down before the smoke, restore that state with
`xcrun simctl shutdown "$SMOKE_DEVICE_UDID"`. Run `simctl delete` only for an exact
UDID confirmed to be a script-dedicated temporary device, never for a shared
development Simulator.

The 17 checks cover preparation, ready boot, aarch64, Alpine 3.19.1, cwd,
environment, split streams and exit 7, merged stderr, byte-exact 8 MiB binary
stdout beyond the 4 MiB native backlog, 100 ms timeout and recovery, an 8 MiB
stdout limit with another 64 KiB attempted, a 64-byte stderr limit, recovery
after both limit paths, blocked-command cancellation and post-cancellation
recovery, soft shutdown returning `.terminated`, and a 256 MiB `ru_maxrss`
limit over the complete smoke lifecycle before the App exits successfully.

With `POCKETROOT_SMOKE_LIFECYCLE=1` on a physical device, an eighteenth check
waits while the runtime is `.ready`. The host suspends the App process by its
launch PID for three seconds, resumes it, and writes a one-use continuation
marker. The App must execute a new guest command, remain `.ready`, and then
complete the same shutdown and peak-memory gates. This is process-level
suspend/resume evidence, not UIKit foreground/background callback evidence.

With the mutually exclusive `POCKETROOT_SMOKE_UI_LIFECYCLE=1`, the eighteenth
check covers real UIKit lifecycle delivery. The host opens Settings, waits for
`applicationDidEnterBackground`, activates the original PID, and requires
ordered `applicationWillEnterForeground` and `applicationDidBecomeActive`
callbacks, followed by a new guest command, `.ready`, shutdown, and peak memory.

With the mutually exclusive `POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1`, the
eighteenth check covers forced-relaunch persistence. The first process writes
and syncs a fixed guest marker, then the host sends SIGKILL only after a fresh
checkpoint. A second launch must return a different PID, report reuse of the
existing RootFS, recover and remove the marker, and complete the standard
command, shutdown, and peak-memory gates. The host clears report and progress
again before verification so stale evidence cannot pass.

With the mutually exclusive `POCKETROOT_SMOKE_STORAGE_FAILURE=1`, two checks
are added for a total of 19. The first fixes installer capacity at zero and
requires typed `insufficientStorage` before staging. The second uses the real
snapshot/gzip path but injects ENOSPC after one gzip-output byte. `rootfs/`
must be empty after each failure before the same directory completes a normal
install, boot, and the standard 17 checks. This bounded injection does not fill
the device and is not real storage pressure or a physical power cut.

With the mutually exclusive `POCKETROOT_SMOKE_MEMORY_WARNING=1`, an eighteenth
check deterministically invokes the public
`UIApplicationDelegate.applicationDidReceiveMemoryWarning(_:)` callback while
one guest command is active. Fresh callback evidence, the full active-command
output, a later command, `.ready`, shutdown, and peak memory must all pass.
This repository-owned injection does not create real memory pressure and does
not prove system low-memory delivery, jetsam, or relaunch recovery.

The sustained-output check proves that Swift can continuously consume binary
output without truncation or corruption merely because it exceeds the 4 MiB
native backlog. The lifecycle high-water check covers RootFS preparation,
8 MiB output, overflow recovery, cancellation, and shutdown on Simulator; it
is not physical-device jetsam evidence. The 100 ms check runs through ABI.6
finite SPAWN and proves recovery after the unified deadline expires and the
session reports authoritative `EXITED`. Upstream deterministic lifecycle tests
separately cover instance/spawn/control-gate expiry and bounded
close/terminate under a stalled writer. The [Roadmap](Roadmap.md)
tracks that native control-path gate.

Success is written only after shutdown returns `.terminated` and another
command produces `restartRequired`. The host then explicitly stops the idle
smoke App and waits for the console client. A pre-success crash cannot produce
a passing report. The script serves as a repository-owned local gate and is
also invoked by the dedicated minimum-toolchain GitHub Actions job.

On 2026-07-24, `v0.4.0-abi.6` with wrapper revision `38d25d6` passed all 17
checks on an iOS 18.2 arm64 Simulator with byte-exact 8 MiB binary stdout and
a 156.5 MiB lifecycle peak
against the 256 MiB limit; shutdown recorded `returned, terminated, restart required`.

On 2026-07-25, the local unapproved candidate built from
`ish-arm64-pkg` revision `9375e0ecc9cf1bbe79b05ef0b45cab8405f1d08c`
(`eaa5dd15a6c983c0ac2ce9034060d15692c2cde811461bf9c17f8858c040bb91`,
6,513,566 bytes) passed the candidate-aware 18-check path on an iOS 18.2 arm64
Simulator. It installed as `candidate-9375e0ecc9cf`, reported Alpine 3.19.1 and
aarch64, completed all command/recovery/shutdown checks, and peaked at
146.6 MiB. The candidate stayed outside the repository and was not uploaded.

The repository's minimum-toolchain job explicitly selects Xcode 16.0 and the
iOS 18.0 SDK on an arm64 macOS runner, materializes the pinned RootFS,
final-links arm64 Simulator and unsigned-device Apps, and runs the same
17-check native smoke on an iOS 18.0 Simulator.

### Development-signed engineering archive

Provide a new external output directory, an Apple team ID, and the downloaded
pinned official SPDX 2.3 schema:

```bash
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SIGNED_ARCHIVE_OUTPUT=/absolute/new/archive-scan \
POCKETROOT_SPDX_SCHEMA=/absolute/spdx-2.3-schema.json \
  ./Scripts/build-signed-engineering-archive.sh
```

The runner creates a standard `PocketRootIshRuntimeSmoke.xcarchive`, requires a
valid development signature, requires every Mach-O entry to be `signed-valid`,
and requires `get-task-allow=true`. It then materializes and
re-verifies file/Mach-O/entitlement/risk evidence, and validates the file-level
SPDX document. Before building, it runs `npm ci --ignore-scripts` from the
pinned lockfile and requires the schema SHA-256 to match the same official SPDX
2.3 schema pinned by CI. The successful output retains only the archive and
`evidence`; temporary DerivedData is removed. An optional
`POCKETROOT_CLONED_SOURCE_PACKAGES_DIR` must identify an existing real external
directory.

The command never invokes `devicectl`, installs an App, calls
`-exportArchive`, or uploads output. It proves that a development-signed
engineering archive can be built and scanned, not final release signing, IPA
export, a complete release-artifact SBOM, App Review, or distribution
authorization.

### Signed iPhone/iPad runner

Use an explicit physical-device reference and team identifier:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

Add physical process suspend/resume to the same gate with:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_LIFECYCLE=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

Use a separate mode for real UIKit background/foreground callbacks:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_UI_LIFECYCLE=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

Use a separate mode for RootFS and guest-data recovery after forced termination:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

Use a separate mode for bounded capacity/ENOSPC cleanup recovery:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_STORAGE_FAILURE=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

Use a separate mode for bounded memory-warning callback recovery:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
POCKETROOT_SMOKE_MEMORY_WARNING=1 \
  ./Scripts/run-runtime-device-smoke.sh
```

The reference may be any CoreDevice UUID, hardware UDID, or device name
accepted by `devicectl`. The runner validates a physical iOS device through
the supported JSON output and resolves its hardware UDID before `xcodebuild`
and later `devicectl` operations. The paired device must have Developer Mode
enabled and support development provisioning. The runner verifies the
application identifier and `get-task-allow`, installs the App, copies the
pinned archive into its data container, and retrieves the JSON report. Standard,
bounded storage-failure, and bounded memory-warning modes use an attached
launch. The mutually
exclusive host-control modes use the launch-JSON PID for suspend/resume, open
Settings and reactivate the same PID for UIKit callbacks, or terminate a seed
PID and require a different verification PID. The runner terminates the
process and uninstalls the App and
RootFS data by default; `POCKETROOT_KEEP_DEVICE_APP=1` retains it.

### Physical Host App UI runner

Run the same Host App lifecycle UI test on one explicitly selected signed
device:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-host-app-device-ui-smoke.sh
```

The runner validates a physical iOS destination, requires the device OS not to
exceed the installed iOS SDK, checks the development-signing team, application
identifier, and `get-task-allow`, then executes boot, sustained PTY
input/output, background/foreground, rotation resize, terminal close/reopen,
persistent Files preview, and ordered shutdown. It uninstalls the Host App and
UI test runner and removes temporary DerivedData by default.
`POCKETROOT_KEEP_DEVICE_APP=1` retains only the Host App;
`POCKETROOT_KEEP_SMOKE_ARTIFACTS=1` retains only the local
diagnostic directory.

Use the development certificate subject's `OU` as the team ID, not the
personal identifier shown in parentheses in the certificate display name. A
newer device OS than Xcode's device-support range fails before build; a
successful signature or install is not reported as a passed XCTest lifecycle.

The 2026-07-24 rerun used Xcode 26.1.1, a development-provisioned iPhone 17 Pro
on iOS 26.1, and the v0.4.0-abi.6 runtime pin. The device-produced
`success: true` report passed all 17 checks: 8 MiB binary stdout was byte-exact,
timeout/output-limit/cancellation recovery succeeded, soft shutdown recorded
`returned, terminated, restart required`, and lifecycle peak memory was
84.6 MiB against the 256 MiB gate. No device identifier, profile, or local
report is committed. This closes the current signed-iPhone
one-shot/soft-shutdown/peak-memory smoke baseline, not iPad,
foreground/background, physical jetsam, storage pressure, or forced-power-cut
gates.

On the same date, “Jack iPhone” (iPhone 14 Pro / iOS 26.6) passed both the
standard 17-check path and the 18-check process-suspend/resume path. After a
three-second suspension the runtime remained `.ready` and a new guest command
passed. Lifecycle-mode peak memory was 89.7 MiB and standard-mode peak memory
was 89.8 MiB. This proves process suspend/resume recovery, not UIKit
foreground/background callbacks, jetsam, or sustained background execution.

The same Jack iPhone then passed the real UIKit 18-check path: Settings caused
the background callback, reactivation preserved the original PID, ordered
foreground/active callbacks arrived, the new guest command passed, and peak
memory was 89.4 MiB. After the shared-runner refactor, the standard 17-check
and process-suspend 18-check paths also regressed green at 82.7 MiB each.
These results do not prove jetsam, memory-warning, sustained background, or iPad.

On 2026-07-25, the same Jack iPhone passed the 18-check forced-relaunch
persistence path. After the seed process wrote and synced the guest marker,
the host sent SIGKILL to that PID. A different verification PID reported RootFS
reuse, recovered and removed the marker, and completed all standard commands
and soft shutdown at a 51.8 MiB peak. The same shared-runner regression passed
the standard 17-check, process-suspend 18-check, and UIKit 18-check paths at
90.2, 89.9, and 87.1 MiB. This proves synced guest-data recovery across forced
App termination, not jetsam, storage pressure, physical power cut, or iPad.

On the same date, the same Jack iPhone passed the 19-check bounded
storage-failure path. Capacity preflight rejected zero available bytes before
staging, gzip returned ENOSPC after one output byte, and `rootfs/` was empty
after both failures. The same directory then installed normally, booted, and
completed all standard commands and soft shutdown at a 91.2 MiB peak. This
proves bounded capacity/ENOSPC cleanup recovery through the production
installer and extractor in a physical App container, not near-full-device
storage pressure, a physical power cut, or iPad.

On the same date, the same Jack iPhone passed the 18-check bounded
memory-warning path. The guest first wrote a fresh start acknowledgement, then
the public App-delegate callback was deterministically invoked while that
command was active; fresh callback evidence, the
active command, a later command, `.ready`, soft shutdown, and the 256 MiB peak
gate all passed at a 90.8 MiB peak; the same default 17-check regression also
passed at 89.9 MiB. This proves runtime continuity under the repository
callback injection, not real memory pressure, system low-memory delivery, or
jetsam.

The same Jack iPhone also passed the candidate-aware standard path for the
unapproved `9375e0e` RootFS above. The device report bound the exact candidate
SHA-256, observed aarch64 and Alpine 3.19.1, passed command/recovery/shutdown,
and peaked at 76.9 MiB. The runner then uninstalled the smoke App and injected
RootFS. This is compatibility evidence only; it does not authorize RootFS
distribution or change the pinned production manifest.

## CI

The standard GitHub Actions job pins the `actions/checkout` action implementation to an exact
revision; that action still checks out the commit SHA selected by the workflow
event (the push SHA or PR merge SHA). On a macOS runner CI then runs
`./Scripts/check-docs.sh`, reports toolchains, runs package tests, downloads and
independently verifies the exact RootFS, runs its first-materialization test,
regenerates the RootFS and maximal Experimental engineering-composition
evidence, validates both SBOMs against the pinned official SPDX 2.3 schema,
obtains pinned XcodeGen with checksum validation, generates the project, builds
the Demo, and final-links arm64 Simulator and unsigned-device runtime Apps. It
then materializes and byte-reverifies the unsigned device App's
file/Mach-O/entitlement inventory and file-level SPDX 2.3 SBOM, requires no
private-framework, private-entitlement, JIT-entitlement, `MAP_JIT`, or invalid
signature signal, and validates the generated SBOM with the same schema. It
uploads neither the App nor scan evidence.

The minimum-toolchain job explicitly selects Xcode 16.0 / iOS 18.0 SDK,
validates real RootFS installation, installs the iOS 18.0 Simulator runtime,
final-links Simulator/device Apps, runs the 17-check native smoke, and executes
the Host App PTY-input/Files-create-delete-preview UI closure. This Simulator
evidence does not prove signed-device or distribution readiness.

## Minimum checks by change

| Change | Required |
| --- | --- |
| Core API/actor | Package tests + strict build |
| RootFS code/manifest | Package + real asset + final links + native smoke |
| Runtime lifecycle/driver | Package + strict build + final links + native smoke |
| Agent loop/model/tool contract | Package tests + strict build + docs |
| Package/native dependency | Package + Demo + both final links + smoke |
| project.yml/Demo | Regenerate + Demo build |
| smoke | Shell syntax + Simulator smoke + signed-device smoke when available |
| terminal/files UI | Terminal tests + strict iOS build + Host App UI smoke |
| docs | Documentation check |
| release composition/compliance evidence | Generator tests + `--check` + pinned SPDX schema validation |
| artifact scanner or CI scan gate | Ruby fixture security/drift tests + real unsigned-device App materialize/verify + pinned SPDX schema validation |
| signed archive runner/project archive settings | Script-contract test + local development-signed `.xcarchive` materialize/verify + pinned SPDX schema validation |
| upstream/RootFS update | Full suite + supply-chain/compliance reaudit |

## Evidence language

State the exact environment. Jack iPhone may be described as passing the
18-check forced-relaunch persistence smoke. The recorded iPhone and
minimum-Xcode baselines do not imply iPad support, physical jetsam or power-cut
coverage, complete physical-device lifecycle, TestFlight readiness, or App
Store approval.

See the [roadmap](Roadmap.md) for open gates.
