#!/usr/bin/env bash
# post-merged-emoji.sh — Add :merged: emoji to a Slack PR announcement.
#
# Replaces the /post-merged skill. Reads the Slack channel from
# repo-config.json and calls add-merged-emoji.sh.
#
# Usage:
#   post-merged-emoji.sh --slack-ts <timestamp>
#
# Arguments:
#   --slack-ts — Slack message timestamp (as returned by post-pr-announce.sh)
#
# Exit codes:
#   0 — emoji added successfully (or no-op if timestamp is empty)
#   1 — failed to add emoji (channel missing, token missing, API error)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "Usage: post-merged-emoji.sh --slack-ts <timestamp>" >&2; }

# --- Parse arguments ---
SLACK_TS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --slack-ts) SLACK_TS="${2:-}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

# --- Guard: empty timestamp is a no-op ---
if [[ -z "$SLACK_TS" ]]; then
    echo "WARNING: No Slack timestamp provided. Skipping :merged: emoji." >&2
    exit 0
fi

# --- Read Slack channel ---
CHANNEL_OUTPUT=$("$SCRIPT_DIR/read-slack-channel.sh")
SLACK_CHANNEL_ID=$(echo "$CHANNEL_OUTPUT" | grep '^SLACK_CHANNEL_ID=' | cut -d= -f2-)

if [[ -z "$SLACK_CHANNEL_ID" ]]; then
    echo "WARNING: repo-config.json missing or slackChannelId not set. Skipping :merged: emoji." >&2
    exit 1
fi

# --- Add emoji ---
"$SCRIPT_DIR/add-merged-emoji.sh" --slack-ts "$SLACK_TS" --channel-id "$SLACK_CHANNEL_ID"
