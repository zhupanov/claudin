#!/usr/bin/env bash
# post-merged-emoji.sh — Add :merged: emoji to a Slack PR announcement.
#
# Replaces the /post-merged skill. Reads $CLAUDIN_SLACK_CHANNEL_ID
# and calls add-merged-emoji.sh.
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
SLACK_CHANNEL_ID="${CLAUDIN_SLACK_CHANNEL_ID:-}"

if [[ -z "$SLACK_CHANNEL_ID" ]]; then
    echo "WARNING: CLAUDIN_SLACK_CHANNEL_ID is not set. Skipping :merged: emoji." >&2
    exit 1
fi

# --- Add emoji ---
"$SCRIPT_DIR/add-merged-emoji.sh" --slack-ts "$SLACK_TS" --channel-id "$SLACK_CHANNEL_ID"
