#!/usr/bin/env bash
# fetch-eligible-issue.sh — Find an eligible issue approved for automated work.
#
# Without --issue: lists open issues, checks each for the "GO" sentinel as
# the last comment, excludes issues locked with "IN PROGRESS", excludes
# issues blocked by other open issues (via GitHub's native issue dependencies),
# and emits the first match (oldest first).
#
# With --issue: targets a specific issue (by number or GitHub URL), verifies
# it is open, has "GO" as the last comment, and has no currently-open
# blocking dependencies.
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
            echo "WARNING: --issue is deprecated; pass the issue number or URL as a positional argument instead." >&2
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
            if [[ -n "$ISSUE_ARG" ]]; then
                echo "ELIGIBLE=false"
                echo "ERROR=Unexpected extra argument: $1 (issue already set to $ISSUE_ARG)"
                exit 2
            fi
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
# open_blockers <issue-number>
#
# Queries GitHub's native issue-dependencies API and prints a space-separated
# list of open blocker issue numbers (e.g., "42 57") on stdout. Empty output
# means no open blockers — the issue may proceed.
#
# API errors (404 on repos without the dependencies feature, transient gh
# failures) are treated as "no blockers known": the function prints nothing
# and returns 0. Rationale: do not let dependency-API availability become a
# hard gate on the automation — if the feature isn't used or is unreachable,
# fall back to pre-existing behavior (GO sentinel alone).
# ---------------------------------------------------------------------------
open_blockers() {
    local num="$1"
    local nums
    # Use --paginate with --jq so the filter runs per page and outputs are concatenated
    # (one number per line). Using --paginate without --jq returns one JSON array per
    # page as separate documents, and `jq '.[] ...'` only consumes the first — missing
    # blockers beyond the default page size.
    nums=$(gh api --paginate "repos/${REPO}/issues/${num}/dependencies/blocked_by" \
        --jq '.[] | select(.state == "open") | .number' 2>/dev/null) || return 0
    # Collapse newline-separated numbers into a single space-separated line, trimming trailing whitespace.
    echo "$nums" | tr '\n' ' ' | sed 's/[[:space:]]*$//'
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

    BLOCKERS=$(open_blockers "$ISSUE_NUM")
    if [ -n "$BLOCKERS" ]; then
        # Format as comma-separated #N list for the error message
        FORMATTED=$(echo "$BLOCKERS" | tr ' ' '\n' | sed 's/^/#/' | paste -sd ',' -)
        echo "ELIGIBLE=false"
        echo "ERROR=Issue #$ISSUE_NUM is blocked by open dependencies: $FORMATTED"
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
        BLOCKERS=$(open_blockers "$ISSUE_NUM")
        if [ -n "$BLOCKERS" ]; then
            # Blocked by at least one open dependency — log on stderr and keep scanning.
            FORMATTED=$(echo "$BLOCKERS" | tr ' ' '\n' | sed 's/^/#/' | paste -sd ',' -)
            echo "Skipping issue #$ISSUE_NUM: blocked by open dependencies ($FORMATTED)" >&2
            continue
        fi
        echo "ELIGIBLE=true"
        echo "ISSUE_NUMBER=$ISSUE_NUM"
        echo "ISSUE_TITLE=$ISSUE_TITLE"
        exit 0
    fi
done <<< "$SORTED"

# No eligible issues found
echo "ELIGIBLE=false"
exit 1
