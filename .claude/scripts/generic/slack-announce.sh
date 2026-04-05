#!/usr/bin/env bash
# slack-announce.sh — Post a Slack announcement for a PR.
#
# Resolves git identity, constructs a Slack message from PR metadata,
# posts via post-slack-message.sh, and saves the Slack timestamp to
# $TMPDIR/slack-ts.txt.
#
# Usage:
#   slack-announce.sh --pr NUMBER --tmpdir DIR --channel-id CHANNEL_ID
#
# Environment:
#   CLAUDIN_SLACK_BOT_TOKEN — required, the Slack bot token
#   CLAUDIN_SLACK_USER_ID   — optional Slack user ID (e.g., U12345678) for @-mentioning
#                     the PR author. If unset, the message is posted without a mention.
#
# Outputs to stdout:
#   SLACK_TS=<timestamp>     (on success)
#   SLACK_TS=                (on failure)
#   SLACK_ERROR=<message>    (on failure)
#
# Exit codes:
#   0 — message posted successfully
#   1 — CLAUDIN_SLACK_BOT_TOKEN not set
#   2 — failed to resolve PR metadata
#   3 — failed to post message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "Usage: slack-announce.sh --pr NUMBER --tmpdir DIR --channel-id CHANNEL_ID" >&2; }

PR_NUMBER=""
TMPDIR_PATH=""
CHANNEL_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR_NUMBER="${2:?--pr requires a value}"; shift 2 ;;
        --tmpdir) TMPDIR_PATH="${2:?--tmpdir requires a value}"; shift 2 ;;
        --channel-id) CHANNEL_ID="${2:?--channel-id requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 3 ;;
    esac
done

if [[ -z "$PR_NUMBER" ]] || [[ -z "$TMPDIR_PATH" ]] || [[ -z "$CHANNEL_ID" ]]; then
    echo "SLACK_TS="
    echo "SLACK_ERROR=--pr, --tmpdir, and --channel-id are required"
    usage; exit 3
fi

# --- Check token ---
if [[ -z "${CLAUDIN_SLACK_BOT_TOKEN:-}" ]]; then
    echo "SLACK_TS="
    echo "SLACK_ERROR=CLAUDIN_SLACK_BOT_TOKEN not set"
    exit 1
fi
CLEAN_TOKEN=$(echo -n "$CLAUDIN_SLACK_BOT_TOKEN" | tr -d '[:space:]')

# --- Resolve git identity ---
GIT_USER_NAME=$(git config user.name 2>/dev/null || echo "")
CLAUDIN_SLACK_USER_ID="${CLAUDIN_SLACK_USER_ID:-}"

# --- Fetch PR metadata and derive repo name from PR URL ---
set +e
PR_JSON=$(gh pr view "$PR_NUMBER" --json url,title,body 2>/dev/null)
set -e

PR_URL=$(echo "$PR_JSON" | jq -r '.url // empty' 2>/dev/null || echo "")
PR_TITLE=$(echo "$PR_JSON" | jq -r '.title // empty' 2>/dev/null || echo "")
PR_BODY=$(echo "$PR_JSON" | jq -r '.body // empty' 2>/dev/null || echo "")
REPO_NAME=$(echo "$PR_URL" | sed -E 's|.*/([^/]+)/pull/[0-9]+$|\1|')
# Guard: if sed didn't match (REPO_NAME still looks like a URL), treat as empty
if [[ "$REPO_NAME" == */* ]]; then
    REPO_NAME=""
fi

if [[ -z "$PR_URL" ]] || [[ -z "$PR_TITLE" ]] || [[ -z "$REPO_NAME" ]]; then
    echo "SLACK_TS="
    echo "SLACK_ERROR=Failed to resolve PR metadata"
    exit 2
fi

# --- Extract Summary bullets from PR body ---
# Get everything between "## Summary" and the next "##" heading or "<details>" block
SUMMARY_BULLETS=$(echo "$PR_BODY" | \
    sed -En '/^## Summary/,/^(## |<details>)/{ /^## Summary/d; /^(## |<details>)/d; p; }' | \
    sed 's/^- //' | \
    sed '/^[[:space:]]*$/d')

# --- Construct message ---
# post-slack-message.sh embeds the text via string interpolation into a JSON
# string (PAYLOAD="{... \"text\": \"$TEXT\"}"). We must pre-escape characters
# that would break JSON: backslashes, double quotes, and newlines.
# For the title, replace " with the left curly quote character to avoid JSON breakage.

LDQUOTE=$'\xe2\x80\x9c'  # U+201C "
BULLET=$'\xe2\x80\xa2'   # U+2022 •

SAFE_TITLE="${PR_TITLE//\"/${LDQUOTE}}"

# Line 1: mention + PR link
if [[ -n "$CLAUDIN_SLACK_USER_ID" ]]; then
    LINE1="<@${CLAUDIN_SLACK_USER_ID}>: FYI \`${REPO_NAME}\` <${PR_URL}|#${PR_NUMBER}> ${LDQUOTE}${SAFE_TITLE}${LDQUOTE}"
else
    LINE1="FYI \`${REPO_NAME}\` <${PR_URL}|#${PR_NUMBER}> ${LDQUOTE}${SAFE_TITLE}${LDQUOTE}"
fi

# Build bullet lines with actual newlines and bullet chars
BULLET_LINES=""
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ -z "$BULLET_LINES" ]]; then
        BULLET_LINES="${BULLET} ${line}"
    else
        BULLET_LINES="${BULLET_LINES}"$'\n'"${BULLET} ${line}"
    fi
done <<< "$SUMMARY_BULLETS"

# Combine: LINE1 + bullets (only add newline where content exists)
MESSAGE="${LINE1}"
if [[ -n "$BULLET_LINES" ]]; then
    MESSAGE="${MESSAGE}"$'\n'"${BULLET_LINES}"
fi

# --- Post to Slack ---
# post-slack-message.sh uses jq --arg for JSON construction, so pass raw text.
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
    echo "SLACK_ERROR=Failed to post Slack message (exit code $POST_EXIT)"
    exit 3
fi

# --- Save timestamp ---
echo "$SLACK_TS" > "$TMPDIR_PATH/slack-ts.txt"
echo "SLACK_TS=$SLACK_TS"
