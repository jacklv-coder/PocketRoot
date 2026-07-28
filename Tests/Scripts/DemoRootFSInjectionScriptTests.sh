#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/Scripts/inject-demo-rootfs.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootDemoRootFSTests.XXXXXX")"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

export POCKETROOT_DEMO_DEVELOPMENT_ASSET_DIRECTORY="$TEST_ROOT/development-rootfs"
export TARGET_BUILD_DIR="$TEST_ROOT/build"
export UNLOCALIZED_RESOURCES_FOLDER_PATH="PocketRootDemo.app"
export CONFIGURATION="Debug"
DESTINATION="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/pocketroot-fs-v0.3.3.tar.gz"

mkdir -p "$(dirname "$DESTINATION")"
printf 'stale' > "$DESTINATION"
"$SCRIPT"
if [[ -e "$DESTINATION" ]]; then
    echo "A missing development RootFS did not remove stale bundle output." >&2
    exit 1
fi

BAD_ARCHIVE="$TEST_ROOT/bad.tar.gz"
printf 'not-a-rootfs' > "$BAD_ARCHIVE"
if POCKETROOT_DEMO_ROOTFS_ARCHIVE="$BAD_ARCHIVE" "$SCRIPT" \
    >"$TEST_ROOT/bad.stdout" 2>"$TEST_ROOT/bad.stderr"; then
    echo "A malformed RootFS unexpectedly passed injection." >&2
    exit 1
fi
if ! grep -Fq "RootFS size mismatch" "$TEST_ROOT/bad.stderr"; then
    echo "Malformed RootFS rejection did not report a size mismatch." >&2
    exit 1
fi

SYMLINK_ARCHIVE="$TEST_ROOT/symlink.tar.gz"
ln -s "$BAD_ARCHIVE" "$SYMLINK_ARCHIVE"
if POCKETROOT_DEMO_ROOTFS_ARCHIVE="$SYMLINK_ARCHIVE" "$SCRIPT" \
    >"$TEST_ROOT/symlink.stdout" 2>"$TEST_ROOT/symlink.stderr"; then
    echo "A symbolic-link RootFS unexpectedly passed injection." >&2
    exit 1
fi
if ! grep -Fq "regular, non-symbolic-link file" "$TEST_ROOT/symlink.stderr"; then
    echo "Symbolic-link rejection did not report the input-type failure." >&2
    exit 1
fi

if POCKETROOT_DEMO_ROOTFS_ARCHIVE="$SCRIPT" "$SCRIPT" \
    >"$TEST_ROOT/source-tree.stdout" 2>"$TEST_ROOT/source-tree.stderr"; then
    echo "A source-tree RootFS input unexpectedly passed injection." >&2
    exit 1
fi
if ! grep -Fq "must remain outside the source repository" "$TEST_ROOT/source-tree.stderr"; then
    echo "Source-tree rejection did not explain the repository boundary." >&2
    exit 1
fi

export CONFIGURATION="Release"
if POCKETROOT_DEMO_ROOTFS_ARCHIVE="$BAD_ARCHIVE" "$SCRIPT" \
    >"$TEST_ROOT/release.stdout" 2>"$TEST_ROOT/release.stderr"; then
    echo "Release RootFS injection unexpectedly succeeded." >&2
    exit 1
fi
if ! grep -Fq "restricted to Debug builds" "$TEST_ROOT/release.stderr"; then
    echo "Release rejection did not explain the Debug-only boundary." >&2
    exit 1
fi

if [[ -n "${POCKETROOT_ROOTFS_ARCHIVE:-}" ]]; then
    export CONFIGURATION="Debug"
    "$SCRIPT" --install-development-archive "$POCKETROOT_ROOTFS_ARCHIVE"
    if [[ ! -f "$POCKETROOT_DEMO_DEVELOPMENT_ASSET_DIRECTORY/pocketroot-fs-v0.3.3.tar.gz" ]]; then
        echo "The reviewed development RootFS was not configured." >&2
        exit 1
    fi
    "$SCRIPT"
    if [[ ! -f "$DESTINATION" ]]; then
        echo "The configured development RootFS was not injected." >&2
        exit 1
    fi
    if [[ "$(stat -f '%z' "$DESTINATION")" != "6581376" ]]; then
        echo "The injected RootFS has the wrong size." >&2
        exit 1
    fi
    if [[ "$(shasum -a 256 "$DESTINATION" | awk '{print $1}')" != \
        "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4" ]]; then
        echo "The injected RootFS has the wrong digest." >&2
        exit 1
    fi
fi

echo "Demo RootFS injection script tests passed."
