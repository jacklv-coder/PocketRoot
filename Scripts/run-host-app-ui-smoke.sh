#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

export POCKETROOT_UI_APP_DIR="$ROOT_DIR/Examples/PocketRootHostApp"
export POCKETROOT_UI_PROJECT_NAME="PocketRootHostApp"
export POCKETROOT_UI_SCHEME="PocketRootHostApp"
export POCKETROOT_UI_TEST_BUNDLE="PocketRootHostAppUITests"
export POCKETROOT_UI_ARTIFACT_LABEL="PocketRoot Host App"
export POCKETROOT_UI_SMOKE_DEVICE="${POCKETROOT_HOST_UI_SMOKE_DEVICE:-}"
export POCKETROOT_UI_DEVICE_TYPE="${POCKETROOT_HOST_UI_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16}"
export POCKETROOT_UI_DEVICE_NAME="${POCKETROOT_HOST_UI_DEVICE_NAME:-PocketRoot-Host-UI-Smoke-$$}"
export POCKETROOT_UI_DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE="${POCKETROOT_HOST_UI_DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-600}"
export POCKETROOT_UI_MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE="${POCKETROOT_HOST_UI_MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE:-600}"

GENERIC_RUNNER="${POCKETROOT_UI_GENERIC_RUNNER:-$ROOT_DIR/Scripts/run-ios-example-ui-smoke.sh}"
TEST_CLASS="PocketRootHostAppUITests/PocketRootHostAppUITests"
LIFECYCLE_TEST="$TEST_CLASS/testPTYLifecycleAndShutdown"
REQUESTED_TEST="${POCKETROOT_HOST_UI_ONLY_TESTING:-}"
FAILURE_ARTIFACTS_ROOT="${POCKETROOT_HOST_UI_FAILURE_ARTIFACTS_DIR:-}"

run_phase() {
    local phase="$1"
    local only_testing="$2"
    local skip_testing="$3"
    shift 3

    echo "PocketRoot Host App UI phase: $phase"
    (
        export POCKETROOT_UI_PHASE_LABEL="$phase"
        export POCKETROOT_UI_ONLY_TESTING="$only_testing"
        export POCKETROOT_UI_SKIP_TESTING="$skip_testing"
        if [[ -n "$FAILURE_ARTIFACTS_ROOT" ]]; then
            export POCKETROOT_UI_FAILURE_ARTIFACTS_DIR="$FAILURE_ARTIFACTS_ROOT/$phase"
        fi
        "$GENERIC_RUNNER" "$@"
    )
}

if [[ -n "$REQUESTED_TEST" ]]; then
    run_phase \
      "requested-test" \
      "$REQUESTED_TEST" \
      "${POCKETROOT_HOST_UI_SKIP_TESTING:-}" \
      "$@"
else
    run_phase "files-workspace" "$TEST_CLASS" "$LIFECYCLE_TEST" "$@"
    run_phase "pty-lifecycle" "$LIFECYCLE_TEST" "" "$@"
fi
