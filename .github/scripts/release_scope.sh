#!/usr/bin/env bash
# Release and version validation helpers for GitHub Actions.
#
# A release runs only when VERSION changes on push to main and the new value
# exceeds the latest GitHub release tag. PRs validate VERSION only when the PR
# modifies that file.

set -euo pipefail

current_version() {
  tr -d '[:space:]' < VERSION
}

version_lt() {
  local left=$1
  local right=$2

  [[ "$left" != "$right" && "$(printf '%s\n' "$left" "$right" | sort -V | head -1)" == "$left" ]]
}

released_version() {
  local latest_tag=${1:-}

  if [[ -z "$latest_tag" ]]; then
    return 0
  fi

  if [[ "$latest_tag" != v* ]]; then
    echo "::error::Latest release tag '$latest_tag' must start with 'v'." >&2
    return 1
  fi

  echo "${latest_tag#v}"
}

assert_version_not_behind_release() {
  local current=$1
  local released=$2

  if [[ -n "$released" ]] && version_lt "$current" "$released"; then
    echo "::error::VERSION ($current) is behind the latest release (v$released). Update VERSION to match or exceed the release tag."
    exit 1
  fi
}

version_bumped() {
  local current=$1
  local released=$2

  [[ -z "$released" || "$current" != "$released" ]]
}

version_changed_in_range() {
  local before=$1
  local after=$2

  if [[ -z "$before" || -z "$after" ]]; then
    return 1
  fi

  if [[ "$before" =~ ^0+$ ]]; then
    before=$(git hash-object -t tree /dev/null)
  fi

  git diff --name-only "$before" "$after" | grep -qx VERSION
}
