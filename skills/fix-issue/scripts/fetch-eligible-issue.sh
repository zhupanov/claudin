#!/usr/bin/env bash
# fetch-eligible-issue.sh — Find an eligible issue approved for automated work.
#
# Without --issue: lists open issues, checks each for the "GO" sentinel as
# the last comment, excludes issues locked with "IN PROGRESS", and emits
# the first match (oldest first).
#
# With --issue: targets a specific issue (by number or GitHub URL), verifies
# it is open and has "GO" as the last comment.
#
# Usage:
#   fetch-eligible-issue.sh [<number-or-url>]
#   fetch-eligible-issue.sh [--issue <number-or-url>]  (deprecated)
#
# Output (KEY=value lines on stdout):
#   ELIGIBLE=true|false
#   ISSUE_NUMBER=<N>        (when ELIGIBLE=true)
#   ISSUE_TITLE=<title>     (when ELIGIBLE=true)
#   ERROR=<message>         (when ELIGIBLE=false and exit 2)
#
# Exit codes:
#   0 — eligible issue found
#   1 — no eligible issues (auto-pick mode only)
#   2 — error: gh CLI failure, or explicit issue not eligible

set -euo pipefail

ISSUE_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue)
            if [[ $# -lt 2 ]]; then
                echo "ELIGIBLE=false"
                echo "ERROR=--issue requires a value"
                exit 2
            fi
            ISSUE_ARG="$2"; shift 2
            ;;
        -*)
            echo "ELIGIBLE=false"
            echo "ERROR=Unknown option: $1"
            exit 2
            ;;
        *)
            # Positional argument: issue number or URL
            ISSUE_ARG="$1"; shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve repo identity
# ---------------------------------------------------------------------------
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
    echo "ELIGIBLE=false"
    echo "ERROR=Failed to resolve repository name"
    exit 2
}

# ---------------------------------------------------------------------------
# Explicit issue mode (--issue provided)
# ---------------------------------------------------------------------------
if [[ -n "$ISSUE_ARG" ]]; then
    # gh issue view accepts both bare numbers and full GitHub URLs natively.
    # For URLs, it resolves the repo from the URL — we must verify it matches
    # the current repo to prevent cross-repo misoperation.
    ISSUE_JSON=$(gh issue view "$ISSUE_ARG" --json number,state,title,url 2>/dev/null) || {
        echo "ELIGIBLE=false"
        echo "ERROR=Failed to fetch issue (invalid number, URL, or inaccessible): $ISSUE_ARG"
        exit 2
    }

    ISSUE_NUM=$(echo "$ISSUE_JSON" | jq -r '.number')
    ISSUE_STATE=$(echo "$ISSUE_JSON" | jq -r '.state')
    ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
    ISSUE_URL=$(echo "$ISSUE_JSON" | jq -r '.url // empty')

    # Verify issue belongs to the current repo by parsing owner/repo from the
    # issue URL (format: https://github.com/OWNER/REPO/issues/N).
    if [[ -z "$ISSUE_URL" ]]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Cannot verify repository ownership for issue: $ISSUE_ARG"
        exit 2
    fi
    ISSUE_REPO=$(echo "$ISSUE_URL" | sed -n 's|https://github.com/\([^/]*/[^/]*\)/issues/.*|\1|p')
    if [[ -z "$ISSUE_REPO" ]]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Cannot parse repository from issue URL: $ISSUE_URL"
        exit 2
    fi
    if [[ "$ISSUE_REPO" != "$REPO" ]]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Issue belongs to $ISSUE_REPO, not the current repo ($REPO)"
        exit 2
    fi

    # Verify issue is open
    if [ "$ISSUE_STATE" != "OPEN" ]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Issue #$ISSUE_NUM is not open (state: $ISSUE_STATE)"
        exit 2
    fi

    # Verify last comment is GO
    LAST_COMMENT=$(gh api --paginate "repos/${REPO}/issues/${ISSUE_NUM}/comments" \
        --jq '.[-1].body // empty' 2>/dev/null | tail -1) || {
        echo "ELIGIBLE=false"
        echo "ERROR=Failed to fetch comments for issue #$ISSUE_NUM"
        exit 2
    }

    TRIMMED=$(echo "$LAST_COMMENT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ "$TRIMMED" != "GO" ]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Issue #$ISSUE_NUM is not approved (last comment: ${TRIMMED:-empty})"
        exit 2
    fi

    echo "ELIGIBLE=true"
    echo "ISSUE_NUMBER=$ISSUE_NUM"
    echo "ISSUE_TITLE=$ISSUE_TITLE"
    exit 0
fi

# ---------------------------------------------------------------------------
# Auto-pick mode (no --issue): scan open issues oldest-first
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
