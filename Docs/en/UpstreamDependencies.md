# Upstream Dependency Inventory

[简体中文](../UpstreamDependencies.md) | [English](UpstreamDependencies.md) | [Documentation](README.md)

This is the sole source of truth for immutable revisions, nested gitlinks,
artifact URLs, sizes, and SHA-256 values used by the Experimental runtime.
Branches, moving tags, unverified release aliases, and local caches are not pins.

Audit date: 2026-07-24

## 1. IshEmbed Swift package

| Field | Audited value |
| --- | --- |
| Repository | `https://github.com/jacklv-coder/ish-arm64-pkg.git` |
| Exact wrapper revision | `38d25d6f8726145e7e988172f12000020d89a638` |
| Release | `v0.4.0-abi.6` prerelease |
| Tag peeled commit | `38d25d6f8726145e7e988172f12000020d89a638` |
| Swift product | `IshEmbed` |
| Manifest platform | iOS 18.0 |
| Native slices | iOS arm64 device and arm64 Simulator |
| System link dependency | `sqlite3` |

Both `Package.swift` and `Package.resolved` pin the full revision:

```swift
.package(
    url: "https://github.com/jacklv-coder/ish-arm64-pkg.git",
    revision: "38d25d6f8726145e7e988172f12000020d89a638"
)
```

Consumed revision `38d25d6f8726145e7e988172f12000020d89a638` is the ABI.6
release commit. It contains the merged Swift-marshalling deadline fix and the
native stdin-close reuse of the original SPAWN deadline, while `Package.swift`
pins the public, independently verified ABI.6 asset built from that source by
URL/checksum. The peeled tag, Release target, and consumed package revision are
identical. The package repository keeps an absolute SSH-over-443 submodule URL;
GitHub CI without an SSH private key applies a public read-only HTTPS rewrite
only while checking out source.

## 2. iSH source gitlink

| Field | Audited value |
| --- | --- |
| Repository | `https://github.com/jacklv-coder/ish-arm64.git` |
| Package path | `third_party/ish` |
| Exact gitlink | `c36dfd25462737b45559eb48d4b09f799471572e` |
| Recorded branch | `embed-chroot-containment` |

The corresponding-source archive records the parent package revision, this
gitlink, Zig 0.16.0, and the musl source used by the static supervisor.
Recursive branch checkout is not a substitute for these exact identities.

## 3. v0.4.0-abi.6 assets

Release:
`https://github.com/jacklv-coder/ish-arm64-pkg/releases/tag/v0.4.0-abi.6`

| Artifact | Size | SHA-256 | Use |
| --- | ---: | --- | --- |
| `libIshKernel.xcframework.zip` | 2,450,755 bytes | `049422af47334a323dbe26fa7eb431160ef0742495783bd50d1c3949dd0c6720` | SwiftPM binary target |
| `IshEmbed-corresponding-source.tar.gz` | 2,364,382 bytes | `a94dbfa58289270ec83aefc5ed1632198290956fd5d1ca381e90dd2ec7f518fa` | Corresponding source |

The XCFramework contains only `ios-arm64` and `ios-arm64-simulator`, both
arm64 with an iOS 18.0 minimum. It has no x86_64 Simulator or macOS slice.
SwiftPM validates the zip checksum. The release transaction also verified:

- the peeled tag, release target, and default branch all identify the release commit;
- the public release is a prerelease, not a draft, and has exactly two assets;
- both public assets redownload with the recorded digests;
- device and Simulator Mach-O metadata, ABI symbols, and final iOS 18 links; and
- 13 passing arm64 iOS Simulator binaryTarget tests, 5 expected RootFS skips,
  and 0 failures.
- the complete PocketRoot Experimental graph final-linked for arm64 Simulator
  and unsigned device; and
- an iOS 18.2 Simulator passed the 17-check native smoke with the pinned v0.3.3
  RootFS, returned byte-exact 8 MiB binary stdout beyond the backlog, recovered
  after cancelling a blocked command, returned `.terminated` from shutdown,
  returned `restartRequired` afterward, and reported a 156.5 MiB lifecycle
  `ru_maxrss` against the 256 MiB limit.
- Xcode 16.0 / iOS 18.0 SDK on an arm64 hosted runner completed real RootFS
  installation, Simulator/device final links, and the same 17-check native smoke.

This release contains **no RootFS**.

## 4. Separately pinned Alpine RootFS

PocketRoot's built-in RootFS manifest still pins the parent v0.3.3 Alpine
3.19.1 aarch64 `fs.tar.gz`. Updating the runtime does not silently replace the
guest filesystem:

| Field | Audited value |
| --- | --- |
| URL | `https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/fs.tar.gz` |
| Size | 6,581,376 bytes |
| SHA-256 | `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4` |
| Guest identity | Alpine `3.19.1`, `aarch64` |

The archive contains fakefs `meta.db`, `data/`, the older `/sbin/ishsv`, and a
VM template. In its default configuration, the new runtime verifies and
installs its own content-addressed embedded supervisor. RootFS remains
caller-supplied local input; the library does not download, commit, or bundle it.

Node.js/npm are not preinstalled by the runtime or RootFS, but callers may
explicitly install them as general guest packages. Codex CLI is not part of
the mobile architecture, and IshEmbed has no installation, provisioning, or
configuration path for it.

## 5. Current behavior and validation boundary

The pinned artifact provides:

- kernel soft-halt and bounded join, so `shutdown()` returns to Swift;
- internal SIGUSR1 unblocked on the embedded bootstrap and guest task threads,
  allowing guest signals to interrupt blocking host syscalls such as `poll`
  and `nanosleep`;
- bounded copies into the fixed 65-byte `uname` fields, preventing long host
  names from triggering a fortified-libc `SIGTRAP`, plus the ABI.2 `/proc`
  lifecycle-lock fix;
- one valid boot/shutdown lifecycle per host process;
- typed supervisor and transport failures, with normal guest exit 17 no longer
  confused with broken pipe;
- a 4 MiB/4096-frame native output backlog per session;
- a 4 MiB/256-frame total control budget with lifecycle reserve;
- finite streaming timeouts that cover the native SPAWN instance/spawn gates
  and control-queue admission from API entry, with ordered bounded asynchronous
  admission for stdin close and terminate;
- bounded stdin/log queues, complete session close, and instance fail-close
  when cleanup cannot be proven;
- root `/proc` mounted before supervisor startup; and
- digest verification for the default bundled supervisor.

PocketRoot remains Experimental. Open gates include:

- physical iPad execution;
- interactive-session read/close cancellation;
- complete PTY, resize, signal, and interactive-session lifecycle;
- sustained workload, peak memory, and jetsam behavior;
- RootFS license/NOTICE/SBOM/corresponding source; and
- an App Store Review Guideline 2.5.2 decision.

## 6. Update procedure

Every upstream update must:

1. pin a complete package commit and every nested gitlink;
2. review source changes from the current revision;
3. obtain an artifact with documented source correspondence;
4. independently record sizes and hashes;
5. inspect all slices, SDKs, and minimum deployment versions;
6. final-link arm64 Simulator and unsigned-device consumers;
7. rerun host tests, native smoke, shutdown/lifecycle, and error paths;
8. rerun signed iPhone/iPad checks when hardware is available;
9. update resolution, tests, ADR, roadmap, and compliance records; and
10. merge only after CR, CI, and all P1/P2 findings are clear.

No branch, moving tag, local binary cache, or unrecorded RootFS may bypass this
procedure.
