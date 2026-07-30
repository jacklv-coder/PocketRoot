#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
APP_DIR="${POCKETROOT_UI_APP_DIR:?POCKETROOT_UI_APP_DIR is required}"
PROJECT_NAME="${POCKETROOT_UI_PROJECT_NAME:?POCKETROOT_UI_PROJECT_NAME is required}"
SCHEME="${POCKETROOT_UI_SCHEME:?POCKETROOT_UI_SCHEME is required}"
TEST_BUNDLE="${POCKETROOT_UI_TEST_BUNDLE:?POCKETROOT_UI_TEST_BUNDLE is required}"
ARTIFACT_LABEL="${POCKETROOT_UI_ARTIFACT_LABEL:-PocketRoot Example}"
ARCHIVE_PATH="${1:-${POCKETROOT_ROOTFS_ARCHIVE:-}}"
DEVICE_UDID="${POCKETROOT_UI_SMOKE_DEVICE:-}"
SIMULATOR_DEVICE_TYPE="${POCKETROOT_UI_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16}"
SIMULATOR_NAME="${POCKETROOT_UI_DEVICE_NAME:-PocketRoot-Example-UI-Smoke-$$}"
CREATED_DEVICE="false"
DERIVED_DATA_ROOT="$(
    mktemp -d "${TMPDIR:-/tmp}/PocketRootExampleUISmoke.XXXXXX"
)"
RESULT_BUNDLE_PATH="$DERIVED_DATA_ROOT/$TEST_BUNDLE.xcresult"
CLONED_SOURCE_PACKAGES_DIR="${POCKETROOT_CLONED_SOURCE_PACKAGES_DIR:-${TMPDIR:-/tmp}/PocketRootSharedSourcePackages}"
ONLY_TESTING="${POCKETROOT_UI_ONLY_TESTING:-$TEST_BUNDLE/$TEST_BUNDLE}"
DEFAULT_TEST_ALLOWANCE="${POCKETROOT_UI_DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-300}"
MAXIMUM_TEST_ALLOWANCE="${POCKETROOT_UI_MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE:-600}"

cleanup() {
    if [[ "$CREATED_DEVICE" == "true" &&
          "${POCKETROOT_KEEP_SIMULATOR:-0}" != "1" ]]; then
        xcrun simctl shutdown "$DEVICE_UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$DEVICE_UDID" >/dev/null 2>&1 || true
    fi
    if [[ "${POCKETROOT_KEEP_UI_RESULT:-0}" == "1" ]]; then
        echo "$ARTIFACT_LABEL UI artifacts retained at $DERIVED_DATA_ROOT"
    else
        rm -rf "$DERIVED_DATA_ROOT"
    fi
}
trap cleanup EXIT

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
    echo "Usage: POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz $0" >&2
    exit 2
fi
if [[ ! -d "$APP_DIR" ||
      ! -f "$APP_DIR/project.yml" ]]; then
    echo "$ARTIFACT_LABEL project inputs are unavailable at $APP_DIR." >&2
    exit 2
fi
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "$ARTIFACT_LABEL UI smoke requires an Apple Silicon host." >&2
    exit 2
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "$ARTIFACT_LABEL UI smoke requires XcodeGen." >&2
    exit 2
fi
if [[ ! "$DEFAULT_TEST_ALLOWANCE" =~ ^[1-9][0-9]*$ ||
      ! "$MAXIMUM_TEST_ALLOWANCE" =~ ^[1-9][0-9]*$ ||
      "$DEFAULT_TEST_ALLOWANCE" -gt "$MAXIMUM_TEST_ALLOWANCE" ]]; then
    echo "Example UI test allowances must be positive integers with default <= maximum." >&2
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
    cd "$APP_DIR"
    xcodegen generate --spec project.yml
)

xcrun simctl boot "$DEVICE_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_UDID" -b

set +e
POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE="$ARCHIVE_PATH" \
xcodebuild \
  -quiet \
  -project "$APP_DIR/$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_ROOT" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance "$DEFAULT_TEST_ALLOWANCE" \
  -maximum-test-execution-time-allowance "$MAXIMUM_TEST_ALLOWANCE" \
  "-only-testing:$ONLY_TESTING" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  test
test_exit_code=$?
set -e

if [[ "$test_exit_code" -ne 0 ]]; then
    echo "$ARTIFACT_LABEL UI smoke failed; xcresult summary follows." >&2
    xcrun xcresulttool get test-results summary \
      --path "$RESULT_BUNDLE_PATH" || true
    exit "$test_exit_code"
fi

echo "$ARTIFACT_LABEL UI smoke passed."
