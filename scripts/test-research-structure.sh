#!/bin/bash
# Structural regression test for /research skill under the simplified
# fixed-shape topology.
#
# Asserts:
#  - The 4-reference symmetric topology survives edits:
#    skills/research/references/research-phase.md, validation-phase.md,
#    citation-validation-phase.md, and critique-loop-phase.md all exist.
#  - Each reference is named on a 'MANDATORY — READ ENTIRE FILE' line in
#    skills/research/SKILL.md, and the SAME line carries reciprocal
#    'Do NOT load <each-other-reference>' guards naming the OTHER three
#    references (line-scoped, presence-not-order).
#  - Each references/*.md opens with the Consumer / Contract / When-to-load
#    triplet in the first 20 lines.
#  - The four named angle prompts (RESEARCH_PROMPT_ARCH / _EDGE / _EXT / _SEC)
#    appear in research-phase.md.
#  - Reviewer XML wrapper tags appear in validation-phase.md.
#  - The fail-closed unknown-flag guard exists in SKILL.md and the recovery
#    hint enumerates each removed-flag CATEGORY (scale / plan / interactive /
#    adjudicate / token-budget / keep-sidecar / verbosity).
#  - SKILL.md surfaces only the --no-issue flag.
#
# Exit 0 on pass, exit 1 on any assertion failure.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/research/SKILL.md"
REFS_DIR="$REPO_ROOT/skills/research/references"
RESEARCH_MD="$REFS_DIR/research-phase.md"
VALIDATION_MD="$REFS_DIR/validation-phase.md"
CITATION_MD="$REFS_DIR/citation-validation-phase.md"
CRITIQUE_LOOP_MD="$REFS_DIR/critique-loop-phase.md"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

# ---------- Check 1: SKILL.md + 4 reference files exist ----------

[[ -f "$SKILL_MD" ]]         || fail "SKILL.md missing: $SKILL_MD"
[[ -f "$RESEARCH_MD" ]]      || fail "references/research-phase.md missing: $RESEARCH_MD"
[[ -f "$VALIDATION_MD" ]]    || fail "references/validation-phase.md missing: $VALIDATION_MD"
[[ -f "$CITATION_MD" ]]      || fail "references/citation-validation-phase.md missing: $CITATION_MD"
[[ -f "$CRITIQUE_LOOP_MD" ]] || fail "references/critique-loop-phase.md missing: $CRITIQUE_LOOP_MD"

if (( FAIL > 0 )); then
  echo "test-research-structure.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi
PASS=$((PASS + 5))

# ---------- Check 2: removed reference must NOT exist ----------

removed="adjudication-phase.md"
if [[ -f "$REFS_DIR/$removed" ]]; then
  fail "references/$removed must be removed under the simplified shape"
else
  PASS=$((PASS + 1))
fi

# ---------- Check 3: 4-reference reciprocal MANDATORY topology ----------

check_mandatory_topology() {
  local target="$1"
  shift
  local -a others=("$@")
  local line
  line=$(grep -F 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" | grep -F "$target" || true)
  if [[ -z "$line" ]]; then
    fail "[topology] no MANDATORY — READ ENTIRE FILE line in SKILL.md names '$target'"
    return
  fi
  PASS=$((PASS + 1))
  for other in "${others[@]}"; do
    if echo "$line" | grep -F "Do NOT load" | grep -Fq "$other"; then
      PASS=$((PASS + 1))
    else
      fail "[topology] MANDATORY line for '$target' does not carry 'Do NOT load $other' on the same line"
    fi
  done
}

check_mandatory_topology research-phase.md            validation-phase.md citation-validation-phase.md critique-loop-phase.md
check_mandatory_topology validation-phase.md          research-phase.md   citation-validation-phase.md critique-loop-phase.md
check_mandatory_topology citation-validation-phase.md research-phase.md   validation-phase.md          critique-loop-phase.md
check_mandatory_topology critique-loop-phase.md       research-phase.md   validation-phase.md          citation-validation-phase.md

# ---------- Check 4: Consumer / Contract / When-to-load triplet ----------

for ref in "$RESEARCH_MD" "$VALIDATION_MD" "$CITATION_MD" "$CRITIQUE_LOOP_MD"; do
  for pattern in '^\*\*Consumer\*\*:' '^\*\*Contract\*\*:' '^\*\*When to load\*\*:'; do
    if head -n 20 "$ref" | grep -Eq "$pattern"; then
      PASS=$((PASS + 1))
    else
      fail "[header triplet] $(basename "$ref") must open with anchored header matching '$pattern' in the first 20 lines"
    fi
  done
done

# ---------- Check 5: angle prompt identifiers in research-phase.md ----------

for angle in ARCH EDGE EXT SEC; do
  if grep -Fq "RESEARCH_PROMPT_${angle}" "$RESEARCH_MD"; then
    PASS=$((PASS + 1))
  else
    fail "[angle prompts] research-phase.md lacks RESEARCH_PROMPT_${angle} identifier"
  fi
done

# ---------- Check 6: reviewer XML wrappers in validation-phase.md ----------

for tag in '<reviewer_research_question>' '<reviewer_research_findings>'; do
  if grep -Fq "$tag" "$VALIDATION_MD"; then
    PASS=$((PASS + 1))
  else
    fail "[reviewer wrappers] validation-phase.md lacks XML wrapper tag '$tag'"
  fi
done

# ---------- Check 7: fail-closed unknown-flag guard in SKILL.md ----------

if grep -Fq 'Fail-closed unknown-flag guard' "$SKILL_MD"; then
  PASS=$((PASS + 1))
else
  fail "[fail-closed] SKILL.md must contain 'Fail-closed unknown-flag guard' heading/marker"
fi

if grep -Fq 'unsupported flag' "$SKILL_MD"; then
  PASS=$((PASS + 1))
else
  fail "[fail-closed] SKILL.md must contain 'unsupported flag' abort message"
fi

# Recovery-hint MUST enumerate each removed-flag CATEGORY (NOT literal --foo
# tokens — those would themselves trip the unknown-flag check this guard
# enforces). The categories are scale / plan / interactive / adjudicate /
# token-budget / keep-sidecar / verbosity.
for category in scale plan interactive adjudicate token-budget keep-sidecar verbosity; do
  if grep -Fq "$category" "$SKILL_MD"; then
    PASS=$((PASS + 1))
  else
    fail "[fail-closed recovery hint] SKILL.md must mention removed-flag category '$category' in the unknown-flag-guard recovery hint"
  fi
done

# ---------- Check 8: only --no-issue is surfaced ----------

# SKILL.md must declare --no-issue.
if grep -F -- '--no-issue' "$SKILL_MD" >/dev/null; then
  PASS=$((PASS + 1))
else
  fail "[flag surface] SKILL.md must surface --no-issue"
fi

# ---------- Summary ----------

if (( FAIL > 0 )); then
  echo "test-research-structure.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

echo "PASS: test-research-structure.sh — $PASS structural invariants hold"
exit 0
