#!/usr/bin/env bash
# compute-degraded-banner.sh — Canonical executable home for the /research
# Step 1.5 reduced-diversity banner formula (issue #506; refactored under #507).
#
# Reads RESEARCH_CURSOR_STATUS / RESEARCH_CODEX_STATUS from a lane-status.txt
# fixture, computes N_FALLBACK / LANE_TOTAL per the per-scale formula, and
# prints the substituted banner literal on stdout when N_FALLBACK >= 1
# (otherwise prints nothing).
#
# Usage:
#   bash compute-degraded-banner.sh <lane-status.txt-path> <scale>
#
#   <scale> ∈ {standard, deep}
#
# Output contract:
#   - On N_FALLBACK >= 1: prints the substituted BANNER_TEMPLATE on stdout,
#     followed by a single newline.
#   - On N_FALLBACK == 0: prints nothing (empty stdout).
#   - On missing/unreadable fixture file: prints nothing (defensive default
#     per research-phase.md prose).
#   - On unknown <scale>: prints nothing; logs a diagnostic on stderr.
#   - On insufficient args (< 2): prints nothing on stdout; logs a diagnostic
#     on stderr.
#   - Always exits 0 (failure-to-emit is signaled by empty stdout, never by
#     a non-zero exit code, so callers using $(...) command substitution
#     under `set -e` don't abort — including the insufficient-args case).
#
# This is the **canonical executable truth** for the formula. Both the
# /research orchestrator (research-phase.md §1.5 banner preamble prose) and
# the test harness (test-degraded-path-banner.sh) fork this script via
# bash subshell and compare stdout. The formula text in research-phase.md
# remains as documentation; this file is what executes.
#
# Edit-in-sync surfaces (5 places — see test-degraded-path-banner.md):
#   1. BANNER_TEMPLATE constant in this file (canonical executable)
#   2. The banner literal in research-phase.md §1.5 banner preamble (prose)
#   3. Check 21a in scripts/test-research-structure.sh (greps THIS file)
#   4. test-degraded-path-banner.sh fixture expectations (forks THIS file)
#   5. SKILL.md Step 3 fully-substituted example banner

set -euo pipefail

# Banner literal — MUST match the literal in research-phase.md §1.5 preamble.
BANNER_TEMPLATE='**⚠ Reduced lane diversity: <N_FALLBACK> of <LANE_TOTAL> external research lanes ran as Claude-fallback. The model-family heterogeneity claim does not hold for this run.**'

emit_banner() {
  local fixture="$1"
  local scale="$2"
  local cursor_status codex_status
  local cursor_fallback codex_fallback
  local n_fallback lane_total

  # Defensive default per research-phase.md prose: missing/unreadable fixture
  # → no banner. The -r check covers chmod 000.
  if [[ ! -f "$fixture" ]] || [[ ! -r "$fixture" ]]; then
    return 0
  fi

  cursor_status="$(grep -E '^RESEARCH_CURSOR_STATUS=' "$fixture" | head -n 1 | sed 's/^RESEARCH_CURSOR_STATUS=//')" || cursor_status=""
  codex_status="$(grep -E '^RESEARCH_CODEX_STATUS=' "$fixture" | head -n 1 | sed 's/^RESEARCH_CODEX_STATUS=//')" || codex_status=""

  if [[ "$cursor_status" == "ok" ]]; then cursor_fallback=0; else cursor_fallback=1; fi
  if [[ "$codex_status" == "ok" ]]; then codex_fallback=0; else codex_fallback=1; fi

  case "$scale" in
    standard)
      # N_FALLBACK = (RESEARCH_CURSOR_STATUS != ok) + (RESEARCH_CODEX_STATUS != ok)
      n_fallback=$(( cursor_fallback + codex_fallback ))
      lane_total=2
      ;;
    deep)
      # N_FALLBACK = 2*(RESEARCH_CURSOR_STATUS != ok) + 2*(RESEARCH_CODEX_STATUS != ok)
      n_fallback=$(( 2 * cursor_fallback + 2 * codex_fallback ))
      lane_total=4
      ;;
    *)
      echo "INTERNAL: compute-degraded-banner.sh unknown scale '$scale' (expected: standard|deep)" >&2
      return 0
      ;;
  esac

  if (( n_fallback >= 1 )); then
    local banner="${BANNER_TEMPLATE/<N_FALLBACK>/$n_fallback}"
    banner="${banner/<LANE_TOTAL>/$lane_total}"
    printf '%s\n' "$banner"
  fi
}

if (( $# < 2 )); then
  # Honor the "Always exits 0" contract documented in compute-degraded-banner.md.
  # An orchestrator that mistakenly omits an argument under `set -e` would
  # otherwise abort the run; emitting the diagnostic on stderr and exiting 0
  # with empty stdout produces the documented "no banner" degraded path.
  echo "WARNING: compute-degraded-banner.sh requires <lane-status.txt-path> <scale> (got $# arg(s)); emitting empty banner" >&2
  echo "  <scale> ∈ {standard, deep}" >&2
  exit 0
fi

emit_banner "$1" "$2"
