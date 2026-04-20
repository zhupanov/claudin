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
#         iter-${ITER}-3d-pre-detect.done
#         iter-${ITER}-3d-post-detect.done
#         iter-${ITER}-3d-plan-post.done
#         iter-${ITER}-3i.done
#         iter-${ITER}-done.sentinel
#     - At least one printf 'done\n' > ... literal (non-empty sentinel write —
#       NOT touch, which would make verify-skill-called.sh --sentinel-file
#       return VERIFIED=false empty_file).
#     - A verify-skill-called.sh invocation (for /im's stdout-line gate).
#     - gh issue comment (appears at least twice: 3.j + 3.d-plan-post).
#     - Each substep breadcrumb: 🔶 3.j, 🔶 3.d, 🔶 3.i, 🔶 4.
#     - The LOOP_TMPDIR path-prefix guard literal /private/tmp/ (the
#       security-boundary check from FINDING_8).
#
#   Outer skills/loop-improve-skill/SKILL.md MUST contain:
#     - verify-skill-called.sh --sentinel-file  (the iteration gate).
#     - /loop-improve-skill-iter               (the delegated child name).
#     - cleanup-tmpdir.sh                      (Step 6 cleanup).
#     - max iterations (10) reached           (the normal-completion exit literal — FINDING_7).
#     - iteration sentinel missing             (the halt-detected exit literal).
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
check_contains "$INNER" 'iter-${ITER}-3d-pre-detect.done'    "inner 3.d pre-rescue-detector sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3d-post-detect.done'   "inner 3.d post-rescue-detector sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3d-plan-post.done'     "inner 3.d plan-post sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-3i.done'               "inner 3.i sentinel literal"
# shellcheck disable=SC2016
check_contains "$INNER" 'iter-${ITER}-done.sentinel'         "inner iteration-complete sentinel literal"

echo ""
echo "--- Inner SKILL.md mechanical gate literals ---"
check_contains "$INNER" "printf 'done" "inner uses non-empty sentinel write (printf, not touch)"
check_contains "$INNER" "verify-skill-called.sh" "inner invokes verify-skill-called.sh (/im stdout-line gate)"
check_count_at_least "$INNER" "gh issue comment" 2 "inner posts gh comments (3.j judge output + 3.d plan)"

echo ""
echo "--- Inner SKILL.md per-substep breadcrumbs ---"
check_contains "$INNER" "🔶 3.j" "inner 3.j breadcrumb"
check_contains "$INNER" "🔶 3.d" "inner 3.d breadcrumb"
check_contains "$INNER" "🔶 3.i" "inner 3.i breadcrumb"

echo ""
echo "--- Inner SKILL.md security boundary ---"
check_contains "$INNER" "/private/tmp/" "inner LOOP_TMPDIR prefix guard (/private/tmp/ literal)"

echo ""
echo "--- Outer SKILL.md mechanical gate literals ---"
check_contains "$OUTER" "verify-skill-called.sh --sentinel-file" "outer invokes verify-skill-called.sh --sentinel-file (iteration gate)"
check_contains "$OUTER" "/loop-improve-skill-iter" "outer delegates to /loop-improve-skill-iter"
check_contains "$OUTER" "cleanup-tmpdir.sh" "outer cleans up LOOP_TMPDIR"
check_contains "$OUTER" "max iterations (10) reached" "outer has max-iteration exit literal"
check_contains "$OUTER" "iteration sentinel missing" "outer has halt-detected exit literal"

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
