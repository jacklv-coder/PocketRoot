#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
HOST_APP_DIR="$ROOT_DIR/Examples/PocketRootHostApp"
ARCHIVE_PATH="${1:-${POCKETROOT_ROOTFS_ARCHIVE:-}}"
DEVICE_REFERENCE="${POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE:-}"
DEVELOPMENT_TEAM="${POCKETROOT_DEVELOPMENT_TEAM:-}"
BUNDLE_ID="com.jacklv.examples.PocketRootHostApp"
TEST_RUNNER_BUNDLE_ID="com.jacklv.examples.PocketRootHostAppUITests.xctrunner"
SMOKE_TIMEOUT_SECONDS="${POCKETROOT_HOST_DEVICE_UI_SMOKE_TIMEOUT_SECONDS:-420}"
RUN_ROOT="$(
    mktemp -d "${TMPDIR:-/tmp}/PocketRootHostAppDeviceUISmoke.XXXXXX"
)"
DERIVED_DATA_ROOT="$RUN_ROOT/DerivedData"
CLONED_SOURCE_PACKAGES_DIR="${POCKETROOT_CLONED_SOURCE_PACKAGES_DIR:-${TMPDIR:-/tmp}/PocketRootSharedSourcePackages}"
DEVICE_DETAILS_PATH="$RUN_ROOT/device-details.json"
ENTITLEMENTS_PATH="$RUN_ROOT/PocketRootHostApp.entitlements.plist"
TEST_RUNNER_ENTITLEMENTS_PATH="$RUN_ROOT/PocketRootHostAppUITests.entitlements.plist"
DEVICE_ID=""
APP_INSTALLED="false"
TEST_RUNNER_INSTALLED="false"
ONLY_TESTING="PocketRootHostAppUITests/PocketRootHostAppUITests/testPTYLifecycleAndShutdown"

cleanup() {
    if [[ "$TEST_RUNNER_INSTALLED" == "true" ]]; then
        xcrun devicectl device uninstall app \
          --device "$DEVICE_ID" \
          "$TEST_RUNNER_BUNDLE_ID" \
          >/dev/null 2>&1 || true
    fi
    if [[ "$APP_INSTALLED" == "true" &&
          "${POCKETROOT_KEEP_DEVICE_APP:-0}" != "1" ]]; then
        xcrun devicectl device uninstall app \
          --device "$DEVICE_ID" \
          "$BUNDLE_ID" \
          >/dev/null 2>&1 || true
    fi
    if [[ "${POCKETROOT_KEEP_SMOKE_ARTIFACTS:-0}" == "1" ]]; then
        echo "Preserved smoke artifacts at $RUN_ROOT"
    else
        rm -rf "$RUN_ROOT"
    fi
}
trap cleanup EXIT

usage() {
    cat >&2 <<EOF
Usage:
  POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \\
  POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE=<physical-device-reference> \\
  POCKETROOT_DEVELOPMENT_TEAM=<team-id> \\
  $0
EOF
}

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
    usage
    exit 2
fi
if [[ -z "$DEVICE_REFERENCE" ]]; then
    echo "POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE must identify one physical iPhone or iPad." >&2
    usage
    exit 2
fi
if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "POCKETROOT_DEVELOPMENT_TEAM must be a 10-character Apple team ID." >&2
    exit 2
fi
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "The Host App physical-device UI smoke requires an Apple Silicon host." >&2
    exit 2
fi
if [[ ! "$SMOKE_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
  || [[ "$SMOKE_TIMEOUT_SECONDS" -lt 60 ]]; then
    echo "POCKETROOT_HOST_DEVICE_UI_SMOKE_TIMEOUT_SECONDS must be an integer of at least 60." >&2
    exit 2
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "The Host App physical-device UI smoke requires XcodeGen." >&2
    exit 2
fi

xcrun devicectl device info details \
  --device "$DEVICE_REFERENCE" \
  --timeout 30 \
  --json-output "$DEVICE_DETAILS_PATH" \
  >/dev/null 2>&1 || true
DEVICE_ID="$(
  plutil -extract result.hardwareProperties.udid raw \
    -o - "$DEVICE_DETAILS_PATH" 2>/dev/null || true
)"
DEVICE_PLATFORM="$(
  plutil -extract result.hardwareProperties.platform raw \
    -o - "$DEVICE_DETAILS_PATH" 2>/dev/null || true
)"
DEVICE_REALITY="$(
  plutil -extract result.hardwareProperties.reality raw \
    -o - "$DEVICE_DETAILS_PATH" 2>/dev/null || true
)"
DEVICE_OS_VERSION="$(
  plutil -extract result.deviceProperties.osVersionNumber raw \
    -o - "$DEVICE_DETAILS_PATH" 2>/dev/null || true
)"
if [[ -z "$DEVICE_ID" || "$DEVICE_PLATFORM" != "iOS" || "$DEVICE_REALITY" != "physical" ]]; then
    echo "POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE did not resolve to a physical iOS device." >&2
    exit 2
fi
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
if [[ ! "$DEVICE_OS_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] \
  || [[ ! "$SDK_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    echo "Could not compare the selected device OS and installed iOS SDK versions." >&2
    exit 2
fi
if ! awk -v device="$DEVICE_OS_VERSION" -v sdk="$SDK_VERSION" '
  BEGIN {
    split(device, device_parts, ".")
    split(sdk, sdk_parts, ".")
    if (device_parts[1] < sdk_parts[1]) {
      exit 0
    }
    if (device_parts[1] == sdk_parts[1] &&
        device_parts[2] <= sdk_parts[2]) {
      exit 0
    }
    exit 1
  }
'; then
    echo "The selected device runs iOS $DEVICE_OS_VERSION, newer than the installed iOS $SDK_VERSION SDK." >&2
    echo "Install an Xcode release whose device-support range includes iOS $DEVICE_OS_VERSION." >&2
    exit 2
fi
echo "Resolved physical device reference '$DEVICE_REFERENCE' to hardware UDID '$DEVICE_ID'."

mkdir -p "$CLONED_SOURCE_PACKAGES_DIR"
(
    cd "$HOST_APP_DIR"
    xcodegen generate --spec project.yml
)

COMMON_XCODEBUILD_ARGUMENTS=(
  -quiet
  -project "$HOST_APP_DIR/PocketRootHostApp.xcodeproj"
  -scheme PocketRootHostApp
  -configuration Debug
  -destination "id=$DEVICE_ID"
  -derivedDataPath "$DERIVED_DATA_ROOT"
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR"
  -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance "$SMOKE_TIMEOUT_SECONDS"
  -maximum-test-execution-time-allowance "$SMOKE_TIMEOUT_SECONDS"
  "-only-testing:$ONLY_TESTING"
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=YES
  CODE_SIGN_STYLE=Automatic
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
)

POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE="$ARCHIVE_PATH" \
xcodebuild "${COMMON_XCODEBUILD_ARGUMENTS[@]}" build-for-testing

APP_PATH="$DERIVED_DATA_ROOT/Build/Products/Debug-iphoneos/PocketRootHostApp.app"
TEST_RUNNER_PATH="$DERIVED_DATA_ROOT/Build/Products/Debug-iphoneos/PocketRootHostAppUITests-Runner.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Host App was not produced at $APP_PATH" >&2
    exit 1
fi
if [[ ! -d "$TEST_RUNNER_PATH" ]]; then
    echo "Host App UI test runner was not produced at $TEST_RUNNER_PATH" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
codesign --verify --deep --strict "$TEST_RUNNER_PATH"
codesign -d --entitlements :- "$APP_PATH" >"$ENTITLEMENTS_PATH" 2>/dev/null
codesign -d --entitlements :- "$TEST_RUNNER_PATH" \
  >"$TEST_RUNNER_ENTITLEMENTS_PATH" 2>/dev/null
APPLICATION_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$ENTITLEMENTS_PATH")"
SIGNED_TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$ENTITLEMENTS_PATH")"
GET_TASK_ALLOW="$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$ENTITLEMENTS_PATH")"
TEST_RUNNER_APPLICATION_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$TEST_RUNNER_ENTITLEMENTS_PATH")"
TEST_RUNNER_SIGNED_TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$TEST_RUNNER_ENTITLEMENTS_PATH")"
TEST_RUNNER_GET_TASK_ALLOW="$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$TEST_RUNNER_ENTITLEMENTS_PATH")"
if [[ "$SIGNED_TEAM_IDENTIFIER" != "$DEVELOPMENT_TEAM" ]]; then
    echo "Signed team identifier does not match POCKETROOT_DEVELOPMENT_TEAM." >&2
    exit 1
fi
if [[ "$TEST_RUNNER_SIGNED_TEAM_IDENTIFIER" != "$DEVELOPMENT_TEAM" ]]; then
    echo "Signed UI test runner team identifier does not match POCKETROOT_DEVELOPMENT_TEAM." >&2
    exit 1
fi
if [[ "$APPLICATION_IDENTIFIER" != *".$BUNDLE_ID" ]]; then
    echo "Signed application identifier does not match the Host App bundle ID." >&2
    exit 1
fi
if [[ "$TEST_RUNNER_APPLICATION_IDENTIFIER" != *".$TEST_RUNNER_BUNDLE_ID" ]]; then
    echo "Signed application identifier does not match the UI test runner bundle ID." >&2
    exit 1
fi
if [[ "$GET_TASK_ALLOW" != "true" ]]; then
    echo "Physical-device UI smoke requires a development provisioning profile." >&2
    exit 1
fi
if [[ "$TEST_RUNNER_GET_TASK_ALLOW" != "true" ]]; then
    echo "Physical-device UI test runner requires a development provisioning profile." >&2
    exit 1
fi
echo "Signed entitlements: application-identifier=$APPLICATION_IDENTIFIER, get-task-allow=$GET_TASK_ALLOW"
echo "Signed UI test runner entitlements: application-identifier=$TEST_RUNNER_APPLICATION_IDENTIFIER, get-task-allow=$TEST_RUNNER_GET_TASK_ALLOW"

xcrun devicectl device uninstall app \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID" \
  >/dev/null 2>&1 || true
xcrun devicectl device uninstall app \
  --device "$DEVICE_ID" \
  "$TEST_RUNNER_BUNDLE_ID" \
  >/dev/null 2>&1 || true
APP_INSTALLED="true"
TEST_RUNNER_INSTALLED="true"
POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE="$ARCHIVE_PATH" \
xcodebuild "${COMMON_XCODEBUILD_ARGUMENTS[@]}" test-without-building

echo "PocketRoot Host App physical-device UI smoke passed."
