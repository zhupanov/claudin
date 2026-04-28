#!/usr/bin/env bash
# test-loop-review-driver.sh — structural regression harness for
# skills/loop-review/scripts/driver.sh. Companion to
# test-loop-review-skill-md.sh (which pins SKILL.md contract tokens).
#
# This is the Tier-1 structural test only. Tier-2 stub-shim integration
# tests using LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE are documented in driver.md
# and tracked as a focused follow-up — they require fixture stubs that
# emit canned partition output + canned per-slice /review output, which
# is more involved than the current PR's scope.
#
# Tier-1 assertions:
#   A) driver.sh exists, is executable, has set -euo pipefail.
#   B) Derives CLAUDE_PLUGIN_ROOT from script location with `cd ../../..`
#      pattern (three-up-from-script layout).
#   C) Has cleanup_on_exit trap on EXIT.
#   D) Has /tmp/+/private/tmp/ prefix guard on LOOP_TMPDIR.
#   E) Has `..` path-component guard on LOOP_TMPDIR.
#   F) Defines invoke_claude_p_freeform AND invoke_claude_p_skill helpers.
#   G) Both invoke helpers preserve FINDING_7/9/10 contracts:
#      - --plugin-dir "$CLAUDE_PLUGIN_ROOT" (FINDING_7)
#      - prompt-file on STDIN via < $prompt_file (FINDING_9)
#      - stderr to <out>.stderr sidecar via 2> $stderr_file (FINDING_10)
#   H) Has parse_slice_kv awk-scoped to lines AFTER `### slice-result`
#      (awk-scoped KV parse pattern).
#   I) Per-slice claude -p invocation uses --slice-file (file-based handoff,
#      bypasses argv shell-quoting) and NOT --slice <argv>.
#   J) References LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE for Tier-2 test override.
#
# Exit 0 on all-pass; exit 1 otherwise. Wired into make lint.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DRIVER_SH="$REPO_ROOT/skills/loop-review/scripts/driver.sh"

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

# --- Assertion B: CLAUDE_PLUGIN_ROOT derivation ---
if grep -qE 'cd "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)/\.\./\.\./\.\." && pwd -P' "$DRIVER_SH"; then
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

# --- Assertion D: /tmp/ prefix guard ---
# shellcheck disable=SC2016  # single quotes intentional — these are byte-literal contract tokens being grepped from driver.sh, not shell variables.
if grep -qE '/tmp/\*\s*\|\|\s*"\$LOOP_TMPDIR" == /private/tmp/\*' "$DRIVER_SH" \
   || grep -qF 'LOOP_TMPDIR == /tmp/* || "$LOOP_TMPDIR" == /private/tmp/*' "$DRIVER_SH"; then
  pass "D: driver.sh has /tmp/+/private/tmp/ prefix guard on LOOP_TMPDIR"
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

# --- Assertion F: invoke_claude_p_freeform + invoke_claude_p_skill defined ---
if grep -qE '^invoke_claude_p_freeform\(\)' "$DRIVER_SH"; then
  pass "F: driver.sh defines invoke_claude_p_freeform()"
else
  fail "F: driver.sh missing invoke_claude_p_freeform() definition"
fi
if grep -qE '^invoke_claude_p_skill\(\)' "$DRIVER_SH"; then
  pass "F: driver.sh defines invoke_claude_p_skill()"
else
  fail "F: driver.sh missing invoke_claude_p_skill() definition"
fi

# --- Assertion G: FINDING_7/9/10 contracts ---
# shellcheck disable=SC2016  # single quotes intentional — these are byte-literal contract tokens being grepped from driver.sh.
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

# --- Assertion H: parse_slice_kv awk-scoped to lines after ### slice-result ---
if grep -qF 'parse_slice_kv()' "$DRIVER_SH" \
   && grep -qF '/^### slice-result/' "$DRIVER_SH"; then
  pass "H: driver.sh has parse_slice_kv awk-scoped to '### slice-result' header"
else
  fail "H: driver.sh missing parse_slice_kv awk-scope to '### slice-result'"
fi

# --- Assertion I: per-slice invocation uses --slice-file (not --slice argv) ---
if grep -qF -- '--slice-file' "$DRIVER_SH"; then
  pass "I: driver.sh uses --slice-file (file-based handoff)"
else
  fail "I: driver.sh missing --slice-file usage"
fi
# Negative assertion: the actual /review invocation line in the per-slice loop
# MUST use --slice-file, not bare --slice <argv>. The bare---slice form would
# reintroduce the F2 argv shell-quoting hazard (verbal descriptions containing
# quotes/parens/&/$ would misparse). Match the printf line that builds the
# slash-command prompt and require it carries --slice-file, not --slice.
# Note: docs comments may mention "--slice" alone — only the printf line that
# actually constructs the /review invocation is checked here.
# shellcheck disable=SC2016  # single-quoted regex literals are intentional contract tokens.
if grep -qE "printf '/review --slice-file " "$DRIVER_SH"; then
  pass "I(neg): driver.sh /review invocation uses --slice-file (not bare --slice)"
else
  fail "I(neg): driver.sh /review invocation does not match 'printf /review --slice-file ...' — argv injection regression risk"
fi

# --- Assertion J: LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE referenced ---
if grep -qF 'LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE' "$DRIVER_SH"; then
  pass "J: driver.sh references LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE (Tier-2 test override)"
else
  fail "J: driver.sh missing LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE reference"
fi

echo "---"
echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
[[ "$FAIL_COUNT" -gt 0 ]] && exit 1
exit 0
