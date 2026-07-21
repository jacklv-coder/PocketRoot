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

Install with `brew install xcodegen` or run `./Scripts/bootstrap.sh`. Generate `PocketRootDemo.xcodeproj` with `./Scripts/generate-project.sh`. Do not edit `project.pbxproj`; `project.yml` is authoritative.

## Dependency resolution

Check network access to the exact package commit and parent release asset, unchanged `Package.resolved`, and the selected Xcode command-line tools. Run `swift package resolve` and regenerate. Never replace immutable inputs with moving tags or unrecorded binaries.

## IshEmbed unavailable or missing module

Native support requires iOS + arm64 + explicit Experimental products. macOS, x86_64 Simulator, Intel Mac, and the default umbrella do not provide a native guest. Check `PocketRootIshRuntimeFactory.isAvailable`.

The upstream package has no macOS XCFramework slice despite its manifest declaration; direct upstream macOS native tests can fail. PocketRoot host tests use injected/unsupported drivers.

## Default Demo says runtime is not installed

Expected. It uses the placeholder shared system and has no PTY or RootFS. Follow the [integration guide](IntegrationGuide.md); do not add an unreviewed archive to the default bundle.

## Runtime not booted

Use the exact `prepared.system` returned by composition, call boot successfully, verify ready, then execute. Do not accidentally use `PocketRootSystem.shared`.

The retry boundary depends on where boot failed:

- RootFS preflight, such as a missing directory or symlinked `meta.db`, runs before the process-global slot is claimed. It leaves the runtime idle, so after correcting the input or preparing again, boot may be retried in the same host process.
- Once the slot has been claimed and native driver boot has been entered, a failure conservatively terminates the global slot. Booting the same or another system then returns `restartRequired`; restart the host app.
- A duplicate boot while the first call is still in progress is rejected. Await the original call instead of racing multiple systems.

## Already booted or restart required

Centralize one prepared system and lifecycle owner. There is one iSH kernel per process. A boot after the native slot was consumed, or after an injected-driver shutdown returned and marked it terminated, produces `restartRequired`. The current real native shutdown exits the host process, and the current build cannot implement shutdown then boot; restart the host app.

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

Timeout must be positive and no longer than 24 hours. Positive sub-millisecond values become 1 ms. It starts constraining the event-read loop only after synchronous `spawn` and `closeStdin` return. In pinned v0.3.3, control writes, terminate, and close may still block, so it is not an end-to-end watchdog for `execute()`. A timed-out result can contain partial collected output; check `timedOut` first without assuming every native operation had the same deadline.

## Output limit

Defaults are 8 MiB stdout and 4 MiB stderr. Overflow terminates the session and throws `commandOutputLimitExceeded`. Reduce/filter output or deliberately adjust limits; never make them unbounded.

## One command at a time

The current runtime accepts one one-shot command. Queue requests in the application and wait before shutdown. Interactive multi-session support does not exist.

## App exits during shutdown

Expected pinned behavior: guest halt reaches `_exit(0)` and terminates the host app. Avoid native shutdown unless the product intentionally wants that. See [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md).

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

## Smoke timeout or missing report

Verify the archive, Simulator boot, app install/launch, console output, storage,
and report. Increase only the JSON-report wait with
`POCKETROOT_SMOKE_TIMEOUT_SECONDS=600` when justified; this variable does not
bound project generation, the build, Simulator boot, or the fixed 20-second
post-report exit check. Missing reports and crashes are failures.

## Local pass, CI failure

Compare toolchains, SDK, destination architecture, resolved dependencies, XcodeGen, artifact digests, generated project source, and uncommitted local dependencies. CI runs `./Scripts/check-docs.sh` before tests and builds. The `actions/checkout` implementation is pinned to an exact revision, while the repository content is the workflow event SHA (push SHA or PR merge SHA). CI has no local archive, DerivedData, generated project, or credentials.

## Issue report

Provide commit, branch, toolchains, destination/architecture, exact command, typed error/log, runtime state, archive version/size/hash, and a minimal reproduction. Do not upload restricted archives, tokens, signing material, or private data.
