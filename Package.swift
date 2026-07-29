// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PocketRoot",
    platforms: [
        .iOS("18.0"),
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
            name: "PocketRootIshRuntime",
            targets: ["PocketRootIshRuntime"]
        ),
        .library(
            name: "PocketRootIshRuntimeIntegration",
            targets: ["PocketRootIshRuntimeIntegration"]
        ),
        .library(
            name: "PocketRootAgent",
            targets: ["PocketRootAgent"]
        ),
        .library(
            name: "PocketRootAgentRuntimeTools",
            targets: ["PocketRootAgentRuntimeTools"]
        ),
        .library(
            name: "PocketRoot",
            targets: ["PocketRoot"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/jacklv-coder/ish-arm64-pkg.git",
            revision: "38d25d6f8726145e7e988172f12000020d89a638"
        ),
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            revision: "dd2fb8ac5b861e7bf617c872895e338f38165648"
        )
    ],
    targets: [
        .target(
            name: "PocketRootCore"
        ),
        .target(
            name: "PocketRootTerminal",
            dependencies: [
                "PocketRootCore",
                .product(
                    name: "SwiftTerm",
                    package: "SwiftTerm",
                    condition: .when(platforms: [.iOS])
                )
            ]
        ),
        .target(
            name: "CPocketRootArchiveSupport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "PocketRootResources",
            dependencies: [
                "CPocketRootArchiveSupport"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "PocketRootIshRuntime",
            dependencies: [
                "PocketRootCore",
                .product(
                    name: "IshEmbed",
                    package: "ish-arm64-pkg",
                    condition: .when(platforms: [.iOS])
                )
            ]
        ),
        .target(
            name: "PocketRootIshRuntimeIntegration",
            dependencies: [
                "PocketRootCore",
                "PocketRootResources",
                "PocketRootIshRuntime",
                "PocketRootTerminal"
            ]
        ),
        .target(
            name: "PocketRootAgent"
        ),
        .target(
            name: "PocketRootAgentRuntimeTools",
            dependencies: [
                "PocketRootAgent",
                "PocketRootCore"
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
        ),
        .testTarget(
            name: "PocketRootResourcesTests",
            dependencies: [
                "PocketRootResources"
            ]
        ),
        .testTarget(
            name: "PocketRootIshRuntimeTests",
            dependencies: [
                "PocketRootCore",
                "PocketRootIshRuntime"
            ]
        ),
        .testTarget(
            name: "PocketRootIshRuntimeIntegrationTests",
            dependencies: [
                "PocketRootCore",
                "PocketRootResources",
                "PocketRootIshRuntimeIntegration"
            ]
        ),
        .testTarget(
            name: "PocketRootAgentTests",
            dependencies: [
                "PocketRootAgent"
            ]
        ),
        .testTarget(
            name: "PocketRootAgentRuntimeToolsTests",
            dependencies: [
                "PocketRootAgent",
                "PocketRootAgentRuntimeTools",
                "PocketRootCore"
            ]
        )
    ]
)
