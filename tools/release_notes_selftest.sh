#!/usr/bin/env bash
#
# release_notes_selftest.sh
#
# Self-test for tools/release_notes.sh. Builds throwaway git repositories
# in a mktemp -d directory (removed on exit via trap) and asserts on the
# generated Markdown:
#
#   1. grouping by scope: `### net` with two bullets, `### ui` with one
#   2. scope-less subjects under `### Other`, printed after the scoped groups
#   3. `release:` subjects never appear
#   4. beta-to-beta range: 2.0.0-beta.2 lists only commits after beta.1
#   5. stable after betas: 2.0.0 lists everything since v1.2.0, betas included
#   6. mixed v/non-v tags: ancestry still finds the right previous tag
#   7. whole-history fallback: a repo with no tags lists all non-release commits
#
# Usage:
#   bash tools/release_notes_selftest.sh
#       runs every check, prints PASS/FAIL per check, exits 0 iff all pass
#   FORCE_FAIL=1 bash tools/release_notes_selftest.sh
#       inverts the first check, to prove the harness exits non-zero when
#       an assertion is broken
#
# Compatible with bash 3.2 (macOS default): no associative arrays, no
# bash-4-isms.

set -euo pipefail

command -v git >/dev/null 2>&1 || { echo "selftest: git is required" >&2; exit 1; }

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SELF_DIR/release_notes.sh"
[ -f "$SCRIPT" ] || { echo "selftest: $SCRIPT not found" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
CHECK_COUNT=0
FORCE_FAIL=${FORCE_FAIL:-0}

# --------------------------------------------------------------- harness

# check <ok:0|1> <label> [detail]
# Records and prints one check. With FORCE_FAIL=1 the first check is
# inverted, so the self-test can be made to fail on purpose.
check() {
  CHECK_COUNT=$((CHECK_COUNT + 1))
  local ok=$1 label=$2 detail=""
  shift 2
  if [ "$#" -gt 0 ]; then
    detail=$*
  fi
  if [ "$FORCE_FAIL" = "1" ] && [ "$CHECK_COUNT" -eq 1 ]; then
    ok=$((1 - ok))
    detail="FORCE_FAIL=1 inverted this check"
  fi
  if [ "$ok" -eq 1 ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS  %s\n' "$label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL  %s\n' "$label"
    if [ -n "$detail" ]; then
      printf '      %s\n' "$detail"
    fi
  fi
}

assert_contains() {
  local label=$1 hay=$2 needle=$3
  case $hay in
    *"$needle"*) check 1 "$label" ;;
    *) check 0 "$label" "expected to find: $needle" ;;
  esac
}

assert_not_contains() {
  local label=$1 hay=$2 needle=$3
  case $hay in
    *"$needle"*) check 0 "$label" "should not contain: $needle" ;;
    *) check 1 "$label" ;;
  esac
}

# line_of <haystack> <needle>: 1-based line number of the first line
# containing <needle>, or 0 if absent.
line_of() {
  local hay=$1 needle=$2 line no=0
  while IFS= read -r line; do
    no=$((no + 1))
    case $line in
      *"$needle"*) printf '%s\n' "$no"; return 0 ;;
    esac
  done <<< "$hay"
  printf '0\n'
}

# assert_order <label> <haystack> <a> <b>: <a> appears, <b> appears, and
# the first <a> line comes before the first <b> line.
assert_order() {
  local label=$1 hay=$2 a=$3 b=$4 la lb
  la=$(line_of "$hay" "$a")
  lb=$(line_of "$hay" "$b")
  if [ "$la" -gt 0 ] && [ "$lb" -gt 0 ] && [ "$la" -lt "$lb" ]; then
    check 1 "$label"
  else
    check 0 "$label" "expected '$a' (line $la) before '$b' (line $lb)"
  fi
}

# group_bullets <haystack> <group>: number of bullet lines under
# `### <group>` (up to the next `### ` heading).
group_bullets() {
  local hay=$1 group=$2 in=0 n=0 line
  while IFS= read -r line; do
    case $line in
      "### $group") in=1; continue ;;
      "### "*) in=0 ;;
    esac
    if [ "$in" -eq 1 ]; then
      case $line in
        "- "*) n=$((n + 1)) ;;
      esac
    fi
  done <<< "$hay"
  printf '%s\n' "$n"
}

assert_group_size() {
  local label=$1 hay=$2 group=$3 expected=$4 actual
  actual=$(group_bullets "$hay" "$group")
  if [ "$actual" = "$expected" ]; then
    check 1 "$label"
  else
    check 0 "$label" "expected $expected bullet(s) in '### $group', got $actual"
  fi
}

# -------------------------------------------------------------- fixtures

new_repo() {
  local dir=$1
  git init -q "$dir" 2>/dev/null || { echo "selftest: git init failed for $dir" >&2; exit 1; }
  git -C "$dir" config user.name "Release Notes Self Test"
  git -C "$dir" config user.email "selftest@example.invalid"
  git -C "$dir" config commit.gpgsign false
}

commit() {
  git -C "$1" commit -q --allow-empty -m "$2"
}

# Run release_notes.sh from inside <repo>: bash <abs path> <version> <ref>.
run_notes() {
  (cd "$1" && bash "$SCRIPT" "$2" "$3")
}

# Main throwaway repo: mixed v/non-v tags, beta tags, scoped and
# scope-less subjects, and a release: commit.
#
#   C0 docs: 📖 initial readme        tag 1.1.0   (no v prefix)
#   C1 net: ✨ add a                  tag v1.2.0
#   C2 net: 🐛 fix b
#   C3 ui: 💄 tweak c
#   C4 release: 🔖 bump version       tag v2.0.0-beta.1
#   C5 net: 🐛 fix d
#   C6 plain subject                  tag v2.0.0-beta.2
#   C7 ui: ✨ add e                   (HEAD)
REPO="$WORK/main"
new_repo "$REPO"

commit "$REPO" "docs: 📖 initial readme"
git -C "$REPO" tag 1.1.0

commit "$REPO" "net: ✨ add a"
C1=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" tag v1.2.0

commit "$REPO" "net: 🐛 fix b"
commit "$REPO" "ui: 💄 tweak c"

commit "$REPO" "release: 🔖 bump version"
C4=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" tag v2.0.0-beta.1

commit "$REPO" "net: 🐛 fix d"

commit "$REPO" "plain subject"
C6=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" tag v2.0.0-beta.2

commit "$REPO" "ui: ✨ add e"
C7=$(git -C "$REPO" rev-parse HEAD)

# ------------------------------------------------- run A: 2.0.0-beta.1

printf '\n== 2.0.0-beta.1 at the v2.0.0-beta.1 commit (prerelease) ==\n'
OUT_A=$(run_notes "$REPO" "2.0.0-beta.1" "$C4") || {
  echo "selftest: release_notes.sh failed for 2.0.0-beta.1" >&2
  exit 1
}
printf '%s\n' "$OUT_A"

assert_contains     "beta1: lists 'ui: 💄 tweak c'"        "$OUT_A" "💄 tweak c"
assert_contains     "beta1: lists 'net: 🐛 fix b'"        "$OUT_A" "🐛 fix b"
assert_not_contains "beta1: excludes release: commit"     "$OUT_A" "bump version"
assert_not_contains "beta1: excludes the v1.2.0 commit"   "$OUT_A" "✨ add a"
assert_not_contains "beta1: not whole-history fallback"   "$OUT_A" "initial readme"

# ------------------------------------------------- run B: 2.0.0-beta.2

printf '\n== 2.0.0-beta.2 at the v2.0.0-beta.2 commit (prerelease) ==\n'
OUT_B=$(run_notes "$REPO" "2.0.0-beta.2" "$C6") || {
  echo "selftest: release_notes.sh failed for 2.0.0-beta.2" >&2
  exit 1
}
printf '%s\n' "$OUT_B"

assert_contains     "beta2: lists commits after beta.1 (fix d)"       "$OUT_B" "🐛 fix d"
assert_contains     "beta2: lists commits after beta.1 (plain)"       "$OUT_B" "plain subject"
assert_not_contains "beta2: excludes commits before beta.1 (add a)"   "$OUT_B" "✨ add a"
assert_not_contains "beta2: excludes commits before beta.1 (fix b)"   "$OUT_B" "🐛 fix b"
assert_not_contains "beta2: excludes commits before beta.1 (tweak c)" "$OUT_B" "💄 tweak c"
assert_not_contains "beta2: excludes release: commit"                 "$OUT_B" "bump version"
assert_order        "beta2: Other printed after scoped groups"        "$OUT_B" "### net" "### Other"

# --------------------------------------------------- run C: 2.0.0 stable

printf '\n== 2.0.0 at the latest commit (regular release) ==\n'
OUT_C=$(run_notes "$REPO" "2.0.0" "$C7") || {
  echo "selftest: release_notes.sh failed for 2.0.0" >&2
  exit 1
}
printf '%s\n' "$OUT_C"

assert_contains     "stable: lists everything since v1.2.0 (fix b)"    "$OUT_C" "🐛 fix b"
assert_contains     "stable: lists everything since v1.2.0 (tweak c)"  "$OUT_C" "💄 tweak c"
assert_contains     "stable: lists beta-era commits (fix d)"           "$OUT_C" "🐛 fix d"
assert_contains     "stable: lists beta-era commits (plain subject)"   "$OUT_C" "plain subject"
assert_contains     "stable: lists commits after the betas (add e)"    "$OUT_C" "✨ add e"
assert_not_contains "stable: excludes release: commit"                 "$OUT_C" "bump version"
assert_not_contains "stable: base is v1.2.0, not 1.1.0 (no add a)"     "$OUT_C" "✨ add a"
assert_not_contains "stable: not whole-history fallback"               "$OUT_C" "initial readme"
assert_order        "stable: Other printed after scoped groups"        "$OUT_C" "### ui" "### Other"
assert_group_size   "stable: '### net' has 2 bullets"                  "$OUT_C" "net" 2
assert_group_size   "stable: '### ui' has 2 bullets"                   "$OUT_C" "ui" 2

# ------------------------------------- run D: 1.2.0, previous tag 1.1.0

printf '\n== 1.2.0 at the v1.2.0 commit (previous tag is non-v 1.1.0) ==\n'
OUT_D=$(run_notes "$REPO" "1.2.0" "$C1") || {
  echo "selftest: release_notes.sh failed for 1.2.0" >&2
  exit 1
}
printf '%s\n' "$OUT_D"

assert_contains     "mixed tags: non-v tag 1.1.0 found as previous tag" "$OUT_D" "✨ add a"
assert_not_contains "mixed tags: base is 1.1.0, not whole history"      "$OUT_D" "initial readme"

# ------------------------------------- run F: fresh repo, no tags

FRESH="$WORK/fresh"
new_repo "$FRESH"
commit "$FRESH" "net: ✨ add a"
commit "$FRESH" "net: 🐛 fix b"
commit "$FRESH" "ui: 💄 tweak c"
commit "$FRESH" "release: 🔖 bump version"
commit "$FRESH" "plain subject"
F_HEAD=$(git -C "$FRESH" rev-parse HEAD)

printf '\n== 1.0.0 in a repo with no tags (whole-history fallback) ==\n'
OUT_F=$(run_notes "$FRESH" "1.0.0" "$F_HEAD") || {
  echo "selftest: release_notes.sh failed for 1.0.0 (no tags)" >&2
  exit 1
}
printf '%s\n' "$OUT_F"

assert_group_size   "no-tag: '### net' has 2 bullets"     "$OUT_F" "net" 2
assert_group_size   "no-tag: '### ui' has 1 bullet"      "$OUT_F" "ui" 1
assert_group_size   "no-tag: '### Other' has 1 bullet"   "$OUT_F" "Other" 1
assert_contains     "no-tag: lists all non-release commits (add a)"         "$OUT_F" "✨ add a"
assert_contains     "no-tag: lists all non-release commits (fix b)"         "$OUT_F" "🐛 fix b"
assert_contains     "no-tag: lists all non-release commits (tweak c)"       "$OUT_F" "💄 tweak c"
assert_contains     "no-tag: lists all non-release commits (plain subject)" "$OUT_F" "plain subject"
assert_not_contains "no-tag: excludes release: commit"    "$OUT_F" "bump version"
assert_order        "no-tag: Other printed after scoped groups" "$OUT_F" "### net" "### Other"

# ------------------------------------------------------------- summary

TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf '\n%d checks: %d passed, %d failed\n' "$TOTAL" "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi
printf '\n%d checks: all passed\n' "$TOTAL"
