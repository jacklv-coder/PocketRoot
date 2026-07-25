#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT_DIR/Scripts/prepare-rootfs-smoke-manifest.rb"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootCandidateSmokeManifest.XXXXXX")"
INSIDE_CANDIDATE=""

cleanup() {
    local rc=$?
    trap - EXIT INT TERM HUP
    rm -rf -- "$TEST_ROOT"
    if [[ -n "$INSIDE_CANDIDATE" ]]; then
        rm -rf -- "$INSIDE_CANDIDATE"
    fi
    exit "$rc"
}
trap cleanup EXIT INT TERM HUP

CANDIDATE="$TEST_ROOT/candidate"
mkdir -p "$CANDIDATE"
printf 'candidate archive fixture\n' >"$CANDIDATE/fs.tar.gz"
cat >"$CANDIDATE/ROOTFS_IDENTITY" <<'IDENTITY'
ROOTFS_IDENTITY_SCHEMA=3
ROOTFS_RECIPE=alpine-fakefs-ishsv-v3
ALPINE_VERSION=3.19.1
ALPINE_ARCH=aarch64
ISH_GUEST_ARCH=arm64
IDENTITY

ROOTFS_SHA256="$(shasum -a 256 "$CANDIDATE/fs.tar.gz" | awk '{print $1}')"
ROOTFS_SIZE="$(stat -f '%z' "$CANDIDATE/fs.tar.gz")"
IDENTITY_SHA256="$(shasum -a 256 "$CANDIDATE/ROOTFS_IDENTITY" | awk '{print $1}')"
printf '%s  fs.tar.gz\n' "$ROOTFS_SHA256" >"$CANDIDATE/SHA256SUMS"
SUMS_SHA256="$(shasum -a 256 "$CANDIDATE/SHA256SUMS" | awk '{print $1}')"
RECIPE_SHA256="$(printf 'fixture recipe' | shasum -a 256 | awk '{print $1}')"
cat >"$CANDIDATE/ROOTFS_RECEIPT" <<RECEIPT
ROOTFS_RECEIPT_SCHEMA=1
ROOTFS_RECIPE_SHA256=$RECIPE_SHA256
ROOTFS_IDENTITY_SHA256=$IDENTITY_SHA256
ROOTFS_TARBALL_SHA256=$ROOTFS_SHA256
ROOTFS_SUMS_SHA256=$SUMS_SHA256
RECEIPT
RECEIPT_SHA256="$(shasum -a 256 "$CANDIDATE/ROOTFS_RECEIPT" | awk '{print $1}')"

write_candidate_metadata() {
    local distribution_authorized="$1"
    ruby -rjson - \
      "$CANDIDATE/ROOTFS_CANDIDATE.json" \
      "$distribution_authorized" \
      "$ROOTFS_SHA256" \
      "$ROOTFS_SIZE" \
      "$IDENTITY_SHA256" \
      "$SUMS_SHA256" \
      "$RECEIPT_SHA256" <<'RUBY'
path, authorized, rootfs_sha, rootfs_size, identity_sha, sums_sha, receipt_sha = ARGV
revision = "1" * 40
document = {
  "schemaVersion" => 1,
  "status" => "local-unapproved-candidate",
  "reproducibility" => {
    "buildCount" => 2,
    "comparison" => "byte-for-byte",
    "sharedHostToolSHA256" => "2" * 64
  },
  "source" => {
    "repository" => "https://github.com/jacklv-coder/ish-arm64-pkg",
    "revision" => revision,
    "ishRevision" => "3" * 40,
    "rootfsPinSHA256" => "4" * 64,
    "candidateScriptSHA256" => "5" * 64
  },
  "artifacts" => {
    "fs.tar.gz" => {"sha256" => rootfs_sha, "size" => Integer(rootfs_size)},
    "ROOTFS_IDENTITY" => {"sha256" => identity_sha},
    "SHA256SUMS" => {"sha256" => sums_sha},
    "ROOTFS_RECEIPT" => {"sha256" => receipt_sha}
  },
  "distributionAuthorized" => authorized == "true"
}
File.write(path, JSON.pretty_generate(document) + "\n")
RUBY
}

write_candidate_metadata false
OUTPUT="$TEST_ROOT/smoke-input.json"
ruby "$HELPER" \
  --archive "$CANDIDATE/fs.tar.gz" \
  --output "$OUTPUT" \
  --repository-root "$ROOT_DIR" \
  --candidate-directory "$CANDIDATE"

ruby -rjson -ruri - "$OUTPUT" "$ROOTFS_SHA256" "$ROOTFS_SIZE" <<'RUBY'
document = JSON.parse(File.read(ARGV[0]))
raise "unexpected schema" unless document["schemaVersion"] == 1
raise "candidate source missing" unless document["source"] == "local-unapproved-candidate"
raise "candidate was authorized" unless document["distributionAuthorized"] == false
raise "candidate version missing" unless document["version"] == "candidate-111111111111"
raise "candidate digest mismatch" unless document["sha256"] == ARGV[1]
raise "candidate size mismatch" unless document["archiveByteCount"] == Integer(ARGV[2])
raise "candidate URL is downloadable" unless URI(document["downloadURL"]).host == "invalid.invalid"
RUBY

set +e
ruby "$HELPER" \
  --archive "$CANDIDATE/fs.tar.gz" \
  --output "$OUTPUT" \
  --repository-root "$ROOT_DIR" \
  --candidate-directory "$CANDIDATE" >/dev/null 2>&1
existing_output_rc=$?
set -e
[[ "$existing_output_rc" -ne 0 ]] || {
    echo "Smoke manifest helper replaced an existing output." >&2
    exit 1
}

write_candidate_metadata true
set +e
ruby "$HELPER" \
  --archive "$CANDIDATE/fs.tar.gz" \
  --output "$TEST_ROOT/authorized.json" \
  --repository-root "$ROOT_DIR" \
  --candidate-directory "$CANDIDATE" >/dev/null 2>&1
authorized_rc=$?
set -e
[[ "$authorized_rc" -ne 0 ]] || {
    echo "Smoke manifest helper accepted distribution authorization." >&2
    exit 1
}
write_candidate_metadata false

cp "$CANDIDATE/fs.tar.gz" "$TEST_ROOT/other.tar.gz"
set +e
ruby "$HELPER" \
  --archive "$TEST_ROOT/other.tar.gz" \
  --output "$TEST_ROOT/other.json" \
  --repository-root "$ROOT_DIR" \
  --candidate-directory "$CANDIDATE" >/dev/null 2>&1
other_archive_rc=$?
set -e
[[ "$other_archive_rc" -ne 0 ]] || {
    echo "Smoke manifest helper accepted an archive outside the candidate." >&2
    exit 1
}

INSIDE_CANDIDATE="$(mktemp -d "$ROOT_DIR/.rootfs-candidate-smoke.XXXXXX")"
cp -R "$CANDIDATE/." "$INSIDE_CANDIDATE/"
set +e
ruby "$HELPER" \
  --archive "$INSIDE_CANDIDATE/fs.tar.gz" \
  --output "$TEST_ROOT/inside.json" \
  --repository-root "$ROOT_DIR" \
  --candidate-directory "$INSIDE_CANDIDATE" >/dev/null 2>&1
inside_rc=$?
set -e
[[ "$inside_rc" -ne 0 ]] || {
    echo "Smoke manifest helper accepted a candidate inside the repository." >&2
    exit 1
}

printf 'tampered\n' >>"$CANDIDATE/ROOTFS_IDENTITY"
set +e
ruby "$HELPER" \
  --archive "$CANDIDATE/fs.tar.gz" \
  --output "$TEST_ROOT/tampered.json" \
  --repository-root "$ROOT_DIR" \
  --candidate-directory "$CANDIDATE" >/dev/null 2>&1
tampered_rc=$?
set -e
[[ "$tampered_rc" -ne 0 ]] || {
    echo "Smoke manifest helper accepted tampered candidate evidence." >&2
    exit 1
}

echo "RootFS candidate smoke manifest tests passed."
