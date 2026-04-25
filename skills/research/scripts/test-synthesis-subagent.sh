#!/usr/bin/env bash
# test-synthesis-subagent.sh — Offline structural pin for the /research Step 1.5
# synthesis-subagent contract (issue #507) and the Step 2 Finalize Validation
# revision-subagent contract.
#
# This harness greps research-phase.md and validation-phase.md for the
# load-bearing literals introduced by issue #507:
#   - 4 synthesis branches (Standard PLAN=false, Standard PLAN=true,
#     Deep PLAN=false, Deep PLAN=true) MUST contain Agent-tool subagent
#     invocation pattern + structural-validator gate prose + helper-fork
#     pattern.
#   - Quick branch MUST remain inline (no Agent invocation, no validator).
#   - validation-phase.md Finalize Validation MUST route revision to a
#     separate Agent subagent + atomic-rewrite of research-report.txt.
#   - The 5 body markers (### Agreements / ### Divergences / ### Significance
#     / ### Architectural patterns / ### Risks and feasibility) MUST be
#     mandated by research-phase.md prose.
#
# Wired into `make lint` via the `test-synthesis-subagent` target. See
# `test-synthesis-subagent.md` for the contract and edit-in-sync rules.
#
# Exit 0 on all assertions passing; exit 1 on any failure (with diagnostic
# on stderr).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
RESEARCH_PHASE_MD="$REPO_ROOT/skills/research/references/research-phase.md"
VALIDATION_PHASE_MD="$REPO_ROOT/skills/research/references/validation-phase.md"
HELPER_SCRIPT="$REPO_ROOT/skills/research/scripts/compute-degraded-banner.sh"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

# ---------- Preconditions ----------

[[ -f "$RESEARCH_PHASE_MD" ]] || fail "research-phase.md missing: $RESEARCH_PHASE_MD"
[[ -f "$VALIDATION_PHASE_MD" ]] || fail "validation-phase.md missing: $VALIDATION_PHASE_MD"
[[ -f "$HELPER_SCRIPT" ]] || fail "compute-degraded-banner.sh missing: $HELPER_SCRIPT"

# Bail early if any precondition file is missing; downstream greps would
# emit confusing chained failures.
if (( FAIL > 0 )); then
  echo "test-synthesis-subagent.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

# ---------- Section extractors (research-phase.md §1.5) ----------

# Slice the §1.5 window first (mirrors test-research-structure.sh's pattern).
SECTION_15_FULL=$(awk '
  /^## 1\.5 — Synthesis/{f=1; next}
  f && /^## /{f=0}
  f
' "$RESEARCH_PHASE_MD")
[[ -n "$SECTION_15_FULL" ]] \
  || fail "research-phase.md must contain a '## 1.5 — Synthesis' section terminated by the next '## ' heading"

# Standard branches (RESEARCH_PLAN=false / RESEARCH_PLAN=true) under §1.5 ###
# Standard.
SECTION_15_STANDARD_FULL=$(echo "$SECTION_15_FULL" | awk '
  /^### Standard \(RESEARCH_SCALE=standard/{f=1; next}
  f && /^### /{f=0}
  f
')
SECTION_15_STANDARD_FALSE=$(echo "$SECTION_15_STANDARD_FULL" | awk '
  /^#### When `RESEARCH_PLAN=false`/{f=1; next}
  f && /^#### /{f=0}
  f
')
SECTION_15_STANDARD_TRUE=$(echo "$SECTION_15_STANDARD_FULL" | awk '
  /^#### When `RESEARCH_PLAN=true`/{f=1; next}
  f && /^#### /{f=0}
  f
')

# Deep branches under §1.5 ### Deep.
SECTION_15_DEEP_FULL=$(echo "$SECTION_15_FULL" | awk '
  /^### Deep \(RESEARCH_SCALE=deep\)/{f=1; next}
  f && /^### /{f=0}
  f
')
SECTION_15_DEEP_FALSE=$(echo "$SECTION_15_DEEP_FULL" | awk '
  /^#### When `RESEARCH_PLAN=false`/{f=1; next}
  f && /^#### /{f=0}
  f
')
SECTION_15_DEEP_TRUE=$(echo "$SECTION_15_DEEP_FULL" | awk '
  /^#### When `RESEARCH_PLAN=true`/{f=1; next}
  f && /^#### /{f=0}
  f
')

# Quick branch under §1.5 ### Quick.
SECTION_15_QUICK=$(echo "$SECTION_15_FULL" | awk '
  /^### Quick \(RESEARCH_SCALE=quick\)/{f=1; next}
  f && /^### /{f=0}
  f
')

[[ -n "$SECTION_15_STANDARD_FALSE" ]] \
  || fail "research-phase.md must contain §1.5 Standard '#### When \`RESEARCH_PLAN=false\`' subsection — extractor cannot anchor"
[[ -n "$SECTION_15_STANDARD_TRUE" ]] \
  || fail "research-phase.md must contain §1.5 Standard '#### When \`RESEARCH_PLAN=true\`' subsection — extractor cannot anchor"
[[ -n "$SECTION_15_DEEP_FALSE" ]] \
  || fail "research-phase.md must contain §1.5 Deep '#### When \`RESEARCH_PLAN=false\`' subsection — extractor cannot anchor"
[[ -n "$SECTION_15_DEEP_TRUE" ]] \
  || fail "research-phase.md must contain §1.5 Deep '#### When \`RESEARCH_PLAN=true\`' subsection — extractor cannot anchor"
[[ -n "$SECTION_15_QUICK" ]] \
  || fail "research-phase.md must contain §1.5 '### Quick (RESEARCH_SCALE=quick)' subsection — extractor cannot anchor"

if (( FAIL > 0 )); then
  echo "test-synthesis-subagent.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

# ---------- Pin 1-4: 4 non-quick branches mandate subagent invocation ----------

assert_branch_has_subagent() {
  local label="$1"
  local body="$2"

  # Pattern: each non-quick branch must mention "synthesis subagent" or
  # "Agent subagent" or specifically the invocation phrasing introduced by #507.
  if ! echo "$body" | grep -Eiq '(synthesis subagent|Agent subagent|Invoke the synthesis subagent)'; then
    fail "[$label] missing synthesis-subagent invocation prose; #507 requires the 3 non-quick branches (and the planner-true variants) to route synthesis to a separate Agent subagent"
    return
  fi

  # Helper-fork pattern: orchestrator computes banner via
  # compute-degraded-banner.sh BEFORE the subagent call.
  if ! echo "$body" | grep -Fq 'compute-degraded-banner.sh'; then
    fail "[$label] missing compute-degraded-banner.sh fork reference; #507 requires the orchestrator to compute the banner via the helper before invoking the synthesis subagent"
    return
  fi

  # Structural-validator gate: each branch must mention "structural validator"
  # or "validator" + "fall back".
  if ! echo "$body" | grep -Eiq '(structural validator|Apply the structural validator)'; then
    fail "[$label] missing structural-validator gate prose; #507 requires a per-profile validator on subagent output"
    return
  fi
  if ! echo "$body" | grep -Eiq '(falling back to inline|fallback)'; then
    fail "[$label] missing inline-fallback prose; #507 requires fallback to inline synthesis on validator failure"
    return
  fi

  PASS=$((PASS + 1))
}

assert_branch_has_subagent "Standard RESEARCH_PLAN=false" "$SECTION_15_STANDARD_FALSE"
assert_branch_has_subagent "Standard RESEARCH_PLAN=true"  "$SECTION_15_STANDARD_TRUE"
assert_branch_has_subagent "Deep RESEARCH_PLAN=false"     "$SECTION_15_DEEP_FALSE"
assert_branch_has_subagent "Deep RESEARCH_PLAN=true"      "$SECTION_15_DEEP_TRUE"

# ---------- Pin 5: Quick branch must NOT contain subagent invocation ----------

if echo "$SECTION_15_QUICK" | grep -Eiq '(Invoke the synthesis subagent|synthesis subagent.*Standard|Apply the structural validator)'; then
  fail "[Quick] §1.5 Quick branch must remain inline (no Agent subagent invocation, no validator) per #507 — single-lane synthesis has no diversity to debias"
else
  PASS=$((PASS + 1))
fi

# Quick branch retains its 'Single-lane confidence' disclaimer (sanity).
if echo "$SECTION_15_QUICK" | grep -Fq "Single-lane confidence"; then
  PASS=$((PASS + 1))
else
  fail "[Quick] §1.5 Quick branch must retain the 'Single-lane confidence' disclaimer"
fi

# ---------- Pin 6: 5 body markers mandated in research-phase.md ----------

REQUIRED_MARKERS=(
  '### Agreements'
  '### Divergences'
  '### Significance'
  '### Architectural patterns'
  '### Risks and feasibility'
)
for marker in "${REQUIRED_MARKERS[@]}"; do
  if echo "$SECTION_15_FULL" | grep -Fq "$marker"; then
    PASS=$((PASS + 1))
  else
    fail "[markers] §1.5 must mandate body marker '$marker' in synthesis subagent prompt prose (#507 5-marker contract)"
  fi
done

# Per-subquestion regex anchor mandated for plan branches.
if echo "$SECTION_15_FULL" | grep -Fq '^### Subquestion [0-9]+:'; then
  PASS=$((PASS + 1))
else
  fail "[markers] §1.5 must mandate the anchored regex '^### Subquestion [0-9]+:' for RESEARCH_PLAN=true branches (#507 anchored-count rule)"
fi

# Per-angle highlights mandated in Deep + plan.
if echo "$SECTION_15_DEEP_TRUE" | grep -Fq '### Per-angle highlights'; then
  PASS=$((PASS + 1))
else
  fail "[markers] §1.5 Deep RESEARCH_PLAN=true must mandate '### Per-angle highlights' marker"
fi

# Cross-cutting findings mandated in plan branches.
if echo "$SECTION_15_STANDARD_TRUE" | grep -Fq '### Cross-cutting findings'; then
  PASS=$((PASS + 1))
else
  fail "[markers] §1.5 Standard RESEARCH_PLAN=true must mandate '### Cross-cutting findings' marker"
fi
if echo "$SECTION_15_DEEP_TRUE" | grep -Fq '### Cross-cutting findings'; then
  PASS=$((PASS + 1))
else
  fail "[markers] §1.5 Deep RESEARCH_PLAN=true must mandate '### Cross-cutting findings' marker"
fi

# 4 angle names mandated in Deep branches (both PLAN values).
ANGLE_NAMES=(
  'architecture & data flow'
  'edge cases & failure modes'
  'external comparisons'
  'security & threat surface'
)
for angle in "${ANGLE_NAMES[@]}"; do
  if echo "$SECTION_15_DEEP_FULL" | grep -Fq "$angle"; then
    PASS=$((PASS + 1))
  else
    fail "[angles] §1.5 Deep branch must name angle '$angle' in synthesis subagent prompt prose"
  fi
done

# ---------- Pin 7-8: validation-phase.md Finalize Validation ----------

# Extract Finalize Validation section.
SECTION_FINALIZE=$(awk '
  /^## Finalize Validation/{f=1; next}
  f && /^## /{f=0}
  f
' "$VALIDATION_PHASE_MD")
[[ -n "$SECTION_FINALIZE" ]] \
  || fail "validation-phase.md must contain a '## Finalize Validation' section terminated by the next '## ' heading"

if [[ -n "$SECTION_FINALIZE" ]]; then
  # Pin 7: Finalize Validation routes revision to a separate subagent.
  if echo "$SECTION_FINALIZE" | grep -Eiq '(revision subagent|Route the synthesis-revision)'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must route revision to a separate Claude Agent subagent per #507"
  fi

  # Pin 7b: revision subagent capture path.
  if echo "$SECTION_FINALIZE" | grep -Fq 'revision-raw.txt'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must capture revision subagent output to \$RESEARCH_TMPDIR/revision-raw.txt per #507"
  fi

  # Pin 8: orchestrator atomically rewrites research-report.txt.
  if echo "$SECTION_FINALIZE" | grep -Eiq '(atomically rewrite|atomic.*rewrite|rewrite.*atomically|mktemp.*mv)'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must atomically rewrite \$RESEARCH_TMPDIR/research-report.txt with the revised body per #507 (without this, Step 3 consumes the pre-revision report)"
  fi

  # Pin 8b: structural validator on revision output.
  if echo "$SECTION_FINALIZE" | grep -Eiq '(structural validator|Apply the structural validator)'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must apply the structural validator to revision subagent output per #507"
  fi

  # Pin 8c: inline-revision fallback.
  if echo "$SECTION_FINALIZE" | grep -Eiq '(Inline-revision fallback|inline revision)'; then
    PASS=$((PASS + 1))
  else
    fail "[Finalize Validation] must specify inline-revision fallback on validator failure per #507"
  fi
fi

# ---------- Pin 9: helper script presence + ownership ----------

if [[ -x "$HELPER_SCRIPT" ]]; then
  PASS=$((PASS + 1))
else
  fail "compute-degraded-banner.sh must be executable: $HELPER_SCRIPT"
fi

# ---------- Summary ----------

if (( FAIL > 0 )); then
  echo "test-synthesis-subagent.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

echo "PASS: test-synthesis-subagent.sh — $PASS assertions passed"
exit 0
