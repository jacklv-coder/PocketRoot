# Upstream Dependency Inventory

[简体中文](../UpstreamDependencies.md) | [English](UpstreamDependencies.md) | [Documentation](README.md)

This is the sole source of truth for immutable revisions, nested gitlinks,
artifact URLs, sizes, and SHA-256 values used by the Experimental runtime.
Branches, moving tags, unverified release aliases, and local caches are not pins.

Audit date: 2026-07-23

## 1. IshEmbed Swift package

| Field | Audited value |
| --- | --- |
| Repository | `https://github.com/jacklv-coder/ish-arm64-pkg.git` |
| Exact revision | `4e311bcea4fe806491e76a23c0e4caeeb1c513bf` |
| Release | `v0.4.0-abi.1` prerelease |
| Tag peeled commit | `4e311bcea4fe806491e76a23c0e4caeeb1c513bf` |
| Swift product | `IshEmbed` |
| Manifest platform | iOS 18.0 |
| Native slices | iOS arm64 device and arm64 Simulator |
| System link dependency | `sqlite3` |

Both `Package.swift` and `Package.resolved` pin the full revision:

```swift
.package(
    url: "https://github.com/jacklv-coder/ish-arm64-pkg.git",
    revision: "4e311bcea4fe806491e76a23c0e4caeeb1c513bf"
)
```

This revision is the release commit that changes only the release URL and
checksum. Its parent, `2858cbf40d9aa10264773f96a6b598703a5533ea`,
contains the PR-reviewed native lifecycle, root `/proc`, and Codex CLI path
cleanup changes.

## 2. iSH source gitlink

| Field | Audited value |
| --- | --- |
| Repository | `https://github.com/jacklv-coder/ish-arm64.git` |
| Package path | `third_party/ish` |
| Exact gitlink | `576ffaf2574310b5fb2d148aab39ddcd2b8fe67d` |
| Recorded branch | `embed-chroot-containment` |

The corresponding-source archive records the parent package revision, this
gitlink, Zig 0.16.0, and the musl source used by the static supervisor.
Recursive branch checkout is not a substitute for these exact identities.

## 3. v0.4.0-abi.1 assets

Release:
`https://github.com/jacklv-coder/ish-arm64-pkg/releases/tag/v0.4.0-abi.1`

| Artifact | Size | SHA-256 | Use |
| --- | ---: | --- | --- |
| `libIshKernel.xcframework.zip` | 2,446,031 bytes | `5bd6f691ed2af1e157118b26f62b962a3568ebe96a608d75f5b2f661d07e1450` | SwiftPM binary target |
| `IshEmbed-corresponding-source.tar.gz` | 2,350,872 bytes | `52b10b3b1dfedf221b4af37b125cde9b5fd03cc819944ab2d77d9893f6a76122` | Corresponding source |

The XCFramework contains only `ios-arm64` and `ios-arm64-simulator`, both
arm64 with an iOS 18.0 minimum. It has no x86_64 Simulator or macOS slice.
SwiftPM validates the zip checksum. The release transaction also verified:

- the peeled tag, release target, and default branch all identify the release commit;
- the public release is a prerelease, not a draft, and has exactly two assets;
- both public assets redownload with the recorded digests;
- device and Simulator Mach-O metadata, ABI symbols, and final iOS 18 links; and
- 12 passing arm64 iOS Simulator binaryTarget tests, 5 expected RootFS skips,
  and 0 failures.
- the complete PocketRoot Experimental graph final-linked for arm64 Simulator
  and unsigned device; and
- an iOS 18.2 Simulator passed the 13-check native smoke with the pinned v0.3.3
  RootFS, returning `.terminated` from shutdown and `restartRequired` afterward.

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
- one valid boot/shutdown lifecycle per host process;
- typed supervisor and transport failures, with normal guest exit 17 no longer
  confused with broken pipe;
- a 4 MiB/4096-frame native output backlog per session;
- a 4 MiB/256-frame total control budget with lifecycle reserve;
- bounded stdin/log queues, complete session close, and instance fail-close
  when cleanup cannot be proven;
- root `/proc` mounted before supervisor startup; and
- digest verification for the default bundled supervisor.

PocketRoot remains Experimental. Open gates include:

- physical iPad execution;
- native final-link and behavior with minimum Xcode 16;
- complete Swift Task-to-native command cancellation;
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
