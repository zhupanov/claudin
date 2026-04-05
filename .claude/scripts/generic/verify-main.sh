#!/usr/bin/env bash
# verify-main.sh — Verify that main's HEAD matches the expected squash-merge commit.
#
# Checks git log -1 --oneline and compares the commit message against
# the expected squash-merge title (typically "<PR title> (#<PR number>)").
#
# Matching strategy (handles both normal and --admin merges):
#   1. Prefix match: commit message starts with the expected title (normal squash merge)
#   2. Suffix match: commit message ends with "(#N)" from the expected title
#      (--admin merge uses the first commit message instead of PR title, but
#      GitHub still appends the PR number suffix)
#
# Usage:
#   verify-main.sh --expected-title TEXT
#
# Arguments:
#   --expected-title — The expected commit title prefix to match against
#
# Outputs (key=value to stdout, always emitted via EXIT trap):
#   VERIFIED=true|false
#   COMMIT_HASH=<short hash>
#   COMMIT_MESSAGE=<commit message>
#
# Preconditions:
#   Caller must have already checked out and pulled main (e.g., via local-cleanup.sh).
#
# Exit codes:
#   0 — always (result communicated via VERIFIED output key)
#   2 — usage/argument error (no output emitted)

set -uo pipefail

usage() { echo "Usage: verify-main.sh --expected-title TEXT" >&2; }

# --- Parse arguments (before installing EXIT trap) ---
EXPECTED_TITLE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --expected-title) EXPECTED_TITLE="${2:?--expected-title requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

if [[ -z "$EXPECTED_TITLE" ]]; then
    echo "ERROR: --expected-title is required" >&2
    usage; exit 2
fi

# --- Output defaults ---
VERIFIED="false"
COMMIT_HASH=""
COMMIT_MESSAGE=""

# shellcheck disable=SC2329,SC2317  # invoked via EXIT trap
emit_output() {
    echo "VERIFIED=$VERIFIED"
    echo "COMMIT_HASH=$COMMIT_HASH"
    echo "COMMIT_MESSAGE=$COMMIT_MESSAGE"
}
trap 'emit_output' EXIT

# --- Get HEAD commit ---
LOG_OUTPUT=$(git log -1 --oneline 2>/dev/null || echo "")

if [[ -z "$LOG_OUTPUT" ]]; then
    COMMIT_MESSAGE="(no commits found)"
    exit 0
fi

# Parse hash and message from "abc1234 commit message here"
COMMIT_HASH="${LOG_OUTPUT%% *}"
COMMIT_MESSAGE="${LOG_OUTPUT#* }"

# --- Compare using prefix match, then PR number suffix fallback ---
# Strategy 1: prefix match (normal squash merge — PR title is the commit message)
if [[ "$COMMIT_MESSAGE" == "$EXPECTED_TITLE"* ]]; then
    VERIFIED="true"
else
    # Strategy 2: suffix match on PR number (--admin merge — commit message differs
    # but GitHub still appends "(#N)")
    # Extract the "(#N)" suffix from the expected title
    PR_SUFFIX=""
    if [[ "$EXPECTED_TITLE" =~ \(#[0-9]+\)$ ]]; then
        PR_SUFFIX="${BASH_REMATCH[0]}"
    fi

    if [[ -n "$PR_SUFFIX" && "$COMMIT_MESSAGE" == *"$PR_SUFFIX" ]]; then
        VERIFIED="true"
    fi
fi

exit 0
