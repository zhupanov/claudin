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
#  11. Deep-mode reviewer name stripping (issue #461) — anchored leading prefix `Code-Sec:` /
#      `Code-Arch:` and anchored trailing suffix ` (Code-Sec)` / ` — Code-Arch` are stripped from
#      defense bodies; mid-content occurrences are preserved. Code-Sec and Code-Arch are the
#      deep-mode reviewer attributions introduced by /research --scale=deep.
#  12. Mixed complete + incomplete blocks → fail-closed exit 2 with
#      ERROR=REJECTED_FINDING_<N> is incomplete sentinel (issue #462). Asserts
#      no partial 2-decision ballot is emitted from a 3-block input where one
#      block is incomplete.
#  13. Lone incomplete block → fail-closed exit 2 with the same sentinel.
#  14. Whitespace-only Finding body → fail-closed exit 2 (FINDING_7 shadow-trim
#      check verified).
#  15. Coordinator surfaces `incomplete-input:` ERROR prefix on malformed
#      REJECTED_FINDING input — narrow string guard at run-research-adjudication.sh
#      pattern-matches the builder's sentinel and prepends `incomplete-input: `
#      so operators can distinguish malformed input from generic builder
#      failure (issue #462 dialectic resolution DECISION_2).
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
# capture; the same fd-2 contract protects the in-brace `base64 -d` failure
# sites, which are not externally inducible (Phase 2 always produces valid
# base64).
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

# --- Test 11: deep-mode reviewer name stripping (Code-Sec / Code-Arch) ------

# Regression test for issue #461. /research --scale=deep introduces two extra
# Claude Code Reviewer subagent attributions: Code-Sec (security lane) and
# Code-Arch (architecture lane). The attribution scrubber must strip these at
# anchored prefix/suffix positions and preserve them mid-content. Without this
# coverage, a deep-mode reviewer's rejected finding would carry its
# "Code-Sec: " / "Code-Arch: " attribution into <defense_content>, breaking
# the anonymous Defense A/B guarantee.

deep_input="$WORK_DIR/deep-rej.md"
deep_output="$WORK_DIR/deep-ballot.txt"

# Two deep-mode rejections plus mid-content tokens to verify preservation.
# The Finding line carries an anchored leading "Code-Sec: " / "Code-Arch: ";
# the Rejection rationale's last line carries an anchored trailing suffix
# (one in parentheses, one with em-dash) to exercise the suffix regex.
cat > "$deep_input" <<'EOF'
### REJECTED_FINDING_1
- **Reviewer**: Code-Sec
- **Finding**: Code-Sec: the documented retry policy at validation-phase.md:142 omits the rate-limit error code path that production traffic actually surfaces under burst load.
- **Rejection rationale**: The retry policy does cover the rate-limit case via the generic transient-error branch at validation-phase.md:151. Code-Sec misread the contract — the orchestrator routes rate-limit responses through the same backoff loop. (Code-Sec)

### REJECTED_FINDING_2
- **Reviewer**: Code-Arch
- **Finding**: Code-Arch: the new helper at scripts/foo.sh:42 mixes orchestration responsibility with serialization concerns and should be split into two separate scripts following the existing layering convention.
- **Rejection rationale**: The helper's two responsibilities are tightly coupled by a shared invariant the existing layering does not address; splitting would force the invariant into both halves. The Code-Arch checklist anticipates this exception under "shared invariant supersedes layering". — Code-Arch
EOF

builder_out_11="$("$BUILDER" --input "$deep_input" --output "$deep_output")"
echo "$builder_out_11" | grep -qE '^DECISION_COUNT=2$' \
  || fail "Test 11: deep-mode input expected DECISION_COUNT=2, got: $builder_out_11"

deep_body="$(cat "$deep_output")"

# (a) Anchored prefix Code-Sec: / Code-Arch: stripped from defense first line.
echo "$deep_body" | grep -qE 'Code-Sec: the documented retry policy' && \
  fail "Test 11a: leading 'Code-Sec: ' attribution prefix was NOT stripped from defense body"
echo "$deep_body" | grep -qE 'Code-Arch: the new helper' && \
  fail "Test 11a: leading 'Code-Arch: ' attribution prefix was NOT stripped from defense body"

# After stripping, the original body content must survive verbatim.
echo "$deep_body" | grep -qF "the documented retry policy at validation-phase.md:142" \
  || fail "Test 11a: Code-Sec finding body content lost after attribution stripping"
echo "$deep_body" | grep -qF "the new helper at scripts/foo.sh:42" \
  || fail "Test 11a: Code-Arch finding body content lost after attribution stripping"

# (b) Anchored trailing suffix " (Code-Sec)" / " — Code-Arch" stripped from last line.
echo "$deep_body" | grep -qE '\(Code-Sec\)' && \
  fail "Test 11b: trailing ' (Code-Sec)' attribution suffix was NOT stripped from defense body"
echo "$deep_body" | grep -qE '— Code-Arch[[:space:]]*$' && \
  fail "Test 11b: trailing ' — Code-Arch' attribution suffix was NOT stripped from defense body"

# (c) Mid-content "Code-Sec" / "Code-Arch" tokens must be preserved.
echo "$deep_body" | grep -qF "Code-Sec misread the contract" \
  || fail "Test 11c: mid-content 'Code-Sec misread the contract' was incorrectly stripped"
echo "$deep_body" | grep -qF "The Code-Arch checklist anticipates this exception" \
  || fail "Test 11c: mid-content 'The Code-Arch checklist anticipates this exception' was incorrectly stripped"

pass "Test 11: deep-mode Code-Sec/Code-Arch — anchored prefix/suffix stripped, mid-content preserved"

# --- Test 12: mixed complete + incomplete blocks → fail-closed exit 2 ---------

# Regression guard for issue #462. The builder MUST fail closed when ANY
# REJECTED_FINDING_<N> block is missing one of Reviewer/Finding/Rejection
# rationale, not soft-drop the incomplete block. A degraded `/research` run
# that captured 2 complete records plus 1 incomplete record must NOT produce
# a partial 2-decision ballot — that would create the DECISION_k → REJECTED_FINDING_<N>
# mapping inconsistency that this PR closes.

mixed_input="$WORK_DIR/mixed-rej.md"
mixed_output="$WORK_DIR/mixed-ballot.txt"
mixed_stderr="$WORK_DIR/mixed-stderr.txt"

cat > "$mixed_input" <<'EOF'
### REJECTED_FINDING_1
- **Reviewer**: Cursor
- **Finding**: Cursor: alpha finding text body that is reasonably long.
- **Rejection rationale**: First rationale paragraph that explains why the alpha finding was rejected, providing enough detail to serve as a defense.

### REJECTED_FINDING_2
- **Reviewer**: Code
- **Finding**: Code: bravo finding text body of approximately the same length.

### REJECTED_FINDING_3
- **Reviewer**: Codex
- **Finding**: Codex: charlie finding text body matching the others in length.
- **Rejection rationale**: Third rationale paragraph for the charlie finding rejection with detailed prose about why the orchestrator's position holds.
EOF

set +e
"$BUILDER" --input "$mixed_input" --output "$mixed_output" 2> "$mixed_stderr"
mixed_rc=$?
set -e

[[ "$mixed_rc" -eq 2 ]] \
  || fail "Test 12: expected exit code 2 on incomplete block, got $mixed_rc"

grep -qE '^FAILED=true$' "$mixed_stderr" \
  || fail "Test 12: FAILED=true line missing from stderr (got: $(cat "$mixed_stderr"))"

grep -qE '^ERROR=REJECTED_FINDING_2 is incomplete' "$mixed_stderr" \
  || fail "Test 12: expected ERROR=REJECTED_FINDING_2 is incomplete... in stderr (got: $(cat "$mixed_stderr"))"

# A partial ballot must NOT have been produced. The trap-on-EXIT cleans
# WORK_DIR but the builder may have written to $mixed_output before failing —
# regardless, a successful BUILT=true line must NOT appear on stdout.
# (We captured stdout to /dev/null above by not redirecting it; rerun with
# stdout capture to verify.)
mixed_stdout="$WORK_DIR/mixed-stdout.txt"
set +e
"$BUILDER" --input "$mixed_input" --output "$mixed_output" \
  > "$mixed_stdout" 2>/dev/null
set -e
if grep -qE '^BUILT=true$' "$mixed_stdout"; then
  fail "Test 12: BUILT=true leaked to stdout on incomplete-block input (regression)"
fi

pass "Test 12: mixed complete + incomplete blocks → fail-closed exit 2 with REJECTED_FINDING_<N> is incomplete sentinel"

# --- Test 13: lone incomplete block → fail-closed exit 2 ---------------------

lone_input="$WORK_DIR/lone-incomplete-rej.md"
lone_output="$WORK_DIR/lone-incomplete-ballot.txt"
lone_stderr="$WORK_DIR/lone-incomplete-stderr.txt"

cat > "$lone_input" <<'EOF'
### REJECTED_FINDING_1
- **Reviewer**: Code
- **Finding**: This block is missing the Rejection rationale field entirely.
EOF

set +e
"$BUILDER" --input "$lone_input" --output "$lone_output" 2> "$lone_stderr"
lone_rc=$?
set -e

[[ "$lone_rc" -eq 2 ]] \
  || fail "Test 13: expected exit code 2 on lone incomplete block, got $lone_rc"

grep -qE '^FAILED=true$' "$lone_stderr" \
  || fail "Test 13: FAILED=true line missing from stderr"

grep -qE '^ERROR=REJECTED_FINDING_1 is incomplete' "$lone_stderr" \
  || fail "Test 13: expected ERROR=REJECTED_FINDING_1 is incomplete... in stderr (got: $(cat "$lone_stderr"))"

pass "Test 13: lone incomplete block → fail-closed exit 2"

# --- Test 14: whitespace-only field body → fail-closed exit 2 ----------------

# Regression guard for issue #462 FINDING_7. flush_record() must trim
# Finding and Rejection rationale before the completeness check, so a
# whitespace-only body (which would otherwise survive the `== ""` check
# because it arrives via raw substr() with continuation-line concatenation)
# is treated as missing.

ws_input="$WORK_DIR/ws-only-rej.md"
ws_output="$WORK_DIR/ws-only-ballot.txt"
ws_stderr="$WORK_DIR/ws-only-stderr.txt"

# Note: the leading character after "Finding**: " is intentionally a space
# only; the bullet-line raw substr captures " " (one space). With the trim,
# this normalizes to "" and the completeness check fires.
cat > "$ws_input" <<'EOF'
### REJECTED_FINDING_1
- **Reviewer**: Code
- **Finding**:
- **Rejection rationale**: Otherwise complete rationale paragraph that meets the prose-length bar for a defense in adjudication.
EOF

set +e
"$BUILDER" --input "$ws_input" --output "$ws_output" 2> "$ws_stderr"
ws_rc=$?
set -e

[[ "$ws_rc" -eq 2 ]] \
  || fail "Test 14: expected exit code 2 on whitespace-only Finding body, got $ws_rc"

grep -qE '^ERROR=REJECTED_FINDING_1 is incomplete' "$ws_stderr" \
  || fail "Test 14: expected ERROR=REJECTED_FINDING_1 is incomplete... in stderr (got: $(cat "$ws_stderr"))"

pass "Test 14: whitespace-only Finding body → fail-closed exit 2 (FINDING_7 trim verified)"

# --- Test 15: coordinator surfaces incomplete-input: ERROR prefix ------------

# Regression guard for issue #462 dialectic resolution DECISION_2 + FINDING_4.
# The coordinator (run-research-adjudication.sh) MUST detect the builder's
# incomplete-block sentinel ERROR and prepend `incomplete-input: ` so
# operators can distinguish malformed input from generic builder breakage at
# the coordinator seam. We invoke the coordinator with the same fixture
# Test 12 used (lone incomplete block) and assert the prefixed ERROR line.

COORDINATOR="$REPO_ROOT/scripts/run-research-adjudication.sh"
[[ -x "$COORDINATOR" ]] || fail "Test 15: coordinator script missing or not executable: $COORDINATOR"

coord_tmpdir="$WORK_DIR/coord-tmpdir"
mkdir -p "$coord_tmpdir"
coord_stdout="$WORK_DIR/coord-stdout.txt"

set +e
"$COORDINATOR" --rejected-findings "$lone_input" --tmpdir "$coord_tmpdir" \
  > "$coord_stdout" 2>&1
coord_rc=$?
set -e

[[ "$coord_rc" -eq 2 ]] \
  || fail "Test 15: expected coordinator exit 2 on incomplete-input, got $coord_rc"

grep -qE '^RAN=false$' "$coord_stdout" \
  || fail "Test 15: expected RAN=false from coordinator (got: $(cat "$coord_stdout"))"
grep -qE '^FAILED=true$' "$coord_stdout" \
  || fail "Test 15: expected FAILED=true from coordinator"
grep -qE '^ERROR=incomplete-input: REJECTED_FINDING_1 is incomplete' "$coord_stdout" \
  || fail "Test 15: expected ERROR=incomplete-input: REJECTED_FINDING_1 is incomplete... from coordinator (got: $(cat "$coord_stdout"))"

# Coordinator must NEVER report RAN=true on malformed input.
if grep -qE '^RAN=true$' "$coord_stdout"; then
  fail "Test 15: coordinator surfaced RAN=true on malformed input (regression)"
fi

pass "Test 15: coordinator surfaces 'incomplete-input:' ERROR prefix on malformed REJECTED_FINDING block"

# --- All tests passed --------------------------------------------------------

echo ""
echo "All test-research-adjudication.sh assertions passed."
exit 0
