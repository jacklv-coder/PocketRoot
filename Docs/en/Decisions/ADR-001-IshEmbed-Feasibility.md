# ADR-001: Adopt IshEmbed as an Experimental ARM64 Runtime

[简体中文](../../Decisions/ADR-001-IshEmbed-Feasibility.md) | [English](ADR-001-IshEmbed-Feasibility.md) | [Documentation](../README.md)

- Status: Accepted for Experimental integration only
- Date: 2026-07-21
- Baseline: iOS 18.0, arm64
- Scope: runtime feasibility, supply-chain pinning, and release gates

This ADR records the decision and evidence snapshot. Dynamic completion belongs in the [roadmap](../Roadmap.md); exact artifact facts belong in the [upstream inventory](../UpstreamDependencies.md).

## Context

PocketRoot needs an embeddable ARM64 Linux runtime that boots an Alpine fakefs, executes one-shot commands, and may later provide PTY sessions.

The audited candidate is the user's `ish-arm64-pkg` fork. It combines Swift/C source, a prebuilt static XCFramework, a separate RootFS, a pinned iSH submodule, and further nested dependencies. It is young, pre-1.0, and does not yet provide one complete source/binary/RootFS distribution record.

## Decision

Adopt IshEmbed behind the separate Experimental `PocketRootIshRuntime` product. Add `PocketRootIshRuntimeIntegration` to compose verified local RootFS materialization with that adapter. Neither product is exported by the safe `PocketRoot` umbrella; the default system remains a placeholder.

Pin:

```text
Repository: https://github.com/jacklv-coder/ish-arm64-pkg.git
Revision:   6f96f02c71830914c2a608258a26a8ef0833d026
Product:    IshEmbed
iSH gitlink: 2f075626049d989dc9ac350a35c09f0b18930ffc
```

Do not follow a branch or use semantic-version selection against a fork that had no audited tag/release.

## Alternatives

- Default umbrella integration: rejected because every consumer would link the arm64-only binary and inherit unresolved lifecycle/compliance risk.
- Placeholder only until every gate closes: rejected because real adapter evidence would not be developed.
- Direct IshEmbed use in the app: rejected because singleton, pointers, blocking calls, RootFS, and UI policy would leak into product code.
- Explicit Experimental isolation: accepted.

## Evidence

The package exposes CIshEmbed, an IshKernel binary, Swift APIs, and RootFS-dependent tests. The released XCFramework has only arm64 iOS device and arm64 Simulator slices; no macOS or x86_64 Simulator.

Independent digests:

| Artifact | SHA-256 |
| --- | --- |
| `libIshKernel.xcframework.zip` | `f747c2e85c3b6082e102fb45aa62797f52146a3bc5eb1a0c386b74bc156d4fca` |
| `fs.tar.gz` | `be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4` |

The Alpine 3.19.1 aarch64 source minirootfs digest is `7ef5eef3a5b1d198dfb1610cde1ef5b0755ff5d838fb1e5e1b9f42b59214820f`.

An iOS 18 consumer final-linked for arm64 Simulator and unsigned device. An iOS 18.2 Simulator boot returned exit 0 and `aarch64` from uname.

Repository integration added exact package resolution, full-graph final links,
secure RootFS snapshot/extraction/validation, journal-protected multi-step
same-volume promotion with rollback and inferred interrupted recovery,
real-asset tests, and a native smoke covering preparation, guest identity,
command context, streams, timeout/output recovery, and shutdown. See
[testing](../Testing.md) and [RootFS security](../RootFS.md).

Static inspection found no MAP_JIT, JIT entitlement, private framework path, or private entitlement in the pinned consumer. This is not an App Review guarantee.

## Runtime constraints

IshEmbed is process-global. PocketRoot uses one process owner, serial native execution, lifecycle state closure before suspension, one in-flight command, bounded reads, stream limits, and no shutdown while a command is active.

That lifecycle state is internal to the adapter. Public
`PocketRootSystem.state` refreshes only after `boot()` / `shutdown()` returns
or throws; it does not expose real-time transient progress during the awaited
call.

RootFS promotion is likewise not described as one atomic replacement. Its
journal stores no phase; it records expected and previous install/current
facts, then recovery infers commit or rollback from an expected-final match,
backup presence, and prior-install facts after individual same-volume renames.
The archive's `fs/` directory itself becomes
the final version directory, so `rootfs/<version>` directly contains
`meta.db`, `data/`, and `.pocketroot-rootfs.json`. A valid version can be reused
even when `current.json` is missing or mismatched; reuse repairs it.

The pinned guest halt path reaches `_exit(0)`. Native shutdown terminates the host app and normally never returns. The runtime cannot restart in-process. Before default integration, the product must explicitly accept that contract or rebuild a soft-shutdown artifact with bounded joins, new source/binary pins, and repeated Simulator/physical tests.

PTY support is deferred because native session pointer ownership and high-level terminal read/close races are not yet proven. A live registry, bounded reads, input/resize/signal/EOF, cancellation, idempotent close, and close-before-shutdown are prerequisites.

## Distribution constraints

The package and iSH sources carry GPL terms; the RootFS contains GPL, Apache, MPL, MIT, BSD, and Zlib families. Complete license/NOTICE, corresponding-source, and SBOM material is absent. Alpine `apk` also creates an independent App Store Guideline 2.5.2 question.

Distribution remains blocked. See [release and compliance](../ReleaseCompliance.md).

## Consequences

The project gains real evidence behind a narrow adapter while default clients stay safe. It accepts an additional binary supply chain, arm64-only native validation, process-terminal shutdown, deferred PTY/Demo integration, and substantial compliance work.

Revisit this decision when changing pins/artifacts/RootFS, adding soft shutdown or PTY/SwiftTerm, exporting Experimental products by default, or enabling any external distribution. Dynamic gates remain in the [roadmap](../Roadmap.md).
