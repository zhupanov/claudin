#!/usr/bin/env bash
# collect-reviewer-results.sh — Collect, validate, and optionally retry external reviewer outputs.
#
# Consolidates the post-launch validation+retry pattern used across all skills.
# Wraps wait-for-reviewers.sh, validates each output, retries once on empty via
# .meta files written by run-external-reviewer.sh, and emits structured results.
#
# Usage:
#   collect-reviewer-results.sh --timeout <seconds> [--write-health <path>] \
#     <output-file> [<output-file> ...]
#
# Options:
#   --timeout <seconds>    Timeout for wait-for-reviewers.sh (e.g., 1860)
#   --write-health <path>  Write updated CODEX_HEALTHY/CURSOR_HEALTHY to file.
#                          Health is monotonic per tool: any failure sets the tool
#                          permanently unhealthy. A later successful instance does
#                          NOT flip it back to healthy.
#                          If the file already exists, prior health state is read
#                          and merged monotonically (prior false is preserved).
#
# Arguments:
#   One or more output file paths (from run-external-reviewer.sh invocations).
#   Sentinel paths are derived by appending .done to each output file.
#   Metadata paths are derived by appending .meta to each output file.
#
# Output (KEY=value blocks on stdout, one block per reviewer, separated by blank lines):
#   REVIEWER_FILE=<output-path>
#   TOOL=<codex|cursor|unknown>
#   STATUS=<OK|TIMED_OUT|FAILED|EMPTY_OUTPUT|SENTINEL_TIMEOUT>
#   EXIT_CODE=<N>
#   HEALTHY=<true|false>
#
# Exit codes:
#   0 — normal completion (results are informational, not errors)
#   1 — argument error (missing required option or unknown flag)

# No -e: exit codes from reviewer subprocesses and retries are informational.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TIMEOUT=""
WRITE_HEALTH=""
OUTPUT_FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            TIMEOUT="${2:?--timeout requires a value}"; shift 2 ;;
        --write-health)
            WRITE_HEALTH="${2:?--write-health requires a path}"; shift 2 ;;
        --help)
            echo "Usage: collect-reviewer-results.sh --timeout <seconds> [--write-health <path>] <output-file>..." >&2
            exit 0 ;;
        -*)
            echo "collect-reviewer-results.sh: unknown option: $1" >&2; exit 1 ;;
        *)
            OUTPUT_FILES+=("$1"); shift ;;
    esac
done

if [[ -z "$TIMEOUT" ]]; then
    echo "collect-reviewer-results.sh: --timeout is required" >&2
    exit 1
fi

if [[ ${#OUTPUT_FILES[@]} -eq 0 ]]; then
    echo "collect-reviewer-results.sh: at least one output file is required" >&2
    exit 1
fi

# --- Derive tool name from output filename ---
derive_tool() {
    local base
    base=$(basename "$1")
    if [[ "$base" == *codex* ]]; then
        echo "codex"
    elif [[ "$base" == *cursor* ]]; then
        echo "cursor"
    else
        echo "unknown"
    fi
}

# --- Health state tracking (portable, no associative arrays) ---
# Monotonic: once false, stays false for the session.
CODEX_TOOL_HEALTHY="true"
CURSOR_TOOL_HEALTHY="true"

# Read prior health state from existing --write-health file (if it exists).
# This preserves monotonicity across separate collect-reviewer-results.sh calls.
if [[ -n "$WRITE_HEALTH" && -f "$WRITE_HEALTH" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
            CODEX_HEALTHY)  [[ "$value" == "false" ]] && CODEX_TOOL_HEALTHY="false" ;;
            CURSOR_HEALTHY) [[ "$value" == "false" ]] && CURSOR_TOOL_HEALTHY="false" ;;
        esac
    done < "$WRITE_HEALTH"
fi

get_tool_healthy() {
    case "$1" in
        codex)  echo "$CODEX_TOOL_HEALTHY" ;;
        cursor) echo "$CURSOR_TOOL_HEALTHY" ;;
        *)      echo "true" ;;
    esac
}

set_tool_unhealthy() {
    case "$1" in
        codex)  CODEX_TOOL_HEALTHY="false" ;;
        cursor) CURSOR_TOOL_HEALTHY="false" ;;
    esac
}

# --- 1. Build sentinel paths and wait ---
SENTINELS=()
for f in "${OUTPUT_FILES[@]}"; do
    SENTINELS+=("${f}.done")
done

WAIT_OUTPUT=$("$SCRIPT_DIR/wait-for-reviewers.sh" --timeout "$TIMEOUT" "${SENTINELS[@]}" 2>/dev/null) || true

# Parse wait output for TIMEOUT indicators (portable: newline-separated list)
TIMED_OUT_SENTINELS=""
while IFS= read -r line; do
    if [[ "$line" == TIMEOUT\ * ]]; then
        local_sentinel="${line#TIMEOUT }"
        local_sentinel="${local_sentinel%%:*}"
        TIMED_OUT_SENTINELS="${TIMED_OUT_SENTINELS}${local_sentinel}"$'\n'
    fi
done <<< "$WAIT_OUTPUT"

# Check if a sentinel basename is in the timed-out list
is_timed_out() {
    local needle="$1"
    echo "$TIMED_OUT_SENTINELS" | grep -qxF "$needle"
}

# --- 2. Validate each output and collect results ---
RETRY_FILES=()
RETRY_INDICES=()
RETRY_TIMEOUTS=()

RESULTS=()
for i in "${!OUTPUT_FILES[@]}"; do
    OUTPUT="${OUTPUT_FILES[$i]}"
    SENTINEL="${OUTPUT}.done"
    META="${OUTPUT}.meta"
    TOOL=$(derive_tool "$OUTPUT")
    STATUS="OK"
    EXIT_CODE="0"
    HEALTHY="true"

    # F1 fix: strip .done suffix to match wait-for-reviewers.sh output format
    SENTINEL_BASE=$(basename "$SENTINEL" .done)
    if is_timed_out "$SENTINEL_BASE"; then
        # wait-for-reviewers.sh reported TIMEOUT (sentinel never appeared)
        STATUS="SENTINEL_TIMEOUT"
        EXIT_CODE="124"
        HEALTHY="false"
    elif [[ -f "$SENTINEL" ]]; then
        EXIT_CODE=$(cat "$SENTINEL" 2>/dev/null || echo "99")
        if [[ "$EXIT_CODE" == "124" ]]; then
            STATUS="TIMED_OUT"
            HEALTHY="false"
        elif [[ "$EXIT_CODE" != "0" ]]; then
            STATUS="FAILED"
            HEALTHY="false"
        elif [[ ! -s "$OUTPUT" ]]; then
            # F4 fix: empty output is a retry candidate, NOT an immediate health failure.
            # Health is only set to false after retry also fails (see section 3 below).
            STATUS="EMPTY_OUTPUT"
            HEALTHY="true"  # tentative — will be set false if retry fails
            # Queue for retry if .meta exists
            if [[ -f "$META" ]]; then
                # Parse META_TIMEOUT for retry wait calculation
                ORIG_TIMEOUT=""
                while IFS= read -r meta_line || [[ -n "$meta_line" ]]; do
                    meta_key="${meta_line%%=*}"
                    meta_val="${meta_line#*=}"
                    [[ "$meta_key" == "TIMEOUT" ]] && ORIG_TIMEOUT="$meta_val"
                done < "$META"
                RETRY_FILES+=("$OUTPUT")
                RETRY_INDICES+=("$i")
                RETRY_TIMEOUTS+=("${ORIG_TIMEOUT:-120}")
            else
                HEALTHY="false"  # no .meta → can't retry → mark unhealthy
            fi
        fi
    else
        # Sentinel doesn't exist (shouldn't happen after wait, but be defensive)
        STATUS="SENTINEL_TIMEOUT"
        EXIT_CODE="124"
        HEALTHY="false"
    fi

    # Monotonic health: if this tool was already marked unhealthy, keep it
    if [[ "$(get_tool_healthy "$TOOL")" == "false" ]]; then
        HEALTHY="false"
    fi
    if [[ "$HEALTHY" == "false" ]]; then
        set_tool_unhealthy "$TOOL"
    fi

    RESULTS+=("REVIEWER_FILE=$OUTPUT|TOOL=$TOOL|STATUS=$STATUS|EXIT_CODE=$EXIT_CODE|HEALTHY=$HEALTHY")
done

# --- 3. Retry empty outputs using .meta files ---
if [[ ${#RETRY_FILES[@]} -gt 0 ]]; then
    RETRY_SENTINELS=()
    # F10 fix: compute max retry timeout from original reviewer timeouts + grace
    MAX_RETRY_TIMEOUT=180
    for j in "${!RETRY_FILES[@]}"; do
        ORIG_OUTPUT="${RETRY_FILES[$j]}"
        META="${ORIG_OUTPUT}.meta"
        RETRY_OUTPUT="${ORIG_OUTPUT%.txt}-retry.txt"
        ORIG_TIMEOUT="${RETRY_TIMEOUTS[$j]}"
        RETRY_WAIT=$(( ORIG_TIMEOUT + 60 ))
        if [[ $RETRY_WAIT -gt $MAX_RETRY_TIMEOUT ]]; then
            MAX_RETRY_TIMEOUT=$RETRY_WAIT
        fi

        # Parse .meta file (full parse for retry command reconstruction)
        META_TOOL=""
        META_TIMEOUT=""
        META_CAPTURE=""
        META_CMD=""
        META_ORIG_OUTPUT=""
        while IFS= read -r meta_line || [[ -n "$meta_line" ]]; do
            meta_key="${meta_line%%=*}"
            meta_val="${meta_line#*=}"
            case "$meta_key" in
                TOOL)           META_TOOL="$meta_val" ;;
                TIMEOUT)        META_TIMEOUT="$meta_val" ;;
                CAPTURE_STDOUT) META_CAPTURE="$meta_val" ;;
                OUTPUT_FILE)    META_ORIG_OUTPUT="$meta_val" ;;
                CMD)            META_CMD="$meta_val" ;;
            esac
        done < "$META"

        if [[ -z "$META_CMD" || -z "$META_TOOL" ]]; then
            continue
        fi

        # Build retry command: run-external-reviewer.sh with updated output path
        RETRY_ARGS=(--tool "$META_TOOL" --output "$RETRY_OUTPUT" --timeout "${META_TIMEOUT:-120}")
        if [[ "$META_CAPTURE" == "true" ]]; then
            RETRY_ARGS+=(--capture-stdout)
        fi
        RETRY_ARGS+=(--)

        # Reconstruct command from shell-quoted CMD, replacing original output path
        # The CMD was saved via printf '%q', so eval reconstructs the original args
        RECONSTRUCTED_CMD="$META_CMD"
        # Replace original output path with retry path in the reconstructed command
        if [[ -n "$META_ORIG_OUTPUT" ]]; then
            RECONSTRUCTED_CMD="${RECONSTRUCTED_CMD//$META_ORIG_OUTPUT/$RETRY_OUTPUT}"
        fi

        # Launch retry in background — eval is intentional: CMD was serialized via
        # printf '%q' and must be re-expanded to reconstruct original arg boundaries.
        # shellcheck disable=SC2294
        eval "$(printf '%q ' "$SCRIPT_DIR/run-external-reviewer.sh" "${RETRY_ARGS[@]}") $RECONSTRUCTED_CMD" >/dev/null 2>&1 &
        RETRY_SENTINELS+=("${RETRY_OUTPUT}.done")
    done

    # Wait for retry sentinels
    if [[ ${#RETRY_SENTINELS[@]} -gt 0 ]]; then
        "$SCRIPT_DIR/wait-for-reviewers.sh" --timeout "$MAX_RETRY_TIMEOUT" "${RETRY_SENTINELS[@]}" >/dev/null 2>&1 || true

        # Check retry results and update
        for j in "${!RETRY_FILES[@]}"; do
            ORIG_OUTPUT="${RETRY_FILES[$j]}"
            RETRY_OUTPUT="${ORIG_OUTPUT%.txt}-retry.txt"
            RETRY_SENTINEL="${RETRY_OUTPUT}.done"
            IDX="${RETRY_INDICES[$j]}"
            TOOL=$(derive_tool "$ORIG_OUTPUT")

            if [[ -f "$RETRY_SENTINEL" ]]; then
                RETRY_EXIT=$(cat "$RETRY_SENTINEL" 2>/dev/null || echo "99")
                if [[ "$RETRY_EXIT" == "0" && -s "$RETRY_OUTPUT" ]]; then
                    # F4 fix: retry succeeded — tool is healthy (retry recovered from transient failure)
                    HEALTHY="true"
                    # Still respect monotonic health from PRIOR calls (via get_tool_healthy)
                    if [[ "$(get_tool_healthy "$TOOL")" == "false" ]]; then
                        HEALTHY="false"
                    fi
                    RESULTS[IDX]="REVIEWER_FILE=$RETRY_OUTPUT|TOOL=$TOOL|STATUS=OK|EXIT_CODE=0|HEALTHY=$HEALTHY"
                else
                    # Retry also failed — NOW mark tool unhealthy
                    set_tool_unhealthy "$TOOL"
                    RESULTS[IDX]="REVIEWER_FILE=$ORIG_OUTPUT|TOOL=$TOOL|STATUS=EMPTY_OUTPUT|EXIT_CODE=0|HEALTHY=false"
                fi
            else
                # Retry sentinel never appeared — mark unhealthy
                set_tool_unhealthy "$TOOL"
                RESULTS[IDX]="REVIEWER_FILE=$ORIG_OUTPUT|TOOL=$TOOL|STATUS=EMPTY_OUTPUT|EXIT_CODE=0|HEALTHY=false"
            fi
        done
    fi
fi

# --- 4. Emit structured results ---
FIRST=true
for result in "${RESULTS[@]}"; do
    if [[ "$FIRST" == "true" ]]; then
        FIRST=false
    else
        echo ""
    fi
    # Convert pipe-delimited to newlines
    echo "$result" | tr '|' '\n'
done

# --- 5. Write health file (if requested, monotonic per tool) ---
# F2 fix: uses CODEX_TOOL_HEALTHY/CURSOR_TOOL_HEALTHY which were seeded from
# the existing health file (if any) and only downgraded during this run.
if [[ -n "$WRITE_HEALTH" ]]; then
    HEALTH_TMPFILE=$(mktemp "${WRITE_HEALTH}.tmp.XXXXXX")
    {
        echo "CODEX_HEALTHY=$CODEX_TOOL_HEALTHY"
        echo "CURSOR_HEALTHY=$CURSOR_TOOL_HEALTHY"
    } > "$HEALTH_TMPFILE"
    mv "$HEALTH_TMPFILE" "$WRITE_HEALTH"
fi
