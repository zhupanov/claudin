#!/usr/bin/env bash
# ci-status.sh — Check CI status and main branch advancement for a PR.
#
# Fetches origin/main, checks PR CI status via `gh pr checks --json`,
# and counts commits behind origin/main.
#
# Usage:
#   ci-status.sh --pr NUMBER --repo OWNER/REPO
#
# Outputs (always all three lines, in order):
#   CI_STATUS=pass|fail|pending|merged
#   BEHIND_COUNT=<N>
#   FAILED_RUN_ID=<id>    (empty string if no failure)
#
# Exit codes:
#   0 — always (status is communicated via output lines)

set -uo pipefail
# Note: not using set -e — we need to guarantee output on all paths

# Defaults — these will always be emitted even on unexpected errors
CI_STATUS="pending"
BEHIND_COUNT="0"
FAILED_RUN_ID=""

# Ensure output is always emitted, even on unexpected errors
trap 'echo "CI_STATUS=$CI_STATUS"; echo "BEHIND_COUNT=$BEHIND_COUNT"; echo "FAILED_RUN_ID=$FAILED_RUN_ID"' EXIT

usage() { echo "Usage: ci-status.sh --pr NUMBER --repo OWNER/REPO" >&2; }

PR_NUMBER=""
REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR_NUMBER="${2:?--pr requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; CI_STATUS="error"; exit 0 ;;
    esac
done

if [[ -z "$PR_NUMBER" ]] || [[ -z "$REPO" ]]; then
    echo "ERROR: --pr and --repo are required" >&2
    usage; CI_STATUS="error"; exit 0
fi

# --- Check if PR has been force-merged ---
PR_STATE=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "")
if [[ "$PR_STATE" == "MERGED" ]]; then
    CI_STATUS="merged"
    exit 0
fi

# --- Fetch origin/main for staleness check ---
if ! git fetch origin main --quiet 2>/dev/null; then
    # Fetch failed — cannot reliably compute BEHIND_COUNT.
    # Force pending status so the caller retries instead of trusting stale refs.
    echo "⚠ git fetch origin main failed — reporting pending to force retry" >&2
    CI_STATUS="pending"
    BEHIND_COUNT="0"
    exit 0
fi

# --- Check CI status ---
# Try JSON output first (gh CLI v2.x)
# Use 'bucket' field which is reliably available (pass/fail/pending)
CHECKS_JSON=$(gh pr checks "$PR_NUMBER" --repo "$REPO" --json name,state,bucket,link 2>/dev/null || echo "")

if [[ -n "$CHECKS_JSON" ]] && [[ "$CHECKS_JSON" != "null" ]] \
    && echo "$CHECKS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
    # Parse JSON output
    TOTAL=$(echo "$CHECKS_JSON" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$TOTAL" -eq 0 ]]; then
        CI_STATUS="pending"
    else
        FAILED=$(echo "$CHECKS_JSON" | jq '[.[] | select(.bucket == "fail")] | length' 2>/dev/null || echo "0")
        PENDING=$(echo "$CHECKS_JSON" | jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null || echo "0")

        if [[ "$FAILED" -gt 0 ]]; then
            CI_STATUS="fail"
            # Extract the run ID from the first failed check's link URL
            # Link format: https://github.com/<owner>/<repo>/actions/runs/<run-id>/job/<job-id>
            FAILED_LINK=$(echo "$CHECKS_JSON" | jq -r '[.[] | select(.bucket == "fail")][0].link // empty' 2>/dev/null || echo "")
            if [[ -n "$FAILED_LINK" ]]; then
                FAILED_RUN_ID=$(echo "$FAILED_LINK" | grep -oE 'runs/[0-9]+' | head -1 | sed 's/runs\///' || echo "")
            fi
        elif [[ "$PENDING" -gt 0 ]]; then
            CI_STATUS="pending"
        else
            CI_STATUS="pass"
        fi
    fi
else
    # Fallback: parse text output
    CHECKS_TEXT=$(gh pr checks "$PR_NUMBER" --repo "$REPO" 2>/dev/null || echo "")

    if [[ -z "$CHECKS_TEXT" ]]; then
        CI_STATUS="pending"
    elif echo "$CHECKS_TEXT" | grep -qiE '\bfail'; then
        CI_STATUS="fail"
        # Try to extract run ID from the URL column
        FAILED_LINK=$(echo "$CHECKS_TEXT" | grep -iE '\bfail' | head -1 | grep -oE 'https://[^ ]+' | head -1 || echo "")
        if [[ -n "$FAILED_LINK" ]]; then
            FAILED_RUN_ID=$(echo "$FAILED_LINK" | grep -oE 'runs/[0-9]+' | head -1 | sed 's/runs\///' || echo "")
        fi
    elif echo "$CHECKS_TEXT" | grep -qiE 'pending|in_progress|queued'; then
        CI_STATUS="pending"
    else
        CI_STATUS="pass"
    fi
fi

# --- Check behind count ---
BEHIND_COUNT=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo "0")

# --- Git-based merge detection (catches race where git refs update before GitHub API) ---
# If main advanced, check if this PR's squash-merge commit landed.
# Uses fixed-string match for "(#N)" — GitHub's squash-merge subject format.
# Note: only works for squash merges (this project uses --squash exclusively).
# False positive would trigger premature cleanup; remote branch preserved for recovery.
if [[ "$BEHIND_COUNT" -gt 0 ]]; then
    if git log HEAD..origin/main --oneline 2>/dev/null | grep -Fq "(#${PR_NUMBER})"; then
        CI_STATUS="merged"
        BEHIND_COUNT="0"
        FAILED_RUN_ID=""
    fi
fi
