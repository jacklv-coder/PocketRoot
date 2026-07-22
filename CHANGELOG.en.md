# Changelog

[简体中文](CHANGELOG.md) | [English](CHANGELOG.en.md) | [Documentation](Docs/en/README.md)

All notable PocketRoot changes are recorded here. Semantic Versioning begins with the first public release. Everything below is currently Unreleased.

## Unreleased

### Added

- Swift Package products for Core, Terminal, Resources, and the safe umbrella.
- Programmatic UIKit Demo with System, Terminal, Commands, and Diagnostics.
- XcodeGen project source, generation, test, and build scripts.
- Placeholder runtime, terminal API foundations, and unit tests.
- Unified iOS 18 deployment baseline.
- Experimental `PocketRootIshRuntime` pinned to IshEmbed revision `6f96f02c71830914c2a608258a26a8ef0833d026`.
- Experimental `PocketRootIshRuntimeIntegration` composing caller-local RootFS installation and native runtime.
- Process ownership, serial native execution, and lifecycle reentrancy protection.
- One-shot cwd, environment, stderr merge, exit, signal, timeout, and stream mapping.
- A default post-boot identity gate using a fixed command and NUL framing; ready now requires matching guest architecture, Alpine identity, optional version, and working directory.
- Positive timeout validation, bounded reads, and default 8 MiB/4 MiB stream limits.
- Immutable v0.3.3 manifest, streaming SHA-256, and byte limits.
- zlib gzip and constrained ustar extraction with traversal/link/special/duplicate rejection.
- fakefs validation, versioned installation, verified reuse, and journal-protected same-volume promotion with rollback and interrupted recovery.
- Real release-archive integration test.
- arm64 Simulator and unsigned-device final-link gates for the full Experimental graph.
- Repository iOS 18 native smoke covering 13 preparation, boot, guest, command, recovery, and shutdown checks.
- Exact SwiftPM resolution in `Package.resolved`.
- IshEmbed [ADR-001](Docs/en/Decisions/ADR-001-IshEmbed-Feasibility.md) and immutable [upstream inventory](Docs/en/UpstreamDependencies.md).
- Chinese-primary, English-mirror documentation for product planning, getting started, integration, architecture, implementation, RootFS, testing, troubleshooting, roadmap, and compliance.
- Automated documentation pair, Chinese coverage, and relative-link checks.

### Changed

- `README.md` is the Chinese primary entry with status, implementation, usage, RootFS policy, and navigation; `README.en.md` is its English mirror.
- Architecture, Roadmap, Upstream, ADR, Contributing, and Changelog now have Chinese primary and English mirror documents.
- Roadmap owns dynamic status, Upstream owns pins/hashes, Testing owns evidence, and ADRs own frozen decisions.
- Contribution Git fetch/push uses SSH.
- Documentation now states that the default shared system is a placeholder and applications must retain the system returned by composition.
- Pinned native shutdown is explicitly process-terminal and not routine UI cleanup.
- The merged native ABI candidate is recorded without changing PocketRoot's current revision or binary behavior because no pinnable artifact exists yet.
- One-shot commands reject NUL-containing C-string inputs and ambiguous environment keys before entering the native driver.
- Pre-exit post-spawn failures now require an authoritative guest `EXITED` before recovery; negative synthetic supervisor states preserve error provenance, while pinned transport's ambiguous `(17, 0)` marker explicitly cleans up and fails the runtime closed.
- The ustar extractor now also rejects duplicate directory entries and filesystem-equivalent directory targets, and RootFS journal documentation no longer promises power-loss durability without explicit `fsync`.

### Security

- RootFS payloads remain uncommitted, unbundled, and never downloaded by the library.
- Production, TestFlight, and public binary distribution remain blocked pending license, NOTICE, source, SBOM, physical-device, and App Store 2.5.2 gates.
