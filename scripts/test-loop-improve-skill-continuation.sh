#!/usr/bin/env bash
# test-loop-improve-skill-continuation.sh — Regression harness for
# /loop-improve-skill + /loop-improve-skill-iter structural continuation
# invariants (closes #231).
#
# Asserts that each halt-equivalent edge in the split skill pair carries
# the mechanical gate / sentinel pattern required to detect parent halt
# at author time, so prose-banner drift cannot silently re-introduce
# issue #231.
#
# Contract (must stay in sync with AGENTS.md canonical-source bullet and
# with both SKILL.md files):
#
#   Inner skills/loop-improve-skill-iter/SKILL.md MUST contain:
#     - Per-substep sentinel literals:
#         iter-${ITER}-3j.done
#         iter-${ITER}-3jv.done                (NEW — Step 3.j.v grade-parse)
#         iter-${ITER}-3d-pre-detect.done
#         iter-${ITER}-3d-post-detect.done
#         iter-${ITER}-3d-plan-post.done
#         iter-${ITER}-3i.done
#         iter-${ITER}-done.sentinel
#         iter-${ITER}-infeasibility.md        (NEW — written on no_plan / design_refusal / im_verification_failed halts)
#     - At least one printf 'done\n' > ... literal (non-empty sentinel write —
#       NOT touch, which would make verify-skill-called.sh --sentinel-file
#       return VERIFIED=false empty_file).
#     - A verify-skill-called.sh invocation (for /im's stdout-line gate).
#     - The shared parser invocation: parse-skill-judge-grade.sh (NEW).
#     - gh issue comment (appears at least twice: 3.j + 3.d-plan-post).
#     - Each substep breadcrumb: 🔶 3.j, 🔶 3.j.v (NEW), 🔶 3.d, 🔶 3.i
#       (Step 4 is close-out only; it emits a ✅ completion line, not a
#       🔶 start line, so no breadcrumb assertion applies there.)
#     - The LOOP_TMPDIR path-prefix guard literal /private/tmp/ (the
#       security-boundary check from FINDING_8).
#     - The grade-A short-circuit literal: grade_a_achieved (NEW).
#     - The /design prompt enrichment literal: Non-A dimensions (NEW).
#     - The grade-history filename literal: grade-history.txt (NEW).
#
#   Outer skills/loop-improve-skill/SKILL.md MUST contain:
#     - verify-skill-called.sh --sentinel-file  (the iteration gate).
#     - /loop-improve-skill-iter               (the delegated child name).
#     - cleanup-tmpdir.sh                      (Step 6 cleanup).
#     - max iterations (10) reached           (the normal-completion exit literal — FINDING_7).
#     - iteration sentinel missing             (the halt-detected exit literal).
#     - last-completed=                        (#247 ledger-scan contract token — enriched halt diagnostic).
#     - halted at or before /skill-judge       (#247 halt-location clause for LAST_COMPLETED=none).
#     - halted at or before /design            (#247 halt-location clause for LAST_COMPLETED=3jv).
#     - halted at or before /im                (#247 halt-location clause for LAST_COMPLETED=3d-plan-post).
#     - grade_a_achieved                       (NEW — terminal happy-path ITER_STATUS).
#     - grade A achieved                       (NEW — EXIT_REASON token).
#     - parse-skill-judge-grade.sh             (NEW — Step 5a final-judge parser invocation).
#     - final-judge.txt                        (NEW — Step 5a capture filename).
#     - Infeasibility Justification            (NEW — close-out body section heading).
#     - Grade History                          (NEW — close-out body section heading).
#     - At least one gh issue comment          (NEW — Step 5c close-out comment post).
#
#   Both SKILL.md files MUST carry EXACTLY ONE top-of-file Anti-halt banner:
#     **Anti-halt continuation reminder.**
#   (Banner-density cap — keeping the mechanical gate as the primary
#   continuation contract; prose banners are secondary.)
#
# Intentional non-goals:
#
#   - No proximity-window / line-distance check between Skill tool calls
#     and their sentinel writes. Existing repo convention uses plain
#     grep-presence checks (test-design-structure.sh, test-anti-halt-banners.sh);
#     a multi-line window check would be fragile without adding real
#     assurance over what grep-presence plus lint-skill-invocations.py
#     already provide.
#
#   - No banner absence check. That is test-anti-halt-banners.sh's job —
#     this harness focuses on the split's mechanical gate contract, not
#     on banner policy across the full orchestrator set.
#
# Invoked via:  bash scripts/test-loop-improve-skill-continuation.sh
# Wired into:   make lint (via the test-loop-improve-skill-continuation
#               Makefile target).
#
# Edits to skills/loop-improve-skill/SKILL.md or
# skills/loop-improve-skill-iter/SKILL.md must keep this harness passing.
# When the contract evolves (e.g., a new halt-equivalent edge is
# introduced), update the literal assertions here in the same PR — the
# AGENTS.md canonical-source bullet documents this sync requirement.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

INNER="$REPO_ROOT/skills/loop-improve-skill-iter/SKILL.md"
OUTER="$REPO_ROOT/skills/loop-improve-skill/SKILL.md"

BANNER_SIGNATURE='**Anti-halt continuation reminder.**'

FAIL_COUNT=0
PASS_COUNT=0

fail() {
  echo "FAIL: $*" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
  echo "PASS: $*"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# Exit early if either SKILL.md is missing — every subsequent grep would
# spam redundant errors and bury the real diagnosis.
if [[ ! -f "$INNER" ]]; then
  echo "FAIL: inner SKILL.md not found at $INNER" >&2
  exit 1
fi
if [[ ! -f "$OUTER" ]]; then
  echo "FAIL: outer SKILL.md not found at $OUTER" >&2
  exit 1
fi

check_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "$needle" "$file"; then
    pass "$label"
  else
    fail "$label — missing literal: $needle"
  fi
}

check_count_exact() {
  local file="$1"
  local needle="$2"
  local expected="$3"
  local label="$4"
  local actual
  actual=$(grep -Fc -- "$needle" "$file" || true)
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (count=$actual)"
  else
    fail "$label — expected count $expected, got $actual for literal: $needle"
  fi
}

check_count_at_least() {
  local file="$1"
  local needle="$2"
  local min="$3"
  local label="$4"
  local actual
  actual=$(grep -Fc -- "$needle" "$file" || true)
  if [[ "$actual" -ge "$min" ]]; then
    pass "$label (count=$actual, min=$min)"
  else
    fail "$label — expected at least $min, got $actual for literal: $needle"
  fi
}

echo "--- Inner SKILL.md sentinel literals ---"
# Single-quoted literals below are intentional — we assert that the literal
# string "iter-${ITER}-..." (with the shell-style placeholder unexpanded) is
# present in the SKILL.md body. shellcheck SC2016 warns about unexpanded
# expressions in single quotes, which is exactly what we want here.
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3j.done'               "inner 3.j sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3jv.done'              "inner 3.j.v grade-parse sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3d-pre-detect.done'    "inner 3.d pre-rescue-detector sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3d-post-detect.done'   "inner 3.d post-rescue-detector sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3d-plan-post.done'     "inner 3.d plan-post sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3i.done'               "inner 3.i sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-done.sentinel'         "inner iteration-complete sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-infeasibility.md'      "inner infeasibility justification file literal"

echo ""
echo "--- Inner SKILL.md mechanical gate literals ---"
check_contains "$INNER" "printf 'done" "inner uses non-empty sentinel write (printf, not touch)"
check_contains "$INNER" "verify-skill-called.sh" "inner invokes verify-skill-called.sh (/im stdout-line gate)"
check_contains "$INNER" "parse-skill-judge-grade.sh" "inner invokes parse-skill-judge-grade.sh (Step 3.j.v)"
check_count_at_least "$INNER" "gh issue comment" 2 "inner posts gh comments (3.j judge output + 3.d plan)"

echo ""
echo "--- Inner SKILL.md per-substep breadcrumbs ---"
check_contains "$INNER" "🔶 3.j" "inner 3.j breadcrumb"
check_contains "$INNER" "🔶 3.j.v" "inner 3.j.v grade-parse breadcrumb"
check_contains "$INNER" "🔶 3.d" "inner 3.d breadcrumb"
check_contains "$INNER" "🔶 3.i" "inner 3.i breadcrumb"

echo ""
echo "--- Inner SKILL.md security boundary ---"
check_contains "$INNER" "/private/tmp/" "inner LOOP_TMPDIR prefix guard (/private/tmp/ literal)"

echo ""
echo "--- Inner SKILL.md grade-A termination contract literals ---"
check_contains "$INNER" "grade_a_achieved" "inner has grade_a_achieved ITER_STATUS literal"
check_contains "$INNER" "Non-A dimensions" "inner /design prompt enrichment literal (Non-A dimensions focus block)"
check_contains "$INNER" "grade-history.txt" "inner appends to grade-history.txt"

echo ""
echo "--- Outer SKILL.md mechanical gate literals ---"
check_contains "$OUTER" "verify-skill-called.sh --sentinel-file" "outer invokes verify-skill-called.sh --sentinel-file (iteration gate)"
check_contains "$OUTER" "/loop-improve-skill-iter" "outer delegates to /loop-improve-skill-iter"
check_contains "$OUTER" "cleanup-tmpdir.sh" "outer cleans up LOOP_TMPDIR"
check_contains "$OUTER" "max iterations (10) reached" "outer has max-iteration exit literal"
check_contains "$OUTER" "iteration sentinel missing" "outer has halt-detected exit literal"

echo ""
echo "--- Outer SKILL.md #247 enriched halt-diagnostic literals ---"
check_contains "$OUTER" "last-completed="                "outer emits last-completed= contract token (#247 ledger scan)"
check_contains "$OUTER" "halted at or before /skill-judge" "outer has LAST_COMPLETED=none halt-location clause (#247)"
check_contains "$OUTER" "halted at or before /design"      "outer has LAST_COMPLETED=3jv halt-location clause (#247)"
check_contains "$OUTER" "halted at or before /im"          "outer has LAST_COMPLETED=3d-plan-post halt-location clause (#247)"

echo ""
echo "--- Outer SKILL.md grade-A termination contract literals ---"
check_contains "$OUTER" "grade_a_achieved" "outer recognizes grade_a_achieved ITER_STATUS"
check_contains "$OUTER" "grade A achieved" "outer has grade-A EXIT_REASON literal"
check_contains "$OUTER" "parse-skill-judge-grade.sh" "outer invokes parse-skill-judge-grade.sh (Step 5a final-judge)"
check_contains "$OUTER" "final-judge.txt" "outer captures final-judge.txt (Step 5a)"
check_contains "$OUTER" "Infeasibility Justification" "outer close-out body has Infeasibility Justification section"
check_contains "$OUTER" "Grade History" "outer close-out body has Grade History section"
check_count_at_least "$OUTER" "gh issue comment" 1 "outer posts at least one gh comment (Step 5c close-out)"

echo ""
echo "--- Banner-density cap (both SKILL.md files) ---"
check_count_exact "$INNER" "$BANNER_SIGNATURE" 1 "inner has exactly one Anti-halt banner"
check_count_exact "$OUTER" "$BANNER_SIGNATURE" 1 "outer has exactly one Anti-halt banner"

echo ""
echo "=== SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
