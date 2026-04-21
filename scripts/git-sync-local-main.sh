#!/usr/bin/env bash
# git-sync-local-main.sh — Fast-forward local `main` ref to `origin/main`.
#
# Silent no-op when the local `main` ref does not exist. Used by the
# Rebase + Re-bump Sub-procedure step 3
# (skills/implement/references/rebase-rebump-subprocedure.md) so that
# `classify-bump.sh`'s merge-base computation resolves against the latest
# remote base.
#
# Never run on `main` itself — `git branch -f` of the current branch fails.
# /implement's Step 10 and Step 12 rebase loops always run on a feature branch.
#
# Usage:
#   git-sync-local-main.sh
#
# Output (stdout):
#   RESULT=updated|absent|already_current
#
# Exit codes:
#   0 — success (including the silent no-op case)
#   1 — invoked while on `main` (guard against accidental self-update)

set -euo pipefail

CURRENT=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$CURRENT" == "main" ]]; then
    echo "git-sync-local-main.sh: refusing to update local 'main' while checked out on main" >&2
    exit 1
fi

if ! git rev-parse --verify main >/dev/null 2>&1; then
    echo "RESULT=absent"
    exit 0
fi

# Check if local main already matches origin/main.
LOCAL_MAIN=$(git rev-parse main 2>/dev/null || echo "")
REMOTE_MAIN=$(git rev-parse origin/main 2>/dev/null || echo "")
if [[ -n "$LOCAL_MAIN" && "$LOCAL_MAIN" == "$REMOTE_MAIN" ]]; then
    echo "RESULT=already_current"
    exit 0
fi

git branch -f main origin/main
echo "RESULT=updated"
