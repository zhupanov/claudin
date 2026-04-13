#!/usr/bin/env bash
# write-session-env.sh — Write session environment values to a file for child skills.
#
# Usage:
#   write-session-env.sh --output <path> --slack-ok <true|false> \
#                        [--slack-missing <csv>] --repo <owner/repo> \
#                        --repo-unavailable <true|false> \
#                        [--codex-healthy <true|false>] [--cursor-healthy <true|false>]
#
# Options:
#   --repo may be empty when --repo-unavailable is true (repo discovery failed).
#   --slack-missing is optional (only meaningful when --slack-ok is false).
#   --codex-healthy/--cursor-healthy are optional (reviewer health state from probe).
#
# Output: Writes a shell-sourceable file to --output path (atomic via temp+mv).
#         When --output is /dev/null, the output is silently discarded.
# Exit codes: 0 success, 1 invalid args

set -euo pipefail

OUTPUT=""
SLACK_OK=""
SLACK_MISSING=""
REPO=""
REPO_UNAVAILABLE=""
CODEX_HEALTHY=""
CURSOR_HEALTHY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)           OUTPUT="$2"; shift 2 ;;
    --slack-ok)         SLACK_OK="$2"; shift 2 ;;
    --slack-missing)    SLACK_MISSING="$2"; shift 2 ;;
    --repo)             REPO="$2"; shift 2 ;;
    --repo-unavailable) REPO_UNAVAILABLE="$2"; shift 2 ;;
    --codex-healthy)    CODEX_HEALTHY="$2"; shift 2 ;;
    --cursor-healthy)   CURSOR_HEALTHY="$2"; shift 2 ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT" || -z "$SLACK_OK" || -z "$REPO_UNAVAILABLE" ]]; then
  echo "ERROR=Missing required arguments: --output, --slack-ok, --repo-unavailable" >&2
  exit 1
fi

# Build the content
CONTENT="SLACK_OK=$SLACK_OK
SLACK_MISSING=$SLACK_MISSING
REPO=$REPO
REPO_UNAVAILABLE=$REPO_UNAVAILABLE"
[[ -n "$CODEX_HEALTHY" ]] && CONTENT="$CONTENT
CODEX_HEALTHY=$CODEX_HEALTHY"
[[ -n "$CURSOR_HEALTHY" ]] && CONTENT="$CONTENT
CURSOR_HEALTHY=$CURSOR_HEALTHY"

# Write atomically via temp+mv for regular paths.
# Skip /dev/null — mktemp and mv both fail on device nodes.
if [[ "$OUTPUT" == "/dev/null" ]]; then
  : # Discard — caller explicitly requested no output
else
  TMPFILE=$(mktemp "${OUTPUT}.tmp.XXXXXX")
  echo "$CONTENT" > "$TMPFILE"
  mv "$TMPFILE" "$OUTPUT"
fi
