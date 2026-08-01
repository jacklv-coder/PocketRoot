# Troubleshooting

[简体中文](../Troubleshooting.md) | [English](Troubleshooting.md) | [Documentation](README.md)

First identify the layer: dependency resolution, project generation, safe Demo, RootFS install, native final link, runtime boot, command execution, or smoke.

## Quick diagnostics

```bash
git status -sb
git remote -v
xcodebuild -version
swift --version
xcrun --sdk iphonesimulator --show-sdk-version
xcodegen version
swift package show-dependencies
```

## XcodeGen missing or project absent

Install with `brew install xcodegen` or run `./Scripts/bootstrap.sh`. Generate
`Examples/PocketRootDemo/PocketRootDemo.xcodeproj` with
`./Scripts/generate-project.sh`. Do not edit `project.pbxproj`;
`Examples/PocketRootDemo/project.yml` is authoritative.

## Dependency resolution

Check network access to the exact package version/commit and parent release
asset, unchanged `Package.resolved`, and the selected Xcode command-line tools.
Run `swift package resolve` and regenerate. Never replace immutable inputs with
branches, moving tags, revisions in a versioned release, or unrecorded binaries.

## IshEmbed unavailable or missing module

Native support requires iOS + arm64 + explicit Experimental products. macOS, x86_64 Simulator, Intel Mac, and the default umbrella do not provide a native guest. `PocketRootIshRuntimeFactory.isAvailable` is useful only after an arm64 target has linked successfully. SwiftPM resolves the binary before application code runs, so an App target selecting the Experimental product must set `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` or be separated from the portable target. Intel Macs cannot build the current native target.

The upstream package has no macOS XCFramework slice despite its manifest declaration; direct upstream macOS native tests can fail. PocketRoot host tests use injected/unsupported drivers.

## Demo reports `RootFS Missing`

The Demo links the Experimental runtime but never downloads a RootFS or reads
one from the repository. Configure the pinned local archive and rebuild:

```bash
./Scripts/inject-demo-rootfs.sh \
  --install-development-archive /absolute/path/to/fs.tar.gz
```

The script rejects symlinks, wrong size/digest, source-tree inputs, and Release
injection. Diagnostics should then show `RootFS Embedded`; after System Boot it
becomes `Installed` and the runtime becomes `Ready`. See the [integration
guide](IntegrationGuide.md) for host-App integration.

## Runtime not booted

Use the exact `prepared.system` returned by composition, call boot successfully, verify ready, then execute. Do not accidentally use `PocketRootSystem.shared`.

The retry boundary depends on where boot failed:

- RootFS preflight, such as a missing directory, symlinked `meta.db`, or an attribute-read failure while checking the files, runs before the process-global slot is claimed. These failures map to typed `rootFSUnavailable` and leave the runtime idle, so after correcting the input or preparing again, boot may be retried in the same host process.
- Once the slot has been claimed and native driver boot has been entered, a failure conservatively terminates the global slot. Booting the same or another system then returns `restartRequired`; restart the host app.
- A duplicate boot while the first call is still in progress is rejected. Await the original call instead of racing multiple systems.

## Already booted or restart required

Centralize one prepared system and lifecycle owner. There is one iSH kernel per process. A boot after the native slot was consumed, or after either real native or injected-driver shutdown returned and marked it terminated, produces `restartRequired`. The current build intentionally cannot implement shutdown then boot; restart the host app.

## RootFS size/hash failure

Expected values are 6,581,376 bytes and `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4`.

```bash
stat -f '%z' /path/to/fs.tar.gz
shasum -a 256 /path/to/fs.tar.gz
```

An incomplete download, wrong release, saved HTML page, cache substitution, or mutation can cause failure. Do not disable verification or change the manifest to accept unknown data.

## RootFS type or layout failure

Inputs and fakefs components must be real files/directories, not symlinks or special files. The archive must contain `fs/meta.db` and `fs/data/`; an Alpine minirootfs is not an iSH fakefs.

A failed candidate intentionally preserves the old installation. Do not manually delete transaction records without understanding the recovery state.

## Invalid timeout or partial timeout output

Timeout must be positive and no longer than 24 hours. Positive sub-millisecond
values become 1 ms. One absolute deadline starts at driver entry; finite
`spawn` receives the remaining duration, and stdin close plus event reads reuse
it. A pre-session deadline expiry returns a timed-out result. An established
session still requires authoritative guest `EXITED` and may return partial
output. Termination confirmation after expiry uses a separate fixed bounded
cleanup window, so timeout is not a promise to return at that exact instant.

## Output limit

Defaults are 8 MiB stdout and 4 MiB stderr. Overflow terminates the session and throws `commandOutputLimitExceeded`. Reduce/filter output or deliberately adjust limits; never make them unbounded.

## One command at a time

The current runtime accepts one one-shot command. Queue requests in the application and wait before shutdown. Interactive multi-session support does not exist.

## Boot is rejected after shutdown

This is the pinned v0.4.0-abi.6 single-lifecycle contract. Shutdown soft-halts,
joins, and returns `.terminated`, but process-global iSH state prevents another
boot in the same host process. Later calls return `restartRequired`; restart
the host process for a new runtime. See
[ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md).

## Smoke cannot find a Simulator

```bash
xcrun simctl list runtimes
xcrun simctl list devices available
```

Install an iOS 18 runtime in Xcode. Use Apple Silicon and optionally set `POCKETROOT_SMOKE_DEVICE` to an existing iOS 18 Simulator UDID. A script-created iPhone 16 Simulator is deleted on successful or failed script exit unless `POCKETROOT_KEEP_SIMULATOR=1`.

For a caller-supplied Simulator, the script boots the device, uninstalls the old smoke App, and installs a new one. On exit it terminates the App but retains the new App, injected archive/report, and resulting boot state. Clean the exact device safely with:

```bash
SMOKE_DEVICE_UDID="paste-exact-udid-here"
xcrun simctl terminate "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke || true
xcrun simctl uninstall "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke
```

Uninstalling also removes the App data container. If the device was shut down before the smoke, run `xcrun simctl shutdown "$SMOKE_DEVICE_UDID"` afterward. Use `simctl delete` only for an exact UDID confirmed as a script-dedicated temporary device, never for a shared development Simulator.

## Physical smoke signing or launch failure

The physical runner requires Xcode to select a valid development profile for `POCKETROOT_DEVELOPMENT_TEAM`; the target must be paired, in Developer Mode, and unlocked. Common failures:

- `POCKETROOT_SMOKE_DEVICE did not resolve`: pass a CoreDevice UUID, hardware
  UDID, or device name recognized by `devicectl`; the runner validates physical
  iOS properties and resolves the hardware UDID required by the Xcode
  destination.
- `No Account for Team`: the selected team has no usable Xcode account/profile. Select the team that can development-sign locally or complete account/signing setup in Xcode.
- `No profiles`: no development profile matches the bundle ID or device.
- `Unable to launch ... Locked`: keep the device unlocked and rerun; successful installation does not permit a foreground launch while locked.
- `Process-suspend smoke did not reach its host checkpoint`: confirm that the
  App did not exit early and inspect the last progress; do not forge the marker.
- `UIKit-lifecycle smoke did not reach its host checkpoint` or
  `UIKit lifecycle App did not report its background callback`: keep the
  device unlocked, confirm Settings can open, and inspect the last progress.
- `UIKit lifecycle activation did not preserve the smoke process PID`: iOS
  terminated or relaunched the App, so the run cannot prove one runtime
  survived the transition and must fail.
- `Forced-relaunch persistence smoke did not reach its host checkpoint`: the
  seed process did not reach the post-write/post-`sync` checkpoint. Inspect
  the last progress and do not forge it.
- `Forced-relaunch seed process did not terminate` or the verification PID
  equals the seed PID: CoreDevice did not prove a cross-process transition.
- `The guest marker did not survive forced App termination`: the RootFS was
  replaced, synced guest data was lost, or fakefs recovery failed. Preserve
  the failure logs; do not bypass the reuse or marker checks.
- `The zero-capacity preflight unexpectedly installed a RootFS`: the bounded
  SPI did not reach production capacity preflight. Do not replace this with
  filling the real device.
- `Storage failure left RootFS entries`: capacity or ENOSPC failure left
  staging, transaction, or installation entries. Preserve the failed container;
  a later successful boot must not hide that residue.
- `Unexpected gzip ENOSPC error`: the fixed one-byte injection did not return
  a space error from the real gzip write path. Inspect the SPI mapping and C
  extractor instead of increasing the write amount.
- `The App delegate did not expose a memory-warning callback`: the smoke target
  lacks the public `applicationDidReceiveMemoryWarning` callback or the active
  delegate is unexpected. Do not replace it with a private selector.
- `The injected memory-warning callback did not persist fresh evidence`: the
  callback did not arrive or stale evidence was read. Verify the independent
  mode and progress reset; do not describe this injection as system pressure.
- `The guest command did not acknowledge active execution before the callback`:
  the guest did not write its fresh start marker within five seconds. The
  callback is not injected in this state; do not replace the acknowledgement
  with a fixed delay.
- `The active guest command did not survive the memory-warning callback`:
  preserve the report and console for runtime-continuity diagnosis; a later
  successful command must not hide this failure.
- `... smoke launch did not return a process identifier`: the current
  Xcode/CoreDevice did not return the supported launch-JSON PID; do not infer
  a PID from human-readable output.
- entitlement validation failure: do not bypass it; verify the application identifier, team identifier, and `get-task-allow`.

On success or failure, the runner uninstalls an installed smoke App and its RootFS by default. `POCKETROOT_KEEP_DEVICE_APP=1` explicitly changes that cleanup behavior.

## Smoke timeout or missing report

Verify the archive, Simulator boot, app install/launch, console output, storage,
and report. Increase only the JSON-report wait with
`POCKETROOT_SMOKE_TIMEOUT_SECONDS=600` when justified; this variable does not
bound project generation, the build, Simulator boot, or the fixed 20-second
post-report runner-cleanup check. Missing reports and crashes are failures.

## Local pass, CI failure

Compare toolchains, SDK, destination architecture, resolved dependencies, XcodeGen, artifact digests, generated project source, and uncommitted local dependencies. CI runs `./Scripts/check-docs.sh` before tests and builds. The `actions/checkout` implementation is pinned to an exact revision, while the repository content is the workflow event SHA (push SHA or PR merge SHA). CI has no local archive, DerivedData, generated project, or credentials.

If Xcode 16 intermittently reports that a UI test runner `is unknown to
FrontBoard`, the shared Simulator UI runner restarts the device and retries
once only when the runner created that temporary device. It does not restart a
shared Simulator supplied by the caller. Only that exact infrastructure signature triggers a retry; do not add
ordinary test failures to the retry condition. If the retry also fails, inspect
both the first and final `xcodebuild` logs.

## Issue report

Provide commit, branch, toolchains, destination/architecture, exact command, typed error/log, runtime state, archive version/size/hash, and a minimal reproduction. Do not upload restricted archives, tokens, signing material, or private data.
