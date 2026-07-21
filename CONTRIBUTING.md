# Contributing to PocketRoot

Thanks for helping build PocketRoot.

## Development workflow

1. Install XcodeGen and use Xcode 16 or newer with the iOS 18 SDK.
2. Run ./Scripts/bootstrap.sh to resolve the package and generate the project.
3. Make core capabilities reusable in the Swift Package; keep the Demo limited
   to presentation and verification.
4. Run ./Scripts/test.sh and ./Scripts/build.sh before submitting changes. Run
   ./Scripts/build-runtime-spike.sh for Experimental runtime or RootFS changes.
   When the audited local v0.3.3 archive and an iOS 18 Simulator are available
   on an Apple Silicon host, also run
   `POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz ./Scripts/run-runtime-smoke.sh`.
   This local smoke is separate from CI and does not replace signed physical
   iPhone and iPad validation.
5. Update CHANGELOG.md when behavior or public APIs change.

## Project rules

- Keep PocketRootCore independent of UIKit.
- Build Demo screens with programmatic UIKit and Auto Layout.
- Do not add storyboards, XIB files, or a SwiftUI App lifecycle.
- Treat project.yml as the Xcode project source of truth.
- Pin every third-party dependency to an immutable release, exact version, or
  full commit revision; record nested gitlinks and artifact hashes separately.
- Do not bundle, mirror, or distribute an Alpine RootFS or iSH binary, or enable
  the Experimental runtime by default, before its licensing and distribution
  requirements have been reviewed.
- Prefix public API types with PocketRoot.

## Changes involving upstream code

Preserve upstream copyright and license notices. Describe the exact upstream
version, local modifications, and redistribution impact in the change request.
