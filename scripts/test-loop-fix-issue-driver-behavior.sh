#!/usr/bin/env bash
# test-loop-fix-issue-driver-behavior.sh — Tier-2 NDJSON behavior fixture for
# skills/loop-fix-issue/scripts/driver.sh. Companion to the Tier-1 structural
# harness at scripts/test-loop-fix-issue-driver.sh and to the SKILL.md harness
# at scripts/test-loop-fix-issue-skill-md.sh.
#
# Purpose: structural assertions cannot catch a regression where the new
# `--output-format stream-json --verbose` flags are typed but the driver's
# grep semantics actually break against the captured NDJSON. This fixture
# exercises the live driver against canned NDJSON via
# `LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE`, covering both the success and the
# no-eligible-issues paths plus the sentinel-mismatch defensive fallback.
#
# Three scenarios:
#   1) success — stub emits NDJSON containing `find & lock — found and locked`
#      on iteration 1, then NDJSON containing `0: find & lock — no approved
#      issues found` on iteration 2. Expected: driver clean-exits after
#      iteration 2 with termination reason `no eligible issues
#      (clean exhaustion)`. Confirms that the NDJSON-format sentinel match
#      AND the multi-iteration loop both work.
#   2) no-eligible — stub emits the no-approved-issues NDJSON immediately.
#      Expected: driver clean-exits on iteration 1 with the same termination
#      reason. Confirms the Step 0 exit-1 sub-sentinel grep works on NDJSON.
#   3) no-sentinel — stub emits NDJSON containing arbitrary text without any
#      Step 0 literal. Expected: driver halts with termination reason
#      `Step 0 unknown short-circuit (sentinel mismatch)` and retains
#      LOOP_TMPDIR. Confirms the defensive-fallback path fires correctly,
#      NOT a false-success match against the broader NDJSON envelope.
#
# Mocking strategy:
# - claude is mocked via LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE pointing at a
#   stub script. The stub uses a counter file in $TEST_TMPDIR to vary output
#   across iterations.
# - The driver's CLAUDE_PLUGIN_ROOT is overridden to point at a test-local
#   stub plugin tree that contains a stub session-setup.sh (creates a fresh
#   tmpdir, emits SESSION_TMPDIR=, exits 0 — bypasses the on-main-branch and
#   git-fetch preflight) and a stub cleanup-tmpdir.sh (rm -rf the arg). The
#   driver's CLAUDE_PLUGIN_ROOT-uses are exactly these two scripts plus the
#   `--plugin-dir` argv passed to the claude-stub (which ignores it).
# - gh is mocked via PATH manipulation. The driver's preflight calls
#   `command -v gh` and `gh auth status`; the stub gh in PATH returns success.
#
# Exit 0 on all-pass; exit 1 otherwise. Wired into make lint.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DRIVER_SH="$REPO_ROOT/skills/loop-fix-issue/scripts/driver.sh"

if [[ ! -x "$DRIVER_SH" ]]; then
  echo "FAIL: $DRIVER_SH does not exist or is not executable" >&2
  exit 1
fi

FAIL_COUNT=0
PASS_COUNT=0

fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }

# Per-test-run tmpdir under canonical /tmp; trap cleans up unless we mark it
# preserved for inspection.
TEST_TMPDIR="$(mktemp -d "/tmp/test-loop-fix-issue-driver-behavior.XXXXXX")"
PRESERVE_TMPDIR="false"

# shellcheck disable=SC2317  # invoked indirectly via `trap ... EXIT` below; shellcheck's static analyzer cannot see that path
cleanup_test_tmpdir() {
  if [[ "$PRESERVE_TMPDIR" == "true" ]]; then
    echo "Retained TEST_TMPDIR=$TEST_TMPDIR for inspection"
  else
    rm -rf "$TEST_TMPDIR"
  fi
}
trap cleanup_test_tmpdir EXIT

# Verify python3 is available (used by the stub for JSON-escaping).
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not available; required by claude-stub.sh JSON-escape helper" >&2
  exit 1
fi

# ===========================================================================
# Stub plugin tree at $TEST_TMPDIR/plugin/
# ===========================================================================
mkdir -p "$TEST_TMPDIR/plugin/scripts"

# Stub session-setup.sh: creates a fresh per-driver-run tmpdir under
# canonical /tmp, emits SESSION_TMPDIR=<path>, exits 0. Bypasses the on-main-
# branch and git-fetch preflight that the production session-setup.sh
# enforces (those are not relevant to the behavior contract under test).
cat > "$TEST_TMPDIR/plugin/scripts/session-setup.sh" <<'SETUPEOF'
#!/usr/bin/env bash
# Stub session-setup.sh for the loop-fix-issue behavior fixture.
set -euo pipefail
PREFIX="claude-loop-fix-issue"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --skip-*|--check-*) shift ;;
    --caller-env|--write-health) shift 2 ;;
    *) shift ;;
  esac
done
SESSION_TMPDIR="$(mktemp -d "/tmp/${PREFIX}.XXXXXX")"
echo "SESSION_TMPDIR=$SESSION_TMPDIR"
exit 0
SETUPEOF
chmod +x "$TEST_TMPDIR/plugin/scripts/session-setup.sh"

# Stub cleanup-tmpdir.sh: deletes the directory passed via --dir.
cat > "$TEST_TMPDIR/plugin/scripts/cleanup-tmpdir.sh" <<'CLEANUPEOF'
#!/usr/bin/env bash
set -euo pipefail
DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "$DIR" && -d "$DIR" ]]; then
  case "$DIR" in
    /tmp/*|/private/tmp/*) rm -rf "$DIR" ;;
    *) echo "stub cleanup-tmpdir.sh: refusing to rm outside /tmp: $DIR" >&2; exit 1 ;;
  esac
fi
exit 0
CLEANUPEOF
chmod +x "$TEST_TMPDIR/plugin/scripts/cleanup-tmpdir.sh"

# ===========================================================================
# Stub claude script — emits canned NDJSON per FIXTURE_SCENARIO.
# ===========================================================================
cat > "$TEST_TMPDIR/claude-stub.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Stub claude shim — emits canned NDJSON for the loop-fix-issue behavior
# fixture. Reads (and discards) stdin (the /fix-issue prompt); writes one
# JSON object per line; exits 0.
set -euo pipefail

FIXTURE_SCENARIO="${FIXTURE_SCENARIO:-success}"
COUNTER_FILE="${FIXTURE_COUNTER_FILE:-/tmp/fixture-counter-default}"

# Drain stdin (the prompt); we don't act on it.
cat >/dev/null

# Increment + persist iteration counter.
if [[ -f "$COUNTER_FILE" ]]; then
  COUNTER=$(cat "$COUNTER_FILE")
  COUNTER=$((COUNTER + 1))
else
  COUNTER=1
fi
echo "$COUNTER" > "$COUNTER_FILE"

emit_init() {
  printf '%s\n' '{"type":"system","subtype":"init","model":"stub","session_id":"test-fixture"}'
}
emit_text() {
  # ensure_ascii=False mirrors Anthropic's actual stream-json encoder behavior
  # — em-dash, ampersand, and other UTF-8 content stay verbatim in the JSON
  # string field (NOT escaped to \uXXXX). The driver's literal-substring grep
  # depends on this; defaulting to ensure_ascii=True would produce
  # `find & lock — found and locked` and silently break the test in a
  # way that does NOT reflect production behavior.
  local text="$1"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(printf '%s' "$text" | python3 -c 'import json, sys; sys.stdout.write(json.dumps(sys.stdin.read(), ensure_ascii=False))')"
}
emit_result() {
  printf '%s\n' '{"type":"result","subtype":"success"}'
}

case "$FIXTURE_SCENARIO" in
  success)
    if [[ "$COUNTER" -eq 1 ]]; then
      emit_init
      emit_text '> **🔶 0: find & lock — found and locked #1: stub-test-issue**'
      emit_text '✅ 0: find & lock — issue #1 locked and titled [IN PROGRESS] (5s)'
      emit_text '✅ 8: cleanup — fix-issue complete!'
      emit_result
    else
      emit_init
      emit_text '✅ 0: find & lock — no approved issues found (5s)'
      emit_text '✅ 8: cleanup — fix-issue complete!'
      emit_result
    fi
    ;;
  no-eligible)
    emit_init
    emit_text '✅ 0: find & lock — no approved issues found (5s)'
    emit_text '✅ 8: cleanup — fix-issue complete!'
    emit_result
    ;;
  no-sentinel)
    emit_init
    emit_text 'some unrelated text without any Step 0 literal'
    emit_text '✅ 8: cleanup — fix-issue complete!'
    emit_result
    ;;
  *)
    echo "claude-stub: unknown FIXTURE_SCENARIO=$FIXTURE_SCENARIO" >&2
    exit 1
    ;;
esac

exit 0
STUBEOF
chmod +x "$TEST_TMPDIR/claude-stub.sh"

# ===========================================================================
# Stub gh in PATH for preflight.
# ===========================================================================
mkdir -p "$TEST_TMPDIR/bin"
cat > "$TEST_TMPDIR/bin/gh" <<'GHSTUBEOF'
#!/usr/bin/env bash
# gh stub — minimal: covers the preflight `gh auth status` invocation.
case "$1" in
  auth) exit 0 ;;
  *) exit 0 ;;
esac
GHSTUBEOF
chmod +x "$TEST_TMPDIR/bin/gh"

# ===========================================================================
# Helper: run the driver under one fixture scenario, capture stdout, return
# the captured driver output for assertion.
# ===========================================================================
run_driver_with_scenario() {
  local scenario="$1"
  local max_iter="$2"
  local out_file="$3"
  local counter_file="$TEST_TMPDIR/counter-$scenario"

  : > "$counter_file"  # reset

  local saved_path="$PATH"
  export PATH="$TEST_TMPDIR/bin:$PATH"
  export LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE="$TEST_TMPDIR/claude-stub.sh"
  export FIXTURE_SCENARIO="$scenario"
  export FIXTURE_COUNTER_FILE="$counter_file"
  export CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/plugin"

  set +e
  bash "$DRIVER_SH" --max-iterations "$max_iter" >"$out_file" 2>&1
  set -e

  unset LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE FIXTURE_SCENARIO FIXTURE_COUNTER_FILE CLAUDE_PLUGIN_ROOT
  export PATH="$saved_path"
}

# ===========================================================================
# Scenario 1: success — sentinel detected on iter 1, no-eligible on iter 2.
# ===========================================================================
SUCCESS_OUT="$TEST_TMPDIR/success-out.txt"
run_driver_with_scenario success 5 "$SUCCESS_OUT"

if grep -qF 'iteration 1 — /fix-issue completed an issue.' "$SUCCESS_OUT"; then
  pass "1: success — driver detected sentinel on iter 1 (continued to iter 2)"
else
  fail "1: success — driver did not report 'iteration 1 — /fix-issue completed an issue.' (sentinel match failed against NDJSON?)"
  echo "--- driver output ---" >&2
  cat "$SUCCESS_OUT" >&2
  echo "---" >&2
fi

if grep -qF 'no eligible issues (clean exhaustion)' "$SUCCESS_OUT"; then
  pass "1: success — driver clean-exited after iter 2 (Step 0 exit-1 sub-sentinel matched on NDJSON)"
else
  fail "1: success — driver did not clean-exit; expected 'no eligible issues (clean exhaustion)' termination reason"
  echo "--- driver output ---" >&2
  cat "$SUCCESS_OUT" >&2
  echo "---" >&2
fi

# ===========================================================================
# Scenario 2: no-eligible — clean exit on first iteration.
# ===========================================================================
NOELIG_OUT="$TEST_TMPDIR/no-eligible-out.txt"
run_driver_with_scenario no-eligible 3 "$NOELIG_OUT"

if grep -qF 'reported no work to do. Loop complete.' "$NOELIG_OUT"; then
  pass "2: no-eligible — driver reported clean exhaustion on iter 1"
else
  fail "2: no-eligible — driver did not report 'reported no work to do. Loop complete.'"
  echo "--- driver output ---" >&2
  cat "$NOELIG_OUT" >&2
  echo "---" >&2
fi

if grep -qF 'no eligible issues (clean exhaustion)' "$NOELIG_OUT"; then
  pass "2: no-eligible — driver clean-exited with expected termination reason"
else
  fail "2: no-eligible — driver did not record expected termination reason"
fi

# ===========================================================================
# Scenario 3: no-sentinel — defensive fallback halts loop, retains LOOP_TMPDIR.
# ===========================================================================
NOSENT_OUT="$TEST_TMPDIR/no-sentinel-out.txt"
run_driver_with_scenario no-sentinel 3 "$NOSENT_OUT"

if grep -qF 'no recognized Step 0 literal' "$NOSENT_OUT"; then
  pass "3: no-sentinel — driver hit defensive-fallback breadcrumb (correctly classified NDJSON without Step 0 literal as sentinel mismatch)"
else
  fail "3: no-sentinel — driver did not report 'no recognized Step 0 literal' fallback"
  echo "--- driver output ---" >&2
  cat "$NOSENT_OUT" >&2
  echo "---" >&2
fi

if grep -qF 'Step 0 unknown short-circuit (sentinel mismatch)' "$NOSENT_OUT"; then
  pass "3: no-sentinel — driver recorded expected termination reason"
else
  fail "3: no-sentinel — driver did not record expected termination reason"
fi

# Verify retained LOOP_TMPDIR breadcrumb.
if grep -qF 'retained working directory:' "$NOSENT_OUT"; then
  pass "3: no-sentinel — driver retained LOOP_TMPDIR (LOOP_PRESERVE_TMPDIR=true on sentinel-mismatch path)"
else
  fail "3: no-sentinel — driver did not emit 'retained working directory:' breadcrumb"
fi

echo "---"
echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  PRESERVE_TMPDIR="true"
  exit 1
fi
exit 0
