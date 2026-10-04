#!/bin/bash
# Tag a release of main as vX.Y.Z and push that tag. Tag only: no builds, no uploads.
#
#   DRY_RUN=1    skip the terminal check, fetch, Pardon's tests, tag and push; print what would happen
#   CHOICE=1..4  the menu answer in a dry run (1 patch, 2 minor, 3 major, 4 abort)
#   --self-test  check the version arithmetic and tag filtering only
#
# Run from anywhere:  ./scripts/release.sh   (or: make release)
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN="${DRY_RUN:-0}"
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# Highest X.Y.Z among the tag names on stdin; only exact vX.Y.Z counts. 0.0.0 if none.
latest_version() {
  local v
  v="$({ grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
  echo "${v:-0.0.0}"
}

# bump X.Y.Z patch|minor|major
bump() {
  local x y z
  IFS=. read -r x y z <<<"$1"
  x=$((10#$x)) y=$((10#$y)) z=$((10#$z))
  case "$2" in
    patch) echo "$x.$y.$((z + 1))" ;;
    minor) echo "$x.$((y + 1)).0" ;;
    major) echo "$((x + 1)).0.0" ;;
  esac
}

# Menu answer -> bump kind; empty means abort.
choice_kind() {
  case "$1" in
    1) echo patch ;;
    2) echo minor ;;
    3) echo major ;;
  esac
}

self_test() {
  local pass=0 fail=0
  check() {
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL %s: got "%s", want "%s"\n' "$1" "$2" "$3"; fi
  }
  check "no tags -> 0.0.0" "$(printf '' | latest_version)" 0.0.0
  check "junk only -> 0.0.0" "$(printf 'v1\nv1.2.3-rc1\nfoo\nv1.2\n1.2.3\n' | latest_version)" 0.0.0
  check "junk ignored beside real tags" "$(printf 'v0.1.0\nv9.9.9-rc1\nv10\nfoo\nv1.2.3.4\nxv2.0.0\nv3.0.0 \n' | latest_version)" 0.1.0
  check "v0.10.0 sorts above v0.9.0" "$(printf 'v0.9.0\nv0.10.0\nv0.2.0\n' | latest_version)" 0.10.0
  check "v1.10.0 sorts above v1.9.9" "$(printf 'v1.10.0\nv1.9.9\n' | latest_version)" 1.10.0
  check "v1.0.10 sorts above v1.0.9" "$(printf 'v1.0.9\nv1.0.10\n' | latest_version)" 1.0.10
  check "v10.0.0 sorts above v2.0.0" "$(printf 'v2.0.0\nv10.0.0\nv9.99.99\n' | latest_version)" 10.0.0
  check "0.0.0 patch" "$(bump 0.0.0 patch)" 0.0.1
  check "v0.1.0 patch" "$(bump 0.1.0 patch)" 0.1.1
  check "v0.1.0 minor" "$(bump 0.1.0 minor)" 0.2.0
  check "v0.1.0 major" "$(bump 0.1.0 major)" 1.0.0
  check "v1.9.9 patch" "$(bump 1.9.9 patch)" 1.9.10
  check "v1.9.9 minor" "$(bump 1.9.9 minor)" 1.10.0
  check "v1.9.9 major" "$(bump 1.9.9 major)" 2.0.0
  check "v1.08.09 patch (no octal)" "$(bump 1.08.09 patch)" 1.8.10
  check "choice 1" "$(choice_kind 1)" patch
  check "choice 2" "$(choice_kind 2)" minor
  check "choice 3" "$(choice_kind 3)" major
  check "choice 4 aborts" "$(choice_kind 4)" ""
  check "choice junk aborts" "$(choice_kind 12)" ""
  check "choice empty aborts" "$(choice_kind '')" ""
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = --self-test ]; then
  self_test
  exit
fi
[ $# -eq 0 ] || die "usage: scripts/release.sh [--self-test]   (DRY_RUN=1 CHOICE=1..4 for a dry run)"

[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)" ] || die "not inside the claude-code-voice repository"
[ "$DRY_RUN" = 1 ] || [ -t 0 ] || die "needs a terminal to answer the prompts (or DRY_RUN=1)"
branch="$(git symbolic-ref --short -q HEAD || true)"
[ "$branch" = main ] || die "on branch '${branch:-detached HEAD}'; releases are tagged from main"
git diff --quiet && git diff --cached --quiet || die "uncommitted changes; commit or stash them first"

if [ "$DRY_RUN" = 1 ]; then
  warn "dry run: would run git fetch --tags origin; comparing with the origin/main already fetched"
else
  git fetch --tags origin || die "git fetch --tags origin failed; check the network and that origin is reachable (git remote -v)"
fi
[ "$(git rev-parse HEAD)" = "$(git rev-parse -q --verify origin/main || true)" ] \
  || die "HEAD is not origin/main; push (or pull) first"

if [ "$DRY_RUN" = 1 ]; then
  warn "dry run: would run make test-ptt"
else
  make --no-print-directory test-ptt || die "Pardon's tests failed; nothing tagged"
fi

current="$(git tag -l | latest_version)"
echo "Current version: v$current"
echo "  1) patch  -> v$(bump "$current" patch)"
echo "  2) minor  -> v$(bump "$current" minor)"
echo "  3) major  -> v$(bump "$current" major)"
echo "  4) abort"
if [ "$DRY_RUN" = 1 ]; then
  choice="${CHOICE:-4}"
  echo "Choice [1-4]: $choice (from CHOICE)"
else
  read -r -p "Choice [1-4]: " choice || choice=4
fi
kind="$(choice_kind "$choice")"
[ -n "$kind" ] || die "aborted; nothing changed"

tag="v$(bump "$current" "$kind")"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "tag $tag already exists; inspect it with git show $tag. If it was never pushed, git tag -d $tag removes it; if it was pushed, leave it and choose a different bump"
echo "Tag:    $tag"
echo "Commit: $(git log -1 --format='%h %s')"

if [ "$DRY_RUN" = 1 ]; then
  warn "dry run: would ask you to type y, then run:"
  echo "    git tag -a $tag -m \"$tag\""
  echo "    git push origin refs/tags/$tag"
  exit 0
fi
read -r -p "Type y (lowercase, nothing else) to tag and push $tag: " answer || answer=
[ "$answer" = y ] || die "aborted: only a lowercase y confirms; nothing changed"

git tag -a "$tag" -m "$tag"
if ! git push origin "refs/tags/$tag"; then
  warn "the push failed; the tag $tag exists locally only"
  echo "    retry the push:       git push origin refs/tags/$tag"
  echo "    or delete the tag:    git tag -d $tag"
  exit 1
fi

echo "Pushed $tag. Run make ptt so the installed Pardon shows $tag (its version comes from git describe)."
