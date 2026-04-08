#!/usr/bin/env bash
# ci-wait.sh — Poll CI status until the action changes from "wait".
#
# Consolidates the CI polling loop into a single blocking call, replacing
# many individual sleep + ci-status.sh + ci-decide.sh tool calls.
# Prints compact dot-based progress to stderr (like wait-for-reviewers.sh).
# Outputs machine-parseable results to stdout when the action is NOT "wait".
#
# Usage:
#   ci-wait.sh --pr NUMBER --repo OWNER/REPO [--rebase-count N] [--fix-attempts N] [--iteration N] [--timeout SECONDS]
#
# Options:
#   --pr             PR number (required)
#   --repo           Owner/repo identifier (required)
#   --rebase-count   Current rebase count, passed through to ci-decide.sh (default: 0)
#   --fix-attempts   Current fix attempt count, passed through to ci-decide.sh (default: 0)
#   --iteration      Starting iteration count (default: 0). Incremented internally each poll cycle.
#   --timeout        Wall-clock timeout in seconds (default: 1800 = 30 minutes)
#
# Outputs (stdout, key=value — always all lines, in order):
#   ACTION=merge|rebase|already_merged|rebase_then_evaluate|evaluate_failure|bail
#   CI_STATUS=pass|fail|pending|merged
#   BEHIND_COUNT=<N>
#   FAILED_RUN_ID=<id>          (empty string if no failure)
#   BAIL_REASON=<text>          (empty string if ACTION != bail)
#   ITERATION=<N>               (final iteration count)
#   ELAPSED=<N>                 (seconds elapsed)
#
# Progress (stderr):
#   Dots every 10s, status line every ~1 minute (every 6th check)
#
# Exit codes:
#   0 — valid decision reached (read ACTION from stdout)
#   1 — usage/argument error

# No -e: we must guarantee output on all paths. Subshell failures handled explicitly.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "Usage: ci-wait.sh --pr NUMBER --repo OWNER/REPO [--rebase-count N] [--fix-attempts N] [--iteration N] [--timeout SECONDS]" >&2; }

# --- Defaults ---
PR_NUMBER=""
REPO=""
REBASE_COUNT=0
FIX_ATTEMPTS=0
ITERATION=0
TIMEOUT=1800

# --- Parse arguments (before installing EXIT trap to avoid emitting output on usage errors) ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR_NUMBER="${2:?--pr requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --rebase-count) REBASE_COUNT="${2:?--rebase-count requires a value}"; shift 2 ;;
        --fix-attempts) FIX_ATTEMPTS="${2:?--fix-attempts requires a value}"; shift 2 ;;
        --iteration) ITERATION="${2:?--iteration requires a value}"; shift 2 ;;
        --timeout) TIMEOUT="${2:?--timeout requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$PR_NUMBER" ]] || [[ -z "$REPO" ]]; then
    echo "ERROR: --pr and --repo are required" >&2
    usage; exit 1
fi

# Validate numeric arguments
for var_name in REBASE_COUNT FIX_ATTEMPTS ITERATION TIMEOUT; do
    val="${!var_name}"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --$(echo "$var_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]') must be a non-negative integer, got: $val" >&2
        exit 1
    fi
done

# --- Output defaults (emitted via trap on any exit after validation passes) ---
ACTION="bail"
CI_STATUS="pending"
BEHIND_COUNT="0"
FAILED_RUN_ID=""
BAIL_REASON="ci-wait.sh exited unexpectedly"

emit_output() {
    echo "ACTION=$ACTION"
    echo "CI_STATUS=$CI_STATUS"
    echo "BEHIND_COUNT=$BEHIND_COUNT"
    echo "FAILED_RUN_ID=$FAILED_RUN_ID"
    echo "BAIL_REASON=$BAIL_REASON"
    echo "ITERATION=$ITERATION"
    # ELAPSED is per-invocation only (resets each time ci-wait.sh is called)
    echo "ELAPSED=$SECONDS"
}
trap 'emit_output' EXIT

# --- Polling loop ---
SECONDS=0
checks=0
ci_failures=0

printf "⏳ CI: waiting" >&2

while true; do
    # Wall-clock timeout
    if [[ "$SECONDS" -ge "$TIMEOUT" ]]; then
        ACTION="bail"
        BAIL_REASON="Wall-clock timeout (${TIMEOUT}s) exceeded"
        printf "\n⚠ CI wait timed out after %ds\n" "$TIMEOUT" >&2
        exit 0
    fi

    # 1. Check CI status
    CI_OUTPUT=$("$SCRIPT_DIR/ci-status.sh" --pr "$PR_NUMBER" --repo "$REPO" ) || true
    CI_STATUS=$(echo "$CI_OUTPUT" | grep '^CI_STATUS=' | head -1 | cut -d= -f2-)
    BEHIND_COUNT=$(echo "$CI_OUTPUT" | grep '^BEHIND_COUNT=' | head -1 | cut -d= -f2-)
    FAILED_RUN_ID=$(echo "$CI_OUTPUT" | grep '^FAILED_RUN_ID=' | head -1 | cut -d= -f2-)

    # If ci-status.sh produced no valid output, bail rather than silently defaulting to pending
    if [[ -z "$CI_STATUS" ]]; then
        ci_failures=$((ci_failures + 1))
        if [[ "$ci_failures" -ge 3 ]]; then
            ACTION="bail"
            BAIL_REASON="ci-status.sh returned no valid output 3 times consecutively"
            printf "\n❌ ci-status.sh failed repeatedly\n" >&2
            exit 0
        fi
        CI_STATUS="pending"
        BEHIND_COUNT="${BEHIND_COUNT:-0}"
        FAILED_RUN_ID="${FAILED_RUN_ID:-}"
    else
        ci_failures=0
        BEHIND_COUNT="${BEHIND_COUNT:-0}"
        FAILED_RUN_ID="${FAILED_RUN_ID:-}"
    fi

    # 2. Get decision
    DECIDE_OUTPUT=$("$SCRIPT_DIR/ci-decide.sh" \
        --status "$CI_STATUS" \
        --behind "$BEHIND_COUNT" \
        --iteration "$ITERATION" \
        --rebase-count "$REBASE_COUNT" \
        --fix-attempts "$FIX_ATTEMPTS" 2>&2)
    DECIDE_EXIT=$?

    if [[ "$DECIDE_EXIT" -ne 0 ]]; then
        ACTION="bail"
        BAIL_REASON="ci-decide.sh exited with error (code $DECIDE_EXIT)"
        printf "\n❌ ci-decide.sh failed (exit %d)\n" "$DECIDE_EXIT" >&2
        exit 0
    fi

    ACTION=$(echo "$DECIDE_OUTPUT" | grep '^ACTION=' | head -1 | cut -d= -f2-)
    BAIL_REASON=$(echo "$DECIDE_OUTPUT" | grep '^BAIL_REASON=' | head -1 | cut -d= -f2-)
    ACTION="${ACTION:-bail}"
    BAIL_REASON="${BAIL_REASON:-}"

    # 3. If not wait, stop and return
    if [[ "$ACTION" != "wait" ]]; then
        printf "\n" >&2
        if [[ "$ACTION" == "merge" ]]; then
            printf "✓ CI passed (%ds, %d checks)\n" "$SECONDS" "$checks" >&2
        elif [[ "$ACTION" == "already_merged" ]]; then
            printf "✓ PR already merged (%ds)\n" "$SECONDS" >&2
        elif [[ "$ACTION" == "bail" ]]; then
            printf "⚠ Bailing: %s (%ds, %d checks)\n" "$BAIL_REASON" "$SECONDS" "$checks" >&2
        else
            printf "→ Action: %s (%ds, %d checks)\n" "$ACTION" "$SECONDS" "$checks" >&2
        fi
        exit 0
    fi

    # 4. ACTION=wait — print dot, sleep, continue
    # Note: ITERATION is NOT incremented on internal wait polls. It counts outer-loop
    # cycles (caller re-invocations after rebase/fix), not internal 10s polls.
    # The 1800s wall-clock timeout is the safety net for long waits.
    # ci-decide.sh's iteration limit (50) guards against infinite rebase/fix loops.
    checks=$((checks + 1))

    printf "." >&2
    # Print status line every 6 checks (~1 minute)
    if [[ $((checks % 6)) -eq 0 ]]; then
        printf "\n⏳ CI: %dm elapsed, %d checks, status=%s\n" \
            "$((SECONDS / 60))" "$checks" "$CI_STATUS" >&2
    fi

    sleep 10
done
