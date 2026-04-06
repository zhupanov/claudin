#!/usr/bin/env bash
# local-cleanup.sh — Post-merge local cleanup: switch to main and delete feature branch.
#
# Switches to main, fetches and pulls the latest, then deletes the
# specified feature branch. Each action is logged to stderr for
# user-visible progress. Treats branch deletion failure as non-fatal
# (the branch may have already been deleted).
#
# Usage:
#   local-cleanup.sh --branch BRANCH_NAME
#
# Arguments:
#   --branch — Name of the feature branch to delete (required, must not be "main")
#
# Outputs (key=value to stdout, always emitted via EXIT trap):
#   CLEANUP_SUCCESS=true|false
#   CURRENT_BRANCH=<branch name after cleanup>
#   BRANCH_DELETED=true|false
#
# Exit codes:
#   0 — always (result communicated via output keys)
#   1 — usage/argument error (no output emitted)

set -uo pipefail

usage() { echo "Usage: local-cleanup.sh --branch BRANCH_NAME" >&2; }

# --- Parse arguments (before installing EXIT trap) ---
BRANCH_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch) BRANCH_NAME="${2:?--branch requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$BRANCH_NAME" ]]; then
    echo "ERROR: --branch is required" >&2
    usage; exit 1
fi

if [[ "$BRANCH_NAME" == "main" ]]; then
    echo "ERROR: --branch must not be 'main'" >&2
    exit 1
fi

# --- Output defaults (emitted via trap on any exit after validation) ---
CLEANUP_SUCCESS="false"
CURRENT_BRANCH="unknown"
BRANCH_DELETED="false"

# shellcheck disable=SC2329,SC2317  # invoked via EXIT trap
emit_output() {
    echo "CLEANUP_SUCCESS=$CLEANUP_SUCCESS"
    echo "CURRENT_BRANCH=$CURRENT_BRANCH"
    echo "BRANCH_DELETED=$BRANCH_DELETED"
}
trap 'emit_output' EXIT

# --- Step 1: Checkout main ---
echo "🔄 Switching to main..." >&2
if ! git checkout main >/dev/null 2>&1; then
    echo "❌ Failed to checkout main" >&2
    CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "unknown")
    exit 0
fi
CURRENT_BRANCH="main"

# --- Step 2: Fetch origin main ---
echo "🔄 Fetching origin main..." >&2
if ! git fetch origin main >/dev/null 2>&1; then
    echo "⚠ Failed to fetch origin main (continuing)" >&2
fi

# --- Step 3: Pull origin main ---
echo "🔄 Pulling latest main..." >&2
if ! git pull origin main >/dev/null 2>&1; then
    echo "❌ Failed to pull origin main" >&2
    exit 0
fi

# --- Step 4: Delete feature branch ---
echo "🔄 Deleting local branch $BRANCH_NAME..." >&2
if git branch -D "$BRANCH_NAME" >/dev/null 2>&1; then
    BRANCH_DELETED="true"
else
    echo "⚠ Failed to delete branch $BRANCH_NAME (may already be deleted)" >&2
    BRANCH_DELETED="false"
fi

CLEANUP_SUCCESS="true"
echo "✅ Local cleanup complete" >&2
exit 0
