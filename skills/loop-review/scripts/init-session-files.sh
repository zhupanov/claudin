#!/usr/bin/env bash
# init-session-files.sh — Initialize loop-review tracking files.
#
# Creates the deferred-accumulated.md, warnings.md, and counter files
# (pr-count.txt, impl-count.txt, defer-count.txt) in the session tmpdir.
#
# Usage:
#   init-session-files.sh --dir <tmpdir-path>
#
# Arguments:
#   --dir — Path to the session temp directory (must exist)
#
# Outputs (key=value to stdout):
#   INITIALIZED=true
#
# Exit codes:
#   0 — success
#   1 — usage/argument error or directory does not exist

set -euo pipefail

usage() { echo "Usage: init-session-files.sh --dir <tmpdir-path>" >&2; }

DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="${2:?--dir requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$DIR" ]]; then
    echo "ERROR: --dir is required" >&2
    usage; exit 1
fi

if [[ ! -d "$DIR" ]]; then
    echo "ERROR: directory does not exist: $DIR" >&2
    exit 1
fi

touch "$DIR/deferred-accumulated.md"
touch "$DIR/warnings.md"
echo "0" > "$DIR/pr-count.txt"
echo "0" > "$DIR/impl-count.txt"
echo "0" > "$DIR/defer-count.txt"

echo "INITIALIZED=true"
