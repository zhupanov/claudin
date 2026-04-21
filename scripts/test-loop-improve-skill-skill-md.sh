#!/usr/bin/env bash
# test-loop-improve-skill-skill-md.sh — structural regression harness for
# skills/loop-improve-skill/SKILL.md (closes #291). Companion to
# scripts/test-loop-improve-skill-driver.sh (which pins driver.sh contract
# tokens); this harness pins the SKILL.md contract tokens introduced by the
# live-streaming pattern (#291): background Bash launch + Monitor attach,
# visible log-path emission, and filter-regex parity with driver.sh's three
# breadcrumb helpers.
#
# Assertions (each failure prints FAIL: … to stderr and increments FAIL_COUNT):
#   A) frontmatter `allowed-tools` line contains both `Bash` and `Monitor`
#      tokens (order-insensitive, whitespace tolerant).
#   B) SKILL.md body declares the env-overridable log-path default literal
#      `LOOP_DRIVER_LOG_FILE` and the `/tmp/` + `/private/tmp/` case-arm
#      validation (security boundary — must stay in parity with the driver's
#      LOOP_TMPDIR prefix guard).
#   C) SKILL.md body surfaces the log path to the user via at least one
#      `📄 Full driver log:` occurrence (pre-launch visible line) AND at
#      least one `📄 Full driver log (retained):` occurrence (completion
#      re-emit) — the two are the user-facing contract from #291.
#   D) SKILL.md body contains the background-Bash launch directive literal
#      `run_in_background: true` AND the Monitor persistence directive
#      literal `persistent: true` (both load-bearing per #291 design).
#   E) SKILL.md body contains the filter-regex byte-verbatim:
#      `tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'`
#      (inside a fenced code block — the issue's explicit acceptance
#      criterion, updated to the double-quoted-$LOG_FILE form by the
#      round-1 code-review fix for whitespace tolerance in the path).
#   F) Filter-regex parity with driver.sh breadcrumb helpers: for each of the
#      three alternatives in the filter regex (`✅`, `> \*\*🔶`, `\*\*⚠`),
#      driver.sh MUST contain a corresponding `printf` line that emits a
#      matching prefix — i.e., `breadcrumb_done` emits `✅`,
#      `breadcrumb_inprogress` emits `> **🔶`, `breadcrumb_warn` emits `**⚠`.
#      A silent drift in either file would break the live stream without
#      any CI signal; this assertion is the mechanical bridge between the
#      two files.
#
# Exit 0 on all-pass; exit 1 otherwise. Meant for `make lint`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILL_MD="$REPO_ROOT/skills/loop-improve-skill/SKILL.md"
DRIVER_SH="$REPO_ROOT/skills/loop-improve-skill/scripts/driver.sh"

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

if [[ ! -f "$SKILL_MD" ]]; then
  fail "$SKILL_MD does not exist"
  exit 1
fi
if [[ ! -f "$DRIVER_SH" ]]; then
  fail "$DRIVER_SH does not exist"
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

# --- Assertion B: LOOP_DRIVER_LOG_FILE env var + /tmp validation ----------

if ! grep -qF 'LOOP_DRIVER_LOG_FILE' "$SKILL_MD"; then
  fail "B: SKILL.md body does not reference LOOP_DRIVER_LOG_FILE env-overridable default"
else
  pass "B: SKILL.md references LOOP_DRIVER_LOG_FILE"
fi

if ! grep -qF '/tmp/*|/private/tmp/*' "$SKILL_MD"; then
  fail "B: SKILL.md body does not contain the '/tmp/*|/private/tmp/*' case-arm validation (security boundary)"
else
  pass "B: SKILL.md contains /tmp/+/private/tmp/ validation"
fi

# --- Assertion C: visible log-path emission (pre-launch + retained) -------

pre_count=$(grep -cE '^📄 Full driver log: ' "$SKILL_MD" || true)
# In the committed SKILL.md, the pre-launch literal appears as `📄 Full
# driver log: $LOG_FILE` inside a fenced code block. Accept matches of
# that form anywhere (the grep above requires line-start; relax by also
# accepting inside backticks or code fences):
if [[ "$pre_count" -lt 1 ]]; then
  pre_count=$(grep -cF '📄 Full driver log: ' "$SKILL_MD" || true)
fi
if [[ "$pre_count" -lt 1 ]]; then
  fail "C: SKILL.md body missing pre-launch '📄 Full driver log: <path>' visibility line"
else
  pass "C: SKILL.md has pre-launch log-path visibility line ($pre_count match(es))"
fi

retained_count=$(grep -cF '📄 Full driver log (retained):' "$SKILL_MD" || true)
if [[ "$retained_count" -lt 1 ]]; then
  fail "C: SKILL.md body missing completion '📄 Full driver log (retained): <path>' line"
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

# The filter literal — pinned exactly as the issue's acceptance criterion.
# $LOG_FILE is double-quoted to tolerate whitespace in user-supplied
# LOOP_DRIVER_LOG_FILE overrides (accepted code-review finding, #291).
# shellcheck disable=SC2016  # $LOG_FILE is intentionally literal — this is the byte-verbatim SKILL.md contract token, not a command substitution.
FILTER_LITERAL='tail -F "$LOG_FILE" | grep --line-buffered -E '"'"'^(✅|> \*\*🔶|\*\*⚠)'"'"''
if ! grep -qF -- "$FILTER_LITERAL" "$SKILL_MD"; then
  fail "E: SKILL.md body does not contain the exact filter literal:"
  fail "   $FILTER_LITERAL"
else
  pass "E: SKILL.md contains the byte-verbatim filter literal"
fi

# --- Assertion F: filter-regex parity with driver.sh breadcrumb helpers ----

# For each of the three filter alternatives, assert driver.sh has a printf
# line whose format string begins with the corresponding prefix.

# breadcrumb_done emits lines beginning with '✅ '
if grep -qE "printf '✅ " "$DRIVER_SH"; then
  pass "F: driver.sh emits '✅ ' prefix (breadcrumb_done — matches filter alternative 1)"
else
  fail "F: driver.sh has no 'printf \"✅ ...\"' line — filter alternative 1 (✅) has no matching emitter"
fi

# breadcrumb_inprogress emits lines beginning with '> **🔶 '
if grep -qE "printf '> \*\*🔶 " "$DRIVER_SH"; then
  pass "F: driver.sh emits '> **🔶 ' prefix (breadcrumb_inprogress — matches filter alternative 2)"
else
  fail "F: driver.sh has no 'printf \"> **🔶 ...\"' line — filter alternative 2 (> \\*\\*🔶) has no matching emitter"
fi

# breadcrumb_warn emits lines beginning with '**⚠ '
if grep -qE "printf '\*\*⚠ " "$DRIVER_SH"; then
  pass "F: driver.sh emits '**⚠ ' prefix (breadcrumb_warn — matches filter alternative 3)"
else
  fail "F: driver.sh has no 'printf \"**⚠ ...\"' line — filter alternative 3 (\\*\\*⚠) has no matching emitter"
fi

# --- Summary --------------------------------------------------------------

echo "---"
echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
