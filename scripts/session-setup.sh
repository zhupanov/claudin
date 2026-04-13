#!/usr/bin/env bash
# session-setup.sh — Shared session setup for all skills.
#
# Consolidates the common Step 0 operations: preflight, temp dir creation,
# Slack configuration check, repo name derivation, and reviewer health probe.
#
# Usage:
#   session-setup.sh --prefix <name> [--skip-preflight] [--skip-branch-check] \
#     [--skip-slack-check] [--skip-repo-check] [--check-reviewers] \
#     [--skip-codex-probe] [--skip-cursor-probe] [--write-health <path>] \
#     [--write-session-env <path>] [--caller-env <path>]
#
# Flags:
#   --prefix <name>       (required) Temp dir prefix for mktemp (e.g., claude-implement)
#   --skip-preflight      Skip preflight.sh call entirely (for skills with no preflight)
#   --skip-branch-check   Forwarded to preflight.sh (skip on-main/clean-tree assertions)
#   --skip-slack-check    Skip LARCH_SLACK_BOT_TOKEN and LARCH_SLACK_CHANNEL_ID check entirely
#   --skip-repo-check     Skip repo name derivation entirely
#   --check-reviewers     Run check-reviewers.sh --probe and emit availability/health keys
#   --skip-codex-probe    Forwarded to check-reviewers.sh (skip Codex health probe)
#   --skip-cursor-probe   Forwarded to check-reviewers.sh (skip Cursor health probe)
#   --write-health <path> Write CODEX_HEALTHY/CURSOR_HEALTHY to file (cross-skill propagation)
#   --write-session-env <path>  Write full session-env file via write-session-env.sh
#   --caller-env <path>   Path to KEY=value file with already-discovered values.
#                          Recognized keys: SLACK_OK, SLACK_MISSING, REPO, REPO_UNAVAILABLE,
#                          CODEX_HEALTHY, CURSOR_HEALTHY.
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
#   CODEX_AVAILABLE=true|false  Output when --check-reviewers
#   CURSOR_AVAILABLE=true|false Output when --check-reviewers
#   CODEX_HEALTHY=true|false    Output when --check-reviewers, or passthrough from --caller-env
#   CURSOR_HEALTHY=true|false   Output when --check-reviewers, or passthrough from --caller-env
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
SKIP_PREFLIGHT=false
SKIP_BRANCH_CHECK=false
SKIP_SLACK_CHECK=false
SKIP_REPO_CHECK=false
CHECK_REVIEWERS=false
SKIP_CODEX_PROBE=false
SKIP_CURSOR_PROBE=false
WRITE_HEALTH=""
WRITE_SESSION_ENV=""
CALLER_ENV=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            [[ $# -ge 2 ]] || { echo "session-setup.sh: --prefix requires a value" >&2; exit 4; }
            PREFIX="$2"; shift 2 ;;
        --skip-preflight)
            SKIP_PREFLIGHT=true; shift ;;
        --skip-branch-check)
            SKIP_BRANCH_CHECK=true; shift ;;
        --skip-slack-check)
            SKIP_SLACK_CHECK=true; shift ;;
        --skip-repo-check)
            SKIP_REPO_CHECK=true; shift ;;
        --check-reviewers)
            CHECK_REVIEWERS=true; shift ;;
        --skip-codex-probe)
            SKIP_CODEX_PROBE=true; shift ;;
        --skip-cursor-probe)
            SKIP_CURSOR_PROBE=true; shift ;;
        --write-health)
            [[ $# -ge 2 ]] || { echo "session-setup.sh: --write-health requires a path" >&2; exit 4; }
            WRITE_HEALTH="$2"; shift 2 ;;
        --write-session-env)
            [[ $# -ge 2 ]] || { echo "session-setup.sh: --write-session-env requires a path" >&2; exit 4; }
            WRITE_SESSION_ENV="$2"; shift 2 ;;
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
CALLER_CODEX_HEALTHY=""
CALLER_CURSOR_HEALTHY=""

if [[ -n "$CALLER_ENV" && -f "$CALLER_ENV" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip empty lines and lines not matching KEY=value pattern
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        case "$key" in
            SLACK_OK)          CALLER_SLACK_OK="$value" ;;
            SLACK_MISSING)     CALLER_SLACK_MISSING="$value" ;;
            REPO)              CALLER_REPO="$value" ;;
            REPO_UNAVAILABLE)  CALLER_REPO_UNAVAILABLE="$value" ;;
            CODEX_HEALTHY)     CALLER_CODEX_HEALTHY="$value" ;;
            CURSOR_HEALTHY)    CALLER_CURSOR_HEALTHY="$value" ;;
            *)                 ;; # Ignore unknown keys
        esac
    done < "$CALLER_ENV"
fi

# --- 1. Preflight ---
if [[ "$SKIP_PREFLIGHT" == "false" ]]; then
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
fi

# --- 2. Create temp directory (always fresh, never inherited) ---
SESSION_TMPDIR=$(mktemp -d "/tmp/${PREFIX}-XXXXXX")
echo "SESSION_TMPDIR=$SESSION_TMPDIR"

# --- 2a. Bridge reviewer model env vars from plugin userConfig (always, regardless of --skip-slack-check) ---
if [[ -z "${LARCH_CURSOR_MODEL:-}" && -n "${CLAUDE_PLUGIN_OPTION_CURSOR_MODEL:-}" ]]; then
    export LARCH_CURSOR_MODEL="${CLAUDE_PLUGIN_OPTION_CURSOR_MODEL}"
fi
if [[ -z "${LARCH_CODEX_MODEL:-}" && -n "${CLAUDE_PLUGIN_OPTION_CODEX_MODEL:-}" ]]; then
    export LARCH_CODEX_MODEL="${CLAUDE_PLUGIN_OPTION_CODEX_MODEL}"
fi

# --- 3. Check Slack configuration (LARCH_SLACK_BOT_TOKEN + LARCH_SLACK_CHANNEL_ID) ---
# Track values for potential --write-session-env use
SLACK_OK_VALUE=""
SLACK_MISSING_VALUE=""

if [[ "$SKIP_SLACK_CHECK" == "false" ]]; then
    if [[ -n "$CALLER_SLACK_OK" ]]; then
        # Reuse caller's values
        SLACK_OK_VALUE="$CALLER_SLACK_OK"
        SLACK_MISSING_VALUE="$CALLER_SLACK_MISSING"
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
            SLACK_OK_VALUE="true"
            echo "SLACK_OK=true"
        else
            SLACK_OK_VALUE="false"
            SLACK_MISSING_VALUE="$SLACK_MISSING_VARS"
            echo "SLACK_OK=false"
            echo "SLACK_MISSING=$SLACK_MISSING_VARS"
        fi
    fi
fi

# --- 4. Derive repository name ---
# Track values for potential --write-session-env use
REPO_VALUE=""
REPO_UNAVAILABLE_VALUE="false"

if [[ "$SKIP_REPO_CHECK" == "false" ]]; then
    if [[ -n "$CALLER_REPO" || -n "$CALLER_REPO_UNAVAILABLE" ]]; then
        # Reuse caller's values (treat REPO + REPO_UNAVAILABLE as one result shape)
        REPO_VALUE="${CALLER_REPO}"
        REPO_UNAVAILABLE_VALUE="${CALLER_REPO_UNAVAILABLE:-false}"
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

        REPO_VALUE="$REPO"
        REPO_UNAVAILABLE_VALUE="$REPO_UNAVAILABLE"
        echo "REPO=$REPO"
        echo "REPO_UNAVAILABLE=$REPO_UNAVAILABLE"
    fi
fi

# --- 5. Reviewer health: either probe (--check-reviewers) or passthrough from caller-env ---
if [[ "$CHECK_REVIEWERS" == "true" ]]; then
    # Auto-set skip-probe flags from caller-env health values
    if [[ "$CALLER_CODEX_HEALTHY" == "false" ]]; then
        SKIP_CODEX_PROBE=true
    fi
    if [[ "$CALLER_CURSOR_HEALTHY" == "false" ]]; then
        SKIP_CURSOR_PROBE=true
    fi

    # Build check-reviewers.sh arguments
    CR_ARGS=(--probe)
    if [[ "$SKIP_CODEX_PROBE" == "true" ]]; then
        CR_ARGS+=(--skip-codex-probe)
    fi
    if [[ "$SKIP_CURSOR_PROBE" == "true" ]]; then
        CR_ARGS+=(--skip-cursor-probe)
    fi

    # Run check-reviewers.sh; capture output, guard against non-zero exit
    REVIEWER_OUTPUT=$("$SCRIPT_DIR/check-reviewers.sh" "${CR_ARGS[@]}" 2>&1) || true

    # Parse and emit reviewer output
    PROBED_CODEX_AVAILABLE=""
    PROBED_CURSOR_AVAILABLE=""
    PROBED_CODEX_HEALTHY=""
    PROBED_CURSOR_HEALTHY=""
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        case "$key" in
            CODEX_AVAILABLE)  PROBED_CODEX_AVAILABLE="$value" ;;
            CURSOR_AVAILABLE) PROBED_CURSOR_AVAILABLE="$value" ;;
            CODEX_HEALTHY)    PROBED_CODEX_HEALTHY="$value" ;;
            CURSOR_HEALTHY)   PROBED_CURSOR_HEALTHY="$value" ;;
        esac
    done <<< "$REVIEWER_OUTPUT"

    [[ -n "$PROBED_CODEX_AVAILABLE" ]] && echo "CODEX_AVAILABLE=$PROBED_CODEX_AVAILABLE"
    [[ -n "$PROBED_CURSOR_AVAILABLE" ]] && echo "CURSOR_AVAILABLE=$PROBED_CURSOR_AVAILABLE"
    [[ -n "$PROBED_CODEX_HEALTHY" ]] && echo "CODEX_HEALTHY=$PROBED_CODEX_HEALTHY"
    [[ -n "$PROBED_CURSOR_HEALTHY" ]] && echo "CURSOR_HEALTHY=$PROBED_CURSOR_HEALTHY"

    # Emit prominent banners to stderr for failed health checks (must be here,
    # not in check-reviewers.sh, because session-setup captures its stdout+stderr
    # via 2>&1 — banners emitted there would be swallowed).
    if [[ "$PROBED_CODEX_AVAILABLE" == "true" && "$PROBED_CODEX_HEALTHY" == "false" \
          && "$SKIP_CODEX_PROBE" == "false" ]]; then
        echo "═══════════════════════════════════════════════════════════" >&2
        echo "  ⚠  CODEX HEALTH CHECK FAILED — not responding" >&2
        echo "     Codex binary found but health probe timed out or errored." >&2
        echo "     Will use Claude replacement for this session." >&2
        echo "═══════════════════════════════════════════════════════════" >&2
    fi
    if [[ "$PROBED_CURSOR_AVAILABLE" == "true" && "$PROBED_CURSOR_HEALTHY" == "false" \
          && "$SKIP_CURSOR_PROBE" == "false" ]]; then
        echo "═══════════════════════════════════════════════════════════" >&2
        echo "  ⚠  CURSOR HEALTH CHECK FAILED — not responding" >&2
        echo "     Cursor binary found but health probe timed out or errored." >&2
        echo "     Will use Claude replacement for this session." >&2
        echo "═══════════════════════════════════════════════════════════" >&2
    fi

    # Use probed values for downstream sections
    FINAL_CODEX_HEALTHY="${PROBED_CODEX_HEALTHY:-}"
    FINAL_CURSOR_HEALTHY="${PROBED_CURSOR_HEALTHY:-}"
else
    # Passthrough from caller-env (no probe)
    if [[ -n "$CALLER_CODEX_HEALTHY" ]]; then
        echo "CODEX_HEALTHY=$CALLER_CODEX_HEALTHY"
    fi
    if [[ -n "$CALLER_CURSOR_HEALTHY" ]]; then
        echo "CURSOR_HEALTHY=$CALLER_CURSOR_HEALTHY"
    fi
    FINAL_CODEX_HEALTHY="${CALLER_CODEX_HEALTHY:-}"
    FINAL_CURSOR_HEALTHY="${CALLER_CURSOR_HEALTHY:-}"
fi

# --- 6. Write health file (if requested) ---
if [[ -n "$WRITE_HEALTH" && "$WRITE_HEALTH" != "/dev/null" ]]; then
    HEALTH_TMPFILE=$(mktemp "${WRITE_HEALTH}.tmp.XXXXXX")
    {
        echo "CODEX_HEALTHY=${FINAL_CODEX_HEALTHY:-true}"
        echo "CURSOR_HEALTHY=${FINAL_CURSOR_HEALTHY:-true}"
    } > "$HEALTH_TMPFILE"
    mv "$HEALTH_TMPFILE" "$WRITE_HEALTH"
fi

# --- 7. Write session-env file (if requested) ---
# Runs after the probe so health keys are included.
if [[ -n "$WRITE_SESSION_ENV" ]]; then
    # Determine Slack values: from probe results above or from caller-env or empty
    WSE_SLACK_OK="${SLACK_OK_VALUE:-false}"
    WSE_SLACK_MISSING="${SLACK_MISSING_VALUE:-}"
    WSE_REPO="${REPO_VALUE:-}"
    WSE_REPO_UNAVAILABLE="${REPO_UNAVAILABLE_VALUE:-false}"

    WSE_ARGS=(--output "$WRITE_SESSION_ENV"
              --slack-ok "$WSE_SLACK_OK"
              --repo-unavailable "$WSE_REPO_UNAVAILABLE")
    [[ -n "$WSE_SLACK_MISSING" ]] && WSE_ARGS+=(--slack-missing "$WSE_SLACK_MISSING")
    [[ -n "$WSE_REPO" ]] && WSE_ARGS+=(--repo "$WSE_REPO")
    [[ -n "$FINAL_CODEX_HEALTHY" ]] && WSE_ARGS+=(--codex-healthy "$FINAL_CODEX_HEALTHY")
    [[ -n "$FINAL_CURSOR_HEALTHY" ]] && WSE_ARGS+=(--cursor-healthy "$FINAL_CURSOR_HEALTHY")

    "$SCRIPT_DIR/write-session-env.sh" "${WSE_ARGS[@]}"
fi
