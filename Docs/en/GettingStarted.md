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

`test.sh` runs host Swift Package tests. The real release-asset test skips unless `POCKETROOT_ROOTFS_ARCHIVE` is set; synthetic fixtures still cover installer reuse and related paths. `build.sh` builds the default Demo for a generic iOS Simulator and does not boot the native guest.

## 5. Demo behavior

The UIKit Demo contains System, Terminal, Commands, and Diagnostics tabs. It is currently a UI and public-API shell:

- System and Commands use the placeholder `PocketRootSystem.shared`.
- Terminal has no PTY.
- Diagnostics describes future integration points.
- The Demo target links the safe `PocketRoot` umbrella, not the Experimental integration product.

“Runtime is not installed yet” is expected. Use the [integration guide](IntegrationGuide.md) for real runtime setup.

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
POCKETROOT_SMOKE_DEVICE=<physical-device-udid> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

The physical runner uninstalls the smoke App and injected RootFS after retrieving the report unless `POCKETROOT_KEEP_DEVICE_APP=1` is set. Never commit a UDID, provisioning profile, or local report.

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
| Signed physical native smoke | `POCKETROOT_ROOTFS_ARCHIVE=... POCKETROOT_SMOKE_DEVICE=... POCKETROOT_DEVELOPMENT_TEAM=... ./Scripts/run-runtime-device-smoke.sh` |
| Documentation checks | `./Scripts/check-docs.sh` |

## 9. Do not commit

Generated projects, build directories, RootFS archives or extracted fakefs data, smoke reports, signing material, tokens, or credentials must remain local.

## Next

- [Integration guide](IntegrationGuide.md)
- [Architecture](Architecture.md)
- [Testing](Testing.md)
- [Troubleshooting](Troubleshooting.md)
