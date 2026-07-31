#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
VERSION="${1:-}"
EXPECTED_COMMIT="${2:-}"
REPOSITORY_URL="${POCKETROOT_RELEASE_REPOSITORY_URL:-https://github.com/jacklv-coder/PocketRoot.git}"

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Usage: $0 VERSION EXPECTED_COMMIT" >&2
    exit 2
fi
if [[ ! "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "EXPECTED_COMMIT must be a full lowercase Git SHA." >&2
    exit 2
fi
if [[ ! "$REPOSITORY_URL" =~ ^https://[^[:space:]]+\.git$ ]]; then
    echo "POCKETROOT_RELEASE_REPOSITORY_URL must be a public HTTPS Git URL." >&2
    exit 2
fi

RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootTagConsumer.XXXXXX")"
cleanup() {
    rm -rf "$RUN_ROOT"
}
trap cleanup EXIT

VERSION="$VERSION" REPOSITORY_URL="$REPOSITORY_URL" RUN_ROOT="$RUN_ROOT" \
    ruby -r json -r fileutils -e '
      version = ENV.fetch("VERSION")
      repository_url = ENV.fetch("REPOSITORY_URL")
      root = ENV.fetch("RUN_ROOT")
      manifest = <<~SWIFT
        // swift-tools-version: 5.10
        import PackageDescription

        let package = Package(
            name: "PocketRootTagConsumer",
            platforms: [.iOS("18.0")],
            dependencies: [
                .package(
                    url: #{JSON.generate(repository_url)},
                    exact: #{JSON.generate(version)}
                )
            ],
            targets: [
                .target(
                    name: "PocketRootTagConsumer",
                    dependencies: [
                        .product(name: "PocketRoot", package: "PocketRoot")
                    ]
                )
            ]
        )
      SWIFT
      File.binwrite(File.join(root, "Package.swift"), manifest)
      source = File.join(root, "Sources", "PocketRootTagConsumer")
      FileUtils.mkdir_p(source)
      File.binwrite(File.join(source, "Consumer.swift"), "import PocketRoot\n")
    '

swift package --package-path "$RUN_ROOT" resolve

RESOLVED_PATH="$RUN_ROOT/Package.resolved" \
VERSION="$VERSION" EXPECTED_COMMIT="$EXPECTED_COMMIT" \
    ruby -r json -e '
      document = JSON.parse(File.binread(ENV.fetch("RESOLVED_PATH")))
      pins = document.fetch("pins")
      pin = pins.find { |candidate| candidate.fetch("identity") == "pocketroot" }
      abort "Resolved package does not contain PocketRoot." unless pin
      state = pin.fetch("state")
      abort "Resolved PocketRoot version mismatch." unless
        state.fetch("version") == ENV.fetch("VERSION")
      abort "Resolved PocketRoot commit mismatch." unless
        state.fetch("revision") == ENV.fetch("EXPECTED_COMMIT")
    '

echo "SwiftPM exact-version consumer resolved PocketRoot $VERSION at $EXPECTED_COMMIT."
