#!/usr/bin/env bash
set -euo pipefail

# Paths that do not require a version bump or release when they are the only changes.
NON_RELEASABLE_PREFIXES=(
  ".github/"
  "test/"
  ".agents/"
  ".claude/"
)

NON_RELEASABLE_FILES=(
  "README.md"
  "AGENTS.md"
  "CLAUDE.md"
  ".gitignore"
  ".dockerignore"
)

is_non_releasable() {
  local file=$1

  for prefix in "${NON_RELEASABLE_PREFIXES[@]}"; do
    if [[ "$file" == "$prefix"* ]]; then
      return 0
    fi
  done

  for exact in "${NON_RELEASABLE_FILES[@]}"; do
    if [[ "$file" == "$exact" ]]; then
      return 0
    fi
  done

  if [[ "$file" == LICENSE* ]]; then
    return 0
  fi

  return 1
}

git_diff_range() {
  local latest_tag=${1:-}

  if [[ -n "$latest_tag" ]]; then
    echo "${latest_tag}..HEAD"
  else
    echo "$(git hash-object -t tree /dev/null)..HEAD"
  fi
}

has_releasable_changes() {
  local range=$1
  local file

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    if ! is_non_releasable "$file"; then
      return 0
    fi
  done < <(git diff --name-only "$range")

  return 1
}

current_version() {
  grep 'version:' mix.exs | head -1 | sed 's/.*"\(.*\)".*/\1/'
}
