#!/usr/bin/env bash
# get-issue-info.sh — Query a single field from a GitHub issue.
#
# Usage:
#   get-issue-info.sh --issue <N> --field <state|url>
#
# Output (KEY=value on stdout):
#   VALUE=<result>    (on success — e.g., VALUE=OPEN or VALUE=https://...)
#   VALUE=            (on failure — gh error, auth, network, invalid issue)
#
# Exit codes:
#   0 — always (fail-open for caller convenience)

set -euo pipefail

ISSUE=""
FIELD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue) ISSUE="${2:?--issue requires a value}"; shift 2 ;;
        --field) FIELD="${2:?--field requires a value}"; shift 2 ;;
        *) echo "get-issue-info.sh: unknown flag: $1" >&2; echo "VALUE="; exit 0 ;;
    esac
done

if [[ -z "$ISSUE" || -z "$FIELD" ]]; then
    echo "get-issue-info.sh: --issue and --field are required" >&2
    echo "VALUE="
    exit 0
fi

case "$FIELD" in
    state|url) ;;
    *) echo "get-issue-info.sh: --field must be 'state' or 'url'" >&2; echo "VALUE="; exit 0 ;;
esac

RESULT=$(gh issue view "$ISSUE" --json "$FIELD" --jq ".$FIELD" 2>/dev/null) || RESULT=""
echo "VALUE=$RESULT"
exit 0
