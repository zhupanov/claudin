#!/usr/bin/env bash
# render-deep-lane-status.sh — format the per-lane attribution record for
# /research's Step 3 final report in DEEP mode (5 research agents +
# 5 validation reviewers).
#
# Reads the same 8-key KV file as the standard renderer
# (`scripts/render-lane-status.sh`) and emits two `<NAME>_HEADER=<value>`
# lines on stdout that SKILL.md Step 3 substitutes into the report.
#
# In deep mode, the schema's per-tool aggregate semantics apply: a single
# `RESEARCH_CURSOR_*` status covers BOTH Cursor research slots (Cursor-Arch
# and Cursor-Edge), and `RESEARCH_CODEX_*` covers BOTH Codex research slots
# (Codex-Ext and Codex-Sec). See `skills/research/SKILL.md` Step 0b. The three
# Claude validation lanes (Code, Code-Sec, Code-Arch) are always Claude with
# no fallback path, so they are hard-coded as ✅. Closes #451.
#
# Usage:
#   render-deep-lane-status.sh --input <path>
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
# Status tokens — see `scripts/render-lane-status-lib.md`. The full canonical
# vocabulary, rendering, and sanitization rules live in the shared library.
#
# Output (KEY=value on stdout):
#   RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: <r>, Cursor-Edge: <r>, Codex-Ext: <r>, Codex-Sec: <r>)
#   VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: <r>, Codex: <r>)
#
# Exit codes (symmetric with `render-lane-status.sh`):
#   0 — success
#   1 — usage error (missing flag, unknown flag)
#   2 — I/O failure (input file missing or unreadable)
#
# Stderr (symmetric with `render-lane-status.sh`):
#   Usage errors (exit 1):
#     `**⚠ render-deep-lane-status: --input is required**`
#     `**⚠ render-deep-lane-status: --input requires a value**`
#     `**⚠ render-deep-lane-status: unknown flag: <flag>**`
#   Input-file errors (exit 2):
#     `**⚠ render-deep-lane-status: input file missing**`
#     `**⚠ render-deep-lane-status: input file unreadable**`
#   Per-occurrence warnings (exit 0, per occurrence):
#     `**⚠ render-deep-lane-status: unknown status token <token>**`
#     (attributed to this script via RENDER_LANE_CALLER, set below)

set -euo pipefail

fail_usage() {
    echo "**⚠ render-deep-lane-status: $1**" >&2
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
    echo "**⚠ render-deep-lane-status: input file missing**" >&2
    exit 2
fi
if [ ! -r "$INPUT" ]; then
    echo "**⚠ render-deep-lane-status: input file unreadable**" >&2
    exit 2
fi

# Source the shared rendering library (sanitize_reason + render_lane). Set
# RENDER_LANE_CALLER first so unknown-token warnings attribute to this
# script (#451 FINDING_2).
RENDER_LANE_CALLER="render-deep-lane-status"
# shellcheck source=scripts/render-lane-status-lib.sh
source "$(dirname "$0")/render-lane-status-lib.sh"

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

# Per-tool aggregate semantics: both Cursor research slots (Arch + Edge)
# share the same RESEARCH_CURSOR_* status; same for Codex research slots
# (Ext + Sec) and RESEARCH_CODEX_*. Render once per slot using the shared
# per-tool status so failures show up consistently across both slot names.
RESEARCH_CURSOR_RENDERED="$(render_lane "$RESEARCH_CURSOR_STATUS" "$RESEARCH_CURSOR_REASON")"
RESEARCH_CODEX_RENDERED="$(render_lane "$RESEARCH_CODEX_STATUS" "$RESEARCH_CODEX_REASON")"
VALIDATION_CURSOR_RENDERED="$(render_lane "$VALIDATION_CURSOR_STATUS" "$VALIDATION_CURSOR_REASON")"
VALIDATION_CODEX_RENDERED="$(render_lane "$VALIDATION_CODEX_STATUS" "$VALIDATION_CODEX_REASON")"

# Deep-mode 5+5 shape pinned in skills/research/SKILL.md Step 3 ### Deep
# subsection. Code, Code-Sec, Code-Arch are Claude lanes with no fallback —
# hard-coded ✅. Cursor-Arch + Cursor-Edge share RESEARCH_CURSOR_RENDERED;
# Codex-Ext + Codex-Sec share RESEARCH_CODEX_RENDERED.
printf 'RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: %s, Cursor-Edge: %s, Codex-Ext: %s, Codex-Sec: %s)\n' \
    "$RESEARCH_CURSOR_RENDERED" "$RESEARCH_CURSOR_RENDERED" \
    "$RESEARCH_CODEX_RENDERED" "$RESEARCH_CODEX_RENDERED"
printf 'VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: %s, Codex: %s)\n' \
    "$VALIDATION_CURSOR_RENDERED" "$VALIDATION_CODEX_RENDERED"

exit 0
