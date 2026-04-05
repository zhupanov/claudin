#!/usr/bin/env bash
# read-slack-channel.sh — Read the Slack channel ID from repo-config.json.
#
# Usage:
#   read-slack-channel.sh [--config <path>]
#
# Options:
#   --config <path>  Path to repo-config.json (default: .claude/repo-config.json relative to CWD)
#
# Output (stdout, KEY=VALUE):
#   SLACK_CHANNEL_ID=<value>   The channel ID, or empty if file/key missing
#
# Exit codes:
#   0 — success (SLACK_CHANNEL_ID may be empty if file/key missing)
#   1 — config file exists but cannot be parsed (broken JSON or jq failure)

set -euo pipefail

CONFIG=".claude/repo-config.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$CONFIG" ]]; then
  echo "SLACK_CHANNEL_ID="
  exit 0
fi

if ! CHANNEL_ID=$(jq -r '.slackChannelId // empty' "$CONFIG" 2>/dev/null); then
  echo "ERROR=Failed to parse $CONFIG" >&2
  exit 1
fi

echo "SLACK_CHANNEL_ID=$CHANNEL_ID"
