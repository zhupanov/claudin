#!/bin/bash
# Structural regression test for /research skill progressive-disclosure refactor.
# Asserts that the skill's 2-reference topology survives edits:
#  - skills/research/references/research-phase.md and validation-phase.md both exist
#  - Each appears on a 'MANDATORY — READ ENTIRE FILE' line in skills/research/SKILL.md,
#    and the SAME line also carries the reciprocal 'Do NOT load <other-reference>' guard
#    (line-scoped so a future edit cannot split the MANDATORY and the Do-NOT-load into
#    different paragraphs without the harness catching the drift)
#  - Each references/*.md OPENS WITH the Consumer / Contract / When-to-load header triplet
#    in the first 20 lines (a /research-local tightening layered on top of the cross-skill
#    presence check enforced by scripts/test-references-headers.sh — matches the sibling
#    contract's literal 'opens with' promise)
#  - RESEARCH_PROMPT literal appears in research-phase.md (substring pin for byte-drift detection)
#  - reviewer XML wrapper tags (<reviewer_research_question>, <reviewer_research_findings>)
#    appear in validation-phase.md (byte pin for prompt-injection hardening)
#
# Exit 0 on pass, exit 1 on any assertion failure.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/research/SKILL.md"
REFS_DIR="$REPO_ROOT/skills/research/references"
RESEARCH_MD="$REFS_DIR/research-phase.md"
VALIDATION_MD="$REFS_DIR/validation-phase.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Check 1: SKILL.md exists.
[[ -f "$SKILL_MD" ]] || fail "SKILL.md missing: $SKILL_MD"

# Check 2: Both reference files exist.
[[ -f "$RESEARCH_MD" ]] || fail "references/research-phase.md missing: $RESEARCH_MD"
[[ -f "$VALIDATION_MD" ]] || fail "references/validation-phase.md missing: $VALIDATION_MD"

# Check 3: Each reference file is named on a MANDATORY — READ ENTIRE FILE line in SKILL.md
#          AND that same line carries the reciprocal 'Do NOT load <other>' guard. Line-scoped
#          by construction (grep operates line-by-line) so a future edit that splits the
#          directive across lines — parking 'Do NOT load X' in a different paragraph — fails.
grep -q 'MANDATORY — READ ENTIRE FILE.*research-phase\.md.*Do NOT load.*validation-phase\.md' "$SKILL_MD" \
  || grep -q 'Do NOT load.*validation-phase\.md.*MANDATORY — READ ENTIRE FILE.*research-phase\.md' "$SKILL_MD" \
  || fail "SKILL.md Step 1 MANDATORY for research-phase.md must share a line with 'Do NOT load ... validation-phase.md' guard"
grep -q 'MANDATORY — READ ENTIRE FILE.*validation-phase\.md.*Do NOT load.*research-phase\.md' "$SKILL_MD" \
  || grep -q 'Do NOT load.*research-phase\.md.*MANDATORY — READ ENTIRE FILE.*validation-phase\.md' "$SKILL_MD" \
  || fail "SKILL.md Step 2 MANDATORY for validation-phase.md must share a line with 'Do NOT load ... research-phase.md' guard"

# Check 4: Each references/*.md opens with the Consumer / Contract / When-to-load header
#          triplet in the first 20 lines. The sibling contract says "opens with" — enforce that
#          literally, so future edits cannot bury the triplet mid-file without the harness
#          catching the drift. Patterns are anchored at line-start (same shape as the global
#          scripts/test-references-headers.sh harness) so the /research-local tightening
#          actually layers on top of the cross-skill anchored presence check — a prose line
#          like `see **Consumer**: below` in the head region must NOT satisfy the check.
contract_header_patterns=(
  '^\*\*Consumer\*\*:'
  '^\*\*Contract\*\*:'
  '^\*\*When to load\*\*:'
)
for ref_path in "$RESEARCH_MD" "$VALIDATION_MD"; do
  for pattern in "${contract_header_patterns[@]}"; do
    head -n 20 "$ref_path" | grep -Eq "$pattern" \
      || fail "references/$(basename "$ref_path") must open with anchored header matching '$pattern' in the first 20 lines"
  done
done

# Check 5: RESEARCH_PROMPT literal (substring pin for byte-drift detection).
grep -Fq "RESEARCH_PROMPT" "$RESEARCH_MD" \
  || fail "references/research-phase.md lacks RESEARCH_PROMPT literal identifier"
# Pin the opening 'You are researching a codebase' substring of the prompt body itself.
grep -Fq "You are researching a codebase to answer this question" "$RESEARCH_MD" \
  || fail "references/research-phase.md lacks RESEARCH_PROMPT body opening substring 'You are researching a codebase to answer this question'"

# Check 6: Validation reviewer XML wrapper tags (byte pin for prompt-injection hardening).
grep -Fq "<reviewer_research_question>" "$VALIDATION_MD" \
  || fail "references/validation-phase.md lacks '<reviewer_research_question>' XML wrapper tag"
grep -Fq "<reviewer_research_findings>" "$VALIDATION_MD" \
  || fail "references/validation-phase.md lacks '<reviewer_research_findings>' XML wrapper tag"

# Check 7: SKILL.md Step 3 must invoke render-lane-status.sh (the lane-attribution
# formatter added by #421). Without this pin, a future edit could quietly remove
# the helper invocation and the report header would silently regress to the
# pre-#421 collapsed ✅/❌ shape (or to a hard-coded literal).
grep -Fq "render-lane-status.sh" "$SKILL_MD" \
  || fail "SKILL.md must reference render-lane-status.sh in Step 3 (#421 lane attribution)"

# Check 8: Both phase references must mention lane-status.txt — the on-disk
# KV record they update via surgical phase-local rewrites. Without these pins,
# the orchestrator-side update logic could be silently dropped, leaving the
# render helper to emit stale Step 0b values for runtime-fallback lanes.
grep -Fq "lane-status.txt" "$RESEARCH_MD" \
  || fail "references/research-phase.md must mention lane-status.txt (#421 RESEARCH_* slice update)"
grep -Fq "lane-status.txt" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must mention lane-status.txt (#421 VALIDATION_* slice update + Step 2 entry propagation)"

echo "PASS: test-research-structure.sh — all 8 structural invariants hold"
exit 0
