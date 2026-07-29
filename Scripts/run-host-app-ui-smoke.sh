#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
HOST_APP_DIR="$ROOT_DIR/Examples/PocketRootHostApp"
ARCHIVE_PATH="${1:-${POCKETROOT_ROOTFS_ARCHIVE:-}}"
DEVICE_UDID="${POCKETROOT_HOST_UI_SMOKE_DEVICE:-}"
SIMULATOR_DEVICE_TYPE="${POCKETROOT_HOST_UI_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16}"
SIMULATOR_NAME="${POCKETROOT_HOST_UI_DEVICE_NAME:-PocketRoot-Host-UI-Smoke-$$}"
CREATED_DEVICE="false"
DERIVED_DATA_ROOT="$(
    mktemp -d "${TMPDIR:-/tmp}/PocketRootHostAppUISmoke.XXXXXX"
)"
RESULT_BUNDLE_PATH="$DERIVED_DATA_ROOT/PocketRootHostAppUITests.xcresult"
CLONED_SOURCE_PACKAGES_DIR="${POCKETROOT_CLONED_SOURCE_PACKAGES_DIR:-${TMPDIR:-/tmp}/PocketRootSharedSourcePackages}"
ONLY_TESTING="${POCKETROOT_HOST_UI_ONLY_TESTING:-PocketRootHostAppUITests/PocketRootHostAppUITests}"

cleanup() {
    if [[ "$CREATED_DEVICE" == "true" &&
          "${POCKETROOT_KEEP_SIMULATOR:-0}" != "1" ]]; then
        xcrun simctl shutdown "$DEVICE_UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$DEVICE_UDID" >/dev/null 2>&1 || true
    fi
    if [[ "${POCKETROOT_KEEP_UI_RESULT:-0}" == "1" ]]; then
        echo "PocketRoot Host App UI artifacts retained at $DERIVED_DATA_ROOT"
    else
        rm -rf "$DERIVED_DATA_ROOT"
    fi
}
trap cleanup EXIT

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
    echo "Usage: POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz $0" >&2
    exit 2
fi
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "The Host App UI smoke requires an Apple Silicon host." >&2
    exit 2
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "The Host App UI smoke requires XcodeGen." >&2
    exit 2
fi

if [[ -z "$DEVICE_UDID" ]]; then
    RUNTIME_ID="$(
        xcrun simctl list runtimes available \
          | awk -f "$ROOT_DIR/Scripts/select-ios18-simulator-runtime.awk"
    )"
    if [[ -z "$RUNTIME_ID" ]]; then
        echo "No available iOS 18 Simulator runtime was found." >&2
        exit 2
    fi
    DEVICE_UDID="$(xcrun simctl create \
      "$SIMULATOR_NAME" \
      "$SIMULATOR_DEVICE_TYPE" \
      "$RUNTIME_ID")"
    CREATED_DEVICE="true"
fi
if [[ -z "$DEVICE_UDID" ]]; then
    echo "No available iOS 18 Simulator was found." >&2
    exit 2
fi

mkdir -p "$CLONED_SOURCE_PACKAGES_DIR"
(
    cd "$HOST_APP_DIR"
    xcodegen generate --spec project.yml
)

xcrun simctl boot "$DEVICE_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_UDID" -b

set +e
POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE="$ARCHIVE_PATH" \
xcodebuild \
  -quiet \
  -project "$HOST_APP_DIR/PocketRootHostApp.xcodeproj" \
  -scheme PocketRootHostApp \
  -configuration Debug \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_ROOT" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 300 \
  "-only-testing:$ONLY_TESTING" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  test
test_exit_code=$?
set -e

if [[ "$test_exit_code" -ne 0 ]]; then
    echo "PocketRoot Host App UI smoke failed; xcresult summary follows." >&2
    xcrun xcresulttool get test-results summary \
      --path "$RESULT_BUNDLE_PATH" || true
    exit "$test_exit_code"
fi

echo "PocketRoot Host App UI smoke passed."
