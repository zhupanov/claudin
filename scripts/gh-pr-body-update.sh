#!/usr/bin/env bash
# gh-pr-body-update.sh — Update a PR's body from a file.
#
# Wraps `gh pr edit --body-file` with structured output. Uses --body-file
# only (not inline --body) to avoid shell argument length limits with
# large PR bodies.
#
# Usage:
#   gh-pr-body-update.sh --pr <number> --body-file <path>
#
# Arguments:
#   --pr        — PR number
#   --body-file — Path to file containing the new PR body
#
# Outputs (key=value to stdout, always emitted via EXIT trap):
#   UPDATED=true|false
#   ERROR=<message>    (empty on success)
#
# Exit codes:
#   0 — update succeeded (UPDATED=true)
#   1 — usage/argument error (no output emitted)
#   2 — update failed (UPDATED=false, ERROR=<message> emitted via EXIT trap)

set -uo pipefail

usage() { echo "Usage: gh-pr-body-update.sh --pr <number> --body-file <path>" >&2; }

PR=""
BODY_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
        --body-file) BODY_FILE="${2:?--body-file requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$PR" ]] || [[ -z "$BODY_FILE" ]]; then
    echo "ERROR: --pr and --body-file are required" >&2
    usage; exit 1
fi

# --- Output defaults ---
UPDATED="false"
ERROR="gh-pr-body-update.sh exited unexpectedly"

# shellcheck disable=SC2329,SC2317
emit_output() {
    echo "UPDATED=$UPDATED"
    echo "ERROR=$ERROR"
}
trap 'emit_output' EXIT

if [[ ! -f "$BODY_FILE" ]]; then
    ERROR="body file not found: $BODY_FILE"
    exit 2
fi

OUTPUT=$(gh pr edit "$PR" --body-file "$BODY_FILE" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    UPDATED="true"
    ERROR=""
    exit 0
else
    UPDATED="false"
    OUTPUT="${OUTPUT//$'\n'/ }"
    ERROR="gh pr edit failed (exit $EXIT_CODE): $OUTPUT"
    exit 2
fi
