#!/usr/bin/env bash
# ci-decide.sh — Decision matrix for CI merge loop.
#
# Pure decision logic with no side effects. Takes the current CI state
# and loop counters, returns the action the caller should take.
#
# Merge is always allowed when CI passes and branch is up-to-date,
# regardless of safety limits. Safety limits only block non-merge actions:
#   - iteration >= 50: bail (timeout)
#   - rebase_count >= 5: bail (too many rebases)
#   - fix_attempts >= 3: bail (too many fixes)
#
# Decision matrix (when no safety limit triggers):
#   CI_STATUS | BEHIND_COUNT > 0 | ACTION
#   ----------|------------------|-------------------
#   merged    | *                | already_merged
#   pending   | yes              | rebase
#   pending   | no               | wait
#   pass      | yes              | rebase
#   pass      | no               | merge
#   fail      | yes              | rebase_then_evaluate
#   fail      | no               | evaluate_failure
#
# Usage:
#   ci-decide.sh --status STATUS --behind N --iteration N --rebase-count N --fix-attempts N
#
# Arguments:
#   --status       — "pass", "fail", "pending", or "merged"
#   --behind       — Number of commits behind origin/main (non-negative integer)
#   --iteration    — Current poll loop iteration (non-negative integer)
#   --rebase-count — Number of rebases performed so far (non-negative integer)
#   --fix-attempts — Number of CI fix attempts so far (non-negative integer)
#
# Outputs (key=value to stdout):
#   ACTION=wait|rebase|merge|already_merged|rebase_then_evaluate|evaluate_failure|bail
#   BAIL_REASON=<text>    (only when ACTION=bail)
#
# Exit codes:
#   0 — always (decision communicated via output)
#   1 — invalid input

set -euo pipefail

usage() { echo "Usage: ci-decide.sh --status STATUS --behind N --iteration N --rebase-count N --fix-attempts N" >&2; }

CI_STATUS=""
BEHIND_COUNT=""
ITERATION=""
REBASE_COUNT=""
FIX_ATTEMPTS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --status) CI_STATUS="${2:?--status requires a value}"; shift 2 ;;
        --behind) BEHIND_COUNT="${2:?--behind requires a value}"; shift 2 ;;
        --iteration) ITERATION="${2:?--iteration requires a value}"; shift 2 ;;
        --rebase-count) REBASE_COUNT="${2:?--rebase-count requires a value}"; shift 2 ;;
        --fix-attempts) FIX_ATTEMPTS="${2:?--fix-attempts requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$CI_STATUS" ]] || [[ -z "$BEHIND_COUNT" ]] || [[ -z "$ITERATION" ]] || [[ -z "$REBASE_COUNT" ]] || [[ -z "$FIX_ATTEMPTS" ]]; then
    echo "ERROR: all arguments are required" >&2
    usage; exit 1
fi

# --- Input validation ---
if [[ "$CI_STATUS" != "pass" ]] && [[ "$CI_STATUS" != "fail" ]] && [[ "$CI_STATUS" != "pending" ]] && [[ "$CI_STATUS" != "merged" ]] && [[ "$CI_STATUS" != "error" ]]; then
    echo "ERROR: --status must be pass|fail|pending|merged|error, got: $CI_STATUS" >&2
    exit 1
fi

# ci-status.sh emits "error" when it fails to parse its own arguments
if [[ "$CI_STATUS" == "error" ]]; then
    echo "ACTION=bail"
    echo "BAIL_REASON=ci-status.sh returned error — check script arguments"
    exit 0
fi

for var_name in BEHIND_COUNT ITERATION REBASE_COUNT FIX_ATTEMPTS; do
    val="${!var_name}"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "ERROR: $var_name must be a non-negative integer, got: $val" >&2
        exit 1
    fi
done

# --- Decision matrix ---
# PR already merged (force-merged by user) — stop waiting immediately
if [[ "$CI_STATUS" == "merged" ]]; then
    echo "ACTION=already_merged"
    exit 0
fi

# Evaluate CI state first — if CI passes and branch is up-to-date, always merge
# (even if safety limits have been reached). Safety limits only block non-merge actions.
BEHIND=$( [[ "$BEHIND_COUNT" -gt 0 ]] && echo "true" || echo "false" )

# Allow merge regardless of safety limits
if [[ "$CI_STATUS" == "pass" ]] && [[ "$BEHIND" == "false" ]]; then
    echo "ACTION=merge"
    exit 0
fi

# --- Safety limits (checked before non-merge actions) ---
if [[ "$ITERATION" -ge 50 ]]; then
    echo "ACTION=bail"
    echo "BAIL_REASON=Timeout: 50 iterations (~25 minutes) without successful merge"
    exit 0
fi

if [[ "$REBASE_COUNT" -ge 5 ]]; then
    echo "ACTION=bail"
    echo "BAIL_REASON=Too many rebases (5) without converging — main branch too active"
    exit 0
fi

if [[ "$FIX_ATTEMPTS" -ge 3 ]]; then
    echo "ACTION=bail"
    echo "BAIL_REASON=Too many fix attempts (3) without CI passing"
    exit 0
fi

# --- Remaining decision matrix ---
case "$CI_STATUS" in
    pending)
        if [[ "$BEHIND" == "true" ]]; then
            echo "ACTION=rebase"
        else
            echo "ACTION=wait"
        fi
        ;;
    pass)
        # pass + behind=true (pass + behind=false handled above)
        echo "ACTION=rebase"
        ;;
    fail)
        if [[ "$BEHIND" == "true" ]]; then
            echo "ACTION=rebase_then_evaluate"
        else
            echo "ACTION=evaluate_failure"
        fi
        ;;
esac
