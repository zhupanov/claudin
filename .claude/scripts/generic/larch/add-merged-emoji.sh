#!/usr/bin/env bash
# add-merged-emoji.sh — Add :merged: emoji to a Slack PR announcement.
#
# Wraps add-slack-emoji.sh with token cleaning.
# This wrapper exists so that callers (skills, ad-hoc commands) can invoke
# it without $() command substitution, which triggers Claude Code's
# interactive permission prompt.
#
# Usage:
#   add-merged-emoji.sh --slack-ts TIMESTAMP --channel-id CHANNEL_ID
#
# Environment:
#   LARCH_SLACK_BOT_TOKEN — required
#
# Exit codes:
#   0 — emoji added successfully
#   1 — LARCH_SLACK_BOT_TOKEN not set
#   2 — missing arguments
#   3 — add-slack-emoji.sh failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "Usage: add-merged-emoji.sh --slack-ts TIMESTAMP --channel-id CHANNEL_ID" >&2; }

SLACK_TS=""
CHANNEL_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --slack-ts) SLACK_TS="${2:?--slack-ts requires a value}"; shift 2 ;;
        --channel-id) CHANNEL_ID="${2:?--channel-id requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

if [[ -z "$SLACK_TS" ]] || [[ -z "$CHANNEL_ID" ]]; then
    echo "ERROR: --slack-ts and --channel-id are required" >&2
    usage; exit 2
fi

if [[ -z "${LARCH_SLACK_BOT_TOKEN:-}" ]]; then
    echo "⚠ LARCH_SLACK_BOT_TOKEN not set. Skipping :merged: emoji."
    exit 1
fi

CLEAN_TOKEN=$(echo -n "$LARCH_SLACK_BOT_TOKEN" | tr -d '[:space:]')

bash "$SCRIPT_DIR/add-slack-emoji.sh" \
    --channel-id "$CHANNEL_ID" \
    --emoji ":merged:" \
    --slack_timestamp "$SLACK_TS" \
    --token "$CLEAN_TOKEN"
