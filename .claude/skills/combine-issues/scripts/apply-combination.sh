#!/usr/bin/env bash
# Create a combined issue and close the source issues.
#
# Required flags:
#   --title <title>         Title for the combined issue.
#   --body-file <path>      Path to a file containing the combined issue body.
#   --source-issues <list>  Comma-separated issue numbers to close (e.g. "12,34,56").
#
# Optional flags:
#   --repo <owner/name>     Repository. Auto-detected if omitted.
#   --dry-run               Print what would happen without making changes.
#
# Output on stdout:
#   COMBINED_ISSUE=<number>
#   CLOSED_ISSUES=<count>
#   DRY_RUN=true|false
# On failure: ERROR=<message> on stderr, exit 1.

set -euo pipefail

TITLE=""
BODY_FILE=""
SOURCE_ISSUES=""
REPO=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)         TITLE="$2";         shift 2 ;;
    --body-file)     BODY_FILE="$2";     shift 2 ;;
    --source-issues) SOURCE_ISSUES="$2"; shift 2 ;;
    --repo)          REPO="$2";          shift 2 ;;
    --dry-run)       DRY_RUN=true;       shift ;;
    *)
      echo "ERROR=Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TITLE" ]]; then
  echo "ERROR=Missing --title" >&2
  exit 1
fi
if [[ -z "$BODY_FILE" || ! -r "$BODY_FILE" ]]; then
  echo "ERROR=Missing or unreadable --body-file: $BODY_FILE" >&2
  exit 1
fi
if [[ -z "$SOURCE_ISSUES" ]]; then
  echo "ERROR=Missing --source-issues" >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || true
  if [[ -z "$REPO" ]]; then
    echo "ERROR=Could not determine repository" >&2
    exit 1
  fi
fi

IFS=',' read -ra ISSUES <<< "$SOURCE_ISSUES"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY_RUN=true"
  echo "WOULD_CREATE=$TITLE"
  echo "WOULD_CLOSE=${#ISSUES[@]} issues: ${SOURCE_ISSUES}"
  exit 0
fi

COMBINED_NUMBER=$(gh issue create --repo "$REPO" --title "$TITLE" --body-file "$BODY_FILE" 2>/dev/null \
  | grep -oE '[0-9]+$') || {
  echo "ERROR=Failed to create combined issue" >&2
  exit 1
}

CLOSED=0
for issue_num in "${ISSUES[@]}"; do
  issue_num=$(echo "$issue_num" | tr -d ' ')
  if gh issue close "$issue_num" --repo "$REPO" \
    --comment "Combined into #${COMBINED_NUMBER}" 2>/dev/null; then
    CLOSED=$((CLOSED + 1))
  fi
done

echo "DRY_RUN=false"
echo "COMBINED_ISSUE=$COMBINED_NUMBER"
echo "CLOSED_ISSUES=$CLOSED"
