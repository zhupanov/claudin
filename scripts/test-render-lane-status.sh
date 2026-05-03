#!/usr/bin/env bash
# test-render-lane-status.sh — offline regression harness for render-lane-status.sh.
#
# Asserts byte-exact stdout for happy-path cases and the contract's behavior
# under error conditions for the 4-research-angle + 3-validation-reviewer
# fixed shape.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$REPO_ROOT/scripts/render-lane-status.sh"

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

assert_stdout_equals() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass
    else
        fail "$label
  EXPECTED:
$(printf '%s' "$expected" | sed 's/^/    /')
  ACTUAL:
$(printf '%s' "$actual" | sed 's/^/    /')"
    fi
}

assert_stderr_contains() {
    local label="$1"
    local needle="$2"
    local actual="$3"
    case "$actual" in
        *"$needle"*) pass ;;
        *) fail "$label
  EXPECTED stderr to contain: $needle
  ACTUAL stderr:
$(printf '%s' "$actual" | sed 's/^/    /')" ;;
    esac
}

assert_exit_equals() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass
    else
        fail "$label
  EXPECTED exit: $expected
  ACTUAL exit:   $actual"
    fi
}

TMPDIR_LOCAL="$(mktemp -d "/tmp/test-render-lane-status-XXXXXX")"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

run_render() {
    local input="$1"
    local out_file err_file rc
    out_file="$TMPDIR_LOCAL/out"
    err_file="$TMPDIR_LOCAL/err"
    rc=0
    "$SCRIPT" --input "$input" >"$out_file" 2>"$err_file" || rc=$?
    STDOUT="$(cat "$out_file")"
    STDERR="$(cat "$err_file")"
    EXIT="$rc"
}

# ---------- Fixture 1 — all-ok happy path ----------
cat > "$TMPDIR_LOCAL/f1.txt" <<'EOF'
RESEARCH_ARCH_STATUS=ok
RESEARCH_ARCH_REASON=
RESEARCH_EDGE_STATUS=ok
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=ok
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=ok
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=ok
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f1.txt"
assert_exit_equals "F1.exit" "0" "$EXIT"
assert_stdout_equals "F1.stdout" \
"RESEARCH_ARCH_HEADER=Architecture: ✅
RESEARCH_EDGE_HEADER=Edge cases: ✅
RESEARCH_EXT_HEADER=External comparisons: ✅
RESEARCH_SEC_HEADER=Security: ✅
VALIDATION_CODE_HEADER=Code: ✅
VALIDATION_CURSOR_HEADER=Cursor: ✅
VALIDATION_CODEX_HEADER=Codex: ✅" "$STDOUT"

# ---------- Fixture 2 — all 4 research angles fell back to Claude ----------
cat > "$TMPDIR_LOCAL/f2.txt" <<'EOF'
RESEARCH_ARCH_STATUS=fallback_binary_missing
RESEARCH_ARCH_REASON=
RESEARCH_EDGE_STATUS=fallback_binary_missing
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=fallback_binary_missing
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=fallback_binary_missing
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=ok
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f2.txt"
assert_exit_equals "F2.exit" "0" "$EXIT"
assert_stdout_equals "F2.stdout" \
"RESEARCH_ARCH_HEADER=Architecture: Claude-fallback (binary missing)
RESEARCH_EDGE_HEADER=Edge cases: Claude-fallback (binary missing)
RESEARCH_EXT_HEADER=External comparisons: Claude-fallback (binary missing)
RESEARCH_SEC_HEADER=Security: Claude-fallback (binary missing)
VALIDATION_CODE_HEADER=Code: ✅
VALIDATION_CURSOR_HEADER=Cursor: ✅
VALIDATION_CODEX_HEADER=Codex: ✅" "$STDOUT"

# ---------- Fixture 3 — mixed (one angle fell back; mixed validation) ----------
cat > "$TMPDIR_LOCAL/f3.txt" <<'EOF'
RESEARCH_ARCH_STATUS=ok
RESEARCH_ARCH_REASON=
RESEARCH_EDGE_STATUS=ok
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=fallback_runtime_timeout
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=ok
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=ok
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=fallback_binary_missing
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=fallback_binary_missing
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f3.txt"
assert_exit_equals "F3.exit" "0" "$EXIT"
assert_stdout_equals "F3.stdout" \
"RESEARCH_ARCH_HEADER=Architecture: ✅
RESEARCH_EDGE_HEADER=Edge cases: ✅
RESEARCH_EXT_HEADER=External comparisons: Claude-fallback (runtime timeout)
RESEARCH_SEC_HEADER=Security: ✅
VALIDATION_CODE_HEADER=Code: ✅
VALIDATION_CURSOR_HEADER=Cursor: Claude-fallback (binary missing)
VALIDATION_CODEX_HEADER=Codex: Claude-fallback (binary missing)" "$STDOUT"

# ---------- Fixture 4 — probe-failed with reason ----------
cat > "$TMPDIR_LOCAL/f4.txt" <<'EOF'
RESEARCH_ARCH_STATUS=fallback_probe_failed
RESEARCH_ARCH_REASON=connection refused on port 5050
RESEARCH_EDGE_STATUS=ok
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=ok
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=ok
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=ok
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=fallback_probe_failed
VALIDATION_CURSOR_REASON=connection refused on port 5050
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f4.txt"
assert_exit_equals "F4.exit" "0" "$EXIT"
assert_stdout_equals "F4.stdout" \
"RESEARCH_ARCH_HEADER=Architecture: Claude-fallback (probe failed: connection refused on port 5050)
RESEARCH_EDGE_HEADER=Edge cases: ✅
RESEARCH_EXT_HEADER=External comparisons: ✅
RESEARCH_SEC_HEADER=Security: ✅
VALIDATION_CODE_HEADER=Code: ✅
VALIDATION_CURSOR_HEADER=Cursor: Claude-fallback (probe failed: connection refused on port 5050)
VALIDATION_CODEX_HEADER=Codex: ✅" "$STDOUT"

# ---------- Fixture 5 — probe-failed without reason ----------
cat > "$TMPDIR_LOCAL/f5.txt" <<'EOF'
RESEARCH_ARCH_STATUS=fallback_probe_failed
RESEARCH_ARCH_REASON=
RESEARCH_EDGE_STATUS=ok
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=ok
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=ok
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=ok
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f5.txt"
assert_exit_equals "F5.exit" "0" "$EXIT"
assert_stdout_equals "F5.stdout" \
"RESEARCH_ARCH_HEADER=Architecture: Claude-fallback (probe failed)
RESEARCH_EDGE_HEADER=Edge cases: ✅
RESEARCH_EXT_HEADER=External comparisons: ✅
RESEARCH_SEC_HEADER=Security: ✅
VALIDATION_CODE_HEADER=Code: ✅
VALIDATION_CURSOR_HEADER=Cursor: ✅
VALIDATION_CODEX_HEADER=Codex: ✅" "$STDOUT"

# ---------- Fixture 6 — runtime-failed sanitization (= and | stripped, whitespace collapsed) ----------
{
    printf 'RESEARCH_ARCH_STATUS=ok\n'
    printf 'RESEARCH_ARCH_REASON=\n'
    printf 'RESEARCH_EDGE_STATUS=ok\n'
    printf 'RESEARCH_EDGE_REASON=\n'
    printf 'RESEARCH_EXT_STATUS=fallback_runtime_failed\n'
    printf 'RESEARCH_EXT_REASON=exit code 124  Process killed after exceeding timeout |||  with == many == bad chars\n'
    printf 'RESEARCH_SEC_STATUS=ok\n'
    printf 'RESEARCH_SEC_REASON=\n'
    printf 'VALIDATION_CODE_STATUS=ok\n'
    printf 'VALIDATION_CODE_REASON=\n'
    printf 'VALIDATION_CURSOR_STATUS=ok\n'
    printf 'VALIDATION_CURSOR_REASON=\n'
    printf 'VALIDATION_CODEX_STATUS=ok\n'
    printf 'VALIDATION_CODEX_REASON=\n'
} > "$TMPDIR_LOCAL/f6.txt"
run_render "$TMPDIR_LOCAL/f6.txt"
assert_exit_equals "F6.exit" "0" "$EXIT"
assert_stdout_equals "F6.stdout" \
"RESEARCH_ARCH_HEADER=Architecture: ✅
RESEARCH_EDGE_HEADER=Edge cases: ✅
RESEARCH_EXT_HEADER=External comparisons: Claude-fallback (runtime failed: exit code 124 Process killed after exceeding timeout with many bad chars)
RESEARCH_SEC_HEADER=Security: ✅
VALIDATION_CODE_HEADER=Code: ✅
VALIDATION_CURSOR_HEADER=Cursor: ✅
VALIDATION_CODEX_HEADER=Codex: ✅" "$STDOUT"

# ---------- Fixture 7 — unknown status token ----------
cat > "$TMPDIR_LOCAL/f7.txt" <<'EOF'
RESEARCH_ARCH_STATUS=ok
RESEARCH_ARCH_REASON=
RESEARCH_EDGE_STATUS=fallback-binary-missing
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=ok
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=ok
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=ok
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f7.txt"
assert_exit_equals "F7.exit" "0" "$EXIT"
assert_stdout_equals "F7.stdout" \
"RESEARCH_ARCH_HEADER=Architecture: ✅
RESEARCH_EDGE_HEADER=Edge cases: (unknown)
RESEARCH_EXT_HEADER=External comparisons: ✅
RESEARCH_SEC_HEADER=Security: ✅
VALIDATION_CODE_HEADER=Code: ✅
VALIDATION_CURSOR_HEADER=Cursor: ✅
VALIDATION_CODEX_HEADER=Codex: ✅" "$STDOUT"
assert_stderr_contains "F7.stderr" "unknown status token fallback-binary-missing" "$STDERR"

# ---------- Fixture 8 — missing input ----------
run_render "$TMPDIR_LOCAL/does-not-exist.txt"
assert_exit_equals "F8.exit" "2" "$EXIT"
assert_stderr_contains "F8.stderr" "render-lane-status: input file missing" "$STDERR"

# ---------- Fixture 9 — usage error: --input flag omitted ----------
EXIT=0
"$SCRIPT" >"$TMPDIR_LOCAL/out" 2>"$TMPDIR_LOCAL/err" || EXIT=$?
STDERR="$(cat "$TMPDIR_LOCAL/err")"
assert_exit_equals "F9.exit" "1" "$EXIT"
assert_stderr_contains "F9.stderr" "--input is required" "$STDERR"

# ---------- Fixture 10 — usage error: unknown flag ----------
EXIT=0
"$SCRIPT" --bogus >"$TMPDIR_LOCAL/out" 2>"$TMPDIR_LOCAL/err" || EXIT=$?
STDERR="$(cat "$TMPDIR_LOCAL/err")"
assert_exit_equals "F10.exit" "1" "$EXIT"
assert_stderr_contains "F10.stderr" "unknown flag: --bogus" "$STDERR"

# ---------- Summary ----------
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo "PASS: test-render-lane-status.sh — $TOTAL assertions passed across 10 fixture cases"
    exit 0
else
    echo "FAIL: test-render-lane-status.sh — $FAIL of $TOTAL assertions failed" >&2
    for d in "${FAIL_DETAILS[@]}"; do
        printf '%s\n' "$d" >&2
        echo "" >&2
    done
    exit 1
fi
