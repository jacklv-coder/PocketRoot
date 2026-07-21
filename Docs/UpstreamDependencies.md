# Upstream Dependency Inventory

This inventory records the exact external inputs accepted for PocketRoot's
Experimental runtime work. Branch names and unverified release aliases are not
valid dependency pins.

Audit date: 2026-07-21

## IshEmbed package

| Field | Audited value |
| --- | --- |
| Consumer repository | `https://github.com/jacklv-coder/ish-arm64-pkg.git` |
| Fork parent | `https://github.com/Lolendor/ish-arm64-pkg.git` |
| Exact revision | `6f96f02c71830914c2a608258a26a8ef0833d026` |
| Parent release correspondence | `v0.3.3` peeled commit |
| Fork tags at audit | None |
| Fork releases at audit | None |
| Swift product | `IshEmbed` |
| Manifest platforms | iOS 14, macOS 12 |
| Native dependency support | iOS arm64 device and arm64 Simulator only |
| System link dependency | `sqlite3` |

The package is consumed with an exact revision:

```swift
.package(
    url: "https://github.com/jacklv-coder/ish-arm64-pkg.git",
    revision: "6f96f02c71830914c2a608258a26a8ef0833d026"
)
```

At the audited revision, the fork still downloads its binary target from the
parent repository's `v0.3.3` GitHub Release. Forking the Git source did not
mirror the release assets, and the included release script is hard-coded to
the parent repository. The dependency is therefore pinned but not yet
self-hosted.

## iSH source submodule

| Field | Audited value |
| --- | --- |
| Repository | `https://github.com/Lolendor/ish-arm64.git` |
| Path in package | `third_party/ish` |
| Exact gitlink | `2f075626049d989dc9ac350a35c09f0b18930ffc` |
| Recorded branch | `embed-chroot-containment` |

The recorded branch was two commits ahead of the pinned gitlink during the
audit. Those commits are not present in the `v0.3.3` XCFramework and must not
be substituted without a new source and binary audit.

The iSH submodule recursively identifies additional source dependencies,
including `ish-app/libapps` and `libarchive/libarchive`. The Linux headers
submodule is configured with `update = none`. A reproducible source archive
must record every gitlink rather than relying on recursive branch checkout.

## Binary artifacts

Source release:
`https://github.com/Lolendor/ish-arm64-pkg/releases/tag/v0.3.3`

| Artifact | Size at audit | SHA-256 | Required use |
| --- | ---: | --- | --- |
| `libIshKernel.xcframework.zip` | 2,121,180 bytes | `f747c2e85c3b6082e102fb45aa62797f52146a3bc5eb1a0c386b74bc156d4fca` | SwiftPM binary target |
| `fs.tar.gz` | 6,581,376 bytes | `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4` | Candidate fakefs seed |

The XCFramework contains:

| Library identifier | Architecture | Platform variant | Minimum OS |
| --- | --- | --- | --- |
| `ios-arm64` | arm64 | iOS device | 14.0 |
| `ios-arm64-simulator` | arm64 | iOS Simulator | 14.0 |

It contains no x86_64 Simulator or macOS library. The object load commands
record SDK 26.2. Linking was independently verified with Xcode 26.1.1 for an
iOS 18 deployment target.

PocketRoot fails closed if a caller-supplied, bundled, or CI-fetched artifact
does not match the exact size and digest in its committed manifest. SwiftPM
validates the XCFramework checksum; PocketRoot separately validates the RootFS
before materialization.

## Alpine RootFS

The audited fakefs release is based on Alpine 3.19.1 aarch64. Its source
minirootfs is:

```text
alpine-minirootfs-3.19.1-aarch64.tar.gz
SHA-256 7ef5eef3a5b1d198dfb1610cde1ef5b0755ff5d838fb1e5e1b9f42b59214820f
```

The upstream build script accepts an empty `ALPINE_SHA256` and merely records
the downloaded digest in that configuration. Any PocketRoot-controlled rebuild
must set and verify the expected digest above, or a deliberately reviewed
replacement digest.

The release contains a fakefs directory with `meta.db` and `data/`, including
an embedded `/sbin/ishsv` supervisor and a duplicated VM template under
`/srv/vms/.template`. SQLite `PRAGMA integrity_check` returned `ok` for the
audited extracted database.

Installed packages and declared license families include:

| Components | Declared license families |
| --- | --- |
| Alpine baselayout, apk-tools, BusyBox, scanelf | GPL-2.0-only |
| musl-utils | MIT, BSD-2-Clause, GPL-2.0-or-later |
| musl and Alpine keys | MIT/BSD variants |
| OpenSSL libraries | Apache-2.0 |
| CA certificate bundle | MPL-2.0 and MIT |
| zlib | Zlib |

The RootFS archive did not contain a complete license bundle, NOTICE set, or
machine-readable SBOM. Those are mandatory distribution work items, along with
corresponding-source availability for copyleft packages.

The build script also writes public DNS resolvers into both the base filesystem
and VM template. Product integration must decide whether to preserve that
behavior, derive resolver configuration at runtime, or expose a user-controlled
policy before shipping.

## Validation record

The following checks passed for the pinned inputs:

- repository fork relationship and commit identity;
- release asset digest verification;
- XCFramework architecture and minimum-version inspection;
- final arm64 iOS 18 Simulator link of the complete PocketRoot integration graph;
- final unsigned arm64 iOS 18 device link of that graph;
- real release archive validation, secure extraction, atomic installation, and
  materialized fakefs validation;
- caller-path replacement isolation, promotion rollback, and interrupted
  commit/rollback recovery tests;
- iOS 18.2 Simulator fakefs boot; and
- the repository-owned PocketRoot adapter smoke on an iOS 18.2 arm64 Simulator.

The adapter smoke passed 13 checks through the complete composition graph:
verified v0.3.3 RootFS preparation, boot, `aarch64`, Alpine 3.19.1, working
directory, environment, split stdout/stderr with exit code 7, merged stderr, a
100 ms timeout and post-timeout recovery, a 64-byte stdout limit and
post-limit recovery, and terminal shutdown. For the final check, the report was
persisted before shutdown and the host script verified that the pinned iSH
`_exit(0)` path terminated the smoke App process successfully.

The following checks have not passed yet:

- signed build and execution on a physical iPhone;
- execution on a physical iPad;
- host-process-safe native shutdown; the pinned artifact deliberately reaches
  `_exit(0)`, and any soft-shutdown replacement requires a rebuilt, re-audited
  XCFramework with bounded thread joins;
- native final-link and behavior checks with the declared minimum Xcode 16
  toolchain;
- complete PTY, signal, resize, cancellation, and shutdown lifecycle;
- memory and jetsam behavior under sustained workloads;
- complete license/NOTICE/SBOM and corresponding-source review; and
- App Store Review Guideline 2.5.2 disposition.

## Update procedure

Any dependency update must be handled as a deliberate supply-chain change:

1. resolve a full immutable package commit and every nested gitlink;
2. review source changes from the currently recorded revisions;
3. rebuild or obtain artifacts whose source correspondence is documented;
4. independently compute and record all artifact hashes;
5. inspect every XCFramework slice and minimum deployment version;
6. link and boot on the minimum iOS Simulator runtime;
7. repeat boot, command, PTY, cancellation, and shutdown tests on physical
   iPhone and iPad hardware;
8. regenerate license, NOTICE, corresponding-source, and SBOM material; and
9. update
   [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md) before changing the
   production pin.

No branch, moving tag, locally cached binary, or unrecorded RootFS may bypass
this procedure.
