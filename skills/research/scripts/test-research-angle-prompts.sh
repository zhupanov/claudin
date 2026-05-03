#!/usr/bin/env bash
# test-research-angle-prompts.sh — Structural regression guard for /research
# fixed-shape angle-prompt mapping.
#
# Pins:
#  - All four named angle prompt identifiers exist in research-phase.md
#    (RESEARCH_PROMPT_ARCH / _EDGE / _EXT / _SEC).
#  - Each angle is bound to one Codex-first lane in the fixed 4-lane topology
#    declared at the top of research-phase.md (Architecture / Edge cases /
#    External comparisons / Security), with per-lane Claude `Agent` fallback.
#
# Wired into `make lint` via the `test-research-angle-prompts` target.
#
# Exit 0 on all assertions passing; exit 1 on any failure (with diagnostic on stderr).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
RESEARCH_MD="$REPO_ROOT/skills/research/references/research-phase.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$RESEARCH_MD" ]] \
  || fail "skills/research/references/research-phase.md not found at $RESEARCH_MD"

# Check 1: All four named angle prompt identifiers present.
for angle in ARCH EDGE EXT SEC; do
  grep -Fq "RESEARCH_PROMPT_${angle}" "$RESEARCH_MD" \
    || fail "research-phase.md lacks RESEARCH_PROMPT_${angle} identifier"
done

# Check 2: Each lane is Codex-first with Claude Agent fallback.
declare -a lanes=(
  "Architecture lane:RESEARCH_PROMPT_ARCH"
  "Edge cases lane:RESEARCH_PROMPT_EDGE"
  "External comparisons lane:RESEARCH_PROMPT_EXT"
  "Security lane:RESEARCH_PROMPT_SEC"
)
for entry in "${lanes[@]}"; do
  label="${entry%%:*}"
  angle="${entry##*:}"
  grep -Fq "$label" "$RESEARCH_MD" \
    || fail "research-phase.md must declare a '$label' in the fixed-shape topology"
  grep -F "$label" "$RESEARCH_MD" | grep -Fq "$angle" \
    || fail "$label must reference $angle as its angle prompt"
  grep -F "$label" "$RESEARCH_MD" | grep -Eq 'Codex-first|Codex' \
    || fail "$label must be declared Codex-first"
done

# Check 3: Per-lane Claude Agent fallback wording is present somewhere in
# the lane-declaration block.
grep -Eq 'Per-lane Claude .?Agent.? fallback' "$RESEARCH_MD" \
  || fail "research-phase.md must document per-lane Claude Agent fallback for Codex-first lanes"

echo "PASS: research-phase.md angle-prompt structural pins hold"
