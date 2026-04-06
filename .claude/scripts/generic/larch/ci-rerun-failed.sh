#!/usr/bin/env bash
# ci-rerun-failed.sh — Rerun failed jobs in a GitHub Actions workflow run.
#
# Wraps `gh run rerun --failed` with structured output. The caller is
# responsible for any sleep/delay before invoking this script (separation
# of concerns: timing policy belongs to the orchestrator).
#
# Usage:
#   ci-rerun-failed.sh --run-id ID --repo OWNER/REPO
#
# Arguments:
#   --run-id — The GitHub Actions workflow run ID to rerun
#   --repo   — Owner/repo identifier (e.g., "myorg/myrepo")
#
# Outputs (key=value to stdout, always emitted via EXIT trap):
#   RERUN_SUBMITTED=true|false
#   ERROR=<message>    (empty string on success)
#
# Exit codes:
#   0 — always (result communicated via output keys)
#   1 — usage/argument error (no output emitted)

set -uo pipefail

usage() { echo "Usage: ci-rerun-failed.sh --run-id ID --repo OWNER/REPO" >&2; }

# --- Parse arguments (before installing EXIT trap) ---
RUN_ID=""
REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id) RUN_ID="${2:?--run-id requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$RUN_ID" ]] || [[ -z "$REPO" ]]; then
    echo "ERROR: --run-id and --repo are required" >&2
    usage; exit 1
fi

# --- Output defaults ---
RERUN_SUBMITTED="false"
ERROR="ci-rerun-failed.sh exited unexpectedly"

# shellcheck disable=SC2329,SC2317  # invoked via EXIT trap
emit_output() {
    echo "RERUN_SUBMITTED=$RERUN_SUBMITTED"
    echo "ERROR=$ERROR"
}
trap 'emit_output' EXIT

# --- Attempt rerun ---
RERUN_OUTPUT=$(gh run rerun "$RUN_ID" --failed --repo "$REPO" 2>&1)
RERUN_EXIT=$?

if [[ $RERUN_EXIT -eq 0 ]]; then
    RERUN_SUBMITTED="true"
    ERROR=""
else
    RERUN_SUBMITTED="false"
    ERROR="gh run rerun failed (exit $RERUN_EXIT): $RERUN_OUTPUT"
fi

exit 0
