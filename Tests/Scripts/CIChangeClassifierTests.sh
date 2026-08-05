#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
CLASSIFIER="$ROOT_DIR/Scripts/classify-ci-changes.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PocketRootCIClassifierTests.XXXXXX")"
REPOSITORY="$TEST_ROOT/repository"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$REPOSITORY"
git -C "$REPOSITORY" init -q
git -C "$REPOSITORY" config user.name "PocketRoot CI Test"
git -C "$REPOSITORY" config user.email "ci-test@example.invalid"

commit_path() {
    local path="$1"
    mkdir -p "$REPOSITORY/$(dirname "$path")"
    printf '%s\n' "$path" > "$REPOSITORY/$path"
    git -C "$REPOSITORY" add -- "$path"
    git -C "$REPOSITORY" commit -q -m "Add $path"
    git -C "$REPOSITORY" rev-parse HEAD
}

assert_outputs() {
    local base="$1"
    local head="$2"
    local expected="$3"
    local output="$TEST_ROOT/output"
    : > "$output"
    POCKETROOT_CI_REPOSITORY_ROOT="$REPOSITORY" \
      "$CLASSIFIER" --base "$base" --head "$head" --output "$output"
    if [[ "$(cat "$output")" != "$expected" ]]; then
        echo "Unexpected classifier output for $base...$head:" >&2
        cat "$output" >&2
        exit 1
    fi
}

BASE="$(commit_path Docs/baseline.md)"
DOCS="$(commit_path Docs/change.md)"
assert_outputs "$BASE" "$DOCS" "$(cat <<'EOF'
package=false
ios=false
native=false
ui=false
external=false
EOF
)"

CORE="$(commit_path Sources/PocketRootCore/Change.swift)"
assert_outputs "$DOCS" "$CORE" "$(cat <<'EOF'
package=true
ios=true
native=true
ui=true
external=true
EOF
)"

AGENT="$(commit_path Sources/PocketRootAgent/Change.swift)"
assert_outputs "$CORE" "$AGENT" "$(cat <<'EOF'
package=true
ios=false
native=false
ui=false
external=false
EOF
)"

TERMINAL="$(commit_path Sources/PocketRootTerminal/Change.swift)"
assert_outputs "$AGENT" "$TERMINAL" "$(cat <<'EOF'
package=true
ios=true
native=false
ui=true
external=true
EOF
)"

C_ARCHIVE="$(commit_path Sources/CPocketRootArchiveSupport/Change.c)"
assert_outputs "$TERMINAL" "$C_ARCHIVE" "$(cat <<'EOF'
package=true
ios=true
native=true
ui=true
external=true
EOF
)"

UNKNOWN="$(commit_path FutureProduct/Change.swift)"
assert_outputs "$C_ARCHIVE" "$UNKNOWN" "$(cat <<'EOF'
package=true
ios=true
native=true
ui=true
external=true
EOF
)"

WORKFLOW="$(commit_path .github/workflows/ci.yml)"
assert_outputs "$UNKNOWN" "$WORKFLOW" "$(cat <<'EOF'
package=true
ios=true
native=true
ui=true
external=true
EOF
)"

CLASSIFIER_CHANGE="$(commit_path Scripts/classify-ci-changes.sh)"
assert_outputs "$WORKFLOW" "$CLASSIFIER_CHANGE" "$(cat <<'EOF'
package=true
ios=true
native=true
ui=true
external=true
EOF
)"

FULL_OUTPUT="$TEST_ROOT/full-output"
: > "$FULL_OUTPUT"
POCKETROOT_CI_REPOSITORY_ROOT="$REPOSITORY" \
  "$CLASSIFIER" --full --output "$FULL_OUTPUT"
if [[ "$(cat "$FULL_OUTPUT")" != "$(cat <<'EOF'
package=true
ios=true
native=true
ui=true
external=true
EOF
)" ]]; then
    echo "Full validation did not enable every CI tier." >&2
    exit 1
fi

echo "CI change classifier tests passed."
