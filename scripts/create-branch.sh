#!/usr/bin/env bash
# create-branch.sh — Branch creation for /design skill.
#
# Two modes:
#   --check          Output current branch state (no side effects)
#   --branch NAME    Create a new branch from latest origin/main
#
# Usage:
#   create-branch.sh --check
#   create-branch.sh --branch <branch-name>
#
# Outputs (key=value to stdout):
#   --check mode:
#     CURRENT_BRANCH=<name>     (empty if detached HEAD)
#     IS_MAIN=true|false
#     IS_USER_BRANCH=true|false
#     USER_PREFIX=<value>       (derived from git config user.name)
#
#   --branch mode:
#     BRANCH_NAME=<name>
#     ACTION=created
#
# Exit codes:
#   0 — success
#   1 — branch already exists (--branch mode only)
#   2 — git operation failed

set -euo pipefail

usage() { echo "Usage: create-branch.sh --check | create-branch.sh --branch NAME" >&2; }

# Derive user prefix from git config user.name:
# lowercase, spaces→hyphens, strip non-alphanumeric-hyphens, truncate to 20 chars, fallback "dev"
derive_user_prefix() {
    local raw
    raw=$(git config user.name 2>/dev/null || echo "")
    if [[ -z "$raw" ]]; then
        echo "dev"
        return
    fi
    local sanitized
    sanitized=$(printf '%s\n' "$raw" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g' | head -c 20 | sed 's/-*$//')
    if [[ -z "$sanitized" ]]; then
        echo "dev"
        return
    fi
    echo "$sanitized"
}

MODE=""
BRANCH_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --branch) MODE="create"; BRANCH_NAME="${2:?--branch requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "ERROR: --check or --branch is required" >&2
    usage; exit 2
fi

USER_PREFIX=$(derive_user_prefix)

if [[ "$MODE" == "check" ]]; then
    # --- Check mode: report current branch state ---
    CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

    IS_MAIN="false"
    IS_USER_BRANCH="false"

    if [[ -z "$CURRENT_BRANCH" ]] || [[ "$CURRENT_BRANCH" == "main" ]]; then
        IS_MAIN="true"
    elif [[ "$CURRENT_BRANCH" == "${USER_PREFIX}"/* ]]; then
        IS_USER_BRANCH="true"
    fi

    echo "CURRENT_BRANCH=$CURRENT_BRANCH"
    echo "IS_MAIN=$IS_MAIN"
    echo "IS_USER_BRANCH=$IS_USER_BRANCH"
    echo "USER_PREFIX=$USER_PREFIX"
    exit 0
fi

# --- Create mode: create branch from latest main ---

# Validate branch name format
if [[ ! "$BRANCH_NAME" == "${USER_PREFIX}"/* ]]; then
    echo "ERROR: Branch name must start with '${USER_PREFIX}/': $BRANCH_NAME" >&2
    exit 2
fi

# Check if branch already exists
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
    echo "ERROR: Branch already exists: $BRANCH_NAME" >&2
    exit 1
fi

# Fetch latest main and create branch directly from origin/main
# (avoids unnecessary checkout main + pull round-trip)
if ! git fetch origin main --quiet >/dev/null 2>&1; then
    echo "ERROR: Failed to fetch origin/main" >&2
    exit 2
fi

if ! git checkout -b "$BRANCH_NAME" origin/main >/dev/null 2>&1; then
    echo "ERROR: Failed to create branch: $BRANCH_NAME" >&2
    exit 2
fi

echo "BRANCH_NAME=$BRANCH_NAME"
echo "ACTION=created"
