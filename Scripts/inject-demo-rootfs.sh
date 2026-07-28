#!/usr/bin/env bash

set -euo pipefail

EXPECTED_BYTE_COUNT="6581376"
EXPECTED_SHA256="be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
RESOURCE_FILE_NAME="pocketroot-fs-v0.3.3.tar.gz"
DEVELOPMENT_ASSET_DIRECTORY="${POCKETROOT_DEMO_DEVELOPMENT_ASSET_DIRECTORY:-${HOME}/Library/Application Support/PocketRootDevelopment/RootFS}"
DEVELOPMENT_ASSET_PATH="$DEVELOPMENT_ASSET_DIRECTORY/$RESOURCE_FILE_NAME"
REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

validate_archive() {
    local archive_path="$1"
    local archive_directory
    local archive_name
    local actual_byte_count
    local actual_sha256

    if [[ ! -f "$archive_path" || -L "$archive_path" ]]; then
        echo "PocketRoot Demo RootFS must be a regular, non-symbolic-link file: $archive_path" >&2
        return 2
    fi

    archive_directory="$(cd "$(dirname "$archive_path")" && pwd -P)"
    archive_name="$(basename "$archive_path")"
    RESOLVED_ARCHIVE_PATH="$archive_directory/$archive_name"

    case "$RESOLVED_ARCHIVE_PATH" in
        "$REPOSITORY_ROOT"|"$REPOSITORY_ROOT"/*)
            echo "RootFS input must remain outside the source repository." >&2
            return 2
            ;;
    esac

    actual_byte_count="$(stat -f '%z' "$RESOLVED_ARCHIVE_PATH")"
    if [[ "$actual_byte_count" != "$EXPECTED_BYTE_COUNT" ]]; then
        echo "PocketRoot Demo RootFS size mismatch." >&2
        echo "Expected $EXPECTED_BYTE_COUNT bytes, got $actual_byte_count." >&2
        return 2
    fi

    actual_sha256="$(shasum -a 256 "$RESOLVED_ARCHIVE_PATH" | awk '{print $1}')"
    if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
        echo "PocketRoot Demo RootFS SHA-256 mismatch." >&2
        echo "Expected $EXPECTED_SHA256, got $actual_sha256." >&2
        return 2
    fi
}

install_atomically() {
    local source_path="$1"
    local destination="$2"
    local destination_directory
    local temporary_destination

    destination_directory="$(dirname "$destination")"
    mkdir -p "$destination_directory"
    temporary_destination="$(mktemp "$destination.XXXXXX")"
    cleanup() {
        rm -f "$temporary_destination"
    }
    trap cleanup EXIT

    install -m 0444 "$source_path" "$temporary_destination"
    mv -f "$temporary_destination" "$destination"
    trap - EXIT
}

if [[ "${1:-}" == "--install-development-archive" ]]; then
    if [[ "$#" != 2 ]]; then
        echo "Usage: $0 --install-development-archive /absolute/path/to/fs.tar.gz" >&2
        exit 2
    fi
    validate_archive "$2"
    install_atomically "$RESOLVED_ARCHIVE_PATH" "$DEVELOPMENT_ASSET_PATH"
    echo "PocketRoot Demo: configured reviewed development RootFS at $DEVELOPMENT_ASSET_PATH"
    exit 0
fi

if [[ "$#" != 0 ]]; then
    echo "Unknown arguments: $*" >&2
    exit 2
fi

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
    echo "TARGET_BUILD_DIR and UNLOCALIZED_RESOURCES_FOLDER_PATH are required." >&2
    exit 2
fi

RESOURCE_DIRECTORY="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
DESTINATION="$RESOURCE_DIRECTORY/$RESOURCE_FILE_NAME"
EXPLICIT_ARCHIVE_PATH="${POCKETROOT_DEMO_ROOTFS_ARCHIVE:-}"
BUILD_CONFIGURATION="${CONFIGURATION:-Debug}"

if [[ "$BUILD_CONFIGURATION" != "Debug" ]]; then
    rm -f "$DESTINATION"
    if [[ -n "$EXPLICIT_ARCHIVE_PATH" ]]; then
        echo "PocketRoot Demo RootFS injection is restricted to Debug builds." >&2
        echo "Release/TestFlight/App Store bundling remains blocked by release-compliance gates." >&2
        exit 2
    fi
    echo "PocketRoot Demo: RootFS injection skipped for $BUILD_CONFIGURATION."
    exit 0
fi

ARCHIVE_PATH="${EXPLICIT_ARCHIVE_PATH:-$DEVELOPMENT_ASSET_PATH}"
if [[ ! -e "$ARCHIVE_PATH" ]]; then
    rm -f "$DESTINATION"
    echo "PocketRoot Demo: no RootFS injected."
    echo "Configure one with:"
    echo "  $0 --install-development-archive /absolute/path/to/fs.tar.gz"
    exit 0
fi

validate_archive "$ARCHIVE_PATH"
install_atomically "$RESOLVED_ARCHIVE_PATH" "$DESTINATION"

echo "PocketRoot Demo: injected reviewed RootFS at $DESTINATION"
