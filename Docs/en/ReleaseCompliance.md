# Release and Compliance

[简体中文](../ReleaseCompliance.md) | [English](ReleaseCompliance.md) | [Documentation](README.md)

This document records the current release boundary and exit criteria; it is not legal advice. See [upstream dependencies](UpstreamDependencies.md) for exact artifacts and the [roadmap](Roadmap.md) for engineering status.

## Current position

The Experimental iSH runtime, XCFramework, and candidate RootFS are for local development and controlled technical validation only.

Production, TestFlight, App Store, public/private binary SDK distribution, RootFS bundling, unreviewed artifact mirroring, and claims of completed license/NOTICE/source/SBOM obligations remain blocked.

## Distribution composition

A native-enabled app may contain PocketRoot source, ish-arm64-pkg source, a static IshKernel XCFramework, iSH-derived source and submodules, an Alpine fakefs archive, guest packages under multiple licenses, and application download/command/UI policy. Review must cover the whole combination.

## Known facts

The package repository carries GPL identifiers and a GPL-3.0 statement but did not provide a complete top-level license/notice set at audit. The pinned iSH source has GPL and `LICENSE.IOS` terms. Binary/source correspondence needs a durable reproducible record.

The current audit pins IshEmbed `v0.4.0-abi.4` release commit
`1c761d4c6de4ceb5ec9f15a4a958be9207ace756` and iSH gitlink
`c36dfd25462737b45559eb48d4b09f799471572e`; the upstream inventory records
the XCFramework and corresponding-source asset sizes and digests. The Release
provides a corresponding-source asset, but product-level RootFS compliance
material and the complete distributable combination remain open, so this does
not unblock distribution.

The Alpine archive includes GPL-2.0-only, GPL-2.0-or-later, Apache-2.0, MPL-2.0, MIT, BSD, and Zlib families. It lacks a complete license bundle, NOTICE set, machine-readable SBOM, and established corresponding-source bundle.

## Repository safeguards

The RootFS is not committed or bundled. Upstream source, nested gitlink, and hashes are pinned. Experimental products are excluded from the umbrella. Composition accepts local input only. CI downloads only for ephemeral validation. Documentation and APIs label Experimental and shutdown risks.

These engineering controls reduce the risk of accidental distribution; they do
not replace legal review.

## App Store 2.5.2

Alpine `apk` can download, install, and execute additional code. A reviewed initial RootFS does not automatically resolve the downloaded-code question.

A release decision must address shell freedom, guest networking and package manager, allowed repositories/content, whether downloaded code changes app functionality, enforcement policy, product audience, and App Review explanation. The gate is currently blocked.

## Private APIs, entitlements, and JIT

Static inspection of the pinned archive and a linked consumer found no `MAP_JIT`, JIT entitlement, private framework path, or `com.apple.private.*` entitlement. The ARM64 engine uses precompiled gadgets.

This is not an App Review guarantee. Signed devices, final entitlements, exported-binary scans, and runtime behavior review remain required.

## Data and privacy

Adding a Linux guest also requires release review of:

- where the RootFS and VM data are stored;
- the iCloud/iTunes backup-exclusion policy;
- the App-file boundary accessible to guest commands;
- retention of commands, stdout, stderr, and kernel logs;
- user input, environment variables, and secrets;
- network permissions and guest DNS;
- the data lifecycle when the App is deleted, the environment is cleared, or a
  version is migrated; and
- whether crash reports contain commands or private paths.

The current code does not provide a complete product-level privacy policy.

## Required before distribution

### PocketRoot itself

- [ ] Choose and commit a complete top-level license.
- [ ] Define the contributor and copyright policy.
- [ ] Generate a release notice.
- [ ] Declare public API stability and semantic-versioning policy.

### IshEmbed / iSH

- [ ] Record every source commit and nested gitlink.
- [ ] Ensure that the XCFramework corresponds to reproducibly buildable source.
- [ ] Preserve build scripts, toolchain information, and checksums.
- [ ] Collect LICENSE, NOTICE, and modification disclosures.
- [ ] Evaluate static-linking obligations.
- [ ] Provide all required corresponding source.

### RootFS

- [ ] Generate a complete package inventory.
- [ ] Generate a machine-readable SBOM.
- [ ] Collect license texts and NOTICE files.
- [ ] Establish a corresponding-source bundle for copyleft components.
- [ ] Review default DNS, repository, and package-manager configuration.
- [ ] Decide whether the archive is bundled, delivered as an on-demand resource,
  or supplied as an external input.
- [ ] Update the manifest, hashes, and test evidence.

### Apple platforms

- [x] Complete RootFS install, native final links, and the 17-check smoke with
  the minimum Xcode 16 toolchain.
- [x] Run the signed iPhone one-shot smoke.
- [ ] Run the signed iPad smoke and complete iPhone/iPad lifecycle coverage.
- [x] Keep complete Simulator smoke lifecycle `ru_maxrss` at or below 256 MiB.
- [ ] Validate foreground/background behavior, physical jetsam handling, and storage
  pressure.
- [ ] Scan entitlements, private APIs, JIT behavior, and exported archives.
- [ ] Record a written Guideline 2.5.2 disposition.
- [ ] Review privacy manifests, networking, and data retention.
- [x] Record the returning soft-shutdown and no-reboot-in-process single-lifecycle contract.

### Delivery material

- [ ] LICENSE bundle.
- [ ] NOTICE.
- [ ] Corresponding-source location and retrieval instructions.
- [ ] SBOM.
- [ ] Dependency, revision, and hash inventory.
- [ ] Security guidance and known limitations.
- [ ] RootFS update and deletion policy.
- [ ] App Review notes.
- [ ] Reproducible-build record.

No distribution status change is allowed until every blocker has an approved disposition.

## Allowed engineering work

Local package tests, ephemeral CI validation, unsigned generic device links, Simulator smoke, controlled signed engineering tests, audits, and compliance-material generation are allowed when restricted payloads are not redistributed.

## Re-review triggers

Any IshEmbed/iSH/XCFramework change, RootFS/build/default-network change, new terminal/network/package feature, distribution channel, shutdown/process change, third-party dependency, or license/store-policy change reopens review.

Update the upstream inventory, ADR, roadmap, changelog, and both language versions with the change.

Engineering maintainers record facts and maintain controls that reduce the risk
of accidental packaging. Authorized legal, compliance, and product owners make
final interpretations and distribution decisions.
