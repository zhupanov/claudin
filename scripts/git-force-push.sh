#!/usr/bin/env bash
# git-force-push.sh — Force-push the current branch with lease protection + recovery.
#
# Wraps `git push --force-with-lease` with the full recovery logic from
# /implement's Rebase + Re-bump Sub-procedure step 5:
#   - Try `git push --force-with-lease` once.
#   - On failure: refresh the local tracking ref (`git fetch origin <branch>`),
#     compare local HEAD vs origin/<branch>. If equal, the push actually landed
#     (rare race) — return success.
#   - If they differ, sleep 5s and retry the push ONCE.
#   - If the retry fails, return a structured "diverged_retry_failed" status so
#     the caller can bail.
#
# Usage:
#   git-force-push.sh
#
# Output (stdout, KEY=VALUE):
#   BRANCH=<name>
#   PUSHED=true|false
#   STATUS=pushed|noop_same_ref|diverged_retry_failed
#
# Exit codes:
#   0 — PUSHED=true (either pushed fresh or race-landed)
#   1 — PUSHED=false with STATUS=diverged_retry_failed (caller should bail)
#   2 — not on a named branch (detached HEAD / not a git repo)

set -euo pipefail

SLEEP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null); then
    echo "git-force-push.sh: not on a named branch" >&2
    exit 2
fi
echo "BRANCH=$BRANCH"

# First attempt.
if git push --force-with-lease; then
    echo "PUSHED=true"
    echo "STATUS=pushed"
    exit 0
fi

# Push failed. Refresh the tracking ref.
git fetch origin "$BRANCH" 2>/dev/null || true

# Compare local HEAD to origin/$BRANCH.
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "")

if [[ -n "$REMOTE" && "$LOCAL" == "$REMOTE" ]]; then
    # Remote accepted the push in the race; client didn't observe the success.
    echo "PUSHED=true"
    echo "STATUS=noop_same_ref"
    exit 0
fi

# Local and remote diverge. Sleep 5s and retry once.
"$SLEEP_SCRIPT_DIR/sleep-seconds.sh" 5 >/dev/null 2>&1 || sleep 5

if git push --force-with-lease; then
    echo "PUSHED=true"
    echo "STATUS=pushed"
    exit 0
fi

echo "PUSHED=false"
echo "STATUS=diverged_retry_failed"
exit 1
