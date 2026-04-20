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
#     STATUS=ok|missing_main_ref|git_error
#   --mode post:
#     VERIFIED=true|false
#     COMMITS_AFTER=<N>
#     EXPECTED=<N>
#     STATUS=ok|missing_main_ref|git_error
#
# STATUS contract (#172):
#   - `ok`                — count is trustworthy (local `main` or `origin/main`
#                           resolved and `git rev-list` succeeded).
#   - `missing_main_ref`  — neither local `main` nor `origin/main` exists;
#                           count is forced to 0, caller MUST treat counts as
#                           untrustworthy.
#   - `git_error`         — a base ref was found but `git rev-list` failed
#                           (corrupted pack, shallow-clone object boundary,
#                           permission error, etc.); count is forced to 0,
#                           caller MUST treat counts as untrustworthy. Also
#                           the fail-closed normalization target: any unknown
#                           or empty token received from the side channel is
#                           normalized to `git_error` (mirrors
#                           verify-skill-called.sh's default branch that
#                           maps unknown to REASON=git_error).
#
#   In `--mode post`, VERIFIED=true ONLY when STATUS=ok AND the numeric
#   commit-delta matches. Any non-`ok` STATUS forces VERIFIED=false,
#   independent of the numeric comparison — the fix for #172's silent-zero
#   false-pass case.
#
# Commit counting uses local `main` if it exists, falling back to `origin/main`
# if only the remote ref is present. This matches classify-bump.sh's base
# resolution and ensures the /implement Rebase + Re-bump Sub-procedure's post-
# verification check works correctly even when the repo has no local `main`
# ref (e.g., some CI clones). Without the fallback, `git rev-list main..HEAD`
# silently returns 0 and the post-check produces a false VERIFIED=false.
#
# Exit codes: 0 success (check STATUS and VERIFIED on stdout),
#             1 invalid args

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

# count_commits_with_status — run count_commits with the status side channel
# enabled, then normalize the token to the stable enum
# {ok, missing_main_ref, git_error}. Any unknown/empty token is normalized
# to `git_error` (fail-closed default, mirrors verify-skill-called.sh:255-260).
#
# Uses a mktemp'd status file and a trap to guarantee cleanup — same pattern
# as verify-skill-called.sh:235-238. A file-based side channel is required
# because bash's $(count_commits) command substitution creates a subshell,
# so any variable the subshell writes would be lost (globals / exported vars
# alike); a temp file survives the subshell boundary.
#
# Prints "<count> <status>" to stdout on a single line; callers split via
# `read`. The status enum contains no whitespace, so word-splitting is safe.
count_commits_with_status() {
    local status_file status count
    status_file=$(mktemp "${TMPDIR:-/tmp}/check-bump-version-status.XXXXXX")
    # shellcheck disable=SC2064  # status_file expansion is intentional at trap-registration time
    trap "rm -f '$status_file'" RETURN
    count=$(COUNT_COMMITS_STATUS_FILE="$status_file" count_commits)
    status=$(cat "$status_file" 2>/dev/null || echo "")
    case "$status" in
        ok|missing_main_ref|git_error)
            ;;
        *)
            # Defensive: any unknown or empty token means the lib changed
            # contract without our knowledge, or the status file write
            # silently failed. Fail closed by normalizing to git_error —
            # matches verify-skill-called.sh:255-260's default branch.
            status="git_error"
            ;;
    esac
    printf '%s %s\n' "$count" "$status"
}

case "$MODE" in
  pre)
    if [[ -f "$PWD/.claude/skills/bump-version/SKILL.md" ]]; then
      echo "HAS_BUMP=true"
    else
      echo "HAS_BUMP=false"
    fi
    read -r pre_count pre_status < <(count_commits_with_status)
    echo "COMMITS_BEFORE=$pre_count"
    echo "STATUS=$pre_status"
    ;;
  post)
    if [[ -z "$BEFORE_COUNT" ]]; then
      echo "ERROR=--before-count required for --mode post" >&2
      exit 1
    fi
    read -r post_count post_status < <(count_commits_with_status)
    EXPECTED=$((BEFORE_COUNT + 1))
    # VERIFIED=true ONLY when STATUS=ok AND the numeric delta matches.
    # Any non-ok status forces VERIFIED=false independent of the count —
    # the fail-closed invariant that prevents the #172 silent-zero
    # false-pass (where a git_error on both pre and post would coerce
    # counts to 0 and numerically "match" EXPECTED=0).
    if [[ "$post_status" == "ok" && "$post_count" -eq "$EXPECTED" ]]; then
      echo "VERIFIED=true"
    else
      echo "VERIFIED=false"
    fi
    echo "COMMITS_AFTER=$post_count"
    echo "EXPECTED=$EXPECTED"
    echo "STATUS=$post_status"
    ;;
  *)
    echo "ERROR=Invalid mode: $MODE (expected pre or post)" >&2
    exit 1
    ;;
esac
