#!/usr/bin/env bash
# compute-research-banner.sh — Canonical executable home for the /research
# Step 1.5 reduced-diversity banner formula.
#
# Reads line-anchored RESEARCH_*_STATUS keys from a lane-status.txt fixture,
# counts how many fell back to Claude (value matches `^fallback_*`), and
# prints the substituted banner literal on stdout when N_FALLBACK >= 1
# (otherwise prints nothing).
#
# Usage:
#   bash compute-research-banner.sh <lane-status.txt-path>
#
# Output contract:
#   - On N_FALLBACK >= 1: prints the substituted BANNER_TEMPLATE on stdout,
#     followed by a single newline.
#   - On N_FALLBACK == 0: prints nothing (empty stdout).
#   - On missing/unreadable fixture file: prints nothing (defensive default).
#   - On insufficient args (< 1): prints nothing on stdout; logs a diagnostic
#     on stderr.
#   - Always exits 0 (failure-to-emit is signaled by empty stdout, never by
#     a non-zero exit code, so callers using $(...) command substitution
#     under `set -e` don't abort).
#
# This is the **canonical executable truth** for the formula. Both the
# /research orchestrator and the test harness (test-research-banner.sh)
# fork this script and compare stdout.

set -euo pipefail

# Banner literal — MUST match the literal in research-phase.md §1.5 preamble
# and the substituted example in skills/research/SKILL.md Step 3.
BANNER_TEMPLATE='**⚠ Reduced lane diversity: <N_FALLBACK> of 4 external research lanes ran as Claude-fallback. The model-family heterogeneity claim does not hold for this run.**'

emit_banner() {
  local fixture="$1"
  local n_fallback=0

  # Defensive default: missing/unreadable fixture → no banner.
  if [[ ! -f "$fixture" ]] || [[ ! -r "$fixture" ]]; then
    return 0
  fi

  # Count line-anchored RESEARCH_*_STATUS lines whose value begins with
  # "fallback_". The strict line anchor on RESEARCH_ (NOT VALIDATION_) plus
  # the value-anchored fallback_ prefix prevent two false positives:
  #   - REASON fields that contain the literal text "fallback_" anywhere.
  #   - VALIDATION_*_STATUS=fallback_* (validation lanes are Code/Cursor/Codex
  #     attribution; they do not affect research diversity).
  while IFS= read -r line; do
    # Match exactly: ^RESEARCH_<KEY>_STATUS=fallback_<token>
    if [[ "$line" =~ ^RESEARCH_[A-Z_]+_STATUS=fallback_ ]]; then
      n_fallback=$(( n_fallback + 1 ))
    fi
  done < "$fixture"

  if (( n_fallback >= 1 )); then
    local banner="${BANNER_TEMPLATE/<N_FALLBACK>/$n_fallback}"
    printf '%s\n' "$banner"
  fi
}

if (( $# < 1 )); then
  echo "WARNING: compute-research-banner.sh requires <lane-status.txt-path> (got $# arg(s)); emitting empty banner" >&2
  exit 0
fi

emit_banner "$1"
