# Changelog

All notable changes to PocketRoot will be documented in this file.

The project follows semantic versioning once the first public release is made.

## Unreleased

### Added

- Initial Swift Package with Core, Terminal, Resources, and umbrella products
- UIKit demo shell with System, Terminal, Commands, and Diagnostics tabs
- XcodeGen project definition and build scripts
- Placeholder runtime APIs and unit tests
- Architecture and roadmap documentation
- Unified iOS 18.0 deployment baseline
- Experimental `PocketRootIshRuntime` boundary pinned to IshEmbed revision
  `6f96f02c71830914c2a608258a26a8ef0833d026`
- Experimental `PocketRootIshRuntimeIntegration` composition product for
  caller-supplied, verified RootFS archives
- Process-wide IshEmbed ownership and blocking-call serialization, one-shot
  lifecycle protection, bounded timeouts, streaming stdout/stderr limits, and
  documented process-terminal shutdown semantics
- Command environment, stderr-merge, and terminating-signal result mapping
- Immutable v0.3.3 RootFS manifest, streaming SHA-256 validation, secure
  gzip/ustar extraction, fakefs validation, and versioned atomic installation
  with bounded private archive snapshots, reuse, corruption replacement,
  concurrency control, persistent promotion recovery, and rollback
- Real release-archive integration coverage plus arm64 Simulator and unsigned
  device final-link gates for the complete Experimental integration graph
- Repository-owned iOS 18 native adapter smoke App and runner covering 13
  preparation, boot, guest identity, command-context, stream, exit-code,
  timeout-recovery, output-limit-recovery, and process-terminal shutdown checks
- Exact SwiftPM resolution recorded in `Package.resolved`
- IshEmbed feasibility and distribution gates documented in
  [ADR-001](Docs/Decisions/ADR-001-IshEmbed-Feasibility.md)
- Immutable upstream revisions, binary hashes, RootFS hashes, and validation
  results documented in
  [Upstream Dependencies](Docs/UpstreamDependencies.md)
