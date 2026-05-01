#!/usr/bin/env bash
# snapshot-untracked.sh — Capture a sorted list of untracked files for pre-review baseline.
#
# Usage:
#   snapshot-untracked.sh --output <file>
#
# On success, writes a sorted list of untracked paths to <file> via atomic rename.
# On ANY failure (git, sort, mv), removes both the temp file and <file> so the
# downstream consumer (check-review-changes.sh) sees UNTRACKED_BASELINE=missing
# and degrades gracefully (issue #651).
#
# Always exits 0 — callers must never abort on snapshot failure.

set -uo pipefail

OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="${2:?--output requires a value}"; shift 2 ;;
        *) echo "snapshot-untracked.sh: unknown flag: $1" >&2; exit 0 ;;
    esac
done

if [[ -z "$OUTPUT" ]]; then
    echo "snapshot-untracked.sh: --output is required" >&2
    exit 0
fi

TMP="${OUTPUT}.tmp"

if git ls-files --others --exclude-standard 2>/dev/null \
    | LC_ALL=C sort > "$TMP" \
    && mv -f "$TMP" "$OUTPUT"; then
    exit 0
fi

rm -f "$OUTPUT" "$TMP"
exit 0
