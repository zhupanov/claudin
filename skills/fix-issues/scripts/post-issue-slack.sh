#!/usr/bin/env bash
# post-issue-slack.sh — Post a Slack message about an issue closure.
#
# Composes a message and delegates to the shared post-slack-message.sh script.
# Does NOT read Slack env vars directly — receives token and channel as args.
#
# Usage:
#   post-issue-slack.sh --issue NUMBER --title TITLE --token TOKEN \
#       --channel-id CHANNEL [--pr-url URL] [--message TEXT]
#
# When --pr-url is provided, the message includes the PR link.
# When --message is provided, it is used as the full message text.
# If neither is provided, a generic closure message is posted.
#
# Output (KEY=value lines on stdout):
#   SLACK_TS=<timestamp>    (on success)
#   SLACK_TS=               (on failure)
#
# Exit codes:
#   0 — message posted
#   1 — missing arguments or posting failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

ISSUE_NUMBER=""
ISSUE_TITLE=""
TOKEN=""
CHANNEL_ID=""
PR_URL=""
MESSAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue) ISSUE_NUMBER="${2:?--issue requires a value}"; shift 2 ;;
        --title) ISSUE_TITLE="${2:?--title requires a value}"; shift 2 ;;
        --token) TOKEN="${2:?--token requires a value}"; shift 2 ;;
        --channel-id) CHANNEL_ID="${2:?--channel-id requires a value}"; shift 2 ;;
        --pr-url) PR_URL="${2:?--pr-url requires a value}"; shift 2 ;;
        --message) MESSAGE="${2:?--message requires a value}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$ISSUE_NUMBER" ]] || [[ -z "$TOKEN" ]] || [[ -z "$CHANNEL_ID" ]]; then
    echo "SLACK_TS="
    echo "ERROR=--issue, --token, and --channel-id are required"
    exit 1
fi

# Compose message if not provided
if [[ -z "$MESSAGE" ]]; then
    if [[ -n "$PR_URL" ]]; then
        MESSAGE="Issue #${ISSUE_NUMBER} (${ISSUE_TITLE:-untitled}) closed — fixed in ${PR_URL}"
    else
        MESSAGE="Issue #${ISSUE_NUMBER} (${ISSUE_TITLE:-untitled}) closed"
    fi
fi

# Delegate to shared posting script
SLACK_TS=$("$PLUGIN_ROOT/scripts/post-slack-message.sh" \
    --channel-id "$CHANNEL_ID" \
    --text "$MESSAGE" \
    --token "$TOKEN") || {
    echo "SLACK_TS="
    echo "ERROR=Failed to post Slack message"
    exit 1
}

echo "SLACK_TS=$SLACK_TS"
