# PocketRoot Roadmap

## Milestone 1: Project foundation

- Swift Package module boundaries
- Public runtime, command, session, and terminal API foundations
- Placeholder runtime and terminal behavior
- Programmatic UIKit demo with four tabs
- XcodeGen generation, scripts, documentation, and tests

## Milestone 2: ARM64 Linux runtime

1. Fork and audit ish-arm64-pkg.
2. Pin an immutable release tag.
3. Add the IshEmbed dependency.
4. Implement RootFSProvider and integrity metadata.
5. Bundle a license-reviewed Alpine ARM64 RootFS.
6. Implement IshLinuxRuntime.
7. Add one-shot command execution.
8. Implement interactive PocketRootSession behavior.
9. Pin a compatible SwiftTerm release.
10. Implement TerminalBridge.
11. Validate aarch64 behavior on physical iPhone and iPad hardware.

## Milestone 3: Hardening

- Runtime lifecycle recovery and cancellation
- RootFS migration and storage policy
- Performance and memory benchmarks
- Accessibility and localization review
- Security, sandbox, and distribution review

Agent, browser automation, and MCP capabilities are intentionally outside the
scope of PocketRootCore.
