#!/usr/bin/env bash
# check-review-changes.sh — Check if the code review step modified the working tree.
#
# Detects review-induced changes via three sources:
#   - staged modifications (git diff --cached)
#   - unstaged modifications (git diff)
#   - new untracked files (current untracked set minus a pre-/review baseline)
#
# The untracked dimension requires a pre-/review baseline file (sorted list of
# untracked paths captured before /review ran). Without a readable baseline,
# the untracked dimension is ignored (UNTRACKED_BASELINE=missing) — this
# degrades gracefully rather than treating every pre-existing untracked file
# as review-created (which would reintroduce the false-positive bug from #651).
#
# A readable file (including zero-byte) means UNTRACKED_BASELINE=present and
# the delta is comm -23 (current sorted) (baseline). A zero-byte baseline
# legitimately represents "no untracked files at snapshot time," so all
# current untracked are considered review-created.
#
# Stdout contract — TWO keys ALWAYS emitted on every invocation in stable
# order. Consumers must parse with key-based grep/awk, never eval/source:
#   FILES_CHANGED=true|false
#   UNTRACKED_BASELINE=present|missing
#
# Usage:
#   check-review-changes.sh [--baseline <path>]
#
# Exit codes:
#   0 — always

set -euo pipefail

BASELINE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline)
            BASELINE="$2"
            shift 2
            ;;
        *)
            echo "ERROR=Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

UNSTAGED=$(git diff --name-only 2>/dev/null || echo "")
STAGED=$(git diff --name-only --cached 2>/dev/null || echo "")

UNTRACKED_BASELINE="missing"
UNTRACKED_DELTA=""

if [[ -n "$BASELINE" ]] && [[ -r "$BASELINE" ]]; then
    UNTRACKED_BASELINE="present"
    CURRENT=$(git ls-files --others --exclude-standard 2>/dev/null | LC_ALL=C sort || echo "")
    UNTRACKED_DELTA=$(comm -23 <(echo "$CURRENT") <(LC_ALL=C sort "$BASELINE") | sed '/^$/d' || echo "")
fi

FILES_CHANGED="false"
if [[ -n "$UNSTAGED" ]] || [[ -n "$STAGED" ]] || [[ -n "$UNTRACKED_DELTA" ]]; then
    FILES_CHANGED="true"
fi

echo "FILES_CHANGED=$FILES_CHANGED"
echo "UNTRACKED_BASELINE=$UNTRACKED_BASELINE"
