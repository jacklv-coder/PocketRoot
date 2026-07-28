#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
DEVELOPMENT_TEAM="${POCKETROOT_DEVELOPMENT_TEAM:-}"
OUTPUT_ROOT="${POCKETROOT_SIGNED_ARCHIVE_OUTPUT:-}"
SPDX_SCHEMA="${POCKETROOT_SPDX_SCHEMA:-}"
SPDX_SCHEMA_SHA256="239208b7ac287b3cf5d9a9af23f9d69863971102a5e1587a27a398b43490b89b"
CLONED_SOURCE_PACKAGES_DIR="${POCKETROOT_CLONED_SOURCE_PACKAGES_DIR:-}"
BUNDLE_IDENTIFIER="com.jacklv.PocketRootIshRuntimeSmoke"
SCHEME="PocketRootIshRuntimeSmoke"
STAGING_ROOT=""
WORK_ROOT=""
SUCCEEDED=0

usage() {
    cat >&2 <<EOF
Usage:
  POCKETROOT_DEVELOPMENT_TEAM=<team-id> \\
  POCKETROOT_SIGNED_ARCHIVE_OUTPUT=/absolute/new/output-directory \\
  POCKETROOT_SPDX_SCHEMA=/absolute/spdx-2.3-schema.json \\
    $0

The command builds a development-signed engineering xcarchive, scans it, and
leaves the archive and evidence outside the repository. It never installs an
App, uploads an artifact, exports an IPA, or authorizes distribution.
EOF
}

cleanup() {
    if [[ -n "$WORK_ROOT" && -d "$WORK_ROOT" ]]; then
        rm -rf "$WORK_ROOT"
    fi
    if [[ "$SUCCEEDED" != "1" && -n "$STAGING_ROOT" && -d "$STAGING_ROOT" ]]; then
        rm -rf "$STAGING_ROOT"
    fi
}
trap cleanup EXIT

if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "POCKETROOT_DEVELOPMENT_TEAM must be a 10-character Apple team ID." >&2
    usage
    exit 2
fi
if [[ -z "$OUTPUT_ROOT" || "$OUTPUT_ROOT" != /* ]]; then
    echo "POCKETROOT_SIGNED_ARCHIVE_OUTPUT must be an absolute new directory." >&2
    usage
    exit 2
fi
if [[ -z "$SPDX_SCHEMA" || "$SPDX_SCHEMA" != /* \
  || ! -f "$SPDX_SCHEMA" || -L "$SPDX_SCHEMA" ]]; then
    echo "POCKETROOT_SPDX_SCHEMA must be an absolute real regular file." >&2
    usage
    exit 2
fi
ACTUAL_SPDX_SCHEMA_SHA256="$(
  ruby -rdigest -e \
    'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' \
    "$SPDX_SCHEMA"
)"
if [[ "$ACTUAL_SPDX_SCHEMA_SHA256" != "$SPDX_SCHEMA_SHA256" ]]; then
    echo "POCKETROOT_SPDX_SCHEMA does not match the pinned official SPDX 2.3 schema." >&2
    exit 2
fi

for tool in xcodebuild xcodegen ruby node npm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool is unavailable: $tool" >&2
        exit 2
    fi
done

npm ci \
  --prefix "$ROOT_DIR/Scripts/rootfs-compliance-validator" \
  --ignore-scripts \
  --no-audit \
  --no-fund

OUTPUT_ROOT="$(
  ruby -rpathname -I "$ROOT_DIR/Scripts" -e '
  require "scan-release-artifact"
  puts PocketRootReleaseArtifactScanner.resolved_new_output(
    Pathname(ARGV.fetch(0))
  )
' "$OUTPUT_ROOT"
)"

OUTPUT_PARENT="$(dirname "$OUTPUT_ROOT")"
STAGING_ROOT="$(mktemp -d "$OUTPUT_PARENT/.PocketRootSignedArchive.XXXXXX")"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootSignedArchiveWork.XXXXXX")"
ARCHIVE_PATH="$STAGING_ROOT/$SCHEME.xcarchive"
EVIDENCE_PATH="$STAGING_ROOT/evidence"
DERIVED_DATA_PATH="$WORK_ROOT/DerivedData"

if [[ -z "$CLONED_SOURCE_PACKAGES_DIR" ]]; then
    CLONED_SOURCE_PACKAGES_DIR="$WORK_ROOT/SourcePackages"
    mkdir "$CLONED_SOURCE_PACKAGES_DIR"
elif [[ "$CLONED_SOURCE_PACKAGES_DIR" != /* \
  || ! -d "$CLONED_SOURCE_PACKAGES_DIR" \
  || -L "$CLONED_SOURCE_PACKAGES_DIR" ]]; then
    echo "POCKETROOT_CLONED_SOURCE_PACKAGES_DIR must be an absolute real directory." >&2
    exit 2
else
    ruby -rpathname -I "$ROOT_DIR/Scripts" -e '
      require "scan-release-artifact"
      PocketRootReleaseArtifactScanner.real_external_directory(
        Pathname(ARGV.fetch(0)),
        "POCKETROOT_CLONED_SOURCE_PACKAGES_DIR"
      )
    ' "$CLONED_SOURCE_PACKAGES_DIR"
fi

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/generate-project.sh"
xcodebuild \
  -quiet \
  -project PocketRootDemo.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR" \
  -allowProvisioningUpdates \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  archive

ruby "$ROOT_DIR/Scripts/scan-release-artifact.rb" \
  --xcarchive "$ARCHIVE_PATH" \
  --output "$EVIDENCE_PATH" \
  --expected-bundle-identifier "$BUNDLE_IDENTIFIER"
ruby "$ROOT_DIR/Scripts/scan-release-artifact.rb" \
  --xcarchive "$ARCHIVE_PATH" \
  --verify "$EVIDENCE_PATH" \
  --expected-bundle-identifier "$BUNDLE_IDENTIFIER" \
  --require-clean
node "$ROOT_DIR/Scripts/rootfs-compliance-validator/validate-spdx.mjs" \
  "$SPDX_SCHEMA" \
  "$EVIDENCE_PATH/SBOM.spdx.json"

ruby -rjson -e '
  inventory =
    JSON.parse(
      File.binread(
        File.join(ARGV.fetch(0), "ARTIFACT-INVENTORY.json")
      )
    )
  signature = inventory.fetch("signature")
  entitlements = signature.fetch("entitlements")
  mach_o_binaries = inventory.fetch("machOBinaries")
  coverage = inventory.fetch("coverage")
  unless inventory.dig("input", "kind") == "xcarchive" &&
    signature.fetch("status") == "signed-valid" &&
    signature.fetch("valid") == true &&
    !mach_o_binaries.empty? &&
    mach_o_binaries.all? { |binary|
      binary.dig("signature", "status") == "signed-valid" &&
        binary.dig("signature", "valid") == true
    } &&
    entitlements.fetch("get-task-allow") == true &&
    entitlements.fetch("com.apple.developer.team-identifier") ==
      ARGV.fetch(1) &&
    coverage.fetch("signedReleaseArtifact") == false &&
    coverage.fetch("exportedReleaseArtifact") == false &&
    coverage.fetch("completeReleaseArtifactSBOM") == false &&
    coverage.fetch("distributionAuthorized") == false
    abort "signed engineering archive evidence gates drifted"
  end
' "$EVIDENCE_PATH" "$DEVELOPMENT_TEAM"

mv "$STAGING_ROOT" "$OUTPUT_ROOT"
SUCCEEDED=1
echo "Signed engineering archive and scan evidence are available at $OUTPUT_ROOT."
echo "No App was installed or uploaded; every release/distribution gate remains closed."
