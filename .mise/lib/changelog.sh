#!/usr/bin/env bash
# Generate release notes from conventional commits between two git refs.

set -euo pipefail

CHANGELOG_TYPES=(
  "breaking:Breaking Changes"
  "feat:Features"
  "fix:Bug Fixes"
  "perf:Performance"
  "refactor:Refactoring"
)

changelog_skip_subject() {
  local subject=$1

  [[ "$subject" =~ ^chore\(release\): ]] ||
    [[ "$subject" =~ ^chore\(release\) ]] ||
    [[ "$subject" =~ ^Merge ]]
}

changelog_parse_subject() {
  local subject=$1

  if changelog_skip_subject "$subject"; then
    return 0
  fi

  [[ "$subject" != *:* ]] && return 0

  local header="${subject%%:*}"
  local description="${subject#*: }"

  [[ "$description" == "$subject" || -z "$description" ]] && return 0

  local type="$header"
  local scope=""
  local breaking=false

  if [[ "$header" == *"("*")"* ]]; then
    type="${header%%(*}"
    scope="${header#*(}"
    scope="${scope%%)*}"

    local suffix="${header#*${scope})}"
    [[ "$suffix" == "!" ]] && breaking=true
  elif [[ "$header" == *"!" ]]; then
    type="${header%!}"
    breaking=true
  fi

  if [[ "$breaking" == true ]]; then
    type="breaking"
  fi

  case "$type" in
    feat|fix|perf|refactor|breaking)
      if [[ -n "$scope" ]]; then
        printf '%s\t**%s:** %s\n' "$type" "$scope" "$description"
      else
        printf '%s\t%s\n' "$type" "$description"
      fi
      ;;
  esac
}

changelog_from_subjects() {
  local version=${1:-}
  local from_ref=${2:-}
  local to_ref=${3:-HEAD}
  local -A section_lines=()

  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue

    while IFS=$'\t' read -r type line; do
      section_lines["$type"]+="- ${line}"$'\n'
    done < <(changelog_parse_subject "$subject")
  done < <(git log "${from_ref}..${to_ref}" --pretty=format:'%s' --no-merges 2>/dev/null || true)

  local printed=false

  for mapping in "${CHANGELOG_TYPES[@]}"; do
    local type=${mapping%%:*}
    local title=${mapping#*:}
    local lines=${section_lines[$type]:-}

    if [[ -n "$lines" ]]; then
      printed=true
      printf '### %s\n' "$title"
      printf '%b' "$lines"
      printf '\n'
    fi
  done

  if [[ "$printed" == false ]]; then
    printf 'No user-facing conventional commits since the previous release.\n\n'
  fi

  local repo=${GITHUB_REPOSITORY:-}
  if [[ -z "$repo" ]] && command -v gh >/dev/null 2>&1; then
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  fi

  if [[ -n "$repo" && -n "$from_ref" && -n "$version" ]]; then
    local to_tag="v${version}"
    printf '**Full Changelog**: https://github.com/%s/compare/%s...%s\n' "$repo" "$from_ref" "$to_tag"
  fi
}

changelog_for_release() {
  local version=$1
  local from_ref=${2:-}

  if [[ -z "$from_ref" ]]; then
    printf '## v%s\n\n' "$version"
    printf 'Initial release.\n'
    return 0
  fi

  printf '## v%s\n\n' "$version"
  changelog_from_subjects "$version" "$from_ref"
}
