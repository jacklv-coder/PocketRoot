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
| Simulator native smoke | `./Scripts/run-runtime-smoke.sh` | Prepare, boot, command bounds, pinned shutdown | Physical, minimum-Xcode, distribution |
| Physical native smoke | `./Scripts/run-runtime-device-smoke.sh` | Same 13 checks, development entitlements, actual process exit | Full lifecycle, memory, iPad, distribution |
| Documentation | `./Scripts/check-docs.sh` | Pairs, Chinese coverage, relative links | Implementation correctness |

## Package tests

```bash
./Scripts/test.sh
```

Coverage includes the following relevant boundaries:

- Core tests cover request/configuration defaults, result-stream decoding, placeholder lifecycle behavior, injected-runtime delegation, public-state refresh after fail-closed execute and failed shutdown, rejection of transient-state publication by a reentrant command, rejection of stale refresh overwrite after a newer failure, plus RootFS-provider/metadata coordination.
- Resources tests cover the pinned manifest and gated bundled provider; archive existence, symlink rejection, byte count, and SHA-256; required fakefs layout and metadata-symlink rejection; successful gzip/ustar extraction, traversal cleanup, explicit-directory-after-implicit-parent rejection, duplicate-directory and case-aliased-directory rejection on insensitive volumes, archive symlink entry/source rejection, and the expanded-byte limit.
- Synthetic Resources fixtures cover first install and reuse, private archive-snapshot isolation and byte bounds, reserved versions, corrupt replacement, failed upgrade/promotion rollback, interrupted transaction recovery, and a single installation under concurrent preparation.
- Injected runtime tests cover configuration and host availability, missing/symlinked fakefs plus typed attribute-read preflight failures without slot consumption, boot and `/bin/sh -lc` request mapping, built-in/custom-manifest health-default selection, the post-boot identity request, architecture/OS/version/cwd mismatch, canonical cwd aliases, timeout, signal/exit, health output limits, invalid UTF-8, duplicate os-release keys, malformed NUL framing, invalid configuration/relative cwd/NUL supervisor path without slot consumption, execute-before-boot, timeout validation/clamping, ambiguous C-string input rejection, process ownership including direct rejection of a different owner UUID, failed/concurrent boot admission, active-command shutdown ordering, output-limit mapping, provenance-preserving recoverable supervisor rejection, shared-gate unconfirmed-exit fail-closed behavior, terminal spawn transport-error mapping, rejection of the pinned transport's ambiguous broken-pipe marker, and terminated/`restartRequired` behavior.
- Agent tests cover direct final text, response/call ID continuation, structured unknown-tool and ordinary-tool failures, repeated response/call IDs, whole-batch validation before side effects, turn/call/input/model/identifier/name/argument/output limits, rejection of concurrent runs and unfinishable last-turn tools, plus configuration, name, and object-schema validation.
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
Simulator boot, or the fixed 20-second post-report process-exit check. A
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

The 13 checks cover preparation, ready boot, aarch64, Alpine 3.19.1, cwd, environment, split streams and exit 7, merged stderr, 100 ms timeout and recovery, 64-byte output limit and recovery, and host-process exit on shutdown.

The 100 ms check proves recovery after an established session observes its event-read deadline. It does not cover the earlier synchronous spawn/control write or prove that terminate/close have the same end-to-end hard limit. The [Roadmap](Roadmap.md) tracks that native control-path gate.

The report is persisted before shutdown. The host requires the attached Simulator process to finish successfully, so an ordinary crash is not accepted. This smoke is a local gate, not a GitHub Actions step.

### Signed iPhone/iPad runner

Use explicit physical-device and team identifiers:

```bash
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \
POCKETROOT_SMOKE_DEVICE=<physical-device-udid> \
POCKETROOT_DEVELOPMENT_TEAM=<team-id> \
  ./Scripts/run-runtime-device-smoke.sh
```

The paired device must have Developer Mode enabled and support development provisioning. The runner verifies the application identifier and `get-task-allow`, installs with `devicectl`, copies the pinned archive into the App data container, performs an attached launch, and retrieves the JSON report. It uninstalls the App and RootFS data by default; `POCKETROOT_KEEP_DEVICE_APP=1` is the explicit opt-out.

The 2026-07-23 record used Xcode 26.1.1 (17B100), an iPhone 17 Pro, iOS 26.1 (23B85), and development provisioning. Archive size/digest, report environment, all 13 checks, and exit status passed. No UDID, profile, or local report is committed. This closes the signed iPhone one-shot baseline, not iPad, foreground/background, memory/jetsam, storage pressure, or minimum-Xcode 16.

## CI

GitHub Actions pins the `actions/checkout` action implementation to an exact
revision; that action still checks out the commit SHA selected by the workflow
event (the push SHA or PR merge SHA). On a macOS runner CI then runs
`./Scripts/check-docs.sh`, reports toolchains, runs package tests, downloads and
independently verifies the exact RootFS, runs its first-materialization test,
obtains pinned XcodeGen with checksum validation, generates the project, builds
the Demo, and final-links arm64 Simulator and unsigned-device runtime Apps.

CI does not boot native iSH.

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

State the exact environment. The recorded iPhone baseline does not imply iPad support, complete physical-device lifecycle, minimum-Xcode native validation, TestFlight readiness, or App Store approval.

See the [roadmap](Roadmap.md) for open gates.
