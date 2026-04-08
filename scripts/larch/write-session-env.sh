#!/usr/bin/env bash
# write-session-env.sh — Write session environment values to a file for child skills.
#
# Usage:
#   write-session-env.sh --output <path> --slack-ok <true|false> \
#                        [--slack-missing <csv>] --repo <owner/repo> \
#                        --repo-unavailable <true|false>
#
# Options:
#   --repo may be empty when --repo-unavailable is true (repo discovery failed).
#   --slack-missing is optional (only meaningful when --slack-ok is false).
#
# Output: Writes a shell-sourceable file to --output path.
# Exit codes: 0 success, 1 invalid args

set -euo pipefail

OUTPUT=""
SLACK_OK=""
SLACK_MISSING=""
REPO=""
REPO_UNAVAILABLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)       OUTPUT="$2"; shift 2 ;;
    --slack-ok)     SLACK_OK="$2"; shift 2 ;;
    --slack-missing) SLACK_MISSING="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --repo-unavailable) REPO_UNAVAILABLE="$2"; shift 2 ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT" || -z "$SLACK_OK" || -z "$REPO_UNAVAILABLE" ]]; then
  echo "ERROR=Missing required arguments: --output, --slack-ok, --repo-unavailable" >&2
  exit 1
fi

cat > "$OUTPUT" << ENVEOF
SLACK_OK=$SLACK_OK
SLACK_MISSING=$SLACK_MISSING
REPO=$REPO
REPO_UNAVAILABLE=$REPO_UNAVAILABLE
ENVEOF
