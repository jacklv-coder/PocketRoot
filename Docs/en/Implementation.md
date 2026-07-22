# PocketRoot Implementation

[简体中文](../Implementation.md) | [English](Implementation.md) | [Documentation](README.md)

This document maps public APIs to source and explains the end-to-end implementation. See [architecture](Architecture.md) for boundaries and the [integration guide](IntegrationGuide.md) for the client contract.

## Source map

| Capability | Main source |
| --- | --- |
| Public system and coordinator | `Sources/PocketRootCore/` |
| Placeholder runtime | `Sources/PocketRootCore/Runtime/PlaceholderLinuxRuntime.swift` |
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

1. Validate a local base URL and safe manifest version.
2. Recover any persistent replacement journal before new work.
3. Open the caller input with `O_NOFOLLOW` and verify a regular file with `fstat`.
4. Copy into private same-volume staging with exclusive creation, user-only permissions, cancellation checks, and a compressed-byte cap.
5. Verify size and SHA-256 on that private snapshot.
6. Stream gzip through zlib with an expanded-byte cap.
7. Parse constrained POSIX ustar: checksums, UTF-8 relative paths, entry count and payload bounds; reject traversal, duplicates, links, and special nodes.
8. Reverify the archive snapshot and validate a real `fs/meta.db` file and `fs/data/` directory.
9. Write `.pocketroot-rootfs.json` into `extracted/fs`, then promote that
   directory itself to `rootfs/<version>`. The final directory directly
   contains the record, `meta.db`, and `data/`; it has no extra `fs/` layer.
10. Before any destructive rename, atomically persist a journal containing the
    target version, expected record, whether a previous install existed, and
    the prior `current.json` bytes. Move an old final to `previous/`, move the
    candidate to final, then atomically write `current.json`.
11. Treat each rename and JSON write as individually atomic, not the whole
    multi-step promotion. Synchronous failure rolls back. Interrupted recovery
    stores no phase; it infers commit or rollback from an expected-final match,
    backup presence, and the journal's prior-install data.
12. Reuse when the final layout and in-directory record match the manifest.
    Missing or mismatched `current.json` does not block reuse; rewrite it before
    returning.

The installer does not run SQLite integrity checks on every install; archive authenticity comes from the fixed digest. See [RootFS security](RootFS.md).

## Boot

The runtime validates fakefs types and health configuration, closes actor reentrancy by setting booting before suspension, claims the process gate, and runs synchronous IshEmbed boot on the shared serial blocking executor. After native boot returns, it runs a fixed `/bin/sh -c` identity command on that same queue. The command uses absolute `/bin/uname` and `/bin/cat`, returns `/etc/os-release` as data, and reports actual plus canonical target `pwd -P` values with NUL framing under a 4 KiB output budget. Swift parses unique ID/VERSION_ID keys without executing the file, rejects malformed quoting, UTF-8, duplicates, or framing, and compares configured expectations. The absolute working directory is passed as argv rather than interpolated into shell text; canonical comparison accepts trailing-slash, `.`, `..`, and symlink aliases. Only a successful match sets ready. A post-native-boot failure conservatively consumes the process slot and requires a host restart.

Those booting/ready/failed values are first the internal `IshLinuxRuntime`
state. `PocketRootSystem.state` does not continuously synchronize while
`await boot()` is in flight; it refreshes only after boot returns or throws.
The same boundary applies to internal shutting-down state. Public state is not
a real-time progress feed.

The direct runtime default requires `aarch64` and Alpine. With no explicit health configuration, the integration factory additionally requires version `3.19.1` only for the exact built-in v0.3.3 manifest; a custom manifest receives the version-agnostic Alpine ARM64 gate and should pass an explicit health configuration to pin its reviewed version. This checks consistency of base guest information and the configured command context inside an already validated RootFS; it is not an independent provenance or security proof and does not cover application-specific tools or services. The health timeout still shares the pinned native spawn/control path and is not an end-to-end hard bound over a blocked synchronous control write.

## One-shot execution

Requests require ready state, positive timeout no longer than 24 hours, positive stream limits, no active command, and current process ownership. Positive sub-millisecond timeout becomes 1 ms.

The adapter spawns:

```text
["/bin/sh", "-lc", request.command]
```

It closes stdin and polls events with bounded read waits. The deadline is created only after synchronous `spawn` and `closeStdin` return. stdout/stderr are accumulated under independent caps. Deadline expiry attempts to terminate the session and returns timeout with partial output; cap overflow terminates and throws a typed error. Exit events map exit code and signal, and the session is always closed. In the pinned v0.3.3 transport, spawn/control/terminate/close can still block, so this deadline is a read-loop boundary rather than an end-to-end time bound for `execute()`.

The command is a shell string; quoting and injection policy belong to the caller.

## Shutdown

The actor rejects shutdown while a command is active, changes state before suspension, verifies ownership, and calls native shutdown on the serial executor. The pinned implementation reaches `_exit(0)`, so the app normally exits inside that call. The returning terminated path exists for tests and a future soft-shutdown build.

## Demo, final link, and smoke

The default Demo stays asset-free and placeholder-backed. The compile spike proves the complete native graph final-links. The smoke injects a verified archive into a dedicated App, runs composition and command checks, persists its report before shutdown, and lets the host verify process exit.

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
- Native shutdown is host-process terminal.
- SwiftTerm waits for proven PTY ownership.

## Open implementation

Complete Task cancellation, public interactive sessions, session registry, bounded PTY reads, input/resize/signal/EOF, close-before-shutdown, soft-shutdown artifact integration, Demo injection, and physical-device hardening remain open. See the [roadmap](Roadmap.md).
