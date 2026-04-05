#!/bin/bash
# post-slack-message.sh — Post a message to Slack via the chat.postMessage API.
#
# Usage:
#   post-slack-message.sh --channel-id CHANNEL_ID --text "Message" \
#       [--username "Name"] [--slack_timestamp "timestamp"] --token "SLACK_TOKEN"
#
# Arguments:
#   --channel-id        Slack channel ID (e.g., C12345678)
#   --text              Message text (Slack mrkdwn format)
#   --token             Slack bot token
#   --username          Optional display name for the bot
#   --slack_timestamp   Optional thread timestamp (replies in thread)
#
# Outputs to stdout:
#   Slack message timestamp (on success)
#
# Exit codes:
#   0 — message posted successfully
#   1 — missing arguments or API failure

set -euo pipefail

CHANNEL_ID=""
TEXT=""
USERNAME=""
SLACK_TIMESTAMP=""
TOKEN=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --channel-id) CHANNEL_ID="$2"; shift ;;
    --text) TEXT="$2"; shift ;;
    --username) USERNAME="$2"; shift ;;
    --slack_timestamp) SLACK_TIMESTAMP="$2"; shift ;;
    --token) TOKEN="$2"; shift ;;
    *) echo "Unknown parameter: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ -z "$CHANNEL_ID" || -z "$TEXT" || -z "$TOKEN" ]]; then
  echo "Error: Missing required arguments" >&2
  echo "Usage: $0 --channel-id CHANNEL_ID --text \"Message\" --token \"SLACK_TOKEN\"" >&2
  exit 1
fi

# Construct JSON payload
PAYLOAD="{\"channel\": \"$CHANNEL_ID\", \"text\": \"$TEXT\""
if [[ -n "$USERNAME" ]]; then
  PAYLOAD="$PAYLOAD, \"username\": \"$USERNAME\""
fi
if [[ -n "$SLACK_TIMESTAMP" ]]; then
  PAYLOAD="$PAYLOAD, \"thread_ts\": \"$SLACK_TIMESTAMP\""
fi
PAYLOAD="$PAYLOAD}"

# Send message to Slack
response=$(curl -s -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "$PAYLOAD")

if echo "$response" | grep -q '"ok":true'; then
  echo "$response" | jq -r '.ts'
else
  echo "Failed to post Slack message: $response" >&2
  exit 1
fi
