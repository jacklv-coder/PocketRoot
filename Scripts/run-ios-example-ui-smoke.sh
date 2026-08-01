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
SKIP_TESTING="${POCKETROOT_UI_SKIP_TESTING:-}"
DEFAULT_TEST_ALLOWANCE="${POCKETROOT_UI_DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-300}"
MAXIMUM_TEST_ALLOWANCE="${POCKETROOT_UI_MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE:-600}"
PHASE_LABEL="${POCKETROOT_UI_PHASE_LABEL:-full-suite}"
FAILURE_ARTIFACTS_DIR="${POCKETROOT_UI_FAILURE_ARTIFACTS_DIR:-}"
INFRASTRUCTURE_RETRY_LIMIT="${POCKETROOT_UI_INFRASTRUCTURE_RETRY_LIMIT:-1}"
TEST_LOG_PATH="$DERIVED_DATA_ROOT/xcodebuild-test.log"
FIRST_ATTEMPT_LOG_PATH="$DERIVED_DATA_ROOT/xcodebuild-test-attempt-1.log"
FIRST_ATTEMPT_RESULT_BUNDLE_PATH="$DERIVED_DATA_ROOT/$TEST_BUNDLE-attempt-1.xcresult"
RETRY_SHUTDOWN_EXIT_CODE="<not-attempted>"
RETRY_RESTART_EXIT_CODE="<not-attempted>"
RETRY_RESTART_FAILURE_STAGE="<not-attempted>"

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
if [[ ! "$INFRASTRUCTURE_RETRY_LIMIT" =~ ^[01]$ ]]; then
    echo "Example UI infrastructure retry limit must be 0 or 1." >&2
    exit 2
fi

TEST_SELECTION_ARGUMENTS=("-only-testing:$ONLY_TESTING")
if [[ -n "$SKIP_TESTING" ]]; then
    TEST_SELECTION_ARGUMENTS+=("-skip-testing:$SKIP_TESTING")
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

run_ui_tests() {
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
      "${TEST_SELECTION_ARGUMENTS[@]}" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      test 2>&1 | tee "$TEST_LOG_PATH"
    return "${PIPESTATUS[0]}"
}

is_retryable_simulator_launch_failure() {
    grep -Fq 'Simulator device failed to launch' "$TEST_LOG_PATH" &&
      grep -Fq 'is unknown to FrontBoard' "$TEST_LOG_PATH"
}

set +e
run_ui_tests
test_exit_code="$?"
set -e

if [[ "$test_exit_code" -ne 0 &&
      "$INFRASTRUCTURE_RETRY_LIMIT" -eq 1 &&
      "$CREATED_DEVICE" == "true" ]] &&
   is_retryable_simulator_launch_failure; then
    mv "$TEST_LOG_PATH" "$FIRST_ATTEMPT_LOG_PATH"
    if [[ -d "$RESULT_BUNDLE_PATH" ]]; then
        mv "$RESULT_BUNDLE_PATH" "$FIRST_ATTEMPT_RESULT_BUNDLE_PATH"
    fi
    echo "$ARTIFACT_LABEL UI test runner was not registered with FrontBoard; restarting the Simulator and retrying once." >&2
    set +e
    xcrun simctl shutdown "$DEVICE_UDID" >/dev/null 2>&1
    RETRY_SHUTDOWN_EXIT_CODE="$?"
    xcrun simctl boot "$DEVICE_UDID" >/dev/null 2>&1
    RETRY_RESTART_EXIT_CODE="$?"
    if [[ "$RETRY_RESTART_EXIT_CODE" -ne 0 ]]; then
        RETRY_RESTART_FAILURE_STAGE="boot"
    else
        xcrun simctl bootstatus "$DEVICE_UDID" -b
        RETRY_RESTART_EXIT_CODE="$?"
        if [[ "$RETRY_RESTART_EXIT_CODE" -ne 0 ]]; then
            RETRY_RESTART_FAILURE_STAGE="bootstatus"
        fi
    fi
    set -e
    if [[ "$RETRY_RESTART_EXIT_CODE" -eq 0 ]]; then
        RETRY_RESTART_FAILURE_STAGE="<none>"
        set +e
        run_ui_tests
        test_exit_code="$?"
        set -e
    else
        test_exit_code="$RETRY_RESTART_EXIT_CODE"
        echo "$ARTIFACT_LABEL Simulator restart failed during $RETRY_RESTART_FAILURE_STAGE with exit code $RETRY_RESTART_EXIT_CODE; the UI test was not retried." \
          | tee "$TEST_LOG_PATH" >&2
    fi
fi

if [[ "$test_exit_code" -ne 0 ]]; then
    if [[ -n "$FAILURE_ARTIFACTS_DIR" ]]; then
        mkdir -p "$FAILURE_ARTIFACTS_DIR"
        cp "$TEST_LOG_PATH" "$FAILURE_ARTIFACTS_DIR/xcodebuild-test.log"
        if [[ -f "$FIRST_ATTEMPT_LOG_PATH" ]]; then
            cp "$FIRST_ATTEMPT_LOG_PATH" \
              "$FAILURE_ARTIFACTS_DIR/xcodebuild-test-attempt-1.log"
        fi
        if [[ -d "$RESULT_BUNDLE_PATH" ]]; then
            cp -R "$RESULT_BUNDLE_PATH" \
              "$FAILURE_ARTIFACTS_DIR/$TEST_BUNDLE.xcresult"
        fi
        if [[ -d "$FIRST_ATTEMPT_RESULT_BUNDLE_PATH" ]]; then
            cp -R "$FIRST_ATTEMPT_RESULT_BUNDLE_PATH" \
              "$FAILURE_ARTIFACTS_DIR/$TEST_BUNDLE-attempt-1.xcresult"
        fi
        {
            echo "artifact=$ARTIFACT_LABEL"
            echo "phase=$PHASE_LABEL"
            echo "device=$DEVICE_UDID"
            echo "device_type=$SIMULATOR_DEVICE_TYPE"
            echo "only_testing=$ONLY_TESTING"
            echo "skip_testing=${SKIP_TESTING:-<none>}"
            echo "default_allowance=$DEFAULT_TEST_ALLOWANCE"
            echo "maximum_allowance=$MAXIMUM_TEST_ALLOWANCE"
            echo "infrastructure_retry_limit=$INFRASTRUCTURE_RETRY_LIMIT"
            echo "retry_shutdown_exit_code=$RETRY_SHUTDOWN_EXIT_CODE"
            echo "retry_restart_exit_code=$RETRY_RESTART_EXIT_CODE"
            echo "retry_restart_failure_stage=$RETRY_RESTART_FAILURE_STAGE"
        } > "$FAILURE_ARTIFACTS_DIR/phase.txt"
        xcrun simctl spawn "$DEVICE_UDID" log show \
          --last 30m \
          --style compact \
          --predicate 'process CONTAINS[c] "PocketRoot"' \
          > "$FAILURE_ARTIFACTS_DIR/simulator.log" 2>&1 || true
        echo "$ARTIFACT_LABEL failure artifacts collected at $FAILURE_ARTIFACTS_DIR" >&2
    fi
    echo "$ARTIFACT_LABEL UI smoke failed; xcresult summary follows." >&2
    xcrun xcresulttool get test-results summary \
      --path "$RESULT_BUNDLE_PATH" || true
    exit "$test_exit_code"
fi

echo "$ARTIFACT_LABEL UI smoke passed."
