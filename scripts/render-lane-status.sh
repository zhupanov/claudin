#!/usr/bin/env bash
# render-lane-status.sh — format the per-lane attribution record into the two
# header lines used by /research's Step 3 final report.
#
# Reads a small KV file holding the codified status of each external lane
# (Research × Cursor/Codex + Validation × Cursor/Codex) and emits two
# `<NAME>_HEADER=<value>` lines on stdout that SKILL.md Step 3 substitutes
# into the report. The Code (Claude code-reviewer subagent) lane has no
# fallback path and is rendered as a hard-coded ✅.
#
# Usage:
#   render-lane-status.sh --input <path>
#
# Input KV schema (8 keys, all optional — missing keys render as `(unknown)`):
#   RESEARCH_CURSOR_STATUS=<token>
#   RESEARCH_CURSOR_REASON=<short reason text>
#   RESEARCH_CODEX_STATUS=<token>
#   RESEARCH_CODEX_REASON=<short reason text>
#   VALIDATION_CURSOR_STATUS=<token>
#   VALIDATION_CURSOR_REASON=<short reason text>
#   VALIDATION_CODEX_STATUS=<token>
#   VALIDATION_CODEX_REASON=<short reason text>
#
# Status tokens (canonical):
#   ok                            → ✅
#   fallback_binary_missing       → Claude-fallback (binary missing)
#   fallback_probe_failed         → Claude-fallback (probe failed: <reason>)
#                                   (parenthetical omitted when REASON is empty)
#   fallback_runtime_timeout      → Claude-fallback (runtime timeout)
#   fallback_runtime_failed       → Claude-fallback (runtime failed: <reason>)
#                                   (parenthetical omitted when REASON is empty)
#   '' (missing or empty)         → (unknown)   (no stderr warning)
#   <anything else, non-empty>    → (unknown)   + stderr warning
#
# Reason sanitization (applied after parse, before render):
#   - collapse all whitespace runs (incl. \n, \t, \r) into single spaces
#   - strip embedded `=` and `|` characters
#   - trim leading/trailing whitespace
#   - truncate to 80 characters
#
# Output (KEY=value on stdout):
#   RESEARCH_HEADER=3 agents (Cursor: <rendered>, Codex: <rendered>)
#   VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: <rendered>, Codex: <rendered>)
#
# Exit codes:
#   0 — success
#   1 — usage error (missing flag, unknown flag)
#   2 — I/O failure (input file missing or unreadable)
#
# Stderr:
#   Usage errors (exit 1):
#     `**⚠ render-lane-status: --input is required**`
#     `**⚠ render-lane-status: --input requires a value**`
#     `**⚠ render-lane-status: unknown flag: <flag>**`
#   Input-file errors (exit 2):
#     `**⚠ render-lane-status: input file missing**`
#     `**⚠ render-lane-status: input file unreadable**`
#   Per-occurrence warnings (exit 0, per occurrence):
#     `**⚠ render-lane-status: unknown status token <token>**`

set -euo pipefail

fail_usage() {
    echo "**⚠ render-lane-status: $1**" >&2
    exit 1
}

INPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --input)
            [ $# -ge 2 ] || fail_usage "--input requires a value"
            INPUT="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            fail_usage "unknown flag: $1" ;;
    esac
done

[ -n "$INPUT" ] || fail_usage "--input is required"

if [ ! -f "$INPUT" ]; then
    echo "**⚠ render-lane-status: input file missing**" >&2
    exit 2
fi
if [ ! -r "$INPUT" ]; then
    echo "**⚠ render-lane-status: input file unreadable**" >&2
    exit 2
fi

# Parse the KV file. Use prefix-strip (not `cut -d=`) so values containing `=`
# don't get truncated. Each line: KEY=VALUE; lines without `=` and lines with
# unrecognized keys are silently ignored.
RESEARCH_CURSOR_STATUS=""
RESEARCH_CURSOR_REASON=""
RESEARCH_CODEX_STATUS=""
RESEARCH_CODEX_REASON=""
VALIDATION_CURSOR_STATUS=""
VALIDATION_CURSOR_REASON=""
VALIDATION_CODEX_STATUS=""
VALIDATION_CODEX_REASON=""

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ''|'#'*) continue ;;
        *=*)
            key="${line%%=*}"
            value="${line#*=}"
            ;;
        *)
            continue ;;
    esac
    case "$key" in
        RESEARCH_CURSOR_STATUS)    RESEARCH_CURSOR_STATUS="$value" ;;
        RESEARCH_CURSOR_REASON)    RESEARCH_CURSOR_REASON="$value" ;;
        RESEARCH_CODEX_STATUS)     RESEARCH_CODEX_STATUS="$value" ;;
        RESEARCH_CODEX_REASON)     RESEARCH_CODEX_REASON="$value" ;;
        VALIDATION_CURSOR_STATUS)  VALIDATION_CURSOR_STATUS="$value" ;;
        VALIDATION_CURSOR_REASON)  VALIDATION_CURSOR_REASON="$value" ;;
        VALIDATION_CODEX_STATUS)   VALIDATION_CODEX_STATUS="$value" ;;
        VALIDATION_CODEX_REASON)   VALIDATION_CODEX_REASON="$value" ;;
    esac
done < "$INPUT"

# sanitize_reason — collapse whitespace, strip = and |, trim, truncate to 80.
# Defense-in-depth: the writer is supposed to sanitize before heredoc-write,
# but we apply the same rules here so a misformed file never breaks markdown.
sanitize_reason() {
    local s="$1"
    # Strip embedded = and | characters first (stripping can create new
    # whitespace gaps; the subsequent collapse pass merges them).
    s="${s//=/}"
    s="${s//|/}"
    # Collapse all whitespace runs (incl. tabs, newlines, CRs) to single space.
    s="$(printf '%s' "$s" | tr -s '[:space:]' ' ')"
    # Trim leading/trailing whitespace.
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    # Truncate to 80 characters.
    if [ "${#s}" -gt 80 ]; then
        s="${s:0:80}"
    fi
    printf '%s' "$s"
}

# render_lane — given a status token and a (possibly empty) reason, emit the
# human-readable string. Emits a stderr warning for unknown tokens.
render_lane() {
    local status="$1"
    local reason="$2"
    local clean
    clean="$(sanitize_reason "$reason")"
    case "$status" in
        ok)
            printf '✅' ;;
        fallback_binary_missing)
            printf 'Claude-fallback (binary missing)' ;;
        fallback_probe_failed)
            if [ -n "$clean" ]; then
                printf 'Claude-fallback (probe failed: %s)' "$clean"
            else
                printf 'Claude-fallback (probe failed)'
            fi ;;
        fallback_runtime_timeout)
            printf 'Claude-fallback (runtime timeout)' ;;
        fallback_runtime_failed)
            if [ -n "$clean" ]; then
                printf 'Claude-fallback (runtime failed: %s)' "$clean"
            else
                printf 'Claude-fallback (runtime failed)'
            fi ;;
        '')
            printf '(unknown)' ;;
        *)
            echo "**⚠ render-lane-status: unknown status token $status**" >&2
            printf '(unknown)' ;;
    esac
}

RESEARCH_CURSOR_RENDERED="$(render_lane "$RESEARCH_CURSOR_STATUS" "$RESEARCH_CURSOR_REASON")"
RESEARCH_CODEX_RENDERED="$(render_lane "$RESEARCH_CODEX_STATUS" "$RESEARCH_CODEX_REASON")"
VALIDATION_CURSOR_RENDERED="$(render_lane "$VALIDATION_CURSOR_STATUS" "$VALIDATION_CURSOR_REASON")"
VALIDATION_CODEX_RENDERED="$(render_lane "$VALIDATION_CODEX_STATUS" "$VALIDATION_CODEX_REASON")"

# 3-lane invariant pinned in research-phase.md and validation-phase.md.
printf 'RESEARCH_HEADER=3 agents (Cursor: %s, Codex: %s)\n' \
    "$RESEARCH_CURSOR_RENDERED" "$RESEARCH_CODEX_RENDERED"
printf 'VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: %s, Codex: %s)\n' \
    "$VALIDATION_CURSOR_RENDERED" "$VALIDATION_CODEX_RENDERED"

exit 0
