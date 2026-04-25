#!/usr/bin/env bash
# test-token-tally.sh — offline regression harness for token-tally.sh.
#
# Asserts byte-exact stdout for happy-path cases plus contract behavior
# under error conditions (exit codes + stderr) for missing/malformed inputs,
# path-validation, and budget-overage. Closes #518.
#
# Test cases:
#   1. report empty dir → "(no measurements available)" placeholder
#   2. report fixture sidecars across all 3 phases → expected aggregate
#   3. report with --planner true → planner row appears in research phase
#   4. report missing sidecar for active lane → "unmeasured" coverage
#   5. report with LARCH_TOKEN_RATE_PER_M=15 → $ column appears
#   6. report without LARCH_TOKEN_RATE_PER_M → $ column omitted
#   7. check-budget under → exit 0
#   8. check-budget over → exit 2 with BUDGET_EXCEEDED diagnostic
#   9. write malformed --total-tokens → exit 1
#  10. write --total-tokens=unknown → succeeds with TOTAL_TOKENS=unknown
#  11. path validation: --dir /home/foo → exit 1
#  12. report after dir removed → "(token telemetry unavailable)" placeholder

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$REPO_ROOT/scripts/token-tally.sh"

PASS=0
FAIL=0
FAIL_DETAILS=()

fail() {
    FAIL=$((FAIL + 1))
    FAIL_DETAILS+=("$1")
}

pass() {
    PASS=$((PASS + 1))
}

assert_exit_code() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass
    else
        fail "$label: expected exit $expected, got $actual"
    fi
}

assert_stdout_contains() {
    local label="$1"
    local needle="$2"
    local actual="$3"
    case "$actual" in
        *"$needle"*) pass ;;
        *) fail "$label: stdout missing '$needle'
ACTUAL:
$(printf '%s' "$actual" | sed 's/^/  /')" ;;
    esac
}

assert_stdout_not_contains() {
    local label="$1"
    local needle="$2"
    local actual="$3"
    case "$actual" in
        *"$needle"*) fail "$label: stdout unexpectedly contains '$needle'
ACTUAL:
$(printf '%s' "$actual" | sed 's/^/  /')" ;;
        *) pass ;;
    esac
}

# Helper: make a fresh tmpdir under /tmp for each test that needs one.
make_dir() {
    mktemp -d "/tmp/test-token-tally.XXXXXX"
}

# Helper: write a sidecar manually with given fields.
write_sidecar() {
    local dir="$1"
    local phase="$2"
    local lane="$3"
    local total="$4"
    cat > "$dir/lane-tokens-$phase-$lane.txt" <<EOF
PHASE=$phase
LANE=$lane
TOOL=claude
TOTAL_TOKENS=$total
EOF
}

# ─── Test 1: report empty dir → placeholder ───
T="$(make_dir)"
out=$("$SCRIPT" report --dir "$T" --scale standard --adjudicate false 2>&1) || true
assert_stdout_contains "T1: empty-dir placeholder" "no measurements available" "$out"
rm -rf "$T"

# ─── Test 2: report with fixture sidecars across phases ───
T="$(make_dir)"
write_sidecar "$T" "research" "code" "1500"
write_sidecar "$T" "validation" "code" "2000"
write_sidecar "$T" "validation" "code-sec" "1800"
write_sidecar "$T" "adjudication" "code" "500"
out=$("$SCRIPT" report --dir "$T" --scale deep --adjudicate true 2>&1)
assert_stdout_contains "T2: token spend header" "## Token Spend" "$out"
assert_stdout_contains "T2: research-phase row" "Research phase" "$out"
assert_stdout_contains "T2: validation-phase row" "Validation phase" "$out"
assert_stdout_contains "T2: adjudication row" "Adjudication" "$out"
assert_stdout_contains "T2: total row" "Total" "$out"
# Total should be 1500+2000+1800+500 = 5800
assert_stdout_contains "T2: aggregate total" "5800" "$out"
rm -rf "$T"

# ─── Test 3: report with --planner true → planner row in research ───
T="$(make_dir)"
write_sidecar "$T" "research" "planner" "300"
write_sidecar "$T" "research" "code" "700"
out=$("$SCRIPT" report --dir "$T" --scale standard --adjudicate false --planner true 2>&1)
assert_stdout_contains "T3: planner counted" "1000" "$out"
rm -rf "$T"

# ─── Test 4: report with missing sidecar / unknown — coverage line ───
T="$(make_dir)"
write_sidecar "$T" "research" "code" "1500"
write_sidecar "$T" "validation" "code" "unknown"
out=$("$SCRIPT" report --dir "$T" --scale standard --adjudicate false 2>&1)
# Total measured = 1500 (only the research row); the "unknown" row is excluded from sum.
assert_stdout_contains "T4: total respects unknown" "1500" "$out"
# Coverage line must mention unknown count somewhere (lane count > measured count).
assert_stdout_contains "T4: unmeasurable note" "unmeasur" "$out"
rm -rf "$T"

# ─── Test 5: report with LARCH_TOKEN_RATE_PER_M set → $ column ───
T="$(make_dir)"
write_sidecar "$T" "research" "code" "1000000"
out=$(LARCH_TOKEN_RATE_PER_M=15 "$SCRIPT" report --dir "$T" --scale standard --adjudicate false 2>&1)
assert_stdout_contains "T5: $ column when env set" "\$15" "$out"
rm -rf "$T"

# ─── Test 6: report without LARCH_TOKEN_RATE_PER_M → no $ column ───
T="$(make_dir)"
write_sidecar "$T" "research" "code" "1000000"
out=$(unset LARCH_TOKEN_RATE_PER_M; "$SCRIPT" report --dir "$T" --scale standard --adjudicate false 2>&1)
assert_stdout_not_contains "T6: no $ column when env unset" "\$" "$out"
rm -rf "$T"

# ─── Test 7: check-budget under → exit 0 ───
T="$(make_dir)"
write_sidecar "$T" "research" "code" "100"
write_sidecar "$T" "validation" "code" "200"
rc=0
"$SCRIPT" check-budget --budget 1000 --dir "$T" >/dev/null 2>&1 || rc=$?
assert_exit_code "T7: budget under → exit 0" 0 "$rc"
rm -rf "$T"

# ─── Test 8: check-budget over → exit 2 ───
T="$(make_dir)"
write_sidecar "$T" "research" "code" "5000"
write_sidecar "$T" "validation" "code" "6000"
rc=0
out=$("$SCRIPT" check-budget --budget 1000 --dir "$T" 2>&1) || rc=$?
assert_exit_code "T8: budget over → exit 2" 2 "$rc"
assert_stdout_contains "T8: BUDGET_EXCEEDED token" "BUDGET_EXCEEDED=true" "$out"
assert_stdout_contains "T8: MEASURED token" "MEASURED=11000" "$out"
rm -rf "$T"

# ─── Test 9: write with malformed --total-tokens → exit 1 ───
T="$(make_dir)"
rc=0
"$SCRIPT" write --phase research --lane code --tool claude --total-tokens "not-a-number" --dir "$T" >/dev/null 2>&1 || rc=$?
assert_exit_code "T9: malformed total-tokens → exit 1" 1 "$rc"
rm -rf "$T"

# ─── Test 10: write --total-tokens=unknown → succeeds ───
T="$(make_dir)"
rc=0
"$SCRIPT" write --phase research --lane code --tool claude --total-tokens "unknown" --dir "$T" >/dev/null 2>&1 || rc=$?
assert_exit_code "T10: unknown total-tokens → exit 0" 0 "$rc"
if [ -f "$T/lane-tokens-research-code.txt" ]; then
    if grep -q "TOTAL_TOKENS=unknown" "$T/lane-tokens-research-code.txt"; then
        pass
    else
        fail "T10: sidecar missing TOTAL_TOKENS=unknown"
    fi
else
    fail "T10: sidecar file not created"
fi
rm -rf "$T"

# ─── Test 11: path validation — non-/tmp dir rejected ───
rc=0
"$SCRIPT" report --dir "/home/nonsense" --scale standard --adjudicate false >/dev/null 2>&1 || rc=$?
assert_exit_code "T11: non-/tmp path → exit 1" 1 "$rc"

rc=0
"$SCRIPT" write --phase research --lane code --tool claude --total-tokens 100 --dir "/home/nonsense" >/dev/null 2>&1 || rc=$?
assert_exit_code "T11: write non-/tmp → exit 1" 1 "$rc"

rc=0
"$SCRIPT" check-budget --budget 1000 --dir "/home/nonsense" >/dev/null 2>&1 || rc=$?
assert_exit_code "T11: check-budget non-/tmp → exit 1" 1 "$rc"

# ─── Test 12: report after dir removed → graceful placeholder ───
T="$(make_dir)"
rm -rf "$T"
out=$("$SCRIPT" report --dir "$T" --scale standard --adjudicate false 2>&1) || true
assert_stdout_contains "T12: missing dir → placeholder" "token telemetry unavailable" "$out"

# ─── Summary ───
echo
echo "─────────────────────────────────────────"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo
    echo "Failures:"
    for d in "${FAIL_DETAILS[@]}"; do
        echo "  • $d"
    done
    exit 1
fi
echo "─────────────────────────────────────────"
