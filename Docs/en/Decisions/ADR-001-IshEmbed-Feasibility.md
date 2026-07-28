# ADR-001: Adopt IshEmbed as an Experimental ARM64 Runtime

[简体中文](../../Decisions/ADR-001-IshEmbed-Feasibility.md) | [English](ADR-001-IshEmbed-Feasibility.md) | [Documentation](../README.md)

- Status: Accepted for Experimental integration only
- Date: 2026-07-21
- Amended: 2026-07-28 to complete low-level PTY ownership and SwiftTerm integration on pinned `v0.4.0-abi.6`
- Baseline: iOS 18.0, arm64
- Scope: runtime feasibility, supply-chain pinning, and release gates

This ADR records the decision and evidence snapshot. Dynamic completion belongs in the [roadmap](../Roadmap.md); exact artifact facts belong in the [upstream inventory](../UpstreamDependencies.md).

## Context

PocketRoot needs an embeddable ARM64 Linux runtime that boots an Alpine fakefs,
executes one-shot commands, and provides Experimental PTY sessions.

The audited candidate is the user's `ish-arm64-pkg` fork. It combines Swift/C source, a prebuilt static XCFramework, a separate RootFS, a pinned iSH submodule, and further nested dependencies. It is young, pre-1.0, and does not yet provide one complete source/binary/RootFS distribution record.

## Decision

Adopt IshEmbed behind the separate Experimental `PocketRootIshRuntime` product. Add `PocketRootIshRuntimeIntegration` to compose verified local RootFS materialization with that adapter. Neither product is exported by the safe `PocketRoot` umbrella; the default system remains a placeholder.

Pin:

```text
Repository: https://github.com/jacklv-coder/ish-arm64-pkg.git
Revision:   38d25d6f8726145e7e988172f12000020d89a638
Product:    IshEmbed
iSH gitlink: c36dfd25462737b45559eb48d4b09f799471572e
```

Do not follow a branch or moving tag. The prerelease tag identifies the
release; consumption still pins the full revision.

## Alternatives

- Default umbrella integration: rejected because every consumer would link the arm64-only binary and inherit unresolved lifecycle/compliance risk.
- Placeholder only until every gate closes: rejected because real adapter evidence would not be developed.
- Direct IshEmbed use in the app: rejected because singleton, pointers, blocking calls, RootFS, and UI policy would leak into product code.
- Explicit Experimental isolation: accepted.

## Evidence

The package exposes CIshEmbed, an IshKernel binary, Swift APIs, and RootFS-dependent tests. The released XCFramework has only arm64 iOS device and arm64 Simulator slices; no macOS or x86_64 Simulator. SwiftPM cannot condition the product dependency on destination architecture, so App targets selecting the Experimental product must exclude x86_64 at build time; `isAvailable` is only a post-link probe.

Independent digests:

| Artifact | SHA-256 |
| --- | --- |
| `libIshKernel.xcframework.zip` | `049422af47334a323dbe26fa7eb431160ef0742495783bd50d1c3949dd0c6720` |
| `IshEmbed-corresponding-source.tar.gz` | `a94dbfa58289270ec83aefc5ed1632198290956fd5d1ca381e90dd2ec7f518fa` |
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

That lifecycle state is internal to the adapter. Lifecycle calls publish their
final state; completed commands publish only stable states. A fail-closed
command publishes `.failed`, but a reentrant command does not expose transient
progress from an awaited lifecycle call.

RootFS promotion is likewise not described as one atomic replacement. Its
journal stores no phase; it records expected and previous install/current
facts, then recovery infers commit or rollback from an expected-final match,
backup presence, and prior-install facts after individual same-volume renames.
The archive's `fs/` directory itself becomes
the final version directory, so `rootfs/<version>` directly contains
`meta.db`, `data/`, and `.pocketroot-rootfs.json`. A valid version can be reused
even when `current.json` is missing or mismatched; reuse repairs it.

Pinned v0.4.0-abi.6 stops the supervisor, soft-halts the embedded kernel,
performs a bounded native join, and returns to Swift. Finite streaming SPAWN
deadlines cover native instance/spawn gates and control-queue admission from
API entry, while stdin close and terminate use bounded asynchronous admission.
It retains ABI.4's internal SIGUSR1-mask fix, ABI.3's bounded fixed-size uname
copies, and the ABI.2 `/proc` lifecycle-lock fix. These maintenance changes do
not alter the public C ABI or Swift API. PocketRoot reuses one deadline from
driver entry and bridges Swift Task cancellation to a one-shot native session;
both paths return only after trusted `EXITED`, and unconfirmed cleanup fails
closed. PocketRoot publishes
`.terminated`, but process-global iSH state still prevents another boot in the
same host process. The new source, binary, checksum,
corresponding-source, Simulator, and minimum-Xcode gates passed; signed-device
and sustained-lifecycle work remains.

Those low-level prerequisites are now covered by session/runtime tests and the
Simulator smoke: a live registry, bounded reads, input/resize/signal/EOF,
cancellation, idempotent termination, and close-before-shutdown. PocketRoot
therefore owns low-level `IshSession` handles directly and connects the pinned
SwiftTerm instead of adopting the upstream high-level `IshTerminal`. Signed
target-iPhone, iPad, background/foreground, sustained-output, and accessibility
lifecycle evidence remain dynamic gates.

## Distribution constraints

The package and iSH sources carry GPL terms; the RootFS contains GPL, Apache, MPL, MIT, BSD, and Zlib families. The repository now generates a package inventory and SPDX SBOM from the pinned release asset, plus an SPDX SBOM for the maximal Experimental engineering composition; the latter does not scan a final App archive. Complete license/NOTICE and corresponding-source delivery material and a complete final-artifact SBOM remain absent. Alpine `apk` also creates an independent App Store Guideline 2.5.2 question.

Distribution remains blocked. See [release and compliance](../ReleaseCompliance.md).

## Consequences

The project gains real evidence behind a narrow adapter while default clients
stay safe. It accepts an additional binary supply chain, arm64-only native
validation, a single-lifecycle soft shutdown, Experimental PTY/SwiftTerm
integration with open device gates, and substantial compliance work.

Revisit this decision when changing pins/artifacts/RootFS, adding soft shutdown or PTY/SwiftTerm, exporting Experimental products by default, or enabling any external distribution. Dynamic gates remain in the [roadmap](../Roadmap.md).
