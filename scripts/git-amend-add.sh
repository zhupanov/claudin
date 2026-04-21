#!/usr/bin/env bash
# git-amend-add.sh — Stage files and amend the previous commit (no message edit).
#
# Wraps `git add <files>` followed by `git commit --amend --no-edit`. Used by
# /implement Step 8a (CHANGELOG) and the Rebase + Re-bump Sub-procedure step 4a
# (skills/implement/references/rebase-rebump-subprocedure.md)
# to fold CHANGELOG.md updates into the preceding bump commit.
#
# Usage:
#   git-amend-add.sh <file> [<file> ...]
#
# Exit codes:
#   0  — success (files staged and amend commit created)
#   1  — usage error (no files given)
#   >0 — passthrough from `git add` or `git commit --amend` failure

set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "git-amend-add.sh: at least one file argument is required" >&2
    echo "usage: git-amend-add.sh <file> [<file> ...]" >&2
    exit 1
fi

git add -- "$@"
git commit --amend --no-edit
