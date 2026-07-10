#!/usr/bin/env bash
# Generate release notes from Conventional Commits between two git refs.

set -euo pipefail

# shellcheck source=release-scope.sh
source "${MISE_PROJECT_ROOT}/.mise/lib/release-scope.sh"
# shellcheck source=conventional-commit.sh
source "${MISE_PROJECT_ROOT}/.mise/lib/conventional-commit.sh"

changelog_previous_tag() {
  local version=$1
  local tag ver

  while IFS= read -r tag; do
    ver="${tag#v}"
    if version_lt "$ver" "$version"; then
      printf '%s\n' "$tag"
      return 0
    fi
  done < <(git tag -l 'v*' --sort=-v:refname)

  return 0
}

changelog_collect_commits() {
  local from_ref=$1
  local to_ref=${2:-HEAD}
  local range

  if [[ -z "$from_ref" ]]; then
    range="$to_ref"
  else
    range="${from_ref}..${to_ref}"
  fi

  git log "$range" --format='%s%n%b%n----' --no-merges
}

changelog_generate() {
  local from_ref=$1
  local to_ref=${2:-HEAD}
  local version=${3:-}

  local -a breaking_lines=()
  local -a feat_lines=()
  local -a fix_lines=()
  local -a perf_lines=()
  local -a revert_lines=()
  local -a refactor_lines=()
  local -a docs_lines=()
  local -a build_lines=()
  local -a chore_lines=()
  local -a ci_lines=()
  local -a style_lines=()
  local -a test_lines=()
  local -a other_lines=()

  local subject body line
  subject=
  body=

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "----" ]]; then
      if [[ -n "$subject" ]] && ! cc_should_skip_subject "$subject"; then
        if cc_parse_subject "$subject"; then
          breaking=false
          if cc_is_breaking_commit "$subject" "$body"; then
            breaking=true
            breaking_lines+=("$(cc_format_release_line "$subject")")
          elif cc_include_in_release_notes "$CC_TYPE" false; then
            case "$CC_TYPE" in
              feat) feat_lines+=("$(cc_format_release_line "$subject")") ;;
              fix) fix_lines+=("$(cc_format_release_line "$subject")") ;;
              perf) perf_lines+=("$(cc_format_release_line "$subject")") ;;
              revert) revert_lines+=("$(cc_format_release_line "$subject")") ;;
              refactor) refactor_lines+=("$(cc_format_release_line "$subject")") ;;
              docs) docs_lines+=("$(cc_format_release_line "$subject")") ;;
              build) build_lines+=("$(cc_format_release_line "$subject")") ;;
              chore) chore_lines+=("$(cc_format_release_line "$subject")") ;;
              ci) ci_lines+=("$(cc_format_release_line "$subject")") ;;
              style) style_lines+=("$(cc_format_release_line "$subject")") ;;
              test) test_lines+=("$(cc_format_release_line "$subject")") ;;
            esac
          fi
        else
          other_lines+=("$(cc_format_release_line "$subject")")
        fi
      fi

      subject=
      body=
      continue
    fi

    if [[ -z "$subject" ]]; then
      subject=$line
      continue
    fi

    if [[ -z "$body" ]]; then
      body=$line
    elif [[ -n "$line" ]]; then
      body+=$'\n'"$line"
    fi
  done < <(changelog_collect_commits "$from_ref" "$to_ref")

  if [[ -n "$version" ]]; then
    printf '## v%s\n\n' "$version"
  fi

  changelog_print_section breaking ${breaking_lines[@]+"${breaking_lines[@]}"}
  changelog_print_section feat ${feat_lines[@]+"${feat_lines[@]}"}
  changelog_print_section fix ${fix_lines[@]+"${fix_lines[@]}"}
  changelog_print_section perf ${perf_lines[@]+"${perf_lines[@]}"}
  changelog_print_section revert ${revert_lines[@]+"${revert_lines[@]}"}
  changelog_print_section refactor ${refactor_lines[@]+"${refactor_lines[@]}"}
  changelog_print_section docs ${docs_lines[@]+"${docs_lines[@]}"}
  changelog_print_section build ${build_lines[@]+"${build_lines[@]}"}
  changelog_print_section chore ${chore_lines[@]+"${chore_lines[@]}"}
  changelog_print_section ci ${ci_lines[@]+"${ci_lines[@]}"}
  changelog_print_section style ${style_lines[@]+"${style_lines[@]}"}
  changelog_print_section test ${test_lines[@]+"${test_lines[@]}"}
  changelog_print_section other ${other_lines[@]+"${other_lines[@]}"}
}

changelog_print_section() {
  local type=$1
  shift

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  cc_section_heading "$type"
  printf '%s\n' "$@"
  printf '\n'
}

changelog_for_version() {
  local version=$1
  local to_ref=${2:-HEAD}
  local previous_tag

  previous_tag=$(changelog_previous_tag "$version")
  changelog_generate "$previous_tag" "$to_ref" "$version"
}
