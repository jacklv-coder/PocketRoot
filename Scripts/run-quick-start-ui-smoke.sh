#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

export POCKETROOT_UI_APP_DIR="$ROOT_DIR/Examples/PocketRootQuickStartApp"
export POCKETROOT_UI_PROJECT_NAME="PocketRootQuickStartApp"
export POCKETROOT_UI_SCHEME="PocketRootQuickStartApp"
export POCKETROOT_UI_TEST_BUNDLE="PocketRootQuickStartAppUITests"
export POCKETROOT_UI_ARTIFACT_LABEL="PocketRoot Quick Start"
export POCKETROOT_UI_SMOKE_DEVICE="${POCKETROOT_QUICK_START_UI_SMOKE_DEVICE:-}"
export POCKETROOT_UI_DEVICE_TYPE="${POCKETROOT_QUICK_START_UI_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16}"
export POCKETROOT_UI_DEVICE_NAME="${POCKETROOT_QUICK_START_UI_DEVICE_NAME:-PocketRoot-Quick-Start-UI-Smoke-$$}"
export POCKETROOT_UI_ONLY_TESTING="${POCKETROOT_QUICK_START_UI_ONLY_TESTING:-PocketRootQuickStartAppUITests/PocketRootQuickStartAppUITests}"

exec "$ROOT_DIR/Scripts/run-ios-example-ui-smoke.sh" "$@"
