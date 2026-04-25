#!/bin/bash
# Structural regression test for /research skill progressive-disclosure refactor.
# Asserts that the skill's 3-reference topology survives edits:
#  - skills/research/references/research-phase.md, validation-phase.md, and
#    adjudication-phase.md all exist
#  - Each appears on a 'MANDATORY — READ ENTIRE FILE' line in skills/research/SKILL.md,
#    and the SAME line also carries reciprocal 'Do NOT load <each-other-reference>'
#    guards naming BOTH other references (line-scoped so a future edit cannot split
#    the MANDATORY and the Do-NOT-load directives into different paragraphs without
#    the harness catching the drift)
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
#  - --substantive-validation flag wiring + STATUS=NOT_SUBSTANTIVE token mapping
#    (#416 Phase 3 of umbrella #413, substantive content validator)
#  - adjudication-phase.md mentions both build-research-adjudication-ballot.sh and
#    run-research-adjudication.sh (byte pin for the ballot-builder + coordinator wiring) (#424)
#
# Exit 0 on pass, exit 1 on any assertion failure.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/research/SKILL.md"
REFS_DIR="$REPO_ROOT/skills/research/references"
RESEARCH_MD="$REFS_DIR/research-phase.md"
VALIDATION_MD="$REFS_DIR/validation-phase.md"
ADJUDICATION_MD="$REFS_DIR/adjudication-phase.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Check 1: SKILL.md exists.
[[ -f "$SKILL_MD" ]] || fail "SKILL.md missing: $SKILL_MD"

# Check 2: All three reference files exist.
[[ -f "$RESEARCH_MD" ]]      || fail "references/research-phase.md missing: $RESEARCH_MD"
[[ -f "$VALIDATION_MD" ]]    || fail "references/validation-phase.md missing: $VALIDATION_MD"
[[ -f "$ADJUDICATION_MD" ]]  || fail "references/adjudication-phase.md missing: $ADJUDICATION_MD"

# Check 3: Each reference file is named on a MANDATORY — READ ENTIRE FILE line in SKILL.md
#          AND that same line carries reciprocal 'Do NOT load <each-other>' guards naming
#          BOTH other references. Line-scoped by construction (grep operates line-by-line)
#          so a future edit that splits the directive across lines — parking 'Do NOT load X'
#          in a different paragraph — fails.
#
# Each MANDATORY line for reference X must also mention BOTH other references in Do-NOT-load
# clauses. The Do-NOT-load clauses may be in either order on the line (the harness checks
# for both possible orderings), but both other reference filenames must be present.

# research-phase.md: MANDATORY line must mention BOTH validation-phase.md AND adjudication-phase.md
grep -qE 'MANDATORY — READ ENTIRE FILE.*research-phase\.md.*Do NOT load.*validation-phase\.md.*Do NOT load.*adjudication-phase\.md' "$SKILL_MD" \
  || grep -qE 'MANDATORY — READ ENTIRE FILE.*research-phase\.md.*Do NOT load.*adjudication-phase\.md.*Do NOT load.*validation-phase\.md' "$SKILL_MD" \
  || fail "SKILL.md Step 1 MANDATORY for research-phase.md must share a line with reciprocal 'Do NOT load' guards naming BOTH validation-phase.md AND adjudication-phase.md"

# validation-phase.md: MANDATORY line must mention BOTH research-phase.md AND adjudication-phase.md
grep -qE 'MANDATORY — READ ENTIRE FILE.*validation-phase\.md.*Do NOT load.*research-phase\.md.*Do NOT load.*adjudication-phase\.md' "$SKILL_MD" \
  || grep -qE 'MANDATORY — READ ENTIRE FILE.*validation-phase\.md.*Do NOT load.*adjudication-phase\.md.*Do NOT load.*research-phase\.md' "$SKILL_MD" \
  || fail "SKILL.md Step 2 MANDATORY for validation-phase.md must share a line with reciprocal 'Do NOT load' guards naming BOTH research-phase.md AND adjudication-phase.md"

# adjudication-phase.md: MANDATORY line must mention BOTH research-phase.md AND validation-phase.md
grep -qE 'MANDATORY — READ ENTIRE FILE.*adjudication-phase\.md.*Do NOT load.*research-phase\.md.*Do NOT load.*validation-phase\.md' "$SKILL_MD" \
  || grep -qE 'MANDATORY — READ ENTIRE FILE.*adjudication-phase\.md.*Do NOT load.*validation-phase\.md.*Do NOT load.*research-phase\.md' "$SKILL_MD" \
  || fail "SKILL.md Step 2.5 MANDATORY for adjudication-phase.md must share a line with reciprocal 'Do NOT load' guards naming BOTH research-phase.md AND validation-phase.md"

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
for ref_path in "$RESEARCH_MD" "$VALIDATION_MD" "$ADJUDICATION_MD"; do
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

# Check 12 (#418, #460): SKILL.md documents abort-on-invalid-value for --scale.
# Pin the full composite error sentence as a single literal so the check
# cannot pass spuriously if only one of two unrelated substrings appears
# (#460: an unrelated `Aborting` elsewhere would otherwise satisfy the prior
# two-grep AND).
grep -Fq -e "must be one of quick|standard|deep (got: foo). Aborting." "$SKILL_MD" \
  || fail "SKILL.md must document abort-on-invalid for --scale (composite literal 'must be one of quick|standard|deep (got: foo). Aborting.' required) (#418, #460)"

# Check 13 (#418 + #424): SKILL.md documents that --debug, --scale, and --adjudicate
# are independent flags (order-independence). Pin the explicit independence statement
# — three flags now after #424 added --adjudicate.
# shellcheck disable=SC2016 # backticks are literal markdown — single quotes are correct here
grep -Eq -e '`--debug`, `--scale`, and `--adjudicate` are independent' "$SKILL_MD" \
  || fail "SKILL.md must explicitly state that '--debug', '--scale', and '--adjudicate' are independent (order-independence) (#418 + #424)"

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

# Check 16 (#416 + #446): Both phase references must invoke collect-reviewer-results.sh
# with --substantive-validation (Phase 3 of umbrella #413). Without these pins,
# a future edit could silently drop the flag and revert /research to the
# pre-Phase-3 "non-empty is enough" check, allowing thin/uncited lane outputs
# to slip through to synthesis.
#
# research-phase.md has TWO scale-specific COLLECTION blocks (### Standard and
# ### Deep) inside the `## 1.4 — Wait and Validate Research Outputs` section.
# The flag must be present in BOTH — #446 documented a regression where the
# Deep block dropped the flag while the Standard block retained it, and a
# single whole-file grep silently passed because Standard satisfied it.
#
# To prevent that class of cross-section leakage, pin the flag per-section
# in two stages: (a) narrow extraction to the Step 1.4 window so the
# per-scale `### Standard` / `### Deep` subsection headers under Step 1.3
# (Launch Research Perspectives) cannot smuggle a satisfying invocation
# into the wrong block; (b) within Step 1.4, scope to the per-scale
# subsection by stopping at the next `###` heading so the Standard and
# Deep blocks cannot substitute for each other either.
#
# The grep pattern anchors on the literal bash-invocation prefix
# `${CLAUDE_PLUGIN_ROOT}/scripts/` so prose paragraphs that happen to
# mention both `collect-reviewer-results.sh` and `--substantive-validation`
# on the same line do NOT satisfy the pin — only the actual command line
# in the bash code fence can.
INVOCATION_PIN='\$\{CLAUDE_PLUGIN_ROOT\}/scripts/collect-reviewer-results\.sh.*--substantive-validation'
SECTION_1_4=$(awk '/^## 1\.4 /{f=1; next} f && /^## /{f=0} f' "$RESEARCH_MD")
[[ -n "$SECTION_1_4" ]] \
  || fail "references/research-phase.md must contain a '## 1.4 ' section (Wait and Validate Research Outputs) — Check 16 cannot anchor without it"
echo "$SECTION_1_4" \
  | awk '/^### Standard \(RESEARCH_SCALE=standard,? ?(default)?\)/{f=1; next} f && /^###/{f=0} f' \
  | grep -Eq "$INVOCATION_PIN" \
  || fail "references/research-phase.md Step 1.4 ### Standard collection block must invoke collect-reviewer-results.sh with --substantive-validation (#416 Phase 3)"
echo "$SECTION_1_4" \
  | awk '/^### Deep \(RESEARCH_SCALE=deep\)/{f=1; next} f && /^###/{f=0} f' \
  | grep -Eq "$INVOCATION_PIN" \
  || fail "references/research-phase.md Step 1.4 ### Deep collection block must invoke collect-reviewer-results.sh with --substantive-validation (#416 Phase 3 + #446)"
# validation-phase.md has a single (scale-agnostic) collection block, so the
# whole-file pin remains correct here. Reuse the invocation-anchored pattern
# for the same anti-prose hardening.
grep -Eq "$INVOCATION_PIN" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must invoke collect-reviewer-results.sh with --substantive-validation (#416 Phase 3)"

# Check 17 (#416): Both phase references must map STATUS=NOT_SUBSTANTIVE in the
# lane-status update bullet so the new collector status flows into the correct
# render token (fallback_runtime_failed). The pre-existing bullet only listed
# FAILED/EMPTY_OUTPUT; without this pin a future edit could drop NOT_SUBSTANTIVE
# silently and the render helper would emit (unknown) for it.
grep -Fq "NOT_SUBSTANTIVE" "$RESEARCH_MD" \
  || fail "references/research-phase.md must map STATUS=NOT_SUBSTANTIVE in lane-status token bullet (#416 Phase 3)"
grep -Fq "NOT_SUBSTANTIVE" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must map STATUS=NOT_SUBSTANTIVE in lane-status token bullet (#416 Phase 3)"

# Check 18 (#424): adjudication-phase.md must reference both the ballot builder
# and the pre-launch coordinator. Without these pins, a future edit could silently
# drop the wiring and Step 2.5 would have no helper invocation, making the
# adjudication step a no-op even when --adjudicate is on.
grep -Fq "build-research-adjudication-ballot.sh" "$ADJUDICATION_MD" \
  || fail "references/adjudication-phase.md must reference scripts/build-research-adjudication-ballot.sh (#424)"
grep -Fq "run-research-adjudication.sh" "$ADJUDICATION_MD" \
  || fail "references/adjudication-phase.md must reference scripts/run-research-adjudication.sh (#424)"

# Section-scoped extractor for the Step 3 ### Deep subsection (used by both
# Check 19 and Check 20). The extractor toggles a code-fence state on bare
# ``` lines so that headings (`^### ...`, `^## ...`) inside fenced markdown
# template blocks do NOT terminate the section prematurely (#451 review
# FINDING_7). The section ends on the next H2 heading outside a fence — the
# Deep subsection is the last H3 under Step 3, so the next H2 (or EOF)
# bounds it cleanly.
extract_deep_section() {
  awk '
    /^```/ { in_fence = !in_fence; next }
    in_deep && !in_fence && /^## / { in_deep = 0 }
    in_deep && !in_fence { print }
    /^### Deep \(RESEARCH_SCALE=deep\)/ { in_deep = 1 }
  ' "$SKILL_MD"
}

DEEP_SECTION=$(extract_deep_section)
[[ -n "$DEEP_SECTION" ]] \
  || fail "SKILL.md must contain a '### Deep (RESEARCH_SCALE=deep)' subsection — Checks 19/20 cannot anchor without it (#451)"

# Check 19 (#451 + review FINDING_6): SKILL.md Step 3 ### Deep subsection
# (NOT just any prose elsewhere in SKILL.md) must invoke the deep-mode
# renderer so the per-phase attribution slices in `lane-status.txt` are the
# source of truth for deep headers (the bug #451 fixed: previously the deep
# branch derived headers from session-wide cursor_available/codex_available
# flags). Step 0b prose now ALSO mentions the deep helper, so a whole-file
# grep would falsely pass even if the actual Step 3 Deep invocation
# regressed — section-scoping closes that hole.
echo "$DEEP_SECTION" | grep -Fq "render-deep-lane-status.sh" \
  || fail "SKILL.md Step 3 ### Deep subsection must invoke render-deep-lane-status.sh (#451 deep-mode lane attribution; #451 review FINDING_6 closed Step 0b loophole)"

# Check 20 (#451 + review FINDING_7): SKILL.md Step 3 ### Deep subsection
# must NOT derive headers from session-wide cursor_available / codex_available
# flags — that pattern is the pre-fix bug. The check is section-scoped via
# the awk extractor above (which handles fenced code blocks). The negative
# regex covers BOTH cursor_available and codex_available so a Codex-only
# reintroduction of the same bug class also fails.
if echo "$DEEP_SECTION" | grep -qE 'session-wide.*cursor_available|cursor_available.*throughout the run|orchestrator tracks the session-wide.*cursor_available|session-wide.*codex_available|codex_available.*throughout the run|orchestrator tracks the session-wide.*codex_available|tracks the session-wide.*cursor_available.*codex_available|tracks the session-wide.*codex_available.*cursor_available'; then
  fail "SKILL.md Step 3 ### Deep subsection must not derive headers from session-wide cursor_available/codex_available flags (#451 — use render-deep-lane-status.sh + lane-status.txt slices instead)"
fi

echo "PASS: test-research-structure.sh — all 20 structural invariants hold"
exit 0
