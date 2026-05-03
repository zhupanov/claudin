#!/usr/bin/env bash
# render-lane-status.sh — format the per-lane attribution record into the
# header lines used by /research's Step 3 final report.
#
# Reads a small KV file holding the codified status of each research angle
# (4 angles: architecture/edge cases/external comparisons/security) and each
# validation reviewer (3 reviewers: Code/Cursor/Codex). Emits seven
# `<NAME>_HEADER=<value>` lines on stdout that SKILL.md Step 3 substitutes
# into the report.
#
# Usage:
#   render-lane-status.sh --input <path>
#
# Input KV schema (14 keys, all optional — missing keys render as `(unknown)`):
#   RESEARCH_ARCH_STATUS=<token>
#   RESEARCH_ARCH_REASON=<short reason text>
#   RESEARCH_EDGE_STATUS=<token>
#   RESEARCH_EDGE_REASON=<short reason text>
#   RESEARCH_EXT_STATUS=<token>
#   RESEARCH_EXT_REASON=<short reason text>
#   RESEARCH_SEC_STATUS=<token>
#   RESEARCH_SEC_REASON=<short reason text>
#   VALIDATION_CODE_STATUS=<token>
#   VALIDATION_CODE_REASON=<short reason text>
#   VALIDATION_CURSOR_STATUS=<token>
#   VALIDATION_CURSOR_REASON=<short reason text>
#   VALIDATION_CODEX_STATUS=<token>
#   VALIDATION_CODEX_REASON=<short reason text>
#
# Status tokens (canonical):
#   ok                            → ✅
#   fallback_binary_missing       → Claude-fallback (binary missing)
#   fallback_probe_failed         → Claude-fallback (probe failed: <reason>)
#   fallback_runtime_timeout      → Claude-fallback (runtime timeout)
#   fallback_runtime_failed       → Claude-fallback (runtime failed: <reason>)
#   '' (missing or empty)         → (unknown)
#   <anything else, non-empty>    → (unknown)   + stderr warning
#
# Output (KEY=value on stdout, 7 lines):
#   RESEARCH_ARCH_HEADER=Architecture: <rendered>
#   RESEARCH_EDGE_HEADER=Edge cases: <rendered>
#   RESEARCH_EXT_HEADER=External comparisons: <rendered>
#   RESEARCH_SEC_HEADER=Security: <rendered>
#   VALIDATION_CODE_HEADER=Code: <rendered>
#   VALIDATION_CURSOR_HEADER=Cursor: <rendered>
#   VALIDATION_CODEX_HEADER=Codex: <rendered>
#
# Exit codes:
#   0 — success
#   1 — usage error (missing flag, unknown flag)
#   2 — I/O failure (input file missing or unreadable)

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

# Initialize all keys to empty.
RESEARCH_ARCH_STATUS=""; RESEARCH_ARCH_REASON=""
RESEARCH_EDGE_STATUS=""; RESEARCH_EDGE_REASON=""
RESEARCH_EXT_STATUS="";  RESEARCH_EXT_REASON=""
RESEARCH_SEC_STATUS="";  RESEARCH_SEC_REASON=""
VALIDATION_CODE_STATUS="";   VALIDATION_CODE_REASON=""
VALIDATION_CURSOR_STATUS=""; VALIDATION_CURSOR_REASON=""
VALIDATION_CODEX_STATUS="";  VALIDATION_CODEX_REASON=""

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
        RESEARCH_ARCH_STATUS)      RESEARCH_ARCH_STATUS="$value" ;;
        RESEARCH_ARCH_REASON)      RESEARCH_ARCH_REASON="$value" ;;
        RESEARCH_EDGE_STATUS)      RESEARCH_EDGE_STATUS="$value" ;;
        RESEARCH_EDGE_REASON)      RESEARCH_EDGE_REASON="$value" ;;
        RESEARCH_EXT_STATUS)       RESEARCH_EXT_STATUS="$value" ;;
        RESEARCH_EXT_REASON)       RESEARCH_EXT_REASON="$value" ;;
        RESEARCH_SEC_STATUS)       RESEARCH_SEC_STATUS="$value" ;;
        RESEARCH_SEC_REASON)       RESEARCH_SEC_REASON="$value" ;;
        VALIDATION_CODE_STATUS)    VALIDATION_CODE_STATUS="$value" ;;
        VALIDATION_CODE_REASON)    VALIDATION_CODE_REASON="$value" ;;
        VALIDATION_CURSOR_STATUS)  VALIDATION_CURSOR_STATUS="$value" ;;
        VALIDATION_CURSOR_REASON)  VALIDATION_CURSOR_REASON="$value" ;;
        VALIDATION_CODEX_STATUS)   VALIDATION_CODEX_STATUS="$value" ;;
        VALIDATION_CODEX_REASON)   VALIDATION_CODEX_REASON="$value" ;;
    esac
done < "$INPUT"

# shellcheck source=scripts/render-lane-status-lib.sh
source "$(dirname "$0")/render-lane-status-lib.sh"

R_ARCH="$(render_lane "$RESEARCH_ARCH_STATUS" "$RESEARCH_ARCH_REASON")"
R_EDGE="$(render_lane "$RESEARCH_EDGE_STATUS" "$RESEARCH_EDGE_REASON")"
R_EXT="$(render_lane "$RESEARCH_EXT_STATUS" "$RESEARCH_EXT_REASON")"
R_SEC="$(render_lane "$RESEARCH_SEC_STATUS" "$RESEARCH_SEC_REASON")"
V_CODE="$(render_lane "$VALIDATION_CODE_STATUS" "$VALIDATION_CODE_REASON")"
V_CURSOR="$(render_lane "$VALIDATION_CURSOR_STATUS" "$VALIDATION_CURSOR_REASON")"
V_CODEX="$(render_lane "$VALIDATION_CODEX_STATUS" "$VALIDATION_CODEX_REASON")"

# Fixed shape: 4 research lines + 3 validation lines.
printf 'RESEARCH_ARCH_HEADER=Architecture: %s\n' "$R_ARCH"
printf 'RESEARCH_EDGE_HEADER=Edge cases: %s\n' "$R_EDGE"
printf 'RESEARCH_EXT_HEADER=External comparisons: %s\n' "$R_EXT"
printf 'RESEARCH_SEC_HEADER=Security: %s\n' "$R_SEC"
printf 'VALIDATION_CODE_HEADER=Code: %s\n' "$V_CODE"
printf 'VALIDATION_CURSOR_HEADER=Cursor: %s\n' "$V_CURSOR"
printf 'VALIDATION_CODEX_HEADER=Codex: %s\n' "$V_CODEX"

exit 0
