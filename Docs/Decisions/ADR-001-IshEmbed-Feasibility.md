# ADR-001: Adopt IshEmbed as an Experimental ARM64 Runtime

- Status: Accepted for Experimental integration only
- Date: 2026-07-21
- Baseline: iOS 18.0, arm64
- Decision scope: runtime feasibility, supply-chain pinning, and release gates

## Context

PocketRoot needs an embeddable ARM64 Linux runtime that can boot an Alpine
fakefs, execute one-shot commands, and later provide interactive PTY sessions.
The audited candidate is the user's fork of `ish-arm64-pkg`, which wraps an
iSH-derived kernel in a Swift Package named `IshEmbed`.

The dependency is young, pre-1.0, and combines source code, a prebuilt static
XCFramework, a separately distributed RootFS, and a pinned iSH submodule.
Adopting it therefore requires both runtime validation and an explicit
distribution gate.

## Decision

PocketRoot will integrate IshEmbed behind the separate
`PocketRootIshRuntime` product as an Experimental implementation. A second
Experimental product, `PocketRootIshRuntimeIntegration`, composes the runtime
with verified RootFS materialization. Neither product is re-exported by the
`PocketRoot` umbrella product while the feasibility gates remain open.

The Swift Package dependency must use this exact immutable revision:

```text
Repository: https://github.com/jacklv-coder/ish-arm64-pkg.git
Revision:   6f96f02c71830914c2a608258a26a8ef0833d026
Product:    IshEmbed
```

That revision is identical to the parent repository's `v0.3.3` peeled commit.
The user's fork had no tags or releases at audit time, so a semantic-version
requirement such as `from: "0.3.3"` must not be used against the fork.

The dependency's `third_party/ish` submodule is independently pinned at:

```text
2f075626049d989dc9ac350a35c09f0b18930ffc
```

The submodule's branch has moved beyond that commit. PocketRoot must not follow
the branch implicitly or substitute a newer submodule commit without rebuilding
and re-auditing every binary artifact.

## Audit evidence

### Package and binary shape

The audited manifest exposes one library product, `IshEmbed`, composed from:

- `CIshEmbed`: C module exposing the stable embedding ABI
- `IshKernel`: prebuilt binary target
- `IshEmbed`: Swift API, session types, and terminal helpers
- `IshEmbedTests`: five RootFS-dependent integration tests

The manifest declares iOS 14 and macOS 12, but the released XCFramework only
contains these slices:

| Identifier | Architecture | Platform | Binary minimum |
| --- | --- | --- | --- |
| `ios-arm64` | arm64 | iOS device | iOS 14.0 |
| `ios-arm64-simulator` | arm64 | iOS Simulator | iOS 14.0 |

There is no x86_64 Simulator slice and no macOS slice. PocketRoot therefore
uses the product only when building for iOS and requires arm64 CI runners for
native integration tests. Running `swift test` directly in the upstream
package on macOS fails at link time despite its macOS platform declaration.

### Artifact integrity

The GitHub Release assets attached to the parent repository's `v0.3.3` release
were downloaded and independently hashed:

| Artifact | SHA-256 |
| --- | --- |
| `libIshKernel.xcframework.zip` | `f747c2e85c3b6082e102fb45aa62797f52146a3bc5eb1a0c386b74bc156d4fca` |
| `fs.tar.gz` | `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4` |

The XCFramework digest matches the checksum embedded in the upstream package
manifest. The RootFS digest is not represented by that manifest and must be
recorded and checked by PocketRoot before materialization.

The RootFS is derived from Alpine 3.19.1 aarch64. The official source
minirootfs used by the build script has SHA-256:

```text
7ef5eef3a5b1d198dfb1610cde1ef5b0755ff5d838fb1e5e1b9f42b59214820f
```

### iOS 18 spike

The audit used Xcode 26.1.1 and Swift 6.2.1 on Apple Silicon. A minimal iOS 18
consumer app completed both an arm64 Simulator link and an unsigned arm64
device link. On an iOS 18.2 iPhone 16 Pro Simulator it then:

1. copied the audited fakefs into the app's writable sandbox;
2. booted `IshInstance.shared`;
3. executed `/bin/uname -m`; and
4. received exit code 0 and `aarch64` on standard output.

This proves the specific Simulator boot path, not physical-device viability.
Every paired physical iPhone was unavailable during the audit, so the
physical iPhone and iPad gate remains open.

### Repository integration evidence

The repository consumes the exact fork revision through SwiftPM and final-links
a minimal application containing `PocketRootIshRuntimeIntegration`,
`PocketRootIshRuntime`, `PocketRootResources`, zlib, sqlite3, IshEmbed, and the
IshKernel XCFramework for both arm64 Simulator and unsigned arm64 device
destinations.

The committed RootFS manifest records the v0.3.3 URL, architecture, format,
archive size, expanded size, and SHA-256. The installer validates the archive,
copies it through a bounded no-follow descriptor into private same-volume
staging, extracts only supported gzip/ustar entries, revalidates the snapshot,
and rejects path traversal, host symlinks, duplicate files, and unexpected
fakefs layouts. A persistent promotion transaction commits or restores an
interrupted rename before stale staging is cleaned. Tests cover install,
verified reuse, source-path replacement, bounded copying, corruption
replacement, concurrent preparation, promotion rollback, interrupted rollback,
and interrupted commit.
The complete flow also passed against the exact 6,581,376-byte release asset;
CI repeats that real-asset test after verifying size and SHA-256.

### PocketRoot adapter smoke

The repository-owned smoke App passed 13 checks through
`PocketRootIshRuntimeIntegration` on an iOS 18.2 arm64 Simulator using the exact
v0.3.3 RootFS:

1. prepared the verified v0.3.3 installation;
2. booted the runtime to `ready`;
3. returned `aarch64` from `/bin/uname -m`;
4. returned Alpine `3.19.1` from `/etc/alpine-release`;
5. applied `/` as the command working directory;
6. applied the caller-provided environment;
7. preserved separate stdout and stderr plus exit code 7;
8. merged stderr into stdout when requested;
9. reported a 100 ms command timeout;
10. executed another command successfully after that timeout;
11. enforced the configured 64-byte stdout limit;
12. executed another command successfully after output-limit termination; and
13. requested native shutdown and verified that the launched App process ended.

The smoke report is persisted before shutdown because the pinned iSH shutdown
path deliberately calls `_exit(0)` when PID 1 terminates. The host script then
requires the attached `simctl --console` process to finish promptly with a
successful exit status. This validates the current process-terminal shutdown
contract; it does not demonstrate an in-process restart.

Run the same local gate on an Apple Silicon host with an iOS 18 Simulator and
the audited archive:

```shell
POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz ./Scripts/run-runtime-smoke.sh
```

This smoke was not run by GitHub Actions and is not evidence for Xcode 16 or a
physical iPhone or iPad.

### Private API and entitlement scan

The released archive and a fully linked consumer binary showed no `MAP_JIT`,
JIT entitlement, private framework path, or `com.apple.private.*` entitlement.
The ARM64 engine dispatches through precompiled gadgets rather than generating
machine code at runtime. The full iSH application source contains entitlements
that are not part of the embedded XCFramework.

This is evidence from static inspection and Simulator execution, not an App
Review guarantee. A signed physical-device build and distribution review are
still required.

## Runtime constraints

The public C contract allows one process-global iSH instance. At the pinned
revision, guest PID 1's shutdown path ends in `_exit(0)`, so
`IshInstance.shutdown()` terminates the entire host App and never returns to
Swift. PocketRoot therefore treats shutdown as process-terminal and must not
implement `restart` as `shutdown` followed by `boot`. The adapter's
`.terminated` and `restartRequired` behavior is unit-tested with an injected
returning driver, but it is not observable after native shutdown in the pinned
binary.

This behavior is acceptable only for the current Experimental feasibility
boundary. Before default product integration, the project must either accept
host-process termination as an explicit application contract or patch the iSH
fork so embedded shutdown exits only the kernel thread. A soft-shutdown rebuild
must also bound the native reader/log thread joins, produce a new audited
XCFramework revision and checksum, and repeat Simulator and physical-device
lifecycle tests.

The audited session implementation also has unsafe shutdown edges: native
shutdown frees registered session objects while Swift wrappers may still hold
their raw pointers, and the upstream high-level `IshTerminal.close()` can race
its indefinitely blocking read pump. PocketRoot must preserve these controls,
which the current one-shot foundation implements where applicable:

- serialize boot, command, session, and shutdown operations;
- keep blocking IshEmbed calls off the main and Swift cooperative executors;
- maintain an explicit registry of live sessions;
- use bounded reads so cancellation can be observed;
- close and release every session before native shutdown; and
- avoid the upstream high-level `IshTerminal` wrapper until its close/read
  ownership is proven safe.

The current adapter reserves the single process owner before native boot,
serializes blocking native operations, allows one one-shot command at a time,
rejects invalid or effectively unbounded timeouts, streams output through
independent stdout/stderr limits, and prevents shutdown from overtaking a live
command. Interactive session ownership remains unimplemented.

The first Experimental increment is intentionally limited to boot, one-shot
commands, and terminal shutdown semantics. Interactive PTY support remains a
separate gate.

## Licensing and distribution constraints

The audited package repository contains GPL SPDX identifiers and states in its
README that the project follows GPL-3.0, but it does not contain complete
top-level `LICENSE` or `NOTICE` files. The pinned iSH submodule contains its own
GPL license text and `LICENSE.IOS` terms.

The released Alpine RootFS contains packages under GPL-2.0-only, GPL-2.0-or-
later, Apache-2.0, MPL-2.0, MIT, BSD, and Zlib licenses, but the release asset
does not contain a complete license bundle, NOTICE set, or SBOM. Static linking
and RootFS distribution therefore remain blocked until PocketRoot's license is
confirmed compatible and all corresponding-source and notice obligations are
reviewed and fulfilled.

The App Store policy gate is independent of the GPL/App Store language in
`LICENSE.IOS`. Alpine's `apk` can download, install, and execute additional
code, which may fall within App Review Guideline 2.5.2. Bundling the reviewed
RootFS is safer than downloading it on first launch, but it does not remove the
package-manager policy question. See the current
[Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Gate status

Status as of 2026-07-21:

| Gate | Status | Evidence or exit condition |
| --- | --- | --- |
| iOS 18 baseline | Passed | Package and demo target iOS 18.0 |
| Immutable package revision | Passed | Exact fork commit recorded above |
| Artifact integrity | Passed for audited assets | Both release digests independently verified |
| iOS 18 arm64 Simulator link | Passed | Minimal consumer linked successfully |
| iOS 18.2 Simulator boot and `uname -m` | Passed | Exit 0, output `aarch64` |
| Experimental one-shot adapter foundation | Passed | Host contract tests and complete arm64 final links pass |
| Native adapter behavior on iOS 18 Simulator | Passed | Repository smoke passed all 13 preparation, command, recovery, and shutdown checks |
| Verified RootFS installer and recovery foundation | Passed | Real archive, private snapshot, install, reuse, corruption, concurrency, rollback, and interrupted recovery pass |
| Runtime/RootFS composition | Passed | Caller-supplied local archive prepares one version-aligned system |
| Default VM and post-boot health check | Not started | Guest context, `aarch64`, and Alpine identity must gate `ready` |
| Interactive PTY lifecycle | Not started | Session registry, bounded reads, resize, signals, and cancellation required |
| Physical iPhone and iPad | Blocked | No physical device was available during audit |
| Minimum Xcode 16 native compatibility | Not started | Repeat final-link and behavior checks with the declared minimum toolchain |
| License, NOTICE, corresponding source, and SBOM | Blocked | Complete distribution bundle and legal review required |
| App Store 2.5.2 review | Blocked | Distribution position and package-manager behavior require review |

Production, TestFlight, and public binary distribution must remain disabled
until every blocked distribution gate has an explicit disposition.

## Consequences

This decision lets PocketRoot validate the runtime behind a narrow module while
keeping the existing placeholder system safe for default clients. It also
accepts an additional binary supply-chain dependency, arm64-only CI constraints,
an irreversible in-process lifecycle, and substantial compliance work.

The decision must be revisited before changing the pinned revision, mirroring
the binary into the user's fork, enabling interactive sessions, or distributing
a binary outside local development.
