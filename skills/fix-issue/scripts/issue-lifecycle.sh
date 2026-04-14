#!/usr/bin/env bash
# issue-lifecycle.sh — GitHub issue lifecycle operations.
#
# Subcommand-based script for commenting on, closing, and updating issues.
#
# Usage:
#   issue-lifecycle.sh comment --issue NUMBER --body TEXT [--lock]
#   issue-lifecycle.sh close   --issue NUMBER [--comment TEXT]
#   issue-lifecycle.sh update-body --issue NUMBER --pr-url URL
#
# Subcommands:
#   comment    — Post a comment on an issue.
#                With --lock: verify last comment is "GO" before posting,
#                then re-read to detect concurrent duplicate locks.
#   close      — Close an issue. Optionally post a comment first.
#   update-body — Append a PR link to the issue body (idempotent).
#
# Exit codes:
#   0 — success
#   1 — lock verification failed, state changed, or API error
#   2 — usage error

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve repo identity (shared across subcommands)
# ---------------------------------------------------------------------------
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
    echo "ERROR=Failed to resolve repository name" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Subcommand: comment
# ---------------------------------------------------------------------------
cmd_comment() {
    local issue="" body="" lock=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
            --body) body="${2:?--body requires a value}"; shift 2 ;;
            --lock) lock=true; shift ;;
            *) echo "Unknown option for comment: $1" >&2; exit 2 ;;
        esac
    done

    if [[ -z "$issue" ]] || [[ -z "$body" ]]; then
        echo "Usage: issue-lifecycle.sh comment --issue N --body TEXT [--lock]" >&2
        exit 2
    fi

    # --lock: verify last comment is still "GO" before posting
    if [ "$lock" = true ]; then
        local last_comment
        last_comment=$(gh api --paginate "repos/${REPO}/issues/${issue}/comments" \
            --jq '.[-1].body // empty' 2>/dev/null | tail -1) || {
            echo "LOCK_ACQUIRED=false"
            echo "ERROR=Failed to read comments for lock verification"
            exit 1
        }

        local trimmed
        trimmed=$(echo "$last_comment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [ "$trimmed" != "GO" ]; then
            echo "LOCK_ACQUIRED=false"
            echo "ERROR=Last comment is no longer GO (found: ${trimmed:-empty})"
            exit 1
        fi
    fi

    # Post the comment
    gh issue comment "$issue" --body "$body" >/dev/null 2>&1 || {
        echo "LOCK_ACQUIRED=false"
        echo "ERROR=Failed to post comment on issue #$issue"
        exit 1
    }

    # --lock post-check: verify no duplicate lock comment
    if [ "$lock" = true ]; then
        # Brief pause to let GitHub propagate
        sleep 1

        local comments_json
        comments_json=$(gh api --paginate --slurp "repos/${REPO}/issues/${issue}/comments" 2>/dev/null | jq 'add // []') || {
            echo "LOCK_ACQUIRED=false"
            echo "ERROR=Failed to re-read comments for duplicate check"
            exit 1
        }

        # Count IN PROGRESS comments posted after the last GO comment
        local lock_count
        lock_count=$(echo "$comments_json" | jq '
            [to_entries
             | (map(select(.value.body == "GO")) | last.key // -1) as $last_go
             | .[]
             | select(.key > $last_go and .value.body == "IN PROGRESS")
            ] | length')

        if [ "$lock_count" -gt 1 ]; then
            echo "LOCK_ACQUIRED=false"
            echo "ERROR=Duplicate IN PROGRESS detected ($lock_count found) — concurrent lock race"
            exit 1
        fi

        echo "LOCK_ACQUIRED=true"
    fi

    echo "COMMENTED=true"
}

# ---------------------------------------------------------------------------
# Subcommand: close
# ---------------------------------------------------------------------------
cmd_close() {
    local issue="" comment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
            --comment) comment="${2:?--comment requires a value}"; shift 2 ;;
            *) echo "Unknown option for close: $1" >&2; exit 2 ;;
        esac
    done

    if [[ -z "$issue" ]]; then
        echo "Usage: issue-lifecycle.sh close --issue N [--comment TEXT]" >&2
        exit 2
    fi

    # Post comment first if provided
    if [[ -n "$comment" ]]; then
        gh issue comment "$issue" --body "$comment" >/dev/null 2>&1 || {
            echo "CLOSED=false"
            echo "ERROR=Failed to post closing comment on issue #$issue"
            exit 1
        }
    fi

    gh issue close "$issue" >/dev/null 2>&1 || {
        echo "CLOSED=false"
        echo "ERROR=Failed to close issue #$issue"
        exit 1
    }

    echo "CLOSED=true"
}

# ---------------------------------------------------------------------------
# Subcommand: update-body
# ---------------------------------------------------------------------------
cmd_update_body() {
    local issue="" pr_url=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
            --pr-url) pr_url="${2:?--pr-url requires a value}"; shift 2 ;;
            *) echo "Unknown option for update-body: $1" >&2; exit 2 ;;
        esac
    done

    if [[ -z "$issue" ]] || [[ -z "$pr_url" ]]; then
        echo "Usage: issue-lifecycle.sh update-body --issue N --pr-url URL" >&2
        exit 2
    fi

    # Read current body
    local current_body
    current_body=$(gh issue view "$issue" --json body --jq '.body // ""' 2>/dev/null) || {
        echo "UPDATED=false"
        echo "ERROR=Failed to read issue #$issue body"
        exit 1
    }

    # Idempotency check: skip if PR URL already present
    if echo "$current_body" | grep -qF "$pr_url"; then
        echo "UPDATED=true"
        echo "SKIPPED=already_present"
        return 0
    fi

    # Append PR link
    local new_body="${current_body}

**PR**: ${pr_url}"

    gh issue edit "$issue" --body "$new_body" >/dev/null 2>&1 || {
        echo "UPDATED=false"
        echo "ERROR=Failed to update issue #$issue body"
        exit 1
    }

    echo "UPDATED=true"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: issue-lifecycle.sh <comment|close|update-body> [options]" >&2
    exit 2
fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
    comment) cmd_comment "$@" ;;
    close) cmd_close "$@" ;;
    update-body) cmd_update_body "$@" ;;
    *) echo "Unknown subcommand: $SUBCOMMAND" >&2; exit 2 ;;
esac
