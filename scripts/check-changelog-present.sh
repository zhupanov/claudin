#!/usr/bin/env bash
# check-changelog-present.sh — Test for CHANGELOG.md at the repo root.
#
# Usage:
#   check-changelog-present.sh
#
# Output (stdout, KEY=VALUE):
#   CHANGELOG_PRESENT=true|false
#
# Always exits 0 — presence is informational, not an error condition.
# Resolves the repo root via `git rev-parse --show-toplevel`; falls back to
# $PWD when not inside a git work tree (defensive: /implement Step 8a always
# runs inside a git repo, but keep the script standalone-callable).

set -euo pipefail

if root=$(git rev-parse --show-toplevel 2>/dev/null); then
    :
else
    root=$PWD
fi

if [[ -f "$root/CHANGELOG.md" ]]; then
    echo "CHANGELOG_PRESENT=true"
else
    echo "CHANGELOG_PRESENT=false"
fi
