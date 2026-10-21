#!/usr/bin/env bash
#
# release_notes.sh <version> <ref>
#
# Prints a Markdown changelog for the release of <ref>:
#
#   <version>  release version, e.g. 2.0.0 or 2.0.0-beta.1
#   <ref>      commit SHA or branch to release
#
# The previous tag is found with `git describe --tags --abbrev=0 <ref>^`
# (from the parent, so a tag on <ref> itself is never the previous tag):
# a regular release (no -suffix) only considers tags without a -suffix,
# a pre-release considers any tag. If no previous tag is found, the whole
# history up to <ref> is used. Commits are listed with --no-merges,
# subjects starting with `release:` are dropped, and the rest are grouped
# by scope (the text before the first ": "); scope-less subjects go under
# "Other", which is printed last.
#
# Compatible with bash 3.2 (macOS default): no associative arrays.

set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <version> <ref>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

version=$1
ref=$2

# A version with a -suffix is a pre-release: any previous tag is a valid
# base. A regular release must start from the previous regular tag, so
# pre-release tags are excluded.
case $version in
  *-*) prerelease=1 ;;
  *)   prerelease=0 ;;
esac

prev=""
if git rev-parse --verify --quiet "${ref}^" >/dev/null 2>&1; then
  if [ "$prerelease" -eq 1 ]; then
    prev=$(git describe --tags --abbrev=0 "${ref}^" 2>/dev/null || true)
  else
    prev=$(git describe --tags --abbrev=0 --exclude='*-*' "${ref}^" 2>/dev/null || true)
  fi
fi

if [ -n "$prev" ]; then
  range="${prev}..${ref}"
else
  range=$ref
fi

log_output=$(git log --no-merges --format='%h%x1f%s' "$range")

sep=$'\x1f'
scopes=()
hashes=()
rests=()
has_other=0

if [ -n "$log_output" ]; then
  while IFS= read -r line; do
    commit_hash=${line%%"$sep"*}
    subject=${line#*"$sep"}

    case $subject in
      release:*) continue ;;
    esac

    case $subject in
      *": "*)
        scope=${subject%%": "*}
        rest=${subject#*": "}
        ;;
      *)
        scope=Other
        rest=$subject
        has_other=1
        ;;
    esac

    n=${#scopes[@]}
    scopes[$n]=$scope
    hashes[$n]=$commit_hash
    rests[$n]=$rest
  done <<< "$log_output"
fi

count=${#scopes[@]}
[ "$count" -gt 0 ] || exit 0

print_group() {
  local group=$1 i
  printf '### %s\n' "$group"
  i=0
  while [ "$i" -lt "$count" ]; do
    if [ "${scopes[$i]}" = "$group" ]; then
      printf -- '- %s (%s)\n' "${rests[$i]}" "${hashes[$i]}"
    fi
    i=$((i + 1))
  done
  printf '\n'
}

# Print groups in order of first appearance, "Other" always last. The
# seen-list is a separator-delimited string (no associative arrays).
seen=$sep
i=0
while [ "$i" -lt "$count" ]; do
  scope=${scopes[$i]}
  if [ "$scope" != "Other" ]; then
    case $seen in
      *"$sep$scope$sep"*) ;;
      *)
        print_group "$scope"
        seen="${seen}${scope}${sep}"
        ;;
    esac
  fi
  i=$((i + 1))
done

if [ "$has_other" -eq 1 ]; then
  print_group "Other"
fi
