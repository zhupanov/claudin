#!/usr/bin/env bash
# run-external-reviewer.sh — Monitored wrapper for external code reviewers (Codex, Cursor).
# Launches the reviewer in the background, polls every 60s with status messages,
# kills after a configurable timeout (e.g., 30 minutes for reviews, 20 minutes for votes/sketches).
#
# Usage:
#   run-external-reviewer.sh --tool NAME --output FILE --timeout SECS [--capture-stdout] -- CMD...
#
# Options:
#   --tool            Tool name (e.g., "codex", "cursor") — used only for log messages
#   --output          Path where tool output is written
#   --timeout         Timeout in seconds (e.g., 1800 for 30 minutes)
#   --capture-stdout  Redirect the tool's stdout/stderr to the output file.
#                     Use for tools like Cursor that write results to stdout.
#                     Omit for tools like Codex that use their own output flags.
#   --               End of wrapper options. Everything after is the command to execute.
#
# Examples:
#   # Codex review (uses --output-last-message flag to write output)
#   run-external-reviewer.sh --tool codex --output /tmp/review-abc/codex-output.txt --timeout 1800 -- \
#     codex exec --full-auto -C /path/to/repo --output-last-message /tmp/review-abc/codex-output.txt "Review prompt..."
#
#   # Cursor review (stdout captured to file via --capture-stdout)
#   run-external-reviewer.sh --tool cursor --output /tmp/review-abc/cursor-output.txt --timeout 900 --capture-stdout -- \
#     cursor agent -p --force --trust --workspace /path/to/repo "Review prompt..."

set -euo pipefail

usage() { echo "Usage: run-external-reviewer.sh --tool NAME --output FILE --timeout SECS [--capture-stdout] -- CMD..." >&2; }

CAPTURE_STDOUT=false
TOOL_NAME=""
OUTPUT_FILE=""
TIMEOUT_SECONDS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool) TOOL_NAME="${2:?--tool requires a value}"; shift 2 ;;
        --output) OUTPUT_FILE="${2:?--output requires a value}"; shift 2 ;;
        --timeout) TIMEOUT_SECONDS="${2:?--timeout requires a value}"; shift 2 ;;
        --capture-stdout) CAPTURE_STDOUT=true; shift ;;
        --help) usage; exit 0 ;;
        --) shift; break ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$TOOL_NAME" ]] || [[ -z "$OUTPUT_FILE" ]] || [[ -z "$TIMEOUT_SECONDS" ]]; then
    echo "ERROR: --tool, --output, and --timeout are required" >&2
    usage; exit 1
fi

case "$TIMEOUT_SECONDS" in
    ''|*[!0-9]*) echo "ERROR: --timeout must be a positive integer, got '$TIMEOUT_SECONDS'" >&2; exit 1 ;;
esac

if [[ $# -eq 0 ]]; then
    echo "ERROR: no command specified after --" >&2
    usage; exit 1
fi

# Clear stale output, sentinel, and metadata files
rm -f "$OUTPUT_FILE" "${OUTPUT_FILE}.done" "${OUTPUT_FILE}.meta"

# Write sentinel file on ANY exit — the reliable completion signal for callers.
# Callers poll for <output-file>.done instead of waiting for runtime notifications.
# Installed BEFORE .meta write so that any early exit still creates a sentinel.
EXIT_CODE=99  # default: wrapper crashed before capturing real exit code
trap 'echo "$EXIT_CODE" > "${OUTPUT_FILE}.done" 2>/dev/null || true' EXIT

# Write metadata for collect-reviewer-results.sh retry support.
# CMD is shell-quoted via printf '%q' to preserve argument boundaries.
{
    echo "TOOL=$TOOL_NAME"
    echo "TIMEOUT=$TIMEOUT_SECONDS"
    echo "CAPTURE_STDOUT=$CAPTURE_STDOUT"
    echo "OUTPUT_FILE=$OUTPUT_FILE"
    printf 'CMD=%s\n' "$(printf '%q ' "$@")"
} > "${OUTPUT_FILE}.meta"

# Launch the reviewer in the background
if [ "$CAPTURE_STDOUT" = true ]; then
    "$@" > "$OUTPUT_FILE" 2>&1 &
else
    "$@" &
fi
PID=$!
SECONDS=0

# Poll until the process exits or times out
# Check timeout BEFORE sleeping to avoid overshooting by a full interval.
# Use 10s intervals for more responsive timeout detection.
while kill -0 "$PID" 2>/dev/null; do
    if [ "$SECONDS" -ge "$TIMEOUT_SECONDS" ]; then
        echo "⚠ ${TOOL_NAME} review: TIMED OUT after $(( TIMEOUT_SECONDS / 60 )) minutes, killing"
        kill "$PID" 2>/dev/null
        sleep 5
        kill -9 "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
        # Report diagnostics even on timeout
        OUTPUT_SIZE=0
        if [ -f "$OUTPUT_FILE" ]; then
            OUTPUT_SIZE=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
        fi
        echo "❌ ${TOOL_NAME} review: TIMED OUT (exit code 124, ${SECONDS}s elapsed, output ${OUTPUT_SIZE} bytes)"
        EXIT_CODE=124
        exit "$EXIT_CODE"
    fi
    sleep 10
    # Print progress every 60s (every 6th iteration)
    if [ $(( SECONDS % 60 )) -lt 10 ]; then
        echo "⏳ ${TOOL_NAME} review: still running ($(( SECONDS / 60 ))m elapsed)"
    fi
done

# Capture exit code without triggering set -e (wait propagates child exit code)
wait "$PID" && EXIT_CODE=0 || EXIT_CODE=$?

# Diagnostics: report completion with details to help debug failures
OUTPUT_SIZE=0
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_SIZE=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
fi

if [ "$EXIT_CODE" -ne 0 ]; then
    echo "❌ ${TOOL_NAME} review: FAILED (exit code ${EXIT_CODE}, ${SECONDS}s elapsed, output ${OUTPUT_SIZE} bytes)"
    if [ "$OUTPUT_SIZE" -gt 0 ]; then
        echo "--- ${TOOL_NAME} output (last 5 lines) ---"
        tail -5 "$OUTPUT_FILE"
        echo "--- end ---"
    fi
elif [ "$OUTPUT_SIZE" -eq 0 ]; then
    echo "⚠ ${TOOL_NAME} review: completed but OUTPUT IS EMPTY (exit code 0, ${SECONDS}s elapsed)"
    echo "This typically means ${TOOL_NAME} exited without producing findings."
else
    echo "✓ ${TOOL_NAME} review: completed (exit code 0, ${SECONDS}s elapsed, output ${OUTPUT_SIZE} bytes)"
fi
exit "$EXIT_CODE"
