# Application Integration Guide

[简体中文](../IntegrationGuide.md) | [English](IntegrationGuide.md) | [Documentation](README.md)

This guide documents the current public behavior and the complete local-RootFS to one-shot-result flow.

> [!CAUTION]
> The pinned IshEmbed shutdown path calls `_exit(0)`. In a native iOS build, `prepared.system.shutdown()` terminates the entire host app and normally never returns to Swift. Do not put it in view, scene, deinit, or routine cleanup paths.

## 1. Choose products

| Product | Purpose | Native iSH |
| --- | --- | --- |
| `PocketRootCore` | State, configuration, command, result, and error model | No |
| `PocketRootResources` | RootFS manifest, validation, extraction, and install | No |
| `PocketRootTerminal` | UIKit terminal placeholder UI | No |
| `PocketRoot` | Safe umbrella exporting the three products above | No |
| `PocketRootIshRuntime` | Experimental pinned IshEmbed adapter | Yes |
| `PocketRootIshRuntimeIntegration` | Experimental RootFS/runtime composition | Yes |

Use `PocketRoot` for stable models and UI. A real guest requires the explicit integration product. The repository has no stable release tag yet; pin a reviewed full commit:

```swift
dependencies: [
    .package(
        url: "https://github.com/jacklv-coder/PocketRoot.git",
        revision: "<reviewed-full-commit>"
    )
],
targets: [
    .target(
        name: "YourAppFeature",
        dependencies: [
            .product(name: "PocketRoot", package: "PocketRoot"),
            .product(name: "PocketRootIshRuntime", package: "PocketRoot"),
            .product(
                name: "PocketRootIshRuntimeIntegration",
                package: "PocketRoot"
            )
        ]
    )
]
```

In Xcode, choose **File → Add Package Dependencies**, enter the repository
URL, select the **Commit** rule with a reviewed full SHA, add `PocketRoot` for
the safe API, and explicitly add both native products only for Experimental
runtime work.

Local development may use `.package(path: "../PocketRoot")`. Do not use a floating branch or `from: "0.1.0"` before a release tag exists.

## 2. Availability

The native driver requires iOS, arm64, and an importable IshEmbed product:

```swift
import PocketRootIshRuntime

guard PocketRootIshRuntimeFactory.isAvailable else {
    return
}
```

The macOS fallback exists for host contract tests, not for a macOS Linux guest.
`isAvailable` runs only after SwiftPM has selected and linked dependencies, so it
cannot provide an x86_64 Simulator fallback for an App target that selects the
Experimental product. Such a target must set
`EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64`, as the repository's spike and
smoke targets do, or be split from the portable target. Intel Macs cannot build
the current native target.

## 3. Prepare a local RootFS

The caller must already own a reviewed local regular file. PocketRoot does not
download, request network access, bundle a payload, or accept
symlink/special-file input. `localReviewedArchiveURL` is supplied by the
product, not created by PocketRoot. A Files/document picker, controlled
download, or development Simulator injection can provide it.

### Move the archive into the App sandbox

```swift
import Foundation
import PocketRoot
import PocketRootIshRuntimeIntegration

let applicationSupportURL = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)

func importRootFSArchive(
    from importedURL: URL,
    applicationSupportURL: URL
) throws -> URL {
    let accessed = importedURL.startAccessingSecurityScopedResource()
    defer {
        if accessed {
            importedURL.stopAccessingSecurityScopedResource()
        }
    }

    let fileManager = FileManager.default
    let inboxURL = applicationSupportURL.appendingPathComponent(
        "RootFSInput",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: inboxURL,
        withIntermediateDirectories: true
    )

    let localURL = inboxURL
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("tar.gz")
    try fileManager.copyItem(at: importedURL, to: localURL)
    return localURL
}

let localReviewedArchiveURL = try importRootFSArchive(
    from: documentPickerURL,
    applicationSupportURL: applicationSupportURL
)

let prepared = try await PocketRootIshSystemFactory.prepareSystem(
    archiveURL: localReviewedArchiveURL,
    applicationSupportURL: applicationSupportURL,
    workDirectory: "/",
    maximumStandardOutputBytes: 8 * 1_024 * 1_024,
    maximumStandardErrorBytes: 4 * 1_024 * 1_024
)
```

A controlled download should likewise finish to a unique app-owned local path
before calling PocketRoot. The caller owns network, authentication, license,
file protection, backup exclusion, and cleanup policy. The installer still
requires a real regular file and captures its own private snapshot. The import
copy may be removed under product policy after `prepareSystem` returns.

Preparation validates and installs the fakefs directly under
`applicationSupportURL/rootfs/<version>`, where `meta.db`, `data/`, and
`.pocketroot-rootfs.json` live. It returns an idle system, never downloads or
boots, and reports its version, fakefs URL, and whether a valid installation
was reused.

The archive's top-level `fs/` is an input-layout boundary; the installer
promotes that directory itself, so the final version has no extra `fs/` layer.
Reuse is based on the version directory and its in-directory installation
record. A missing or mismatched `current.json` does not block valid reuse; the
installer repairs that index before returning.

See [RootFS security](RootFS.md) for the storage and recovery algorithm.

## 4. Boot

```swift
let system = prepared.system
try await system.boot()

guard await system.state == .ready else {
    throw PocketRootError.runtimeFailure("Runtime did not become ready.")
}
```

After native boot returns, `boot()` automatically runs a fixed post-boot identity command. When `healthCheck` is omitted or nil, only the exact built-in `.ishEmbedV0_3_3` manifest selects the same-name gate and strictly requires `aarch64`, `alpine`, and `3.19.1`; a custom manifest receives the version-agnostic `.alpineARM64` default and should explicitly pass the version reviewed for that RootFS. Identity values must be non-empty and NUL-free, timeout must be in `(0, 60]` seconds, and guest `workDirectory` must be an absolute NUL-free path. An optional `supervisorGuestPath` must also be NUL-free and is validated before the process slot is claimed or native boot begins.

The identity command has independent 4 KiB stdout/stderr caps. Swift parses `os-release` as data, the working directory is passed as argv, and actual plus target `pwd -P` values are compared so path aliases do not false-fail; expected identity values are never interpolated into shell text. A failure after native boot conservatively sets failed, consumes the process-global slot, and requires a host restart. This is a consistency check over base guest information and command context inside an already validated RootFS, not an independent provenance/security proof or an application-tool, network, or data check. A synchronous control write in the pinned v0.3.3 transport can still outlive the configured health timeout.

## 5. Execute one-shot commands

```swift
let result = try await system.execute(
    PocketRootCommandRequest(
        command: "printf '%s' \"$POCKETROOT_MODE\"; uname -m",
        workingDirectory: "/",
        environment: ["POCKETROOT_MODE": "integration"],
        timeout: .seconds(10),
        mergeStandardError: false
    )
)

print(result.exitCode)
print(result.signal)
print(result.stdout)
print(result.stderr)
print(result.timedOut)
```

Contract:

- The command runs as `/bin/sh -lc <command>`. It is a shell string, not an argv-safe API.
- One runtime accepts one one-shot command at a time.
- Timeout must be positive and no longer than 24 hours; positive sub-millisecond values become 1 ms.
- Timeout starts in the event-read loop only after the session is established and stdin is closed; expiry attempts termination and, when the call returns, reports `timedOut == true` with partial output.
- In pinned v0.3.3, spawn, control writes, terminate, and close may still block. The request timeout is therefore not an end-to-end watchdog for `execute()` and remains an Experimental read-loop deadline until native transport hardening is integrated.
- Command, cwd, and environment keys/values must contain no NUL; environment keys must also be nonempty and contain no `=`. Validation happens before the native driver to prevent silent C-string truncation.
- After session spawn, close-stdin failures, non-timeout read failures, timeout, and output overflow all terminate the session first. The runtime remains recoverable only when it observes an authoritative guest `EXITED`. A negative synthetic exit from pinned supervisor rejection before guest creation is instead surfaced as a provenance-preserving recoverable runtime error, never as a guest exit code. Pinned v0.3.3 also uses `(exitCode: 17, signal: 0)` for transport broken pipe, so that ambiguous pair explicitly requests termination and then fails closed. Failed termination or exit confirmation likewise locks the runtime in `failed` and requires a host-process restart.
- Merged stderr is returned in stdout with an empty stderr buffer.
- Default stdout/stderr caps are 8 MiB/4 MiB. Exceeding a cap throws `commandOutputLimitExceeded`.
- Swift Task cancellation is not yet a complete native-kill contract.
- `PocketRootConfiguration` defaults do not automatically override each request; build an application request factory if needed.

The result exposes exit code, signal, raw Data streams, UTF-8 convenience strings, and timeout state.

## 6. States and errors

The runtime state machine contains `idle`, `preparingRootFS`, `booting`,
`ready`, `shuttingDown`, `terminated`, and `failed(String)`. The public
`PocketRootSystem.state` publishes only a stable state after `boot()`,
`shutdown()`, or `execute()` returns or throws;
polling during an in-flight call can still show the previous value and is not a
progress stream. A command that fails closed publishes the
runtime's `.failed` state as `execute()` throws. Native terminated/restart behavior is normally
not observable because current shutdown exits the process.

Internally, `IshLinuxRuntime` sets `.booting` / `.shuttingDown` before
suspension to prevent reentrancy. A reentrant refresh ignores those transient
values. Refreshes also carry increasing generations: once a newer refresh has
started, an older delayed snapshot is discarded instead of overwriting a newer
`.failed` observation.

Handle typed `PocketRootError` cases: `runtimeNotBooted`, `rootFSUnavailable`, `runtimeFailure`, `restartRequired`, `invalidCommandRequest`, `commandOutputLimitExceeded`, and `unsupportedOperation`. RootFS preparation can additionally throw typed validation, extraction, and installation errors.

Do not branch only on localized strings.

## 7. Shutdown

```swift
// Invoke only if the product deliberately wants the host app process to exit.
try await system.shutdown()
```

Wait for active commands first. The current build cannot boot again after shutdown, and shutdown must not be used for ordinary UI cleanup. Applications that cannot accept process exit should avoid native shutdown until a soft-shutdown artifact exists.

## 8. Interactive sessions are not implemented

`PocketRootSession` types are API foundations only. PTY input/output, resize, signal/EOF, SwiftTerm, cancellation, session registry, and safe close-before-shutdown remain unavailable.

## 9. Use the placeholder terminal UI

`PocketRootTerminal` is currently usable as a UIKit presentation component,
not as a PTY:

```swift
import PocketRootTerminal

let terminalViewController = PocketRootTerminalViewController(
    configuration: PocketRootTerminalConfiguration(
        placeholderText: "Linux terminal is not connected.",
        prompt: "$ ",
        allowsInput: true,
        showsAccessoryView: true
    ),
    theme: .dark
)

terminalViewController.appendOutput("Preparing local environment…")
terminalViewController.apply(
    theme: PocketRootTerminalTheme(palette: .dark, fontSize: 16)
)
navigationController?.pushViewController(
    terminalViewController,
    animated: true
)
```

Run these UIKit operations on `MainActor`. `appendOutput` updates the
transcript and `clearOutput()` removes it. Even with input enabled, the current
accessory only echoes input and reports that the runtime is not installed; it
does not send commands to a guest. A real terminal waits for the session, PTY,
and SwiftTerm gates.

## 10. Integration checklist

- iOS 18+ arm64 target.
- Reviewed full PocketRoot commit and explicit Experimental products.
- Caller-owned regular RootFS file matching the manifest.
- Ordered preparation, built-in boot identity gate, and application-specific health checks.
- Positive command timeout and handling for exit, signal, timeout, and output limits.
- Explicit acceptance or avoidance of process-terminal shutdown.
- No claim that Simulator evidence proves physical-device or distribution readiness.
- All [release and compliance](ReleaseCompliance.md) gates closed before distribution.

## Related

- [RootFS security](RootFS.md)
- [Implementation](Implementation.md)
- [Testing](Testing.md)
- [Troubleshooting](Troubleshooting.md)
