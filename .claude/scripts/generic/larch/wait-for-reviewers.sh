#!/usr/bin/env bash
# wait-for-reviewers.sh — Poll for external reviewer sentinel files with compact progress.
#
# Usage:
#   wait-for-reviewers.sh [--timeout <seconds>] <sentinel.done> [sentinel2.done ...]
#
# Sentinel files are the .done files created by run-external-reviewer.sh.
# Progress (dots, status lines) goes to stderr.
# Machine-parseable results (DONE/TIMEOUT lines) go to stdout.
# Always exits 0 for normal operation (including timeouts) — callers inspect stdout
# to determine which reviewers completed vs timed out. Exits 1 only for usage errors.
#
# The default timeout is 960 seconds (16 minutes), matching the run-external-reviewer.sh
# default of 15 minutes + 1 minute grace period. Override with --timeout if a different
# wrapper timeout was used.

# No -e: script always exits 0 for normal operation; subshell failures must not abort.
set -uo pipefail

# --- Parse arguments ---
usage() { echo "Usage: wait-for-reviewers.sh [--timeout SECONDS] <sentinel.done> [sentinel2.done ...]" >&2; }

TIMEOUT=960
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) TIMEOUT="${2:?--timeout requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *) break ;;
    esac
done

case "$TIMEOUT" in
    ''|*[!0-9]*) echo "Error: --timeout value must be a positive integer, got '$TIMEOUT'" >&2; exit 1 ;;
esac

if [[ $# -eq 0 ]]; then
    echo "ERROR: at least one sentinel file path is required" >&2
    usage; exit 1
fi

TOTAL=$#
MARKER_DIR=$(mktemp -d /tmp/wait-reviewers-XXXXXX) || { echo "fatal: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$MARKER_DIR"' EXIT

# read_exit_code <sentinel-file> — read and validate the exit code from a sentinel file.
read_exit_code() {
    local code
    code=$(tr -d '[:space:]' < "$1" 2>/dev/null)
    case "$code" in
        ''|*[!0-9]*) code="unknown" ;;
    esac
    printf '%s' "$code"
}

# check_sentinels — scan all sentinel files, update markers and found_count.
check_sentinels() {
    local idx=0
    for sentinel in "$@"; do
        idx=$((idx + 1))
        if [ -f "$MARKER_DIR/$idx" ]; then
            continue
        fi
        if [ -f "$sentinel" ]; then
            local exit_code
            exit_code=$(read_exit_code "$sentinel")
            echo "$exit_code" > "$MARKER_DIR/$idx"
            found_count=$((found_count + 1))
            printf "\n✓ %s: exit=%s\n" "$(basename "$sentinel" .done)" "$exit_code" >&2
        fi
    done
}

# --- Polling loop ---
SECONDS=0
found_count=0
checks=0

# Check before first sleep — detect pre-existing sentinels immediately
check_sentinels "$@"

while [ "$found_count" -lt "$TOTAL" ] && [ "$SECONDS" -lt "$TIMEOUT" ]; do
    # Print dot progress
    printf "." >&2
    checks=$((checks + 1))
    # Print status line every 12 checks (~1 minute)
    if [ $((checks % 12)) -eq 0 ]; then
        printf "\n⏳ Waiting: %dm elapsed, %d checks, %d/%d done\n" \
            "$((SECONDS / 60))" "$checks" "$found_count" "$TOTAL" >&2
    fi

    sleep 5

    check_sentinels "$@"
done

# Snapshot elapsed time before summary output
ELAPSED=$SECONDS

# --- Summary output (stdout, machine-parseable) ---
printf "\n" >&2
idx=0
timed_out=0
for sentinel in "$@"; do
    idx=$((idx + 1))
    name=$(basename "$sentinel" .done)
    if [ -f "$MARKER_DIR/$idx" ]; then
        exit_code=$(cat "$MARKER_DIR/$idx" 2>/dev/null)
        echo "DONE $name: exit=$exit_code"
    else
        echo "TIMEOUT $name"
        timed_out=$((timed_out + 1))
    fi
done

if [ "$timed_out" -gt 0 ]; then
    printf "⚠ %d/%d reviewer(s) timed out after %d seconds\n" "$timed_out" "$TOTAL" "$TIMEOUT" >&2
else
    printf "✓ All %d reviewer(s) completed in %ds\n" "$TOTAL" "$ELAPSED" >&2
fi

exit 0
