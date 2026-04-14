#!/usr/bin/env bash
# fetch-eligible-issue.sh — Find the oldest open issue approved for automated work.
#
# Lists open issues, checks each for the "GO" sentinel as the last comment,
# excludes issues locked with "IN PROGRESS", and emits the first match.
#
# Usage:
#   fetch-eligible-issue.sh
#
# Output (KEY=value lines on stdout):
#   ELIGIBLE=true|false
#   ISSUE_NUMBER=<N>        (when ELIGIBLE=true)
#   ISSUE_TITLE=<title>     (when ELIGIBLE=true)
#
# Exit codes:
#   0 — eligible issue found
#   1 — no eligible issues
#   2 — gh CLI or API error

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve repo identity
# ---------------------------------------------------------------------------
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
    echo "ELIGIBLE=false"
    echo "ERROR=Failed to resolve repository name"
    exit 2
}

# ---------------------------------------------------------------------------
# Fetch open issues (oldest first, up to 100)
# ---------------------------------------------------------------------------
ISSUES_JSON=$(gh issue list --state open --json number,title --limit 100 2>/dev/null) || {
    echo "ELIGIBLE=false"
    echo "ERROR=Failed to list issues"
    exit 2
}

# Sort by number ascending (oldest first) and iterate
SORTED=$(echo "$ISSUES_JSON" | jq -c 'sort_by(.number) | .[]')

if [ -z "$SORTED" ]; then
    echo "ELIGIBLE=false"
    exit 1
fi

while IFS= read -r issue_row; do
    ISSUE_NUM=$(echo "$issue_row" | jq -r '.number')
    ISSUE_TITLE=$(echo "$issue_row" | jq -r '.title')

    # Get the last comment body (paginated to ensure we see all comments)
    LAST_COMMENT=$(gh api --paginate "repos/${REPO}/issues/${ISSUE_NUM}/comments" \
        --jq '.[-1].body // empty' 2>/dev/null | tail -1) || {
        echo "ELIGIBLE=false"
        echo "ERROR=Failed to fetch comments for issue #$ISSUE_NUM"
        exit 2
    }

    # Trim whitespace for strict comparison
    TRIMMED=$(echo "$LAST_COMMENT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Skip if last comment is IN PROGRESS (locked by another run)
    if [ "$TRIMMED" = "IN PROGRESS" ]; then
        continue
    fi

    # Check if last comment is exactly GO (case-sensitive)
    if [ "$TRIMMED" = "GO" ]; then
        echo "ELIGIBLE=true"
        echo "ISSUE_NUMBER=$ISSUE_NUM"
        echo "ISSUE_TITLE=$ISSUE_TITLE"
        exit 0
    fi
done <<< "$SORTED"

# No eligible issues found
echo "ELIGIBLE=false"
exit 1
