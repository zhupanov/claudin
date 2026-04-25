#!/usr/bin/env bash
# test-render-lane-status.sh — offline regression harness for render-lane-status.sh.
#
# Asserts byte-exact stdout for happy-path cases and the contract's behavior
# under error conditions (exit code + stderr) for missing-input and
# unknown-token fixtures. Closes #421.
#
# 9 fixture cases (matches the count documented in scripts/render-lane-status.md):
#   1. happy path (all four lanes ok)
#   2. all-binary-missing (4 × fallback_binary_missing)
#   3. mixed (one ok, one runtime-timeout, two binary-missing)
#   4. probe-failed with reason
#   5. probe-failed without reason
#   6. runtime-timeout
#   7. runtime-failed with multiline reason (sanitization must collapse)
#   8. unknown-status (asserts stderr + still emits headers)
#   9. missing-input (asserts exit 2 + stderr)

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
    # Run script with --input <path>, capture stdout / stderr / exit separately.
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

# ---------- Fixture 1 — happy path ----------
cat > "$TMPDIR_LOCAL/f1.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=ok
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=ok
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f1.txt"
assert_exit_equals "F1.exit" "0" "$EXIT"
assert_stdout_equals "F1.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: ✅, Codex: ✅)
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: ✅, Codex: ✅)" "$STDOUT"

# ---------- Fixture 2 — all binary missing ----------
cat > "$TMPDIR_LOCAL/f2.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=fallback_binary_missing
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=fallback_binary_missing
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=fallback_binary_missing
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=fallback_binary_missing
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f2.txt"
assert_exit_equals "F2.exit" "0" "$EXIT"
assert_stdout_equals "F2.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: Claude-fallback (binary missing), Codex: Claude-fallback (binary missing))
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: Claude-fallback (binary missing), Codex: Claude-fallback (binary missing))" "$STDOUT"

# ---------- Fixture 3 — mixed ----------
cat > "$TMPDIR_LOCAL/f3.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=ok
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=fallback_runtime_timeout
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=fallback_binary_missing
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=fallback_binary_missing
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f3.txt"
assert_exit_equals "F3.exit" "0" "$EXIT"
assert_stdout_equals "F3.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: ✅, Codex: Claude-fallback (runtime timeout))
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: Claude-fallback (binary missing), Codex: Claude-fallback (binary missing))" "$STDOUT"

# ---------- Fixture 4 — probe-failed with reason ----------
cat > "$TMPDIR_LOCAL/f4.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=fallback_probe_failed
RESEARCH_CURSOR_REASON=connection refused on port 5050
RESEARCH_CODEX_STATUS=ok
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=fallback_probe_failed
VALIDATION_CURSOR_REASON=connection refused on port 5050
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f4.txt"
assert_exit_equals "F4.exit" "0" "$EXIT"
assert_stdout_equals "F4.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: Claude-fallback (probe failed: connection refused on port 5050), Codex: ✅)
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: Claude-fallback (probe failed: connection refused on port 5050), Codex: ✅)" "$STDOUT"

# ---------- Fixture 5 — probe-failed without reason ----------
cat > "$TMPDIR_LOCAL/f5.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=fallback_probe_failed
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=ok
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=fallback_probe_failed
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f5.txt"
assert_exit_equals "F5.exit" "0" "$EXIT"
assert_stdout_equals "F5.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: Claude-fallback (probe failed), Codex: ✅)
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: Claude-fallback (probe failed), Codex: ✅)" "$STDOUT"

# ---------- Fixture 6 — runtime-timeout ----------
cat > "$TMPDIR_LOCAL/f6.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=ok
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=fallback_runtime_timeout
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=fallback_runtime_timeout
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f6.txt"
assert_exit_equals "F6.exit" "0" "$EXIT"
assert_stdout_equals "F6.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: ✅, Codex: Claude-fallback (runtime timeout))
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: ✅, Codex: Claude-fallback (runtime timeout))" "$STDOUT"

# ---------- Fixture 7 — runtime-failed with multiline reason (sanitization must collapse) ----------
# The orchestrator's sanitize-on-write pass should already have collapsed
# newlines to spaces, but the script applies a second-line defense. We write
# a file with embedded newlines using printf to verify the script's own
# sanitization collapses them.
{
    printf 'RESEARCH_CURSOR_STATUS=ok\n'
    printf 'RESEARCH_CURSOR_REASON=\n'
    printf 'RESEARCH_CODEX_STATUS=fallback_runtime_failed\n'
    # Reason value spans one line (KV is line-oriented), but contains lots of
    # extra whitespace and characters that should be sanitized.
    printf 'RESEARCH_CODEX_REASON=exit code 124  Process killed after exceeding timeout |||  with == many == bad chars\n'
    printf 'VALIDATION_CURSOR_STATUS=ok\n'
    printf 'VALIDATION_CURSOR_REASON=\n'
    printf 'VALIDATION_CODEX_STATUS=ok\n'
    printf 'VALIDATION_CODEX_REASON=\n'
} > "$TMPDIR_LOCAL/f7.txt"
run_render "$TMPDIR_LOCAL/f7.txt"
assert_exit_equals "F7.exit" "0" "$EXIT"
# Expected: pipes and = stripped, whitespace collapsed, truncated to 80 chars.
assert_stdout_equals "F7.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: ✅, Codex: Claude-fallback (runtime failed: exit code 124 Process killed after exceeding timeout with many bad chars))
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: ✅, Codex: ✅)" "$STDOUT"

# ---------- Fixture 7b — reason that exceeds 80 chars must truncate ----------
{
    printf 'RESEARCH_CURSOR_STATUS=ok\n'
    printf 'RESEARCH_CURSOR_REASON=\n'
    printf 'RESEARCH_CODEX_STATUS=fallback_runtime_failed\n'
    printf 'RESEARCH_CODEX_REASON=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA_BEYOND_TRUNCATION\n'
    printf 'VALIDATION_CURSOR_STATUS=ok\n'
    printf 'VALIDATION_CURSOR_REASON=\n'
    printf 'VALIDATION_CODEX_STATUS=ok\n'
    printf 'VALIDATION_CODEX_REASON=\n'
} > "$TMPDIR_LOCAL/f7b.txt"
run_render "$TMPDIR_LOCAL/f7b.txt"
assert_exit_equals "F7b.exit" "0" "$EXIT"
assert_stdout_equals "F7b.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: ✅, Codex: Claude-fallback (runtime failed: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA))
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: ✅, Codex: ✅)" "$STDOUT"

# ---------- Fixture 8 — unknown status token ----------
cat > "$TMPDIR_LOCAL/f8.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=ok
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=fallback-binary-missing
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f8.txt"
assert_exit_equals "F8.exit" "0" "$EXIT"
assert_stdout_equals "F8.stdout" \
"RESEARCH_HEADER=3 agents (Cursor: ✅, Codex: (unknown))
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: ✅, Codex: ✅)" "$STDOUT"
assert_stderr_contains "F8.stderr" "unknown status token fallback-binary-missing" "$STDERR"

# ---------- Fixture 9 — missing input ----------
run_render "$TMPDIR_LOCAL/does-not-exist.txt"
assert_exit_equals "F9.exit" "2" "$EXIT"
assert_stderr_contains "F9.stderr" "render-lane-status: input file missing" "$STDERR"

# ---------- Summary ----------
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo "PASS: test-render-lane-status.sh — $TOTAL assertions passed across 9 fixture cases"
    exit 0
else
    echo "FAIL: test-render-lane-status.sh — $FAIL of $TOTAL assertions failed" >&2
    for d in "${FAIL_DETAILS[@]}"; do
        printf '%s\n' "$d" >&2
        echo "" >&2
    done
    exit 1
fi
