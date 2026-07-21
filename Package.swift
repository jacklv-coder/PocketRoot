// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PocketRoot",
    platforms: [
        .iOS(.v17),
        // A host-only compatibility floor keeps Swift package tests available
        // on macOS while UIKit remains conditionally compiled for iOS.
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PocketRootCore",
            targets: ["PocketRootCore"]
        ),
        .library(
            name: "PocketRootTerminal",
            targets: ["PocketRootTerminal"]
        ),
        .library(
            name: "PocketRootResources",
            targets: ["PocketRootResources"]
        ),
        .library(
            name: "PocketRoot",
            targets: ["PocketRoot"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PocketRootCore"
        ),
        .target(
            name: "PocketRootTerminal",
            dependencies: [
                "PocketRootCore"
            ]
        ),
        .target(
            name: "PocketRootResources",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "PocketRoot",
            dependencies: [
                "PocketRootCore",
                "PocketRootTerminal",
                "PocketRootResources"
            ]
        ),
        .testTarget(
            name: "PocketRootCoreTests",
            dependencies: [
                "PocketRootCore"
            ]
        ),
        .testTarget(
            name: "PocketRootTerminalTests",
            dependencies: [
                "PocketRootTerminal"
            ]
        )
    ]
)
