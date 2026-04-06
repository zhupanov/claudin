#!/usr/bin/env bash
# create-pr.sh — Push branch and create a GitHub PR.
#
# Checks for an existing open PR on the current branch first.
# If none exists, pushes the branch and creates a new PR.
#
# Usage:
#   create-pr.sh --title TEXT --body-file FILE
#
# Arguments:
#   --title     — PR title (under 70 chars recommended)
#   --body-file — Path to a file containing the PR body (markdown)
#
# Outputs (key=value to stdout):
#   PR_NUMBER=<N>
#   PR_URL=<url>
#   PR_TITLE=<title>
#   PR_STATUS=created|existing
#
# Exit codes:
#   0 — success (PR created or already exists)
#   1 — push failed
#   2 — PR creation failed

set -euo pipefail

usage() { echo "Usage: create-pr.sh --title TEXT --body-file FILE" >&2; }

TITLE=""
BODY_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --title) TITLE="${2:?--title requires a value}"; shift 2 ;;
        --body-file) BODY_FILE="${2:?--body-file requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

if [[ -z "$TITLE" ]] || [[ -z "$BODY_FILE" ]]; then
    echo "ERROR: --title and --body-file are required" >&2
    usage; exit 2
fi

if [[ ! -f "$BODY_FILE" ]]; then
    echo "ERROR: Body file not found: $BODY_FILE" >&2
    exit 2
fi

# --- Get current branch ---
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ -z "$BRANCH" ]]; then
    echo "ERROR: Not on a branch (detached HEAD)" >&2
    exit 2
fi

# --- Check for existing open PR ---
EXISTING_PR=$(gh pr view --json number,url,state,title 2>/dev/null || echo "")
if [[ -n "$EXISTING_PR" ]]; then
    PR_STATE=$(echo "$EXISTING_PR" | jq -r '.state // empty' 2>/dev/null || echo "")
    if [[ "$PR_STATE" == "OPEN" ]]; then
        PR_NUMBER=$(echo "$EXISTING_PR" | jq -r '.number // empty' 2>/dev/null || echo "")
        PR_URL=$(echo "$EXISTING_PR" | jq -r '.url // empty' 2>/dev/null || echo "")
        if [[ -n "$PR_NUMBER" ]] && [[ -n "$PR_URL" ]]; then
            # Push any new local commits before returning
            git push -u origin HEAD >/dev/null 2>&1 || true
            # Fetch the existing PR title
            PR_TITLE=$(echo "$EXISTING_PR" | jq -r '.title // empty' 2>/dev/null || echo "")
            if [[ -z "$PR_TITLE" ]]; then
                PR_TITLE=$(gh pr view "$PR_NUMBER" --json title -q '.title' 2>/dev/null || echo "")
            fi
            echo "PR_NUMBER=$PR_NUMBER"
            echo "PR_URL=$PR_URL"
            echo "PR_TITLE=$PR_TITLE"
            echo "PR_STATUS=existing"
            exit 0
        fi
    fi
fi

# --- Push branch ---
PUSH_STDERR=$(mktemp)
PR_STDERR_FILE=""
trap 'rm -f "$PUSH_STDERR" "$PR_STDERR_FILE"' EXIT
if ! git push -u origin HEAD >"$PUSH_STDERR" 2>&1; then
    echo "ERROR: Failed to push branch: $(cat "$PUSH_STDERR")" >&2
    exit 1
fi

# --- Create PR ---
PR_STDERR_FILE=$(mktemp)
PR_OUTPUT=$(gh pr create \
    --assignee @me \
    --head "$BRANCH" \
    --base main \
    --title "$TITLE" \
    --body-file "$BODY_FILE" 2>"$PR_STDERR_FILE")
PR_EXIT=$?

if [[ $PR_EXIT -ne 0 ]]; then
    PR_STDERR=$(cat "$PR_STDERR_FILE" 2>/dev/null)
    echo "ERROR: Failed to create PR: $PR_STDERR $PR_OUTPUT" >&2
    exit 2
fi

# --- Extract PR number and URL ---
# gh pr create outputs the PR URL on success
PR_URL="$PR_OUTPUT"

# Parse PR number from URL first (avoids extra API call)
# URL format: https://github.com/owner/repo/pull/N
PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || echo "")

if [[ -z "$PR_NUMBER" ]]; then
    # Fallback: fetch via gh pr view if URL parsing failed
    PR_NUMBER=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
fi

if [[ -z "$PR_NUMBER" ]] || [[ -z "$PR_URL" ]]; then
    echo "ERROR: Could not extract PR number/URL from output: $PR_OUTPUT" >&2
    exit 2
fi

echo "PR_NUMBER=$PR_NUMBER"
echo "PR_URL=$PR_URL"
echo "PR_TITLE=$TITLE"
echo "PR_STATUS=created"
