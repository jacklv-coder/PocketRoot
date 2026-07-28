# Release and Compliance

[简体中文](../ReleaseCompliance.md) | [English](ReleaseCompliance.md) | [Documentation](README.md)

This document records the current release boundary and exit criteria; it is not legal advice. See [upstream dependencies](UpstreamDependencies.md) for exact artifacts and the [roadmap](Roadmap.md) for engineering status.

## Current position

The Experimental iSH runtime, XCFramework, and candidate RootFS are for local development and controlled technical validation only.

Production, TestFlight, App Store, public/private binary SDK distribution, RootFS bundling, unreviewed artifact mirroring, and claims of completed license/NOTICE/source/SBOM obligations remain blocked.

## Distribution composition

A native-enabled app may contain PocketRoot source, ish-arm64-pkg source, a static IshKernel XCFramework, iSH-derived source and submodules, an Alpine fakefs archive, guest packages under multiple licenses, and application download/command/UI policy. Review must cover the whole combination.

The repository now commits a reproducible maximal Experimental engineering
composition inventory and SPDX 2.3 JSON SBOM under
[`Compliance/Release/experimental-v0.1.0`](../../Compliance/Release/experimental-v0.1.0/README.md).
It distinguishes the default Demo, native-runtime smoke, and all Swift products,
and covers pinned ABI.6 IshEmbed/XCFramework, the iSH gitlink, supervisor musl
source, the caller-provided external RootFS, and its 15 Alpine packages. The
default Demo contains neither IshEmbed nor a RootFS. This evidence does not scan
a final archive and explicitly keeps `completeReleaseArtifactSBOM=false` and
`distributionAuthorized=false`; it is not a release-artifact SBOM or
distribution authorization.

## Known facts

The package repository carries GPL identifiers and a GPL-3.0 statement but did not provide a complete top-level license/notice set at audit. The pinned iSH source has GPL and `LICENSE.IOS` terms. Binary/source correspondence needs a durable reproducible record.

The current audit pins IshEmbed wrapper revision
`38d25d6f8726145e7e988172f12000020d89a638`, the `v0.4.0-abi.6` release
commit `38d25d6f8726145e7e988172f12000020d89a638`, and iSH gitlink
`c36dfd25462737b45559eb48d4b09f799471572e`; the upstream inventory records
the XCFramework and corresponding-source asset sizes and digests. The Release
provides a corresponding-source asset, but product-level RootFS compliance
material and the complete distributable combination remain open, so this does
not unblock distribution.

The Alpine archive includes GPL-2.0-only, GPL-2.0-or-later, Apache-2.0,
MPL-2.0, MIT, BSD, and Zlib families. The archive itself lacks a complete
license bundle, NOTICE set, and embedded machine-readable SBOM. The repository
now reproducibly generates all 15 installed binary packages, 10 source
origins, an SPDX 2.3 JSON SBOM, declared-license/attribution inventories, and
the default `apk`, repository, and DNS snapshot. No identifiable
LICENSE/COPYING/NOTICE file was found in the archive. A checksum-pinned
aports-snapshot/upstream-distfile manifest covers the inventory, and an
outside-repository materializer creates reproducible review inputs. A second
outside-repository tool pins, extracts, and verifies 78 license, attribution,
declaration, and inline-notice candidates across all 10 source origins.
A pinned result manifest records engineering review of all 78 candidates.
`libc-dev` and `zlib` have no remaining indexed items; eight source origins
still have package-level follow-up. The repository now pins an external
candidate bundle for those origins: 13 remote license/attribution payloads,
47 supplemental aports files, and all existing reviewed evidence. The tool can
atomically materialize and re-verify it outside the repository. A pinned
results manifest binds engineering review to the exact 138-file payload tree.
Seven origins have no remaining candidate-material engineering items; only
`alpine-keys` remains open because its upstream package lacks an MIT grant and
copyright notice. The corresponding-source candidate materializer now binds
the complete inventory, 10 aports trees with 130 canonical entries, nine
upstream distfiles, and the engineering review results to a schema-v3 receipt
and complete typed tree. Candidate source material is engineering-complete
for all 10 origins. Modification disclosure is indexed in the five-unit
delivery inventory, while the pinned release's exact rebuild,
source-offer mechanics, legal review, and delivery approval remain
unresolved. New rebuild evidence identifies the
historical v0.3.3 builder but does not claim its exact environment or archive
rebuild. A schema-v4 successor is byte-reproducible across two same-host
invocations and four total builds. Its five-unit source-delivery inventory is
complete, while the materialized bundle, source offer, legal review, and
delivery approval remain open. The output is neither a complete NOTICE set, a source offer, nor
approved corresponding-source delivery.

## Repository safeguards

The RootFS is not committed or bundled. Upstream source, nested gitlink, and
hashes are pinned. Experimental products are excluded from the umbrella.
Composition accepts local input only. CI downloads only for ephemeral
validation and regenerates the package inventory, SPDX SBOM, source locators,
source-acquisition manifest, license/NOTICE candidate index and engineering
review results, declared-license data, and default configuration under
[`Compliance/RootFS/v0.3.3`](../../Compliance/RootFS/v0.3.3/README.md).
CI offline-tests checksum verification, path isolation, and safe extraction for
the external corresponding-source candidate materializer; it does not upload
source material.
CI also regenerates the maximal Experimental engineering-composition
inventory/SPDX SBOM and validates it against the pinned official SPDX 2.3
schema; it neither builds nor scans a final release archive.
Documentation and APIs label Experimental and shutdown risks.

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

- [x] Generate a complete inventory from the pinned APK database.
- [x] Generate a machine-readable SBOM validated against the SPDX 2.3 JSON schema.
- [x] Complete checksum-bound engineering review of all 78 pinned
  license/NOTICE candidates.
- [x] Index a checksum-bound external candidate bundle and reproducible
  materializer for the eight remaining origins; payloads stay uncommitted and
  approval gates stay closed.
- [x] Complete checksum-bound engineering review of all 138 external candidate
  payloads; seven origins have no remaining candidate-material engineering
  items, and only `alpine-keys` remains open because its upstream package
  lacks an MIT grant and copyright notice.
- [ ] Collect license texts and NOTICE files.
- [x] Establish a checksum-bound external corresponding-source candidate
  materialization and verification flow covering all 10 source origins, 130
  canonical aports entries, and nine upstream distfiles; candidate-material
  engineering review is complete and payloads remain uncommitted.
- [x] Establish a unified external delivery-candidate materializer that
  re-verifies the source and LICENSE/NOTICE candidates, recursively exports
  pinned builder/submodule Git objects, binds the Alpine input and modification
  disclosure, and emits a receipt, typed tree, and checksums without committing
  output or opening any authorization gate.
- [ ] Approve the rebuild environment/toolchain, modification disclosure,
  source-offer mechanics, legal review, and corresponding-source delivery.
- [x] Record default DNS, repository, and package-manager facts.
- [ ] Decide the product policy to retain, restrict, proxy, or disable guest
  package management and networking.
- [x] Keep the current caller-supplied local-input decision; re-review any
  bundle or on-demand-resource change.
- [x] Update the manifest, hashes, and reproducible CI evidence.

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
- [x] Generate the maximal Experimental engineering composition's dependency,
  revision, hash inventory, and SPDX SBOM.
- [ ] Generate a complete SBOM from the built and scanned final release artifact.
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
