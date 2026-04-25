#!/usr/bin/env bash
# test-standard-angle-prompts.sh — Structural regression guard for /research
# standard-mode per-lane angle-prompt mapping (closes #508).
#
# Pins:
#  - RESEARCH_PROMPT_BASELINE literal exists in research-phase.md (the renamed
#    literal — formerly RESEARCH_PROMPT — used only by quick mode and
#    deep-mode's Claude inline lane after #508)
#  - All four named angle prompt identifiers exist in research-phase.md
#    (RESEARCH_PROMPT_ARCH / _EDGE / _EXT / _SEC). Already pinned by Check 10
#    of test-research-structure.sh; pinned here too for failure-locality so
#    a regression in standard-mode wiring fails THIS harness with a directly
#    relevant message.
#  - Per-lane angle assignment in the Step 1.3 ### Standard subsection:
#      Cursor → <RESEARCH_PROMPT_ARCH>
#      Codex → <RESEARCH_PROMPT_EDGE> (default) and <RESEARCH_PROMPT_EXT>
#              with `external_evidence_mode` switching language
#      Claude inline → RESEARCH_PROMPT_SEC
#
# Section extraction is H2-then-H3 nested:
#   1. Narrow to the `## 1.3` window (between `^## 1.3 ` and the next `^## `)
#      so the `### Standard` headers in Step 1.4 / Step 1.5 cannot satisfy
#      the per-lane pins below.
#   2. Within that window, scope to the `### Standard (RESEARCH_SCALE=standard, default)`
#      subsection (between that header and the next `^### ` header) so the
#      Quick / Deep subsections cannot substitute either.
#
# This nesting mirrors Check 16 of test-research-structure.sh — see that file
# for the rationale (scaling-block leakage prevention).
#
# Wired into `make lint` via the `test-standard-angle-prompts` target.
#
# Exit 0 on all assertions passing; exit 1 on any failure (with diagnostic on stderr).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
RESEARCH_MD="$REPO_ROOT/skills/research/references/research-phase.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Sanity: file exists.
[[ -f "$RESEARCH_MD" ]] \
  || fail "skills/research/references/research-phase.md not found at $RESEARCH_MD"

# Check 1: RESEARCH_PROMPT_BASELINE literal identifier present (the post-#508 rename).
grep -Fq "RESEARCH_PROMPT_BASELINE" "$RESEARCH_MD" \
  || fail "research-phase.md lacks RESEARCH_PROMPT_BASELINE identifier (post-#508 rename of RESEARCH_PROMPT)"

# Check 2: All four named angle prompt identifiers present.
for angle in ARCH EDGE EXT SEC; do
  grep -Fq "RESEARCH_PROMPT_${angle}" "$RESEARCH_MD" \
    || fail "research-phase.md lacks RESEARCH_PROMPT_${angle} identifier"
done

# Section extraction: narrow to ## 1.3 window first, then to ### Standard inside it.
SECTION_1_3=$(awk '/^## 1\.3 /{f=1; next} f && /^## /{f=0} f' "$RESEARCH_MD")
[[ -n "$SECTION_1_3" ]] \
  || fail "research-phase.md must contain a '## 1.3 ' section (Launch Research Perspectives) — angle-mapping pins cannot anchor without it"

STANDARD_BLOCK=$(echo "$SECTION_1_3" \
  | awk '/^### Standard \(RESEARCH_SCALE=standard,? ?default\)/{f=1; next} f && /^### /{f=0} f')
[[ -n "$STANDARD_BLOCK" ]] \
  || fail "research-phase.md Step 1.3 must contain '### Standard (RESEARCH_SCALE=standard, default)' subsection"

# Check 3: Cursor lane carries <RESEARCH_PROMPT_ARCH>.
echo "$STANDARD_BLOCK" | grep -Fq "<RESEARCH_PROMPT_ARCH>" \
  || fail "Step 1.3 ### Standard subsection must reference '<RESEARCH_PROMPT_ARCH>' (Cursor lane angle prompt — #508)"

# Check 4: Codex lane carries <RESEARCH_PROMPT_EDGE> as the default.
echo "$STANDARD_BLOCK" | grep -Fq "<RESEARCH_PROMPT_EDGE>" \
  || fail "Step 1.3 ### Standard subsection must reference '<RESEARCH_PROMPT_EDGE>' (Codex lane default angle prompt — #508)"

# Check 5: Codex lane mentions <RESEARCH_PROMPT_EXT> (external_evidence_mode=true variant).
echo "$STANDARD_BLOCK" | grep -Fq "<RESEARCH_PROMPT_EXT>" \
  || fail "Step 1.3 ### Standard subsection must reference '<RESEARCH_PROMPT_EXT>' (Codex lane external_evidence_mode=true variant — #508)"

# Check 6: Codex lane documents external_evidence_mode switching.
echo "$STANDARD_BLOCK" | grep -Fq "external_evidence_mode" \
  || fail "Step 1.3 ### Standard subsection must mention 'external_evidence_mode' for Codex EDGE → EXT switching (#508)"

# Check 7: Claude inline lane carries RESEARCH_PROMPT_SEC.
echo "$STANDARD_BLOCK" | grep -Fq "RESEARCH_PROMPT_SEC" \
  || fail "Step 1.3 ### Standard subsection must reference 'RESEARCH_PROMPT_SEC' (Claude inline lane angle prompt — #508)"

echo "PASS: 7 assertions"
