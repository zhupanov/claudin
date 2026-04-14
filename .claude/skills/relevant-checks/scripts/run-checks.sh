#!/usr/bin/env bash
# Run validation checks relevant to modified files on the current branch.
# Delegates to pre-commit for file-type routing and linting.
# This script is private to the /relevant-checks skill.
# Note: -e intentionally omitted — pre-commit exit code is captured explicitly
# (PRE_COMMIT_EXIT) rather than aborting, so later checks can still run.
set -uo pipefail

# ---------------------------------------------------------------------------
# Pre-flight: ensure pre-commit is installed
# ---------------------------------------------------------------------------
command -v pre-commit >/dev/null 2>&1 || {
    echo "ERROR: pre-commit not found. Run: pip install pre-commit (or: make setup)"
    exit 1
}

REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "ERROR: not inside a git repository"; exit 1; }
cd "$REPO_ROOT" || exit 1

# ---------------------------------------------------------------------------
# Shared post-check function: claude-lint
# ---------------------------------------------------------------------------
run_post_checks() {
    if command -v claude-lint >/dev/null 2>&1; then
        echo ""
        echo "=== Running claude-lint ==="
        claude-lint "$REPO_ROOT"
        return $?
    else
        echo ""
        echo "WARNING: claude-lint not found on PATH — skipping"
    fi
}

# ---------------------------------------------------------------------------
# Determine changed files (union of branch diff + staged + unstaged + untracked)
# ---------------------------------------------------------------------------
# Only fall back to origin/main if local main is truly unavailable, not if the
# diff is just empty (which happens on a new branch with no commits yet — when
# there are no branch commits, main...HEAD returns empty, and we rely on the
# staged/unstaged/untracked diffs to capture working tree changes).
if git rev-parse --verify main >/dev/null 2>&1; then
    branch_diff="$(git diff --name-only main...HEAD 2>/dev/null || true)"
elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    branch_diff="$(git diff --name-only origin/main...HEAD 2>/dev/null || true)"
else
    branch_diff=""
fi

# Staged changes (files added to index but not yet committed)
staged_diff="$(git diff --cached --name-only 2>/dev/null || true)"

# Unstaged changes (modified but not yet staged)
unstaged_diff="$(git diff --name-only 2>/dev/null || true)"

# Untracked files (newly created, not yet staged — e.g., files written by Claude)
untracked="$(git ls-files --others --exclude-standard 2>/dev/null || true)"

# Union and deduplicate
MODIFIED_FILES="$(printf '%s\n%s\n%s\n%s' "$branch_diff" "$staged_diff" "$unstaged_diff" "$untracked" | sort -u | grep -v '^$' || true)"

if [ -z "$MODIFIED_FILES" ]; then
    echo "No modified files detected — no checks to run."
    exit 0
fi

# ---------------------------------------------------------------------------
# Build file array, filtering to files that exist on disk (deleted files from
# branch diff would cause pre-commit to fail with file-not-found errors).
# Uses a portable while-read loop instead of mapfile for macOS Bash 3.2 compat.
# ---------------------------------------------------------------------------
files=()
while IFS= read -r f; do
    if [ -f "$f" ]; then
        files+=("$f")
    fi
done <<< "$MODIFIED_FILES"

# ---------------------------------------------------------------------------
# If all changes are deletions (files[] empty but MODIFIED_FILES non-empty),
# pre-commit has nothing to lint, but claude-lint is exactly what we want —
# deletions are the most likely cause of structural regressions (deleted
# referenced scripts, removed SKILL.md, etc.). Run claude-lint before exiting.
# ---------------------------------------------------------------------------
if [ ${#files[@]} -eq 0 ]; then
    echo "No existing modified files to check (all changes are deletions)."
    run_post_checks
    exit $?
fi

# ---------------------------------------------------------------------------
# Run pre-commit on changed files. Pre-commit handles file-type routing via
# the types/files fields in .pre-commit-config.yaml — no manual gating needed.
# ---------------------------------------------------------------------------
echo "=== Running pre-commit on ${#files[@]} changed file(s) ==="
pre-commit run --files "${files[@]}"
PRE_COMMIT_EXIT=$?

if [ "$PRE_COMMIT_EXIT" -ne 0 ]; then
    exit "$PRE_COMMIT_EXIT"
fi

# ---------------------------------------------------------------------------
# Pre-commit succeeded — run claude-lint on the full repo.
# This catches structural regressions (frontmatter, references, dead scripts,
# etc.) that pre-commit's file-type linters cannot detect. Mirrors the same
# linter invoked by CI's claude-lint job, so developers can catch regressions
# locally before pushing.
# ---------------------------------------------------------------------------
run_post_checks
