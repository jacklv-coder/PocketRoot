#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="${1:-${POCKETROOT_ROOTFS_ARCHIVE:-}}"
DEVICE_UDID="${POCKETROOT_SMOKE_DEVICE:-}"
CREATED_DEVICE="false"
SIMCTL_LAUNCH_PID=""
BUNDLE_ID="com.jacklv.PocketRootIshRuntimeSmoke"
ARCHIVE_NAME="pocketroot-fs-v0.3.3.tar.gz"
REPORT_NAME="pocketroot-smoke-result.json"
EXPECTED_SHA256="be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
EXPECTED_BYTE_COUNT="6581376"
SMOKE_TIMEOUT_SECONDS="${POCKETROOT_SMOKE_TIMEOUT_SECONDS:-300}"
DERIVED_DATA_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootRuntimeSmoke.XXXXXX")"
CLONED_SOURCE_PACKAGES_DIR="${POCKETROOT_CLONED_SOURCE_PACKAGES_DIR:-${TMPDIR:-/tmp}/PocketRootSharedSourcePackages}"

cleanup() {
    if [[ -n "$DEVICE_UDID" ]]; then
        xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$SIMCTL_LAUNCH_PID" ]]; then
        wait "$SIMCTL_LAUNCH_PID" >/dev/null 2>&1 || true
    fi
    if [[ "$CREATED_DEVICE" == "true" && "${POCKETROOT_KEEP_SIMULATOR:-0}" != "1" ]]; then
        xcrun simctl shutdown "$DEVICE_UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$DEVICE_UDID" >/dev/null 2>&1 || true
    fi
    rm -rf "$DERIVED_DATA_ROOT"
}
trap cleanup EXIT

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
    echo "Usage: POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz $0" >&2
    exit 2
fi
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "The native smoke requires an Apple Silicon host." >&2
    exit 2
fi
if [[ ! "$SMOKE_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "POCKETROOT_SMOKE_TIMEOUT_SECONDS must be a positive integer." >&2
    exit 2
fi

if [[ "$(stat -f '%z' "$ARCHIVE_PATH")" != "$EXPECTED_BYTE_COUNT" ]]; then
    echo "RootFS archive size does not match the pinned v0.3.3 artifact." >&2
    exit 2
fi
echo "$EXPECTED_SHA256  $ARCHIVE_PATH" | shasum -a 256 --check

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
      "PocketRoot-iOS18-Smoke-$$" \
      com.apple.CoreSimulator.SimDeviceType.iPhone-16 \
      "$RUNTIME_ID")"
    CREATED_DEVICE="true"
fi
if [[ -z "$DEVICE_UDID" ]]; then
    echo "No available iOS 18 Simulator was found." >&2
    exit 2
fi

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/generate-project.sh"
mkdir -p "$CLONED_SOURCE_PACKAGES_DIR"

xcrun simctl boot "$DEVICE_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_UDID" -b

xcodebuild \
  -project PocketRootDemo.xcodeproj \
  -scheme PocketRootIshRuntimeSmoke \
  -configuration Debug \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_ROOT" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA_ROOT/Build/Products/Debug-iphonesimulator/PocketRootIshRuntimeSmoke.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Smoke app was not produced at $APP_PATH" >&2
    exit 1
fi

xcrun simctl uninstall "$DEVICE_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_UDID" "$APP_PATH"
DATA_CONTAINER="$(xcrun simctl get_app_container "$DEVICE_UDID" "$BUNDLE_ID" data)"
mkdir -p "$DATA_CONTAINER/Documents"
install -m 0644 "$ARCHIVE_PATH" "$DATA_CONTAINER/Documents/$ARCHIVE_NAME"
rm -f "$DATA_CONTAINER/Documents/$REPORT_NAME"

CONSOLE_LOG="$DERIVED_DATA_ROOT/native-smoke-console.log"
xcrun simctl launch \
  --console \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  >"$CONSOLE_LOG" 2>&1 &
SIMCTL_LAUNCH_PID=$!

REPORT_PATH="$DATA_CONTAINER/Documents/$REPORT_NAME"
for _ in $(seq 1 $((SMOKE_TIMEOUT_SECONDS * 4))); do
    if [[ -f "$REPORT_PATH" ]]; then
        break
    fi
    if ! kill -0 "$SIMCTL_LAUNCH_PID" >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

if [[ ! -f "$REPORT_PATH" ]]; then
    echo "Timed out waiting for the native smoke report." >&2
    cat "$CONSOLE_LOG" >&2 || true
    xcrun simctl spawn "$DEVICE_UDID" log show \
      --style compact \
      --last 5m \
      --predicate 'process == "PocketRootIshRuntimeSmoke"' \
      | tail -200 >&2 || true
    exit 1
fi

cat "$REPORT_PATH"
if [[ "$(plutil -extract success raw -o - "$REPORT_PATH")" != "true" ]]; then
    exit 1
fi

# Success is written only after native shutdown returned, `.terminated` was
# observed, and a later command returned restartRequired. Stop the otherwise
# idle smoke App explicitly; process exit is cleanup, not lifecycle evidence.
xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
APP_EXITED="false"
for _ in $(seq 1 80); do
    if ! kill -0 "$SIMCTL_LAUNCH_PID" >/dev/null 2>&1; then
        APP_EXITED="true"
        break
    fi
    sleep 0.25
done
if [[ "$APP_EXITED" != "true" ]]; then
    echo "The verified smoke App did not stop during runner cleanup." >&2
    cat "$CONSOLE_LOG" >&2 || true
    exit 1
fi

wait "$SIMCTL_LAUNCH_PID" >/dev/null 2>&1 || true
SIMCTL_LAUNCH_PID=""
cat "$CONSOLE_LOG"
