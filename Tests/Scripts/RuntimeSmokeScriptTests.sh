#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PARSER="$ROOT_DIR/Scripts/select-ios18-simulator-runtime.awk"

assert_runtime() {
    local expected="$1"
    local input="$2"
    local actual

    actual="$(printf '%s\n' "$input" | awk -f "$PARSER")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected runtime '$expected', got '$actual'." >&2
        exit 1
    fi
}

assert_runtime \
  "com.apple.CoreSimulator.SimRuntime.iOS-18-2" \
  "iOS 18.2 (18.2 - 22C150) - com.apple.CoreSimulator.SimRuntime.iOS-18-2"

assert_runtime \
  "com.apple.CoreSimulator.SimRuntime.iOS-18-4" \
  "iOS 18.4 (18.4 - 22E238) - com.apple.CoreSimulator.SimRuntime.iOS-18-4 (available)"

assert_runtime \
  "com.apple.CoreSimulator.SimRuntime.iOS-18-5" \
  $'iOS 17.5 (17.5 - 21F79) - com.apple.CoreSimulator.SimRuntime.iOS-17-5\niOS 18.5 (18.5 - 22F76) - com.apple.CoreSimulator.SimRuntime.iOS-18-5\niOS 18.6 (18.6 - 22G86) - com.apple.CoreSimulator.SimRuntime.iOS-18-6'

assert_runtime "" \
  "iOS 17.5 (17.5 - 21F79) - com.apple.CoreSimulator.SimRuntime.iOS-17-5"

echo "Runtime smoke script tests passed."
