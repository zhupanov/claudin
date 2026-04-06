#!/usr/bin/env bash
# gather-branch-context.sh — Gather git diff, file list, and commit log for
# the current branch vs main.
#
# Writes each output to a separate file in the specified output directory,
# then emits the file paths as key=value output to stdout.
#
# Usage:
#   gather-branch-context.sh --output-dir <path>
#
# Arguments:
#   --output-dir — Directory to write output files into (must exist)
#
# Creates:
#   <output-dir>/diff.txt      — Full diff (git diff main...HEAD)
#   <output-dir>/file-list.txt — Changed file names (git diff main...HEAD --name-only)
#   <output-dir>/commit-log.txt — Commit log (git log main...HEAD --oneline)
#
# Outputs (key=value to stdout):
#   DIFF_FILE=<path>
#   FILE_LIST_FILE=<path>
#   COMMIT_LOG_FILE=<path>
#
# Exit codes:
#   0 — success
#   1 — usage/argument error or git command failure

set -euo pipefail

usage() { echo "Usage: gather-branch-context.sh --output-dir <path>" >&2; }

# --- Parse arguments ---
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir) OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "ERROR: --output-dir is required" >&2
    usage; exit 1
fi

if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "ERROR: output directory does not exist: $OUTPUT_DIR" >&2
    exit 1
fi

# --- Gather context ---
DIFF_FILE="$OUTPUT_DIR/diff.txt"
FILE_LIST_FILE="$OUTPUT_DIR/file-list.txt"
COMMIT_LOG_FILE="$OUTPUT_DIR/commit-log.txt"

git diff main...HEAD > "$DIFF_FILE"
git diff main...HEAD --name-only > "$FILE_LIST_FILE"
git log main...HEAD --oneline > "$COMMIT_LOG_FILE"

# --- Emit output ---
echo "DIFF_FILE=$DIFF_FILE"
echo "FILE_LIST_FILE=$FILE_LIST_FILE"
echo "COMMIT_LOG_FILE=$COMMIT_LOG_FILE"
