#!/usr/bin/env bash
# check-review-changes.sh — Check if code review made any file changes.
#
# Detects staged changes, unstaged changes, and untracked files to
# determine if the code review step modified anything. Used to decide
# whether to run a second validation pass and create a review-fixes commit.
#
# Usage:
#   check-review-changes.sh
#
# Outputs (key=value to stdout):
#   FILES_CHANGED=true|false
#
# Exit codes:
#   0 — always

set -euo pipefail

FILES_CHANGED="false"

# Check for unstaged modifications (working tree vs index)
UNSTAGED=$(git diff --name-only 2>/dev/null || echo "")

# Check for staged modifications
STAGED=$(git diff --name-only --cached 2>/dev/null || echo "")

# Check for untracked files (review may create new test/helper files)
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || echo "")

if [[ -n "$UNSTAGED" ]] || [[ -n "$STAGED" ]] || [[ -n "$UNTRACKED" ]]; then
    FILES_CHANGED="true"
fi

echo "FILES_CHANGED=$FILES_CHANGED"
