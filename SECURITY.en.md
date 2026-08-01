# PocketRoot Security Policy

[简体中文](SECURITY.md) | [English](SECURITY.en.md) | [Contributing](CONTRIBUTING.en.md)

## Supported scope

PocketRoot accepts security reports for the public `v0.1.x` source line and
the `main` branch. The native iSH runtime, RootFS installer, PTY, Files,
Workspace, and optional Agent components remain Experimental. Their APIs may
change, but memory safety, path validation, authorization boundaries,
credential handling, and supply-chain issues are still treated as security
concerns.

Runtime, App, TestFlight, App Store, and binary SDK distribution are not yet
authorized. A security report or fix does not automatically open any
[distribution gate](Docs/en/ReleaseCompliance.md).

## Report a vulnerability privately

Do not open a public Issue, Discussion, or pull request for an unpatched
security problem. Email the repository owner's public security contact,
[`jacklvapple@gmail.com`](mailto:jacklvapple@gmail.com), with a subject that
starts with `[PocketRoot Security]`.

Include when possible:

- the affected PocketRoot version, full commit, and selected Swift Package
  products;
- iOS, Xcode, device or Simulator architecture;
- minimal reproduction steps, expected and actual results, and security impact;
- sanitized logs, stack traces, or a minimal source patch;
- whether IshEmbed/iSH, SwiftTerm, or a caller-provided RootFS is involved.

Do not send real tokens, signing material, device identifiers, personal data,
RootFS archives, Apps, IPAs, XCFrameworks, or other unauthorized binaries. If
an artifact is essential, initially provide only its type, size, and SHA-256,
then wait for a maintainer-approved secure transfer method.

Maintainers aim to acknowledge reports within three business days and provide
an initial assessment or information request within seven business days. These
are response goals, not a fix deadline or service-level agreement. Keep the
report private until maintainers confirm the fixed version and disclosure time.

## Disclosure and remediation

Maintainers will validate impact, reproduction conditions, third-party
ownership, and the existing distribution boundary. Confirmed issues will be
fixed, tested, and documented without unnecessarily expanding exploitability;
upstream projects will be coordinated with when appropriate. Public disclosure
should identify affected versions, mitigations, and the fixed version without
including credentials, personal data, or unnecessary exploit payloads.

Use the structured
[Issue forms](https://github.com/jacklv-coder/PocketRoot/issues/new/choose)
for general support, non-sensitive bugs, and feature requests.
