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
export POCKETROOT_UI_ONLY_TESTING="${POCKETROOT_HOST_UI_ONLY_TESTING:-PocketRootHostAppUITests/PocketRootHostAppUITests}"

exec "$ROOT_DIR/Scripts/run-ios-example-ui-smoke.sh" "$@"
