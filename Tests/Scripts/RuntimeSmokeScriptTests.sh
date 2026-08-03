#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PARSER="$ROOT_DIR/Scripts/select-ios18-simulator-runtime.awk"
SIMULATOR_RUNNER="$ROOT_DIR/Scripts/run-runtime-smoke.sh"
DEVICE_RUNNER="$ROOT_DIR/Scripts/run-runtime-device-smoke.sh"
HOST_UI_RUNNER="$ROOT_DIR/Scripts/run-host-app-ui-smoke.sh"
HOST_DEVICE_UI_RUNNER="$ROOT_DIR/Scripts/run-host-app-device-ui-smoke.sh"
GENERIC_UI_RUNNER="$ROOT_DIR/Scripts/run-ios-example-ui-smoke.sh"
QUICK_START_UI_RUNNER="$ROOT_DIR/Scripts/run-quick-start-ui-smoke.sh"
EXTERNAL_CONSUMER_UI_RUNNER="$ROOT_DIR/Scripts/run-external-consumer-ui-smoke.sh"
HOST_APP_SOURCE="$ROOT_DIR/Examples/PocketRootHostApp/Sources/HostApp.swift"
HOST_UI_TESTS="$ROOT_DIR/Examples/PocketRootHostApp/UITests/PocketRootHostAppUITests.swift"
HOST_PROJECT_SPEC="$ROOT_DIR/Examples/PocketRootHostApp/project.yml"
QUICK_START_SOURCE="$ROOT_DIR/Examples/PocketRootQuickStartApp/Sources/QuickStartApp.swift"
QUICK_START_UI_TESTS="$ROOT_DIR/Examples/PocketRootQuickStartApp/UITests/PocketRootQuickStartAppUITests.swift"
QUICK_START_PROJECT_SPEC="$ROOT_DIR/Examples/PocketRootQuickStartApp/project.yml"
EXTERNAL_CONSUMER_FIXTURE="$ROOT_DIR/Tests/Integration/ExternalConsumerApp"
EXTERNAL_CONSUMER_SOURCE="$EXTERNAL_CONSUMER_FIXTURE/Sources/ExternalConsumerApp.swift"
EXTERNAL_CONSUMER_UI_TESTS="$EXTERNAL_CONSUMER_FIXTURE/UITests/ExternalConsumerAppUITests.swift"
EXTERNAL_CONSUMER_PROJECT_TEMPLATE="$EXTERNAL_CONSUMER_FIXTURE/project.yml.template"
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
bash -n "$GENERIC_UI_RUNNER"
bash -n "$QUICK_START_UI_RUNNER"
bash -n "$EXTERNAL_CONSUMER_UI_RUNNER"

if ! grep -Fq -- 'POCKETROOT_HOST_UI_SMOKE_DEVICE' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_HOST_UI_DEVICE_TYPE' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'PocketRootHostAppUITests' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'files-workspace' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'pty-lifecycle' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'testPTYLifecycleAndShutdown' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_HOST_UI_DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-600' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'run-ios-example-ui-smoke.sh' "$HOST_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_QUICK_START_UI_SMOKE_DEVICE' "$QUICK_START_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_QUICK_START_UI_DEVICE_TYPE' "$QUICK_START_UI_RUNNER" \
  || ! grep -Fq -- 'PocketRootQuickStartAppUITests' "$QUICK_START_UI_RUNNER" \
  || ! grep -Fq -- 'run-ios-example-ui-smoke.sh' "$QUICK_START_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_EXTERNAL_CONSUMER_REVISION' "$EXTERNAL_CONSUMER_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_EXTERNAL_CONSUMER_REPOSITORY_URL' "$EXTERNAL_CONSUMER_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_EXTERNAL_CONSUMER_REQUIRE_REMOTE' "$EXTERNAL_CONSUMER_UI_RUNNER" \
  || ! grep -Fq -- 'PocketRootExternalConsumerAppUITests' "$EXTERNAL_CONSUMER_UI_RUNNER" \
  || ! grep -Fq -- 'run-ios-example-ui-smoke.sh' "$EXTERNAL_CONSUMER_UI_RUNNER"; then
    echo "Example UI wrappers are missing deterministic target mappings." >&2
    exit 1
fi

if ! grep -Fq -- 'POCKETROOT_KEEP_UI_RESULT' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_UI_SKIP_TESTING' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_UI_FAILURE_ARTIFACTS_DIR' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_UI_INFRASTRUCTURE_RETRY_LIMIT' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'is_retryable_simulator_launch_failure' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- "is unknown to FrontBoard" "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'retrying once' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'xcodebuild-test-attempt-1.log' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- '-attempt-1.xcresult' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'xcodebuild-test.log' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'simulator.log' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_DEVELOPMENT_ROOTFS_ARCHIVE="$ARCHIVE_PATH"' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- '-test-timeouts-enabled YES' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- '-default-test-execution-time-allowance "$DEFAULT_TEST_ALLOWANCE"' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- '-maximum-test-execution-time-allowance "$MAXIMUM_TEST_ALLOWANCE"' "$GENERIC_UI_RUNNER" \
  || ! grep -Fq -- 'xcrun simctl delete "$DEVICE_UDID"' "$GENERIC_UI_RUNNER"; then
    echo "Shared example UI runner is missing bounded execution or cleanup." >&2
    exit 1
fi

GENERIC_RUNNER_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootGenericUIRunnerTests.XXXXXX")"
GENERIC_RUNNER_MOCK_BIN="$GENERIC_RUNNER_TEST_ROOT/bin"
GENERIC_RUNNER_APP="$GENERIC_RUNNER_TEST_ROOT/app"
GENERIC_RUNNER_ARCHIVE="$GENERIC_RUNNER_TEST_ROOT/rootfs.tar.gz"
GENERIC_RUNNER_XCODEBUILD_CALLS="$GENERIC_RUNNER_TEST_ROOT/xcodebuild-calls.txt"
GENERIC_RUNNER_XCRUN_CALLS="$GENERIC_RUNNER_TEST_ROOT/xcrun-calls.txt"
GENERIC_RUNNER_BOOTSTATUS_CALLS="$GENERIC_RUNNER_TEST_ROOT/bootstatus-calls.txt"
GENERIC_RUNNER_BOOT_CALLS="$GENERIC_RUNNER_TEST_ROOT/boot-calls.txt"
mkdir -p "$GENERIC_RUNNER_MOCK_BIN" "$GENERIC_RUNNER_APP"
: > "$GENERIC_RUNNER_ARCHIVE"
: > "$GENERIC_RUNNER_APP/project.yml"

cat > "$GENERIC_RUNNER_MOCK_BIN/uname" <<'MOCK'
#!/usr/bin/env bash
printf 'arm64\n'
MOCK
cat > "$GENERIC_RUNNER_MOCK_BIN/xcodegen" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$GENERIC_RUNNER_MOCK_BIN/xcrun" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$POCKETROOT_MOCK_XCRUN_CALLS"
if [[ "$*" == "simctl list runtimes available" ]]; then
    printf 'iOS 18.0 - com.apple.CoreSimulator.SimRuntime.iOS-18-0\n'
fi
if [[ "$*" == "simctl shutdown MOCK-UDID" &&
      "${POCKETROOT_MOCK_XCRUN_MODE:-success}" == "already-shutdown" ]]; then
    exit 44
fi
if [[ "$*" == "simctl boot MOCK-UDID" ]]; then
    calls=0
    if [[ -f "$POCKETROOT_MOCK_BOOT_CALLS" ]]; then
        calls="$(cat "$POCKETROOT_MOCK_BOOT_CALLS")"
    fi
    calls="$((calls + 1))"
    printf '%s\n' "$calls" > "$POCKETROOT_MOCK_BOOT_CALLS"
    if [[ "${POCKETROOT_MOCK_XCRUN_MODE:-success}" == "boot-failure" &&
          "$calls" -eq 2 ]]; then
        exit 43
    fi
fi
if [[ "$1" == "simctl" && "$2" == "create" ]]; then
    printf 'MOCK-UDID\n'
fi
if [[ "$*" == "simctl bootstatus MOCK-UDID -b" ]]; then
    calls=0
    if [[ -f "$POCKETROOT_MOCK_BOOTSTATUS_CALLS" ]]; then
        calls="$(cat "$POCKETROOT_MOCK_BOOTSTATUS_CALLS")"
    fi
    calls="$((calls + 1))"
    printf '%s\n' "$calls" > "$POCKETROOT_MOCK_BOOTSTATUS_CALLS"
    if [[ "${POCKETROOT_MOCK_XCRUN_MODE:-success}" == "restart-failure" &&
          "$calls" -eq 2 ]]; then
        exit 42
    fi
fi
exit 0
MOCK
cat > "$GENERIC_RUNNER_MOCK_BIN/xcodebuild" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
calls=0
if [[ -f "$POCKETROOT_MOCK_XCODEBUILD_CALLS" ]]; then
    calls="$(cat "$POCKETROOT_MOCK_XCODEBUILD_CALLS")"
fi
calls="$((calls + 1))"
printf '%s\n' "$calls" > "$POCKETROOT_MOCK_XCODEBUILD_CALLS"
result_bundle_path=""
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "-resultBundlePath" && "$#" -gt 1 ]]; then
        result_bundle_path="$2"
        break
    fi
    shift
done
if [[ -n "$result_bundle_path" ]]; then
    mkdir -p "$result_bundle_path"
fi
if [[ "${POCKETROOT_MOCK_XCODEBUILD_MODE:-retry}" == "retry" && "$calls" -eq 1 ]]; then
    echo "Simulator device failed to launch com.example.UITests.xctrunner."
    echo 'Application "com.example.UITests.xctrunner" is unknown to FrontBoard.'
    exit 65
fi
if [[ "${POCKETROOT_MOCK_XCODEBUILD_MODE:-retry}" == "assertion" ]]; then
    echo "Testing failed: expected value did not match"
    exit 65
fi
exit 0
MOCK
chmod +x "$GENERIC_RUNNER_MOCK_BIN"/*

GENERIC_RUNNER_OUTPUT="$GENERIC_RUNNER_TEST_ROOT/retry-output.txt"
PATH="$GENERIC_RUNNER_MOCK_BIN:$PATH" \
POCKETROOT_UI_APP_DIR="$GENERIC_RUNNER_APP" \
POCKETROOT_UI_PROJECT_NAME="MockApp" \
POCKETROOT_UI_SCHEME="MockApp" \
POCKETROOT_UI_TEST_BUNDLE="MockAppUITests" \
POCKETROOT_CLONED_SOURCE_PACKAGES_DIR="$GENERIC_RUNNER_TEST_ROOT/packages" \
POCKETROOT_MOCK_XCODEBUILD_CALLS="$GENERIC_RUNNER_XCODEBUILD_CALLS" \
POCKETROOT_MOCK_XCRUN_CALLS="$GENERIC_RUNNER_XCRUN_CALLS" \
POCKETROOT_MOCK_BOOTSTATUS_CALLS="$GENERIC_RUNNER_BOOTSTATUS_CALLS" \
POCKETROOT_MOCK_BOOT_CALLS="$GENERIC_RUNNER_BOOT_CALLS" \
  "$GENERIC_UI_RUNNER" "$GENERIC_RUNNER_ARCHIVE" \
  > "$GENERIC_RUNNER_OUTPUT" 2>&1

if [[ "$(cat "$GENERIC_RUNNER_XCODEBUILD_CALLS")" != "2" ]] \
  || ! grep -Fq -- 'retrying once' "$GENERIC_RUNNER_OUTPUT" \
  || ! grep -Fq -- 'simctl shutdown MOCK-UDID' "$GENERIC_RUNNER_XCRUN_CALLS"; then
    echo "Shared example UI runner did not bound and recover the FrontBoard launch retry." >&2
    exit 1
fi

printf '0\n' > "$GENERIC_RUNNER_XCODEBUILD_CALLS"
: > "$GENERIC_RUNNER_XCRUN_CALLS"
: > "$GENERIC_RUNNER_BOOT_CALLS"
if ! PATH="$GENERIC_RUNNER_MOCK_BIN:$PATH" \
  POCKETROOT_UI_APP_DIR="$GENERIC_RUNNER_APP" \
  POCKETROOT_UI_PROJECT_NAME="MockApp" \
  POCKETROOT_UI_SCHEME="MockApp" \
  POCKETROOT_UI_TEST_BUNDLE="MockAppUITests" \
  POCKETROOT_CLONED_SOURCE_PACKAGES_DIR="$GENERIC_RUNNER_TEST_ROOT/packages" \
  POCKETROOT_MOCK_XCODEBUILD_CALLS="$GENERIC_RUNNER_XCODEBUILD_CALLS" \
  POCKETROOT_MOCK_XCRUN_CALLS="$GENERIC_RUNNER_XCRUN_CALLS" \
  POCKETROOT_MOCK_BOOTSTATUS_CALLS="$GENERIC_RUNNER_BOOTSTATUS_CALLS" \
  POCKETROOT_MOCK_BOOT_CALLS="$GENERIC_RUNNER_BOOT_CALLS" \
  POCKETROOT_MOCK_XCRUN_MODE="already-shutdown" \
    "$GENERIC_UI_RUNNER" "$GENERIC_RUNNER_ARCHIVE" \
    > "$GENERIC_RUNNER_TEST_ROOT/already-shutdown-output.txt" 2>&1; then
    echo "Shared example UI runner did not recover an already-shutdown temporary Simulator." >&2
    exit 1
fi
if [[ "$(cat "$GENERIC_RUNNER_XCODEBUILD_CALLS")" != "2" ]] \
  || [[ "$(cat "$GENERIC_RUNNER_BOOT_CALLS")" != "2" ]]; then
    echo "Shared example UI runner treated an already-shutdown Simulator as a restart failure." >&2
    exit 1
fi

printf '0\n' > "$GENERIC_RUNNER_XCODEBUILD_CALLS"
: > "$GENERIC_RUNNER_XCRUN_CALLS"
if PATH="$GENERIC_RUNNER_MOCK_BIN:$PATH" \
  POCKETROOT_UI_APP_DIR="$GENERIC_RUNNER_APP" \
  POCKETROOT_UI_PROJECT_NAME="MockApp" \
  POCKETROOT_UI_SCHEME="MockApp" \
  POCKETROOT_UI_TEST_BUNDLE="MockAppUITests" \
  POCKETROOT_UI_SMOKE_DEVICE="MOCK-UDID" \
  POCKETROOT_CLONED_SOURCE_PACKAGES_DIR="$GENERIC_RUNNER_TEST_ROOT/packages" \
  POCKETROOT_MOCK_XCODEBUILD_CALLS="$GENERIC_RUNNER_XCODEBUILD_CALLS" \
  POCKETROOT_MOCK_XCRUN_CALLS="$GENERIC_RUNNER_XCRUN_CALLS" \
  POCKETROOT_MOCK_BOOTSTATUS_CALLS="$GENERIC_RUNNER_BOOTSTATUS_CALLS" \
  POCKETROOT_MOCK_BOOT_CALLS="$GENERIC_RUNNER_BOOT_CALLS" \
    "$GENERIC_UI_RUNNER" "$GENERIC_RUNNER_ARCHIVE" \
    > "$GENERIC_RUNNER_TEST_ROOT/caller-device-output.txt" 2>&1; then
    echo "Shared example UI runner accepted a FrontBoard failure on a caller-owned Simulator." >&2
    exit 1
fi
if [[ "$(cat "$GENERIC_RUNNER_XCODEBUILD_CALLS")" != "1" ]] \
  || grep -Fq -- 'simctl shutdown MOCK-UDID' "$GENERIC_RUNNER_XCRUN_CALLS"; then
    echo "Shared example UI runner restarted a caller-owned Simulator." >&2
    exit 1
fi

printf '0\n' > "$GENERIC_RUNNER_XCODEBUILD_CALLS"
: > "$GENERIC_RUNNER_XCRUN_CALLS"
if PATH="$GENERIC_RUNNER_MOCK_BIN:$PATH" \
  POCKETROOT_UI_APP_DIR="$GENERIC_RUNNER_APP" \
  POCKETROOT_UI_PROJECT_NAME="MockApp" \
  POCKETROOT_UI_SCHEME="MockApp" \
  POCKETROOT_UI_TEST_BUNDLE="MockAppUITests" \
  POCKETROOT_CLONED_SOURCE_PACKAGES_DIR="$GENERIC_RUNNER_TEST_ROOT/packages" \
  POCKETROOT_MOCK_XCODEBUILD_CALLS="$GENERIC_RUNNER_XCODEBUILD_CALLS" \
  POCKETROOT_MOCK_XCRUN_CALLS="$GENERIC_RUNNER_XCRUN_CALLS" \
  POCKETROOT_MOCK_BOOTSTATUS_CALLS="$GENERIC_RUNNER_BOOTSTATUS_CALLS" \
  POCKETROOT_MOCK_BOOT_CALLS="$GENERIC_RUNNER_BOOT_CALLS" \
  POCKETROOT_MOCK_XCODEBUILD_MODE="assertion" \
    "$GENERIC_UI_RUNNER" "$GENERIC_RUNNER_ARCHIVE" \
    > "$GENERIC_RUNNER_TEST_ROOT/assertion-output.txt" 2>&1; then
    echo "Shared example UI runner retried or accepted a test assertion failure." >&2
    exit 1
fi
if [[ "$(cat "$GENERIC_RUNNER_XCODEBUILD_CALLS")" != "1" ]]; then
    echo "Shared example UI runner retried a non-infrastructure failure." >&2
    exit 1
fi

printf '0\n' > "$GENERIC_RUNNER_XCODEBUILD_CALLS"
: > "$GENERIC_RUNNER_XCRUN_CALLS"
: > "$GENERIC_RUNNER_BOOTSTATUS_CALLS"
GENERIC_RUNNER_FAILURE_ARTIFACTS="$GENERIC_RUNNER_TEST_ROOT/failure-artifacts"
if PATH="$GENERIC_RUNNER_MOCK_BIN:$PATH" \
  POCKETROOT_UI_APP_DIR="$GENERIC_RUNNER_APP" \
  POCKETROOT_UI_PROJECT_NAME="MockApp" \
  POCKETROOT_UI_SCHEME="MockApp" \
  POCKETROOT_UI_TEST_BUNDLE="MockAppUITests" \
  POCKETROOT_UI_FAILURE_ARTIFACTS_DIR="$GENERIC_RUNNER_FAILURE_ARTIFACTS" \
  POCKETROOT_CLONED_SOURCE_PACKAGES_DIR="$GENERIC_RUNNER_TEST_ROOT/packages" \
  POCKETROOT_MOCK_XCODEBUILD_CALLS="$GENERIC_RUNNER_XCODEBUILD_CALLS" \
  POCKETROOT_MOCK_XCRUN_CALLS="$GENERIC_RUNNER_XCRUN_CALLS" \
  POCKETROOT_MOCK_BOOTSTATUS_CALLS="$GENERIC_RUNNER_BOOTSTATUS_CALLS" \
  POCKETROOT_MOCK_BOOT_CALLS="$GENERIC_RUNNER_BOOT_CALLS" \
  POCKETROOT_MOCK_XCRUN_MODE="restart-failure" \
    "$GENERIC_UI_RUNNER" "$GENERIC_RUNNER_ARCHIVE" \
    > "$GENERIC_RUNNER_TEST_ROOT/restart-failure-output.txt" 2>&1; then
    echo "Shared example UI runner accepted a failed retry restart." >&2
    exit 1
fi
if [[ "$(cat "$GENERIC_RUNNER_XCODEBUILD_CALLS")" != "1" ]] \
  || [[ ! -f "$GENERIC_RUNNER_FAILURE_ARTIFACTS/xcodebuild-test-attempt-1.log" ]] \
  || [[ ! -d "$GENERIC_RUNNER_FAILURE_ARTIFACTS/MockAppUITests-attempt-1.xcresult" ]] \
  || ! grep -Fq -- 'Simulator restart failed during bootstatus with exit code 42' \
    "$GENERIC_RUNNER_FAILURE_ARTIFACTS/xcodebuild-test.log"; then
    echo "Shared example UI runner did not preserve diagnostics after a failed retry restart." >&2
    exit 1
fi

printf '0\n' > "$GENERIC_RUNNER_XCODEBUILD_CALLS"
: > "$GENERIC_RUNNER_XCRUN_CALLS"
: > "$GENERIC_RUNNER_BOOTSTATUS_CALLS"
: > "$GENERIC_RUNNER_BOOT_CALLS"
GENERIC_RUNNER_BOOT_FAILURE_ARTIFACTS="$GENERIC_RUNNER_TEST_ROOT/boot-failure-artifacts"
if PATH="$GENERIC_RUNNER_MOCK_BIN:$PATH" \
  POCKETROOT_UI_APP_DIR="$GENERIC_RUNNER_APP" \
  POCKETROOT_UI_PROJECT_NAME="MockApp" \
  POCKETROOT_UI_SCHEME="MockApp" \
  POCKETROOT_UI_TEST_BUNDLE="MockAppUITests" \
  POCKETROOT_UI_FAILURE_ARTIFACTS_DIR="$GENERIC_RUNNER_BOOT_FAILURE_ARTIFACTS" \
  POCKETROOT_CLONED_SOURCE_PACKAGES_DIR="$GENERIC_RUNNER_TEST_ROOT/packages" \
  POCKETROOT_MOCK_XCODEBUILD_CALLS="$GENERIC_RUNNER_XCODEBUILD_CALLS" \
  POCKETROOT_MOCK_XCRUN_CALLS="$GENERIC_RUNNER_XCRUN_CALLS" \
  POCKETROOT_MOCK_BOOTSTATUS_CALLS="$GENERIC_RUNNER_BOOTSTATUS_CALLS" \
  POCKETROOT_MOCK_BOOT_CALLS="$GENERIC_RUNNER_BOOT_CALLS" \
  POCKETROOT_MOCK_XCRUN_MODE="boot-failure" \
    "$GENERIC_UI_RUNNER" "$GENERIC_RUNNER_ARCHIVE" \
    > "$GENERIC_RUNNER_TEST_ROOT/boot-failure-output.txt" 2>&1; then
    echo "Shared example UI runner accepted a failed retry boot." >&2
    exit 1
fi
if [[ "$(cat "$GENERIC_RUNNER_XCODEBUILD_CALLS")" != "1" ]] \
  || ! grep -Fq -- 'Simulator restart failed during boot with exit code 43' \
    "$GENERIC_RUNNER_BOOT_FAILURE_ARTIFACTS/xcodebuild-test.log" \
  || ! grep -Fq -- 'retry_restart_failure_stage=boot' \
    "$GENERIC_RUNNER_BOOT_FAILURE_ARTIFACTS/phase.txt" \
  || [[ ! -d "$GENERIC_RUNNER_BOOT_FAILURE_ARTIFACTS/MockAppUITests-attempt-1.xcresult" ]]; then
    echo "Shared example UI runner ignored a failed retry boot." >&2
    exit 1
fi
rm -rf "$GENERIC_RUNNER_TEST_ROOT"

WRAPPER_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootHostUIWrapperTests.XXXXXX")"
trap 'rm -rf "$WRAPPER_TEST_ROOT"' EXIT
WRAPPER_CALLS="$WRAPPER_TEST_ROOT/calls.txt"
WRAPPER_MOCK="$WRAPPER_TEST_ROOT/mock-generic-runner.sh"
cat > "$WRAPPER_MOCK" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s|%s|%s\n' \
  "$POCKETROOT_UI_PHASE_LABEL" \
  "$POCKETROOT_UI_ONLY_TESTING" \
  "${POCKETROOT_UI_SKIP_TESTING:-}" \
  "${POCKETROOT_UI_FAILURE_ARTIFACTS_DIR:-}" \
  >> "$POCKETROOT_WRAPPER_CALLS"
MOCK
chmod +x "$WRAPPER_MOCK"

POCKETROOT_UI_GENERIC_RUNNER="$WRAPPER_MOCK" \
POCKETROOT_WRAPPER_CALLS="$WRAPPER_CALLS" \
POCKETROOT_HOST_UI_FAILURE_ARTIFACTS_DIR="$WRAPPER_TEST_ROOT/artifacts" \
  "$HOST_UI_RUNNER" "$WRAPPER_TEST_ROOT/rootfs.tar.gz"

EXPECTED_SPLIT_CALLS="$(cat <<EOF
files-workspace|PocketRootHostAppUITests/PocketRootHostAppUITests|PocketRootHostAppUITests/PocketRootHostAppUITests/testPTYLifecycleAndShutdown|$WRAPPER_TEST_ROOT/artifacts/files-workspace
pty-lifecycle|PocketRootHostAppUITests/PocketRootHostAppUITests/testPTYLifecycleAndShutdown||$WRAPPER_TEST_ROOT/artifacts/pty-lifecycle
EOF
)"
if [[ "$(cat "$WRAPPER_CALLS")" != "$EXPECTED_SPLIT_CALLS" ]]; then
    echo "Host App UI wrapper did not isolate the PTY lifecycle phase." >&2
    exit 1
fi

: > "$WRAPPER_CALLS"
POCKETROOT_UI_GENERIC_RUNNER="$WRAPPER_MOCK" \
POCKETROOT_WRAPPER_CALLS="$WRAPPER_CALLS" \
POCKETROOT_HOST_UI_ONLY_TESTING="PocketRootHostAppUITests/PocketRootHostAppUITests/testFilesCreateAndDelete" \
  "$HOST_UI_RUNNER" "$WRAPPER_TEST_ROOT/rootfs.tar.gz"
if [[ "$(wc -l < "$WRAPPER_CALLS" | tr -d ' ')" != "1" ]] \
  || [[ "$(cat "$WRAPPER_CALLS")" != \
    requested-test\|PocketRootHostAppUITests/PocketRootHostAppUITests/testFilesCreateAndDelete\|\| ]]; then
    echo "Host App UI wrapper did not preserve an explicitly requested test." >&2
    exit 1
fi

if ! grep -Fq -- 'pocketroot-system-file-ui-fixture.txt' "$HOST_APP_SOURCE" \
  || ! grep -Fq -- 'testSystemFileImportAndShareExportRoundTrip' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'Save to Files' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'revealFileEntry' "$HOST_UI_TESTS" \
  || ! grep -Fq -- '"PocketRootFiles.list"' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'if element.isEnabled' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'hasUsableFrame(appFrame)' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'hasUsableFrame(actionsFrame)' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'tapFrame(actionsFrame, in: appFrame, using: app)' "$HOST_UI_TESTS" \
  || grep -Fq -- 'waitForHittable(actions)' "$HOST_UI_TESTS" \
  || grep -Fq -- 'hostActions.isHittable' "$HOST_UI_TESTS" \
  || grep -Fq -- 'hostIsHittable' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'waitForInteractionFrames(' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'underlying host geometry' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'for attempt in 0..<2' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'relaunchAndBoot(app)' "$HOST_UI_TESTS" \
  || grep -Fq -- 'browse.tap()' "$HOST_UI_TESTS" \
  || grep -Fq -- 'waitForHittable(imported)' "$HOST_UI_TESTS" \
  || ! grep -Fq -- '.matching(identifier: "ActivityListView")' "$HOST_UI_TESTS" \
  || grep -Fq -- 'app.otherElements["ActivityListView"]' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'try? activityView.snapshot()' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'tapOutsideSnapshotFrame(' "$HOST_UI_TESTS" \
  || grep -Fq -- 'tapOutsideCurrentFrame' "$HOST_UI_TESTS" \
  || ! grep -Fq -- 'LSSupportsOpeningDocumentsInPlace: true' "$HOST_PROJECT_SPEC" \
  || ! grep -Fq -- 'UIFileSharingEnabled: true' "$HOST_PROJECT_SPEC"; then
    echo "Host App UI smoke is missing the system file transfer closure." >&2
    exit 1
fi

if ! grep -Fq -- 'makeTerminalViewController()' "$QUICK_START_SOURCE" \
  || ! grep -Fq -- 'makeFilesViewController()' "$QUICK_START_SOURCE" \
  || ! grep -Fq -- 'func sceneDidDisconnect(_ scene: UIScene)' "$QUICK_START_SOURCE" \
  || ! grep -Fq -- 'pocketRootHost?.closeWorkspaces()' "$QUICK_START_SOURCE" \
  || ! grep -Fq -- 'testFilesEntryAutoBootsFromColdLaunch' "$QUICK_START_UI_TESTS" \
  || ! grep -Fq -- 'testTerminalCreatesFileThatFilesCanPreview' "$QUICK_START_UI_TESTS" \
  || ! grep -Fq -- 'PocketRootTerminal.pty' "$QUICK_START_UI_TESTS" \
  || ! grep -Fq -- 'PocketRootFiles.preview' "$QUICK_START_UI_TESTS" \
  || ! grep -Fq -- 'PocketRootQuickStartAppUITests:' "$QUICK_START_PROJECT_SPEC" \
  || ! grep -Fq -- 'path: ../..' "$QUICK_START_PROJECT_SPEC" \
  || ! grep -Fq -- 'product: PocketRootIshRuntimeIntegration' "$QUICK_START_PROJECT_SPEC" \
  || ! grep -Fq -- '"$SRCROOT/../../Scripts/inject-demo-rootfs.sh"' "$QUICK_START_PROJECT_SPEC"; then
    echo "Quick Start App is missing its two-entry UI closure or package boundary." >&2
    exit 1
fi

if ! grep -Fq -- '__POCKETROOT_PACKAGE_SOURCE__' "$EXTERNAL_CONSUMER_PROJECT_TEMPLATE" \
  || ! grep -Fq -- 'product: PocketRoot' "$EXTERNAL_CONSUMER_PROJECT_TEMPLATE" \
  || ! grep -Fq -- 'product: PocketRootIshRuntimeIntegration' "$EXTERNAL_CONSUMER_PROJECT_TEMPLATE" \
  || ! grep -Fq -- 'host.makeTerminalViewController()' "$EXTERNAL_CONSUMER_SOURCE" \
  || ! grep -Fq -- 'host.makeFilesViewController()' "$EXTERNAL_CONSUMER_SOURCE" \
  || ! grep -Fq -- 'try await host.shutdown()' "$EXTERNAL_CONSUMER_SOURCE" \
  || ! grep -Fq -- 'func sceneDidDisconnect(_ scene: UIScene)' "$EXTERNAL_CONSUMER_SOURCE" \
  || ! grep -Fq -- 'pocketRootHost?.closeWorkspaces()' "$EXTERNAL_CONSUMER_SOURCE" \
  || ! grep -Fq -- 'testRemoteConsumerTerminalFilesAndLifecycleClosure' "$EXTERNAL_CONSUMER_UI_TESTS" \
  || ! grep -Fq -- 'XCUIDevice.shared.press(.home)' "$EXTERNAL_CONSUMER_UI_TESTS" \
  || ! grep -Fq -- 'app.wait(for: .runningBackground' "$EXTERNAL_CONSUMER_UI_TESTS" \
  || ! grep -Fq -- 'app.wait(for: .runningForeground' "$EXTERNAL_CONSUMER_UI_TESTS" \
  || ! grep -Fq -- '__POCKETROOT_EXTERNAL_CONSUMER_FOREGROUND__' "$EXTERNAL_CONSUMER_UI_TESTS" \
  || ! grep -Fq -- 'Runtime Terminated' "$EXTERNAL_CONSUMER_UI_TESTS"; then
    echo "External Consumer acceptance fixture is missing its public API or lifecycle closure." >&2
    exit 1
fi

if ! grep -Fq -- 'POCKETROOT_HOST_DEVICE_UI_SMOKE_DEVICE' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'result.hardwareProperties.udid' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- '"$DEVICE_REALITY" != "physical"' "$HOST_DEVICE_UI_RUNNER" \
  || grep -Fq -- 'xcrun --sdk iphoneos --show-sdk-version' "$HOST_DEVICE_UI_RUNNER" \
  || grep -Fq -- 'newer than the installed iOS' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- 'The SDK version is not Xcode' "$HOST_DEVICE_UI_RUNNER" \
  || ! grep -Fq -- '-destination "id=$DEVICE_ID"' "$HOST_DEVICE_UI_RUNNER" \
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

if ! grep -Fq -- 'POCKETROOT_SMOKE_STABILITY must be 0 or 1.' "$SIMULATOR_RUNNER" \
  || ! grep -Fq -- 'SIMCTL_CHILD_POCKETROOT_SMOKE_STABILITY=' "$SIMULATOR_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_SMOKE_STABILITY must be 0 or 1.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'Stability smoke cannot be combined with another optional mode.' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'STABILITY_LAUNCH_ENVIRONMENT=' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'POCKETROOT_SMOKE_LONG_WORKLOAD:-0' "$DEVICE_RUNNER" \
  || ! grep -Fq -- 'defaultStabilityIterationCount = 90' "$SMOKE_APP" \
  || ! grep -Fq -- 'running-stability-workload-check' "$SMOKE_APP" \
  || ! grep -Fq -- 'name: "stability-workload"' "$SMOKE_APP" \
  || ! grep -Fq -- 'system.makeSession(' "$SMOKE_APP" \
  || ! grep -Fq -- 'POCKETROOT_STABILITY_RECOVERED' "$SMOKE_APP" \
  || ! grep -Fq -- 'PocketRootFileBrowser(executor: system)' "$SMOKE_APP"; then
    echo "Native smoke does not gate the configurable persistent-PTY stability workload." >&2
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
  || ! grep -Fq -- 'peakResidentBytes <= maximumPeakResidentBytes' "$SMOKE_APP" \
  || ! grep -Fq -- 'task_flavor_t(TASK_VM_INFO)' "$SMOKE_APP" \
  || ! grep -Fq -- 'maximumStabilityFootprintGrowthBytes' "$SMOKE_APP" \
  || ! grep -Fq -- 'footprintGrowthBytes <= maximumStabilityFootprintGrowthBytes' "$SMOKE_APP"; then
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
