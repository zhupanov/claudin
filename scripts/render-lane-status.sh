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

# Source the shared rendering library (sanitize_reason + render_lane). The
# library is sourced by both render-lane-status.sh (standard) and
# render-deep-lane-status.sh (deep) so the token vocabulary, sanitization
# rules, and stderr-warning shape stay in lockstep across both renderers.
# RENDER_LANE_CALLER is set per consumer so unknown-token warnings attribute
# to the correct script basename (#451 FINDING_2).
RENDER_LANE_CALLER="render-lane-status"
# shellcheck source=scripts/render-lane-status-lib.sh
source "$(dirname "$0")/render-lane-status-lib.sh"

RESEARCH_CURSOR_RENDERED="$(render_lane "$RESEARCH_CURSOR_STATUS" "$RESEARCH_CURSOR_REASON")"
RESEARCH_CODEX_RENDERED="$(render_lane "$RESEARCH_CODEX_STATUS" "$RESEARCH_CODEX_REASON")"
VALIDATION_CURSOR_RENDERED="$(render_lane "$VALIDATION_CURSOR_STATUS" "$VALIDATION_CURSOR_REASON")"
VALIDATION_CODEX_RENDERED="$(render_lane "$VALIDATION_CODEX_STATUS" "$VALIDATION_CODEX_REASON")"

# Standard-mode 3-lane shape pinned in research-phase.md and validation-phase.md
# `### Standard` subsections (this script is used only by SKILL.md Step 3's
# Standard branch; quick / deep emit literal headers without it — see #418).
printf 'RESEARCH_HEADER=3 agents (Cursor: %s, Codex: %s)\n' \
    "$RESEARCH_CURSOR_RENDERED" "$RESEARCH_CODEX_RENDERED"
printf 'VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: %s, Codex: %s)\n' \
    "$VALIDATION_CURSOR_RENDERED" "$VALIDATION_CODEX_RENDERED"

exit 0
