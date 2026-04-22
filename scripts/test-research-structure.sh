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
#          catching the drift.
contract_headers=(
  '**Consumer**:'
  '**Contract**:'
  '**When to load**:'
)
for ref_path in "$RESEARCH_MD" "$VALIDATION_MD"; do
  for hdr in "${contract_headers[@]}"; do
    head -n 20 "$ref_path" | grep -Fq "$hdr" \
      || fail "references/$(basename "$ref_path") must open with '$hdr' header in the first 20 lines"
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

echo "PASS: test-research-structure.sh — all 6 structural invariants hold"
exit 0
