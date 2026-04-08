#!/usr/bin/env bash
# git-branch-info.sh — Get current HEAD SHA and branch name.
#
# Wraps `git rev-parse --short HEAD` and `git branch --show-current`
# into a single script with KEY=value output.
#
# Usage:
#   git-branch-info.sh
#
# Outputs (key=value to stdout):
#   HEAD_SHA=<short hash>
#   CURRENT_BRANCH=<branch name>  (empty string if detached HEAD)
#
# Exit codes:
#   0 — success
#   1 — not in a git repository

set -euo pipefail

HEAD_SHA=$(git rev-parse --short HEAD)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

echo "HEAD_SHA=$HEAD_SHA"
echo "CURRENT_BRANCH=$CURRENT_BRANCH"
