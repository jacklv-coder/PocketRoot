#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="${1:-${POCKETROOT_ROOTFS_ARCHIVE:-}}"
DEVICE_REFERENCE="${POCKETROOT_SMOKE_DEVICE:-}"
DEVICE_ID=""
DEVELOPMENT_TEAM="${POCKETROOT_DEVELOPMENT_TEAM:-}"
BUNDLE_ID="com.jacklv.PocketRootIshRuntimeSmoke"
ARCHIVE_NAME="pocketroot-fs-v0.3.3.tar.gz"
REPORT_NAME="pocketroot-smoke-result.json"
EXPECTED_SHA256="be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
EXPECTED_BYTE_COUNT="6581376"
SMOKE_TIMEOUT_SECONDS="${POCKETROOT_SMOKE_TIMEOUT_SECONDS:-300}"
RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootDeviceSmoke.XXXXXX")"
DERIVED_DATA_ROOT="$RUN_ROOT/DerivedData"
CLONED_SOURCE_PACKAGES_DIR="${POCKETROOT_CLONED_SOURCE_PACKAGES_DIR:-${TMPDIR:-/tmp}/PocketRootSharedSourcePackages}"
CONSOLE_LOG="$RUN_ROOT/device-smoke-console.log"
REPORT_PATH="$RUN_ROOT/$REPORT_NAME"
EMPTY_REPORT_PATH="$RUN_ROOT/empty-$REPORT_NAME"
ENTITLEMENTS_PATH="$RUN_ROOT/PocketRootIshRuntimeSmoke.entitlements.plist"
DEVICE_DETAILS_PATH="$RUN_ROOT/device-details.json"
APP_INSTALLED="false"
LAUNCH_CLIENT_PID=""

cleanup() {
    if [[ -n "$LAUNCH_CLIENT_PID" ]] && kill -0 "$LAUNCH_CLIENT_PID" >/dev/null 2>&1; then
        kill "$LAUNCH_CLIENT_PID" >/dev/null 2>&1 || true
        wait "$LAUNCH_CLIENT_PID" >/dev/null 2>&1 || true
    fi
    if [[ "$APP_INSTALLED" == "true" && "${POCKETROOT_KEEP_DEVICE_APP:-0}" != "1" ]]; then
        xcrun devicectl device uninstall app \
          --device "$DEVICE_ID" \
          "$BUNDLE_ID" \
          >/dev/null 2>&1 || true
    fi
    rm -rf "$RUN_ROOT"
}
trap cleanup EXIT

usage() {
    cat >&2 <<EOF
Usage:
  POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz \\
  POCKETROOT_SMOKE_DEVICE=<physical-device-reference> \\
  POCKETROOT_DEVELOPMENT_TEAM=<team-id> \\
  $0
EOF
}

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
    usage
    exit 2
fi
if [[ -z "$DEVICE_REFERENCE" ]]; then
    echo "POCKETROOT_SMOKE_DEVICE must identify one physical iPhone or iPad." >&2
    usage
    exit 2
fi
if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "POCKETROOT_DEVELOPMENT_TEAM must be a 10-character Apple team ID." >&2
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
if [[ -z "$DEVICE_ID" || "$DEVICE_PLATFORM" != "iOS" || "$DEVICE_REALITY" != "physical" ]]; then
    echo "POCKETROOT_SMOKE_DEVICE did not resolve to a physical iOS device." >&2
    exit 2
fi
echo "Resolved physical device reference '$DEVICE_REFERENCE' to hardware UDID '$DEVICE_ID'."

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/generate-project.sh"
mkdir -p "$DERIVED_DATA_ROOT" "$CLONED_SOURCE_PACKAGES_DIR"

xcodebuild \
  -quiet \
  -project PocketRootDemo.xcodeproj \
  -scheme PocketRootIshRuntimeSmoke \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_ROOT" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  build

APP_PATH="$DERIVED_DATA_ROOT/Build/Products/Debug-iphoneos/PocketRootIshRuntimeSmoke.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Smoke app was not produced at $APP_PATH" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH" >"$ENTITLEMENTS_PATH" 2>/dev/null
APPLICATION_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$ENTITLEMENTS_PATH")"
SIGNED_TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$ENTITLEMENTS_PATH")"
GET_TASK_ALLOW="$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$ENTITLEMENTS_PATH")"
if [[ "$SIGNED_TEAM_IDENTIFIER" != "$DEVELOPMENT_TEAM" ]]; then
    echo "Signed team identifier does not match POCKETROOT_DEVELOPMENT_TEAM." >&2
    exit 1
fi
if [[ "$APPLICATION_IDENTIFIER" != *".$BUNDLE_ID" ]]; then
    echo "Signed application identifier does not match the smoke bundle ID." >&2
    exit 1
fi
if [[ "$GET_TASK_ALLOW" != "true" ]]; then
    echo "Physical smoke requires a development provisioning profile." >&2
    exit 1
fi
echo "Signed entitlements: application-identifier=$APPLICATION_IDENTIFIER, get-task-allow=$GET_TASK_ALLOW"

xcrun devicectl device uninstall app \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID" \
  >/dev/null 2>&1 || true
APP_INSTALLED="true"
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  --timeout "$SMOKE_TIMEOUT_SECONDS" \
  "$APP_PATH"

# An unsuccessful uninstall can leave an existing data container in place.
# Overwrite any old success report before launch so it can never satisfy this run.
touch "$EMPTY_REPORT_PATH"
xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --source "$EMPTY_REPORT_PATH" \
  --destination "Documents/$REPORT_NAME" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --timeout "$SMOKE_TIMEOUT_SECONDS"

xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --source "$ARCHIVE_PATH" \
  --destination "Documents/$ARCHIVE_NAME" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --timeout "$SMOKE_TIMEOUT_SECONDS"

xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  --console \
  --timeout "$SMOKE_TIMEOUT_SECONDS" \
  "$BUNDLE_ID" \
  >"$CONSOLE_LOG" 2>&1 &
LAUNCH_CLIENT_PID=$!

REPORT_READY="false"
REPORT_SUCCESS=""
REPORT_DEADLINE=$((SECONDS + SMOKE_TIMEOUT_SECONDS))
LAUNCH_EXIT_OBSERVED="false"
while [[ "$SECONDS" -lt "$REPORT_DEADLINE" ]]; do
    REMAINING_SECONDS=$((REPORT_DEADLINE - SECONDS))
    if [[ "$REMAINING_SECONDS" -lt 1 ]]; then
        break
    fi
    COPY_TIMEOUT_SECONDS="$REMAINING_SECONDS"
    if [[ "$COPY_TIMEOUT_SECONDS" -gt 5 ]]; then
        COPY_TIMEOUT_SECONDS=5
    fi
    rm -f "$REPORT_PATH"
    if xcrun devicectl device copy from \
      --device "$DEVICE_ID" \
      --source "Documents/$REPORT_NAME" \
      --destination "$REPORT_PATH" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --timeout "$COPY_TIMEOUT_SECONDS" \
      >/dev/null 2>&1 \
      && REPORT_SUCCESS="$(plutil -extract success raw -o - "$REPORT_PATH" 2>/dev/null)"; then
        REPORT_READY="true"
        break
    fi
    if ! kill -0 "$LAUNCH_CLIENT_PID" >/dev/null 2>&1; then
        if [[ "$LAUNCH_EXIT_OBSERVED" == "true" ]]; then
            break
        fi
        # Permit one final bounded copy attempt if the console client ends.
        LAUNCH_EXIT_OBSERVED="true"
        sleep 0.25
    else
        sleep 1
    fi
done

if [[ "$REPORT_READY" != "true" ]]; then
    cat "$CONSOLE_LOG" >&2 || true
    echo "The device smoke report could not be retrieved before launch ended or timed out." >&2
    exit 1
fi

cat "$REPORT_PATH"
if [[ "$REPORT_SUCCESS" != "true" ]]; then
    cat "$CONSOLE_LOG" >&2 || true
    exit 1
fi

# Success is written only after soft shutdown returned, `.terminated` was
# observed, and a later command returned restartRequired. Detach the console
# client; normal cleanup uninstalls the otherwise idle test App.
kill "$LAUNCH_CLIENT_PID" >/dev/null 2>&1 || true
wait "$LAUNCH_CLIENT_PID" >/dev/null 2>&1 || true
LAUNCH_CLIENT_PID=""
cat "$CONSOLE_LOG"

echo "Physical-device native smoke passed on $DEVICE_ID."
