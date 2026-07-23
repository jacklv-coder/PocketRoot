# PocketRoot Documentation

[简体中文](../README.md) | [English](README.md) | [Project home](../../README.en.md)

This is the English documentation hub for PocketRoot. The Chinese documents at the parent paths are the primary narrative set; every maintained document has an English mirror.

## Reading paths

### Product and project owners

1. [Product plan](ProductPlan.md) for users, use cases, value, non-goals, and release definitions.
2. [Roadmap](Roadmap.md) for current completion, gates, and priorities.
3. [Release and compliance](ReleaseCompliance.md) for licensing, RootFS, SBOM, and App Store constraints.
4. [ADR-001](Decisions/ADR-001-IshEmbed-Feasibility.md) for the Experimental IshEmbed decision.

### Application integrators

1. [Getting started](GettingStarted.md) for prerequisites, builds, and the Demo.
2. [Integration guide](IntegrationGuide.md) for Swift Package product selection and the `prepare → boot → execute` flow.
3. [Lightweight Agent Loop](Agent.md) for upper-layer model/tool orchestration, resource bounds, and safety principles.
4. [RootFS security](RootFS.md) for archive ownership, verification, installation, storage, and recovery.
5. [Troubleshooting](Troubleshooting.md) for architecture, hash, state, timeout, and shutdown issues.

### Maintainers

1. [Technical Learning Guide](TechnicalGuide.md) for a system-wide model of the repositories, modules, call paths, and verification strategy.
2. [Architecture](Architecture.md) for module boundaries, dependency direction, concurrency, and lifecycle.
3. [Implementation](Implementation.md) for end-to-end call paths, source mapping, and invariants.
4. [Testing](Testing.md) for unit, real-asset, final-link, CI, and native smoke coverage.
5. [Upstream dependencies](UpstreamDependencies.md) for immutable revisions, gitlinks, hashes, and update procedure.
6. [Contributing](../../CONTRIBUTING.en.md) for branch, validation, and bilingual-document rules.
7. [Changelog](../../CHANGELOG.en.md) for unreleased behavior and API changes.

## Sources of truth

| Document | Authoritative responsibility |
| --- | --- |
| [Technical Learning Guide](TechnicalGuide.md) | Cross-repository mental model, source entry points, verification mapping, and learning order |
| [Product plan](ProductPlan.md) | Users, scenarios, value, MVP, and non-goals |
| [Roadmap](Roadmap.md) | Dynamic status, gates, and next work |
| [Architecture](Architecture.md) | Current module, dependency, concurrency, and lifecycle design |
| [Implementation](Implementation.md) | Source-to-behavior mapping |
| [Integration guide](IntegrationGuide.md) | Public usage, API semantics, and examples |
| [Lightweight Agent Loop](Agent.md) | Upper-layer loop protocol, resource bounds, safety principles, and staged follow-up work |
| [RootFS security](RootFS.md) | RootFS input boundary, install algorithm, and storage model |
| [Testing](Testing.md) | Test commands, environments, scope, and evidence |
| [Upstream dependencies](UpstreamDependencies.md) | Revisions, gitlinks, URLs, sizes, and hashes |
| [Release and compliance](ReleaseCompliance.md) | License, NOTICE, source, SBOM, and store gates |
| [ADR](Decisions/ADR-001-IshEmbed-Feasibility.md) | Frozen decisions, rationale, and consequences |
| [Changelog](../../CHANGELOG.en.md) | Versioned and unreleased changes |

Code, `Package.resolved`, committed manifests, and the designated source-of-truth document take precedence over summaries.

## Current status

- Minimum deployment target: iOS 18.0.
- Default `PocketRoot` product: buildable placeholder; no real iSH runtime.
- `PocketRootIshRuntime` and `PocketRootIshRuntimeIntegration`: Experimental and opt-in.
- `PocketRootAgent`: provider-agnostic bounded agent loop; provider transport and Linux command tool remain open.
- RootFS secure installation: implemented; payload not committed, bundled, or downloaded by the library.
- iOS 18.2 arm64 Simulator: repository native smoke passed.
- Default boot identity gate: ready now requires matching `aarch64`, Alpine identity, optional version, and guest working directory.
- The signed iPhone one-shot baseline passed; iPad, complete physical-device lifecycle, minimum-Xcode native behavior, PTY, soft shutdown, and public distribution remain open or blocked.

See the [roadmap](Roadmap.md) for the current status.

## Language policy

- Parent `Docs/` paths are Simplified Chinese primary documents; `Docs/en/` contains English mirrors.
- Root documents are paired as `README.md / README.en.md`, `CONTRIBUTING.md / CONTRIBUTING.en.md`, and `CHANGELOG.md / CHANGELOG.en.md`.
- Behavior, API, hash, script, or gate changes must update both languages in the same pull request.
- API names, module names, paths, commands, state cases, and hashes remain unchanged.
- Diagrams must have equivalent prose.
- Run `./Scripts/check-docs.sh` to validate document pairs, Chinese coverage, and relative links.

## Terminology

| Chinese | English | Meaning |
| --- | --- | --- |
| 实验性 | Experimental | Requires explicit opt-in and carries no distribution commitment |
| 一次性命令 | one-shot command | Starts a child process, collects bounded output, and waits for exit |
| 进程终止式关闭 | process-terminal shutdown | Shutting down the guest also terminates the host App process |
| 软关闭 | soft shutdown | A future shutdown implementation that preserves the host process |
| 最终链接 | final link | Produces an executable App rather than only a static archive |
| 制品 | artifact | An external input such as an XCFramework or RootFS |
| `arm64` | `arm64` | Apple-platform build architecture |
| `aarch64` | `aarch64` | Architecture name reported by the Linux guest |
| `fakefs` | `fakefs` | The `meta.db + data/` filesystem layout used by iSH |
