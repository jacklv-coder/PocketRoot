# PocketRoot

Embeddable ARM64 Linux runtime and terminal foundations for iOS.

## Status

PocketRoot is currently under active development.

The first milestone provides:

- A reusable Swift Package structure
- A pure UIKit demo app for iPhone and iPad
- Runtime and terminal API foundations
- XcodeGen-based project generation
- Unit tests for the placeholder behavior

Linux runtime, Alpine RootFS, and SwiftTerm integration are planned for a later
milestone. This repository does not download or start a Linux runtime yet.

## Architecture

- UIKit demo application using AppDelegate, SceneDelegate, and UIWindow
- Swift Package modularization
- PocketRootCore
- PocketRootTerminal
- PocketRootResources
- PocketRoot umbrella product

See Docs/Architecture.md for module boundaries and Docs/Roadmap.md for the
integration sequence.

## Requirements

- Xcode with the iOS 17 SDK or newer
- Swift 5.10 or newer
- XcodeGen

## Build

    brew install xcodegen
    ./Scripts/bootstrap.sh
    ./Scripts/test.sh
    ./Scripts/build.sh
    open PocketRootDemo.xcodeproj

The generated Xcode project is intentionally ignored. Update project.yml and
regenerate instead of editing project.pbxproj by hand.

## License

The licensing policy is being finalized before the first public release. See
LICENSE for the current notice.

PocketRoot is expected to include GPL-licensed runtime components in later
milestones. Every upstream component will retain its own copyright and license,
and the final distribution must preserve all upstream requirements.
