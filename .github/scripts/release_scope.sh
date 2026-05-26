#!/usr/bin/env bash
# Decides whether a push to main is releasable.
#
# GitHub Actions `paths` / `paths-ignore` only gate whole workflows on the
# files in a single push. We need to:
#   1. Diff against the last released tag (not just the previous commit), and
#   2. Expose the result as a job output so docker/release can skip while
#      tests still run.
#
# That logic does not fit in workflow YAML, so it lives here.

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
