# Testing and Validation

[简体中文](../Testing.md) | [English](Testing.md) | [Documentation](README.md)

PocketRoot separates host logic, real RootFS, iOS build, native final-link, and runtime behavior evidence. No layer substitutes for another.

## Matrix

| Layer | Entry | Proves | Does not prove |
| --- | --- | --- | --- |
| Package tests | `./Scripts/test.sh` | Core, Resources, Terminal, adapter seam, composition | Native runtime execution |
| Real asset test | Filtered test with archive env | Exact release archive validates and materializes once | Existing-installation reuse or iSH boot |
| Demo build | `./Scripts/build.sh` | Umbrella and UIKit build | Experimental graph |
| Native final link | `./Scripts/build-runtime-spike.sh` | Full graph forms arm64 executables | Physical or guest behavior |
| Simulator native smoke | `./Scripts/run-runtime-smoke.sh` | Prepare, boot, command bounds, returning soft shutdown | Other toolchains, physical devices, distribution |
| Physical native smoke | `./Scripts/run-runtime-device-smoke.sh` | Same 17 checks, optional process suspend/resume or UIKit lifecycle, development entitlements, returning soft shutdown | Jetsam, iPad, distribution |
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
- Integration and Terminal tests cover preparation/configuration alignment and the placeholder terminal configuration, theme, transcript, and clear behavior.

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

The Demo build checks the safe umbrella. The runtime spike final-links the full graph for arm64 generic Simulator and unsigned generic device. A device destination link is not signed hardware execution.

## Native smoke

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh
```

Requirements: Apple Silicon, iOS 18 Simulator, XcodeGen, and the exact v0.3.3
archive. The archive may be the first argument.
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

The repository's minimum-toolchain job explicitly selects Xcode 16.0 and the
iOS 18.0 SDK on an arm64 macOS runner, materializes the pinned RootFS,
final-links arm64 Simulator and unsigned-device Apps, and runs the same
17-check native smoke on an iOS 18.0 Simulator.

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

The reference may be any CoreDevice UUID, hardware UDID, or device name
accepted by `devicectl`. The runner validates a physical iOS device through
the supported JSON output and resolves its hardware UDID before `xcodebuild`
and later `devicectl` operations. The paired device must have Developer Mode
enabled and support development provisioning. The runner verifies the
application identifier and `get-task-allow`, installs the App, copies the
pinned archive into its data container, and retrieves the JSON report. Standard
mode uses an attached launch. The mutually exclusive host-control modes use
the launch-JSON PID for suspend/resume, open Settings and reactivate the same
PID for UIKit callbacks, or terminate a seed PID and require a different
verification PID. The runner terminates the process and uninstalls the App and
RootFS data by default; `POCKETROOT_KEEP_DEVICE_APP=1` retains it.

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

## CI

The standard GitHub Actions job pins the `actions/checkout` action implementation to an exact
revision; that action still checks out the commit SHA selected by the workflow
event (the push SHA or PR merge SHA). On a macOS runner CI then runs
`./Scripts/check-docs.sh`, reports toolchains, runs package tests, downloads and
independently verifies the exact RootFS, runs its first-materialization test,
obtains pinned XcodeGen with checksum validation, generates the project, builds
the Demo, and final-links arm64 Simulator and unsigned-device runtime Apps.

The minimum-toolchain job explicitly selects Xcode 16.0 / iOS 18.0 SDK,
validates real RootFS installation, installs the iOS 18.0 Simulator runtime,
final-links Simulator/device Apps, and runs the 17-check native smoke. This
Simulator evidence does not prove signed-device or distribution readiness.

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
| docs | Documentation check |
| upstream/RootFS update | Full suite + supply-chain/compliance reaudit |

## Evidence language

State the exact environment. Jack iPhone may be described as passing the
18-check forced-relaunch persistence smoke. The recorded iPhone and
minimum-Xcode baselines do not imply iPad support, physical jetsam or power-cut
coverage, complete physical-device lifecycle, TestFlight readiness, or App
Store approval.

See the [roadmap](Roadmap.md) for open gates.
