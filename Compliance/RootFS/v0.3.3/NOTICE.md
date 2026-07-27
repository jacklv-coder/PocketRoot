# Pinned RootFS attribution inventory

Generated from the exact `v0.3.3` archive with SHA-256
`be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4`.

> This is reproducible engineering evidence, not a complete legal NOTICE,
> license bundle, corresponding-source offer, or redistribution approval.
> Engineering candidate review is complete. Package-specific open items,
> legal review, and redistribution approval remain required.

## Installed packages

| Package | Version | Declared license | Source origin | aports commit |
| --- | --- | --- | --- | --- |
| `alpine-baselayout` | `3.4.3-r2` | `GPL-2.0-only` | `alpine-baselayout` | `7749273fed55f6e1df7c9ee6a127f18099f98a94` |
| `alpine-baselayout-data` | `3.4.3-r2` | `GPL-2.0-only` | `alpine-baselayout` | `7749273fed55f6e1df7c9ee6a127f18099f98a94` |
| `alpine-keys` | `2.4-r1` | `MIT` | `alpine-keys` | `aab68f8c9ab434a46710de8e12fb3206e2930a59` |
| `apk-tools` | `2.14.0-r5` | `GPL-2.0-only` | `apk-tools` | `33283848034c9885d984c8e8697c645c57324938` |
| `busybox` | `1.36.1-r15` | `GPL-2.0-only` | `busybox` | `d1b6f274f29076967826e0ecf6ebcaa5d360272f` |
| `busybox-binsh` | `1.36.1-r15` | `GPL-2.0-only` | `busybox` | `d1b6f274f29076967826e0ecf6ebcaa5d360272f` |
| `ca-certificates-bundle` | `20230506-r0` | `MPL-2.0 AND MIT` | `ca-certificates` | `59534a02716a92a10d177a118c34066162eff4a6` |
| `libc-utils` | `0.7.2-r5` | `BSD-2-Clause AND BSD-3-Clause` | `libc-dev` | `988f183cc9d6699930c3e18ccf4a9e36010afb56` |
| `libcrypto3` | `3.1.4-r5` | `Apache-2.0` | `openssl` | `b784a22cad0c452586b438cb7a597d846fc09ff4` |
| `libssl3` | `3.1.4-r5` | `Apache-2.0` | `openssl` | `b784a22cad0c452586b438cb7a597d846fc09ff4` |
| `musl` | `1.2.4_git20230717-r4` | `MIT` | `musl` | `ca7f2ab5e88794e4e654b40776f8a92256f50639` |
| `musl-utils` | `1.2.4_git20230717-r4` | `MIT AND BSD-2-Clause AND GPL-2.0-or-later` | `musl` | `ca7f2ab5e88794e4e654b40776f8a92256f50639` |
| `scanelf` | `1.3.7-r2` | `GPL-2.0-only` | `pax-utils` | `e65a4f2d0470e70d862ef2b5c412ecf2cb9ad0a6` |
| `ssl_client` | `1.36.1-r15` | `GPL-2.0-only` | `busybox` | `d1b6f274f29076967826e0ecf6ebcaa5d360272f` |
| `zlib` | `1.3.1-r0` | `Zlib` | `zlib` | `9406f6fc5fca057d990eb0d260d75839eeb34d83` |

## License and notice status

No file whose path identifies it as LICENSE, COPYING, NOTICE, or a license-directory member was found in the guest template.

Declared identifiers and expressions are recorded in
`LICENSE-INVENTORY.json`. `LICENSE-REVIEW.json` pins 78
candidate license, attribution, declaration, and inline-notice files across
all 10 source origins. The external review tool
extracts and verifies those candidates from the pinned source-review bundle.
`LICENSE-REVIEW-RESULTS.json` records the checksum-bound engineering review
of all 78 candidates. All indexed review items are resolved
for `libc-dev`, `zlib`.
8 source origins still have package-specific open
items, so this is not a complete or legally approved license/NOTICE bundle.
`LICENSE-NOTICE-CANDIDATES.json` now pins an external candidate bundle for
those open origins: 13 remote
reference/attribution payloads and
47 supplemental aports
files, together with all checksum-bound reviewed evidence. The repository
tool can materialize and re-verify that bundle outside the repository.
`LICENSE-NOTICE-REVIEW-RESULTS.json` records checksum-bound engineering
review of all 138 indexed
payload files. 7 origins have no remaining
candidate-material engineering items; 1 origin still requires
package-specific material. Legal review and redistribution
approval remain open.

## Corresponding-source status

Exact Alpine aports recipe locators are recorded for all
10 source origins in `SOURCE-INVENTORY.json`.
`SOURCE-ACQUISITION.json` pins each aports snapshot and upstream distfile
with cryptographic checksums. The repository script can materialize those
inputs into a new external review directory.
Source origins with declared copyleft terms are
`alpine-baselayout`, `apk-tools`, `busybox`, `ca-certificates`, `musl`, `pax-utils`.

No source archive is committed or shipped by this repository. A materialized
directory still requires package-specific license/NOTICE, modification,
build-completeness, offer-mechanics, and legal review before it can be
treated as corresponding-source delivery material.

## Runtime configuration status

`RUNTIME-CONFIGURATION.json` records the package manager, repositories, DNS
resolver values, architecture, and world set. Product policy for retaining,
restricting, proxying, or disabling package installation and networking
remains open.
