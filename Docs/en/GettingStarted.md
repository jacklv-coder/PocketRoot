# Getting Started

[简体中文](../GettingStarted.md) | [English](GettingStarted.md) | [Documentation](README.md)

This guide covers checkout, dependency resolution, tests, Demo builds, and Experimental runtime final links. A reviewed local RootFS is required only for native runtime execution.

## 1. Prerequisites

- Xcode 16.0+ with the iOS 18 SDK
- Swift 5.10+
- macOS development host
- XcodeGen
- Homebrew, because `bootstrap.sh` installs XcodeGen when it is missing

```bash
xcode-select -p
xcodebuild -version
swift --version
xcrun --sdk iphonesimulator --show-sdk-version
```

The native IshEmbed binary has arm64 iOS device and arm64 Simulator slices only. It does not run in macOS or an x86_64 Simulator process. An App target that selects the Experimental product must exclude x86_64 before package linking; a runtime `isAvailable` check cannot repair a missing binary slice.

## 2. Checkout

```bash
git clone git@github.com:jacklv-coder/PocketRoot.git
cd PocketRoot
git status -sb
git remote -v
```

The repository Git remote uses SSH.

## 3. Bootstrap

```bash
./Scripts/bootstrap.sh
```

The script installs XcodeGen through Homebrew when required, runs `swift package resolve`, and generates `PocketRootDemo.xcodeproj` from `project.yml`.

To regenerate only:

```bash
./Scripts/generate-project.sh
```

Do not edit `project.pbxproj` manually. The generated project is ignored; `project.yml` is the source of truth.

## 4. Basic validation

```bash
./Scripts/test.sh
./Scripts/build.sh
open PocketRootDemo.xcodeproj
```

`test.sh` runs host Swift Package tests. The real release-asset test skips unless `POCKETROOT_ROOTFS_ARCHIVE` is set; synthetic fixtures still cover installer reuse and related paths. `build.sh` final-links the arm64 Demo; without a configured RootFS it does not boot a guest.

## 5. Run the real Demo

The UIKit Demo contains System, Terminal, Commands, and Diagnostics tabs:

- System verifies and installs the fixed RootFS, then boots, checks, or shuts
  down the Experimental runtime.
- Terminal presents the persistent SwiftTerm PTY and a Files entry for `/root`.
- Commands executes bounded one-shot commands against the same booted system.
- Diagnostics reports live RootFS, iSH Runtime, and SwiftTerm status.

Configure a reviewed archive matching the built-in v0.3.3 manifest outside the
repository:

```bash
./Scripts/inject-demo-rootfs.sh \
  --install-development-archive /absolute/path/to/fs.tar.gz
```

The command requires a regular non-symlink, the exact 6,581,376-byte size, and
the pinned SHA-256, then atomically copies it under
`~/Library/Application Support/PocketRootDevelopment/RootFS/`. Rebuild and tap
**Prepare and Boot Runtime** in System. At `Ready`, Terminal supports `ls`,
`cd`, and file creation, while Files browses and previews guest files.

For a single command-line build, pass the input directly:

```bash
POCKETROOT_DEMO_ROOTFS_ARCHIVE=/absolute/path/to/fs.tar.gz \
  ./Scripts/build.sh
```

Without a RootFS the Demo still compiles, reports `RootFS Missing`, and
disables Boot. Injection is Debug-only; Release, TestFlight, and App Store
distribution remain compliance-blocked. See the [integration
guide](IntegrationGuide.md) for host-App integration.

## 6. Final-link the native graph

```bash
./Scripts/build-runtime-spike.sh
```

This regenerates the project and final-links the complete Experimental graph for arm64 generic Simulator and unsigned generic device destinations. A successful link is not physical-device execution evidence.

## 7. Optional real-asset and native smoke

After obtaining and independently validating the pinned archive as described in [RootFS security](RootFS.md):

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment

POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
  ./Scripts/run-runtime-smoke.sh
```

The filtered test uses a fresh temporary directory and verifies the real
release asset's size, digest, extracted layout, and first materialization. It
does not perform a second preparation and therefore does not by itself prove
reuse; see [testing](Testing.md#real-asset).

To exercise a repository-external local double-build candidate from
`ish-arm64-pkg`, do not change the built-in manifest or copy the archive into
this repository. Pass the complete directory produced by
`scripts/prepare-rootfs-candidate.sh --output`:

```bash
POCKETROOT_ROOTFS_CANDIDATE=/absolute/path/to/local-candidate \
  ./Scripts/run-runtime-smoke.sh
```

The runner verifies the candidate JSON, receipt, identity, every companion
digest, the exact archive path, and `distributionAuthorized=false` before
creating an ephemeral smoke-only manifest. This path does not download,
bundle, upload, or authorize RootFS distribution, and it does not update the
formal `.ishEmbedV0_3_3` manifest.

The smoke requires Apple Silicon, an iOS 18 Simulator runtime, and the exact
v0.3.3 archive. It may also receive the archive as its first argument.
`POCKETROOT_SMOKE_DEVICE` selects an existing Simulator.
`POCKETROOT_SMOKE_TIMEOUT_SECONDS` changes only the default 300-second
JSON-report wait after App launch, not the
project generation, build, Simulator boot, or the fixed 20-second post-report
runner-cleanup check. A script-created device is deleted on script exit unless
`POCKETROOT_KEEP_SIMULATOR=1`; a caller-supplied device is booted, has the old
smoke App replaced, and retains the new App, injected data, and resulting boot
state.

Remove the smoke App and its injected data from a caller-supplied device with
the exact UDID:

```bash
SMOKE_DEVICE_UDID="paste-exact-udid-here"
xcrun simctl uninstall "$SMOKE_DEVICE_UDID" com.jacklv.PocketRootIshRuntimeSmoke
```

If it was shut down before the smoke, restore that state with
`xcrun simctl shutdown "$SMOKE_DEVICE_UDID"`. Do not run `simctl delete` against a
shared Simulator; see [testing](Testing.md#native-smoke) for the complete
cleanup boundary.

See [testing](Testing.md) for coverage.

Run the same checks on a paired iOS 18+ device with Developer Mode and development provisioning:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

For a local candidate, replace `POCKETROOT_ROOTFS_ARCHIVE` with the same
complete-directory input:

```bash
POCKETROOT_ROOTFS_CANDIDATE=/absolute/path/to/local-candidate \
POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

`POCKETROOT_SMOKE_DEVICE` may be any CoreDevice UUID, hardware UDID, or device
name accepted by `devicectl`. The runner validates that it resolves to a
physical iOS device and passes the resolved hardware UDID to `xcodebuild`.
It uninstalls the smoke App and injected RootFS after retrieving the report
unless `POCKETROOT_KEEP_DEVICE_APP=1` is set. Never commit a device identifier,
provisioning profile, or local report.

Add `POCKETROOT_SMOKE_LIFECYCLE=1` to verify physical process suspend/resume.
The runner suspends the PID for three seconds while the runtime is `.ready`,
resumes it, and requires a new guest command to succeed. This is not a UIKit
foreground/background callback test.

Use the mutually exclusive `POCKETROOT_SMOKE_UI_LIFECYCLE=1` mode for real
UIKit callbacks. The runner opens Settings to background the App, activates
the original process, and requires background, foreground, active, and a new
guest command to succeed.

Use the mutually exclusive `POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1` mode to
verify RootFS and guest-data recovery after forced termination. The runner
syncs a guest marker, terminates the first App PID, starts a new PID, and
requires it to reuse the RootFS, recover and remove the marker, and complete
the standard command, shutdown, and peak-memory gates.

Use the mutually exclusive `POCKETROOT_SMOKE_STORAGE_FAILURE=1` mode to verify
storage-failure recovery without filling the whole device. The App fixes
available capacity at zero, then injects ENOSPC after one gzip-output byte.
Both failures must leave no staging/transaction residue before a normal
install, boot, and standard smoke recover in the same directory.

Use the mutually exclusive `POCKETROOT_SMOKE_MEMORY_WARNING=1` mode for
bounded recovery when the public `UIApplicationDelegate` memory-warning
callback arrives. The repository smoke deterministically invokes that callback
while one guest command is active, then requires fresh callback evidence, the
active command, a later command, and `.ready` to survive. It does not create
real memory pressure and is not jetsam evidence.

## 8. Command reference

| Goal | Command |
| --- | --- |
| Resolve and generate | `./Scripts/bootstrap.sh` |
| Generate only | `./Scripts/generate-project.sh` |
| Package tests | `./Scripts/test.sh` |
| Default Demo build | `./Scripts/build.sh` |
| Experimental final links | `./Scripts/build-runtime-spike.sh` |
| Real RootFS first-materialization test | `POCKETROOT_ROOTFS_ARCHIVE=... swift test --filter testPinnedReleaseArchiveWhenProvidedByEnvironment` |
| Native smoke | `POCKETROOT_ROOTFS_ARCHIVE=... ./Scripts/run-runtime-smoke.sh` |
| Development-signed archive scan | `POCKETROOT_DEVELOPMENT_TEAM=... POCKETROOT_SIGNED_ARCHIVE_OUTPUT=/absolute/new/output POCKETROOT_SPDX_SCHEMA=/absolute/schema.json ./Scripts/build-signed-engineering-archive.sh` |
| Signed physical native smoke | `POCKETROOT_ROOTFS_ARCHIVE=... POCKETROOT_SMOKE_DEVICE=... POCKETROOT_DEVELOPMENT_TEAM=... ./Scripts/run-runtime-device-smoke.sh` |
| Signed process suspend/resume smoke | Add `POCKETROOT_SMOKE_LIFECYCLE=1` to the signed physical smoke command |
| Signed UIKit lifecycle smoke | Add `POCKETROOT_SMOKE_UI_LIFECYCLE=1` to the signed physical smoke command |
| Signed forced-relaunch persistence smoke | Add `POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1` to the signed physical smoke command |
| Signed bounded storage-failure smoke | Add `POCKETROOT_SMOKE_STORAGE_FAILURE=1` to the signed physical smoke command |
| Signed bounded memory-warning smoke | Add `POCKETROOT_SMOKE_MEMORY_WARNING=1` to the signed physical smoke command |
| Documentation checks | `./Scripts/check-docs.sh` |

## 9. Do not commit

Generated projects, build directories, RootFS archives or extracted fakefs data, smoke reports, signing material, tokens, or credentials must remain local.

## Next

- [Integration guide](IntegrationGuide.md)
- [Architecture](Architecture.md)
- [Testing](Testing.md)
- [Troubleshooting](Troubleshooting.md)
