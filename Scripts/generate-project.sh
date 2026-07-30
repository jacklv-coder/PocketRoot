#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="$ROOT_DIR/Examples/PocketRootDemo"

cd "$DEMO_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is not installed."
    echo "Install with: brew install xcodegen"
    exit 1
fi

xcodegen generate --spec project.yml
echo "Generated Examples/PocketRootDemo/PocketRootDemo.xcodeproj"
