#!/usr/bin/env bash
# test-loop-fix-issue-driver.sh — structural regression harness for
# skills/loop-fix-issue/scripts/driver.sh. Companion to
# test-loop-fix-issue-skill-md.sh (which pins SKILL.md contract tokens).
#
# This is the Tier-1 structural test only. Tier-2 stub-shim integration
# tests using LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE are documented in
# driver.md as future work — they require fixture stubs that emit canned
# /fix-issue stdout, which is more involved than the current PR's scope.
#
# Tier-1 assertions:
#   A) driver.sh exists, is executable, has set -euo pipefail.
#   B) Derives CLAUDE_PLUGIN_ROOT from script location with `cd ../../..`
#      pattern (three-up-from-script layout). loop-fix-issue wraps the
#      derivation in an `if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]` guard, so
#      this assertion uses fixed-string match on the literal substring
#      rather than the case-arm regex shape used by test-loop-review-driver.sh.
#   C) Has cleanup_on_exit trap on EXIT.
#   D) Has /tmp/+/private/tmp/ prefix guard on LOOP_TMPDIR. loop-fix-issue's
#      driver.sh uses `if ! [[ ... == /tmp/* || ... ]]` (line 212), NOT a
#      case-arm with pipe separator. Fixed-string match on the if-form
#      substring rather than the case-arm regex from the loop-review precedent.
#   E) Has `..` path-component guard on LOOP_TMPDIR.
#   F) Defines invoke_claude_p_skill helper. (loop-fix-issue defines only
#      this one helper — invoke_claude_p_freeform is loop-review-specific
#      because partition+slice topology is loop-review-only.)
#   G) invoke_claude_p_skill preserves FINDING_7/9/10 contracts:
#      - --plugin-dir "$CLAUDE_PLUGIN_ROOT" (FINDING_7)
#      - prompt-file on STDIN via < $prompt_file (FINDING_9)
#      - stderr to <out>.stderr sidecar via 2> $stderr_file (FINDING_10)
#   H) SETUP_SENTINEL is assigned the literal `find & lock — found and locked`
#      on a single line. Anchored on the executable assignment line, not the
#      header comments where the same prose appears (driver.sh:27, :231).
#   I) All four Step-0 sub-sentinel literals appear, each anchored with
#      the `0: find & lock —` step prefix:
#         (1) `0: find & lock — no approved issues found`
#         (2) `0: find & lock — error:`
#         (3) `0: find & lock — lock failed`
#         (4) defensive fallback: `no recognized Step 0 literal`
#      The fourth check uses a unique substring from the breadcrumb_warn
#      body (driver.sh:292) to disambiguate from the surrounding comments.
#   J) Exactly four `LOOP_PRESERVE_TMPDIR="true"` assignments are present,
#      matching the four documented abnormal-exit paths (subprocess error,
#      Step 0 error, lock failed, sentinel mismatch). Pairs with the
#      structural assertion that the clean "no approved issues" path
#      relies on the default `LOOP_PRESERVE_TMPDIR="false"` and never
#      assigns true on its breadcrumb_done branch.
#   K) References LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE for Tier-2 test override.
#   L) Per-iteration prompt construction uses `printf '/fix-issue%s\n'`
#      (anchored on the printf line, NOT on the bare `/fix-issue` token
#      which appears extensively in comments) and writes to
#      `fix-issue-prompt.txt`.
#
# Exit 0 on all-pass; exit 1 otherwise. Wired into make lint.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DRIVER_SH="$REPO_ROOT/skills/loop-fix-issue/scripts/driver.sh"

FAIL_COUNT=0
PASS_COUNT=0

fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }

# --- Assertion A: existence + executability + set -euo pipefail ---
if [[ ! -f "$DRIVER_SH" ]]; then
  fail "A: $DRIVER_SH does not exist"
  exit 1
fi
if [[ ! -x "$DRIVER_SH" ]]; then
  fail "A: $DRIVER_SH is not executable"
else
  pass "A: driver.sh is executable"
fi
if grep -qE '^set -euo pipefail' "$DRIVER_SH"; then
  pass "A: driver.sh has 'set -euo pipefail'"
else
  fail "A: driver.sh missing 'set -euo pipefail'"
fi

# --- Assertion B: CLAUDE_PLUGIN_ROOT derivation (fixed-string, tolerates if-guard) ---
# shellcheck disable=SC2016  # single quotes intentional — byte-literal contract token.
if grep -qF 'cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P' "$DRIVER_SH"; then
  pass "B: driver.sh derives CLAUDE_PLUGIN_ROOT via three-up-from-script pattern"
else
  fail "B: driver.sh missing CLAUDE_PLUGIN_ROOT derivation pattern (cd .../../..)"
fi

# --- Assertion C: cleanup_on_exit trap ---
if grep -qE 'trap cleanup_on_exit EXIT' "$DRIVER_SH"; then
  pass "C: driver.sh has 'trap cleanup_on_exit EXIT'"
else
  fail "C: driver.sh missing 'trap cleanup_on_exit EXIT'"
fi

# --- Assertion D: /tmp/+/private/tmp/ prefix guard (if [[ ]] form) ---
# shellcheck disable=SC2016  # single quotes intentional — byte-literal contract token.
if grep -qF 'LOOP_TMPDIR" == /tmp/* || "$LOOP_TMPDIR" == /private/tmp/*' "$DRIVER_SH"; then
  pass "D: driver.sh has /tmp/+/private/tmp/ prefix guard on LOOP_TMPDIR (if [[ ]] form)"
else
  fail "D: driver.sh missing /tmp/+/private/tmp/ prefix guard on LOOP_TMPDIR"
fi

# --- Assertion E: '..' path-component guard ---
# shellcheck disable=SC2016
if grep -qF 'case "$LOOP_TMPDIR" in' "$DRIVER_SH" \
   && grep -qE '\*/\.\.\|\*/\.\./\*' "$DRIVER_SH"; then
  pass "E: driver.sh has '..' path-component guard on LOOP_TMPDIR"
else
  fail "E: driver.sh missing '..' path-component guard"
fi

# --- Assertion F: invoke_claude_p_skill defined ---
if grep -qE '^invoke_claude_p_skill\(\)' "$DRIVER_SH"; then
  pass "F: driver.sh defines invoke_claude_p_skill()"
else
  fail "F: driver.sh missing invoke_claude_p_skill() definition"
fi

# --- Assertion G: FINDING_7/9/10 contracts ---
# shellcheck disable=SC2016  # single quotes intentional — byte-literal contract tokens.
if grep -qF -- '--plugin-dir "$CLAUDE_PLUGIN_ROOT"' "$DRIVER_SH"; then
  pass "G: driver.sh uses --plugin-dir \"\$CLAUDE_PLUGIN_ROOT\" (FINDING_7)"
else
  fail "G: driver.sh missing --plugin-dir \"\$CLAUDE_PLUGIN_ROOT\" (FINDING_7)"
fi
# G9: STDIN delivery via < $prompt_file
# shellcheck disable=SC2016
if grep -qE '< "\$prompt_file"' "$DRIVER_SH"; then
  pass "G: driver.sh uses STDIN delivery via < \"\$prompt_file\" (FINDING_9)"
else
  fail "G: driver.sh missing STDIN delivery (FINDING_9)"
fi
# G10: stderr sidecar via 2> $stderr_file
# shellcheck disable=SC2016
if grep -qE '2> "\$stderr_file"' "$DRIVER_SH"; then
  pass "G: driver.sh uses stderr sidecar via 2> \"\$stderr_file\" (FINDING_10)"
else
  fail "G: driver.sh missing stderr sidecar (FINDING_10)"
fi

# --- Assertion H: SETUP_SENTINEL live assignment line (anchors on the
# executable assignment, not the header comments where the same prose
# appears at driver.sh:27 and :231). ---
# shellcheck disable=SC2016
if grep -qE "^SETUP_SENTINEL='find & lock — found and locked'" "$DRIVER_SH"; then
  pass "H: driver.sh has live SETUP_SENTINEL='find & lock — found and locked' assignment"
else
  fail "H: driver.sh missing live SETUP_SENTINEL assignment line (only comments contain the substring?)"
fi

# --- Assertion I: four Step-0 sub-sentinels (each anchored with the
# `0: find & lock —` step-prefix; defensive fallback uses a unique
# substring from the breadcrumb_warn body at driver.sh:292). ---
if grep -qF '0: find & lock — no approved issues found' "$DRIVER_SH"; then
  pass "I: driver.sh has 'no approved issues found' sub-sentinel"
else
  fail "I: driver.sh missing 'no approved issues found' sub-sentinel"
fi
if grep -qF '0: find & lock — error:' "$DRIVER_SH"; then
  pass "I: driver.sh has 'error:' sub-sentinel"
else
  fail "I: driver.sh missing 'error:' sub-sentinel"
fi
if grep -qF '0: find & lock — lock failed' "$DRIVER_SH"; then
  pass "I: driver.sh has 'lock failed' sub-sentinel"
else
  fail "I: driver.sh missing 'lock failed' sub-sentinel"
fi
# Defensive fallback: pin the unique substring from the breadcrumb_warn body.
if grep -qF 'no recognized Step 0 literal' "$DRIVER_SH"; then
  pass "I: driver.sh has defensive-fallback breadcrumb (no recognized Step 0 literal)"
else
  fail "I: driver.sh missing defensive-fallback breadcrumb"
fi

# --- Assertion J: exactly four LOOP_PRESERVE_TMPDIR="true" assignments,
# matching the four documented abnormal-exit paths (subprocess error,
# Step 0 error, lock failed, sentinel mismatch). The clean "no approved
# issues" path relies on the default LOOP_PRESERVE_TMPDIR="false" and
# does NOT assign true on its breadcrumb_done branch. ---
preserve_count=$(grep -cE '^[[:space:]]+LOOP_PRESERVE_TMPDIR="true"' "$DRIVER_SH")
if [[ "$preserve_count" -eq 4 ]]; then
  pass "J: driver.sh has exactly 4 LOOP_PRESERVE_TMPDIR=\"true\" assignments (4 abnormal-exit paths)"
else
  fail "J: driver.sh has $preserve_count LOOP_PRESERVE_TMPDIR=\"true\" assignments (expected 4: subprocess error, Step 0 error, lock failed, sentinel mismatch)"
fi
# Also confirm the default false initialization remains.
# shellcheck disable=SC2016
if grep -qE '^LOOP_PRESERVE_TMPDIR="false"' "$DRIVER_SH"; then
  pass "J: driver.sh has default LOOP_PRESERVE_TMPDIR=\"false\" initialization"
else
  fail "J: driver.sh missing default LOOP_PRESERVE_TMPDIR=\"false\" initialization"
fi

# --- Assertion K: LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE referenced ---
if grep -qF 'LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE' "$DRIVER_SH"; then
  pass "K: driver.sh references LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE (Tier-2 test override)"
else
  fail "K: driver.sh missing LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE reference"
fi

# --- Assertion L: per-iteration prompt construction. Anchored on the
# `printf '/fix-issue%s\n'` live code at driver.sh:247, NOT on the bare
# `/fix-issue` token (which appears extensively in driver.sh comments at
# lines 3, 5, 7, 22, 44, etc.). Also confirm the prompt file path. ---
# shellcheck disable=SC2016  # single-quoted regex literal is intentional.
if grep -qF "printf '/fix-issue%s" "$DRIVER_SH"; then
  pass "L: driver.sh constructs /fix-issue prompt via printf '/fix-issue%%s...' (live prompt construction line)"
else
  fail "L: driver.sh /fix-issue prompt construction not anchored on the printf line — argv injection / token-drift regression risk"
fi
if grep -qF 'fix-issue-prompt.txt' "$DRIVER_SH"; then
  pass "L: driver.sh writes prompt to fix-issue-prompt.txt"
else
  fail "L: driver.sh missing fix-issue-prompt.txt prompt-file path"
fi

echo "---"
echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
[[ "$FAIL_COUNT" -gt 0 ]] && exit 1
exit 0
