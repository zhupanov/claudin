#!/bin/bash
# add-slack-emoji.sh — Add an emoji reaction to a Slack message.
#
# Usage:
#   add-slack-emoji.sh --channel-id CHANNEL_ID --emoji ":emoji:" \
#       --slack_timestamp "timestamp" --token "SLACK_TOKEN"
#
# Arguments:
#   --channel-id        Slack channel ID (e.g., C12345678)
#   --emoji             Emoji name with colons (e.g., :merged:)
#   --slack_timestamp   Message timestamp to react to
#   --token             Slack bot token
#
# Outputs to stdout:
#   Emoji name (on success)
#
# Exit codes:
#   0 — emoji added successfully
#   1 — missing arguments or API failure

set -euo pipefail

CHANNEL_ID=""
EMOJI=""
SLACK_TIMESTAMP=""
TOKEN=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --channel-id) CHANNEL_ID="$2"; shift ;;
    --emoji) EMOJI="$2"; shift ;;
    --slack_timestamp) SLACK_TIMESTAMP="$2"; shift ;;
    --token) TOKEN="$2"; shift ;;
    *) echo "Unknown parameter: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ -z "$CHANNEL_ID" || -z "$EMOJI" || -z "$SLACK_TIMESTAMP" || -z "$TOKEN" ]]; then
  echo "Error: Missing required arguments" >&2
  echo "Usage: $0 --channel-id CHANNEL_ID --emoji \":emoji:\" --slack_timestamp \"timestamp\" --token \"SLACK_TOKEN\"" >&2
  exit 1
fi

# Remove ':' from emoji for API
EMOJI_NAME="${EMOJI#:}"
EMOJI_NAME="${EMOJI_NAME%:}"

# Construct JSON payload safely using jq
PAYLOAD=$(jq -n \
  --arg channel "$CHANNEL_ID" \
  --arg name "$EMOJI_NAME" \
  --arg timestamp "$SLACK_TIMESTAMP" \
  '{channel: $channel, name: $name, timestamp: $timestamp}')

# Add emoji using reactions.add
response=$(curl -s -X POST https://slack.com/api/reactions.add \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "$PAYLOAD")

if echo "$response" | grep -q '"ok":true'; then
  echo "$EMOJI_NAME"
else
  echo "Failed to add emoji: $response" >&2
  exit 1
fi
