#!/usr/bin/env bash
# test-anti-halt-banners.sh — Regression harness for the anti-halt
# continuation banner and per-call-site micro-reminder (closes #177).
#
# Asserts three contracts defined in
# skills/shared/subskill-invocation.md section "Anti-halt continuation
# reminder":
#
#   (A) The banner substring "**Anti-halt continuation reminder.**"
#       appears in each orchestrator SKILL.md.
#   (B) The same banner substring does NOT appear in any pure-delegator
#       SKILL.md — the rule explicitly exempts them.
#   (C) The micro-reminder substring "Continue after child returns"
#       (matches both standard and loop-internal variants) appears at
#       least once in each orchestrator SKILL.md.
#
# Invoked via:  bash scripts/test-anti-halt-banners.sh
# Wired into:   make lint (via the test-anti-halt Makefile target).
#
# The banner and micro-reminder substrings are fixed contract tokens.
# When editing the canonical wording in
# skills/shared/subskill-invocation.md, keep the substrings here in sync
# in the same PR.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

BANNER_SIGNATURE='**Anti-halt continuation reminder.**'
MICRO_SIGNATURE='Continue after child returns'

ORCHESTRATORS=(
  "skills/fix-issue/SKILL.md"
  "skills/implement/SKILL.md"
  "skills/review/SKILL.md"
  "skills/loop-review/SKILL.md"
)

DELEGATORS=(
  "skills/im/SKILL.md"
  "skills/imaq/SKILL.md"
  "skills/alias/SKILL.md"
  "skills/create-skill/SKILL.md"
)

FAIL_COUNT=0
PASS_COUNT=0

check_banner_present() {
  local rel="$1"
  local abs="$REPO_ROOT/$rel"
  if [[ ! -f "$abs" ]]; then
    echo "FAIL: $rel does not exist" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi
  if grep -Fq -- "$BANNER_SIGNATURE" "$abs"; then
    echo "PASS: $rel contains banner"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $rel is missing banner substring: $BANNER_SIGNATURE" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_banner_absent() {
  local rel="$1"
  local abs="$REPO_ROOT/$rel"
  if [[ ! -f "$abs" ]]; then
    echo "FAIL: $rel does not exist" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi
  if grep -Fq -- "$BANNER_SIGNATURE" "$abs"; then
    echo "FAIL: $rel contains banner substring but is a pure delegator (should be exempt)" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $rel is correctly banner-free (pure delegator)"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

check_micro_present() {
  local rel="$1"
  local abs="$REPO_ROOT/$rel"
  if [[ ! -f "$abs" ]]; then
    # Already reported by check_banner_present for this file; no duplicate.
    return
  fi
  if grep -Fq -- "$MICRO_SIGNATURE" "$abs"; then
    echo "PASS: $rel contains at least one micro-reminder"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $rel is missing micro-reminder substring: $MICRO_SIGNATURE" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "--- Orchestrator banner presence ---"
for rel in "${ORCHESTRATORS[@]}"; do
  check_banner_present "$rel"
done

echo ""
echo "--- Pure-delegator banner absence ---"
for rel in "${DELEGATORS[@]}"; do
  check_banner_absent "$rel"
done

echo ""
echo "--- Orchestrator micro-reminder presence ---"
for rel in "${ORCHESTRATORS[@]}"; do
  check_micro_present "$rel"
done

echo ""
echo "=== SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
