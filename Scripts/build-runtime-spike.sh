#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_PROJECT="$ROOT_DIR/Examples/PocketRootDemo/PocketRootDemo.xcodeproj"
DERIVED_DATA_ROOT="${TMPDIR:-/tmp}/PocketRootIshRuntimeCompileSpike"

cd "$ROOT_DIR"

"$ROOT_DIR/Scripts/generate-project.sh"

for destination in 'generic/platform=iOS Simulator' 'generic/platform=iOS'; do
    suffix="$(printf '%s' "$destination" | tr ' /=' '---')"
    xcodebuild \
      -project "$DEMO_PROJECT" \
      -scheme PocketRootIshRuntimeCompileSpike \
      -configuration Debug \
      -destination "$destination" \
      -derivedDataPath "$DERIVED_DATA_ROOT-$suffix" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      build
done
