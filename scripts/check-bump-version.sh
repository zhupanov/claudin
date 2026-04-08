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
# Exit codes: 0 success, 1 invalid args

set -euo pipefail

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
    COMMITS=$(git rev-list main..HEAD --count 2>/dev/null || echo "0")
    echo "COMMITS_BEFORE=$COMMITS"
    ;;
  post)
    if [[ -z "$BEFORE_COUNT" ]]; then
      echo "ERROR=--before-count required for --mode post" >&2
      exit 1
    fi
    COMMITS_AFTER=$(git rev-list main..HEAD --count 2>/dev/null || echo "0")
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
