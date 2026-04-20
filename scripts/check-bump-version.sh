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

# count_commits is defined in the shared library scripts/lib-count-commits.sh
# so scripts/verify-skill-called.sh (#160) can reuse the exact same base-ref
# resolution and git-error handling. The stderr WARN prefix remains
# `WARN: check-bump-version.sh:` for log parity with operators' existing grep
# patterns; see lib-count-commits.sh's header for rationale.
# shellcheck source=scripts/lib-count-commits.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib-count-commits.sh"

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
