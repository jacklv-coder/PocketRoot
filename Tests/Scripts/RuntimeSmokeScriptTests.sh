#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PARSER="$ROOT_DIR/Scripts/select-ios18-simulator-runtime.awk"
SIMULATOR_RUNNER="$ROOT_DIR/Scripts/run-runtime-smoke.sh"
DEVICE_RUNNER="$ROOT_DIR/Scripts/run-runtime-device-smoke.sh"
HOST_UI_RUNNER="$ROOT_DIR/Scripts/run-host-app-ui-smoke.sh"
HOST_DEVICE_UI_RUNNER="$ROOT_DIR/Scripts/run-host-app-device-ui-smoke.sh"
HOST_APP_SOURCE="$ROOT_DIR/Examples/PocketRootHostApp/Sources/HostApp.swift"
HOST_UI_TESTS="$ROOT_DIR/Examples/PocketRootHostApp/UITests/PocketRootHostAppUITests.swift"
HOST_PROJECT_SPEC="$ROOT_DIR/Examples/PocketRootHostApp/project.yml"
QUICK_START_SOURCE="$ROOT_DIR/Examples/PocketRootQuickStartApp/Sources/QuickStartApp.swift"
QUICK_START_PROJECT_SPEC="$ROOT_DIR/Examples/PocketRootQuickStartApp/project.yml"
PROJECT_SPEC="$ROOT_DIR/Examples/PocketRootDemo/project.yml"
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
bash -n "$HOST_UI_RUNNER"
bash -n "$HOST_DEVICE_UI_RUNNER"

if ! grep -Fq -- 'POCKETROOT_HOST_UI_SMOKE_DEVICE' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_HOST_UI_DEVICE_TYPE' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_KEEP_UI_RESULT' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'PocketRootHostAppUITests' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE="$ARCHIVE_PATH"' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- '-test-timeouts-enabled YES' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- '-default-test-execution-time-allowance 300' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- '-maximum-test-execution-time-allowance 600' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'xcrun simctl delete "$DEVICE_UDID"' "$HOST_UI_RUNNER"; then
    echo "Host App UI smoke runner is missing deterministic inputs or cleanup." >&2
    exit 1
fi

if ! grep -Fq -- 'pocketroot-system-file-ui-fixture.txt' "$HOST_APP_SOURCE" \
  || ! grep -Fq -- 'testSystemFileImportAndShareExportRoundTrip' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'Save to Files' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'LSSupportsOpeningDocumentsInPlace: true' "$HOST_PROJECT_SPEC" \
  || ! grep -Fq -- 'UIFileSharingEnabled: true' "$HOST_PROJECT_SPEC"; then
    echo "Host App UI smoke is missing the system file transfer closure." >&2
    exit 1
fi

if ! grep -Fq -- 'makeTerminalViewController()' "$QUICK_START_SOURCE" \
  || ! grep -Fq -- 'makeFilesViewController()' "$QUICK_START_SOURCE" \
  || ! grep -Fq -- 'func sceneDidDisconnect(_ scene: UIScene)' "$QUICK_START_SOURCE" \
  || ! grep -Fq -- 'pocketRootHost?.closeWorkspaces()' "$QUICK_START_SOURCE" \
  || ! grep -Fq -- 'path: ../..' "$QUICK_START_PROJECT_SPEC" \
  || ! grep -Fq -- 'product: PocketRootIshRuntimeIntegration' "$QUICK_START_PROJECT_SPEC" \
  || ! grep -Fq -- '"$SRCROOT/../../Scripts/inject-demo-rootfs.sh"' "$QUICK_START_PROJECT_SPEC"; then
    echo "Quick Start App is missing its two public entry points or package boundary." >&2
    exit 1
fi

if ! grep -Fq -- 'POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'result.hardwareProperties.udid' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- '"$DEVICE_REALITY" != "physical"' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'result.deviceProperties.osVersionNumber' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'xcrun --sdk iphoneos --show-sdk-version' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'build-for-testing' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'test-without-building' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- '"$SIGNED_TEAM_IDENTIFIER" != "$DEVELOPMENT_TEAM"' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_KEEP_SMOKE_ARTIFACTS' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'xcrun devicectl device uninstall app' "$HOST_DEVICE_UI_RUNNER"; then
    echo "Host App physical-device UI runner is missing validation or cleanup." >&2
    exit 1
fi

if ! grep -Fq -- 'POCKETROOT_ROOTFS_CANDIDATE' "$SIMULATOR_RUNNER" \
  || ! grep -Fq -- 'prepare-rootfs-smoke-manifest.rb' "$SIMULATOR_RUNNER" \
  || ! grep -Fq -- '"$DATA_CONTAINER/Documents/$SMOKE_MANIFEST_NAME"' "$SIMULATOR_RUNNER"; then
    echo "Simulator runner does not validate and inject local candidate metadata." >&2
    exit 1
fi

if ! grep -Fq -- 'POCKETROOT_ROOTFS_CANDIDATE' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'prepare-rootfs-smoke-manifest.rb' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '--destination "Documents/$SMOKE_MANIFEST_NAME"' "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not validate and inject local candidate metadata." >&2
    exit 1
fi

if ! grep -Fq -- 'rootFSInputFileName = "pocketroot-smoke-rootfs.json"' "$SMOKE_APP" \
  || ! grep -Fq -- 'distributionAuthorized' "$SMOKE_APP" \
  || ! grep -Fq -- 'healthCheck: .ishEmbedV0_3_3' "$SMOKE_APP" \
  || ! grep -Fq -- 'name: "rootfs-input"' "$SMOKE_APP"; then
    echo "Native smoke App does not fail closed on candidate metadata." >&2
    exit 1
fi

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
  || ! grep -Fq -- 'wait_for_remote_smoke_process_match' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'Retry an' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'indeterminate query within the shared smoke deadline.' "$DEVICE_RUNNER" \
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

if ! grep -Fq -- 'POCKETROOT_SMOKE_UI_LIFECYCLE must be 0 or 1.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'Select only one physical host-control smoke mode per run.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'awaiting-host-background' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '--destination "Documents/$UI_LIFECYCLE_NAME"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"$SETTINGS_BUNDLE_ID"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'REACTIVATED_PROCESS_PID' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"$REACTIVATED_PROCESS_PID" != "$REMOTE_PROCESS_PID"' "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not preserve PID across UIKit lifecycle control." >&2
    exit 1
fi

if ! grep -Fq -- 'applicationDidEnterBackground' "$SMOKE_APP" \
  || ! grep -Fq -- 'applicationWillEnterForeground' "$SMOKE_APP" \
  || ! grep -Fq -- 'applicationDidBecomeActive' "$SMOKE_APP" \
  || ! grep -Fq -- 'try fileManager.removeItem(at: eventURL)' "$SMOKE_APP" \
  || ! grep -Fq -- 'name: "ui-background-foreground"' "$SMOKE_APP" \
  || ! grep -Fq -- 'after-ui-lifecycle-ok' "$SMOKE_APP"; then
    echo "Native smoke does not verify UIKit lifecycle callback recovery." >&2
    exit 1
fi

if ! grep -Fq -- 'POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE must be 0 or 1.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'HOST_CONTROL_MODE_COUNT=' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE":"seed"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'xcrun devicectl device process terminate' "$DEVICE_RUNNER" \
  || ! grep -Fq -- "--kill \\" "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'wait_for_remote_smoke_process_exit' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'wait_for_remote_smoke_process_appearance' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE":"verify"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"$REMOTE_PROCESS_PID" == "$SEED_PROCESS_PID"' "$DEVICE_RUNNER"; then
    echo "Physical-device runner does not enforce forced-relaunch process identity." >&2
    exit 1
fi

if ! grep -Fq -- 'prepared.installation.reusedExistingInstallation' "$SMOKE_APP" \
  || ! grep -Fq -- 'name: "forced-relaunch-persistence"' "$SMOKE_APP" \
  || ! grep -Fq -- '> \(relaunchPersistenceFileName) && sync' "$SMOKE_APP" \
  || ! grep -Fq -- 'The guest marker did not survive forced App termination.' "$SMOKE_APP"; then
    echo "Native smoke does not verify guest persistence after forced relaunch." >&2
    exit 1
fi

if ! grep -Fq -- 'POCKETROOT_SMOKE_STORAGE_FAILURE must be 0 or 1.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'Storage failure smoke cannot be combined with a host-control mode.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"POCKETROOT_SMOKE_STORAGE_FAILURE":"1"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'prepareSystemForFailureInjection' "$SMOKE_APP" \
  || ! grep -Fq -- 'failureInjection: .insufficientStorage' "$SMOKE_APP" \
  || ! grep -Fq -- 'failureInjection: .gzipENOSPC' "$SMOKE_APP" \
  || ! grep -Fq -- 'catch PocketRootArchiveExtractionError.gzipDecompressionFailed' "$SMOKE_APP" \
  || ! grep -Fq -- 'name: "storage-capacity-preflight"' "$SMOKE_APP" \
  || ! grep -Fq -- 'name: "storage-enospc-cleanup"' "$SMOKE_APP" \
  || ! grep -Fq -- 'requireCleanStorageFailureWorkspace' "$SMOKE_APP" \
  || grep -Fq -- 'ATTACHED_LAUNCH_ENVIRONMENT_ARGUMENTS' "$DEVICE_RUNNER"; then
    echo "Physical-device smoke does not safely gate storage failure recovery." >&2
    exit 1
fi

if ! grep -Fq -- 'POCKETROOT_SMOKE_MEMORY_WARNING must be 0 or 1.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'Memory-warning smoke cannot be combined with another optional mode.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- '"POCKETROOT_SMOKE_MEMORY_WARNING":"1"' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'applicationDidReceiveMemoryWarning' "$SMOKE_APP" \
  || ! grep -Fq -- 'recordMemoryWarningCallback' "$SMOKE_APP" \
  || ! grep -Fq -- 'deliverMemoryWarningCallback' "$SMOKE_APP" \
  || ! grep -Fq -- 'before-warning' "$SMOKE_APP" \
  || ! grep -Fq -- 'awaitMemoryWarningCommandStart' "$SMOKE_APP" \
  || ! grep -Fq -- 'memoryWarningActiveGuestPath' "$SMOKE_APP" \
  || ! grep -Fq -- 'after-memory-warning-ok' "$SMOKE_APP" \
  || ! grep -Fq -- 'name: "memory-warning-recovery"' "$SMOKE_APP"; then
    echo "Physical-device smoke does not gate bounded memory-warning recovery." >&2
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
