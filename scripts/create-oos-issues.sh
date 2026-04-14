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
#   ISSUES_DEDUPLICATED=<N>
#   ISSUE_1_NUMBER=<N>
#   ISSUE_1_URL=<url>
#   ISSUE_1_TITLE=<title>
#   ISSUE_1_DUPLICATE=true           (if deduplicated)
#   ISSUE_1_DUPLICATE_OF_NUMBER=<N>  (existing issue number)
#   ISSUE_1_DUPLICATE_OF_URL=<url>   (existing issue URL)
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

# Fetch all open issue titles for deduplication (one API call, reused per item)
EXISTING_ISSUES_FILE=$(mktemp)
trap 'rm -f "$EXISTING_ISSUES_FILE"' EXIT
gh issue list --repo "$REPO" --state open --json title,number,url --limit 500 --jq '.[] | "\(.number)\t\(.url)\t\(.title)"' > "$EXISTING_ISSUES_FILE" 2>/dev/null || true

# Normalize a title for comparison: lowercase, strip [OOS] prefix, collapse whitespace, trim
normalize_title() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^\[oos\]\s*//' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//'
}

# Check if a title is a duplicate of an existing open issue.
# Returns 0 (match found) and prints "NUMBER<tab>URL" of the match, or returns 1 (no match).
check_duplicate() {
    local new_title="$1"
    local new_norm
    new_norm=$(normalize_title "$new_title")
    [[ -z "$new_norm" ]] && return 1

    while IFS=$'\t' read -r num url existing_title; do
        local existing_norm
        existing_norm=$(normalize_title "$existing_title")
        [[ -z "$existing_norm" ]] && continue

        # Exact match after normalization
        if [[ "$new_norm" == "$existing_norm" ]]; then
            printf '%s\t%s' "$num" "$url"
            return 0
        fi

        # Substring containment (either direction)
        if [[ "$existing_norm" == *"$new_norm"* ]] || [[ "$new_norm" == *"$existing_norm"* ]]; then
            printf '%s\t%s' "$num" "$url"
            return 0
        fi
    done < "$EXISTING_ISSUES_FILE"

    return 1
}

# Parse OOS items from the input file
# Each item starts with "### OOS_" and contains Description, Reviewer, Vote tally, Phase
ISSUES_CREATED=0
ISSUES_FAILED=0
ISSUES_DEDUPLICATED=0
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

    # Check for duplicate before creating
    local dup_info
    if dup_info=$(check_duplicate "$title"); then
        local dup_number dup_url
        dup_number=$(echo "$dup_info" | cut -f1)
        dup_url=$(echo "$dup_info" | cut -f2)
        ISSUES_DEDUPLICATED=$((ISSUES_DEDUPLICATED + 1))
        echo "ISSUE_${ITEM_INDEX}_DUPLICATE=true"
        echo "ISSUE_${ITEM_INDEX}_DUPLICATE_OF_NUMBER=$dup_number"
        echo "ISSUE_${ITEM_INDEX}_DUPLICATE_OF_URL=$dup_url"
        echo "ISSUE_${ITEM_INDEX}_TITLE=$title"
        return
    fi

    # Write issue body to temp file (avoids shell quoting issues)
    local body_file
    body_file=$(mktemp)
    cat > "$body_file" <<BODY_EOF
## Out-of-Scope Observation

**Surfaced by**: $reviewer
**Phase**: $phase
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
    elif [[ -n "$CURRENT_TITLE" ]] && [[ -z "$CURRENT_DESCRIPTION" ]]; then
        # Malformed input: title without description — count as failure
        ISSUES_FAILED=$((ISSUES_FAILED + 1))
        echo "SKIPPED: '$CURRENT_TITLE' — missing description" >&2
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
echo "ISSUES_DEDUPLICATED=$ISSUES_DEDUPLICATED"
