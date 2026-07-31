# Contributing to PocketRoot

[简体中文](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md) | [Documentation](Docs/en/README.md)

PocketRoot is in an Experimental runtime phase. Code quality, native lifecycle, supply-chain records, and both documentation languages must move together.

## License and contributions

Original source code copyrighted by PocketRoot contributors is provided under
the MIT License in the repository-root `LICENSE`. By submitting an issue,
patch, or pull request, a contributor represents that they have the right to
submit the material. Unless separately agreed in writing, original code and
documentation intentionally submitted and accepted by the project are
provided under the same MIT License.

Do not re-label third-party or upstream material as MIT. Preserve its original
copyright and license notices, disclose provenance, version, modifications,
and distribution impact, and follow the
[upstream dependency procedure](Docs/en/UpstreamDependencies.md) for NOTICE,
source-correspondence, and SBOM evidence.

## Git and GitHub

Use SSH for fetch and push:

```bash
git remote set-url origin git@github.com:jacklv-coder/PocketRoot.git
```

When port 22 is blocked:

```bash
git remote set-url origin \
  ssh://git@ssh.github.com:443/jacklv-coder/PocketRoot.git
```

Verify GitHub host keys. Never commit keys, tokens, device codes, signing material, or credentials.

Do not work directly on `main`. Codex/automation branches use `agent/<description>`. Keep commits terse, such as `docs: add bilingual integration guides`. Start with a Draft PR until validation and gate descriptions are complete.

## Environment and bootstrap

Use Xcode 16+, iOS 18 SDK, Swift 5.10+, XcodeGen, and Homebrew. Native runtime work requires Apple Silicon and an iOS 18 Simulator; physical gates require signed iPhone/iPad hardware.

```bash
./Scripts/bootstrap.sh
```

## Workflow

1. Inspect status and update with fast-forward only.
2. Create a focused branch.
3. Change code, tests, and documentation together.
4. Run at least:

   ```bash
   ./Scripts/check-docs.sh
   ./Scripts/test.sh
   ./Scripts/build.sh
   ```

5. Runtime, RootFS, package, or native changes also require final links, the real-asset test, and native smoke when the audited archive is available.
6. Inspect `git status`, `git diff --check`, and the complete diff.
7. Stage only intended files, commit, and push through SSH.
8. Create or update a Draft PR with what, why, impact, validation, and open gates.

## Architecture rules

- Core has no UIKit, concrete RootFS, or IshEmbed dependency.
- Use programmatic UIKit and Auto Layout; no storyboard/XIB/SwiftUI App lifecycle.
- `Examples/PocketRootDemo/project.yml` is authoritative for the complete Demo; generated projects are not committed.
- The umbrella never exports Experimental runtime products.
- Blocking IshEmbed calls stay off main/cooperative executors.
- Close lifecycle reentrancy before suspension.
- Preserve process ownership, one in-flight command, and output bounds.
- Do not connect SwiftTerm before PTY pointer and close ownership are proven.
- Prefix public types with `PocketRoot`.
- Document public API, state, error, and critical constraints in both languages.

## RootFS and artifacts

Never commit RootFS archives, extracted fakefs, unaudited kernel copies, smoke payloads/reports, or build output.

Pin dependencies immutably and record nested gitlinks, URLs, byte counts, SHA-256, source correspondence, and license/notice/SBOM impact.

Follow the [upstream update procedure](Docs/en/UpstreamDependencies.md). Do not bundle/mirror a RootFS, enable native runtime by default, or distribute binaries before all release gates close.

## Testing

Use the [test matrix](Docs/en/Testing.md). Fixes need regression tests. Concurrency work needs strict warnings-as-errors builds. RootFS work needs malicious inputs, rollback, and real assets. Runtime work needs injected-driver and native smoke. Package/native changes need executable final links.

Do not substitute Simulator for physical-device evidence or report skipped gates as passed. Runtime changes should also use `run-runtime-device-smoke.sh` with explicit archive, device, and development-team inputs when signed hardware is available.

## Bilingual documentation

Pairs:

| Chinese | English |
| --- | --- |
| `README.md` | `README.en.md` |
| `CONTRIBUTING.md` | `CONTRIBUTING.en.md` |
| `CHANGELOG.md` | `CHANGELOG.en.md` |
| `Docs/<name>.md` | `Docs/en/<name>.md` |
| `Docs/Decisions/<name>.md` | `Docs/en/Decisions/<name>.md` |

Update both in the same PR for behavior, API, scripts, hashes, status, or gates. Keep code identifiers unchanged, place dynamic status in Roadmap, hashes in Upstream, evidence in Testing, and decisions in ADRs. Diagrams need equivalent prose. New Markdown cannot be English-only.

Run `./Scripts/check-docs.sh`.

## Changelog and upstream

Update both changelogs for API, behavior, baseline, dependency, security, compatibility, gate, or documentation-structure changes. Use Added, Changed, Fixed, Security, Deprecated, and Removed categories.

Preserve upstream copyright/licenses and record exact revisions, gitlinks, modifications, rebuild method, checksum, redistribution impact, and source/notice/SBOM updates.

## PR checklist

- Focused scope with no unrelated files.
- Tests for public behavior.
- Required builds/final-links/smoke run or explicitly not run.
- No RootFS/artifact payload committed.
- Chinese and English updated.
- Documentation and diff checks pass.
- Changelog updated.
- PR explains impact, risk, validation, and gates.
- SSH push.
- No credentials or private data.
