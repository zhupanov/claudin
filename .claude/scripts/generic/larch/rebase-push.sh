#!/usr/bin/env bash
# rebase-push.sh — Rebase onto origin/main and optionally force-push with lease.
#
# Fetches origin/main, rebases, and (unless --no-push) pushes. Reports
# conflicts and push failures via exit codes.
#
# Usage:
#   rebase-push.sh [--continue] [--no-push]
#
# Flags:
#   --continue — Continue an in-progress rebase instead of starting a new one.
#                Skips fetch and runs `git rebase --continue` instead of
#                `git rebase origin/main`. Caller must resolve conflicts and
#                stage files before invoking with --continue.
#   --no-push  — Skip the push step after a successful rebase. Used by
#                /implement for local-only freshness rebases where the branch
#                has not yet been pushed. In this mode, conflicts are aborted
#                immediately (exit 1) instead of left in progress.
#
# Exit codes:
#   0 — rebase (and push, unless --no-push) succeeded
#   1 — rebase failed with conflicts
#       Default mode: rebase left in progress (CONFLICT_FILES= on stdout)
#       --no-push mode: rebase aborted, branch restored to pre-rebase state
#   2 — push --force-with-lease failed (PUSH_ERROR= on stderr, caller should retry after fetch)
#       Not possible in --no-push mode.
#   3 — rebase failed for non-conflict reasons (REBASE_ERROR= on stderr)
#       In normal mode: rebase is aborted.
#       In --continue mode: rebase is left in progress (caller can inspect/retry).
#       In --no-push mode: rebase is aborted.
#
# Stdout on exit 1 (default mode only):
#   CONFLICT_FILES=<comma-separated list of conflicted files>
#
# Note: On exit 1 in default mode, the rebase is left in progress so the
# caller can resolve conflicts and run `rebase-push.sh --continue`. On exit 1
# in --no-push mode, the rebase is aborted (caller does not resolve conflicts).
# On exit 3 in normal mode, the rebase is aborted. On exit 3 in --continue
# mode, the rebase is left in progress to avoid destroying already-resolved work.

set -uo pipefail
# Note: not using set -e — we need to capture exit codes explicitly

# --- Parse flags ---
CONTINUE_MODE=false
NO_PUSH=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --continue) CONTINUE_MODE=true; shift ;;
        --no-push) NO_PUSH=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ "$CONTINUE_MODE" == "true" && "$NO_PUSH" == "true" ]]; then
    echo "REBASE_ERROR=--continue and --no-push cannot be used together" >&2
    exit 3
fi

if [[ "$CONTINUE_MODE" == "true" ]]; then
    # --- Guard: must have a rebase in progress ---
    GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
    if [[ -z "$GIT_DIR" || (! -d "$GIT_DIR/rebase-merge" && ! -d "$GIT_DIR/rebase-apply") ]]; then
        echo "REBASE_ERROR=--continue called but no rebase is in progress" >&2
        exit 3
    fi

    # --- Continue an in-progress rebase (GIT_EDITOR=true prevents editor hang) ---
    REBASE_OUTPUT=$(GIT_EDITOR=true git rebase --continue 2>&1)
    REBASE_EXIT=$?
else
    # --- Guard: must be on a branch, not detached HEAD ---
    if ! git symbolic-ref --quiet HEAD > /dev/null 2>&1; then
        echo "REBASE_ERROR=Not on a branch (detached HEAD)" >&2
        exit 3
    fi

    # --- Fetch latest main ---
    # In --no-push mode, fetch failure is fatal (the whole point is freshness).
    # In default mode, fetch failure is tolerated to allow rebasing against cached origin/main.
    if [[ "$NO_PUSH" == "true" ]]; then
        if ! git fetch origin main --quiet 2>/dev/null; then
            echo "REBASE_ERROR=git fetch origin main failed (network/auth issue)" >&2
            exit 3
        fi
    else
        git fetch origin main --quiet 2>/dev/null || true
    fi

    # --- Attempt rebase ---
    REBASE_OUTPUT=$(git rebase origin/main 2>&1)
    REBASE_EXIT=$?
fi

if [[ $REBASE_EXIT -ne 0 ]]; then
    # Check if there are conflicts
    CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    if [[ -n "$CONFLICT_FILES" ]]; then
        if [[ "$NO_PUSH" == "true" ]]; then
            # In --no-push mode, abort immediately — caller does not resolve conflicts
            git rebase --abort 2>/dev/null || true
            exit 1
        fi
        echo "CONFLICT_FILES=$CONFLICT_FILES"
        # Leave the rebase in progress so caller can resolve and --continue
        exit 1
    else
        # Rebase failed for another reason (not conflicts)
        # Sanitize multi-line git output to single line for key=value protocol
        REBASE_OUTPUT="${REBASE_OUTPUT//$'\n'/ }"
        echo "REBASE_ERROR=$REBASE_OUTPUT" >&2
        if [[ "$CONTINUE_MODE" == "true" ]]; then
            # In --continue mode, leave rebase in progress to avoid destroying
            # already-resolved work. Caller can inspect and retry.
            exit 3
        else
            git rebase --abort 2>/dev/null || true
            exit 3
        fi
    fi
fi

# --- Skip push in --no-push mode ---
if [[ "$NO_PUSH" == "true" ]]; then
    exit 0
fi

# --- Attempt force-push ---
PUSH_OUTPUT=$(git push --force-with-lease 2>&1)
PUSH_EXIT=$?

if [[ $PUSH_EXIT -ne 0 ]]; then
    PUSH_OUTPUT="${PUSH_OUTPUT//$'\n'/ }"
    echo "PUSH_ERROR=$PUSH_OUTPUT" >&2
    exit 2
fi

exit 0
