#!/usr/bin/env bash
# apply-bump.sh — Apply a computed semver bump to .claude-plugin/plugin.json.
#
# Contract:
#   - FIRST: verify working tree is clean (fails on any staged or unstaged changes).
#   - Validate .claude-plugin/plugin.json with jq.
#   - Back up plugin.json.
#   - Rewrite .version field atomically via jq + mv.
#   - git add + commit with message "Bump version to <new-version>".
#   - Roll back from backup if git commit fails.
#
# Usage:
#   apply-bump.sh --new-version <x.y.z>
#
# Output (stdout):
#   APPLIED=true|false
#   COMMIT_SHA=<sha>             (if APPLIED=true)
#   ERROR=<message>              (if APPLIED=false)
#
# Exit codes: 0 on success, 1 on invalid args / validation / dirty worktree / commit failure.

set -euo pipefail

# fail MESSAGE — emit APPLIED=false / ERROR=MESSAGE on stdout and exit 1.
# Used for all non-rollback failure paths so callers see a consistent
# machine-parseable contract on stdout.
fail() {
  echo "APPLIED=false"
  echo "ERROR=$1"
  exit 1
}

NEW_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --new-version)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        fail "Missing value for --new-version"
      fi
      NEW_VERSION="$2"
      shift 2
      ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [[ -z "$NEW_VERSION" ]]; then
  fail "Missing required argument: --new-version"
fi

if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "--new-version '$NEW_VERSION' is not semver (expected X.Y.Z)"
fi

PLUGIN_JSON="$PWD/.claude-plugin/plugin.json"
BACKUP="$PLUGIN_JSON.bump-backup"

# Step 1 (FIRST): Verify clean working tree.
# This MUST run before any mutation so the script can't trip over its own write.
# `git status --porcelain` covers tracked changes (staged and unstaged) AND
# untracked files — unlike `git diff-index --quiet HEAD --` which silently
# ignores untracked entries.
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  fail "Working tree is not clean (staged, unstaged, or untracked changes present); refusing to bump version. Commit, stash, or clean them first."
fi

# Step 2: Validate plugin.json parses.
[[ -f "$PLUGIN_JSON" ]] || fail "$PLUGIN_JSON not found"
jq empty "$PLUGIN_JSON" 2>/dev/null || fail "$PLUGIN_JSON is not valid JSON"

# Step 3: Backup before mutation.
cp "$PLUGIN_JSON" "$BACKUP"

# Step 4: Atomic rewrite via jq + mv.
TMP_JSON="$PLUGIN_JSON.tmp.$$"
if ! jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$TMP_JSON"; then
  rm -f "$TMP_JSON" "$BACKUP"
  fail "jq rewrite failed"
fi
mv "$TMP_JSON" "$PLUGIN_JSON"

# Step 5: Stage and commit.
git add "$PLUGIN_JSON"
COMMIT_MSG="Bump version to $NEW_VERSION"
if git commit -m "$COMMIT_MSG" --quiet; then
  # Success — remove backup, emit result.
  rm -f "$BACKUP"
  COMMIT_SHA=$(git rev-parse HEAD)
  echo "APPLIED=true"
  echo "COMMIT_SHA=$COMMIT_SHA"
  exit 0
fi

# Step 6: Rollback on commit failure.
# Restore from backup, unstage the file.
mv "$BACKUP" "$PLUGIN_JSON"
git reset HEAD "$PLUGIN_JSON" >/dev/null 2>&1 || true
echo "APPLIED=false"
echo "ERROR=git commit failed; rolled back $PLUGIN_JSON from backup"
exit 1
