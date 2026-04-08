#!/usr/bin/env bash
# preflight.sh — Pre-skill sanity checks.
#
# Default: verify on main, clean working tree, then fetch+rebase to latest main.
# With --skip-branch-check: skip on-main and clean-status checks, only fetch.
#
# Usage:
#   preflight.sh [--skip-branch-check]
#
# Exit codes:
#   0 — all checks passed
#   1 — not on main branch (only without --skip-branch-check)
#   2 — dirty working tree (only without --skip-branch-check)
#   3 — git fetch or rebase failed

set -euo pipefail

SKIP_BRANCH_CHECK=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-branch-check) SKIP_BRANCH_CHECK=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 3 ;;
    esac
done

if [[ "$SKIP_BRANCH_CHECK" == "false" ]]; then
    # Check on main
    CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        echo "PREFLIGHT=fail"
        echo "PREFLIGHT_ERROR=Not on main branch (on '$CURRENT_BRANCH'). Switch to main first, or pass --skip-branch-check."
        exit 1
    fi

    # Check clean status
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        echo "PREFLIGHT=fail"
        echo "PREFLIGHT_ERROR=Working tree is not clean. Commit or stash changes first."
        exit 2
    fi

    # Fetch and rebase main to latest
    if ! git fetch origin main --quiet 2>/dev/null; then
        echo "PREFLIGHT=fail"
        echo "PREFLIGHT_ERROR=git fetch origin main failed."
        exit 3
    fi
    if ! git rebase origin/main --quiet 2>/dev/null; then
        echo "PREFLIGHT=fail"
        echo "PREFLIGHT_ERROR=git rebase origin/main failed."
        exit 3
    fi
else
    # Skip branch/status checks, only fetch to ensure origin/main is current
    if ! git fetch origin main --quiet 2>/dev/null; then
        echo "PREFLIGHT=fail"
        echo "PREFLIGHT_ERROR=git fetch origin main failed."
        exit 3
    fi
fi

echo "PREFLIGHT=ok"
