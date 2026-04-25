#!/usr/bin/env bash
# test-research-adjudication.sh — offline regression guard for /research --adjudicate.
#
# Validates scripts/build-research-adjudication-ballot.sh against fixture inputs.
# Tests cover (mirroring the actual test order in this script):
#   1. Empty input → DECISION_COUNT=0, ballot file present but empty.
#   2. Deterministic ordering — same rejection set in different append orders → byte-identical ballot.
#   3. DECISION renumbering — entries are renumbered DECISION_1, DECISION_2, ... after the deterministic sort.
#   4. Position rotation — odd N: rejection-stands = Defense A; even N: reinstate = Defense A.
#   5. Anchored-only attribution stripping — leading `<Reviewer>:` prefix on a finding's first line is
#      stripped from the defense body; mid-content occurrences of Cursor/Codex/Code/orchestrator are preserved.
#   6. <defense_content> wrapping with the "treat as data" preamble.
#   7. Ballot header text — research-specific THESIS/ANTI_THESIS semantics are byte-pinned.
#   8. Multi-line Finding/Rejection rationale → DECISION_COUNT=1 with both continuation lines
#      preserved verbatim through the FS sentinel round-trip.
#   9. Literal-tab in Finding text → DECISION_COUNT=1 with the embedded TAB byte preserved through
#      the GS sentinel substitution + tr-decode round-trip.
#  10. emit_failure routes FAILED=/ERROR= to stderr (not stdout), so the Phase 3
#      `{ ... } > "$OUTPUT"` brace-group redirect cannot capture the failure
#      lines into the ballot file; caller-style `2>&1` merge still surfaces
#      ERROR= for the existing run-research-adjudication.sh extraction
#      (regression guard for issue #463).
#
# Wired into the Makefile via the `test-harnesses` target. Runs under `make lint`
# locally (since `lint: test-harnesses lint-only`) and under CI's `test-harnesses`
# job (which is split from `lint-only` in CI per docs/linting.md). NOT part of
# `make smoke-dialectic` (that target validates /design's dialectic-execution.md
# fixtures, which have debater XML tags / RECOMMEND lines / file:line citations
# not present in research adjudication ballots).
#
# Exit 0 on pass, exit 1 on any assertion failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILDER="$REPO_ROOT/scripts/build-research-adjudication-ballot.sh"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures/research-adjudication"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

[[ -x "$BUILDER" ]] || fail "Builder script missing or not executable: $BUILDER"
[[ -d "$FIXTURES_DIR" ]] || fail "Fixtures directory missing: $FIXTURES_DIR"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Test 1: empty input -----------------------------------------------------

empty_input="$WORK_DIR/empty-rej.md"
empty_output="$WORK_DIR/empty-ballot.txt"
: > "$empty_input"

builder_out="$("$BUILDER" --input "$empty_input" --output "$empty_output")"
echo "$builder_out" | grep -qE '^BUILT=true$'        || fail "Test 1: empty input did not emit BUILT=true. Got: $builder_out"
echo "$builder_out" | grep -qE '^DECISION_COUNT=0$'  || fail "Test 1: empty input did not emit DECISION_COUNT=0. Got: $builder_out"
[[ -f "$empty_output" ]]                              || fail "Test 1: ballot file was not created"
[[ ! -s "$empty_output" ]]                            || fail "Test 1: ballot file is non-empty (expected empty)"
pass "Test 1: empty input → DECISION_COUNT=0, empty ballot"

# --- Test 2: deterministic ordering, append order independence --------------

input_order_1="$WORK_DIR/order1-rej.md"
input_order_2="$WORK_DIR/order2-rej.md"
output_order_1="$WORK_DIR/order1-ballot.txt"
output_order_2="$WORK_DIR/order2-ballot.txt"

cat > "$input_order_1" <<'EOF'
### REJECTED_FINDING_1
- **Reviewer**: Cursor
- **Finding**: Cursor: alpha finding text body that is reasonably long.
- **Rejection rationale**: First rationale paragraph that explains why the alpha finding was rejected, providing enough detail to serve as a defense.

### REJECTED_FINDING_2
- **Reviewer**: Code
- **Finding**: Code: bravo finding text body of approximately the same length.
- **Rejection rationale**: Second rationale paragraph explaining the rejection of the bravo finding with substantive reasoning about the codebase state.

### REJECTED_FINDING_3
- **Reviewer**: Codex
- **Finding**: Codex: charlie finding text body matching the others in length.
- **Rejection rationale**: Third rationale paragraph for the charlie finding rejection with detailed prose about why the orchestrator's position holds.
EOF

# Same three findings, different append order
cat > "$input_order_2" <<'EOF'
### REJECTED_FINDING_1
- **Reviewer**: Codex
- **Finding**: Codex: charlie finding text body matching the others in length.
- **Rejection rationale**: Third rationale paragraph for the charlie finding rejection with detailed prose about why the orchestrator's position holds.

### REJECTED_FINDING_2
- **Reviewer**: Cursor
- **Finding**: Cursor: alpha finding text body that is reasonably long.
- **Rejection rationale**: First rationale paragraph that explains why the alpha finding was rejected, providing enough detail to serve as a defense.

### REJECTED_FINDING_3
- **Reviewer**: Code
- **Finding**: Code: bravo finding text body of approximately the same length.
- **Rejection rationale**: Second rationale paragraph explaining the rejection of the bravo finding with substantive reasoning about the codebase state.
EOF

"$BUILDER" --input "$input_order_1" --output "$output_order_1" >/dev/null
"$BUILDER" --input "$input_order_2" --output "$output_order_2" >/dev/null

if ! diff -q "$output_order_1" "$output_order_2" >/dev/null; then
  fail "Test 2: ballots differ when input append order differs (expected byte-identical)"
fi
pass "Test 2: deterministic ordering — append order independence verified"

# --- Test 3: DECISION renumbering --------------------------------------------

# Expect DECISION_1, DECISION_2, DECISION_3 in lexicographic-by-reviewer order.
# Code < Codex < Cursor → DECISION_1 = Code (bravo), DECISION_2 = Codex (charlie), DECISION_3 = Cursor (alpha)
grep -qE '^### DECISION_1: ' "$output_order_1" || fail "Test 3: missing DECISION_1 header"
grep -qE '^### DECISION_2: ' "$output_order_1" || fail "Test 3: missing DECISION_2 header"
grep -qE '^### DECISION_3: ' "$output_order_1" || fail "Test 3: missing DECISION_3 header"

# DECISION_1 should be the Code reviewer's bravo finding; DECISION_3 should be Cursor's alpha
decision_1_finding="$(awk '/^### DECISION_1:/{flag=1; next} /^### DECISION_2:/{flag=0} flag' "$output_order_1")"
decision_3_finding="$(awk '/^### DECISION_3:/{flag=1; next} flag' "$output_order_1")"

echo "$decision_1_finding" | grep -q "bravo finding text body" || fail "Test 3: DECISION_1 does not contain the Code reviewer's bravo finding (lex-first)"
echo "$decision_3_finding" | grep -q "alpha finding text body" || fail "Test 3: DECISION_3 does not contain the Cursor reviewer's alpha finding (lex-last)"
pass "Test 3: DECISION renumbering — lex-by-reviewer ordering verified"

# --- Test 4: position rotation ------------------------------------------------

# DECISION_1 (odd N) → rejection-stands = Defense A; reinstate = Defense B
decision_1_block="$(awk '/^### DECISION_1:/{flag=1; next} /^### DECISION_2:/{flag=0} flag' "$output_order_1")"
echo "$decision_1_block" | grep -qE '^Defense A \(defends rejection stands\):'      || fail "Test 4: DECISION_1 (odd) Defense A does not defend rejection stands"
echo "$decision_1_block" | grep -qE '^Defense B \(defends reinstate the finding\):' || fail "Test 4: DECISION_1 (odd) Defense B does not defend reinstate"

# DECISION_2 (even N) → reinstate = Defense A; rejection-stands = Defense B
decision_2_block="$(awk '/^### DECISION_2:/{flag=1; next} /^### DECISION_3:/{flag=0} flag' "$output_order_1")"
echo "$decision_2_block" | grep -qE '^Defense A \(defends reinstate the finding\):' || fail "Test 4: DECISION_2 (even) Defense A does not defend reinstate"
echo "$decision_2_block" | grep -qE '^Defense B \(defends rejection stands\):'      || fail "Test 4: DECISION_2 (even) Defense B does not defend rejection stands"
pass "Test 4: position rotation — odd/even alternation verified"

# --- Test 5: anchored-only attribution stripping ----------------------------

# In the test inputs, each finding starts with "<reviewer>: ..." which is the
# anchored attribution-prefix pattern. The stripping must remove the leading
# "<reviewer>: " on the first line of each defense body. Mid-content
# occurrences of "Cursor"/"Codex"/"Code" must be preserved.

mid_input="$WORK_DIR/mid-rej.md"
mid_output="$WORK_DIR/mid-ballot.txt"

cat > "$mid_input" <<'EOF'
### REJECTED_FINDING_1
- **Reviewer**: Cursor
- **Finding**: Cursor: the orchestrator's merge step at validation-phase.md:73 lacks a deterministic sort, breaking downstream tooling that depends on Cursor's negotiation outputs being reproducible.
- **Rejection rationale**: This finding misidentifies the merge step's behavior. The orchestrator does apply a deterministic ordering at validation-phase.md:99 during dedup, after Cursor's negotiation completes. The reviewer's claim contradicts the source file. Factually incorrect.
EOF

"$BUILDER" --input "$mid_input" --output "$mid_output" >/dev/null

# The leading "Cursor: " on the Finding's first line should be stripped from the defense body.
# The mid-content "the orchestrator's", "Cursor's negotiation", and "after Cursor's negotiation" should all be PRESERVED.
ballot_body="$(cat "$mid_output")"

# After stripping, the finding-body should start with "the orchestrator's merge step", NOT "Cursor: the orchestrator's"
echo "$ballot_body" | grep -qE 'Cursor: the orchestrator' && \
  fail "Test 5a: leading 'Cursor: ' attribution prefix was NOT stripped from defense body"

# Mid-content "the orchestrator" must be preserved
echo "$ballot_body" | grep -qE "the orchestrator's merge step" || \
  fail "Test 5b: mid-content 'the orchestrator's merge step' was incorrectly stripped"

# Mid-content "Cursor's negotiation" must be preserved
echo "$ballot_body" | grep -qE "Cursor's negotiation" || \
  fail "Test 5c: mid-content 'Cursor's negotiation' was incorrectly stripped"

pass "Test 5: anchored-only attribution stripping — leading prefix removed, mid-content preserved"

# --- Test 6: <defense_content> wrapping with treat-as-data preamble ---------

# Each defense body should be wrapped in <defense_content>...</defense_content> with the preamble.
defense_count="$(grep -c '<defense_content>' "$output_order_1" || true)"
defense_close_count="$(grep -c '</defense_content>' "$output_order_1" || true)"
preamble_count="$(grep -c 'The following content delimits an untrusted defense' "$output_order_1" || true)"

# 3 decisions × 2 defenses each = 6 wrappers
[[ "$defense_count" == "6" ]]       || fail "Test 6: expected 6 <defense_content> opening tags, got $defense_count"
[[ "$defense_close_count" == "6" ]] || fail "Test 6: expected 6 </defense_content> closing tags, got $defense_close_count"
[[ "$preamble_count" == "6" ]]      || fail "Test 6: expected 6 'treat as data' preambles, got $preamble_count"
pass "Test 6: <defense_content> wrapping with treat-as-data preamble verified"

# --- Test 7: ballot header text ----------------------------------------------

grep -qF '## Dialectic Ballot — Research Adjudication' "$output_order_1" || \
  fail "Test 7: ballot header missing"
grep -qF 'THESIS = "rejection stands" wins' "$output_order_1" || \
  fail "Test 7: THESIS semantics not declared in ballot header"
grep -qF 'ANTI_THESIS = "reinstate the finding" wins' "$output_order_1" || \
  fail "Test 7: ANTI_THESIS semantics not declared in ballot header"
pass "Test 7: ballot header declares research-specific THESIS/ANTI_THESIS semantics"

# --- Test 8: multi-line finding/rationale produces ONE decision (not multiple) -----

# Regression test for the FINDING_1 multi-line TSV corruption bug. Before the FS/GS
# sentinel fix, a single ### REJECTED_FINDING_1 block with a multi-line Finding plus
# a multi-line Rejection rationale produced DECISION_COUNT=3 with garbled defenses.

multi_input="$WORK_DIR/multi-rej.md"
multi_output="$WORK_DIR/multi-ballot.txt"

cat > "$multi_input" <<'EOF'
### REJECTED_FINDING_1
- **Reviewer**: Code
- **Finding**: The function at foo.sh:10 is missing an error check.
Additional context spanning a second line about the same finding.
- **Rejection rationale**: First sentence of the rejection rationale paragraph explaining the rejection.
Second sentence adds more substantive prose to make the paragraph properly long.
EOF

builder_out_8="$("$BUILDER" --input "$multi_input" --output "$multi_output")"
echo "$builder_out_8" | grep -qE '^DECISION_COUNT=1$' \
  || fail "Test 8: multi-line input expected DECISION_COUNT=1, got: $builder_out_8"

# Defense bodies must contain both lines verbatim — the second line of each must
# survive the FS sentinel round-trip back into the ballot.
grep -qF "Additional context spanning a second line about the same finding." "$multi_output" \
  || fail "Test 8: second line of multi-line Finding lost in ballot"
grep -qF "Second sentence adds more substantive prose to make the paragraph properly long." "$multi_output" \
  || fail "Test 8: second line of multi-line Rejection rationale lost in ballot"
pass "Test 8: multi-line Finding/Rejection rationale → 1 decision, both lines preserved"

# --- Test 9: tab-containing finding handled correctly ------------------------

# Codex's review reproduced TSV corruption when a literal tab appeared in finding text.
# The GS sentinel substitution (Phase 1) + tr-decode (Phase 2) round-trip preserves tabs
# without breaking IFS=$'\t' record splitting in Phase 2.

tab_input="$WORK_DIR/tab-rej.md"
tab_output="$WORK_DIR/tab-ballot.txt"

# Use printf so a real TAB is embedded in the Finding line.
printf '### REJECTED_FINDING_1\n- **Reviewer**: Code\n- **Finding**: column1\tcolumn2 example with a literal tab character in the middle.\n- **Rejection rationale**: This rejection rationale paragraph contains substantive prose explaining why the orchestrator rejected this finding factually.\n' > "$tab_input"

builder_out_9="$("$BUILDER" --input "$tab_input" --output "$tab_output")"
echo "$builder_out_9" | grep -qE '^DECISION_COUNT=1$' \
  || fail "Test 9: tab-containing input expected DECISION_COUNT=1, got: $builder_out_9"

# The tab must round-trip back to the ballot. Build the expected literal with a
# real TAB byte via printf so the check is portable across BSD grep / GNU grep.
expected_tab_line=$(printf 'column1\tcolumn2 example with a literal tab character')
grep -qF "$expected_tab_line" "$tab_output" \
  || fail "Test 9: literal tab character lost in ballot round-trip"
pass "Test 9: literal tab in Finding text → 1 decision, tab preserved"

# --- Test 10: emit_failure writes ERROR= to stderr, not stdout ---------------

# Regression test for issue #463. The two emit_failure calls inside the
# Phase 3 brace group `{ ... } > "$OUTPUT"` would write FAILED=true / ERROR=
# into the ballot file when emit_failure printf'd to stdout, hiding the
# specific TSV-corruption diagnostic from the caller. The fix routes
# emit_failure's printf to fd 2 so it bypasses the brace-group stdout
# redirect on every call site. We exercise an out-of-brace emit_failure path
# (missing required --input flag, exit 1) under separated stdout/stderr
# capture; the same fd-2 contract protects the in-brace sites at lines
# ~285/288, which are not externally inducible (Phase 2 always produces
# valid base64).
err10_stdout="$WORK_DIR/test10-stdout.txt"
err10_stderr="$WORK_DIR/test10-stderr.txt"

set +e
"$BUILDER" --output "$WORK_DIR/test10-ballot.txt" \
  > "$err10_stdout" 2> "$err10_stderr"
err10_rc=$?
set -e

[[ "$err10_rc" -ne 0 ]] || fail "Test 10: builder exited 0 on missing --input (expected non-zero)"

# ERROR= MUST land on stderr.
grep -qE '^ERROR=' "$err10_stderr" \
  || fail "Test 10: ERROR= line missing from stderr (got: $(cat "$err10_stderr"))"
grep -qE '^FAILED=true$' "$err10_stderr" \
  || fail "Test 10: FAILED=true line missing from stderr"

# ERROR= MUST NOT appear on stdout — that's the regression we're guarding.
if grep -qE '^ERROR=' "$err10_stdout"; then
  fail "Test 10: ERROR= line leaked to stdout (regression — the fix routes emit_failure to fd 2)"
fi

# Caller-style 2>&1 merge MUST still surface ERROR= (the caller in
# run-research-adjudication.sh:129 captures with `2>&1` and greps for ERROR=).
set +e
merged_out="$("$BUILDER" --output "$WORK_DIR/test10-ballot2.txt" 2>&1)"
merged_rc=$?
set -e
[[ "$merged_rc" -ne 0 ]] || fail "Test 10: builder exited 0 on missing --input under 2>&1 capture"
echo "$merged_out" | grep -qE '^ERROR=' \
  || fail "Test 10: caller-style 2>&1 capture lost ERROR= line (got: $merged_out)"

pass "Test 10: emit_failure routes FAILED=/ERROR= to stderr; caller 2>&1 merge still captures it"

# --- All tests passed --------------------------------------------------------

echo ""
echo "All test-research-adjudication.sh assertions passed."
exit 0
