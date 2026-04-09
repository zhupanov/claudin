#!/usr/bin/env bash
# drop-bump-commit.sh — Drop a terminal "Bump version to X.Y.Z" commit from HEAD.
#
# Narrow primitive used by /implement's Rebase + Re-bump Sub-procedure to
# strip a stale version-bump commit before rebasing onto latest main.
# Refuses to do anything destructive unless ALL of these hold:
#   1. Working tree is clean (no staged, unstaged, or untracked changes).
#   2. HEAD subject matches ^Bump version to [0-9]+\.[0-9]+\.[0-9]+$.
#   3. HEAD~1 exists (branch has at least 2 commits).
#   4. HEAD touches exactly one file: .claude-plugin/plugin.json.
#
# If any check fails, the script prints DROPPED=false and exits 0 (no-op).
# A stderr WARN line explains which guard refused the drop, for callers that
# want to surface it.
#
# Usage:
#   drop-bump-commit.sh
#
# Output (stdout, KEY=VALUE):
#   DROPPED=true|false
#   OLD_BUMP_SHA=<sha>   (only when DROPPED=true)
#
# Exit codes:
#   0 — success, including no-op cases (inspect DROPPED to know what happened)
#   1 — git error during the reset itself (rare)

set -uo pipefail
# Note: not using set -e — we handle errors explicitly so all no-op paths
# exit 0 with DROPPED=false, matching the contract used by callers.

# --- Guard 1: clean working tree ---
# Defense in depth: even though callers are expected to ensure the worktree
# is clean before invoking, this script refuses destructive `git reset --hard`
# if anything is uncommitted. `git status --porcelain` covers staged, unstaged,
# and untracked files — unlike `git diff-index --quiet` which skips untracked.
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "WARN: worktree has uncommitted changes; refusing to drop bump commit" >&2
    echo "DROPPED=false"
    exit 0
fi

# --- Guard 2: HEAD subject must be a bump commit ---
HEAD_SUBJECT=$(git log -1 --format=%s HEAD 2>/dev/null || true)
if ! [[ "$HEAD_SUBJECT" =~ ^Bump\ version\ to\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "DROPPED=false"
    exit 0
fi

# --- Guard 3: HEAD~1 must exist ---
if ! git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    echo "WARN: HEAD~1 does not exist; cannot drop the only commit on the branch" >&2
    echo "DROPPED=false"
    exit 0
fi

# --- Guard 4: commit must touch only allowed bump files ---
# Use diff --name-only against HEAD~1. A legitimate bump commit produced by
# apply-bump.sh stages .claude-plugin/plugin.json. Step 8a of /implement may
# additionally amend CHANGELOG.md into the same commit. Both are acceptable.
CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | sort)
ALLOWED_ONE=".claude-plugin/plugin.json"
ALLOWED_TWO=$'CHANGELOG.md\n.claude-plugin/plugin.json'
if [[ "$CHANGED_FILES" != "$ALLOWED_ONE" && "$CHANGED_FILES" != "$ALLOWED_TWO" ]]; then
    echo "WARN: HEAD subject matches bump pattern but commit touches unexpected files (changed: $CHANGED_FILES); refusing to drop" >&2
    echo "DROPPED=false"
    exit 0
fi

# --- All guards passed: capture SHA and drop ---
OLD_BUMP_SHA=$(git rev-parse HEAD)

if ! git reset --hard HEAD~1 >/dev/null 2>&1; then
    echo "ERROR: git reset --hard HEAD~1 failed" >&2
    exit 1
fi

echo "DROPPED=true"
echo "OLD_BUMP_SHA=$OLD_BUMP_SHA"
exit 0
