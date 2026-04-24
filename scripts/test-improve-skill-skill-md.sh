#!/usr/bin/env bash
# test-improve-skill-skill-md.sh — Structural regression harness for
# skills/improve-skill/SKILL.md. Companion to test-improve-skill-iteration.sh
# (which pins iteration.sh contract tokens); this harness pins the SKILL.md
# contract tokens introduced by the live-streaming pattern (background Bash
# launch + Monitor attach + filter regex parity with iteration.sh breadcrumb
# helpers). Structurally mirrors test-loop-improve-skill-skill-md.sh — the
# SKILL.md contract is byte-close to /loop-improve-skill's.
#
# Assertions:
#   A) frontmatter `allowed-tools` line contains both `Bash` and `Monitor`
#      tokens (order-insensitive, whitespace tolerant).
#   B) SKILL.md body declares the env-overridable log-path default literal
#      `IMPROVE_SKILL_LOG_FILE` and the `/tmp/` + `/private/tmp/` case-arm
#      validation (security boundary).
#   C) SKILL.md body surfaces the log path to the user via a pre-launch
#      `📄 Full iteration log:` line AND a completion
#      `📄 Full iteration log (retained):` line.
#   D) SKILL.md body contains the background-Bash launch directive literal
#      `run_in_background: true` AND the Monitor persistence directive
#      literal `persistent: true`.
#   E) SKILL.md body contains the filter-regex byte-verbatim:
#      `tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'`
#   F) Filter-regex parity with iteration.sh breadcrumb helpers: for each
#      of the three alternatives in the filter regex (`✅`, `> \*\*🔶`,
#      `\*\*⚠`), iteration.sh MUST contain a corresponding printf line
#      that emits a matching prefix.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILL_MD="$REPO_ROOT/skills/improve-skill/SKILL.md"
KERNEL_SH="$REPO_ROOT/skills/improve-skill/scripts/iteration.sh"

FAIL_COUNT=0
PASS_COUNT=0

fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }

if [[ ! -f "$SKILL_MD" ]]; then
  fail "$SKILL_MD does not exist"
  exit 1
fi
if [[ ! -f "$KERNEL_SH" ]]; then
  fail "$KERNEL_SH does not exist"
  exit 1
fi

# --- Assertion A: allowed-tools contains both Bash and Monitor -------------

allowed_line=$(grep -E '^allowed-tools:' "$SKILL_MD" | head -1 || true)
if [[ -z "$allowed_line" ]]; then
  fail "A: SKILL.md has no 'allowed-tools:' line in frontmatter"
else
  if ! grep -qE '\bBash\b' <<<"$allowed_line"; then
    fail "A: allowed-tools line does not contain 'Bash': $allowed_line"
  else
    pass "A: allowed-tools contains Bash"
  fi
  if ! grep -qE '\bMonitor\b' <<<"$allowed_line"; then
    fail "A: allowed-tools line does not contain 'Monitor': $allowed_line"
  else
    pass "A: allowed-tools contains Monitor"
  fi
fi

# --- Assertion B: IMPROVE_SKILL_LOG_FILE env var + /tmp validation --------

if ! grep -qF 'IMPROVE_SKILL_LOG_FILE' "$SKILL_MD"; then
  fail "B: SKILL.md body does not reference IMPROVE_SKILL_LOG_FILE env-overridable default"
else
  pass "B: SKILL.md references IMPROVE_SKILL_LOG_FILE"
fi

if ! grep -qF '/tmp/*|/private/tmp/*' "$SKILL_MD"; then
  fail "B: SKILL.md body does not contain the '/tmp/*|/private/tmp/*' case-arm validation"
else
  pass "B: SKILL.md contains /tmp/+/private/tmp/ validation"
fi

# --- Assertion C: visible log-path emission (pre-launch + retained) -------

pre_count=$(grep -cF '📄 Full iteration log: ' "$SKILL_MD" || true)
if [[ "$pre_count" -lt 1 ]]; then
  fail "C: SKILL.md body missing pre-launch '📄 Full iteration log: <path>' visibility line"
else
  pass "C: SKILL.md has pre-launch log-path visibility line ($pre_count match(es))"
fi

retained_count=$(grep -cF '📄 Full iteration log (retained):' "$SKILL_MD" || true)
if [[ "$retained_count" -lt 1 ]]; then
  fail "C: SKILL.md body missing completion '📄 Full iteration log (retained): <path>' line"
else
  pass "C: SKILL.md has completion retained-log-path line ($retained_count match(es))"
fi

# --- Assertion D: background Bash + persistent Monitor directives ---------

if ! grep -qF 'run_in_background: true' "$SKILL_MD"; then
  fail "D: SKILL.md body does not contain 'run_in_background: true' (background Bash launch directive)"
else
  pass "D: SKILL.md contains run_in_background: true"
fi

if ! grep -qF 'persistent: true' "$SKILL_MD"; then
  fail "D: SKILL.md body does not contain 'persistent: true' (Monitor persistence directive)"
else
  pass "D: SKILL.md contains persistent: true"
fi

# --- Assertion E: filter regex byte-verbatim in SKILL.md ------------------

# shellcheck disable=SC2016  # $LOG_FILE is intentionally literal — this is the byte-verbatim SKILL.md contract token, not a command substitution.
FILTER_LITERAL='tail -F "$LOG_FILE" | grep --line-buffered -E '"'"'^(✅|> \*\*🔶|\*\*⚠)'"'"''
if ! grep -qF -- "$FILTER_LITERAL" "$SKILL_MD"; then
  fail "E: SKILL.md body does not contain the exact filter literal:"
  fail "   $FILTER_LITERAL"
else
  pass "E: SKILL.md contains the byte-verbatim filter literal"
fi

# --- Assertion F: filter-regex parity with iteration.sh breadcrumb helpers ----

# breadcrumb_done emits lines beginning with '✅ '
if grep -qE "printf '✅ " "$KERNEL_SH"; then
  pass "F: iteration.sh emits '✅ ' prefix (breadcrumb_done — matches filter alternative 1)"
else
  fail "F: iteration.sh has no 'printf \"✅ ...\"' line — filter alternative 1 (✅) has no matching emitter"
fi

# breadcrumb_inprogress emits lines beginning with '> **🔶 '
if grep -qE "printf '> \*\*🔶 " "$KERNEL_SH"; then
  pass "F: iteration.sh emits '> **🔶 ' prefix (breadcrumb_inprogress — matches filter alternative 2)"
else
  fail "F: iteration.sh has no 'printf \"> **🔶 ...\"' line — filter alternative 2 (> \\*\\*🔶) has no matching emitter"
fi

# breadcrumb_warn emits lines beginning with '**⚠ '
if grep -qE "printf '\*\*⚠ " "$KERNEL_SH"; then
  pass "F: iteration.sh emits '**⚠ ' prefix (breadcrumb_warn — matches filter alternative 3)"
else
  fail "F: iteration.sh has no 'printf \"**⚠ ...\"' line — filter alternative 3 (\\*\\*⚠) has no matching emitter"
fi

# --- Summary --------------------------------------------------------------

echo "---"
echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
