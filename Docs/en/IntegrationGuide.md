# Application Integration Guide

[简体中文](../IntegrationGuide.md) | [English](IntegrationGuide.md) | [Documentation](README.md)

This guide documents the current public behavior, distinguishes the safe
default, explicit agent, and Experimental native products, and covers the
complete local-RootFS to one-shot-result flow.

> [!CAUTION]
> Pinned `v0.4.0-abi.9` soft-halts and joins the embedded kernel, then
> `prepared.system.shutdown()` returns to Swift. The same host process cannot
> boot again after success. Do not trigger it accidentally from view, scene,
> deinit, or routine cleanup paths.

## 1. Choose products

| Product | Purpose | Native iSH |
| --- | --- | --- |
| `PocketRootCore` | State, configuration, command, result, and error model | No |
| `PocketRootResources` | RootFS manifest, validation, extraction, and install | No |
| `PocketRootTerminal` | UIKit/SwiftUI SwiftTerm PTY, guest files, and command fallback | No |
| `PocketRootAgent` | Provider-agnostic bounded agent loop and OpenAI Responses transport | No |
| `PocketRootAgentRuntimeTools` | Approval- and policy-gated Linux command adapter | No |
| `PocketRoot` | Safe umbrella exporting Core, Resources, and Terminal | No |
| `PocketRootIshRuntime` | Experimental pinned IshEmbed adapter | Yes |
| `PocketRootIshRuntimeIntegration` | Experimental RootFS/runtime composition | Yes |

Use `PocketRoot` for stable models and UI. Add `PocketRootAgent` explicitly for
the agent loop and optional OpenAI Responses transport. Add
`PocketRootAgentRuntimeTools` only when exposing a prepared system through the
approval-gated command adapter documented in [Lightweight Agent Loop](Agent.md).
A real guest requires the explicit integration product. Add
`PocketRootIshRuntime` only when calling the lower-level runtime factory
directly; the recommended host controller does not require the App to import
it. The repository has no stable release tag yet; pin a reviewed full commit:

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
the safe API, and explicitly add `PocketRootIshRuntimeIntegration` for
Experimental runtime work.

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

### Recommended: one host controller for the minimal loop

Retain one `PocketRootIshWorkspaceHost` in the App or scene owner. The caller
provides a reviewed local RootFS archive and Application Support location; the
host coalesces boot, prepares the RootFS, boots the runtime, and directly
creates Terminal, Files, or combined Workspace screens:

```swift
import PocketRoot
import PocketRootIshRuntimeIntegration

let pocketRootHost = PocketRootIshWorkspaceHost(
    runtimeConfiguration: PocketRootIshRuntimeControllerConfiguration(
        archiveURL: localReviewedArchiveURL,
        applicationSupportURL: applicationSupportURL,
        workDirectory: "/"
    ),
    workspaceConfiguration: PocketRootWorkspaceConfiguration(
        terminalConfiguration: .interactive(
            initialWorkingDirectory: "/root"
        ),
        initialFilePath: "/root",
        allowsFileOperations: true
    )
)

navigationController?.pushViewController(
    pocketRootHost.makeTerminalViewController(),
    animated: true
)

navigationController?.pushViewController(
    pocketRootHost.makeFilesViewController(),
    animated: true
)
```

Neither direct entry requires the App to boot first or poll `readySystem`.
Leaving a Terminal screen closes only its PTY while preserving the runtime for
a later Terminal, Files, or Workspace screen. Use
`pocketRootHost.makeViewController()` for the combined two-tab Workspace; its
PTY stays alive while the user switches to Files.

Set `allowsFileOperations: false` on
`PocketRootWorkspaceConfiguration` when the entire Workspace Files tab must be
browse-and-preview only. The SwiftUI and UIKit workspace wrappers enforce the
same read-only boundary.

Retain one `PocketRootIshWorkspaceHost` in the App or scene owner. The first
screen presentation coalesces concurrent boot requests and prepares the
caller-supplied local RootFS. When intentionally ending Linux support, call
`try await pocketRootHost.shutdown()`; it closes every screen made by that host
before process-global shutdown.

SwiftUI passes the same process-retained host to
`PocketRootIshWorkspaceView(host: pocketRootHost)`; do not recreate the host
from `body`. The host never downloads or chooses a RootFS and does not install
Node.js, npm, Codex CLI, or an Agent Loop. The two-entry
[`Examples/PocketRootQuickStartApp`](../../Examples/PocketRootQuickStartApp)
and full-lifecycle
[`Examples/PocketRootHostApp`](../../Examples/PocketRootHostApp) XcodeGen Apps
use only public Swift Package products. CI builds both and verifies their
injected RootFS.

### Lower-level host lifecycle

Apps that want separate Boot, Terminal, and Files controls may retain
`PocketRootIshRuntimeController`, present surfaces only while `readySystem` is
non-nil, call `closeSession()` when leaving a PTY, and refresh authoritative
runtime state after a fatal session end.

### Lower-level manual lifecycle

Products that need direct prepared-system ownership may continue to use the
composition factory:

```swift
let system = prepared.system
try await system.boot()

guard await system.state == .ready else {
    throw PocketRootError.runtimeFailure("Runtime did not become ready.")
}
```

After native boot returns, `boot()` automatically runs a fixed post-boot identity command. When `healthCheck` is omitted or nil, only the exact built-in `.ishEmbedV0_3_3` manifest selects the same-name gate and strictly requires `aarch64`, `alpine`, and `3.19.1`; a custom manifest receives the version-agnostic `.alpineARM64` default and should explicitly pass the version reviewed for that RootFS. Identity values must be non-empty and NUL-free, timeout must be in `(0, 60]` seconds, and guest `workDirectory` must be an absolute NUL-free path. An optional `supervisorGuestPath` must also be NUL-free and is validated before the process slot is claimed or native boot begins.

The identity command has independent 4 KiB stdout/stderr caps. Swift parses `os-release` as data, the working directory is passed as argv, and actual plus target `pwd -P` values are compared so path aliases do not false-fail; expected identity values are never interpolated into shell text. A failure after native boot conservatively sets failed, consumes the process-global slot, and requires a host restart. This is a consistency check over base guest information and command context inside an already validated RootFS, not an independent provenance/security proof or an application-tool, network, or data check. The health timeout covers finite SPAWN, stdin close, and event reads from driver entry; termination confirmation has a separate fixed bounded cleanup window.

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
- One timeout deadline starts at driver entry. Finite SPAWN receives the
  remaining duration, and stdin close plus the event-read loop reuse the same
  deadline. Expiry attempts termination and reports `timedOut == true` with
  partial output after authoritative exit.
- Native control queues, session backlogs, and lifecycle reserve are bounded.
  Termination and authoritative `EXITED` confirmation after expiry use a
  separate fixed bounded cleanup window.
- Command, cwd, and environment keys/values must contain no NUL; environment keys must also be nonempty and contain no `=`. Validation happens before the native driver to prevent silent C-string truncation.
- Direct not-running, protocol, or broken-pipe spawn failures fail the runtime
  closed. Later close-stdin, non-timeout read, request-timeout, and product-cap
  failures terminate and confirm exit. Wire v4 returns supervisor rejection,
  broken pipe, and native-backlog overflow as typed errors. Guest exit 17 is
  valid; a negative `EXITED` payload is a protocol-integrity failure. Native
  backlog overflow requests bounded cleanup and preserves byte/frame
  provenance, but void `session.close()` cannot prove whether cleanup escalated
  to instance fail-close. PocketRoot therefore closes its process gate and
  requires a restart.
- Merged stderr is returned in stdout with an empty stderr buffer.
- Default stdout/stderr caps are 8 MiB/4 MiB. Exceeding a cap throws `commandOutputLimitExceeded`.
- Cancelling the Swift Task requests native-session termination and throws
  `CancellationError` only after a trusted `EXITED` event. Successful
  cancellation keeps the runtime ready; unconfirmed cleanup fails it closed.
  Cancellation does not undo side effects that already occurred.
- `PocketRootConfiguration` defaults do not automatically override each request; build an application request factory if needed.

The result exposes exit code, signal, raw Data streams, UTF-8 convenience strings, and timeout state.

## 6. States and errors

The runtime state machine contains `idle`, `preparingRootFS`, `booting`,
`ready`, `shuttingDown`, `terminated`, and `failed(String)`. Each read of
`PocketRootSystem.state` reconciles with the underlying runtime, so an
asynchronous PTY failure after `makeSession()` returns is observable. It
publishes only stable states; polling during an in-flight call can still show
the previous value and is not a progress stream. A command that fails closed publishes the
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
// Invoke after every active command has completed.
try await system.shutdown()
```

Shutdown stops the supervisor, soft-halts and joins the kernel, returns to
Swift, and publishes `.terminated`. The same host process cannot boot again.
Do not trigger this terminal lifecycle transition accidentally from ordinary UI
cleanup.

## 8. Interactive PTY sessions

An already-booted system can create a persistent PTY shell:

```swift
let session = try await system.makeSession(
    configuration: PocketRootSessionConfiguration(
        shell: "/bin/sh",
        shellArguments: ["-il"],
        workingDirectory: "/root"
    )
)

try await session.write(Data("mkdir -p demo && cd demo\r".utf8))
try await session.resize(to: .init(rows: 32, columns: 100))
try await session.sendSignal(2)
try await session.closeInput()
await session.terminate()
```

The shell, cwd, environment, and foreground jobs persist inside the real PTY.
Reads poll with a 100 ms bound. Output is split into 16 KiB chunks and the
event stream retains at most 4 MiB while preserving terminal `.failed` and
`.exited` events when full.
`SHELL` defaults to the configured executable unless explicitly overridden.
Terminate uses finite native admission and remains idempotent. Shutdown rejects
an in-flight session creation instead of passing an unregistered native handle,
and fatal transport failures make the runtime restart-required. Runtime shutdown
stops PID 1 and the kernel only after every registered live session has produced
an authoritative exit, closed, and unregistered. Canceled creation closes a
native handle that was spawned but not returned. Recoverable supervisor
rejections and post-EOF operations remain session-local instead of poisoning
the runtime.
`PocketRootCommandTerminalSession` remains an optional one-shot fallback.

## 9. Embed Terminal and Files

When a host already owns a prepared and booted `system`, the lower-level
workspace can present a persistent PTY and guest file browser. Switching
surfaces does not recreate the terminal session:

```swift
import PocketRootTerminal

let workspace = PocketRootWorkspaceViewController(
    system: system,
    configuration: .init(
        terminalConfiguration: .interactive(
            initialWorkingDirectory: "/root"
        ),
        initialFilePath: "/root"
    )
)
navigationController?.pushViewController(workspace, animated: true)
```

The host injects an already-ready system. The workspace does not install a
RootFS, boot, or shut down the runtime. It closes its PTY when permanently
removed; before host-driven shutdown, call
`workspace.closeSession(completion:)`. The UIKit segmented control and tab bar
both switch Terminal/Files without destroying either child page.

For a terminal-only surface, UIKit can open the SwiftTerm PTY directly:

```swift
import PocketRootTerminal

let terminalViewController = PocketRootTerminalViewController(
    system: system,
    configuration: .interactive(initialWorkingDirectory: "/root"),
    theme: .dark
)
terminalViewController.onSessionEnded = { [weak terminalViewController] _ in
    // Dismiss the page or offer a new terminal after shell exit or PTY failure.
    terminalViewController?.navigationController?.popViewController(animated: true)
}
navigationController?.pushViewController(
    terminalViewController,
    animated: true
)
```

When `sessionConfiguration` is omitted, the PTY uses
`configuration.initialWorkingDirectory`. Pass an explicit session configuration
to customize the shell, environment, or terminal size; that complete session
configuration takes precedence.
`cursorBlinkEnabled` defaults to `true`. Deterministic screenshots or UI
automation may set it to `false` without changing PTY input, output, or
lifecycle behavior.

The guest file browser is another ready-to-present page:

```swift
let filesViewController = PocketRootFileBrowserViewController(
    system: system,
    initialPath: "/root",
    allowsFileOperations: true
)
navigationController?.pushViewController(filesViewController, animated: true)
```

The disclosure control on a folder row loads and expands that directory inline.
Tapping the folder icon or name instead navigates to a dedicated directory page.
Both interactions use the same bounded command protocol and path validation;
neither reads the RootFS storage layout directly from the host App sandbox. The
top-right action menu creates empty files or folders, while long-press and swipe
actions rename, delete, or share-export regular files. `Import File` in the
same menu uses the system document picker. Folder deletion requires recursive
deletion confirmation. Pass `allowsFileOperations: false` for a read-only
surface.

Hosts that do not use the ready-made page can call the same actor directly:

```swift
let files = PocketRootFileBrowser(system: system)
try await files.createFile(named: "notes.txt", in: "/root")
try await files.createDirectory(named: "Sources", in: "/root")
try await files.renameItem(at: "/root/notes.txt", to: "README.txt")
try await files.importFile(
    data: Data("hello\n".utf8),
    named: "imported.txt",
    in: "/root"
)
let exported = try await files.exportFile(at: "/root/imported.txt")
try await files.deleteItem(at: "/root/Sources", recursively: true)
```

Names must occupy 1–255 UTF-8 bytes and cannot be `.`, `..`, or contain `/` or
NUL. Guest arguments are validated; create and rename never replace an existing
item; `/` cannot be renamed or deleted; and non-empty directory deletion
requires explicit `recursively: true`. Rename uses IshEmbed
the atomic `RENAME_NOREPLACE` equivalent in `v0.4.0-abi.9`, not a racy shell
check-then-move sequence. Import and export default to a 1 MiB maximum. Import
bytes travel through `PocketRootCommandRequest.standardInput`, never shell
text, into a random mode-`0600` staging file in the destination directory;
the same native no-replace rename commits it. Existing destinations are never
replaced, and write, cancellation, or commit failures perform bounded
best-effort cleanup. Export accepts regular files only and checks the limit
both with guest `stat` and after Swift receives the bytes.

SwiftUI has the same composed entry point:

```swift
import PocketRootTerminal
import SwiftUI

struct LinuxTerminalScreen: View {
    let system: PocketRootSystem

    var body: some View {
        PocketRootWorkspaceView(
            system: system,
            configuration: .init(initialFilePath: "/root")
        )
    }
}
```

SwiftTerm handles ANSI/VT rendering, keyboard input, selection, scrolling, and
accessibility semantics. The bridge preserves input order, forwards character
size changes, and streams guest output. Guest OSC 52 clipboard access is denied
by default. The Files page uses NUL-framed listings and bounded previews of up
to 512 KiB, plus basic guest file management. Only explicit import/export
crosses the host/guest boundary through the system document picker/share
sheet; the browser never exposes arbitrary host App sandbox paths.

With a custom configuration whose `allowsInput` is `false`, the PTY remains
visible and continues receiving guest output, but the bridge drops every
keyboard or paste write and does not automatically show the keyboard. The
SwiftUI wrapper keys its hosted controller by the system/executor reference,
session configuration, and terminal configuration. Changing any of those
inputs closes the old session and rebuilds the controller; a theme-only update
is applied in place.

## 10. Integration checklist

- iOS 18+ arm64 target.
- Reviewed full PocketRoot commit and explicit Experimental products.
- Caller-owned regular RootFS file matching the manifest.
- Ordered preparation, built-in boot identity gate, and application-specific health checks.
- Terminal and Files share the same application-owned, booted system.
- UIKit handles shell exit and PTY failure through `onSessionEnded`, then
  dismisses the terminal or offers a new session.
- Read-only terminals set `allowsInput: false`; backend/configuration changes
  intentionally rebuild the SwiftUI-hosted session.
- Positive command timeout and handling for exit, signal, timeout, and output limits.
- Acceptance of the single-lifecycle contract: no reboot in the same host process after shutdown.
- No claim that Simulator evidence proves physical-device or distribution readiness.
- All [release and compliance](ReleaseCompliance.md) gates closed before distribution.

## Related

- [RootFS security](RootFS.md)
- [Implementation](Implementation.md)
- [Testing](Testing.md)
- [Troubleshooting](Troubleshooting.md)
