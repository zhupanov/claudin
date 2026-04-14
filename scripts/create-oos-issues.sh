#!/usr/bin/env bash
# create-oos-issues.sh — Create GitHub issues for accepted OOS items.
#
# Reads a structured markdown file of accepted out-of-scope observations
# and creates one GitHub issue per item. Best-effort: continues on
# per-item failure and reports partial success.
#
# Usage:
#   create-oos-issues.sh --input-file FILE --repo OWNER/REPO
#
# Arguments:
#   --input-file — Path to markdown file with accepted OOS items
#   --repo       — Repository in OWNER/REPO format
#
# Input file format (one or more blocks):
#   ### OOS_N: <short title>
#   - **Description**: <full description>
#   - **Reviewer**: <attribution>
#   - **Vote tally**: <YES/NO/EXONERATE counts>
#   - **Phase**: design|review
#
# Outputs (key=value to stdout):
#   ISSUES_CREATED=<N>
#   ISSUES_FAILED=<N>
#   ISSUE_1_NUMBER=<N>
#   ISSUE_1_URL=<url>
#   ISSUE_1_TITLE=<title>
#   ...
#
# Exit codes:
#   0 — success (even partial — check ISSUES_FAILED)
#   1 — usage error or input file not found
#   2 — repo not accessible

set -euo pipefail

usage() { echo "Usage: create-oos-issues.sh --input-file FILE --repo OWNER/REPO" >&2; }

INPUT_FILE=""
REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input-file) INPUT_FILE="${2:?--input-file requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$INPUT_FILE" ]] || [[ -z "$REPO" ]]; then
    usage
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR=Input file not found: $INPUT_FILE" >&2
    exit 1
fi

# Verify repo access
if ! gh repo view "$REPO" --json name >/dev/null 2>&1; then
    echo "ERROR=Cannot access repository: $REPO" >&2
    exit 2
fi

# Check if the "out-of-scope" label exists
LABEL_FLAG=""
if gh label list --repo "$REPO" --search "out-of-scope" --json name --jq '.[].name' 2>/dev/null | grep -qx "out-of-scope"; then
    LABEL_FLAG="--label out-of-scope"
fi

# Parse OOS items from the input file
# Each item starts with "### OOS_" and contains Description, Reviewer, Vote tally, Phase
ISSUES_CREATED=0
ISSUES_FAILED=0
ITEM_INDEX=0
CURRENT_TITLE=""
CURRENT_DESCRIPTION=""
CURRENT_REVIEWER=""
CURRENT_VOTE=""
CURRENT_PHASE=""

create_issue() {
    local title="$1"
    local description="$2"
    local reviewer="$3"
    local vote="$4"
    local phase="$5"

    ITEM_INDEX=$((ITEM_INDEX + 1))

    # Write issue body to temp file (avoids shell quoting issues)
    local body_file
    body_file=$(mktemp)
    cat > "$body_file" <<BODY_EOF
## Out-of-Scope Observation

**Surfaced by**: $reviewer
**Phase**: $phase review
**Vote tally**: $vote

## Description

$description

---
*This issue was automatically created by the larch \`/implement\` workflow from an out-of-scope observation that received majority YES votes during review.*
BODY_EOF

    local issue_url
    # shellcheck disable=SC2086
    if issue_url=$(gh issue create --repo "$REPO" --title "[OOS] $title" --body-file "$body_file" $LABEL_FLAG 2>/dev/null); then
        # gh issue create outputs the issue URL on stdout (e.g., https://github.com/owner/repo/issues/42)
        local number
        number=$(echo "$issue_url" | grep -oE '[0-9]+$')
        ISSUES_CREATED=$((ISSUES_CREATED + 1))
        echo "ISSUE_${ITEM_INDEX}_NUMBER=$number"
        echo "ISSUE_${ITEM_INDEX}_URL=$issue_url"
        echo "ISSUE_${ITEM_INDEX}_TITLE=$title"
    else
        ISSUES_FAILED=$((ISSUES_FAILED + 1))
        echo "ISSUE_${ITEM_INDEX}_FAILED=true" >&2
        echo "ISSUE_${ITEM_INDEX}_TITLE=$title" >&2
    fi

    rm -f "$body_file"
}

flush_item() {
    if [[ -n "$CURRENT_TITLE" ]] && [[ -n "$CURRENT_DESCRIPTION" ]]; then
        create_issue "$CURRENT_TITLE" "$CURRENT_DESCRIPTION" "$CURRENT_REVIEWER" "$CURRENT_VOTE" "$CURRENT_PHASE"
    fi
    CURRENT_TITLE=""
    CURRENT_DESCRIPTION=""
    CURRENT_REVIEWER=""
    CURRENT_VOTE=""
    CURRENT_PHASE=""
}

while IFS= read -r line; do
    if [[ "$line" =~ ^###\ OOS_[0-9]+:\ (.+)$ ]]; then
        flush_item
        CURRENT_TITLE="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^-\ \*\*Description\*\*:\ (.+)$ ]]; then
        CURRENT_DESCRIPTION="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^-\ \*\*Reviewer\*\*:\ (.+)$ ]]; then
        CURRENT_REVIEWER="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^-\ \*\*Vote\ tally\*\*:\ (.+)$ ]]; then
        CURRENT_VOTE="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^-\ \*\*Phase\*\*:\ (.+)$ ]]; then
        CURRENT_PHASE="${BASH_REMATCH[1]}"
    fi
done < "$INPUT_FILE"

# Flush the last item
flush_item

echo "ISSUES_CREATED=$ISSUES_CREATED"
echo "ISSUES_FAILED=$ISSUES_FAILED"
