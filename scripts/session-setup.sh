#!/usr/bin/env bash
# session-setup.sh — Shared session setup for /design and /implement skills.
#
# Consolidates the common Step 0 operations: preflight, temp dir creation,
# Slack configuration check, and repo name derivation.
#
# Usage:
#   session-setup.sh --prefix <name> [--skip-branch-check] [--skip-slack-check] \
#     [--skip-repo-check] [--caller-env <path>]
#
# Flags:
#   --prefix <name>       (required) Temp dir prefix for mktemp (e.g., claude-implement)
#   --skip-branch-check   Forwarded to preflight.sh (skip on-main/clean-tree assertions)
#   --skip-slack-check    Skip LARCH_SLACK_BOT_TOKEN and LARCH_SLACK_CHANNEL_ID check entirely
#   --skip-repo-check     Skip repo name derivation entirely
#   --caller-env <path>   Path to KEY=value file with already-discovered values.
#                          Recognized keys: SLACK_OK, SLACK_MISSING, REPO, REPO_UNAVAILABLE.
#                          If a key is present and non-empty, the script skips re-deriving it.
#                          SESSION_TMPDIR is never inherited — a fresh tmpdir is always created.
#                          If the file does not exist or is empty, full discovery happens.
#
# Output (KEY=value lines on stdout):
#   SESSION_TMPDIR=<path>       Always output (fresh per invocation)
#   SLACK_OK=true|false         Output unless --skip-slack-check
#   SLACK_MISSING=<csv>         Output when SLACK_OK=false (comma-separated missing var names)
#   REPO=<owner/repo>           Output unless --skip-repo-check
#   REPO_UNAVAILABLE=true|false Output unless --skip-repo-check
#
# On preflight failure, outputs PREFLIGHT_ERROR=<message> and exits non-zero.
#
# Exit codes:
#   0 — success
#   1-3 — passthrough from preflight.sh
#   4 — missing --prefix or other session-setup.sh error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREFIX=""
SKIP_BRANCH_CHECK=false
SKIP_SLACK_CHECK=false
SKIP_REPO_CHECK=false
CALLER_ENV=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            [[ $# -ge 2 ]] || { echo "session-setup.sh: --prefix requires a value" >&2; exit 4; }
            PREFIX="$2"; shift 2 ;;
        --skip-branch-check)
            SKIP_BRANCH_CHECK=true; shift ;;
        --skip-slack-check)
            SKIP_SLACK_CHECK=true; shift ;;
        --skip-repo-check)
            SKIP_REPO_CHECK=true; shift ;;
        --caller-env)
            [[ $# -ge 2 ]] || { echo "session-setup.sh: --caller-env requires a path" >&2; exit 4; }
            CALLER_ENV="$2"; shift 2 ;;
        *)
            echo "session-setup.sh: unknown option: $1" >&2
            exit 4 ;;
    esac
done

if [[ -z "$PREFIX" ]]; then
    echo "session-setup.sh: --prefix is required" >&2
    exit 4
fi

# --- Read caller-env file (if provided and exists) ---
# Parse line-by-line; do NOT source. Only recognized keys with non-empty values are used.
CALLER_SLACK_OK=""
CALLER_SLACK_MISSING=""
CALLER_REPO=""
CALLER_REPO_UNAVAILABLE=""

if [[ -n "$CALLER_ENV" && -f "$CALLER_ENV" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip empty lines and lines not matching KEY=value pattern
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        case "$key" in
            SLACK_OK)          CALLER_SLACK_OK="$value" ;;
            SLACK_MISSING)     CALLER_SLACK_MISSING="$value" ;;
            REPO)              CALLER_REPO="$value" ;;
            REPO_UNAVAILABLE)  CALLER_REPO_UNAVAILABLE="$value" ;;
            *)                 ;; # Ignore unknown keys
        esac
    done < "$CALLER_ENV"
fi

# --- 1. Preflight ---
PREFLIGHT_OUTPUT=""
PREFLIGHT_EXIT=0
if [[ "$SKIP_BRANCH_CHECK" == "true" ]]; then
    PREFLIGHT_OUTPUT=$("$SCRIPT_DIR/preflight.sh" --skip-branch-check 2>&1) || PREFLIGHT_EXIT=$?
else
    PREFLIGHT_OUTPUT=$("$SCRIPT_DIR/preflight.sh" 2>&1) || PREFLIGHT_EXIT=$?
fi

if [[ $PREFLIGHT_EXIT -ne 0 ]]; then
    # Re-emit preflight output (contains PREFLIGHT_ERROR=...)
    echo "$PREFLIGHT_OUTPUT"
    exit "$PREFLIGHT_EXIT"
fi

# --- 2. Create temp directory (always fresh, never inherited) ---
SESSION_TMPDIR=$(mktemp -d "/tmp/${PREFIX}-XXXXXX")
echo "SESSION_TMPDIR=$SESSION_TMPDIR"

# --- 3. Check Slack configuration (LARCH_SLACK_BOT_TOKEN + LARCH_SLACK_CHANNEL_ID) ---
if [[ "$SKIP_SLACK_CHECK" == "false" ]]; then
    if [[ -n "$CALLER_SLACK_OK" ]]; then
        # Reuse caller's values
        echo "SLACK_OK=$CALLER_SLACK_OK"
        if [[ -n "$CALLER_SLACK_MISSING" ]]; then
            echo "SLACK_MISSING=$CALLER_SLACK_MISSING"
        fi
    else
        # Derive fresh: both vars must be set for Slack to be available.
        # Check env vars first; fall back to CLAUDE_PLUGIN_OPTION_* (set by
        # plugin userConfig when installed via marketplace). Env var wins.
        EFFECTIVE_BOT_TOKEN="${LARCH_SLACK_BOT_TOKEN:-${CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN:-}}"
        EFFECTIVE_CHANNEL_ID="${LARCH_SLACK_CHANNEL_ID:-${CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID:-}}"

        # Export effective values so downstream scripts see them as LARCH_SLACK_*
        if [[ -n "$EFFECTIVE_BOT_TOKEN" && -z "${LARCH_SLACK_BOT_TOKEN:-}" ]]; then
            export LARCH_SLACK_BOT_TOKEN="$EFFECTIVE_BOT_TOKEN"
        fi
        if [[ -n "$EFFECTIVE_CHANNEL_ID" && -z "${LARCH_SLACK_CHANNEL_ID:-}" ]]; then
            export LARCH_SLACK_CHANNEL_ID="$EFFECTIVE_CHANNEL_ID"
        fi
        # Also bridge user ID (optional, used for @-mentions)
        if [[ -z "${LARCH_SLACK_USER_ID:-}" && -n "${CLAUDE_PLUGIN_OPTION_SLACK_USER_ID:-}" ]]; then
            export LARCH_SLACK_USER_ID="${CLAUDE_PLUGIN_OPTION_SLACK_USER_ID}"
        fi

        SLACK_MISSING_VARS=""
        if [[ -z "$EFFECTIVE_BOT_TOKEN" ]]; then
            SLACK_MISSING_VARS="LARCH_SLACK_BOT_TOKEN"
        fi
        if [[ -z "$EFFECTIVE_CHANNEL_ID" ]]; then
            if [[ -n "$SLACK_MISSING_VARS" ]]; then
                SLACK_MISSING_VARS="$SLACK_MISSING_VARS,LARCH_SLACK_CHANNEL_ID"
            else
                SLACK_MISSING_VARS="LARCH_SLACK_CHANNEL_ID"
            fi
        fi

        if [[ -z "$SLACK_MISSING_VARS" ]]; then
            echo "SLACK_OK=true"
        else
            echo "SLACK_OK=false"
            echo "SLACK_MISSING=$SLACK_MISSING_VARS"
        fi
    fi
fi

# --- 4. Derive repository name ---
if [[ "$SKIP_REPO_CHECK" == "false" ]]; then
    if [[ -n "$CALLER_REPO" || -n "$CALLER_REPO_UNAVAILABLE" ]]; then
        # Reuse caller's values (treat REPO + REPO_UNAVAILABLE as one result shape)
        echo "REPO=${CALLER_REPO}"
        echo "REPO_UNAVAILABLE=${CALLER_REPO_UNAVAILABLE:-false}"
    else
        # Derive fresh: try gh first, then git remote fallback
        REPO=""
        REPO_UNAVAILABLE="false"

        if REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null) && [[ -n "$REPO" ]]; then
            : # Success
        else
            # Fallback: parse from git remote
            REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
            if [[ -n "$REMOTE_URL" ]]; then
                # Strip .git suffix, then extract owner/repo
                REMOTE_URL="${REMOTE_URL%.git}"
                if [[ "$REMOTE_URL" =~ git@github\.com:([^/]+/[^/]+)$ ]]; then
                    REPO="${BASH_REMATCH[1]}"
                elif [[ "$REMOTE_URL" =~ github\.com/([^/]+/[^/]+)$ ]]; then
                    REPO="${BASH_REMATCH[1]}"
                fi
            fi
        fi

        if [[ -z "$REPO" ]]; then
            REPO_UNAVAILABLE="true"
        fi

        echo "REPO=$REPO"
        echo "REPO_UNAVAILABLE=$REPO_UNAVAILABLE"
    fi
fi
