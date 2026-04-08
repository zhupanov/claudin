#!/usr/bin/env bash
# post-pr-announce.sh — Post a PR announcement to Slack.
#
# Replaces the /post-pr skill. Composes: parse-pr-summary.sh →
# slack-announce.sh with $LARCH_SLACK_CHANNEL_ID.
#
# Note: This script does NOT perform bullet condensation (the former skill
# condensed > 3 bullets using LLM reasoning). In practice, /implement
# always creates PR bodies with ≤ 3 bullets, so condensation never fired. If
# a PR has > 3 bullets, a warning is emitted but the announcement proceeds
# with all bullets.
#
# Usage:
#   post-pr-announce.sh --pr <number>
#
# Arguments:
#   --pr — PR number to announce
#
# Outputs (key=value to stdout, always emitted via EXIT trap):
#   SLACK_TS=<value>    (Slack message timestamp on success)
#   SLACK_TS=           (empty on failure)
#
# Exit codes:
#   0 — announcement posted successfully
#   1 — LARCH_SLACK_BOT_TOKEN not set
#   2 — could not resolve PR metadata
#   3 — Slack announcement failed
#   4 — usage/argument error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "Usage: post-pr-announce.sh --pr <number>" >&2; }

# --- Output defaults (install trap BEFORE parsing to guarantee SLACK_TS= on all paths) ---
SLACK_TS=""

# shellcheck disable=SC2329,SC2317
emit_output() {
    echo "SLACK_TS=$SLACK_TS"
}
trap 'emit_output' EXIT

# --- Parse arguments ---
PR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 4 ;;
    esac
done

if [[ -z "$PR" ]]; then
    echo "ERROR: --pr is required" >&2
    usage; exit 4
fi

# --- Create temp directory ---
TMPDIR_OUTPUT=$("$SCRIPT_DIR/create-session-tmpdir.sh" --prefix claude-post-pr)
POST_PR_TMPDIR=$(echo "$TMPDIR_OUTPUT" | grep '^SESSION_TMPDIR=' | cut -d= -f2-)

if [[ -z "$POST_PR_TMPDIR" ]]; then
    echo "ERROR: Failed to create temp directory" >&2
    exit 3
fi

# --- Check bullet count (informational only, no condensation) ---
SUMMARY_OUTPUT=$("$SCRIPT_DIR/parse-pr-summary.sh" --pr "$PR" 2>/dev/null || echo "BULLET_COUNT=0")
BULLET_COUNT=$(echo "$SUMMARY_OUTPUT" | grep '^BULLET_COUNT=' | cut -d= -f2-)

if [[ "${BULLET_COUNT:-0}" -gt 3 ]]; then
    echo "WARNING: PR #$PR has $BULLET_COUNT summary bullets (> 3). Proceeding without condensation." >&2
fi

# --- Read Slack channel ---
SLACK_CHANNEL_ID="${LARCH_SLACK_CHANNEL_ID:-}"

if [[ -z "$SLACK_CHANNEL_ID" ]]; then
    echo "WARNING: LARCH_SLACK_CHANNEL_ID is not set. Slack announcement skipped." >&2
    "$SCRIPT_DIR/cleanup-tmpdir.sh" --dir "$POST_PR_TMPDIR" 2>/dev/null || true
    exit 0
fi

# --- Post to Slack ---
ANNOUNCE_OUTPUT=$("$SCRIPT_DIR/slack-announce.sh" --pr "$PR" --tmpdir "$POST_PR_TMPDIR" --channel-id "$SLACK_CHANNEL_ID" 2>&1)
ANNOUNCE_EXIT=$?

SLACK_TS=$(echo "$ANNOUNCE_OUTPUT" | grep '^SLACK_TS=' | cut -d= -f2-)

# --- Cleanup ---
"$SCRIPT_DIR/cleanup-tmpdir.sh" --dir "$POST_PR_TMPDIR" 2>/dev/null || true

if [[ $ANNOUNCE_EXIT -ne 0 ]]; then
    SLACK_TS=""
    exit "$ANNOUNCE_EXIT"
fi
if [[ -z "$SLACK_TS" ]]; then
    SLACK_TS=""
    exit 3
fi

exit 0
