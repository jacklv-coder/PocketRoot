# PocketRoot Implementation

[简体中文](../Implementation.md) | [English](Implementation.md) | [Documentation](README.md)

This document maps public APIs to source and explains the end-to-end implementation. See [architecture](Architecture.md) for boundaries and the [integration guide](IntegrationGuide.md) for the client contract.

## Source map

| Capability | Main source |
| --- | --- |
| Public system and coordinator | `Sources/PocketRootCore/` |
| Placeholder runtime | `Sources/PocketRootCore/Runtime/PlaceholderLinuxRuntime.swift` |
| Lightweight agent loop | `Sources/PocketRootAgent/` |
| RootFS manifest, validation, extraction, install | `Sources/PocketRootResources/` |
| zlib primitive | `Sources/CPocketRootArchiveSupport/` |
| Native factory and adapter | `Sources/PocketRootIshRuntime/` |
| RootFS/runtime composition | `Sources/PocketRootIshRuntimeIntegration/` |
| Terminal UI | `Sources/PocketRootTerminal/` |
| Demo | `Demo/PocketRootDemo/` |
| Final-link and native behavior probes | `Spikes/` |

## Safe default

`PocketRootSystem()` and `PocketRootSystem.shared` inject `PlaceholderLinuxRuntime`. Boot is unsupported, execute reports not booted, and importing the umbrella does not link IshEmbed.

A native system is created only through:

```text
PocketRootIshSystemFactory.prepareSystem
  ├── PocketRootRootFSInstaller.prepareArchive
  └── PocketRootIshRuntimeFactory.makeSystem
      └── PocketRootSystem(package runtime: IshLinuxRuntime)
```

The returned instance never replaces `PocketRootSystem.shared`.

## Composition

`prepareSystem` validates and installs the caller archive, aligns `rootFSVersion` to the manifest, maps runtime configuration, and returns an installation plus an idle system. It does not download or boot.

## RootFS algorithm

1. Require a caller-created, existing real base directory and a safe manifest
   version. The installer does not recursively create unknown ancestors.
2. Recover any persistent replacement journal before new work.
3. If the target cannot be reused, require same-volume important-usage
   capacity for the compressed snapshot, two expanded copies, and a 16 MiB
   reserve before creating staging. A custom extractor wider than the manifest
   uses the larger expanded bound.
4. Open the caller input with `O_NOFOLLOW` and verify a regular file with `fstat`.
5. Copy into private same-volume staging with exclusive creation, user-only permissions, cancellation checks, and a compressed-byte cap.
6. Verify size and SHA-256 on that private snapshot.
7. Stream gzip through zlib with an expanded-byte cap.
8. Parse constrained POSIX ustar: checksums, UTF-8 relative paths, entry count and payload bounds; record every implicitly created parent as an archive target, then reject later same-path or filesystem-equivalent duplicate file/directory targets, links, and special nodes.
9. Reverify the archive snapshot and validate a real `fs/meta.db` file and `fs/data/` directory.
10. Write `.pocketroot-rootfs.json` into `extracted/fs`, flush every candidate
   regular file with `F_FULLFSYNC` (`fsync` fallback), synchronize directories
   leaf-first, then promote that
   directory itself to `rootfs/<version>`. The final directory directly
   contains the record, `meta.db`, and `data/`; it has no extra `fs/` layer.
11. Before any destructive rename, durably write an on-disk journal containing the
    target version, expected record, whether a previous install existed, and
    the prior `current.json` bytes. Move an old final to `previous/`, move the
    candidate to final, synchronizing source and destination parents after each
    move, then atomically and durably write `current.json`.
12. Treat each rename and JSON write as individually atomic, not the whole
    multi-step promotion. Synchronous failure rolls back. Interrupted recovery
    stores no phase; it infers commit or rollback from an expected-final match,
    backup presence, and the journal's prior-install data.
13. Reuse when the final layout and in-directory record match the manifest.

The installer creates `rootfs/` with an atomic `mkdir`; `EEXIST` only triggers
revalidation of the existing real, non-symlink directory. The shared executor
serializes work within one process. Multiple processes sharing the same base
directory are outside the supported contract.
    Missing or mismatched `current.json` does not block reuse; rewrite it before
    returning.

Test-only write fault points inject ENOSPC into snapshot, gzip output, tar
payload, installation-record, promotion-journal, and current-record paths. The
gzip fault fires after C/zlib accepts a configured output count so partial-tar
deletion is exercised; the other points use production cleanup and rollback
without changing the public API.

Seven test-only persistence barriers inject synchronization failures at the
candidate tree, journal file/directory, both promotion renames, and current
file/directory. Rollback and recovery apply the same parent-directory
synchronization rules to renames, record restoration, and transaction removal.
For candidate entries without owner read/search permission, the installer adds
only the access required inside private staging, restores the original mode
through the open descriptor, and then flushes it; final permissions are
unchanged. Before deleting failed staging or an old backup, cleanup grants
owner traversal/write only to the tree being removed and never follows links.

The installer does not run SQLite integrity checks on every install; archive authenticity comes from the fixed digest. See [RootFS security](RootFS.md).

## Boot

The runtime validates fakefs types, health configuration, and the optional supervisor path before claiming the process slot. A supervisor path containing NUL is rejected before native boot so C-string conversion cannot silently truncate it. The runtime then closes actor reentrancy by setting booting before suspension, claims the process gate, and runs synchronous IshEmbed boot on the shared serial blocking executor. After native boot returns, it runs a fixed `/bin/sh -c` identity command on that same queue. The command uses absolute `/bin/uname` and `/bin/cat`, returns `/etc/os-release` as data, and reports actual plus canonical target `pwd -P` values with NUL framing under a 4 KiB output budget. Swift parses unique ID/VERSION_ID keys without executing the file, rejects malformed quoting, UTF-8, duplicates, or framing, and compares configured expectations. The absolute working directory is passed as argv rather than interpolated into shell text; canonical comparison accepts trailing-slash, `.`, `..`, and symlink aliases. Only a successful match sets ready. A post-native-boot failure conservatively consumes the process slot and requires a host restart.

Those booting/ready/failed values are first the internal `IshLinuxRuntime`
state. `PocketRootSystem.state` does not continuously synchronize while
`await boot()` is in flight; it refreshes only after boot returns or throws.
The same boundary applies to internal shutting-down state. Public state is not
a real-time progress feed.

The direct runtime default requires `aarch64` and Alpine. With no explicit health configuration, the integration factory additionally requires version `3.19.1` only for the exact built-in v0.3.3 RootFS manifest; a custom manifest receives the version-agnostic Alpine ARM64 gate and should pass an explicit health configuration to pin its reviewed version. This checks consistency of base guest information and the configured command context inside an already validated RootFS; it is not an independent provenance or security proof and does not cover application-specific tools or services. The health timeout covers finite SPAWN, stdin close, and event reads from driver entry; exit confirmation has a separate fixed bounded cleanup window.

## One-shot execution

Requests require ready state, positive timeout no longer than 24 hours, positive stream limits, no active command, and current process ownership. Positive sub-millisecond timeout becomes 1 ms. Command, cwd, and environment keys/values must contain no NUL; environment keys must also be nonempty and contain no `=` so C-string and `key=value` encoding cannot truncate or become ambiguous.

The adapter spawns:

```text
["/bin/sh", "-lc", request.command]
```

At driver entry it creates one absolute deadline, passes the remaining
duration to finite `spawn`, closes stdin, and polls events with bounded reads.
SPAWN deadline expiry without a session returns a timed-out result. Direct not-running,
protocol, or broken-pipe errors from `spawn` make the transport untrustworthy
and fail the runtime closed; other pre-session failures preserve their source.
ABI.6 covers native instance/spawn gates and control-queue admission from
SPAWN API entry, with bounded asynchronous admission for stdin close and
terminate. The event loop reuses the same absolute deadline. stdout/stderr
have independent caps. Later close-stdin, non-timeout read, request-timeout,
and product-cap failures terminate the session and require authoritative
`EXITED` confirmation. Wire v4 returns supervisor rejection, broken pipe, and
native backlog overflow as typed terminal errors. Guest exit 17 is valid; a
negative `EXITED` payload is a protocol-integrity failure. Supervisor rejection
remains recoverable. Native backlog overflow requests bounded cleanup, but the
void close ABI cannot prove whether cleanup escalated to instance fail-close,
so PocketRoot permanently closes the process gate. Termination and
authoritative `EXITED` confirmation after expiry use a separate fixed bounded
cleanup window.

The command is a shell string; quoting and injection policy belong to the caller.

`BlockingIshExecutor.performCancellable` checks cancellation before enqueue,
when the serial queue starts the operation, and after native return. A queued
cancelled command never spawns. For an active command, the driver polls the
token at most every 250 ms, terminates the session, and throws
`CancellationError` only after authoritative `EXITED`. Cleanup errors take
precedence and fail the runtime closed; successful cancellation leaves it ready.

## Shutdown

The actor rejects shutdown while a command is active, changes state before
suspension, verifies ownership, and calls native shutdown on the serial
executor. Pinned v0.4.0-abi.6 stops the supervisor, soft-halts the kernel,
performs a bounded join, and returns. State becomes `.terminated`; the same
host process cannot boot another iSH lifecycle.

## Demo, final link, and smoke

The Demo explicitly links the Experimental graph but keeps RootFS material
outside the repository. Its Debug build phase accepts only the exact pinned
size/digest, removes stale output when absent, and never injects into Release.
`DemoRuntimeStore` runs `prepare → boot` and shares one system across System,
Terminal, Commands, and Files. The compile spike proves final linking, while
the separate smoke remains the automated behavioral evidence and persists
success only after bounded shutdown returns.

## Invariants

- The umbrella never links IshEmbed.
- The library never downloads a RootFS.
- Only manifest-matching snapshots are promoted.
- Caller path replacement cannot alter a captured snapshot.
- Failed replacement preserves the last valid install.
- One host process has one native owner.
- Blocking native calls stay off the main/cooperative executors.
- Internal runtime lifecycle state closes before suspension; public system state is not a real-time progress feed.
- One-shot commands have positive time and finite output.
- Shutdown cannot overtake an active command.
- Native shutdown returns `.terminated`, and the same process cannot boot again.
- SwiftTerm only attaches through registered, bounded-read PTY ownership with
  close-before-shutdown ordering.

## Open implementation

Prepared-system Demo injection, currently available signed-iPhone PTY lifecycle and sustained-output
coverage, iPad keyboard/rotation/layout, VoiceOver, and app-transition
hardening remain open. See the [roadmap](Roadmap.md).
