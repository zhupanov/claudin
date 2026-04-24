#!/usr/bin/env bash
# post-issue-slack.sh — Post a one-line Slack message about an issue's state.
#
# Composes "<emoji> <https://github.com/$REPO/issues/$N|Issue #N> (<title>) — <status>[ — <detail>]"
# and delegates the API call to post-slack-message.sh. Resolves git user identity
# via `git config user.name` and passes it as --username so the post appears
# attributed to the human, not the bot.
#
# Usage:
#   post-issue-slack.sh --issue-number N --status STATUS --repo OWNER/REPO \
#       --token TOKEN --channel-id CHANNEL [--pr-url URL] [--detail TEXT]
#
# Arguments:
#   --issue-number  GitHub issue number (integer)
#   --status        One of: closed | pr-opened | blocked | user-input
#   --repo          OWNER/REPO (for link composition fallback if gh fails)
#   --token         Slack bot token
#   --channel-id    Slack channel ID
#   --pr-url        Optional PR URL (populates pr-opened status tail)
#   --detail        Optional free-form tail text appended after the base status
#
# Status-to-emoji map: closed=✅, pr-opened=📝, blocked=❌, user-input=❓.
#
# Output (KEY=value lines on stdout):
#   SLACK_TS=<timestamp>      (on success)
#   SLACK_TS=                 (on failure)
#   SLACK_ERROR=<message>     (on failure)
#
# Exit codes:
#   0 — message posted
#   1 — invalid arguments or post failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISSUE_NUMBER=""
STATUS=""
REPO=""
TOKEN=""
CHANNEL_ID=""
PR_URL=""
DETAIL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue-number) ISSUE_NUMBER="${2:?--issue-number requires a value}"; shift 2 ;;
        --status) STATUS="${2:?--status requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --token) TOKEN="${2:?--token requires a value}"; shift 2 ;;
        --channel-id) CHANNEL_ID="${2:?--channel-id requires a value}"; shift 2 ;;
        --pr-url) PR_URL="${2:?--pr-url requires a value}"; shift 2 ;;
        --detail) DETAIL="${2:?--detail requires a value}"; shift 2 ;;
        *) echo "SLACK_TS="; echo "SLACK_ERROR=Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$ISSUE_NUMBER" ]] || [[ -z "$STATUS" ]] || [[ -z "$REPO" ]] || [[ -z "$TOKEN" ]] || [[ -z "$CHANNEL_ID" ]]; then
    echo "SLACK_TS="
    echo "SLACK_ERROR=--issue-number, --status, --repo, --token, --channel-id are required"
    exit 1
fi

case "$STATUS" in
    closed|pr-opened|blocked|user-input) ;;
    *) echo "SLACK_TS="; echo "SLACK_ERROR=Invalid --status: $STATUS (want closed|pr-opened|blocked|user-input)"; exit 1 ;;
esac

# Emoji + base status summary
case "$STATUS" in
    closed)     EMOJI="✅"; STATUS_SUMMARY="closed" ;;
    pr-opened)  EMOJI="📝"; STATUS_SUMMARY="PR opened, awaiting merge" ;;
    blocked)    EMOJI="❌"; STATUS_SUMMARY="blocked" ;;
    user-input) EMOJI="❓"; STATUS_SUMMARY="needs user input" ;;
esac

# Fetch issue title + URL via gh (best-effort; fall back to repo-synthesized URL)
ISSUE_URL=""
ISSUE_TITLE=""
if command -v gh >/dev/null 2>&1; then
    set +e
    ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --json url,title 2>/dev/null)
    set -e
    if [[ -n "$ISSUE_JSON" ]]; then
        ISSUE_URL=$(echo "$ISSUE_JSON" | jq -r '.url // empty' 2>/dev/null || echo "")
        ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title // empty' 2>/dev/null || echo "")
    fi
fi
if [[ -z "$ISSUE_URL" ]]; then
    ISSUE_URL="https://github.com/${REPO}/issues/${ISSUE_NUMBER}"
fi

# Sanitize title for Slack mrkdwn link text: | < > are reserved.
# Replace double-quote with left-curly-quote (matches the pattern in the old slack-announce.sh).
LDQUOTE=$'\xe2\x80\x9c'
SAFE_TITLE="${ISSUE_TITLE//\"/${LDQUOTE}}"
SAFE_TITLE="${SAFE_TITLE//|/\\|}"
SAFE_TITLE="${SAFE_TITLE//</\\<}"
SAFE_TITLE="${SAFE_TITLE//>/\\>}"
[[ -z "$SAFE_TITLE" ]] && SAFE_TITLE="untitled"

# Compose link + title prefix
LINK="<${ISSUE_URL}|Issue #${ISSUE_NUMBER}>"

# Compose status tail
TAIL="$STATUS_SUMMARY"
if [[ "$STATUS" == "pr-opened" ]] && [[ -n "$PR_URL" ]]; then
    TAIL="PR <${PR_URL}|opened>, awaiting merge"
fi
if [[ -n "$DETAIL" ]]; then
    TAIL="${TAIL} — ${DETAIL}"
fi

MESSAGE="${EMOJI} ${LINK} (${SAFE_TITLE}) — ${TAIL}"

# Resolve git-user identity for --username
GIT_USER_NAME=$(git config user.name 2>/dev/null || echo "")

CLEAN_TOKEN=$(echo -n "$TOKEN" | tr -d '[:space:]')

# Delegate to shared poster
set +e
SLACK_TS=$(bash "$SCRIPT_DIR/post-slack-message.sh" \
    --channel-id "$CHANNEL_ID" \
    --text "$MESSAGE" \
    --username "$GIT_USER_NAME" \
    --token "$CLEAN_TOKEN" 2>/dev/null)
POST_EXIT=$?
set -e

if [[ $POST_EXIT -ne 0 ]] || [[ -z "$SLACK_TS" ]]; then
    echo "SLACK_TS="
    echo "SLACK_ERROR=Failed to post Slack message (exit $POST_EXIT)"
    exit 1
fi

echo "SLACK_TS=$SLACK_TS"
