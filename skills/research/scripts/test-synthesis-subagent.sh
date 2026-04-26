#!/usr/bin/env bash
# test-synthesis-subagent.sh — Offline structural pin for the /research Step 1.5
# synthesis-subagent contract (issue #507) and the Step 2 Finalize Validation
# revision-subagent contract. Issue #520 adds K-vote profiles for Quick.
#
# This harness greps research-phase.md and validation-phase.md for the
# load-bearing literals introduced by issue #507 + #520:
#   - 4 synthesis branches (Standard PLAN=false, Standard PLAN=true,
#     Deep PLAN=false, Deep PLAN=true) MUST contain Agent-tool subagent
#     invocation pattern + structural-validator gate prose + helper-fork
#     pattern.
#   - Quick branch (issue #520) is now SPLIT into 3 #### sub-subsections:
#     - LANES_SUCCEEDED >= 2 vote path: MUST invoke synthesis subagent +
#       MUST contain Quick-vote validator profile + 3 vote markers
#       (### Consensus / ### Divergence / ### Correlated-error caveat).
#     - LANES_SUCCEEDED == 1 single-lane fallback path: MUST NOT invoke
#       a synthesis subagent + MUST contain 'Single-lane confidence'
#       fallback disclaimer reference.
#     - LANES_SUCCEEDED == 0 no-lane hard-fail path: MUST NOT invoke
#       a synthesis subagent + MUST contain explicit "research-phase failed"
#       prose.
#   - validation-phase.md Finalize Validation MUST route revision to a
#     separate Agent subagent + atomic-rewrite of research-report.txt.
#   - The 5 body markers (### Agreements / ### Divergences / ### Significance
#     / ### Architectural patterns / ### Risks and feasibility) MUST be
#     mandated by research-phase.md prose for non-Quick branches.
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

# Quick branch under §1.5 ### Quick (issue #520 splits this into 3 #### sub-subsections).
SECTION_15_QUICK_FULL=$(echo "$SECTION_15_FULL" | awk '
  /^### Quick \(RESEARCH_SCALE=quick\)/{f=1; next}
  f && /^### /{f=0}
  f
')
SECTION_15_QUICK_VOTE=$(echo "$SECTION_15_QUICK_FULL" | awk '
  /^#### When `LANES_SUCCEEDED >= 2`/{f=1; next}
  f && /^#### /{f=0}
  f
')
SECTION_15_QUICK_FALLBACK=$(echo "$SECTION_15_QUICK_FULL" | awk '
  /^#### When `LANES_SUCCEEDED == 1`/{f=1; next}
  f && /^#### /{f=0}
  f
')
SECTION_15_QUICK_NOLANE=$(echo "$SECTION_15_QUICK_FULL" | awk '
  /^#### When `LANES_SUCCEEDED == 0`/{f=1; next}
  f && /^#### /{f=0}
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
[[ -n "$SECTION_15_QUICK_FULL" ]] \
  || fail "research-phase.md must contain §1.5 '### Quick (RESEARCH_SCALE=quick)' subsection — extractor cannot anchor"
[[ -n "$SECTION_15_QUICK_VOTE" ]] \
  || fail "research-phase.md must contain §1.5 Quick '#### When \`LANES_SUCCEEDED >= 2\`' sub-subsection (issue #520 vote path) — Quick-vote profile cannot anchor"
[[ -n "$SECTION_15_QUICK_FALLBACK" ]] \
  || fail "research-phase.md must contain §1.5 Quick '#### When \`LANES_SUCCEEDED == 1\`' sub-subsection (issue #520 single-lane fallback) — Quick-fallback profile cannot anchor"
[[ -n "$SECTION_15_QUICK_NOLANE" ]] \
  || fail "research-phase.md must contain §1.5 Quick '#### When \`LANES_SUCCEEDED == 0\`' sub-subsection (issue #520 no-lane hard-fail) — Quick-fallback profile cannot anchor"

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

# ---------- Pin 5: Quick-vote profile (issue #520) ----------
# LANES_SUCCEEDED >= 2 sub-subsection MUST invoke the synthesis subagent and
# MUST mandate the 3 K-vote markers + a structural validator.

if echo "$SECTION_15_QUICK_VOTE" | grep -Eiq '(Invoke the synthesis subagent|synthesis subagent)'; then
  PASS=$((PASS + 1))
else
  fail "[Quick-vote] §1.5 Quick '#### When \`LANES_SUCCEEDED >= 2\`' sub-subsection MUST invoke the synthesis subagent (issue #520 vote path)"
fi

if echo "$SECTION_15_QUICK_VOTE" | grep -Eiq '(structural validator|Apply the structural validator|Quick-vote profile)'; then
  PASS=$((PASS + 1))
else
  fail "[Quick-vote] §1.5 Quick '#### When \`LANES_SUCCEEDED >= 2\`' sub-subsection MUST mandate a structural validator (issue #520 vote path)"
fi

QUICK_VOTE_MARKERS=(
  '### Consensus'
  '### Divergence'
  '### Correlated-error caveat'
)
for marker in "${QUICK_VOTE_MARKERS[@]}"; do
  if echo "$SECTION_15_QUICK_VOTE" | grep -Fq "$marker"; then
    PASS=$((PASS + 1))
  else
    fail "[Quick-vote markers] §1.5 Quick '#### When \`LANES_SUCCEEDED >= 2\`' sub-subsection MUST mandate marker '$marker' (issue #520)"
  fi
done

# K-lane voting confidence must be referenced on the vote path (positive anchor).
if echo "$SECTION_15_QUICK_VOTE" | grep -Fq "K-lane voting confidence"; then
  PASS=$((PASS + 1))
else
  fail "[Quick-vote] §1.5 Quick vote sub-subsection MUST reference 'K-lane voting confidence' framing (issue #520)"
fi

# ---------- Pin 6: Quick-fallback profile (issue #520) ----------
# LANES_SUCCEEDED == 1 sub-subsection MUST NOT invoke a synthesis subagent and
# MUST reference the Single-lane confidence fallback disclaimer.

if echo "$SECTION_15_QUICK_FALLBACK" | grep -Eiq '(Invoke the synthesis subagent|Apply the structural validator)'; then
  fail "[Quick-fallback] §1.5 Quick '#### When \`LANES_SUCCEEDED == 1\`' sub-subsection MUST NOT invoke a synthesis subagent or apply a validator (issue #520 single-lane fallback path)"
else
  PASS=$((PASS + 1))
fi

# Single-lane confidence disclaimer reference.
if echo "$SECTION_15_QUICK_FALLBACK" | grep -Fq "Single-lane confidence"; then
  PASS=$((PASS + 1))
else
  fail "[Quick-fallback] §1.5 Quick '#### When \`LANES_SUCCEEDED == 1\`' sub-subsection MUST reference 'Single-lane confidence' fallback disclaimer (issue #520)"
fi

# Reference to the fallback file path.
if echo "$SECTION_15_QUICK_FALLBACK" | grep -Fq "quick-disclaimer-fallback.txt"; then
  PASS=$((PASS + 1))
else
  fail "[Quick-fallback] §1.5 Quick '#### When \`LANES_SUCCEEDED == 1\`' sub-subsection MUST reference 'quick-disclaimer-fallback.txt' (issue #520)"
fi

# ---------- Pin 6b: Quick no-lane hard-fail (issue #520) ----------
# LANES_SUCCEEDED == 0 sub-subsection MUST NOT invoke a synthesis subagent.

if echo "$SECTION_15_QUICK_NOLANE" | grep -Eiq '(Invoke the synthesis subagent|Apply the structural validator)'; then
  fail "[Quick-nolane] §1.5 Quick '#### When \`LANES_SUCCEEDED == 0\`' sub-subsection MUST NOT invoke a synthesis subagent or apply a validator (issue #520 no-lane hard-fail path)"
else
  PASS=$((PASS + 1))
fi

# No-lane hard-fail must mention the failure mode prose.
if echo "$SECTION_15_QUICK_NOLANE" | grep -Eiq '(research[ -]phase failed|all .*lanes returned empty|hard-fail)'; then
  PASS=$((PASS + 1))
else
  fail "[Quick-nolane] §1.5 Quick '#### When \`LANES_SUCCEEDED == 0\`' sub-subsection MUST contain explicit 'research-phase failed' / 'lanes returned empty' / 'hard-fail' prose (issue #520)"
fi

# ---------- Pin 6c: Negative — 'independent reviewers' must be absent ----------
# Failure mode 4 mitigation: synthesis prompt must not overstate K-lane voting
# as cross-tool diversity. Negative pin: no occurrence of "independent reviewers"
# anywhere in the Quick branch.

if echo "$SECTION_15_QUICK_FULL" | grep -Fq "independent reviewers"; then
  fail "[Quick negative] §1.5 Quick branch MUST NOT contain 'independent reviewers' (issue #520 — overstates K-lane voting as cross-tool diversity)"
else
  PASS=$((PASS + 1))
fi

# ---------- Pin 6: 5 body markers mandated in research-phase.md ----------

REQUIRED_MARKERS=(
  '### Agreements'
  '### Divergences'
  '### Significance'
  '### Architectural patterns'
  '### Risks and feasibility'
)
# Use pure-bash substring match instead of `echo | grep -Fq`. With `set -euo
# pipefail` and §1.5 growing past the OS pipe buffer (issue #520 K-vote
# additions), `echo`'s SIGPIPE on early `grep -q` exit propagates as a non-zero
# pipeline exit and produces false-negative test failures in CI. The glob form
# is subprocess-free and immune to SIGPIPE.
for marker in "${REQUIRED_MARKERS[@]}"; do
  if [[ "$SECTION_15_FULL" == *"$marker"* ]]; then
    PASS=$((PASS + 1))
  else
    fail "[markers] §1.5 must mandate body marker '$marker' in synthesis subagent prompt prose (#507 5-marker contract)"
  fi
done

# Per-subquestion regex anchor mandated for plan branches.
if [[ "$SECTION_15_FULL" == *'^### Subquestion [0-9]+:'* ]]; then
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
