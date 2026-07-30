#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT_DIR/Scripts/build-signed-engineering-archive.sh"
PROJECT_SPEC="$ROOT_DIR/Examples/PocketRootDemo/project.yml"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootSignedArchiveContract.XXXXXX")"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

bash -n "$RUNNER"

if POCKETROOT_DEVELOPMENT_TEAM="" \
  POCKETROOT_SIGNED_ARCHIVE_OUTPUT="" \
  POCKETROOT_SPDX_SCHEMA="" \
  "$RUNNER" >/dev/null 2>&1; then
    echo "Signed archive runner accepted missing required inputs." >&2
    exit 1
fi

printf '{}\n' >"$TEST_ROOT/not-the-pinned-schema.json"
if POCKETROOT_DEVELOPMENT_TEAM="36XNX296J9" \
  POCKETROOT_SIGNED_ARCHIVE_OUTPUT="$TEST_ROOT/output" \
  POCKETROOT_SPDX_SCHEMA="$TEST_ROOT/not-the-pinned-schema.json" \
  "$RUNNER" >/dev/null 2>&1; then
    echo "Signed archive runner accepted an unpinned SPDX schema." >&2
    exit 1
fi

if ! grep -Fq -- 'PocketRootReleaseArtifactScanner.resolved_new_output(' "$RUNNER" \
  || ! grep -Fq -- '-destination "generic/platform=iOS"' "$RUNNER" \
  || ! grep -Fq -- '-allowProvisioningUpdates' "$RUNNER" \
  || ! grep -Fq -- 'CODE_SIGN_STYLE=Automatic' "$RUNNER" \
  || ! grep -Fq -- 'DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"' "$RUNNER" \
  || ! grep -Fq -- '--xcarchive "$ARCHIVE_PATH"' "$RUNNER" \
  || ! grep -Fq -- '--require-clean' "$RUNNER" \
  || ! grep -Fq -- '239208b7ac287b3cf5d9a9af23f9d69863971102a5e1587a27a398b43490b89b' "$RUNNER" \
  || ! grep -Fq -- 'npm ci' "$RUNNER" \
  || ! grep -Fq -- '--ignore-scripts' "$RUNNER" \
  || ! grep -Fq -- 'validate-spdx.mjs' "$RUNNER" \
  || ! grep -Fq -- '!mach_o_binaries.empty?' "$RUNNER" \
  || ! grep -Fq -- 'mach_o_binaries.all? { |binary|' "$RUNNER" \
  || ! grep -Fq -- 'binary.dig("signature", "status") == "signed-valid"' "$RUNNER" \
  || ! grep -Fq -- 'entitlements.fetch("get-task-allow") == true' "$RUNNER" \
  || ! grep -Fq -- 'coverage.fetch("distributionAuthorized") == false' "$RUNNER"; then
    echo "Signed archive runner does not enforce its build, scan, or closed-gate contract." >&2
    exit 1
fi

if grep -Fq -- "devicectl" "$RUNNER" \
  || grep -Fq -- "-exportArchive" "$RUNNER" \
  || grep -Fq -- "gh " "$RUNNER"; then
    echo "Signed archive runner installs, exports, or uploads an artifact." >&2
    exit 1
fi

SMOKE_TARGET="$(
  awk '
    /^  PocketRootIshRuntimeSmoke:/ { target = 1 }
    target && /^  PocketRootDemo:/ { exit }
    target { print }
  ' "$PROJECT_SPEC"
)"
SMOKE_SCHEME="$(
  awk '
    /^  PocketRootIshRuntimeSmoke:/ { count += 1; if (count == 2) scheme = 1 }
    scheme && /^  PocketRootDemo:/ { exit }
    scheme { print }
  ' "$PROJECT_SPEC"
)"

if ! grep -Fq -- "SKIP_INSTALL: NO" <<<"$SMOKE_TARGET" \
  || ! grep -Fq -- "archive:" <<<"$SMOKE_SCHEME" \
  || ! grep -Fq -- "config: Debug" <<<"$SMOKE_SCHEME"; then
    echo "Smoke target is not configured as a development engineering archive." >&2
    exit 1
fi

echo "Signed engineering archive runner contract passed."
