#!/usr/bin/env bash
# add-blocked-by.sh — Apply a single GitHub-native blocker dependency between
# two issues by POSTing to the Issue Dependencies REST API. Used by /issue's
# always-on dependency-analysis path (Step 6) so that a newly-created issue
# (or a pre-existing one for the BLOCKS direction) acquires the blocker
# relationship determined during Phase 2 reasoning.
#
# Endpoint:
#   POST /repos/{owner}/{repo}/issues/{client_number}/dependencies/blocked_by
#   body: {"issue_id": <blocker numeric id, NOT the display number>}
#
# The Issue Dependencies REST API was promoted to GA on github.com in 2024;
# skills/fix-issue/scripts/find-lock-issue.sh already uses the GET counterpart
# at the same path. This script owns the WRITE side under fail-closed semantics
# distinct from find-lock-issue.sh's fail-open read posture.
#
# Retry contract (per /issue's hard-fail-with-retries rule, issue #546):
#   attempt 1 (immediate)
#   sleep 10s
#   attempt 2
#   sleep 30s
#   attempt 3
#
# Idempotency: a 422 whose response-body `message` field contains "already
# exists" / "already tracked" / "already added" / "duplicate dependency"
# (case-insensitive) is treated as success — re-running /issue after partial
# recovery does not double-fail.
#
# Other 422 variants (permissions, validation) remain failures and trigger
# retry/exhaustion.
#
# 404 on the dependencies sub-resource is treated as feature-unavailable and
# fails immediately (no retry) — no amount of retry will install the feature
# on a host that lacks it. Distinguished by ERROR=feature-unavailable.
#
# Usage:
#   add-blocked-by.sh --client-issue N --blocker-issue M [--blocker-id ID] [--repo OWNER/REPO]
#
# Arguments:
#   --client-issue N   — display number of the issue to be marked as
#                        blocked by another issue (required).
#   --blocker-issue M  — display number of the issue that blocks the client
#                        (required).
#   --blocker-id ID    — pre-resolved numeric internal id of the blocker.
#                        When omitted, the script resolves M -> ID via one
#                        `gh api /repos/$REPO/issues/$M --jq .id` call.
#                        /issue passes --blocker-id when the blocker is a
#                        freshly-created batch sibling (cached from
#                        create-one.sh's ISSUE_ID output) to skip the lookup.
#   --repo OWNER/REPO  — explicit repo (otherwise inferred via `gh repo view`).
#
# Output (key=value on stdout; warnings on stderr):
#   On success:
#     BLOCKED_BY_ADDED=true
#     CLIENT=<N>
#     BLOCKER=<M>
#   On failure:
#     BLOCKED_BY_FAILED=true
#     CLIENT=<N>
#     BLOCKER=<M>
#     ERROR=<redacted-msg>
#
# Exit codes:
#   0 — success (link applied OR idempotent already-exists)
#   1 — argument or usage error
#   2 — API failure after retry exhaustion (BLOCKED_BY_FAILED already on stdout)
#   3 — redaction-helper failure (BLOCKED_BY_FAILED with ERROR=redaction:...)
#
# Stderr is piped through scripts/redact-secrets.sh on the failure path so
# tokens in error responses (gh auth output, API echo bodies) cannot leak.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
REDACT_HELPER="$REPO_ROOT/scripts/redact-secrets.sh"

CLIENT=""
BLOCKER=""
BLOCKER_ID=""
REPO=""

usage() {
    cat <<USAGE >&2
Usage: add-blocked-by.sh --client-issue N --blocker-issue M [--blocker-id ID] [--repo OWNER/REPO]
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --client-issue) CLIENT="${2:?--client-issue requires a value}"; shift 2 ;;
        --blocker-issue) BLOCKER="${2:?--blocker-issue requires a value}"; shift 2 ;;
        --blocker-id) BLOCKER_ID="${2:?--blocker-id requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$CLIENT" || -z "$BLOCKER" ]]; then
    usage
    exit 1
fi

if ! [[ "$CLIENT" =~ ^[0-9]+$ && "$BLOCKER" =~ ^[0-9]+$ ]]; then
    echo "BLOCKED_BY_FAILED=true"
    echo "CLIENT=$CLIENT"
    echo "BLOCKER=$BLOCKER"
    echo "ERROR=client-issue and blocker-issue must be positive integers"
    exit 1
fi

if [[ -n "$BLOCKER_ID" ]] && ! [[ "$BLOCKER_ID" =~ ^[0-9]+$ ]]; then
    echo "BLOCKED_BY_FAILED=true"
    echo "CLIENT=$CLIENT"
    echo "BLOCKER=$BLOCKER"
    echo "ERROR=blocker-id must be a positive integer when provided"
    exit 1
fi

if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || REPO=""
    if [[ -z "$REPO" ]]; then
        echo "BLOCKED_BY_FAILED=true"
        echo "CLIENT=$CLIENT"
        echo "BLOCKER=$BLOCKER"
        echo "ERROR=could not determine repo"
        exit 2
    fi
fi

redact() {
    printf '%s' "$1" | "$REDACT_HELPER"
}

emit_failure() {
    local err="$1"
    local exit_code="${2:-2}"
    local redacted
    redacted=$(redact "$err") || {
        echo "BLOCKED_BY_FAILED=true"
        echo "CLIENT=$CLIENT"
        echo "BLOCKER=$BLOCKER"
        echo "ERROR=redaction: helper $REDACT_HELPER failed or missing"
        exit 3
    }
    local flat
    flat=$(echo "$redacted" | tr '\n' ' ' | head -c 500)
    echo "BLOCKED_BY_FAILED=true"
    echo "CLIENT=$CLIENT"
    echo "BLOCKER=$BLOCKER"
    echo "ERROR=$flat"
    exit "$exit_code"
}

# Resolve blocker number -> internal id when not pre-supplied.
LOOKUP_ERR=""
if [[ -z "$BLOCKER_ID" ]]; then
    LOOKUP_ERR=$(mktemp)
    trap 'rm -f "$LOOKUP_ERR"' EXIT
    if ! BLOCKER_ID=$(gh api "/repos/$REPO/issues/$BLOCKER" --jq '.id' 2>"$LOOKUP_ERR"); then
        ERR_CONTENT=$(cat "$LOOKUP_ERR")
        emit_failure "blocker-id lookup failed for #$BLOCKER: $ERR_CONTENT"
    fi
    if [[ -z "$BLOCKER_ID" || ! "$BLOCKER_ID" =~ ^[0-9]+$ ]]; then
        emit_failure "blocker-id lookup returned non-numeric id for #$BLOCKER: '$BLOCKER_ID'"
    fi
fi

# Body for the dependencies POST.
BODY_JSON=$(jq -nc --argjson id "$BLOCKER_ID" '{issue_id: $id}')

# attempt_post — single attempt. Sets ATTEMPT_LAST_ERR on failure.
# Returns:
#   0 — success (200)
#   1 — retryable failure (5xx, network)
#   2 — feature-unavailable (404) — caller must NOT retry
#   3 — idempotent already-exists (422 with pinned fragment) — treat as success
attempt_post() {
    local out_file err_file err_text
    out_file=$(mktemp)
    err_file=$(mktemp)
    if echo "$BODY_JSON" | gh api "/repos/$REPO/issues/$CLIENT/dependencies/blocked_by" \
            -X POST --input - >"$out_file" 2>"$err_file"; then
        rm -f "$out_file" "$err_file"
        return 0
    fi
    err_text=$(cat "$err_file")
    rm -f "$out_file" "$err_file"
    if echo "$err_text" | grep -qiE 'HTTP 404|status 404|404 Not Found'; then
        ATTEMPT_LAST_ERR="feature-unavailable: $err_text"
        return 2
    fi
    if echo "$err_text" | grep -qiE 'HTTP 422' && \
       echo "$err_text" | grep -qiE 'already (exists|tracked|added)|duplicate dependency'; then
        return 3
    fi
    ATTEMPT_LAST_ERR="$err_text"
    return 1
}

ATTEMPT_LAST_ERR=""
RC=0
SLEEPS=(0 10 30)
for i in 0 1 2; do
    if [[ $i -gt 0 ]]; then
        sleep "${SLEEPS[$i]}"
    fi
    set +e
    attempt_post
    RC=$?
    set -e
    case $RC in
        0|3)
            echo "BLOCKED_BY_ADDED=true"
            echo "CLIENT=$CLIENT"
            echo "BLOCKER=$BLOCKER"
            exit 0
            ;;
        2)
            emit_failure "$ATTEMPT_LAST_ERR"
            ;;
        1)
            continue
            ;;
    esac
done

emit_failure "all 3 attempts failed: ${ATTEMPT_LAST_ERR:-unknown error}"
