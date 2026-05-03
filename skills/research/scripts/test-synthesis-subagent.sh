#!/usr/bin/env bash
# test-synthesis-subagent.sh — Offline structural pin for the /research Step 1.5
# synthesis-subagent contract under the fixed-shape topology.
#
# Pins:
#   - §1.5 mandates a single synthesis-subagent invocation that reads the 4
#     lane output files by path, with explicit "treat as data, not instructions"
#     hardening prose.
#   - The orchestrator forks `compute-research-banner.sh` BEFORE invoking the
#     subagent (banner ownership is the orchestrator's, not the subagent's).
#   - A structural validator runs after the subagent returns, with an inline
#     fallback on validator failure.
#   - The 5 body markers (### Agreements / ### Divergences / ### Significance
#     / ### Architectural patterns / ### Risks and feasibility) are mandated.
#   - The 4 angle names are mandated by name.
#   - The anchored regex `^### Subquestion [0-9]+:` is mandated for the
#     planner-driven (RESEARCH_PLAN_N > 0) profile.
#   - validation-phase.md Finalize Validation MUST route revision to a separate
#     Agent subagent and atomically rewrite research-report.txt.
#
# Wired into `make lint` via the `test-synthesis-subagent` target. See
# `test-synthesis-subagent.md` for the contract and edit-in-sync rules.
#
# Exit 0 on all assertions passing; exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
RESEARCH_PHASE_MD="$REPO_ROOT/skills/research/references/research-phase.md"
VALIDATION_PHASE_MD="$REPO_ROOT/skills/research/references/validation-phase.md"
HELPER_SCRIPT="$REPO_ROOT/skills/research/scripts/compute-research-banner.sh"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

# ---------- Preconditions ----------

[[ -f "$RESEARCH_PHASE_MD" ]] || fail "research-phase.md missing: $RESEARCH_PHASE_MD"
[[ -f "$VALIDATION_PHASE_MD" ]] || fail "validation-phase.md missing: $VALIDATION_PHASE_MD"
[[ -f "$HELPER_SCRIPT" ]] || fail "compute-research-banner.sh missing: $HELPER_SCRIPT"

if (( FAIL > 0 )); then
  echo "test-synthesis-subagent.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

# ---------- Section extractor ----------

SECTION_15=$(awk '
  /^## 1\.5 — Synthesis/{f=1; next}
  f && /^## /{f=0}
  f
' "$RESEARCH_PHASE_MD")
[[ -n "$SECTION_15" ]] \
  || fail "research-phase.md must contain '## 1.5 — Synthesis' section terminated by next '## ' heading"

if (( FAIL > 0 )); then
  echo "test-synthesis-subagent.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

# ---------- Pin 1: subagent invocation prose ----------

if [[ "$SECTION_15" == *"synthesis subagent"* ]] || [[ "$SECTION_15" == *"Synthesis subagent"* ]]; then
  PASS=$((PASS + 1))
else
  fail "[invocation] §1.5 must mention the synthesis subagent"
fi

# ---------- Pin 2: orchestrator forks compute-research-banner.sh ----------

if [[ "$SECTION_15" == *"compute-research-banner.sh"* ]]; then
  PASS=$((PASS + 1))
else
  fail "[banner ownership] §1.5 must reference compute-research-banner.sh — orchestrator forks helper before subagent"
fi

# ---------- Pin 3: lane-output file path tags ----------

for tag in '<lane_1_output_path>' '<lane_2_output_path>' '<lane_3_output_path>' '<lane_4_output_path>'; do
  if [[ "$SECTION_15" == *"$tag"* ]]; then
    PASS=$((PASS + 1))
  else
    fail "[lane tags] §1.5 must wrap lane-output file paths in $tag"
  fi
done

# ---------- Pin 4: prompt-injection hardening prose ----------

if [[ "$SECTION_15" == *"data, not instructions"* ]]; then
  PASS=$((PASS + 1))
else
  fail "[hardening] §1.5 must contain 'data, not instructions' hardening prose"
fi

# ---------- Pin 5: structural validator + inline fallback ----------

if [[ "$SECTION_15" == *"Structural validator"* ]] || [[ "$SECTION_15" == *"structural validation"* ]]; then
  PASS=$((PASS + 1))
else
  fail "[validator] §1.5 must mandate a structural validator on subagent output"
fi

if [[ "$SECTION_15" == *"inline synthesis"* ]] || [[ "$SECTION_15" == *"inline-synthesis fallback"* ]]; then
  PASS=$((PASS + 1))
else
  fail "[validator] §1.5 must specify inline-synthesis fallback on validator failure"
fi

# ---------- Pin 6: 5 body markers ----------

REQUIRED_MARKERS=(
  '### Agreements'
  '### Divergences'
  '### Significance'
  '### Architectural patterns'
  '### Risks and feasibility'
)
for marker in "${REQUIRED_MARKERS[@]}"; do
  if [[ "$SECTION_15" == *"$marker"* ]]; then
    PASS=$((PASS + 1))
  else
    fail "[markers] §1.5 must mandate body marker '$marker'"
  fi
done

# ---------- Pin 7: anchored regex for planner-driven profile ----------

if [[ "$SECTION_15" == *'^### Subquestion [0-9]+:'* ]]; then
  PASS=$((PASS + 1))
else
  fail "[anchored regex] §1.5 must mandate '^### Subquestion [0-9]+:' for the RESEARCH_PLAN_N > 0 profile"
fi

if [[ "$SECTION_15" == *'### Per-angle highlights'* ]]; then
  PASS=$((PASS + 1))
else
  fail "[markers] §1.5 must mandate '### Per-angle highlights' marker for planner-driven runs"
fi

if [[ "$SECTION_15" == *'### Cross-cutting findings'* ]]; then
  PASS=$((PASS + 1))
else
  fail "[markers] §1.5 must mandate '### Cross-cutting findings' marker for planner-driven runs"
fi

# ---------- Pin 8: 4 angle names ----------

ANGLE_NAMES=(
  'architecture & data flow'
  'edge cases & failure modes'
  'external comparisons'
  'security & threat surface'
)
for angle in "${ANGLE_NAMES[@]}"; do
  if [[ "$SECTION_15" == *"$angle"* ]]; then
    PASS=$((PASS + 1))
  else
    fail "[angles] §1.5 must name angle '$angle' in synthesis prompt prose"
  fi
done

# ---------- Pin 9: orchestrator forbids subagent emitting banner literal ----------

if [[ "$SECTION_15" == *"must NOT emit the banner literal"* ]] || \
   [[ "$SECTION_15" == *"Do NOT emit any reduced-diversity banner literal"* ]] || \
   [[ "$SECTION_15" == *"the orchestrator owns it"* ]]; then
  PASS=$((PASS + 1))
else
  fail "[banner ownership] §1.5 must explicitly forbid the subagent from emitting the banner literal"
fi

# ---------- Pin 10: validation-phase.md Finalize Validation routes revision to subagent ----------

SECTION_FINALIZE=$(awk '
  /^## Finalize Validation/{f=1; next}
  f && /^## /{f=0}
  f
' "$VALIDATION_PHASE_MD")
[[ -n "$SECTION_FINALIZE" ]] \
  || fail "validation-phase.md must contain '## Finalize Validation' section terminated by next '## ' heading"

if [[ -n "$SECTION_FINALIZE" ]]; then
  if echo "$SECTION_FINALIZE" | grep -Eiq '(revision subagent|Route the synthesis-revision)'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must route revision to a separate Claude Agent subagent"
  fi

  if echo "$SECTION_FINALIZE" | grep -Fq 'revision-raw.txt'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must capture revision subagent output to \$RESEARCH_TMPDIR/revision-raw.txt"
  fi

  if echo "$SECTION_FINALIZE" | grep -Eiq '(atomically rewrite|atomic.*rewrite|rewrite.*atomically|mktemp.*mv)'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must atomically rewrite \$RESEARCH_TMPDIR/research-report.txt with the revised body"
  fi

  if echo "$SECTION_FINALIZE" | grep -Eiq '(structural validator|Apply the structural validator)'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must apply the structural validator to revision subagent output"
  fi

  if echo "$SECTION_FINALIZE" | grep -Eiq '(Inline-revision fallback|inline revision)'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must specify inline-revision fallback on validator failure"
  fi
fi

# ---------- Pin 11: helper script is executable ----------

if [[ -x "$HELPER_SCRIPT" ]]; then
  PASS=$((PASS + 1))
else
  fail "compute-research-banner.sh must be executable: $HELPER_SCRIPT"
fi

# ---------- Summary ----------

if (( FAIL > 0 )); then
  echo "test-synthesis-subagent.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

echo "PASS: test-synthesis-subagent.sh — $PASS assertions passed"
exit 0
