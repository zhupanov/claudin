#!/usr/bin/env bash
# merge-pr.sh — Squash-merge a PR with --admin fallback.
#
# Attempts a squash merge. On failure, checks if the branch is behind
# main or if CI is not ready. If CI is confirmed passing and the branch
# is up-to-date, retries with --admin to override review requirements.
#
# CRITICAL: The --admin flag overrides ALL branch protection rules
# including review requirements. It is ONLY used after confirming:
#   1. All CI checks are passing (bucket == "pass" for every check)
#   2. The branch is up-to-date with main (mergeStateStatus != "BEHIND")
# Keep in sync with the same --admin fallback in:
#   - /admin-upgrade-clients Sub-Step 7
#   - /admin-add-user Step 10
#
# Usage:
#   merge-pr.sh --pr NUMBER --repo OWNER/REPO
#
# Outputs (key=value to stdout, always emitted via EXIT trap):
#   MERGE_RESULT=merged|admin_merged|main_advanced|ci_not_ready|admin_failed|error
#   ERROR=<message>    (empty string when no error)
#
# Exit codes:
#   0 — always (result communicated via MERGE_RESULT)
#   1 — usage/argument error (no output emitted)

set -uo pipefail

usage() { echo "Usage: merge-pr.sh --pr NUMBER --repo OWNER/REPO" >&2; }

# --- Parse arguments (before installing EXIT trap) ---
PR_NUMBER=""
REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR_NUMBER="${2:?--pr requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$PR_NUMBER" ]] || [[ -z "$REPO" ]]; then
    echo "ERROR: --pr and --repo are required" >&2
    usage; exit 1
fi

# --- Output defaults (emitted via trap on any exit after validation) ---
MERGE_RESULT="error"
ERROR="merge-pr.sh exited unexpectedly"

# shellcheck disable=SC2329,SC2317  # invoked via EXIT trap
emit_output() {
    echo "MERGE_RESULT=$MERGE_RESULT"
    echo "ERROR=$ERROR"
}
trap 'emit_output' EXIT

# --- Attempt squash merge ---
MERGE_OUTPUT=$(gh pr merge "$PR_NUMBER" --repo "$REPO" --squash 2>&1)
MERGE_EXIT=$?

if [[ $MERGE_EXIT -eq 0 ]]; then
    MERGE_RESULT="merged"
    ERROR=""
    exit 0
fi

# --- Merge failed — check why ---
echo "ℹ Merge attempt failed: $MERGE_OUTPUT" >&2

# Check if branch is behind main
MERGE_STATE=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json mergeStateStatus -q '.mergeStateStatus' 2>/dev/null || echo "")

if [[ "$MERGE_STATE" == "BEHIND" ]]; then
    MERGE_RESULT="main_advanced"
    ERROR=""
    exit 0
fi

# --- Re-verify CI before attempting --admin ---
# Use gh pr checks --json with bucket field (consistent with ci-status.sh)
CHECKS_JSON=$(gh pr checks "$PR_NUMBER" --repo "$REPO" --json name,state,bucket,link 2>/dev/null || echo "")

CI_GOOD=false
if [[ -n "$CHECKS_JSON" ]] && [[ "$CHECKS_JSON" != "null" ]] \
    && echo "$CHECKS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
    TOTAL=$(echo "$CHECKS_JSON" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$TOTAL" -eq 0 ]]; then
        # Zero checks — conservative: treat as not ready
        CI_GOOD=false
    else
        # Require every check to have bucket == "pass" (not just absence of fail/pending).
        # This rejects cancelled, skipping, or any other non-pass bucket.
        PASSED=$(echo "$CHECKS_JSON" | jq '[.[] | select(.bucket == "pass")] | length' 2>/dev/null || echo "0")

        if [[ "$PASSED" -eq "$TOTAL" ]]; then
            CI_GOOD=true
        fi
    fi
else
    # Fallback: parse text output — conservative: only accept if all lines show pass
    CHECKS_TEXT=$(gh pr checks "$PR_NUMBER" --repo "$REPO" 2>/dev/null || echo "")
    if [[ -n "$CHECKS_TEXT" ]]; then
        if ! echo "$CHECKS_TEXT" | grep -qiE '\bfail|pending|in_progress|queued|cancelled|skipping'; then
            CI_GOOD=true
        fi
    fi
    # Empty or unparseable — conservative: treat as not ready
fi

if [[ "$CI_GOOD" != "true" ]]; then
    MERGE_RESULT="ci_not_ready"
    ERROR="CI checks are not all passing"
    exit 0
fi

# Double-check freshness (may have changed since first check)
# CLEAN = mergeable normally; UNSTABLE = CI passed but review not approved;
# BLOCKED = review/policy block (--admin handles this); HAS_HOOKS = has pre-receive hooks.
# Anything else (BEHIND, DIRTY, DRAFT, UNKNOWN) = not ready.
if [[ "$MERGE_STATE" != "CLEAN" ]] && [[ "$MERGE_STATE" != "UNSTABLE" ]] && [[ "$MERGE_STATE" != "HAS_HOOKS" ]] && [[ "$MERGE_STATE" != "BLOCKED" ]]; then
    MERGE_RESULT="main_advanced"
    ERROR="Branch mergeStateStatus is $MERGE_STATE"
    exit 0
fi

# --- All checks passed — retry with --admin ---
echo "ℹ CI is green and branch is fresh. Retrying with --admin..." >&2
ADMIN_OUTPUT=$(gh pr merge "$PR_NUMBER" --repo "$REPO" --squash --admin 2>&1)
ADMIN_EXIT=$?

if [[ $ADMIN_EXIT -eq 0 ]]; then
    MERGE_RESULT="admin_merged"
    ERROR=""
    exit 0
fi

MERGE_RESULT="admin_failed"
ERROR="Admin merge failed: $ADMIN_OUTPUT"
exit 0
