#!/usr/bin/env bash
set -euo pipefail

verify_release() {
  local repository="$1"
  local tag="$2"
  local expected_commit="$3"
  local immutable
  local peeled_commit

  immutable="$(
    gh api \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      "repos/${repository}/releases/tags/${tag}" \
      --jq '.immutable'
  )"
  if [[ "$immutable" != "true" ]]; then
    echo "${repository} release ${tag} is not immutable" >&2
    return 1
  fi

  peeled_commit="$(
    git ls-remote --tags "https://github.com/${repository}.git" \
      "refs/tags/${tag}^{}" |
      awk 'NR == 1 { print $1 }'
  )"
  if [[ "$peeled_commit" != "$expected_commit" ]]; then
    echo "${repository} tag ${tag} peels to ${peeled_commit:-<missing>}, expected ${expected_commit}" >&2
    return 1
  fi
}

verify_release \
  "jacklv-coder/ish-arm64-pkg" \
  "0.4.0-abi.9.1" \
  "2419f736b271beb52a699b2f780027cf280472b8"
verify_release \
  "jacklv-coder/SwiftTerm" \
  "1.15.0-pocketroot.1" \
  "dd2fb8ac5b861e7bf617c872895e338f38165648"

echo "Immutable upstream release pins verified."
