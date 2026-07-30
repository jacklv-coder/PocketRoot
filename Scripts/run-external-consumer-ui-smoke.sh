#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
FIXTURE_DIR="$ROOT_DIR/Tests/Integration/ExternalConsumerApp"
ARCHIVE_PATH="${1:-${POCKETROOT_ROOTFS_ARCHIVE:-}}"
PACKAGE_PATH="${POCKETROOT_EXTERNAL_CONSUMER_PACKAGE_PATH:-}"
REPOSITORY_URL="${POCKETROOT_EXTERNAL_CONSUMER_REPOSITORY_URL:-https://github.com/jacklv-coder/PocketRoot.git}"
REVISION="${POCKETROOT_EXTERNAL_CONSUMER_REVISION:-}"
REQUIRE_REMOTE="${POCKETROOT_EXTERNAL_CONSUMER_REQUIRE_REMOTE:-0}"
RUN_ROOT="$(
    mktemp -d "${TMPDIR:-/tmp}/PocketRootExternalConsumer.XXXXXX"
)"
APP_DIR="$RUN_ROOT/PocketRootExternalConsumerApp"
RESOURCE_NAME="pocketroot-fs-v0.3.3.tar.gz"

cleanup() {
    if [[ "${POCKETROOT_KEEP_EXTERNAL_CONSUMER_APP:-0}" == "1" ]]; then
        echo "PocketRoot External Consumer retained at $RUN_ROOT"
    else
        rm -rf "$RUN_ROOT"
    fi
}
trap cleanup EXIT

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ||
      -L "$ARCHIVE_PATH" ]]; then
    echo "Usage: POCKETROOT_ROOTFS_ARCHIVE=/path/to/fs.tar.gz $0" >&2
    exit 2
fi
if [[ ! -d "$FIXTURE_DIR/Sources" ||
      ! -d "$FIXTURE_DIR/UITests" ||
      ! -f "$FIXTURE_DIR/project.yml.template" ]]; then
    echo "External Consumer fixture inputs are incomplete." >&2
    exit 2
fi
if [[ -n "$PACKAGE_PATH" && -n "$REVISION" ]]; then
    echo "Choose either a local PocketRoot package path or a remote revision." >&2
    exit 2
fi
if [[ "$REQUIRE_REMOTE" != "0" && "$REQUIRE_REMOTE" != "1" ]]; then
    echo "POCKETROOT_EXTERNAL_CONSUMER_REQUIRE_REMOTE must be 0 or 1." >&2
    exit 2
fi
if [[ "$REQUIRE_REMOTE" == "1" && -z "$REVISION" ]]; then
    echo "External Consumer remote mode requires a full Git revision." >&2
    exit 2
fi

if [[ -z "$REVISION" ]]; then
    PACKAGE_PATH="${PACKAGE_PATH:-$ROOT_DIR}"
    if [[ ! -f "$PACKAGE_PATH/Package.swift" ]]; then
        echo "PocketRoot package path is invalid: $PACKAGE_PATH" >&2
        exit 2
    fi
    PACKAGE_PATH="$(cd "$PACKAGE_PATH" && pwd -P)"
    PACKAGE_SOURCE="$(
      PACKAGE_PATH="$PACKAGE_PATH" ruby -r json -e '
        puts "    path: #{JSON.generate(ENV.fetch("PACKAGE_PATH"))}"
      '
    )"
    echo "PocketRoot External Consumer dependency: local $PACKAGE_PATH"
else
    if [[ ! "$REVISION" =~ ^[0-9a-f]{40}$ ]]; then
        echo "POCKETROOT_EXTERNAL_CONSUMER_REVISION must be a full lowercase Git SHA." >&2
        exit 2
    fi
    if [[ ! "$REPOSITORY_URL" =~ ^https://[^[:space:]]+\.git$ ]]; then
        echo "POCKETROOT_EXTERNAL_CONSUMER_REPOSITORY_URL must be a public HTTPS Git URL." >&2
        exit 2
    fi
    PACKAGE_SOURCE="$(
      REPOSITORY_URL="$REPOSITORY_URL" \
      REVISION="$REVISION" \
      ruby -r json -e '
        puts "    url: #{JSON.generate(ENV.fetch("REPOSITORY_URL"))}"
        puts "    revision: #{JSON.generate(ENV.fetch("REVISION"))}"
      '
    )"
    echo "PocketRoot External Consumer dependency: $REPOSITORY_URL @ $REVISION"
fi

mkdir -p "$APP_DIR/Sources" "$APP_DIR/UITests" "$APP_DIR/Resources"
cp "$FIXTURE_DIR/Sources/ExternalConsumerApp.swift" "$APP_DIR/Sources/"
cp "$FIXTURE_DIR/UITests/ExternalConsumerAppUITests.swift" "$APP_DIR/UITests/"
install -m 0444 "$ARCHIVE_PATH" "$APP_DIR/Resources/$RESOURCE_NAME"

TEMPLATE_PATH="$FIXTURE_DIR/project.yml.template" \
OUTPUT_PATH="$APP_DIR/project.yml" \
PACKAGE_SOURCE="$PACKAGE_SOURCE" \
ruby -e '
  template = File.binread(ENV.fetch("TEMPLATE_PATH"))
  marker = "__POCKETROOT_PACKAGE_SOURCE__"
  abort "Project template package marker is missing." unless
    template.scan(marker).length == 1
  rendered = template.sub(marker, ENV.fetch("PACKAGE_SOURCE"))
  File.binwrite(ENV.fetch("OUTPUT_PATH"), rendered)
'

export POCKETROOT_UI_APP_DIR="$APP_DIR"
export POCKETROOT_UI_PROJECT_NAME="PocketRootExternalConsumerApp"
export POCKETROOT_UI_SCHEME="PocketRootExternalConsumerApp"
export POCKETROOT_UI_TEST_BUNDLE="PocketRootExternalConsumerAppUITests"
export POCKETROOT_UI_ARTIFACT_LABEL="PocketRoot External Consumer"
export POCKETROOT_UI_SMOKE_DEVICE="${POCKETROOT_EXTERNAL_CONSUMER_UI_SMOKE_DEVICE:-}"
export POCKETROOT_UI_DEVICE_TYPE="${POCKETROOT_EXTERNAL_CONSUMER_UI_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16}"
export POCKETROOT_UI_DEVICE_NAME="${POCKETROOT_EXTERNAL_CONSUMER_UI_DEVICE_NAME:-PocketRoot-External-Consumer-UI-Smoke-$$}"
export POCKETROOT_UI_ONLY_TESTING="${POCKETROOT_EXTERNAL_CONSUMER_UI_ONLY_TESTING:-PocketRootExternalConsumerAppUITests/PocketRootExternalConsumerAppUITests}"
export POCKETROOT_UI_DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE="${POCKETROOT_EXTERNAL_CONSUMER_UI_DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-600}"
export POCKETROOT_UI_MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE="${POCKETROOT_EXTERNAL_CONSUMER_UI_MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE:-600}"

"$ROOT_DIR/Scripts/run-ios-example-ui-smoke.sh" "$ARCHIVE_PATH"
