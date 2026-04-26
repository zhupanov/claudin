#!/usr/bin/env bash
# test-loop-fix-issue-skill-md.sh — structural regression harness for
# skills/loop-fix-issue/SKILL.md. Companion to scripts/test-loop-fix-issue-driver.sh
# (which pins driver.sh contract tokens). Mirrors test-loop-review-skill-md.sh
# byte-for-byte where applicable since /loop-fix-issue uses the same
# bash-driver + Bash-background + Monitor-attach topology as /loop-review;
# the only meaningful divergence is the env-overridable log-path name
# (LOOP_FIX_ISSUE_DRIVER_LOG_FILE rather than LOOP_DRIVER_LOG_FILE).
#
# Assertions:
#   A) frontmatter `allowed-tools` line contains both `Bash` and `Monitor` tokens.
#   B) SKILL.md body declares LOOP_FIX_ISSUE_DRIVER_LOG_FILE env-overridable
#      default AND the /tmp/+/private/tmp/ case-arm validation (security boundary).
#   C) SKILL.md body surfaces the log path: at least one '📄 Full driver log:'
#      pre-launch line AND at least one '📄 Full driver log (retained):'
#      completion line.
#   D) SKILL.md body contains 'run_in_background: true' AND 'persistent: true'.
#   E) Filter-regex byte-verbatim:
#      tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'
#   F) Filter-regex parity with driver.sh breadcrumb helpers (✅, > **🔶, **⚠).
#
# Exit 0 on all-pass; exit 1 otherwise. Wired into make lint via
# test-loop-fix-issue-skill-md target.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILL_MD="$REPO_ROOT/skills/loop-fix-issue/SKILL.md"
DRIVER_SH="$REPO_ROOT/skills/loop-fix-issue/scripts/driver.sh"

FAIL_COUNT=0
PASS_COUNT=0

fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }

if [[ ! -f "$SKILL_MD" ]]; then
  fail "$SKILL_MD does not exist"
  exit 1
fi
if [[ ! -f "$DRIVER_SH" ]]; then
  fail "$DRIVER_SH does not exist"
  exit 1
fi

# --- Assertion A: allowed-tools contains both Bash and Monitor ---
allowed_line=$(grep -E '^allowed-tools:' "$SKILL_MD" | head -1 || true)
if [[ -z "$allowed_line" ]]; then
  fail "A: SKILL.md has no 'allowed-tools:' line"
else
  if ! grep -qE '\bBash\b' <<<"$allowed_line"; then
    fail "A: allowed-tools missing 'Bash': $allowed_line"
  else
    pass "A: allowed-tools contains Bash"
  fi
  if ! grep -qE '\bMonitor\b' <<<"$allowed_line"; then
    fail "A: allowed-tools missing 'Monitor': $allowed_line"
  else
    pass "A: allowed-tools contains Monitor"
  fi
fi

# --- Assertion B: LOOP_FIX_ISSUE_DRIVER_LOG_FILE + /tmp validation ---
if ! grep -qF 'LOOP_FIX_ISSUE_DRIVER_LOG_FILE' "$SKILL_MD"; then
  fail "B: SKILL.md missing LOOP_FIX_ISSUE_DRIVER_LOG_FILE env-overridable default"
else
  pass "B: SKILL.md references LOOP_FIX_ISSUE_DRIVER_LOG_FILE"
fi
if ! grep -qF '/tmp/*|/private/tmp/*' "$SKILL_MD"; then
  fail "B: SKILL.md missing '/tmp/*|/private/tmp/*' case-arm validation"
else
  pass "B: SKILL.md contains /tmp/+/private/tmp/ validation"
fi

# --- Assertion C: log-path visibility ---
if ! grep -qF '📄 Full driver log: ' "$SKILL_MD"; then
  fail "C: SKILL.md missing pre-launch '📄 Full driver log: <path>' line"
else
  pass "C: SKILL.md has pre-launch log-path visibility line"
fi
if ! grep -qF '📄 Full driver log (retained):' "$SKILL_MD"; then
  fail "C: SKILL.md missing completion '📄 Full driver log (retained): <path>' line"
else
  pass "C: SKILL.md has completion retained-log-path line"
fi

# --- Assertion D: background + persistent directives ---
if ! grep -qF 'run_in_background: true' "$SKILL_MD"; then
  fail "D: SKILL.md missing 'run_in_background: true'"
else
  pass "D: SKILL.md contains run_in_background: true"
fi
if ! grep -qF 'persistent: true' "$SKILL_MD"; then
  fail "D: SKILL.md missing 'persistent: true'"
else
  pass "D: SKILL.md contains persistent: true"
fi

# --- Assertion E: filter regex byte-verbatim ---
# shellcheck disable=SC2016
FILTER_LITERAL='tail -F "$LOG_FILE" | grep --line-buffered -E '"'"'^(✅|> \*\*🔶|\*\*⚠)'"'"''
if ! grep -qF -- "$FILTER_LITERAL" "$SKILL_MD"; then
  fail "E: SKILL.md missing exact filter literal: $FILTER_LITERAL"
else
  pass "E: SKILL.md contains byte-verbatim filter literal"
fi

# --- Assertion F: filter-regex parity with driver.sh breadcrumb helpers ---
if grep -qE "printf '✅ " "$DRIVER_SH"; then
  pass "F: driver.sh emits '✅ ' prefix (breadcrumb_done)"
else
  fail "F: driver.sh has no breadcrumb_done printf line"
fi
if grep -qE "printf '> \*\*🔶 " "$DRIVER_SH"; then
  pass "F: driver.sh emits '> **🔶 ' prefix (breadcrumb_inprogress)"
else
  fail "F: driver.sh has no breadcrumb_inprogress printf line"
fi
if grep -qE "printf '\*\*⚠ " "$DRIVER_SH"; then
  pass "F: driver.sh emits '**⚠ ' prefix (breadcrumb_warn)"
else
  fail "F: driver.sh has no breadcrumb_warn printf line"
fi

echo "---"
echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
[[ "$FAIL_COUNT" -gt 0 ]] && exit 1
exit 0
