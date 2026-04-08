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

NEW_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --new-version) NEW_VERSION="$2"; shift 2 ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$NEW_VERSION" ]]; then
  echo "ERROR=Missing required argument: --new-version" >&2
  exit 1
fi

if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR=--new-version '$NEW_VERSION' is not semver (expected X.Y.Z)" >&2
  exit 1
fi

PLUGIN_JSON="$PWD/.claude-plugin/plugin.json"
BACKUP="$PLUGIN_JSON.bump-backup"

# Step 1 (FIRST): Verify clean working tree.
# This MUST run before any mutation so the script can't trip over its own write.
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  echo "ERROR=Working tree has uncommitted changes; refusing to bump version. Commit or stash them first." >&2
  exit 1
fi
if ! git diff-index --quiet --cached HEAD -- 2>/dev/null; then
  echo "ERROR=Index has staged changes; refusing to bump version. Commit or unstage them first." >&2
  exit 1
fi

# Step 2: Validate plugin.json parses.
[[ -f "$PLUGIN_JSON" ]] || { echo "ERROR=$PLUGIN_JSON not found" >&2; exit 1; }
jq empty "$PLUGIN_JSON" 2>/dev/null || { echo "ERROR=$PLUGIN_JSON is not valid JSON" >&2; exit 1; }

# Step 3: Backup before mutation.
cp "$PLUGIN_JSON" "$BACKUP"

# Step 4: Atomic rewrite via jq + mv.
TMP_JSON="$PLUGIN_JSON.tmp.$$"
if ! jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$TMP_JSON"; then
  rm -f "$TMP_JSON" "$BACKUP"
  echo "ERROR=jq rewrite failed" >&2
  exit 1
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
