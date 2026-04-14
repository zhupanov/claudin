#!/usr/bin/env bash
# get-issue-details.sh — Fetch an issue's full details (body + all comments).
#
# Writes a structured text file containing the issue title, body, labels,
# and all comments with author attribution.
#
# Usage:
#   get-issue-details.sh --issue NUMBER --output PATH
#
# Output file format:
#   # Issue #N: <title>
#   **Labels**: <comma-separated>
#   **Created**: <date>
#
#   ## Description
#   <body>
#
#   ## Comments
#   ### Comment by <login> at <date>
#   <body>
#
# Exit codes:
#   0 — success
#   1 — error (missing args, API failure)

set -euo pipefail

ISSUE_NUMBER=""
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue) ISSUE_NUMBER="${2:?--issue requires a value}"; shift 2 ;;
        --output) OUTPUT_PATH="${2:?--output requires a value}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$ISSUE_NUMBER" ]] || [[ -z "$OUTPUT_PATH" ]]; then
    echo "Usage: get-issue-details.sh --issue NUMBER --output PATH" >&2
    exit 1
fi

# Resolve repo identity
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
    echo "ERROR=Failed to resolve repository name" >&2
    exit 1
}

# Fetch issue metadata
ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --json title,body,labels,createdAt 2>/dev/null) || {
    echo "ERROR=Failed to fetch issue #$ISSUE_NUMBER" >&2
    exit 1
}

TITLE=$(echo "$ISSUE_JSON" | jq -r '.title // "Untitled"')
BODY=$(echo "$ISSUE_JSON" | jq -r '.body // "No description provided."')
LABELS=$(echo "$ISSUE_JSON" | jq -r '[.labels[].name] | join(", ") // "none"')
CREATED=$(echo "$ISSUE_JSON" | jq -r '.createdAt // "unknown"')

# Fetch all comments (paginated)
COMMENTS=$(gh api --paginate --slurp "repos/${REPO}/issues/${ISSUE_NUMBER}/comments" 2>/dev/null | jq 'add // []') || {
    echo "ERROR=Failed to fetch comments for issue #$ISSUE_NUMBER" >&2
    exit 1
}

# Write structured output
{
    echo "# Issue #${ISSUE_NUMBER}: ${TITLE}"
    echo "**Labels**: ${LABELS}"
    echo "**Created**: ${CREATED}"
    echo ""
    echo "## Description"
    echo ""
    echo "$BODY"
    echo ""
    echo "## Comments"
    echo ""

    COMMENT_COUNT=$(echo "$COMMENTS" | jq 'length')
    if [ "$COMMENT_COUNT" -eq 0 ]; then
        echo "No comments."
    else
        echo "$COMMENTS" | jq -r '.[] | "### Comment by \(.user.login) at \(.created_at)\n\n\(.body)\n"'
    fi
} > "$OUTPUT_PATH"

echo "OUTPUT_FILE=$OUTPUT_PATH"
