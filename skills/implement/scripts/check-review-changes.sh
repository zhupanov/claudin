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
#   0 — always (including bad CLI input — see Parse-error policy below).
#
# Parse-error policy: on unknown flag or --baseline-without-path, emit an
# informational ERROR=... line on stderr and degrade to the missing-baseline
# path on stdout. The always-2-keys, exit-0 contract is preserved so callers
# (notably skills/implement/SKILL.md Step 6) parse stdout uniformly.
#
# Best-effort git probing: git diff and git ls-files are run with
# 2>/dev/null || echo "", so transient git errors degrade to "no changes
# detected on that source" rather than aborting. The script does NOT emit a
# separate health key — empty output and "git failed" are observationally
# indistinguishable on stdout. See check-review-changes.md for the full
# graceful-degradation philosophy.

set -euo pipefail

BASELINE=""
PARSE_ERROR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline)
            if [[ $# -lt 2 ]]; then
                PARSE_ERROR="--baseline requires a path argument"
                break
            fi
            BASELINE="$2"
            shift 2
            ;;
        *)
            PARSE_ERROR="Unknown argument: $1"
            break
            ;;
    esac
done

# Parse errors degrade to the missing-baseline path so the always-emit-2-keys,
# exit-0 stdout contract holds even on bad CLI input. The ERROR= line on stderr
# is informational only — callers parse stdout, not stderr or exit code.
if [[ -n "$PARSE_ERROR" ]]; then
    echo "ERROR=$PARSE_ERROR" >&2
    BASELINE=""
fi

UNSTAGED=$(git diff --name-only 2>/dev/null || echo "")
STAGED=$(git diff --name-only --cached 2>/dev/null || echo "")

UNTRACKED_BASELINE="missing"
UNTRACKED_DELTA=""

if [[ -n "$BASELINE" ]] && [[ -r "$BASELINE" ]]; then
    UNTRACKED_BASELINE="present"
    CURRENT=$(git ls-files --others --exclude-standard 2>/dev/null | LC_ALL=C sort || echo "")
    UNTRACKED_DELTA=$(comm -23 <(printf '%s\n' "$CURRENT") <(LC_ALL=C sort "$BASELINE") | sed '/^$/d' || echo "")
fi

FILES_CHANGED="false"
if [[ -n "$UNSTAGED" ]] || [[ -n "$STAGED" ]] || [[ -n "$UNTRACKED_DELTA" ]]; then
    FILES_CHANGED="true"
fi

echo "FILES_CHANGED=$FILES_CHANGED"
echo "UNTRACKED_BASELINE=$UNTRACKED_BASELINE"
