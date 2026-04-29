#!/usr/bin/env bash
# collect-agent-results.sh — Collect, validate, and optionally retry external reviewer outputs.
#
# Consolidates the post-launch validation+retry pattern used across all skills.
# Wraps wait-for-reviewers.sh, validates each output, retries once on empty via
# .meta files written by run-external-agent.sh, and emits structured results.
#
# Usage:
#   collect-agent-results.sh --timeout <seconds> [--write-health <path>] \
#     [--substantive-validation] <output-file> [<output-file> ...]
#
# Options:
#   --timeout <seconds>            Timeout for wait-for-reviewers.sh (e.g., 1860)
#   --write-health <path>          Write updated CODEX_HEALTHY/CURSOR_HEALTHY to file.
#                                  Health is monotonic per tool: any failure sets the tool
#                                  permanently unhealthy. A later successful instance does
#                                  NOT flip it back to healthy.
#                                  If the file already exists, prior health state is read
#                                  and merged monotonically (prior false is preserved).
#   --substantive-validation       After the existing non-empty + retry path settles,
#                                  invoke scripts/validate-research-output.sh on each
#                                  STATUS=OK entry. On validator failure, rewrite the
#                                  entry as STATUS=NOT_SUBSTANTIVE | HEALTHY=false |
#                                  FAILURE_REASON=<sanitized validator diagnostic>
#                                  and call set_tool_unhealthy to preserve health
#                                  monotonicity. Default OFF — opt-in per caller.
#                                  Currently opted in by: /research research phase
#                                  (Standard / Deep), /research validation phase,
#                                  /review Step 3a, /implement Step 5 quick-mode
#                                  review, /design Step 3 plan-review.
#                                  Closes #416 (Phase 3 of umbrella #413), #661.
#   --validation-mode              Modifier for --substantive-validation: forwards
#                                  --validation-mode to validate-research-output.sh
#                                  so its preset (NO_ISSUES_FOUND short-circuit + 30-
#                                  word floor) applies. Use for short reviewer-style
#                                  outputs whose contract is "numbered findings ...
#                                  If NO issues, output exactly NO_ISSUES_FOUND" —
#                                  /research validation phase, /review, /implement
#                                  Step 5 quick-mode, /design plan-review. The
#                                  /research research phase deliberately omits this
#                                  modifier because its outputs are 2-3-paragraph
#                                  prose, not short findings. No effect when
#                                  --substantive-validation is not also passed.
#                                  See docs/external-reviewers.md Output Validation
#                                  for the per-skill opt-in matrix.
#
# Arguments:
#   One or more output file paths (from run-external-agent.sh invocations).
#   Sentinel paths are derived by appending .done to each output file.
#   Metadata paths are derived by appending .meta to each output file.
#
# Output (KEY=value blocks on stdout, one block per reviewer, separated by blank lines):
#   REVIEWER_FILE=<output-path>
#   TOOL=<codex|cursor|unknown>
#   STATUS=<OK|TIMED_OUT|FAILED|EMPTY_OUTPUT|SENTINEL_TIMEOUT|NOT_SUBSTANTIVE>
#   EXIT_CODE=<N>
#   HEALTHY=<true|false>
#   FAILURE_REASON=<explanation>  (non-empty when STATUS != OK; explains the cause of failure)
#
# Exit codes:
#   0 — normal completion (results are informational, not errors)
#   1 — argument error (missing required option or unknown flag)

# No -e: exit codes from reviewer subprocesses and retries are informational.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TIMEOUT=""
WRITE_HEALTH=""
SUBSTANTIVE_VALIDATION="false"
VALIDATION_MODE="false"
OUTPUT_FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            TIMEOUT="${2:?--timeout requires a value}"; shift 2 ;;
        --write-health)
            WRITE_HEALTH="${2:?--write-health requires a path}"; shift 2 ;;
        --substantive-validation)
            SUBSTANTIVE_VALIDATION="true"; shift ;;
        --validation-mode)
            VALIDATION_MODE="true"; shift ;;
        --help)
            echo "Usage: collect-agent-results.sh --timeout <seconds> [--write-health <path>] [--substantive-validation [--validation-mode]] <output-file>..." >&2
            exit 0 ;;
        -*)
            echo "collect-agent-results.sh: unknown option: $1" >&2; exit 1 ;;
        *)
            OUTPUT_FILES+=("$1"); shift ;;
    esac
done

if [[ -z "$TIMEOUT" ]]; then
    echo "collect-agent-results.sh: --timeout is required" >&2
    exit 1
fi

if [[ ${#OUTPUT_FILES[@]} -eq 0 ]]; then
    echo "collect-agent-results.sh: at least one output file is required" >&2
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
# This preserves monotonicity across separate collect-agent-results.sh calls.
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

# --- Helper: build failure reason from .diag file or status ---
build_failure_reason() {
    local output_file="$1"
    local status="$2"
    local exit_code="$3"
    local diag_file="${output_file}.diag"

    if [[ -f "$diag_file" ]]; then
        cat "$diag_file"
        return
    fi

    # Fallback: construct reason from status and exit code
    case "$status" in
        SENTINEL_TIMEOUT) echo "Process did not complete (sentinel file missing — possible crash or system kill)" ;;
        TIMED_OUT)        echo "Process timed out (exit code 124)" ;;
        FAILED)           echo "Process failed with exit code $exit_code" ;;
        EMPTY_OUTPUT)     echo "Process exited successfully but produced no output" ;;
        *)                echo "Unknown failure (status=$status, exit_code=$exit_code)" ;;
    esac
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
    FAILURE_REASON=""

    # F1 fix: strip .done suffix to match wait-for-reviewers.sh output format
    SENTINEL_BASE=$(basename "$SENTINEL" .done)
    if is_timed_out "$SENTINEL_BASE"; then
        # wait-for-reviewers.sh reported TIMEOUT (sentinel never appeared)
        STATUS="SENTINEL_TIMEOUT"
        EXIT_CODE="124"
        HEALTHY="false"
        FAILURE_REASON=$(build_failure_reason "$OUTPUT" "$STATUS" "$EXIT_CODE")
    elif [[ -f "$SENTINEL" ]]; then
        EXIT_CODE=$(cat "$SENTINEL" 2>/dev/null || echo "99")
        if [[ "$EXIT_CODE" == "124" ]]; then
            STATUS="TIMED_OUT"
            HEALTHY="false"
            FAILURE_REASON=$(build_failure_reason "$OUTPUT" "$STATUS" "$EXIT_CODE")
        elif [[ "$EXIT_CODE" != "0" ]]; then
            STATUS="FAILED"
            HEALTHY="false"
            FAILURE_REASON=$(build_failure_reason "$OUTPUT" "$STATUS" "$EXIT_CODE")
        elif [[ ! -s "$OUTPUT" ]]; then
            # F4 fix: empty output is a retry candidate, NOT an immediate health failure.
            # Health is only set to false after retry also fails (see section 3 below).
            STATUS="EMPTY_OUTPUT"
            HEALTHY="true"  # tentative — will be set false if retry fails
            FAILURE_REASON=$(build_failure_reason "$OUTPUT" "$STATUS" "$EXIT_CODE")
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
        FAILURE_REASON=$(build_failure_reason "$OUTPUT" "$STATUS" "$EXIT_CODE")
    fi

    # Monotonic health: if this tool was already marked unhealthy, keep it
    if [[ "$(get_tool_healthy "$TOOL")" == "false" ]]; then
        HEALTHY="false"
    fi
    if [[ "$HEALTHY" == "false" ]]; then
        set_tool_unhealthy "$TOOL"
    fi

    RESULTS+=("REVIEWER_FILE=$OUTPUT|TOOL=$TOOL|STATUS=$STATUS|EXIT_CODE=$EXIT_CODE|HEALTHY=$HEALTHY|FAILURE_REASON=$FAILURE_REASON")
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

        # Build retry command: run-external-agent.sh with updated output path
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
        eval "$(printf '%q ' "$SCRIPT_DIR/run-external-agent.sh" "${RETRY_ARGS[@]}") $RECONSTRUCTED_CMD" >/dev/null 2>&1 &
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
                    RESULTS[IDX]="REVIEWER_FILE=$RETRY_OUTPUT|TOOL=$TOOL|STATUS=OK|EXIT_CODE=0|HEALTHY=$HEALTHY|FAILURE_REASON="
                else
                    # Retry also failed — NOW mark tool unhealthy
                    set_tool_unhealthy "$TOOL"
                    if [[ "$RETRY_EXIT" == "124" ]]; then
                        RETRY_STATUS="TIMED_OUT"
                    elif [[ "$RETRY_EXIT" != "0" ]]; then
                        RETRY_STATUS="FAILED"
                    else
                        RETRY_STATUS="EMPTY_OUTPUT"
                    fi
                    RETRY_REASON=$(build_failure_reason "$RETRY_OUTPUT" "$RETRY_STATUS" "$RETRY_EXIT")
                    RESULTS[IDX]="REVIEWER_FILE=$ORIG_OUTPUT|TOOL=$TOOL|STATUS=EMPTY_OUTPUT|EXIT_CODE=0|HEALTHY=false|FAILURE_REASON=Retry also failed: $RETRY_REASON"
                fi
            else
                # Retry sentinel never appeared — mark unhealthy
                set_tool_unhealthy "$TOOL"
                RESULTS[IDX]="REVIEWER_FILE=$ORIG_OUTPUT|TOOL=$TOOL|STATUS=EMPTY_OUTPUT|EXIT_CODE=0|HEALTHY=false|FAILURE_REASON=Retry process did not complete (sentinel file missing)"
            fi
        done
    fi
fi

# --- 3.5. Substantive-content validation (opt-in via --substantive-validation) ---
# After section 3 (retry) every entry in RESULTS reflects its final status. For
# each entry whose STATUS=OK, invoke validate-research-output.sh on its file
# (REVIEWER_FILE — the retry path may have set it to a *-retry.txt). On
# validator failure, rewrite the entry to STATUS=NOT_SUBSTANTIVE with the
# sanitized diagnostic in FAILURE_REASON and HEALTHY=false; call
# set_tool_unhealthy to preserve per-tool health monotonicity. Closes #416.
if [[ "$SUBSTANTIVE_VALIDATION" == "true" ]]; then
    VALIDATOR="$SCRIPT_DIR/validate-research-output.sh"
    VAL_ARGS=()
    if [[ "$VALIDATION_MODE" == "true" ]]; then
        VAL_ARGS+=(--validation-mode)
    fi
    for j in "${!RESULTS[@]}"; do
        entry="${RESULTS[$j]}"
        # Precise field-by-field extraction. Fields 1-5 (REVIEWER_FILE, TOOL,
        # STATUS, EXIT_CODE, HEALTHY) never contain '|' by construction (paths
        # are tmpdir paths; tools are codex|cursor|unknown; STATUS/HEALTHY are
        # fixed enums; EXIT_CODE is numeric). FAILURE_REASON (field 6) is the
        # only field that may carry user content, and it's the trailing field
        # — its content cannot collide with the field-1..5 prefixes.
        rf_field="${entry%%|*}"             # REVIEWER_FILE=<path>
        REVIEWER_FILE="${rf_field#REVIEWER_FILE=}"
        rest1="${entry#*|}"                 # TOOL=<name>|...
        tool_field="${rest1%%|*}"           # TOOL=<name>
        ENTRY_TOOL="${tool_field#TOOL=}"
        rest2="${rest1#*|}"                 # STATUS=<S>|...
        status_field="${rest2%%|*}"         # STATUS=<S>
        ENTRY_STATUS="${status_field#STATUS=}"

        if [[ "$ENTRY_STATUS" != "OK" ]]; then
            continue
        fi

        # Run validator. Diagnostic on stdout; capture both stdout and stderr.
        # The collector runs without `set -e`, so a non-zero exit from the
        # validator does NOT abort the loop.
        # bash 3.2 portability: `"${VAL_ARGS[@]}"` on an empty array fires
        # `unbound variable` under `set -u` on macOS /bin/bash (3.2.57); the
        # `${arr[@]+"${arr[@]}"}` guard expands to nothing when empty. #511.
        DIAG=$("$VALIDATOR" "${VAL_ARGS[@]+"${VAL_ARGS[@]}"}" "$REVIEWER_FILE" 2>&1)
        VAL_EXIT=$?
        if [[ "$VAL_EXIT" -ne 0 ]]; then
            # Sanitize: strip '|' (would corrupt pipe-delimited RESULTS), replace
            # newlines with spaces, collapse whitespace, truncate to 200 chars.
            DIAG_SAN=$(printf '%s' "$DIAG" | tr '|\n' '/ ' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//' | cut -c1-200)
            RESULTS[j]="REVIEWER_FILE=$REVIEWER_FILE|TOOL=$ENTRY_TOOL|STATUS=NOT_SUBSTANTIVE|EXIT_CODE=0|HEALTHY=false|FAILURE_REASON=$DIAG_SAN"
            set_tool_unhealthy "$ENTRY_TOOL"
        fi
    done
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
if [[ -n "$WRITE_HEALTH" && "$WRITE_HEALTH" != "/dev/null" ]]; then
    HEALTH_TMPFILE=$(mktemp "${WRITE_HEALTH}.tmp.XXXXXX")
    {
        echo "CODEX_HEALTHY=$CODEX_TOOL_HEALTHY"
        echo "CURSOR_HEALTHY=$CURSOR_TOOL_HEALTHY"
    } > "$HEALTH_TMPFILE"
    mv "$HEALTH_TMPFILE" "$WRITE_HEALTH"
fi
