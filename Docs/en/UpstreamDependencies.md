# Upstream Dependency Inventory

[简体中文](../UpstreamDependencies.md) | [English](UpstreamDependencies.md) | [Documentation](README.md)

This is the sole source of truth for immutable revisions, nested gitlinks,
artifact URLs, sizes, and SHA-256 values used by the Experimental runtime.
Branches, moving tags, unverified release aliases, and local caches are not pins.

Audit date: 2026-07-31

## 1. IshEmbed Swift package

| Field | Audited value |
| --- | --- |
| Repository | `https://github.com/jacklv-coder/ish-arm64-pkg.git` |
| Exact wrapper revision | `2419f736b271beb52a699b2f780027cf280472b8` |
| SwiftPM package release | `0.4.0-abi.9.1` immutable prerelease |
| Binary asset release | `v0.4.0-abi.9` prerelease |
| Tag peeled commit | `2419f736b271beb52a699b2f780027cf280472b8` |
| Swift product | `IshEmbed` |
| Manifest platform | iOS 18.0 |
| Native slices | iOS arm64 device and arm64 Simulator |
| System link dependency | `sqlite3` |

`Package.swift` uses an immutable exact SemVer while `Package.resolved` also
records its peeled commit:

```swift
.package(
    url: "https://github.com/jacklv-coder/ish-arm64-pkg.git",
    exact: "0.4.0-abi.9.1"
)
```

Exact version `0.4.0-abi.9.1` peels to revision
`2419f736b271beb52a699b2f780027cf280472b8`, the ABI.9
release commit. It contains ABI.7's atomic guest `RENAME_NOREPLACE` C/Swift
APIs and makes finite-session stdin write/close reuse one SPAWN absolute
deadline, while `Package.swift` pins the public, independently verified ABI.9 asset built from that source by
URL/checksum. The peeled tag, Release target, and consumed package revision are
identical. `0.4.0-abi.9.1` is an asset-free GitHub immutable Release that locks
the package tag; the existing `v0.4.0-abi.9` continues to serve the
checksum-pinned binary and corresponding-source assets. The package repository
keeps an absolute SSH-over-443 submodule URL;
GitHub CI without an SSH private key applies a public read-only HTTPS rewrite
only while checking out source.

## 2. iSH source gitlink

| Field | Audited value |
| --- | --- |
| Repository | `https://github.com/jacklv-coder/ish-arm64.git` |
| Package path | `third_party/ish` |
| Exact gitlink | `3d0b4f6f55108f6d602ac6a2c86df555935b979d` |
| Recorded branch | `embed-chroot-containment` |

The corresponding-source archive records the parent package revision, this
gitlink, Zig 0.16.0, and the musl source used by the static supervisor.
Recursive branch checkout is not a substitute for these exact identities.

## 3. v0.4.0-abi.9 assets

Release:
`https://github.com/jacklv-coder/ish-arm64-pkg/releases/tag/v0.4.0-abi.9`

| Artifact | Size | SHA-256 | Use |
| --- | ---: | --- | --- |
| `libIshKernel.xcframework.zip` | 2,460,178 bytes | `c68f47587686000cf125105ac25eaf4d79de6dbd1715d39838bfb7d35abc72f8` | SwiftPM binary target |
| `IshEmbed-corresponding-source.tar.gz` | 2,391,682 bytes | `8e5d3d56056ece402c09e5f1b3cbdaad75f2f8697ed0e41eaeecd7c403f26557` | Corresponding source |

The XCFramework contains only `ios-arm64` and `ios-arm64-simulator`, both
arm64 with an iOS 18.0 minimum. It has no x86_64 Simulator or macOS slice.
SwiftPM validates the zip checksum. The release transaction also verified:

- the peeled tag, release target, and default branch all identify the release commit;
- the public release is a prerelease, not a draft, and has exactly two assets;
- both public assets redownload with the recorded digests;
- device and Simulator Mach-O metadata, ABI symbols, and final iOS 18 links; and
- 16 passing arm64 iOS Simulator binaryTarget tests, 5 expected RootFS skips,
  and 0 failures.
- 57 passing native tests, including successful atomic no-replace rename,
  `EEXIST` collision, and timeout coverage;
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

## 4. SwiftTerm

| Field | Audited value |
| --- | --- |
| SwiftPM mirror repository | `https://github.com/jacklv-coder/SwiftTerm.git` |
| Upstream repository | `https://github.com/migueldeicaza/SwiftTerm.git` |
| Exact revision | `dd2fb8ac5b861e7bf617c872895e338f38165648` |
| Upstream tag | `v1.15.0` |
| Immutable package release | `1.15.0-pocketroot.1` |
| Swift product | `SwiftTerm` |
| License | MIT |
| License copy | `ThirdPartyNotices/SwiftTerm-LICENSE.txt` |

The PocketRoot fork's immutable Release mirrors the exact commit from upstream
`v1.15.0` and attaches no binary assets. The release gate checks both package
Releases' `immutable` state through the GitHub API and revalidates their remotely
peeled tag commits. `PocketRootTerminal` links this product only on iOS.
SwiftTerm's manifest also
resolves `swift-argument-parser`, but the library target consumed by PocketRoot
does not depend on or link that product.

## 5. Separately pinned Alpine RootFS

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

## 6. Current behavior and validation boundary

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
- atomic no-replace guest rename for files and directories, preserving both
  sides and returning `EEXIST` when the destination exists.

PocketRoot remains Experimental. Open gates include:

- physical iPad execution;
- physical-device interactive read/close, resize, signal, and page lifecycle;
- sustained workload, peak memory, and jetsam behavior;
- generated RootFS package inventory, SPDX SBOM, source locators, and default
  configuration are present, while the complete license/NOTICE and
  corresponding-source bundles remain open;
- the maximal Experimental engineering-composition inventory/SPDX SBOM binds
  the ABI.9 assets, iSH gitlink, supervisor musl source, and external RootFS
  recorded here, while no final App archive has been scanned; and
- an App Store Review Guideline 2.5.2 decision.

## 7. Update procedure

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
