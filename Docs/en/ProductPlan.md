# PocketRoot Product Plan

[简体中文](../ProductPlan.md) | [English](ProductPlan.md) | [Documentation](README.md)

## Vision

PocketRoot aims to let an iOS application embed an ARM64 Linux guest through explicit, bounded, and auditable Swift APIs. The first useful capability is controlled one-shot command execution; interactive terminal support follows only after PTY lifecycle ownership is proven.

PocketRoot is not a full iSH app fork or a general virtualization platform. It separates runtime, RootFS, command, terminal UI, and host lifecycle concerns into reusable modules with supply-chain and release gates encoded in the repository.

## Target users

- iOS developers building offline Linux tooling, diagnostics, developer features, or controlled shell workflows.
- Runtime and terminal maintainers evolving iSH, RootFS, PTY, SwiftTerm, concurrency, and lifecycle independently from product UI.
- Security, compliance, and release owners who need exact upstream, artifact, license, and App Store status.

## Core scenarios

1. Prepare a reviewed Alpine fakefs, boot the runtime, execute a bounded shell command, and consume exit code, signal, stdout, and stderr.
2. Add an interactive terminal after session input, output, resize, signal, EOF, cancellation, and shutdown ownership are safe.
3. Reuse or recover a verified local Linux environment without allowing partial installation to replace the last valid version.
4. Pin every external input by commit, nested gitlink, size, and SHA-256.

## Product value

- Application code uses PocketRoot APIs instead of holding iSH native objects.
- Experimental native binaries are never linked by the default product.
- The caller owns network retrieval and authorization; PocketRoot never downloads a RootFS implicitly.
- The executor for blocking native work, process ownership, the post-establishment read-loop deadline, and Swift result buffers have explicit boundaries; end-to-end native control-path time bounds and transport-backlog backpressure remain open gates.
- Build evidence, hashes, constraints, and release gates are traceable from the repository.

## Scope

### Current

- iOS 18+, arm64 iPhone/iPad and arm64 iOS Simulator builds.
- Modular Swift Package APIs and a UIKit demonstration shell.
- Caller-supplied local RootFS archives.
- iSH boot and bounded one-shot shell commands.
- A default post-boot guest identity gate.
- Secure RootFS installation and recovery.
- Experimental final-link and Simulator smoke validation.

### Planned

- Application-specific guest tool, network, and data health checks.
- Real runtime injection into the Demo.
- Interactive `PocketRootSession`, PTY, and SwiftTerm.
- A soft shutdown or an explicit decision to accept host-process exit.
- Physical-device lifecycle, memory, performance, and fault testing.
- Controlled distribution after all compliance gates are satisfied.

### Non-goals

- A macOS iSH guest or x86_64 Simulator support.
- Multiple parallel iSH kernels.
- Default network RootFS downloads or unreviewed artifacts.
- Browser automation, agents, MCP, or cloud command orchestration.
- Private APIs, sandbox escape, or App Store policy bypass.
- Production, TestFlight, or public binary distribution before gate closure.

## Product layers

| Layer | Product |
| --- | --- |
| Public model and coordination | `PocketRootCore` |
| RootFS resources and installation | `PocketRootResources` |
| Terminal UI foundation | `PocketRootTerminal` |
| Safe default umbrella | `PocketRoot` |
| Experimental native adapter | `PocketRootIshRuntime` |
| Experimental RootFS/runtime composition | `PocketRootIshRuntimeIntegration` |

The umbrella product exports Core, Resources, and Terminal only. Native products are explicit opt-ins.

## Release stages

### Foundation

Package boundaries, iOS 18 baseline, UIKit Demo, XcodeGen, scripts, CI, and safe placeholder behavior.

### Experimental Runtime

Immutable dependency evidence, secure RootFS recovery, arm64 final links, Simulator smoke, and explicit open gates.

### Developer Preview

Proposed exit criteria: signed iPhone/iPad runs, minimum-Xcode native verification, a continuously passing base identity gate plus application health policy, prepared-system Demo injection, minimum viable PTY/SwiftTerm flow, and a decided shutdown contract.

### Beta / Distribution Candidate

Proposed exit criteria: lifecycle and resource hardening, reproducible artifacts, complete license/NOTICE/source/SBOM material, security review, and a resolved App Store 2.5.2 position.

Dynamic completion is maintained only in the [roadmap](Roadmap.md).

## Success metrics

During development, PocketRoot uses verifiable engineering outcomes rather
than download counts:

- A new integrator can build the project, select the appropriate products, and
  run a one-shot command using only the repository documentation.
- Every external artifact has an immutable source, size, hash, and audit record.
- Runtime or RootFS changes must pass their corresponding unit, real-asset,
  final-link, and smoke gates.
- A failed installation cannot damage the last verified RootFS.
- After native control-path, cancellation, and backlog hardening, blocked writes
  or unbounded output cannot leave a command occupying the process indefinitely;
  until then, those gaps remain explicit gates.
- Every production blocker has an actionable exit criterion in the roadmap.
- Links, commands, and critical facts remain synchronized between the Chinese
  and English documentation.

## Principles

1. Safe by default; Experimental by explicit choice.
2. The caller owns network and asset-authorization policy.
3. Immutable inputs over moving convenience versions.
4. Prove lifecycle ownership before terminal UI integration.
5. Preserve the last verified state on failure.
6. Simulator evidence is not physical-device or distribution evidence.
7. Put critical constraints before usage examples.

## Main risks

| Risk | Strategy |
| --- | --- |
| Native shutdown exits the host app | Keep Experimental; accept the contract or rebuild a soft-shutdown artifact |
| Limited XCFramework slices | Publish the arm64 support matrix and require final links |
| Complex RootFS licensing | Do not commit or bundle; pin hashes and block distribution |
| Process-global iSH singleton | Process ownership gate and serial native executor |
| PTY pointer and close races | Delay SwiftTerm until registry, bounded reads, and close order are proven |
| App Store downloaded-code policy | Separate Guideline 2.5.2 review |
| Documentation drift | Designated sources of truth and bilingual checks |

## Related documents

- [Roadmap](Roadmap.md)
- [Architecture](Architecture.md)
- [Integration guide](IntegrationGuide.md)
- [Release and compliance](ReleaseCompliance.md)
- [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md)
