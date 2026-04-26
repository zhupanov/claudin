#!/usr/bin/env bash
# finalize-umbrella.sh — Finalize an umbrella issue when all of its tracked
# children have been closed.
#
# Composes the rename + close + closing-comment sequence used by /fix-issue's
# umbrella support. Two callers:
#   1. find-lock-issue.sh's exit-4 path (umbrella detected, all children
#      already closed at /fix-issue invocation time) — invoked from SKILL.md
#      Step 0.
#   2. /fix-issue Step 6 (after closing the just-processed child, when
#      $UMBRELLA_NUMBER is set and the now-completed child was the umbrella's
#      last open tracked issue), Step 5a (adopted-issue-closed bailout, same
#      hook), and Step 3 (not-material close, same hook).
#
# Both callers share this helper to keep the finalize sequence centralized
# (FINDING_2: idempotency rules can't be enforced if every caller composes
# its own rename/comment/close sequence).
#
# Subcommand:
#   finalize --issue N
#
# Idempotency guard (FINDING_2):
#   Before posting any comment or running rename/close, probe the umbrella's
#   current state and look for a sentinel HTML-comment marker that would have
#   been embedded by a prior successful finalize. The guard treats ANY of the
#   following as "already finalized":
#     1. Issue state is CLOSED.
#     2. Title starts with "[DONE] " (managed lifecycle prefix).
#     3. Any existing comment body contains the literal marker
#        "<!-- larch:fix-issue:umbrella-finalized -->".
#   On any of these, emit FINALIZED=false ALREADY_FINALIZED=true and exit 0
#   without posting a duplicate comment. issue-lifecycle.sh close ALREADY
#   skips the gh issue close call when state is CLOSED, but it posts the
#   --comment BEFORE its idempotency probe — so without this pre-flight guard
#   we would still double-comment under concurrent finalize attempts.
#
# Sequence on the non-idempotent path:
#   1. Rename the umbrella's title to "[DONE] <title>" via
#      tracking-issue-write.sh rename --state done. Best-effort: a rename
#      failure is logged on stderr but does not abort finalization (the close
#      is the correctness boundary; the title prefix is a visual lifecycle
#      marker).
#   2. Post the closing comment AND close the issue via issue-lifecycle.sh
#      close. The comment body embeds the sentinel marker so a later finalize
#      attempt's idempotency guard catches it.
#
# Stdout contract (KEY=value lines):
#   FINALIZED=true|false
#   ALREADY_FINALIZED=true        (only when the idempotency guard fired)
#   RENAMED=true|false            (rename outcome — present on the executed
#                                  path; omitted on ALREADY_FINALIZED)
#   CLOSED=true|false             (close outcome — present on the executed
#                                  path; omitted on ALREADY_FINALIZED)
#   ERROR=<reason>                (only on FINALIZED=false non-idempotent
#                                  failures)
#
# Exit codes:
#   0 — success (FINALIZED=true) OR already-finalized (FINALIZED=false
#       ALREADY_FINALIZED=true). Both are non-fatal for the caller.
#   1 — non-idempotent failure (gh API error, close failed, etc.)
#   2 — usage error

set -euo pipefail

MARKER='<!-- larch:fix-issue:umbrella-finalized -->'
CLOSING_COMMENT_BODY='All tracked issues are closed. Marking umbrella as DONE and closing.'

# ---------------------------------------------------------------------------
# Resolve repo identity (used for comment-marker probe).
# ---------------------------------------------------------------------------
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
    echo "FINALIZED=false"
    echo "ERROR=Failed to resolve repository name"
    exit 1
}

# ---------------------------------------------------------------------------
# Resolve helper script paths.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIFECYCLE_SCRIPT="${SCRIPT_DIR}/issue-lifecycle.sh"
RENAME_SCRIPT="${SCRIPT_DIR}/../../../scripts/tracking-issue-write.sh"

# ---------------------------------------------------------------------------
# Subcommand: finalize
# ---------------------------------------------------------------------------
cmd_finalize() {
    local issue=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
            *) echo "FINALIZED=false"; echo "ERROR=Unknown option for finalize: $1"; exit 2 ;;
        esac
    done
    if [[ -z "$issue" ]]; then
        echo "FINALIZED=false"
        echo "ERROR=Usage: finalize-umbrella.sh finalize --issue N"
        exit 2
    fi

    # ---- Idempotency guard ----
    local cur_state cur_title
    local view_json
    view_json=$(gh issue view "$issue" --json state,title --jq '{state,title}' 2>/dev/null) || {
        echo "FINALIZED=false"
        echo "ERROR=Failed to fetch umbrella #$issue state"
        exit 1
    }
    cur_state=$(printf '%s' "$view_json" | jq -r '.state // ""')
    cur_title=$(printf '%s' "$view_json" | jq -r '.title // ""')

    # ---- Idempotency guard semantics ----
    # Only state=CLOSED is a strict short-circuit (no further mutation).
    # If state=OPEN but we already see the [DONE] title prefix or the marker
    # comment in the stream, that means a PRIOR finalize attempt got past
    # rename and/or comment-post but its `gh issue close` failed (issue-
    # lifecycle.sh close posts the comment BEFORE the close call, leaving
    # this exact partial-success window). On retry, we must NOT re-emit
    # rename or the marker comment (avoiding double-comment under
    # concurrency), but we MUST still call `gh issue close` to drive the
    # umbrella to its terminal state — otherwise every retry returns
    # ALREADY_FINALIZED=true and the umbrella stays OPEN forever. Branch on
    # state below: state=CLOSED → idempotent short-circuit; state=OPEN with
    # title/marker present → close-only retry; else → full sequence.
    if [[ "$cur_state" == "CLOSED" ]]; then
        echo "FINALIZED=false"
        echo "ALREADY_FINALIZED=true"
        echo "REASON=already CLOSED"
        return 0
    fi
    # Probe state and detect partial-success marker(s) — these are the
    # signals that rename and/or comment-post already ran successfully on a
    # prior attempt. We do NOT short-circuit on these alone; we use them to
    # decide whether to skip the rename + comment-post steps and just call
    # close.
    local title_done=false marker_present=false
    case "$cur_title" in
        '[DONE] '*) title_done=true ;;
    esac
    local marker_hits
    marker_hits=$(gh api --paginate --slurp "repos/${REPO}/issues/${issue}/comments" 2>/dev/null \
        | jq -r --arg marker "$MARKER" 'add // [] | map(select(.body | tostring | contains($marker))) | length') || marker_hits=0
    if [[ "${marker_hits:-0}" -gt 0 ]]; then
        marker_present=true
    fi

    # ---- Step 1: rename to [DONE] (best-effort, skip if title already done). ----
    local rename_out rename_exit=0 renamed=false
    local rename_state="done"
    if [[ "$title_done" == "true" ]]; then
        # Title is already prefixed; skip the rename API call. Report
        # RENAMED=false in the contract (no rename happened this call) but
        # do not mark this as a failure — the prior attempt's rename
        # succeeded and the title is in the desired terminal state.
        renamed="false"
    else
        rename_out=$("$RENAME_SCRIPT" rename --issue "$issue" --state "$rename_state" 2>&1) || rename_exit=$?
        renamed=$(echo "$rename_out" | awk -F= '/^RENAMED=/ { v=$2 } END { print v }')
        local rename_failed
        rename_failed=$(echo "$rename_out" | awk -F= '/^FAILED=/ { v=$2 } END { print v }')
        if [[ "$rename_exit" -ne 0 ]] || [[ "$rename_failed" == "true" ]]; then
            # Best-effort: log on stderr but proceed to close.
            echo "WARNING: title rename to [DONE] failed for umbrella #$issue (exit $rename_exit)" >&2
            renamed=false
        fi
        if [[ -z "$renamed" ]]; then
            renamed=false
        fi
    fi

    # ---- Step 2: post closing comment + close (idempotent on already-CLOSED). ----
    # If the marker is already in the comment stream from a prior partial
    # attempt, skip the comment post (avoid double-commenting under
    # concurrency / retry) but still drive `gh issue close`. Pass --comment
    # only when the marker is absent.
    local close_out close_exit=0
    if [[ "$marker_present" == "true" ]]; then
        # Marker already present — close without re-posting the closing
        # comment. issue-lifecycle.sh close --issue N (no --comment) closes
        # the issue and skips the comment post entirely.
        close_out=$("$LIFECYCLE_SCRIPT" close --issue "$issue" 2>&1) || close_exit=$?
    else
        local closing_comment
        closing_comment=$(printf '%s\n%s' "$MARKER" "$CLOSING_COMMENT_BODY")
        close_out=$("$LIFECYCLE_SCRIPT" close --issue "$issue" --comment "$closing_comment" 2>&1) || close_exit=$?
    fi
    local closed close_error
    closed=$(echo "$close_out" | awk -F= '/^CLOSED=/ { v=$2 } END { print v }')
    close_error=$(echo "$close_out" | awk -F= '/^ERROR=/ { sub(/^ERROR=/, "", $0); v=$0 } END { print v }')
    if [[ "$closed" != "true" ]] || [[ "$close_exit" -ne 0 ]]; then
        echo "FINALIZED=false"
        echo "RENAMED=$renamed"
        echo "CLOSED=false"
        if [[ -n "$close_error" ]]; then
            echo "ERROR=$close_error"
        else
            echo "ERROR=Failed to close umbrella #$issue (issue-lifecycle.sh exit $close_exit)"
        fi
        exit 1
    fi

    # ---- Emit success ----
    echo "FINALIZED=true"
    echo "RENAMED=$renamed"
    echo "CLOSED=true"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "FINALIZED=false"
    echo "ERROR=Usage: finalize-umbrella.sh finalize --issue N"
    exit 2
fi

SUBCOMMAND="$1"
shift
case "$SUBCOMMAND" in
    finalize) cmd_finalize "$@" ;;
    *) echo "FINALIZED=false"; echo "ERROR=Unknown subcommand: $SUBCOMMAND"; exit 2 ;;
esac
