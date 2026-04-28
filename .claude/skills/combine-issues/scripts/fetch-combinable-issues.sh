#!/usr/bin/env bash
# Fetch open GitHub issues eligible for combination.
# Excludes issues with managed title prefixes ([IN PROGRESS], [STALLED], [DONE]).
#
# Output on stdout: ISSUES_FILE=<path> and COUNT=<n>.
# On failure: ERROR=<message> on stderr, exit 1.

set -euo pipefail

REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *)
      echo "ERROR=Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || true
  if [[ -z "$REPO" ]]; then
    echo "ERROR=Could not determine repository" >&2
    exit 1
  fi
fi

RAW=$(gh issue list --repo "$REPO" --state open --limit 200 \
  --json number,title,body,labels 2>/dev/null) || {
  echo "ERROR=Failed to fetch issues from $REPO" >&2
  exit 1
}

if [[ -z "$RAW" || "$RAW" == "[]" ]]; then
  TMPFILE=$(mktemp /tmp/combine-issues-XXXXXX.json)
  echo "[]" > "$TMPFILE"
  echo "ISSUES_FILE=$TMPFILE"
  echo "COUNT=0"
  exit 0
fi

FILTERED=$(echo "$RAW" | jq '[
  .[] |
  select(
    (.title | test("^\\[(IN PROGRESS|STALLED|DONE)\\] ") | not) and
    (.title | test("^\\[LOCKED\\]") | not)
  )
]')

TMPFILE=$(mktemp /tmp/combine-issues-XXXXXX.json)
echo "$FILTERED" > "$TMPFILE"
COUNT=$(echo "$FILTERED" | jq 'length')

echo "ISSUES_FILE=$TMPFILE"
echo "COUNT=$COUNT"
