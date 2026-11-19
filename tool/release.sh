#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dry_run=false
if [[ "${1:-}" == --dry-run ]]; then
  dry_run=true
  shift
fi

case "${1:-}" in
  -h|--help)
    printf 'Usage: %s [--dry-run] [X.Y.Z]\n' "$0"
    printf 'Without a version, push a release tag using pubspec.yaml.\n'
    printf 'With a version, update pubspec.yaml, increment the build number, and push the release commit and tag.\n'
    exit 0
    ;;
  ''|--version) ;;
  -*) printf 'Error: unknown option: %s\n' "$1" >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then
  printf 'Error: expected at most one option.\n' >&2
  exit 1
fi

version=$(awk '/^version:[[:space:]]/ { print $2 }' pubspec.yaml)
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+[1-9][0-9]*$ ]]; then
  printf 'Error: expected version X.Y.Z+BUILD in pubspec.yaml, with a positive build number.\n' >&2
  exit 1
fi

if [[ "${1:-}" == --version ]]; then
  printf '%s\n' "$version"
  exit 0
fi

current_version=$version
requested_name=${1:-}
if [[ -n "$requested_name" ]]; then
  if [[ ! "$requested_name" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf 'Error: expected a release version in X.Y.Z format.\n' >&2
    exit 1
  fi
  if [[ "$requested_name" != "${current_version%+*}" ]]; then
    build_number=${current_version##*+}
    if [[ ${#build_number} -gt 10 ]] || (( build_number >= 2100000000 )); then
      printf 'Error: cannot increment the build number within the Android versionCode limit.\n' >&2
      exit 1
    fi
    version="$requested_name+$((build_number + 1))"
  fi
fi

tag="v${version%+*}"
ref="refs/tags/$tag"
if [[ "$dry_run" == true ]]; then
  if [[ "$version" != "$current_version" ]]; then
    printf 'Would update pubspec.yaml from %s to %s and commit it.\n' "$current_version" "$version"
  fi
  if [[ -n "$requested_name" ]]; then
    printf 'Would push the current branch and %s to origin (version %s).\n' "$tag" "$version"
  else
    printf 'Would tag HEAD as %s and push to origin (version %s).\n' "$tag" "$version"
  fi
  exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Error: commit your changes before releasing.\n' >&2
  exit 1
fi

branch_ref=''
if [[ -n "$requested_name" ]]; then
  if ! branch_ref=$(git symbolic-ref --quiet HEAD); then
    printf 'Error: switch to the release branch before updating the version.\n' >&2
    exit 1
  fi
fi

if git ls-remote --exit-code --refs origin "$ref" >/dev/null; then
  printf 'Error: %s already exists on origin. To retry a failed build, rerun it in GitHub Actions.\n' "$tag" >&2
  exit 1
elif [[ $? -ne 2 ]]; then
  printf 'Error: could not check release tags on origin.\n' >&2
  exit 1
fi

# Reuse a local tag left behind by a failed push, but never move it.
if git show-ref --verify --quiet "$ref"; then
  if [[ "$version" != "$current_version" || "$(git rev-parse "$ref^{commit}")" != "$(git rev-parse HEAD)" ]]; then
    printf 'Error: local tag %s already exists for a different release commit.\n' "$tag" >&2
    exit 1
  fi
else
  if [[ "$version" != "$current_version" ]]; then
    updated_pubspec=$(awk -v version="$version" '
      /^version:[[:space:]]/ { sub(/^version:[[:space:]]+[^[:space:]]+/, "version: " version) }
      { print }
    ' pubspec.yaml)
    printf '%s\n' "$updated_pubspec" > pubspec.yaml
    git commit -m "chore: release $tag" -- pubspec.yaml
  fi
  git tag -a "$tag" -m "Sakuga $version"
fi

if [[ -n "$branch_ref" ]]; then
  git push --atomic origin "$branch_ref:$branch_ref" "$ref"
else
  git push origin "$ref"
fi
printf 'Pushed %s. GitHub Actions will build and publish the release.\n' "$tag"
