#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
    brew install xcodegen
fi

swift package resolve
"$ROOT_DIR/Scripts/generate-project.sh"
