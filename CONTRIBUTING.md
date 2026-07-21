# Contributing to PocketRoot

Thanks for helping build PocketRoot.

## Development workflow

1. Install XcodeGen and use an Xcode version that includes the iOS 17 SDK.
2. Run ./Scripts/bootstrap.sh to resolve the package and generate the project.
3. Make core capabilities reusable in the Swift Package; keep the Demo limited
   to presentation and verification.
4. Run ./Scripts/test.sh and ./Scripts/build.sh before submitting changes.
5. Update CHANGELOG.md when behavior or public APIs change.

## Project rules

- Keep PocketRootCore independent of UIKit.
- Build Demo screens with programmatic UIKit and Auto Layout.
- Do not add storyboards, XIB files, or a SwiftUI App lifecycle.
- Treat project.yml as the Xcode project source of truth.
- Pin every third-party dependency to a release tag or exact version.
- Do not add an Alpine RootFS or iSH integration before its licensing and
  distribution requirements have been reviewed.
- Prefix public API types with PocketRoot.

## Changes involving upstream code

Preserve upstream copyright and license notices. Describe the exact upstream
version, local modifications, and redistribution impact in the change request.
