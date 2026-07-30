#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_PROJECT="$ROOT_DIR/Examples/PocketRootDemo/PocketRootDemo.xcodeproj"

cd "$ROOT_DIR"

xcodebuild \
  -project "$DEMO_PROJECT" \
  -scheme PocketRootDemo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
