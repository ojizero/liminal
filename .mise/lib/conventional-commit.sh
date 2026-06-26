#!/usr/bin/env bash
# Conventional Commits 1.0.0 parsing and validation helpers.
# https://www.conventionalcommits.org/en/v1.0.0/

set -euo pipefail

# Types recommended by the spec (Angular convention).

cc_subject_matches() {
  cc_parse_subject "$1"
}

cc_is_merge_subject() {
  local subject=$1
  [[ "$subject" =~ ^[Mm]erge ]]
}

cc_is_release_subject() {
  local subject=$1
  [[ "$subject" =~ ^chore\\(release\\): ]]
}

cc_should_skip_subject() {
  local subject=$1
  cc_is_merge_subject "$subject" || cc_is_release_subject "$subject"
}

# Parse a conventional commit subject into fields via exported variables:
#   CC_TYPE, CC_SCOPE, CC_BREAKING, CC_DESCRIPTION
# Returns 0 when the subject matches, 1 otherwise.
cc_parse_subject() {
  local subject=$1
  local lower_subject original_prefix prefix scope_part

  CC_TYPE=
  CC_SCOPE=
  CC_BREAKING=false
  CC_DESCRIPTION=

  lower_subject=$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')

  if [[ ! "$lower_subject" =~ :[[:space:]] ]]; then
    return 1
  fi

  CC_DESCRIPTION="${subject#*: }"
  original_prefix="${subject%%: *}"
  prefix="${lower_subject%%: *}"

  if [[ "$prefix" == *! ]]; then
    CC_BREAKING=true
    prefix="${prefix%!}"
    original_prefix="${original_prefix%!}"
  fi

  if [[ "$prefix" == *"("*")" ]]; then
    CC_TYPE="${prefix%%(*}"
    scope_part="${original_prefix#*(}"
    CC_SCOPE="${scope_part%)}"
  else
    CC_TYPE="$prefix"
    CC_SCOPE=
  fi

  case "$CC_TYPE" in
    build | chore | ci | docs | feat | fix | perf | refactor | revert | style | test) ;;
    *) return 1 ;;
  esac

  return 0
}

cc_has_breaking_change_footer() {
  local body=${1:-}
  [[ "$body" =~ (^|[[:space:]])BREAKING[[:space:]]CHANGE: ]]
}

cc_is_breaking_commit() {
  local subject=$1
  local body=${2:-}

  if cc_parse_subject "$subject"; then
    [[ "$CC_BREAKING" == true ]] && return 0
  fi

  cc_has_breaking_change_footer "$body"
}

# Types included in published release notes. Internal-only types are omitted.
cc_include_in_release_notes() {
  local type=$1
  local breaking=${2:-false}

  if [[ "$breaking" == true ]]; then
    return 0
  fi

  case "$type" in
    feat | fix | perf | revert | refactor | docs) return 0 ;;
    *) return 1 ;;
  esac
}

cc_format_release_line() {
  local subject=$1

  if ! cc_parse_subject "$subject"; then
    printf '%s\n' "- $subject"
    return
  fi

  if [[ -n "$CC_SCOPE" ]]; then
    printf '%s\n' "- **${CC_SCOPE}**: ${CC_DESCRIPTION}"
  else
    printf '%s\n' "- ${CC_DESCRIPTION}"
  fi
}

cc_section_heading() {
  local type=$1

  case "$type" in
    breaking) printf '%s\n' '### ⚠️ Breaking Changes' ;;
    feat) printf '%s\n' '### ✨ Features' ;;
    fix) printf '%s\n' '### 🐛 Bug Fixes' ;;
    perf) printf '%s\n' '### ⚡ Performance' ;;
    revert) printf '%s\n' '### ⏪ Reverts' ;;
    refactor) printf '%s\n' '### ♻️ Refactoring' ;;
    docs) printf '%s\n' '### 📝 Documentation' ;;
    other) printf '%s\n' '### Other Changes' ;;
    *) printf '%s\n' "### ${type}" ;;
  esac
}

cc_verify_subjects() {
  local from_ref=$1
  local to_ref=${2:-HEAD}
  local failures=0
  local subject

  while IFS= read -r subject; do
    if cc_should_skip_subject "$subject"; then
      continue
    fi

    if ! cc_subject_matches "$subject"; then
      echo "::error::Commit is not a Conventional Commit: $subject" >&2
      failures=$((failures + 1))
    fi
  done < <(git -C "${CC_GIT_ROOT:-.}" log "${from_ref}..${to_ref}" --format='%s' --no-merges)

  if [[ "$failures" -gt 0 ]]; then
    echo "::error::Found $failures non-conventional commit(s) between ${from_ref}..${to_ref}." >&2
    return 1
  fi

  return 0
}
