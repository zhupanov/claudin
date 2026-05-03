#!/usr/bin/env bash
# test-token-tally.sh — offline regression harness for token-tally.sh.
#
# Asserts byte-exact stdout for happy-path cases plus contract behavior
# under error conditions (exit codes + stderr) for missing/malformed inputs
# and path-validation.
#
# Test cases:
#   1. report empty dir → "(no measurements available)" placeholder
#   2. report fixture sidecars across research+validation → aggregate
#   3. report missing sidecar for active lane → "unmeasured" coverage
#   4. report with LARCH_TOKEN_RATE_PER_M=15 → $ column appears
#   5. report without LARCH_TOKEN_RATE_PER_M → $ column omitted
#   6. report with LARCH_TOKEN_RATE_PER_M=0 → no $ column
#   7. write malformed --total-tokens → exit 1
#   8. write --total-tokens=unknown → succeeds
#   9. path validation: --dir /home/foo → exit 1
#  10. report after dir removed → graceful placeholder
#  11. write --phase=adjudication → exit 1 (enum restricted)
#  12. report with no flags other than --dir → fixed shape
#  13. validate_dir rejects '..' segments
#  14. validate_dir rejects symlink-parent escape
#  15. check-budget subcommand removed → exit 1

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
out=$("$SCRIPT" report --dir "$T" 2>&1) || true
assert_stdout_contains "T1: empty-dir placeholder" "no measurements available" "$out"
rm -rf "$T"

# ─── Test 2: report with research+validation sidecars ───
T="$(make_dir)"
write_sidecar "$T" "research" "architecture" "1500"
write_sidecar "$T" "validation" "code" "2000"
write_sidecar "$T" "validation" "cursor" "1800"
out=$("$SCRIPT" report --dir "$T" 2>&1)
assert_stdout_contains "T2: token spend header" "## Token Spend" "$out"
assert_stdout_contains "T2: research-phase row" "Research phase" "$out"
assert_stdout_contains "T2: validation-phase row" "Validation phase" "$out"
assert_stdout_contains "T2: total row" "Total" "$out"
# Total should be 1500+2000+1800 = 5300
assert_stdout_contains "T2: aggregate total" "5300" "$out"
# No adjudication row in fixed-shape report
assert_stdout_not_contains "T2: no adjudication row" "Adjudication" "$out"
rm -rf "$T"

# ─── Test 3: report with unknown — coverage line ───
T="$(make_dir)"
write_sidecar "$T" "research" "architecture" "1500"
write_sidecar "$T" "validation" "code" "unknown"
out=$("$SCRIPT" report --dir "$T" 2>&1)
# Total measured = 1500 (only the research row); the "unknown" row is excluded from sum.
assert_stdout_contains "T3: total respects unknown" "1500" "$out"
# Coverage line must mention unknown count somewhere (lane count > measured count).
assert_stdout_contains "T3: unmeasurable note" "unmeasur" "$out"
rm -rf "$T"

# ─── Test 4: report with LARCH_TOKEN_RATE_PER_M set → $ column ───
T="$(make_dir)"
write_sidecar "$T" "research" "architecture" "1000000"
out=$(LARCH_TOKEN_RATE_PER_M=15 "$SCRIPT" report --dir "$T" 2>&1)
assert_stdout_contains "T4: \$ column when env set" "\$15" "$out"
rm -rf "$T"

# ─── Test 5: report without LARCH_TOKEN_RATE_PER_M → no $ column ───
T="$(make_dir)"
write_sidecar "$T" "research" "architecture" "1000000"
out=$(unset LARCH_TOKEN_RATE_PER_M; "$SCRIPT" report --dir "$T" 2>&1)
assert_stdout_not_contains "T5: no \$ column when env unset" "\$" "$out"
rm -rf "$T"

# ─── Test 6: LARCH_TOKEN_RATE_PER_M=0 → no $ column ───
T="$(make_dir)"
write_sidecar "$T" "research" "architecture" "1000000"
out=$(LARCH_TOKEN_RATE_PER_M=0 "$SCRIPT" report --dir "$T" 2>&1)
assert_stdout_not_contains "T6a: no \$ column when rate=0" "\$" "$out"
out=$(LARCH_TOKEN_RATE_PER_M=0.0 "$SCRIPT" report --dir "$T" 2>&1)
assert_stdout_not_contains "T6b: no \$ column when rate=0.0" "\$" "$out"
rm -rf "$T"

# ─── Test 7: write with malformed --total-tokens → exit 1 ───
T="$(make_dir)"
rc=0
"$SCRIPT" write --phase research --lane architecture --tool claude --total-tokens "not-a-number" --dir "$T" >/dev/null 2>&1 || rc=$?
assert_exit_code "T7: malformed total-tokens → exit 1" 1 "$rc"
rm -rf "$T"

# ─── Test 8: write --total-tokens=unknown → succeeds ───
T="$(make_dir)"
rc=0
"$SCRIPT" write --phase research --lane architecture --tool claude --total-tokens "unknown" --dir "$T" >/dev/null 2>&1 || rc=$?
assert_exit_code "T8: unknown total-tokens → exit 0" 0 "$rc"
if [ -f "$T/lane-tokens-research-architecture.txt" ]; then
    if grep -q "TOTAL_TOKENS=unknown" "$T/lane-tokens-research-architecture.txt"; then
        pass
    else
        fail "T8: sidecar missing TOTAL_TOKENS=unknown"
    fi
else
    fail "T8: sidecar file not created"
fi
rm -rf "$T"

# ─── Test 9: path validation — non-/tmp dir rejected ───
rc=0
"$SCRIPT" report --dir "/home/nonsense" >/dev/null 2>&1 || rc=$?
assert_exit_code "T9: report non-/tmp → exit 1" 1 "$rc"

rc=0
"$SCRIPT" write --phase research --lane code --tool claude --total-tokens 100 --dir "/home/nonsense" >/dev/null 2>&1 || rc=$?
assert_exit_code "T9: write non-/tmp → exit 1" 1 "$rc"

# ─── Test 10: report after dir removed → graceful placeholder ───
T="$(make_dir)"
rm -rf "$T"
out=$("$SCRIPT" report --dir "$T" 2>&1) || true
assert_stdout_contains "T10: missing dir → placeholder" "token telemetry unavailable" "$out"
assert_stdout_contains "T10: subtitle on missing-dir" "Claude tokens only" "$out"

# ─── Test 11: write --phase=adjudication → exit 1 (enum restricted) ───
T="$(make_dir)"
rc=0
"$SCRIPT" write --phase adjudication --lane code --tool claude --total-tokens 100 --dir "$T" >/dev/null 2>&1 || rc=$?
assert_exit_code "T11: --phase=adjudication rejected" 1 "$rc"
rm -rf "$T"

# ─── Test 12: report fixed shape — no scale/adjudicate flags ───
T="$(make_dir)"
write_sidecar "$T" "validation" "code" "1500"
out=$("$SCRIPT" report --dir "$T" 2>&1)
assert_stdout_contains "T12: research row rendered" "Research phase" "$out"
assert_stdout_contains "T12: explicit not-measured framing" "not measured" "$out"
rm -rf "$T"

# ─── Test 13: validate_dir rejects '..' segments ───
rc=0
"$SCRIPT" report --dir "/tmp/../etc" >/dev/null 2>&1 || rc=$?
assert_exit_code "T13: /tmp/../etc → exit 1" 1 "$rc"
rc=0
"$SCRIPT" write --phase research --lane code --tool claude --total-tokens 100 --dir "/tmp/../home" >/dev/null 2>&1 || rc=$?
assert_exit_code "T13: write /tmp/../home → exit 1" 1 "$rc"

# ─── Test 14: validate_dir rejects symlink-parent escape ───
t14_run() {
    local T_ESCAPE_DIR="" T_DIR T_DANGLING T_FILE rc
    T_DIR="$(make_dir)"
    # shellcheck disable=SC2317
    t14_cleanup() { rm -rf "$T_DIR" ${T_ESCAPE_DIR:+"$T_ESCAPE_DIR"}; }
    trap t14_cleanup RETURN
    T_ESCAPE_DIR=$(mktemp -d /var/tmp/test-token-tally-escape.XXXXXX 2>/dev/null) || \
        T_ESCAPE_DIR=$(mktemp -d "${HOME}/test-token-tally-escape.XXXXXX" 2>/dev/null) || {
            echo "WARNING: T14 skipped — could not create escape-target outside /tmp/" >&2
            return 0
        }

    ln -s "$T_ESCAPE_DIR" "$T_DIR/link"
    rc=0
    "$SCRIPT" write --phase research --lane code --tool claude --total-tokens 100 --dir "$T_DIR/link/escaped" >/dev/null 2>&1 || rc=$?
    assert_exit_code "T14a: write symlink-parent escape → exit 1" 1 "$rc"
    if [ -d "$T_ESCAPE_DIR/escaped" ]; then
        fail "T14a: write created escape directory at $T_ESCAPE_DIR/escaped"
    fi
    rc=0
    "$SCRIPT" report --dir "$T_DIR/link/escaped" >/dev/null 2>&1 || rc=$?
    assert_exit_code "T14a: report symlink-parent escape → exit 1" 1 "$rc"

    T_DANGLING="$T_DIR/dangling-link"
    ln -s "/tmp/test-token-tally-nonexistent-target.$$" "$T_DANGLING"
    rc=0
    "$SCRIPT" write --phase research --lane code --tool claude --total-tokens 100 --dir "$T_DANGLING/escaped" >/dev/null 2>&1 || rc=$?
    assert_exit_code "T14b: write dangling-symlink → exit 1" 1 "$rc"

    T_FILE="$T_DIR/regular-file"
    : > "$T_FILE"
    rc=0
    "$SCRIPT" write --phase research --lane code --tool claude --total-tokens 100 --dir "$T_FILE" >/dev/null 2>&1 || rc=$?
    assert_exit_code "T14c: write regular-file ancestor → exit 1" 1 "$rc"
}
t14_run

# ─── Test 15: check-budget subcommand removed → exit 1 ───
rc=0
"$SCRIPT" check-budget --budget 1000 --dir "/tmp" >/dev/null 2>&1 || rc=$?
assert_exit_code "T15: check-budget subcommand removed" 1 "$rc"

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
