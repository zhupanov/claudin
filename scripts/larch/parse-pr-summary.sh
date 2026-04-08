#!/usr/bin/env bash
# parse-pr-summary.sh — Extract "## Summary" bullets from a PR body.
#
# Fetches the PR body via gh, extracts bullet lines between "## Summary"
# and the next "##" heading, counts them, and outputs the results.
#
# Note: Similar extraction logic exists in slack-announce.sh.
# Both implementations extract the "## Summary" section from PR bodies.
#
# Usage:
#   parse-pr-summary.sh --pr NUMBER
#
# Outputs (key=value to stdout):
#   BULLET_COUNT=<N>
#   BULLETS=<pipe-separated bullet text, without "- " prefix>
#
# Exit codes:
#   0 — success (even if no Summary section found — outputs BULLET_COUNT=0)
#   1 — failed to fetch PR body

set -euo pipefail

usage() { echo "Usage: parse-pr-summary.sh --pr NUMBER" >&2; }

PR_NUMBER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR_NUMBER="${2:?--pr requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$PR_NUMBER" ]]; then
    echo "ERROR: --pr is required" >&2
    usage; exit 1
fi

# Fetch PR body
PR_BODY=$(gh pr view "$PR_NUMBER" --json body -q '.body' 2>/dev/null || echo "")
if [[ -z "$PR_BODY" ]]; then
    echo "ERROR: Failed to fetch PR body for #$PR_NUMBER" >&2
    exit 1
fi

# Extract text between "## Summary" and the next "##" heading or "<details>" block
# Strip bullet prefixes ("- " or "* ") and blank lines
BULLETS=$(printf '%s\n' "$PR_BODY" | \
    sed -En '/^## Summary/,/^(## |<details>)/{ /^## Summary/d; /^(## |<details>)/d; p; }' | \
    sed 's/^[[:space:]]*[-*][[:space:]]*//' | \
    sed '/^[[:space:]]*$/d')

if [[ -z "$BULLETS" ]]; then
    echo "BULLET_COUNT=0"
    echo "BULLETS="
    exit 0
fi

# Count non-empty lines
BULLET_COUNT=$(printf '%s\n' "$BULLETS" | wc -l | tr -d ' ')

# Join bullets with pipe separator to keep KEY=value on a single line
BULLETS_ONELINE=$(printf '%s\n' "$BULLETS" | tr '\n' '|' | sed 's/|$//')

echo "BULLET_COUNT=$BULLET_COUNT"
echo "BULLETS=$BULLETS_ONELINE"
