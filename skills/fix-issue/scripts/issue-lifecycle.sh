#!/usr/bin/env bash
# issue-lifecycle.sh — GitHub issue lifecycle operations.
#
# Subcommand-based script for commenting on, closing, and updating issues.
#
# Usage:
#   issue-lifecycle.sh comment --issue NUMBER --body TEXT [--lock]
#   issue-lifecycle.sh close   --issue NUMBER [--comment TEXT] [--pr-url URL]
#   issue-lifecycle.sh update-body --issue NUMBER --pr-url URL
#
# Subcommands:
#   comment    — Post a comment on an issue.
#                With --lock: verify last comment is "GO", DELETE that GO
#                comment, then post the new comment (typically "IN PROGRESS").
#                Re-reads afterward to detect concurrent duplicate locks via
#                "IN PROGRESS" comments created after the deleted GO timestamp.
#   close      — Close an issue. Optionally post a comment first.
#                With --pr-url: update the issue body with the PR link before closing.
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

    local go_ts=""

    # --lock: verify last comment is "GO", capture its id + timestamp, then
    # delete it so the GO sentinel does not remain on the issue after locking.
    if [ "$lock" = true ]; then
        local comments_json
        comments_json=$(gh api --paginate --slurp "repos/${REPO}/issues/${issue}/comments" 2>/dev/null | jq 'add // []') || {
            echo "LOCK_ACQUIRED=false"
            echo "ERROR=Failed to read comments for lock verification"
            exit 1
        }

        local last_body last_id
        last_body=$(echo "$comments_json" | jq -r '.[-1].body // empty')
        last_id=$(echo "$comments_json" | jq -r '.[-1].id // empty')
        go_ts=$(echo "$comments_json" | jq -r '.[-1].created_at // empty')

        local trimmed
        trimmed=$(echo "$last_body" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [ "$trimmed" != "GO" ]; then
            echo "LOCK_ACQUIRED=false"
            echo "ERROR=Last comment is no longer GO (found: ${trimmed:-empty})"
            exit 1
        fi

        if [[ -z "$last_id" ]] || [[ -z "$go_ts" ]]; then
            echo "LOCK_ACQUIRED=false"
            echo "ERROR=Failed to extract GO comment id/timestamp for deletion"
            exit 1
        fi

        # Delete the GO comment. The post-check below uses $go_ts (captured
        # above) as the duplicate-detection sentinel in place of a surviving
        # GO anchor.
        gh api -X DELETE "repos/${REPO}/issues/comments/${last_id}" >/dev/null 2>&1 || {
            echo "LOCK_ACQUIRED=false"
            echo "ERROR=Failed to delete GO comment on issue #$issue"
            exit 1
        }
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

        # Count IN PROGRESS comments created strictly after the deleted GO's
        # timestamp. Two concurrent runners that both raced the pre-check will
        # see count > 1 here.
        local lock_count
        lock_count=$(echo "$comments_json" | jq --arg ts "$go_ts" '
            [.[] | select(.body == "IN PROGRESS" and .created_at > $ts)] | length')

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
    local issue="" comment="" pr_url=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
            --comment) comment="${2:?--comment requires a value}"; shift 2 ;;
            --pr-url) pr_url="${2:?--pr-url requires a value}"; shift 2 ;;
            *) echo "Unknown option for close: $1" >&2; exit 2 ;;
        esac
    done

    if [[ -z "$issue" ]]; then
        echo "Usage: issue-lifecycle.sh close --issue N [--comment TEXT] [--pr-url URL]" >&2
        exit 2
    fi

    # Update body with PR link if provided (idempotent). Suppress stdout so
    # cmd_update_body's UPDATED=/SKIPPED= keys never leak into cmd_close's
    # stdout — the caller-visible contract is CLOSED=true (or CLOSED=false + ERROR=).
    if [[ -n "$pr_url" ]]; then
        cmd_update_body --issue "$issue" --pr-url "$pr_url" >/dev/null || {
            echo "CLOSED=false"
            echo "ERROR=Failed to update issue #$issue body with PR link"
            exit 1
        }
    fi

    # Post comment first if provided
    if [[ -n "$comment" ]]; then
        gh issue comment "$issue" --body "$comment" >/dev/null 2>&1 || {
            echo "CLOSED=false"
            echo "ERROR=Failed to post closing comment on issue #$issue"
            exit 1
        }
    fi

    # Idempotency guard: probe current state before attempting close. If the
    # issue is already CLOSED (e.g., GitHub auto-closed it via `Closes #<N>`
    # on PR merge), skip the `gh issue close` call but still emit CLOSED=true
    # on stdout so /fix-issue Step 7's stdout parser cannot distinguish the
    # paths (stderr carries an INFO note; stdout contract is byte-stable).
    # On probe failure, log a WARNING to stderr and fall through to the
    # existing close path rather than hard-failing — this preserves the
    # pre-PR OPEN-path reliability (a transient `gh issue view` blip must
    # not abort a close that would otherwise have succeeded).
    # Exact match on "CLOSED": /fix-issue only ever passes issue numbers
    # (never PR numbers), so MERGED and other PR-state values never appear here.
    local current_state probe_ok=1
    current_state=$(gh issue view "$issue" --json state --jq '.state' 2>/dev/null) || probe_ok=0

    if (( probe_ok )) && [ "$current_state" = "CLOSED" ]; then
        echo "INFO: issue #$issue already closed; backfilling DONE metadata only" >&2
    else
        if (( ! probe_ok )); then
            echo "WARNING: failed to probe state for issue #$issue; attempting close anyway" >&2
        fi
        gh issue close "$issue" >/dev/null 2>&1 || {
            echo "CLOSED=false"
            echo "ERROR=Failed to close issue #$issue"
            exit 1
        }
    fi

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
            *) echo "Unknown option for update-body: $1" >&2; return 2 ;;
        esac
    done

    if [[ -z "$issue" ]] || [[ -z "$pr_url" ]]; then
        echo "Usage: issue-lifecycle.sh update-body --issue N --pr-url URL" >&2
        return 2
    fi

    # Read current body
    local current_body
    current_body=$(gh issue view "$issue" --json body --jq '.body // ""' 2>/dev/null) || {
        echo "UPDATED=false"
        echo "ERROR=Failed to read issue #$issue body"
        return 1
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
        return 1
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
