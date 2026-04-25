#!/usr/bin/env bash
# test-eval-research-baseline-flag.sh — Regression harness for the
# `--baseline` flag handling in scripts/eval-research.sh (issue #441).
#
# Pins the post-#441 behavior:
#   1. `--baseline` not set → no PREVIEW MODE banner on stdout.
#   2. `--baseline <valid-ref>` → exit 0; PREVIEW MODE banner on stdout;
#      cached baseline JSON exists at $WORK_DIR/baseline-rows.json.
#   3. `--baseline <bogus-ref>` → exit 2; ERROR with the ref + git stderr
#      tail on stderr; no cache file left behind.
#
# Runs offline by PATH-stubbing `claude` and `jq` so the harness exercises
# the baseline block without needing either real binary on PATH (CI's
# test-harnesses job only installs PyYAML — see plan-review FINDING_2).
# `--id nonexistent-id-zzz` ensures the eval loop iterates zero entries
# so `claude -p` is never actually invoked.
#
# Invoked via:  bash scripts/test-eval-research-baseline-flag.sh
# Wired into:   standalone Makefile target `test-eval-research-baseline-flag`.
#               NOT a `test-harnesses` prerequisite — eval-research is opt-in
#               operator instrumentation by repo contract (Makefile:148,
#               docs/linting.md, scripts/eval-research.md).

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/eval-research.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: eval-research.sh not found at $SCRIPT" >&2
  exit 1
fi

FAIL_COUNT=0
PASS_COUNT=0

pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# -----------------------------------------------------------------------
# Set up PATH stubs for `claude` and `jq` so the test runs offline.
# -----------------------------------------------------------------------

fixture_tmp="$(mktemp -d)"
trap 'rm -rf "$fixture_tmp"' EXIT

stub_dir="$fixture_tmp/stubs"
mkdir -p "$stub_dir"

# claude stub: must satisfy `require_tool claude` (presence on PATH). It is
# never invoked at runtime because --id nonexistent-id-zzz skips the loop.
cat > "$stub_dir/claude" <<'CLAUDE_EOF'
#!/usr/bin/env bash
# Test stub — eval-research.sh's --baseline regression harness.
# The real binary is never needed because --id <nonexistent> skips the loop.
exit 0
CLAUDE_EOF
chmod +x "$stub_dir/claude"

# jq stub: must satisfy `require_tool jq` AND succeed on validate_baseline_json's
# `jq -e '.version and .scale and (.entries | type == "array")' <file>` call.
# Returning exit 0 unconditionally is safe because we control the test inputs
# (the committed eval-baseline.json, which is a schema-valid stub).
cat > "$stub_dir/jq" <<'JQ_EOF'
#!/usr/bin/env bash
# Test stub — eval-research.sh's --baseline regression harness.
# Always succeeds; the only call we exercise is validate_baseline_json's
# `-e` schema check, which only cares about exit code.
exit 0
JQ_EOF
chmod +x "$stub_dir/jq"

# Run all eval-research.sh invocations under the stubbed PATH.
run_eval() {
  local work_dir="$1"
  shift
  PATH="$stub_dir:$PATH" bash "$SCRIPT" --work-dir "$work_dir" --id nonexistent-id-zzz "$@"
}

# -----------------------------------------------------------------------
# Sub-1: no --baseline → no PREVIEW MODE banner; exit 0.
# -----------------------------------------------------------------------

echo "--- Sub-1: no --baseline flag ---"
sub1_work="$fixture_tmp/sub1"
mkdir -p "$sub1_work"
sub1_stdout="$fixture_tmp/sub1.stdout"
sub1_stderr="$fixture_tmp/sub1.stderr"
sub1_rc=0
run_eval "$sub1_work" >"$sub1_stdout" 2>"$sub1_stderr" || sub1_rc=$?

if [[ "$sub1_rc" == "0" ]]; then
  pass "Sub-1: exit 0 with no --baseline"
else
  fail "Sub-1: expected exit 0, got $sub1_rc (stderr: $(tail -n 5 "$sub1_stderr"))"
fi
if grep -q 'PREVIEW MODE' "$sub1_stdout"; then
  fail "Sub-1: PREVIEW MODE banner unexpectedly present on stdout (must be gated on --baseline)"
else
  pass "Sub-1: no PREVIEW MODE banner on stdout"
fi
if [[ -e "$sub1_work/baseline-rows.json" ]]; then
  fail "Sub-1: baseline-rows.json unexpectedly present (must not be created without --baseline)"
else
  pass "Sub-1: no cache file created"
fi

# -----------------------------------------------------------------------
# Sub-2: --baseline HEAD → PREVIEW MODE banner; cache exists; exit 0.
# Uses HEAD (the committed eval-baseline.json schema-only stub) so the
# git -C "$CLAUDE_PLUGIN_ROOT" show invocation resolves successfully.
# -----------------------------------------------------------------------

echo "--- Sub-2: --baseline HEAD (valid ref) ---"
sub2_work="$fixture_tmp/sub2"
mkdir -p "$sub2_work"
sub2_stdout="$fixture_tmp/sub2.stdout"
sub2_stderr="$fixture_tmp/sub2.stderr"
sub2_rc=0
run_eval "$sub2_work" --baseline HEAD >"$sub2_stdout" 2>"$sub2_stderr" || sub2_rc=$?

if [[ "$sub2_rc" == "0" ]]; then
  pass "Sub-2: exit 0 with valid --baseline ref"
else
  fail "Sub-2: expected exit 0, got $sub2_rc (stderr: $(tail -n 5 "$sub2_stderr"))"
fi
if grep -q 'PREVIEW MODE' "$sub2_stdout"; then
  pass "Sub-2: PREVIEW MODE banner present on stdout"
else
  fail "Sub-2: PREVIEW MODE banner missing from stdout (full stdout: $(cat "$sub2_stdout"))"
fi
if [[ -s "$sub2_work/baseline-rows.json" ]]; then
  pass "Sub-2: baseline cache file present and non-empty at $sub2_work/baseline-rows.json"
else
  fail "Sub-2: baseline cache file missing or empty at $sub2_work/baseline-rows.json"
fi

# -----------------------------------------------------------------------
# Sub-3: --baseline <bogus-ref> → exit 2; ERROR with ref + git diagnostic
# tail on stderr; no cache file.
# -----------------------------------------------------------------------

echo "--- Sub-3: --baseline definitely-not-a-real-ref-xyz (bad ref) ---"
sub3_work="$fixture_tmp/sub3"
mkdir -p "$sub3_work"
sub3_stdout="$fixture_tmp/sub3.stdout"
sub3_stderr="$fixture_tmp/sub3.stderr"
sub3_rc=0
run_eval "$sub3_work" --baseline definitely-not-a-real-ref-xyz >"$sub3_stdout" 2>"$sub3_stderr" || sub3_rc=$?

if [[ "$sub3_rc" == "2" ]]; then
  pass "Sub-3: exit 2 on unresolvable ref"
else
  fail "Sub-3: expected exit 2, got $sub3_rc (stderr: $(tail -n 10 "$sub3_stderr"))"
fi
if grep -q 'definitely-not-a-real-ref-xyz' "$sub3_stderr"; then
  pass "Sub-3: error message names the unresolvable ref"
else
  fail "Sub-3: error message does NOT name the unresolvable ref (full stderr: $(cat "$sub3_stderr"))"
fi
if grep -q 'git show stderr' "$sub3_stderr"; then
  pass "Sub-3: git stderr tail surfaced for diagnosability (FINDING_7)"
else
  fail "Sub-3: git stderr tail NOT surfaced (FINDING_7 regression — operators can't distinguish ref-missing / file-missing / non-git-checkout)"
fi
if [[ -e "$sub3_work/baseline-rows.json" ]]; then
  fail "Sub-3: baseline-rows.json present after bad-ref failure (must be removed via rm -f)"
else
  pass "Sub-3: no cache file left behind on bad-ref failure"
fi

# -----------------------------------------------------------------------
# Sub-4: trailing --baseline with no value → exit 2; clear error on stderr.
# Pre-fix behavior: `shift 2` failed under `set -e` because only one
# positional remained, exiting with code 1 — which collides with the
# documented schema-validation exit code, making a malformed flag
# indistinguishable from a real schema failure to wrappers checking $?
# (issue #477). The fix adds a `require_value` arity check before each
# `shift 2` in the parser loop so missing values yield exit 2 with a
# recognizable stderr message. The helper is applied uniformly to all
# seven value-taking flags in eval-research.sh; this Sub-4 spot-checks
# `--baseline` since that is the case the issue reported.
# -----------------------------------------------------------------------

echo "--- Sub-4: trailing --baseline with no value ---"
sub4_stdout="$fixture_tmp/sub4.stdout"
sub4_stderr="$fixture_tmp/sub4.stderr"
sub4_rc=0
PATH="$stub_dir:$PATH" bash "$SCRIPT" --id nonexistent-id-zzz --baseline \
  >"$sub4_stdout" 2>"$sub4_stderr" || sub4_rc=$?

if [[ "$sub4_rc" == "2" ]]; then
  pass "Sub-4: exit 2 on trailing --baseline with no value"
else
  fail "Sub-4: expected exit 2, got $sub4_rc (stderr: $(tail -n 5 "$sub4_stderr"))"
fi
if grep -q -- '--baseline requires a value' "$sub4_stderr"; then
  pass "Sub-4: stderr names --baseline as the flag missing a value"
else
  fail "Sub-4: stderr does not name --baseline (full stderr: $(cat "$sub4_stderr"))"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------

echo ""
echo "=== SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
