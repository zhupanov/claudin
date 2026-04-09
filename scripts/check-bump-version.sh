#!/usr/bin/env bash
# check-bump-version.sh — Check for /bump-version skill and verify commit count.
#
# Usage:
#   check-bump-version.sh --mode pre    # Check if skill exists, count commits before
#   check-bump-version.sh --mode post --before-count <N>  # Verify one new commit was added
#
# Output (stdout, KEY=VALUE):
#   --mode pre:
#     HAS_BUMP=true|false
#     COMMITS_BEFORE=<N>
#   --mode post:
#     VERIFIED=true|false
#     COMMITS_AFTER=<N>
#     EXPECTED=<N>
#
# Commit counting uses local `main` if it exists, falling back to `origin/main`
# if only the remote ref is present. This matches classify-bump.sh's base
# resolution and ensures the /implement Rebase + Re-bump Sub-procedure's post-
# verification check works correctly even when the repo has no local `main`
# ref (e.g., some CI clones). Without the fallback, `git rev-list main..HEAD`
# silently returns 0 and the post-check produces a false VERIFIED=false.
#
# Exit codes: 0 success, 1 invalid args

set -euo pipefail

# count_commits — Count commits on the current branch that aren't on main.
# Prefers local `main`; falls back to `origin/main` if local is absent.
# Prints "0" on any git error to preserve the caller's key=value contract.
# When neither `main` nor `origin/main` exists (a degenerate repo state that
# normally cannot occur mid-/implement because `rebase-push.sh` would have
# already failed on the missing `origin/main` fetch), emits a stderr WARN
# so the caller can see the edge case in execution logs, and still returns
# "0" to preserve the KEY=VALUE stdout contract. The downstream VERIFIED
# check will then report false and /implement's Step 12 will bail — which
# is the correct outcome when the bump base cannot be determined.
count_commits() {
  local base_ref=""
  if git rev-parse --verify main >/dev/null 2>&1; then
    base_ref="main"
  elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    base_ref="origin/main"
  fi
  if [[ -z "$base_ref" ]]; then
    echo "WARN: check-bump-version.sh: neither local 'main' nor 'origin/main' exists; cannot determine bump base. Returning 0." >&2
    echo "0"
    return
  fi
  git rev-list "${base_ref}..HEAD" --count 2>/dev/null || echo "0"
}

MODE=""
BEFORE_COUNT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)         MODE="$2"; shift 2 ;;
    --before-count) BEFORE_COUNT="$2"; shift 2 ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "ERROR=Missing required argument: --mode" >&2
  exit 1
fi

case "$MODE" in
  pre)
    if [[ -f "$PWD/.claude/skills/bump-version/SKILL.md" ]]; then
      echo "HAS_BUMP=true"
    else
      echo "HAS_BUMP=false"
    fi
    echo "COMMITS_BEFORE=$(count_commits)"
    ;;
  post)
    if [[ -z "$BEFORE_COUNT" ]]; then
      echo "ERROR=--before-count required for --mode post" >&2
      exit 1
    fi
    COMMITS_AFTER=$(count_commits)
    EXPECTED=$((BEFORE_COUNT + 1))
    if [[ "$COMMITS_AFTER" -eq "$EXPECTED" ]]; then
      echo "VERIFIED=true"
    else
      echo "VERIFIED=false"
    fi
    echo "COMMITS_AFTER=$COMMITS_AFTER"
    echo "EXPECTED=$EXPECTED"
    ;;
  *)
    echo "ERROR=Invalid mode: $MODE (expected pre or post)" >&2
    exit 1
    ;;
esac
