#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT="${POCKETROOT_CI_REPOSITORY_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
OUTPUT_PATH=""
BASE_REVISION=""
HEAD_REVISION=""
FULL_VALIDATION="false"

usage() {
    echo "Usage: $0 [--full | --base REV --head REV] --output PATH" >&2
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --full)
            FULL_VALIDATION="true"
            shift
            ;;
        --base)
            BASE_REVISION="${2:-}"
            shift 2
            ;;
        --head)
            HEAD_REVISION="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="${2:-}"
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$OUTPUT_PATH" ]]; then
    usage
    exit 2
fi
if [[ "$FULL_VALIDATION" == "true" ]]; then
    if [[ -n "$BASE_REVISION" || -n "$HEAD_REVISION" ]]; then
        usage
        exit 2
    fi
elif [[ -z "$BASE_REVISION" || -z "$HEAD_REVISION" ]]; then
    usage
    exit 2
fi

package="false"
ios="false"
native="false"
ui="false"
external="false"

enable_all() {
    package="true"
    ios="true"
    native="true"
    ui="true"
    external="true"
}

classify_path() {
    local path="$1"
    local classified="false"

    case "$path" in
        Package.swift|Package.resolved|.github/workflows/ci.yml|.github/actions/setup-minimum-xcode-16/*|Scripts/classify-ci-changes.sh|Scripts/verify-pr-ci-reuse.rb|Tests/Scripts/CIChangeClassifierTests.sh|Tests/Scripts/PRCIReuseTests.rb)
            enable_all
            return
            ;;
    esac

    case "$path" in
        CHANGELOG.md|CHANGELOG.en.md|CODE_OF_CONDUCT.md|CONTRIBUTING.md|CONTRIBUTING.en.md|LICENSE|README.md|README.en.md|SECURITY.md|SECURITY.en.md|Docs/*|Compliance/*|.github/ISSUE_TEMPLATE/*|.github/PULL_REQUEST_TEMPLATE.md|.github/workflows/source-release.yml|Tests/Scripts/*)
            return
            ;;
    esac

    case "$path" in
        Sources/*|Tests/PocketRoot*Tests/*)
            package="true"
            classified="true"
            ;;
    esac

    case "$path" in
        Sources/CPocketRootArchiveSupport/*|Sources/PocketRoot/*|Sources/PocketRootCore/*|Sources/PocketRootResources/*|Sources/PocketRootTerminal/*|Sources/PocketRootIshRuntime/*|Sources/PocketRootIshRuntimeIntegration/*|Tests/PocketRootCoreTests/*|Tests/PocketRootResourcesTests/*|Tests/PocketRootTerminalTests/*|Tests/PocketRootIshRuntimeTests/*|Tests/PocketRootIshRuntimeIntegrationTests/*|Examples/*|Spikes/*|Scripts/bootstrap.sh|Scripts/build.sh|Scripts/generate-project.sh|Scripts/inject-demo-rootfs.sh)
            ios="true"
            classified="true"
            ;;
    esac

    case "$path" in
        Sources/CPocketRootArchiveSupport/*|Sources/PocketRootCore/*|Sources/PocketRootResources/*|Sources/PocketRootIshRuntime/*|Sources/PocketRootIshRuntimeIntegration/*|Tests/PocketRootCoreTests/*|Tests/PocketRootResourcesTests/*|Tests/PocketRootIshRuntimeTests/*|Tests/PocketRootIshRuntimeIntegrationTests/*|Examples/PocketRootDemo/*|Spikes/*|Scripts/build-runtime-spike.sh|Scripts/run-runtime-smoke.sh|Scripts/select-ios18-simulator-runtime.awk)
            native="true"
            classified="true"
            ;;
    esac

    case "$path" in
        Sources/CPocketRootArchiveSupport/*|Sources/PocketRoot/*|Sources/PocketRootCore/*|Sources/PocketRootResources/*|Sources/PocketRootTerminal/*|Sources/PocketRootIshRuntime/*|Sources/PocketRootIshRuntimeIntegration/*|Examples/*|Scripts/run-ios-example-ui-smoke.sh|Scripts/run-host-app-ui-smoke.sh|Scripts/run-quick-start-ui-smoke.sh|Scripts/run-external-consumer-ui-smoke.sh|Scripts/inject-demo-rootfs.sh|Scripts/generate-project.sh)
            ui="true"
            classified="true"
            ;;
    esac

    case "$path" in
        Sources/CPocketRootArchiveSupport/*|Sources/PocketRoot/*|Sources/PocketRootCore/*|Sources/PocketRootResources/*|Sources/PocketRootTerminal/*|Sources/PocketRootIshRuntime/*|Sources/PocketRootIshRuntimeIntegration/*|Tests/Integration/ExternalConsumerApp/*|Scripts/run-external-consumer-ui-smoke.sh|Scripts/run-ios-example-ui-smoke.sh)
            external="true"
            classified="true"
            ;;
    esac

    if [[ "$classified" == "false" ]]; then
        enable_all
    fi
}

if [[ "$FULL_VALIDATION" == "true" ]]; then
    enable_all
else
    git -C "$REPOSITORY_ROOT" rev-parse --verify "$BASE_REVISION^{commit}" >/dev/null
    git -C "$REPOSITORY_ROOT" rev-parse --verify "$HEAD_REVISION^{commit}" >/dev/null
    while IFS= read -r -d '' path; do
        classify_path "$path"
    done < <(
        git -C "$REPOSITORY_ROOT" diff \
          --name-only \
          --diff-filter=ACDMRTUXB \
          -z \
          "$BASE_REVISION...$HEAD_REVISION"
    )
fi

{
    echo "package=$package"
    echo "ios=$ios"
    echo "native=$native"
    echo "ui=$ui"
    echo "external=$external"
} >> "$OUTPUT_PATH"
