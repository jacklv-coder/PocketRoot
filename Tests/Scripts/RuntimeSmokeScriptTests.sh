#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PARSER="$ROOT_DIR/Scripts/select-ios18-simulator-runtime.awk"
SIMULATOR_RUNNER="$ROOT_DIR/Scripts/run-runtime-smoke.sh"
DEVICE_RUNNER="$ROOT_DIR/Scripts/run-runtime-device-smoke.sh"
PROJECT_SPEC="$ROOT_DIR/project.yml"
SMOKE_APP="$ROOT_DIR/Spikes/PocketRootIshRuntimeSmoke/PocketRootIshRuntimeSmoke.swift"

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

if ! grep -Fq -- '--json-output "$DEVICE_DETAILS_PATH"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'result.hardwareProperties.udid' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"$DEVICE_PLATFORM" != "iOS"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"$DEVICE_REALITY" != "physical"' "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not resolve and validate a hardware UDID." >&2
    exit 1
fi

if ! grep -Fq -- '"$SIGNED_TEAM_IDENTIFIER" != "$DEVELOPMENT_TEAM"' "$DEVICE_RUNNER" \
  || grep -Fq -- '"$SIGNED_TEAM_IDENTIFIER.$BUNDLE_ID"' "$DEVICE_RUNNER"; then
    echo "Physical-device runner assumes the App ID prefix equals the team ID." >&2
    exit 1
fi

REPORT_RESET_LINE="$(
  grep -nF -- '--destination "Documents/$REPORT_NAME"' "$DEVICE_RUNNER" \
    | head -1 \
    | cut -d: -f1
)"
LAUNCH_LINE="$(
  grep -nF -- 'xcrun devicectl device process launch' "$DEVICE_RUNNER" \
    | head -1 \
    | cut -d: -f1
)"
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

if ! grep -Fq -- 'POCKETROOT_SMOKE_LIFECYCLE must be 0 or 1.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'result.process.processIdentifier' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'xcrun devicectl device process suspend' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'xcrun devicectl device process resume' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'Documents/$RESUME_MARKER_NAME' "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not control the lifecycle suspend/resume gate." >&2
    exit 1
fi

if ! grep -Fq -- '--destination "Documents/$PROGRESS_NAME"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'remote_process_matches_smoke_app' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'plutil -extract result.runningProcesses xml1' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'process_identifier == expected_pid' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'retrieve_device_report "$COPY_TIMEOUT_SECONDS"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'bounded_smoke_timeout 15' "$DEVICE_RUNNER" \
  || grep -Fq -- 'jq ' "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not reject stale or unsafe lifecycle evidence." >&2
    exit 1
fi

if ! grep -Fq -- 'name: "process-suspend-resume"' "$SMOKE_APP" \
  || ! grep -Fq -- 'awaitHostSuspendResume(in: documentsURL)' "$SMOKE_APP" \
  || ! grep -Fq -- 'after-suspend-resume-ok' "$SMOKE_APP"; then
    echo "Native smoke does not verify guest recovery after process resume." >&2
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

if ! grep -Fq -- 'try fileManager.createDirectory(' "$SMOKE_APP" \
  || ! grep -Fq -- 'at: applicationSupportURL,' "$SMOKE_APP"; then
    echo "Native smoke does not create the RootFS installation base." >&2
    exit 1
fi

if ! grep -Fq -- '/bin/dd if=/dev/zero bs=65536 count=128 2>/dev/null' "$SMOKE_APP" \
  || ! grep -Fq -- '/bin/dd if=/dev/zero bs=65536 count=129 2>/dev/null' "$SMOKE_APP" \
  || ! grep -Fq -- 'sustainedOutput.standardOutput.allSatisfy { $0 == 0 }' "$SMOKE_APP"; then
    echo "Native smoke does not verify sustained binary output byte-for-byte." >&2
    exit 1
fi

if ! grep -Fq -- 'maximumPeakResidentBytes: UInt64 = 256 * 1_024 * 1_024' "$SMOKE_APP" \
  || ! grep -Fq -- 'getrusage(RUSAGE_SELF, &usage)' "$SMOKE_APP" \
  || ! grep -Fq -- 'peakResidentBytes <= maximumPeakResidentBytes' "$SMOKE_APP"; then
    echo "Native smoke does not enforce the lifecycle peak-memory gate." >&2
    exit 1
fi

if ! grep -Fq -- 'The native smoke App exited before writing its report.' "$SIMULATOR_RUNNER"; then
    echo "Simulator runner does not distinguish early App exit from timeout." >&2
    exit 1
fi

if ! grep -Fq -- 'Last native smoke progress:' "$SIMULATOR_RUNNER"; then
    echo "Simulator runner does not report the last durable progress marker." >&2
    exit 1
fi

if ! grep -Fq -- 'simctl launch exit status:' "$SIMULATOR_RUNNER"; then
    echo "Simulator runner does not report the launch client exit status." >&2
    exit 1
fi

if ! grep -Fq -- 'eventMessage CONTAINS[c] \"$BUNDLE_ID\"' "$SIMULATOR_RUNNER"; then
    echo "Simulator runner does not include system termination events." >&2
    exit 1
fi

if ! grep -Fq -- 'Library/Logs/DiagnosticReports' "$SIMULATOR_RUNNER" \
  || ! grep -Fq -- 'Simulator crash report:' "$SIMULATOR_RUNNER"; then
    echo "Simulator runner does not print matching crash reports." >&2
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
