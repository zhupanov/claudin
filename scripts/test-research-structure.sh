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
#  - render-lane-status.sh + lane-status.txt pins (#421)
#  - --scale=quick|standard|deep value-flag surface (#418): flag enum + 4 named angle
#    prompt identifiers + literal quick-mode skip breadcrumb + abort-on-invalid + flag
#    independence statement + ### Standard byte-drift pins on existing filename literals
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

# Check 9 (#418): SKILL.md documents the --scale=quick|standard|deep value flag.
# Pin the literal triple so a future edit cannot silently rename or drop a value
# from the enum. Use `-e --` so grep does not interpret the leading '--' as flags.
grep -Fq -e "--scale=quick|standard|deep" "$SKILL_MD" \
  || fail "SKILL.md must document the --scale=quick|standard|deep value flag (#418)"

# Check 10 (#418): research-phase.md defines all four named angle prompts as
# explicit identifiers. These are the data-bearing literals that distinguish
# deep mode from standard mode; their absence means deep mode lost its
# diversified-angle architecture.
for prompt in RESEARCH_PROMPT_ARCH RESEARCH_PROMPT_EDGE RESEARCH_PROMPT_EXT RESEARCH_PROMPT_SEC; do
  grep -Fq "$prompt" "$RESEARCH_MD" \
    || fail "references/research-phase.md must define the named angle prompt '$prompt' (#418 deep mode)"
done

# Check 11 (#418): SKILL.md documents the exact quick-mode skip breadcrumb.
# Pin the literal so the gate cannot silently drop or rephrase the visible
# user signal that validation was intentionally skipped.
grep -Fq -e "⏩ 2: validation — skipped (--scale=quick)" "$SKILL_MD" \
  || fail "SKILL.md must contain the literal quick-mode skip breadcrumb '⏩ 2: validation — skipped (--scale=quick)' (#418)"

# Check 12 (#418): SKILL.md documents abort-on-invalid-value for --scale.
# Pin the abort message literal so a future edit cannot drop the explicit
# rejection of malformed --scale values.
if grep -Fq -e "Aborting" "$SKILL_MD" && grep -Fq -e "must be one of quick|standard|deep" "$SKILL_MD"; then
  : # both literals present
else
  fail "SKILL.md must document abort-on-invalid for --scale (literals 'must be one of quick|standard|deep' and 'Aborting' both required) (#418)"
fi

# Check 13 (#418): SKILL.md documents that --debug and --scale are independent
# flags (order-independence). Pin the explicit independence statement.
# shellcheck disable=SC2016 # backticks are literal markdown — single quotes are correct here
grep -Eq -e '`--debug` and `--scale` are independent' "$SKILL_MD" \
  || fail "SKILL.md must explicitly state that '--debug' and '--scale' are independent (order-independence) (#418)"

# Check 14 (#418): research-phase.md ### Standard subsection contains a stable
# byte-drift pin (the existing standard-mode cursor research output filename
# literal). Without this guard, an editor could change the standard branch's
# bash block content and the harness would not catch the drift.
grep -Fq "cursor-research-output.txt" "$RESEARCH_MD" \
  || fail "references/research-phase.md must contain the standard-mode 'cursor-research-output.txt' filename literal (#418 byte-drift guard)"
grep -Fq "codex-research-output.txt" "$RESEARCH_MD" \
  || fail "references/research-phase.md must contain the standard-mode 'codex-research-output.txt' filename literal (#418 byte-drift guard)"

# Check 15 (#418): validation-phase.md ### Standard byte-drift pin (existing
# Cursor/Codex validation output filenames must remain in the file for the
# standard validation branch).
grep -Fq "cursor-validation-output.txt" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must contain the standard-mode 'cursor-validation-output.txt' filename literal (#418 byte-drift guard)"
grep -Fq "codex-validation-output.txt" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must contain the standard-mode 'codex-validation-output.txt' filename literal (#418 byte-drift guard)"

echo "PASS: test-research-structure.sh — all 15 structural invariants hold"
exit 0
