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
#   - **Description**: <full description, may span multiple lines>
#     <continuation lines are appended until the next field>
#   - **Reviewer**: <attribution>
#   - **Vote tally**: <YES/NO/EXONERATE counts>
#   - **Phase**: design|review|implement
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
    printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^\[oos\]\s*//' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//'
}

# Defense-in-depth secret/PII redaction. Catches common token patterns that
# might slip past prompt-level sanitization in skills/implement/SKILL.md
# (Mandatory dual-write rule). Patterns are conservative — false positives
# (over-redaction) are preferred to leaking real secrets into public issues.
# Returns the redacted string on stdout. Pre-existing reviewer-voted OOS
# items also flow through here, so the rules apply uniformly.
redact_secrets() {
    local text="$1"
    # Anthropic / OpenAI sk-* keys
    text=$(printf '%s' "$text" | sed -E 's/sk-(ant-)?[A-Za-z0-9_-]{20,}/<REDACTED-TOKEN>/g')
    # GitHub PATs and fine-grained tokens
    text=$(printf '%s' "$text" | sed -E 's/(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}/<REDACTED-TOKEN>/g')
    # AWS access key IDs
    text=$(printf '%s' "$text" | sed -E 's/AKIA[0-9A-Z]{16}/<REDACTED-TOKEN>/g')
    # Slack tokens (xoxb, xoxa, xoxp, xoxs)
    text=$(printf '%s' "$text" | sed -E 's/xox[baprs]-[A-Za-z0-9-]{10,}/<REDACTED-TOKEN>/g')
    # Generic JWT (header.payload.signature, base64url segments separated by dots)
    text=$(printf '%s' "$text" | sed -E 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/<REDACTED-TOKEN>/g')
    # PEM private key blocks
    text=$(printf '%s' "$text" | sed -E 's/-----BEGIN [A-Z ]*PRIVATE KEY-----.*-----END [A-Z ]*PRIVATE KEY-----/<REDACTED-PRIVATE-KEY>/g')
    printf '%s' "$text"
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
IN_DESCRIPTION=false

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

    # Defense-in-depth: redact common secret/credential patterns from the
    # description before it lands in a public GitHub issue body. Prompt-level
    # sanitization in skills/implement/SKILL.md is the primary line of defense;
    # this is the deterministic backstop for missed patterns.
    description=$(redact_secrets "$description")

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
*This issue was automatically created by the larch \`/implement\` workflow from an out-of-scope observation surfaced during the workflow.*
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
        # Append to snapshot so later items in this batch detect intra-run duplicates
        printf '%s\t%s\t[OOS] %s\n' "$number" "$issue_url" "$title" >> "$EXISTING_ISSUES_FILE"
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
    IN_DESCRIPTION=false
}

while IFS= read -r line; do
    if [[ "$line" =~ ^###\ OOS_[0-9]+:\ (.+)$ ]]; then
        flush_item
        CURRENT_TITLE="${BASH_REMATCH[1]}"
        IN_DESCRIPTION=false
    elif [[ "$line" =~ ^-\ \*\*Description\*\*:\ (.+)$ ]]; then
        CURRENT_DESCRIPTION="${BASH_REMATCH[1]}"
        IN_DESCRIPTION=true
    elif [[ "$line" =~ ^-\ \*\*Reviewer\*\*:\ (.+)$ ]]; then
        CURRENT_REVIEWER="${BASH_REMATCH[1]}"
        IN_DESCRIPTION=false
    elif [[ "$line" =~ ^-\ \*\*Vote\ tally\*\*:\ (.+)$ ]]; then
        CURRENT_VOTE="${BASH_REMATCH[1]}"
        IN_DESCRIPTION=false
    elif [[ "$line" =~ ^-\ \*\*Phase\*\*:\ (.+)$ ]]; then
        CURRENT_PHASE="${BASH_REMATCH[1]}"
        IN_DESCRIPTION=false
    elif [[ "$IN_DESCRIPTION" == true ]]; then
        # Accumulate continuation lines (including blank lines) so paragraph breaks
        # survive — IN_DESCRIPTION is cleared only by a field marker or a new
        # ### OOS_N: header, so this branch never captures structural lines.
        CURRENT_DESCRIPTION+=$'\n'"$line"
    fi
done < "$INPUT_FILE"

# Flush the last item
flush_item

echo "ISSUES_CREATED=$ISSUES_CREATED"
echo "ISSUES_FAILED=$ISSUES_FAILED"
echo "ISSUES_DEDUPLICATED=$ISSUES_DEDUPLICATED"
