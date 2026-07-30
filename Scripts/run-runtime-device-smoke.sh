#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="${1:-${POCKETROOT_ROOTFS_ARCHIVE:-}}"
CANDIDATE_DIRECTORY="${POCKETROOT_ROOTFS_CANDIDATE:-}"
DEVICE_REFERENCE="${POCKETROOT_SMOKE_DEVICE:-}"
DEVICE_ID=""
DEVELOPMENT_TEAM="${POCKETROOT_DEVELOPMENT_TEAM:-}"
BUNDLE_ID="com.jacklv.PocketRootIshRuntimeSmoke"
APP_PROCESS_NAME="PocketRootIshRuntimeSmoke"
SETTINGS_BUNDLE_ID="com.apple.Preferences"
ARCHIVE_NAME="pocketroot-fs-v0.3.3.tar.gz"
SMOKE_MANIFEST_NAME="pocketroot-smoke-rootfs.json"
REPORT_NAME="pocketroot-smoke-result.json"
SMOKE_TIMEOUT_SECONDS="${POCKETROOT_SMOKE_TIMEOUT_SECONDS:-300}"
LIFECYCLE_MODE="${POCKETROOT_SMOKE_LIFECYCLE:-0}"
UI_LIFECYCLE_MODE="${POCKETROOT_SMOKE_UI_LIFECYCLE:-0}"
RELAUNCH_PERSISTENCE_MODE="${POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE:-0}"
STORAGE_FAILURE_MODE="${POCKETROOT_SMOKE_STORAGE_FAILURE:-0}"
MEMORY_WARNING_MODE="${POCKETROOT_SMOKE_MEMORY_WARNING:-0}"
RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootDeviceSmoke.XXXXXX")"
DERIVED_DATA_ROOT="$RUN_ROOT/DerivedData"
CLONED_SOURCE_PACKAGES_DIR="${POCKETROOT_CLONED_SOURCE_PACKAGES_DIR:-${TMPDIR:-/tmp}/PocketRootSharedSourcePackages}"
CONSOLE_LOG="$RUN_ROOT/device-smoke-console.log"
REPORT_PATH="$RUN_ROOT/$REPORT_NAME"
EMPTY_REPORT_PATH="$RUN_ROOT/empty-$REPORT_NAME"
ENTITLEMENTS_PATH="$RUN_ROOT/PocketRootIshRuntimeSmoke.entitlements.plist"
DEVICE_DETAILS_PATH="$RUN_ROOT/device-details.json"
SMOKE_MANIFEST_PATH="$RUN_ROOT/$SMOKE_MANIFEST_NAME"
LAUNCH_RESULT_PATH="$RUN_ROOT/launch-result.json"
PROCESS_LIST_PATH="$RUN_ROOT/processes.json"
REACTIVATION_RESULT_PATH="$RUN_ROOT/reactivation-result.json"
SETTINGS_LAUNCH_RESULT_PATH="$RUN_ROOT/settings-launch-result.json"
PROGRESS_NAME="pocketroot-smoke-progress.txt"
PROGRESS_PATH="$RUN_ROOT/$PROGRESS_NAME"
RESUME_MARKER_NAME="pocketroot-smoke-lifecycle-resume.txt"
RESUME_MARKER_PATH="$RUN_ROOT/$RESUME_MARKER_NAME"
UI_LIFECYCLE_NAME="pocketroot-smoke-ui-lifecycle.txt"
APP_INSTALLED="false"
LAUNCH_CLIENT_PID=""
REMOTE_PROCESS_PID=""

remote_process_matches_smoke_app() {
    local timeout_seconds="$1"
    local executable_suffix="/$APP_PROCESS_NAME.app/$APP_PROCESS_NAME"

    if [[ -z "$REMOTE_PROCESS_PID" || -z "$DEVICE_ID" ]]; then
        return 1
    fi
    rm -f "$PROCESS_LIST_PATH"
    if ! xcrun devicectl device info processes \
      --device "$DEVICE_ID" \
      --timeout "$timeout_seconds" \
      --json-output "$PROCESS_LIST_PATH" \
      >/dev/null 2>&1; then
        return 2
    fi
    if plutil -extract result.runningProcesses xml1 \
      -o - "$PROCESS_LIST_PATH" 2>/dev/null \
      | awk \
        -v expected_pid="$REMOTE_PROCESS_PID" \
        -v expected_suffix="$executable_suffix" '
          /<dict>/ {
              process_identifier = ""
              executable = ""
          }
          /<key>processIdentifier<\/key>/ {
              getline
              process_identifier = $0
              gsub(/.*<integer>|<\/integer>.*/, "", process_identifier)
          }
          /<key>executable<\/key>/ {
              getline
              executable = $0
              gsub(/.*<string>|<\/string>.*/, "", executable)
          }
          /<\/dict>/ {
              suffix_start = length(executable) - length(expected_suffix) + 1
              if (process_identifier == expected_pid &&
                  suffix_start > 0 &&
                  substr(executable, suffix_start) == expected_suffix) {
                  found = 1
              }
          }
          END {
              exit(found ? 0 : 1)
          }
        '; then
        return 0
    fi
    return 1
}

terminate_remote_smoke_process() {
    local timeout_seconds="$1"

    if remote_process_matches_smoke_app "$timeout_seconds"; then
        xcrun devicectl device process terminate \
          --device "$DEVICE_ID" \
          --pid "$REMOTE_PROCESS_PID" \
          --timeout "$timeout_seconds" \
          >/dev/null 2>&1 || true
    fi
    REMOTE_PROCESS_PID=""
}

cleanup() {
    if [[ -n "$LAUNCH_CLIENT_PID" ]] && kill -0 "$LAUNCH_CLIENT_PID" >/dev/null 2>&1; then
        kill "$LAUNCH_CLIENT_PID" >/dev/null 2>&1 || true
        wait "$LAUNCH_CLIENT_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$REMOTE_PROCESS_PID" ]]; then
        terminate_remote_smoke_process 5
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
  [POCKETROOT_SMOKE_LIFECYCLE=1] \\
  [POCKETROOT_SMOKE_UI_LIFECYCLE=1] \\
  [POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE=1] \\
  [POCKETROOT_SMOKE_STORAGE_FAILURE=1] \\
  [POCKETROOT_SMOKE_MEMORY_WARNING=1] \\
  $0

For a local unapproved double-build candidate, replace
POCKETROOT_ROOTFS_ARCHIVE with:
  POCKETROOT_ROOTFS_CANDIDATE=/absolute/candidate-directory
EOF
}

if [[ -n "$CANDIDATE_DIRECTORY" && -z "$ARCHIVE_PATH" ]]; then
    ARCHIVE_PATH="$CANDIDATE_DIRECTORY/fs.tar.gz"
fi
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
if [[ ! "$SMOKE_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
  || [[ "$SMOKE_TIMEOUT_SECONDS" -lt 5 ]]; then
    echo "POCKETROOT_SMOKE_TIMEOUT_SECONDS must be an integer of at least 5." >&2
    exit 2
fi
if [[ "$LIFECYCLE_MODE" != "0" && "$LIFECYCLE_MODE" != "1" ]]; then
    echo "POCKETROOT_SMOKE_LIFECYCLE must be 0 or 1." >&2
    exit 2
fi
if [[ "$UI_LIFECYCLE_MODE" != "0" && "$UI_LIFECYCLE_MODE" != "1" ]]; then
    echo "POCKETROOT_SMOKE_UI_LIFECYCLE must be 0 or 1." >&2
    exit 2
fi
if [[ "$RELAUNCH_PERSISTENCE_MODE" != "0" && "$RELAUNCH_PERSISTENCE_MODE" != "1" ]]; then
    echo "POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE must be 0 or 1." >&2
    exit 2
fi
if [[ "$STORAGE_FAILURE_MODE" != "0" && "$STORAGE_FAILURE_MODE" != "1" ]]; then
    echo "POCKETROOT_SMOKE_STORAGE_FAILURE must be 0 or 1." >&2
    exit 2
fi
if [[ "$MEMORY_WARNING_MODE" != "0" && "$MEMORY_WARNING_MODE" != "1" ]]; then
    echo "POCKETROOT_SMOKE_MEMORY_WARNING must be 0 or 1." >&2
    exit 2
fi
HOST_CONTROL_MODE_COUNT=$((LIFECYCLE_MODE + UI_LIFECYCLE_MODE + RELAUNCH_PERSISTENCE_MODE))
if [[ "$HOST_CONTROL_MODE_COUNT" -gt 1 ]]; then
    echo "Select only one physical host-control smoke mode per run." >&2
    exit 2
fi
if [[ "$HOST_CONTROL_MODE_COUNT" -eq 1 && "$STORAGE_FAILURE_MODE" == "1" ]]; then
    echo "Storage failure smoke cannot be combined with a host-control mode." >&2
    exit 2
fi
if [[ "$MEMORY_WARNING_MODE" == "1" \
  && $((HOST_CONTROL_MODE_COUNT + STORAGE_FAILURE_MODE)) -gt 0 ]]; then
    echo "Memory-warning smoke cannot be combined with another optional mode." >&2
    exit 2
fi
SMOKE_MANIFEST_ARGS=(
  --archive "$ARCHIVE_PATH"
  --output "$SMOKE_MANIFEST_PATH"
  --repository-root "$ROOT_DIR"
)
if [[ -n "$CANDIDATE_DIRECTORY" ]]; then
    SMOKE_MANIFEST_ARGS+=(--candidate-directory "$CANDIDATE_DIRECTORY")
fi
ruby "$ROOT_DIR/Scripts/prepare-rootfs-smoke-manifest.rb" \
  "${SMOKE_MANIFEST_ARGS[@]}"

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
  -project "$ROOT_DIR/Examples/PocketRootDemo/PocketRootDemo.xcodeproj" \
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

xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --source "$SMOKE_MANIFEST_PATH" \
  --destination "Documents/$SMOKE_MANIFEST_NAME" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --timeout "$SMOKE_TIMEOUT_SECONDS"

if [[ "$HOST_CONTROL_MODE_COUNT" -eq 1 \
  || "$STORAGE_FAILURE_MODE" == "1" \
  || "$MEMORY_WARNING_MODE" == "1" ]]; then
    # A failed uninstall can preserve the prior data container. Clear progress
    # before launch so this run cannot accept stale host-control evidence.
    xcrun devicectl device copy to \
      --device "$DEVICE_ID" \
      --source "$EMPTY_REPORT_PATH" \
      --destination "Documents/$PROGRESS_NAME" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --timeout "$SMOKE_TIMEOUT_SECONDS"
    if [[ "$LIFECYCLE_MODE" == "1" ]]; then
        xcrun devicectl device copy to \
          --device "$DEVICE_ID" \
          --source "$EMPTY_REPORT_PATH" \
          --destination "Documents/$RESUME_MARKER_NAME" \
          --domain-type appDataContainer \
          --domain-identifier "$BUNDLE_ID" \
          --timeout "$SMOKE_TIMEOUT_SECONDS"
    elif [[ "$UI_LIFECYCLE_MODE" == "1" ]]; then
        xcrun devicectl device copy to \
          --device "$DEVICE_ID" \
          --source "$EMPTY_REPORT_PATH" \
          --destination "Documents/$UI_LIFECYCLE_NAME" \
          --domain-type appDataContainer \
          --domain-identifier "$BUNDLE_ID" \
          --timeout "$SMOKE_TIMEOUT_SECONDS"
    fi
fi

REPORT_READY="false"
REPORT_SUCCESS=""
REPORT_DEADLINE=$((SECONDS + SMOKE_TIMEOUT_SECONDS))
LAUNCH_EXIT_OBSERVED="false"
REMOTE_EXIT_OBSERVED="false"

bounded_smoke_timeout() {
    local maximum_seconds="$1"
    local remaining_seconds=$((REPORT_DEADLINE - SECONDS))

    # devicectl rejects timeout values below five seconds. Stop early instead
    # of issuing an operation that would exceed the shared smoke deadline.
    if [[ "$remaining_seconds" -lt 5 ]]; then
        return 1
    fi
    if [[ "$remaining_seconds" -gt "$maximum_seconds" ]]; then
        remaining_seconds="$maximum_seconds"
    fi
    printf '%s' "$remaining_seconds"
}

wait_for_remote_smoke_process_match() {
    local query_timeout
    local match_status

    while [[ "$SECONDS" -lt "$REPORT_DEADLINE" ]]; do
        if ! query_timeout="$(bounded_smoke_timeout 5)"; then
            return 2
        fi
        if remote_process_matches_smoke_app "$query_timeout"; then
            return 0
        else
            match_status=$?
        fi
        if [[ "$match_status" == "1" ]]; then
            return 1
        fi
        # CoreDevice process enumeration can fail transiently. Retry an
        # indeterminate query within the shared smoke deadline.
        sleep 1
    done
    return 2
}

wait_for_remote_smoke_process_exit() {
    local query_timeout
    local match_status

    while [[ "$SECONDS" -lt "$REPORT_DEADLINE" ]]; do
        if ! query_timeout="$(bounded_smoke_timeout 5)"; then
            return 1
        fi
        if remote_process_matches_smoke_app "$query_timeout"; then
            sleep 1
            continue
        else
            match_status=$?
        fi
        if [[ "$match_status" == "1" ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_remote_smoke_process_appearance() {
    local appearance_deadline=$((SECONDS + 15))
    local query_timeout

    while [[ "$SECONDS" -lt "$REPORT_DEADLINE" ]] \
      && [[ "$SECONDS" -lt "$appearance_deadline" ]]; do
        if ! query_timeout="$(bounded_smoke_timeout 5)"; then
            return 1
        fi
        if remote_process_matches_smoke_app "$query_timeout"; then
            return 0
        fi
        # A successful launch can become visible to process enumeration a
        # moment later. Retry both absent and indeterminate observations.
        sleep 1
    done
    return 1
}

retrieve_device_report() {
    local timeout_seconds="$1"

    rm -f "$REPORT_PATH"
    if xcrun devicectl device copy from \
      --device "$DEVICE_ID" \
      --source "Documents/$REPORT_NAME" \
      --destination "$REPORT_PATH" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --timeout "$timeout_seconds" \
      >/dev/null 2>&1 \
      && REPORT_SUCCESS="$(plutil -extract success raw -o - "$REPORT_PATH" 2>/dev/null)"; then
        REPORT_READY="true"
        return 0
    fi
    return 1
}

if [[ "$HOST_CONTROL_MODE_COUNT" -eq 1 ]]; then
    if [[ "$LIFECYCLE_MODE" == "1" ]]; then
        HOST_CONTROL_ENVIRONMENT='{"POCKETROOT_SMOKE_LIFECYCLE":"1"}'
        HOST_CONTROL_CHECKPOINT="awaiting-host-suspend"
        HOST_CONTROL_LABEL="Process-suspend"
    elif [[ "$UI_LIFECYCLE_MODE" == "1" ]]; then
        HOST_CONTROL_ENVIRONMENT='{"POCKETROOT_SMOKE_UI_LIFECYCLE":"1"}'
        HOST_CONTROL_CHECKPOINT="awaiting-host-background"
        HOST_CONTROL_LABEL="UIKit-lifecycle"
    else
        HOST_CONTROL_ENVIRONMENT='{"POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE":"seed"}'
        HOST_CONTROL_CHECKPOINT="awaiting-host-termination"
        HOST_CONTROL_LABEL="Forced-relaunch persistence"
    fi
    xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      --terminate-existing \
      --environment-variables "$HOST_CONTROL_ENVIRONMENT" \
      --timeout "$SMOKE_TIMEOUT_SECONDS" \
      --json-output "$LAUNCH_RESULT_PATH" \
      "$BUNDLE_ID"
    REMOTE_PROCESS_PID="$(
      plutil -extract result.process.processIdentifier raw \
        -o - "$LAUNCH_RESULT_PATH" 2>/dev/null || true
    )"
    if [[ ! "$REMOTE_PROCESS_PID" =~ ^[1-9][0-9]*$ ]]; then
        echo "$HOST_CONTROL_LABEL smoke launch did not return a process identifier." >&2
        exit 1
    fi

    HOST_CONTROL_CHECKPOINT_READY="false"
    while [[ "$SECONDS" -lt "$REPORT_DEADLINE" ]]; do
        if ! COPY_TIMEOUT_SECONDS="$(bounded_smoke_timeout 5)"; then
            break
        fi
        rm -f "$PROGRESS_PATH"
        if xcrun devicectl device copy from \
          --device "$DEVICE_ID" \
          --source "Documents/$PROGRESS_NAME" \
          --destination "$PROGRESS_PATH" \
          --domain-type appDataContainer \
          --domain-identifier "$BUNDLE_ID" \
          --timeout "$COPY_TIMEOUT_SECONDS" \
          >/dev/null 2>&1 \
          && [[ "$(cat "$PROGRESS_PATH")" == "$HOST_CONTROL_CHECKPOINT" ]]; then
            HOST_CONTROL_CHECKPOINT_READY="true"
            break
        fi
        if ! COPY_TIMEOUT_SECONDS="$(bounded_smoke_timeout 5)"; then
            break
        fi
        if retrieve_device_report "$COPY_TIMEOUT_SECONDS"; then
            cat "$REPORT_PATH" >&2
            echo "$HOST_CONTROL_LABEL smoke App reported before reaching its host checkpoint." >&2
            exit 1
        fi
        if ! PROCESS_QUERY_TIMEOUT="$(bounded_smoke_timeout 5)"; then
            break
        fi
        if remote_process_matches_smoke_app "$PROCESS_QUERY_TIMEOUT"; then
            :
        else
            PROCESS_MATCH_STATUS=$?
            if [[ "$PROCESS_MATCH_STATUS" == "1" ]]; then
                echo "$HOST_CONTROL_LABEL smoke App exited before reaching its host checkpoint." >&2
                exit 1
            fi
        fi
        sleep 1
    done
    if [[ "$HOST_CONTROL_CHECKPOINT_READY" != "true" ]]; then
        if [[ -f "$PROGRESS_PATH" ]]; then
            echo "Last host-control smoke progress: $(cat "$PROGRESS_PATH")" >&2
        fi
        echo "$HOST_CONTROL_LABEL smoke did not reach its host checkpoint." >&2
        exit 1
    fi

    if [[ "$LIFECYCLE_MODE" == "1" ]]; then
        if ! HOST_OPERATION_TIMEOUT="$(bounded_smoke_timeout 15)"; then
            echo "Lifecycle smoke deadline expired before process suspension." >&2
            exit 1
        fi
        xcrun devicectl device process suspend \
          --device "$DEVICE_ID" \
          --pid "$REMOTE_PROCESS_PID" \
          --timeout "$HOST_OPERATION_TIMEOUT"
        if [[ $((REPORT_DEADLINE - SECONDS)) -lt 8 ]]; then
            echo "Lifecycle smoke deadline cannot cover suspension and resume." >&2
            exit 1
        fi
        sleep 3
        if ! HOST_OPERATION_TIMEOUT="$(bounded_smoke_timeout 15)"; then
            echo "Lifecycle smoke deadline expired before process resume." >&2
            exit 1
        fi
        xcrun devicectl device process resume \
          --device "$DEVICE_ID" \
          --pid "$REMOTE_PROCESS_PID" \
          --timeout "$HOST_OPERATION_TIMEOUT"
        printf 'resume\n' >"$RESUME_MARKER_PATH"
        if ! HOST_OPERATION_TIMEOUT="$(bounded_smoke_timeout 15)"; then
            echo "Lifecycle smoke deadline expired before resume acknowledgement." >&2
            exit 1
        fi
        xcrun devicectl device copy to \
          --device "$DEVICE_ID" \
          --source "$RESUME_MARKER_PATH" \
          --destination "Documents/$RESUME_MARKER_NAME" \
          --domain-type appDataContainer \
          --domain-identifier "$BUNDLE_ID" \
          --timeout "$HOST_OPERATION_TIMEOUT"
    elif [[ "$UI_LIFECYCLE_MODE" == "1" ]]; then
        if wait_for_remote_smoke_process_match; then
            :
        else
            PROCESS_MATCH_STATUS=$?
            if [[ "$PROCESS_MATCH_STATUS" == "1" ]]; then
                echo "UIKit lifecycle App exited before backgrounding." >&2
            else
                echo "UIKit lifecycle process query deadline expired before backgrounding." >&2
            fi
            exit 1
        fi
        if ! HOST_OPERATION_TIMEOUT="$(bounded_smoke_timeout 15)"; then
            echo "UIKit lifecycle deadline expired before launching Settings." >&2
            exit 1
        fi
        rm -f "$SETTINGS_LAUNCH_RESULT_PATH"
        xcrun devicectl device process launch \
          --device "$DEVICE_ID" \
          --timeout "$HOST_OPERATION_TIMEOUT" \
          --json-output "$SETTINGS_LAUNCH_RESULT_PATH" \
          "$SETTINGS_BUNDLE_ID"

        UI_BACKGROUND_READY="false"
        while [[ "$SECONDS" -lt "$REPORT_DEADLINE" ]]; do
            if ! COPY_TIMEOUT_SECONDS="$(bounded_smoke_timeout 5)"; then
                break
            fi
            rm -f "$PROGRESS_PATH"
            if xcrun devicectl device copy from \
              --device "$DEVICE_ID" \
              --source "Documents/$PROGRESS_NAME" \
              --destination "$PROGRESS_PATH" \
              --domain-type appDataContainer \
              --domain-identifier "$BUNDLE_ID" \
              --timeout "$COPY_TIMEOUT_SECONDS" \
              >/dev/null 2>&1 \
              && [[ "$(cat "$PROGRESS_PATH")" == "host-backgrounded" ]]; then
                UI_BACKGROUND_READY="true"
                break
            fi
            if ! COPY_TIMEOUT_SECONDS="$(bounded_smoke_timeout 5)"; then
                break
            fi
            if retrieve_device_report "$COPY_TIMEOUT_SECONDS"; then
                cat "$REPORT_PATH" >&2
                echo "UIKit lifecycle App reported before its background callback." >&2
                exit 1
            fi
            if ! PROCESS_QUERY_TIMEOUT="$(bounded_smoke_timeout 5)"; then
                break
            fi
            if remote_process_matches_smoke_app "$PROCESS_QUERY_TIMEOUT"; then
                sleep 1
            else
                PROCESS_MATCH_STATUS=$?
                if [[ "$PROCESS_MATCH_STATUS" == "1" ]]; then
                    echo "UIKit lifecycle App exited while backgrounded." >&2
                    exit 1
                fi
                sleep 1
            fi
        done
        if [[ "$UI_BACKGROUND_READY" != "true" ]]; then
            echo "UIKit lifecycle App did not report its background callback." >&2
            exit 1
        fi

        if ! HOST_OPERATION_TIMEOUT="$(bounded_smoke_timeout 15)"; then
            echo "UIKit lifecycle deadline expired before foreground activation." >&2
            exit 1
        fi
        rm -f "$REACTIVATION_RESULT_PATH"
        xcrun devicectl device process launch \
          --device "$DEVICE_ID" \
          --timeout "$HOST_OPERATION_TIMEOUT" \
          --json-output "$REACTIVATION_RESULT_PATH" \
          "$BUNDLE_ID"
        REACTIVATED_PROCESS_PID="$(
          plutil -extract result.process.processIdentifier raw \
            -o - "$REACTIVATION_RESULT_PATH" 2>/dev/null || true
        )"
        if [[ "$REACTIVATED_PROCESS_PID" != "$REMOTE_PROCESS_PID" ]]; then
            echo "UIKit lifecycle activation did not preserve the smoke process PID." >&2
            exit 1
        fi
        if wait_for_remote_smoke_process_match; then
            :
        else
            PROCESS_MATCH_STATUS=$?
            if [[ "$PROCESS_MATCH_STATUS" == "1" ]]; then
                echo "UIKit lifecycle activation lost the original smoke process." >&2
            else
                echo "UIKit lifecycle process query deadline expired after activation." >&2
            fi
            exit 1
        fi
    else
        if ! HOST_OPERATION_TIMEOUT="$(bounded_smoke_timeout 15)"; then
            echo "Forced-relaunch deadline expired before seed-process termination." >&2
            exit 1
        fi
        SEED_PROCESS_PID="$REMOTE_PROCESS_PID"
        xcrun devicectl device process terminate \
          --device "$DEVICE_ID" \
          --pid "$SEED_PROCESS_PID" \
          --kill \
          --timeout "$HOST_OPERATION_TIMEOUT"
        if ! wait_for_remote_smoke_process_exit; then
            echo "Forced-relaunch seed process did not terminate within the deadline." >&2
            exit 1
        fi
        REMOTE_PROCESS_PID=""

        # Fail closed if the seed process raced with termination and managed to
        # persist a report. The verification process must produce fresh evidence.
        if ! HOST_OPERATION_TIMEOUT="$(bounded_smoke_timeout 15)"; then
            echo "Forced-relaunch deadline expired before evidence reset." >&2
            exit 1
        fi
        xcrun devicectl device copy to \
          --device "$DEVICE_ID" \
          --source "$EMPTY_REPORT_PATH" \
          --destination "Documents/$REPORT_NAME" \
          --domain-type appDataContainer \
          --domain-identifier "$BUNDLE_ID" \
          --timeout "$HOST_OPERATION_TIMEOUT"
        xcrun devicectl device copy to \
          --device "$DEVICE_ID" \
          --source "$EMPTY_REPORT_PATH" \
          --destination "Documents/$PROGRESS_NAME" \
          --domain-type appDataContainer \
          --domain-identifier "$BUNDLE_ID" \
          --timeout "$HOST_OPERATION_TIMEOUT"

        if ! HOST_OPERATION_TIMEOUT="$(bounded_smoke_timeout 15)"; then
            echo "Forced-relaunch deadline expired before verification launch." >&2
            exit 1
        fi
        rm -f "$REACTIVATION_RESULT_PATH"
        xcrun devicectl device process launch \
          --device "$DEVICE_ID" \
          --environment-variables \
            '{"POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE":"verify"}' \
          --timeout "$HOST_OPERATION_TIMEOUT" \
          --json-output "$REACTIVATION_RESULT_PATH" \
          "$BUNDLE_ID"
        REMOTE_PROCESS_PID="$(
          plutil -extract result.process.processIdentifier raw \
            -o - "$REACTIVATION_RESULT_PATH" 2>/dev/null || true
        )"
        if [[ ! "$REMOTE_PROCESS_PID" =~ ^[1-9][0-9]*$ ]]; then
            echo "Forced-relaunch verification did not return a process identifier." >&2
            exit 1
        fi
        if [[ "$REMOTE_PROCESS_PID" == "$SEED_PROCESS_PID" ]]; then
            echo "Forced-relaunch verification did not start a new process." >&2
            exit 1
        fi
        if ! wait_for_remote_smoke_process_appearance; then
            echo "Forced-relaunch verification process was not observable." >&2
            exit 1
        fi
    fi
elif [[ "$STORAGE_FAILURE_MODE" == "1" ]]; then
    xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      --terminate-existing \
      --environment-variables \
        '{"POCKETROOT_SMOKE_STORAGE_FAILURE":"1"}' \
      --console \
      --timeout "$SMOKE_TIMEOUT_SECONDS" \
      "$BUNDLE_ID" \
      >"$CONSOLE_LOG" 2>&1 &
    LAUNCH_CLIENT_PID=$!
elif [[ "$MEMORY_WARNING_MODE" == "1" ]]; then
    xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      --terminate-existing \
      --environment-variables \
        '{"POCKETROOT_SMOKE_MEMORY_WARNING":"1"}' \
      --console \
      --timeout "$SMOKE_TIMEOUT_SECONDS" \
      "$BUNDLE_ID" \
      >"$CONSOLE_LOG" 2>&1 &
    LAUNCH_CLIENT_PID=$!
else
    xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      --terminate-existing \
      --console \
      --timeout "$SMOKE_TIMEOUT_SECONDS" \
      "$BUNDLE_ID" \
      >"$CONSOLE_LOG" 2>&1 &
    LAUNCH_CLIENT_PID=$!
fi

while [[ "$SECONDS" -lt "$REPORT_DEADLINE" ]]; do
    if ! COPY_TIMEOUT_SECONDS="$(bounded_smoke_timeout 5)"; then
        break
    fi
    if retrieve_device_report "$COPY_TIMEOUT_SECONDS"; then
        break
    fi
    if [[ -n "$LAUNCH_CLIENT_PID" ]] \
      && ! kill -0 "$LAUNCH_CLIENT_PID" >/dev/null 2>&1; then
        if [[ "$LAUNCH_EXIT_OBSERVED" == "true" ]]; then
            break
        fi
        # Permit one final bounded copy attempt if the console client ends.
        LAUNCH_EXIT_OBSERVED="true"
        sleep 0.25
    elif [[ -n "$REMOTE_PROCESS_PID" ]]; then
        if ! PROCESS_QUERY_TIMEOUT="$(bounded_smoke_timeout 5)"; then
            break
        fi
        if remote_process_matches_smoke_app "$PROCESS_QUERY_TIMEOUT"; then
            sleep 1
        else
            PROCESS_MATCH_STATUS=$?
            if [[ "$PROCESS_MATCH_STATUS" == "1" ]]; then
                if [[ "$REMOTE_EXIT_OBSERVED" == "true" ]]; then
                    break
                fi
                # Permit one final bounded report copy after remote exit.
                REMOTE_EXIT_OBSERVED="true"
                sleep 0.25
            else
                sleep 1
            fi
        fi
    else
        sleep 1
    fi
done

if [[ "$REPORT_READY" != "true" ]]; then
    if [[ -f "$CONSOLE_LOG" ]]; then
        cat "$CONSOLE_LOG" >&2
    fi
    if [[ "$HOST_CONTROL_MODE_COUNT" -eq 1 ]]; then
        rm -f "$PROGRESS_PATH"
        if xcrun devicectl device copy from \
          --device "$DEVICE_ID" \
          --source "Documents/$PROGRESS_NAME" \
          --destination "$PROGRESS_PATH" \
          --domain-type appDataContainer \
          --domain-identifier "$BUNDLE_ID" \
          --timeout 5 \
          >/dev/null 2>&1; then
            echo "Last host-control smoke progress: $(cat "$PROGRESS_PATH")" >&2
        fi
    fi
    echo "The device smoke report could not be retrieved before launch ended or timed out." >&2
    exit 1
fi

cat "$REPORT_PATH"
if [[ "$REPORT_SUCCESS" != "true" ]]; then
    if [[ -f "$CONSOLE_LOG" ]]; then
        cat "$CONSOLE_LOG" >&2
    fi
    exit 1
fi

# Success is written only after soft shutdown returned, `.terminated` was
# observed, and a later command returned restartRequired. Stop the console
# client or detached lifecycle process; normal cleanup then uninstalls the App.
if [[ -n "$LAUNCH_CLIENT_PID" ]]; then
    kill "$LAUNCH_CLIENT_PID" >/dev/null 2>&1 || true
    wait "$LAUNCH_CLIENT_PID" >/dev/null 2>&1 || true
fi
LAUNCH_CLIENT_PID=""
if [[ -n "$REMOTE_PROCESS_PID" ]]; then
    terminate_remote_smoke_process 5
fi
if [[ -f "$CONSOLE_LOG" ]]; then
    cat "$CONSOLE_LOG"
fi

echo "Physical-device native smoke passed on $DEVICE_ID."
