#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PARSER="$ROOT_DIR/Scripts/select-ios18-simulator-runtime.awk"
SIMULATOR_RUNNER="$ROOT_DIR/Scripts/run-runtime-smoke.sh"
DEVICE_RUNNER="$ROOT_DIR/Scripts/run-runtime-device-smoke.sh"
PROJECT_SPEC="$ROOT_DIR/project.yml"

assert_runtime() {
    local expected="$1"
    local input="$2"
    local actual

    actual="$(printf '%s\n' "$input" | awk -f "$PARSER")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected runtime '$expected', got '$actual'." >&2
        exit 1
    fi
}

assert_runtime \
  "com.apple.CoreSimulator.SimRuntime.iOS-18-2" \
  "iOS 18.2 (18.2 - 22C150) - com.apple.CoreSimulator.SimRuntime.iOS-18-2"

assert_runtime \
  "com.apple.CoreSimulator.SimRuntime.iOS-18-4" \
  "iOS 18.4 (18.4 - 22E238) - com.apple.CoreSimulator.SimRuntime.iOS-18-4 (available)"

assert_runtime \
  "com.apple.CoreSimulator.SimRuntime.iOS-18-5" \
  $'iOS 17.5 (17.5 - 21F79) - com.apple.CoreSimulator.SimRuntime.iOS-17-5\niOS 18.5 (18.5 - 22F76) - com.apple.CoreSimulator.SimRuntime.iOS-18-5\niOS 18.6 (18.6 - 22G86) - com.apple.CoreSimulator.SimRuntime.iOS-18-6'

assert_runtime "" \
  "iOS 17.5 (17.5 - 21F79) - com.apple.CoreSimulator.SimRuntime.iOS-17-5"

bash -n "$SIMULATOR_RUNNER"
bash -n "$DEVICE_RUNNER"

if ! grep -Fq -- "-allowProvisioningDeviceRegistration" "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not allow automatic device registration." >&2
    exit 1
fi

if ! grep -Fq -- '"$SIGNED_TEAM_IDENTIFIER" != "$DEVELOPMENT_TEAM"' "$DEVICE_RUNNER" \
  || grep -Fq -- '"$SIGNED_TEAM_IDENTIFIER.$BUNDLE_ID"' "$DEVICE_RUNNER"; then
    echo "Physical-device runner assumes the App ID prefix equals the team ID." >&2
    exit 1
fi

REPORT_RESET_LINE="$(grep -nF -- '--source "$EMPTY_REPORT_PATH"' "$DEVICE_RUNNER" | cut -d: -f1)"
LAUNCH_LINE="$(grep -nF -- 'xcrun devicectl device process launch' "$DEVICE_RUNNER" | cut -d: -f1)"
if [[ -z "$REPORT_RESET_LINE" || -z "$LAUNCH_LINE" || "$REPORT_RESET_LINE" -ge "$LAUNCH_LINE" ]]; then
    echo "Physical-device runner does not clear stale evidence before launch." >&2
    exit 1
fi

if ! grep -Fq -- 'LAUNCH_CLIENT_PID=$!' "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not launch asynchronously before report polling." >&2
    exit 1
fi

if ! grep -Fq -- 'REPORT_DEADLINE=$((SECONDS + SMOKE_TIMEOUT_SECONDS))' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '--timeout "$COPY_TIMEOUT_SECONDS"' "$DEVICE_RUNNER"; then
    echo "Physical-device report polling does not use one bounded deadline." >&2
    exit 1
fi

if ! grep -Fq -- 'Success is written only after soft shutdown returned' "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not require post-shutdown success evidence." >&2
    exit 1
fi

if ! grep -Fq -- 'simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true' "$SIMULATOR_RUNNER"; then
    echo "Simulator runner cleanup is not best-effort after durable success." >&2
    exit 1
fi

if [[ "$(grep -Fc -- 'ENABLE_DEBUG_DYLIB: NO' "$PROJECT_SPEC")" -lt 2 ]]; then
    echo "Native runtime harnesses must use a single executable layout." >&2
    exit 1
fi

if ! grep -Fq -- 'The native smoke App exited before writing its report.' "$SIMULATOR_RUNNER"; then
    echo "Simulator runner does not distinguish early App exit from timeout." >&2
    exit 1
fi

set +e
RUNNER_OUTPUT="$($DEVICE_RUNNER 2>&1)"
RUNNER_STATUS=$?
set -e
if [[ "$RUNNER_STATUS" -ne 2 || "$RUNNER_OUTPUT" != *"POCKETROOT_SMOKE_DEVICE"* ]]; then
    echo "Physical-device runner did not reject missing required inputs." >&2
    exit 1
fi

echo "Runtime smoke script tests passed."
